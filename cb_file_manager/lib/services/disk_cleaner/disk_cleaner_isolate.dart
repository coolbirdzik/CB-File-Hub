import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'cleaner_models.dart';

/// Resolved rule passed to [spawnScanWithResolvedRules] — `basePath` is
/// already absolute (the main isolate resolves environment variables).
class ResolvedRule {
  final String categoryId;
  final String basePath;
  final List<String>? includeGlobs;
  final List<String>? excludeGlobs;
  final Duration? minAge;
  final bool emptyOnly;
  final bool recursive;

  const ResolvedRule({
    required this.categoryId,
    required this.basePath,
    this.includeGlobs,
    this.excludeGlobs,
    this.minAge,
    this.emptyOnly = true,
    this.recursive = true,
  });

  int get minAgeMs => minAge?.inMilliseconds ?? 0;
}

/// Thin handle around an in-flight scan. The service owns one of these per
/// active scan and exposes cancellation + progress streaming.
class CleanerScanHandle {
  final Isolate _isolate;
  final ReceivePort _receivePort;
  final StreamController<ScanProgress> _progress =
      StreamController<ScanProgress>.broadcast();
  final Completer<ScanReport> _done = Completer<ScanReport>();
  final List<String> _drives;
  final DateTime _startedAt = DateTime.now();
  bool _cancelled = false;

  CleanerScanHandle._({
    required Isolate isolate,
    required ReceivePort receivePort,
    required List<String> drives,
  })  : _isolate = isolate,
        _receivePort = receivePort,
        _drives = drives;

  Stream<ScanProgress> get progress => _progress.stream;
  Future<ScanReport> get future => _done.future;
  bool get isCancelled => _cancelled;
  List<String> get drivesScanned => List.unmodifiable(_drives);

  /// Cancels the scan. Subscribers receive an empty [ScanReport].
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    try {
      _isolate.kill(priority: Isolate.immediate);
    } catch (_) {}
    _receivePort.close();
    if (!_progress.isClosed) _progress.close();
    if (!_done.isCompleted) {
      _done.complete(ScanReport(
        drivesScanned: _drives,
        itemsByCategory: const {},
        warnings: const ['cancelled'],
        scannedAt: _startedAt,
      ));
    }
  }
}

/// Spawns the scan worker isolate.
///
/// [drivesScanned] is informational — junk categories use per-user
/// environment paths, but the report records which drives the user asked
/// about.
Future<CleanerScanHandle> spawnScanWithResolvedRules({
  required List<String> drivesScanned,
  required List<ResolvedRule> rules,
}) async {
  final receivePort = ReceivePort();
  final args = _SpawnArgs(
    sendPort: receivePort.sendPort,
    rules: rules,
  );

  final isolate = await Isolate.spawn(_scanWorker, args);
  final handle = CleanerScanHandle._(
    isolate: isolate,
    receivePort: receivePort,
    drives: drivesScanned,
  );

  receivePort.listen((dynamic msg) {
    if (handle._cancelled) return;
    if (msg is _ProgressMsg) {
      if (!handle._progress.isClosed) {
        handle._progress.add(ScanProgress(
          currentPath: msg.currentPath,
          itemsFound: msg.itemsFound,
          bytesFound: msg.bytesFound,
          categoryId: msg.categoryId,
        ));
      }
    } else if (msg is _DoneMsg) {
      receivePort.close();
      if (!handle._progress.isClosed) handle._progress.close();
      if (!handle._done.isCompleted) {
        handle._done.complete(ScanReport(
          drivesScanned: drivesScanned,
          itemsByCategory: msg.itemsByCategory,
          warnings: msg.warnings,
          scannedAt: handle._startedAt,
        ));
      }
    }
  });

  return handle;
}

// ---------------------------------------------------------------------------
// Worker isolate entry — top-level so it can be passed to Isolate.spawn.
// ---------------------------------------------------------------------------

