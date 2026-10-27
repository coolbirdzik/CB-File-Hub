import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cb_native/cb_native.dart';

import 'cleaner_models.dart';
import 'cleaner_xcode_cache.dart';

const Duration _defaultRootOpenTimeout = Duration(milliseconds: 800);

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
  final CleanerRuleScope scope;

  const ResolvedRule({
    required this.categoryId,
    required this.basePath,
    this.includeGlobs,
    this.excludeGlobs,
    this.minAge,
    this.emptyOnly = true,
    this.recursive = true,
    this.scope = CleanerRuleScope.tree,
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
    required this._isolate,
    required this._receivePort,
    required this._drives,
  });

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
      _done.complete(
        ScanReport(
          drivesScanned: _drives,
          itemsByCategory: const {},
          warnings: const ['cancelled'],
          scannedAt: _startedAt,
        ),
      );
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

  /// Bounds opening the root enumeration. The stream is intentionally not
  /// timed after its first entry so a large recursive scan is not interrupted
  /// by a per-event timeout. Passing [Duration.zero] is a deterministic test
  /// seam that forces the first-entry timeout after directory existence is
  /// checked; production callers should use the default.
  Duration rootOpenTimeout = _defaultRootOpenTimeout,
  bool useNativeScanner = true,
}) async {
  final receivePort = ReceivePort();
  final args = _SpawnArgs(
    sendPort: receivePort.sendPort,
    rules: rules,
    rootOpenTimeout: rootOpenTimeout,
    useNativeScanner: useNativeScanner,
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
        handle._progress.add(
          ScanProgress(
            currentPath: msg.currentPath,
            itemsFound: msg.itemsFound,
            bytesFound: msg.bytesFound,
            categoryId: msg.categoryId,
            fraction: msg.fraction,
          ),
        );
      }
    } else if (msg is _DoneMsg) {
      receivePort.close();
      if (!handle._progress.isClosed) handle._progress.close();
      if (!handle._done.isCompleted) {
        handle._done.complete(
          ScanReport(
            drivesScanned: drivesScanned,
            itemsByCategory: msg.itemsByCategory,
            warnings: msg.warnings,
            scannedAt: handle._startedAt,
          ),
        );
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

  final compiledRules = <_CompiledRule>[];
  final expandedRules = <ResolvedRule>[];
  final summarized = <String>{};
  for (final rule in args.rules) {
    if (rule.scope == CleanerRuleScope.folderSummary) {
      if (!summarized.add('${rule.categoryId}:${_pathKey(rule.basePath)}')) {
        continue;
      }
      sendPort.send(
        _ProgressMsg(
          currentPath: rule.basePath,
          itemsFound: 0,
          bytesFound: 0,
          categoryId: rule.categoryId,
          fraction: null,
        ),
      );
      final item = await _folderSummary(
        rule,
        warnings,
        useNative: args.useNativeScanner,
      );
      if (item != null) {
        results.putIfAbsent(rule.categoryId, () => []).add(item);
      }
      continue;
    }
    if (rule.scope != CleanerRuleScope.xcodeBuildOutputs) {
      expandedRules.add(rule);
      continue;
    }
    for (final root in CleanerXcodeCache.discoverRoots(
      rule.basePath,
      warnings,
    )) {
      expandedRules.add(
        ResolvedRule(
          categoryId: rule.categoryId,
          basePath: root,
          includeGlobs: rule.includeGlobs,
          excludeGlobs: rule.excludeGlobs,
          minAge: rule.minAge,
          emptyOnly: rule.emptyOnly,
          recursive: rule.recursive,
        ),
      );
    }
  }
  for (var i = 0; i < expandedRules.length; i++) {
    final rule = expandedRules[i];
    if (rule.basePath.isEmpty) continue;
    compiledRules.add(_CompiledRule(rule, i));
  }
  // Keep the original rule contract: a rule only scans when its own base is
  // an existing directory. This is a cheap metadata check and avoids treating
  // a file-shaped base path as a matching file when it shares an ancestor with
  // another rule. Duration.zero is reserved as a test seam for the first
  // enumeration entry, so existence remains an ordinary immediate check.
  final existingRules = <_CompiledRule>[];
  for (final rule in compiledRules) {
    final check = await _checkDirectory(
      Directory(rule.source.basePath),
      timeout: args.rootOpenTimeout == Duration.zero
          ? null
          : args.rootOpenTimeout,
    );
    if (check == _DirectoryCheck.exists) {
      existingRules.add(rule);
    } else if (check == _DirectoryCheck.timedOut) {
      _addTimeoutWarnings(warnings, <_CompiledRule>[rule]);
    }
  }
  final groups = _buildScanGroups(existingRules);
  final seenByCategory = <String, Set<String>>{};

  int totalItems = results.values.fold(0, (sum, items) => sum + items.length);
  int totalBytes = results.values
      .expand((items) => items)
      .fold(0, (sum, item) => sum + item.sizeBytes);
  DateTime lastFlush = DateTime.now();
  String currentCategory = '';
  final progress = JunkScanFraction(groups.map((group) => group.scanPath));

  void maybeFlush(String path, {bool force = false}) {
    final now = DateTime.now();
    if (force || now.difference(lastFlush).inMilliseconds >= 100) {
      lastFlush = now;
      sendPort.send(
        _ProgressMsg(
          currentPath: path,
          itemsFound: totalItems,
          bytesFound: totalBytes,
          categoryId: currentCategory,
          fraction: progress.at(path),
        ),
      );
    }
  }

  for (final (index, group) in groups.indexed) {
    progress.startGroup(index);
    maybeFlush(group.scanPath, force: true);
    final dir = Directory(group.scanPath);
    final check = await _checkDirectory(
      dir,
      timeout: args.rootOpenTimeout == Duration.zero
          ? null
          : args.rootOpenTimeout,
    );
    if (check == _DirectoryCheck.missing) continue;
    if (check == _DirectoryCheck.timedOut) {
      _addTimeoutWarnings(warnings, group.rules);
      continue;
    }

    // Rust walks the group when package:cb_native is built: no async stat
    // per file and no RegExp per name, with the same rules and results.
    // Duration.zero is the test seam for the Dart first-entry timeout below.
    if (args.useNativeScanner && args.rootOpenTimeout != Duration.zero) {
      final baseItems = totalItems;
      final baseBytes = totalBytes;
      final elapsed = Stopwatch()..start();
      var nativeTimedOut = false;
      final native = await NativeFs.junkScan(
        scanPath: group.scanPath,
        recursive: group.recursive,
        lowerCaseKeys: Platform.isWindows,
        rules: [
          for (final (index, rule) in group.rules.indexed)
            NativeJunkRule(
              index: index,
              baseKey: rule.baseKey,
              recursive: rule.source.recursive,
              includeGlobs: rule.source.includeGlobs,
              excludeGlobs: rule.source.excludeGlobs,
              // isAfter(cutoff) at millisecond precision.
              cutoffMs: rule.minAgeCutoff == null
                  ? null
                  : rule.minAgeCutoff!.microsecondsSinceEpoch ~/ 1000,
            ),
        ],
        tick: const Duration(milliseconds: 50),
        shouldContinue: () => !nativeTimedOut,
        onProgress: (progress) {
          final counters = progress.counters;
          // Like the Dart first-entry timeout: the root never opened.
          if (counters[2] == 0 && elapsed.elapsed > args.rootOpenTimeout) {
            nativeTimedOut = true;
            return;
          }
          totalItems = baseItems + counters[0];
          totalBytes = baseBytes + counters[1];
          if (counters[3] > 0) {
            currentCategory = group.rules[counters[3] - 1].source.categoryId;
          }
          maybeFlush(
            progress.currentPath.isEmpty
                ? group.scanPath
                : progress.currentPath,
          );
        },
      );
      if (nativeTimedOut) {
        _addTimeoutWarnings(warnings, group.rules);
        continue;
      }
      if (native != null) {
        totalItems = baseItems;
        totalBytes = baseBytes;
        for (final hit in native.hits) {
          final entityPath = _pathKey(hit.path);
          final modified = DateTime.fromMillisecondsSinceEpoch(hit.modifiedMs);
          for (final index in hit.ruleIndices) {
            final categoryId = group.rules[index].source.categoryId;
            if (categoryId == CleanerXcodeCache.categoryId &&
                !CleanerXcodeCache.isGeneratedFile(hit.path)) {
              continue;
            }
            final seen = seenByCategory.putIfAbsent(
              categoryId,
              () => <String>{},
            );
            if (!seen.add(entityPath)) continue;
            currentCategory = categoryId;
            results
                .putIfAbsent(categoryId, () => <JunkItem>[])
                .add(
                  JunkItem(
                    path: hit.path,
                    sizeBytes: hit.size,
                    lastModified: modified,
                    categoryId: categoryId,
                  ),
                );
            totalItems++;
            totalBytes += hit.size;
          }
        }
        final error = native.error;
        if (error != null) {
          for (final rule in group.rules) {
            warnings.add(
              '${rule.source.categoryId}: $error (${rule.source.basePath})',
            );
          }
        }
        continue;
      }
    }

    Object? streamError;
    final matchingRules = <_CompiledRule>[];
    final iterator = StreamIterator<FileSystemEntity>(
      dir.list(recursive: group.recursive, followLinks: false).handleError((
        Object e,
        StackTrace st,
      ) {
        streamError ??= e;
      }),
    );
    var timedOut = false;
    try {
      final hasFirstEntry = args.rootOpenTimeout == Duration.zero
          ? false
          : await iterator.moveNext().timeout(
              args.rootOpenTimeout,
              onTimeout: () {
                timedOut = true;
                return false;
              },
            );
      if (args.rootOpenTimeout == Duration.zero) {
        timedOut = true;
      }
      if (timedOut) {
        await _cancelIterator(iterator, args.rootOpenTimeout);
      } else if (hasFirstEntry) {
        do {
          final entity = iterator.current;
          if (entity is! File) continue;

          final entityPath = _pathKey(entity.path);
          final fileName = _basename(entity.path);
          matchingRules.clear();
          for (final candidate in group.rules) {
            if (candidate.source.categoryId == CleanerXcodeCache.categoryId &&
                !CleanerXcodeCache.isGeneratedFile(entity.path)) {
              continue;
            }
            if (_matchesRule(candidate, entityPath, fileName)) {
              matchingRules.add(candidate);
            }
          }
          if (matchingRules.isEmpty) continue;

          late final FileStat stat;
          try {
            stat = await entity.stat();
          } catch (_) {
            continue;
          }

          for (final rule in matchingRules) {
            final cutoff = rule.minAgeCutoff;
            if (cutoff != null && stat.modified.isAfter(cutoff)) continue;

            final seen = seenByCategory.putIfAbsent(
              rule.source.categoryId,
              () => <String>{},
            );
            if (!seen.add(entityPath)) continue;

            currentCategory = rule.source.categoryId;
            final list = results.putIfAbsent(
              rule.source.categoryId,
              () => <JunkItem>[],
            );
            list.add(
              JunkItem(
                path: entity.path,
                sizeBytes: stat.size,
                lastModified: stat.modified,
                categoryId: rule.source.categoryId,
              ),
            );
            totalItems++;
            totalBytes += stat.size;

            if (totalItems % 50 == 0) {
              maybeFlush(entity.path);
            }
          }
        } while (await iterator.moveNext());
      }
    } on FileSystemException catch (e) {
      streamError ??= e;
    }

    if (timedOut) {
      _addTimeoutWarnings(warnings, group.rules);
    } else if (streamError != null) {
      for (final rule in group.rules) {
        final error = streamError!;
        final message = error is FileSystemException
            ? error.message
            : error.toString();
        warnings.add(
          '${rule.source.categoryId}: $message (${rule.source.basePath})',
        );
      }
    }
  }

  progress.finish();
  maybeFlush('', force: true);
  sendPort.send(_DoneMsg(itemsByCategory: results, warnings: warnings));
}

/// Metadata only, on the scan isolate; never reads file contents or follows links.
Future<JunkItem?> _folderSummary(
  ResolvedRule rule,
  List<String> warnings, {
  required bool useNative,
}) async {
  final root = rule.basePath;
  try {
    if (FileSystemEntity.typeSync(root, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    var bytes = 0;
    final native = useNative
        ? await NativeFs.directorySize(directories: [root])
        : null;
    if (native != null) {
      bytes = native.bytes;
      if (native.unreadable > 0) {
        warnings.add(
          '${rule.categoryId}: ${native.unreadable} unreadable entries; size is partial ($root)',
        );
      }
    } else {
      final pending = [root];
      while (pending.isNotEmpty) {
        final directory = pending.removeLast();
        try {
          for (final entry in Directory(
            directory,
          ).listSync(followLinks: false)) {
            if (entry is Directory) pending.add(entry.path);
            if (entry is File) {
              try {
                bytes += entry.lengthSync();
              } on FileSystemException catch (error) {
                warnings.add(
                  '${rule.categoryId}: ${error.message} (${entry.path})',
                );
              }
            }
          }
        } on FileSystemException catch (error) {
          warnings.add('${rule.categoryId}: ${error.message} ($directory)');
        }
      }
    }
    if (bytes <= 0) return null;
    return JunkItem(
      path: root,
      sizeBytes: bytes,
      categoryId: rule.categoryId,
      isContainerOnly: true,
      lastModified: Directory(root).statSync().modified,
    );
  } on FileSystemException catch (error) {
    warnings.add('${rule.categoryId}: ${error.message} ($root)');
    return null;
  }
}

enum _DirectoryCheck { exists, missing, timedOut }

class _RootEnumerationTimeout implements Exception {
  const _RootEnumerationTimeout();
}

Future<_DirectoryCheck> _checkDirectory(
  Directory dir, {
  Duration? timeout,
}) async {
  try {
    final exists = timeout == null
        ? await dir.exists()
        : await dir.exists().timeout(
            timeout,
            onTimeout: () => throw const _RootEnumerationTimeout(),
          );
    return exists ? _DirectoryCheck.exists : _DirectoryCheck.missing;
  } on _RootEnumerationTimeout {
    return _DirectoryCheck.timedOut;
  } catch (_) {
    return _DirectoryCheck.missing;
  }
}

Future<void> _cancelIterator(
  StreamIterator<FileSystemEntity> iterator,
  Duration timeout,
) async {
  try {
    await iterator.cancel().timeout(
      timeout == Duration.zero ? const Duration(milliseconds: 1) : timeout,
      onTimeout: () {},
    );
  } catch (_) {}
}

void _addTimeoutWarnings(List<String> warnings, Iterable<_CompiledRule> rules) {
  for (final rule in rules) {
    warnings.add(
      '${rule.source.categoryId}: Permission probe timed out '
      '(${rule.source.basePath})',
    );
  }
}

String _basename(String path) {
  final i = _lastSeparator(path);
  return i < 0 ? path : path.substring(i + 1);
}

int _lastSeparator(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf('\\');
  return slash > backslash ? slash : backslash;
}

/// Compiled rule state shared by all entries in one physical traversal.
///
/// A rule captures the age cutoff once. The old worker called [DateTime.now]
/// for every matching file, which made a large scan needlessly allocate and
/// could make files at the boundary disagree with one another.
class _CompiledRule {
  final ResolvedRule source;
  final int order;
  final String baseKey;
  final List<RegExp>? includePatterns;
  final List<RegExp>? excludePatterns;
  final DateTime? minAgeCutoff;

  _CompiledRule(this.source, this.order)
    : baseKey = _pathKey(source.basePath),
      includePatterns = source.includeGlobs?.map(_globToRegex).toList(),
      excludePatterns = source.excludeGlobs?.map(_globToRegex).toList(),
      minAgeCutoff = source.minAgeMs > 0
          ? DateTime.now().subtract(Duration(milliseconds: source.minAgeMs))
          : null;
}

/// A single traversal root and every rule whose physical roots overlap it.
class _ScanGroup {
  String scanPath;
  String scanKey;
  final List<_CompiledRule> rules;

  _ScanGroup(_CompiledRule first)
    : scanPath = first.source.basePath,
      scanKey = first.baseKey,
      rules = <_CompiledRule>[first];

  bool get recursive =>
      rules.any((rule) => rule.source.recursive || rule.baseKey != scanKey);

  void add(_CompiledRule rule) {
    rules.add(rule);
    rules.sort((a, b) => a.order.compareTo(b.order));
    if (rule.baseKey.length < scanKey.length) {
      scanPath = rule.source.basePath;
      scanKey = rule.baseKey;
    }
  }
}

List<_ScanGroup> _buildScanGroups(List<_CompiledRule> rules) {
  final groups = <_ScanGroup>[];
  for (final rule in rules) {
    final matching = <_ScanGroup>[];
    for (final group in groups) {
      if (group.rules.any(
        (existing) => _pathsOverlap(existing.baseKey, rule.baseKey),
      )) {
        matching.add(group);
      }
    }

    if (matching.isEmpty) {
      groups.add(_ScanGroup(rule));
      continue;
    }

    final target = matching.first;
    target.add(rule);
    for (var i = 1; i < matching.length; i++) {
      final other = matching[i];
      for (final otherRule in other.rules) {
        target.add(otherRule);
      }
      groups.remove(other);
    }
  }
  return groups;
}

bool _matchesRule(_CompiledRule rule, String entityPath, String fileName) {
  if (!_isSameOrDescendantPath(entityPath, rule.baseKey)) return false;

  if (!rule.source.recursive) {
    final separator = entityPath.lastIndexOf('\\');
    final parent = separator < 0
        ? entityPath
        : entityPath.substring(0, separator);
    if (parent != rule.baseKey) return false;
  }

  final include = rule.includePatterns;
  if (include != null &&
      !include.any((pattern) => pattern.hasMatch(fileName))) {
    return false;
  }
  final exclude = rule.excludePatterns;
  if (exclude != null && exclude.any((pattern) => pattern.hasMatch(fileName))) {
    return false;
  }
  return true;
}

bool _pathsOverlap(String first, String second) =>
    _isSameOrDescendantPath(first, second) ||
    _isSameOrDescendantPath(second, first);

bool _isSameOrDescendantPath(String path, String base) {
  if (path == base) return true;
  if (base.endsWith('\\')) return path.startsWith(base);
  return path.startsWith('$base\\');
}

String _pathKey(String path) {
  var key = path.replaceAll('/', '\\');
  while (key.length > 1 && key.endsWith('\\')) {
    // Keep a drive root such as C:\\ intact.
    if (key.length == 3 && key[1] == ':') break;
    key = key.substring(0, key.length - 1);
  }
  return Platform.isWindows ? key.toLowerCase() : key;
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
  final Duration rootOpenTimeout;
  final bool useNativeScanner;
  const _SpawnArgs({
    required this.sendPort,
    required this.rules,
    required this.rootOpenTimeout,
    required this.useNativeScanner,
  });
}

class _ProgressMsg {
  final String currentPath;
  final int itemsFound;
  final int bytesFound;
  final String categoryId;
  final double? fraction;
  const _ProgressMsg({
    required this.currentPath,
    required this.itemsFound,
    required this.bytesFound,
    required this.categoryId,
    required this.fraction,
  });
}

/// Estimates how far a junk scan has got from the path being read.
///
/// Each scan root weighs as much as it has top-level folders, and inside a
/// root the position of the top-level folder being walked marks progress.
/// The value never goes backwards, even if listing order differs.
class JunkScanFraction {
  final List<String> _roots;
  final List<Map<String, int>> _childIndex = [];
  final List<int> _weights = [];
  late final int _total;
  int _group = -1;
  int _doneWeight = 0;
  double _reported = 0;

  JunkScanFraction(
    Iterable<String> roots, {
    List<String> Function(String root)? listChildren,
  }) : _roots = roots.map(_upper).toList() {
    for (final root in _roots) {
      final index = <String, int>{};
      try {
        for (final name in (listChildren ?? _childFolders)(root)) {
          index.putIfAbsent(name.toUpperCase(), () => index.length);
        }
      } catch (_) {}
      _childIndex.add(index);
      // One unit for files directly in the root plus one per folder.
      _weights.add(index.length + 1);
    }
    _total = _weights.fold(0, (sum, w) => sum + w);
  }

  static String _upper(String path) {
    final upper = path.toUpperCase();
    return upper.endsWith(r'\') ? upper.substring(0, upper.length - 1) : upper;
  }

  static List<String> _childFolders(String root) => [
    for (final entity in Directory(root).listSync(followLinks: false))
      if (entity is Directory)
        entity.path.substring(entity.path.lastIndexOf(r'\') + 1),
  ];

  void startGroup(int index) {
    for (var i = _group < 0 ? 0 : _group; i < index; i++) {
      _doneWeight += _weights[i];
    }
    _group = index;
  }

  void finish() => _reported = 1;

  double at(String path) {
    if (_total == 0 || _reported >= 1) return _reported;
    var within = 0;
    if (_group >= 0 && path.isNotEmpty) {
      final prefix = '${_roots[_group]}\\';
      final upper = path.toUpperCase();
      if (upper.startsWith(prefix)) {
        final rest = upper.substring(prefix.length);
        final slash = rest.indexOf(r'\');
        final child = slash < 0 ? rest : rest.substring(0, slash);
        // Folders before this one are done; +1 for the root's own files.
        final position = _childIndex[_group][child];
        if (position != null) within = position + 1;
      }
    }
    final value = (_doneWeight + within) / _total;
    if (value > _reported) _reported = value.clamp(0.0, 0.999);
    return _reported;
  }
}

class _DoneMsg {
  final Map<String, List<JunkItem>> itemsByCategory;
  final List<String> warnings;
  const _DoneMsg({required this.itemsByCategory, required this.warnings});
}