void _scanWorker(_SpawnArgs args) async {
  final sendPort = args.sendPort;
  final results = <String, List<JunkItem>>{};
  final warnings = <String>[];

  int totalItems = 0;
  int totalBytes = 0;
  DateTime lastFlush = DateTime.now();
  String currentCategory = '';

  void maybeFlush(String path) {
    final now = DateTime.now();
    if (now.difference(lastFlush).inMilliseconds >= 100) {
      lastFlush = now;
      sendPort.send(_ProgressMsg(
        currentPath: path,
        itemsFound: totalItems,
        bytesFound: totalBytes,
        categoryId: currentCategory,
      ));
    }
  }

  for (final rule in args.rules) {
    currentCategory = rule.categoryId;
    final base = rule.basePath;
    if (base.isEmpty) continue;

    final dir = Directory(base);
    final exists = await _exists(dir);
    if (!exists) continue;

    // Permission probe — touch the directory to trigger any access denial.
    try {
      await dir
          .list(followLinks: false)
          .first
          .timeout(const Duration(milliseconds: 800), onTimeout: () {
        throw const FileSystemException('Permission probe timed out');
      });
    } on FileSystemException catch (e) {
      warnings.add('${rule.categoryId}: ${e.message} (${rule.basePath})');
      continue;
    } catch (_) {
      // Empty directory — no permission issue. Proceed.
    }

    final includePatterns = rule.includeGlobs?.map(_globToRegex).toList();
    final excludePatterns = rule.excludeGlobs?.map(_globToRegex).toList();

    try {
      await for (final entity in dir
          .list(recursive: rule.recursive, followLinks: false)
          .handleError((Object e, StackTrace st) {})) {
        if (entity is! File) continue;

        final fileName = _basename(entity.path);
        if (includePatterns != null &&
            !includePatterns.any((p) => p.hasMatch(fileName))) {
          continue;
        }
        if (excludePatterns != null &&
            excludePatterns.any((p) => p.hasMatch(fileName))) {
          continue;
        }

        FileStat stat;
        try {
          stat = await entity.stat();
        } catch (_) {
          continue;
        }

        if (rule.minAgeMs > 0) {
          final ageMs =
              DateTime.now().difference(stat.modified).inMilliseconds;
          if (ageMs < rule.minAgeMs) continue;
        }

        final list = results.putIfAbsent(rule.categoryId, () => <JunkItem>[]);
        list.add(JunkItem(
          path: entity.path,
          sizeBytes: stat.size,
          lastModified: stat.modified,
          categoryId: rule.categoryId,
        ));
        totalItems++;
        totalBytes += stat.size;

        if (totalItems % 50 == 0) {
          maybeFlush(entity.path);
        }
      }
    } on FileSystemException catch (e) {
      warnings.add('${rule.categoryId}: ${e.message}');
    }
  }

  sendPort.send(_DoneMsg(
    itemsByCategory: results,
    warnings: warnings,
  ));
}

Future<bool> _exists(Directory dir) async {
  try {
    return await dir.exists();
  } catch (_) {
    return false;
  }
}

String _basename(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? path : path.substring(i + 1);
}

/// Translates a simple glob (`*`, `?`) to a case-insensitive [RegExp].
RegExp _globToRegex(String glob) {
  final buffer = StringBuffer('^');
  for (final ch in glob.split('')) {
    switch (ch) {
      case '*':
        buffer.write('.*');
        break;
      case '?':
        buffer.write('.');
        break;
      case '.':
      case '(':
      case ')':
      case '[':
      case ']':
      case '{':
      case '}':
      case r'\':
      case '+':
      case '|':
      case '^':
      case r'$':
        buffer.write(r'\');
        buffer.write(ch);
        break;
      default:
        buffer.write(ch);
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString(), caseSensitive: false);
}

// ---------------------------------------------------------------------------
// Private isolate message types.
// ---------------------------------------------------------------------------

class _SpawnArgs {
  final SendPort sendPort;
  final List<ResolvedRule> rules;
  const _SpawnArgs({required this.sendPort, required this.rules});
}

class _ProgressMsg {
  final String currentPath;
  final int itemsFound;
  final int bytesFound;
  final String categoryId;
  const _ProgressMsg({
    required this.currentPath,
    required this.itemsFound,
    required this.bytesFound,
    required this.categoryId,
  });
}

class _DoneMsg {
  final Map<String, List<JunkItem>> itemsByCategory;
  final List<String> warnings;
  const _DoneMsg({
    required this.itemsByCategory,
    required this.warnings,
  });
}
