import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../../helpers/core/filesystem_utils.dart';

/// One row of a transfer pane.
class TransferEntry {
  final String name, path;
  final bool isDirectory;

  /// A symbolic link (or Windows junction). Its target decides
  /// [isDirectory]; transfers never recurse through it.
  final bool isLink;
  final int size;
  final DateTime? modified;
  const TransferEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isLink = false,
    this.size = 0,
    this.modified,
  });
}

/// One side of the two-pane transfer screen: this computer or an SFTP session.
abstract class TransferFileSystem {
  p.Context get paths;

  /// Directory a pane opens on.
  Future<String> home();

  /// The folder above [path], or null at the top.
  String? parent(String path);
  Future<List<TransferEntry>> list(String directory);

  /// Null when nothing exists at [path], otherwise whether it is a directory.
  Future<bool?> kind(String path);
  Future<void> createDirectory(String path);
  Stream<Uint8List> read(String path);

  /// Writes [data] to [path], replacing it. [onProgress] receives the bytes
  /// written to this file so far.
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    void Function(int written) onProgress,
  );
  Future<void> deleteFile(String path);
}

/// This computer. On Windows the empty path lists the drives.
class LocalTransferFileSystem implements TransferFileSystem {
  LocalTransferFileSystem({p.Context? paths, this.listDrives})
    : paths = paths ?? p.context;

  @override
  final p.Context paths;

  /// Overrides the Windows drive list, for tests.
  final Future<List<String>> Function()? listDrives;

  bool get _hasDriveList => paths.style == p.Style.windows;

  @override
  Future<String> home() async {
    // Android has no usable HOME; start on the shared storage instead.
    if (Platform.isAndroid) {
      try {
        final storage = await getAllStorageLocations();
        if (storage.isNotEmpty) return storage.first.path;
      } catch (_) {}
    }
    final home =
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (home != null && await Directory(home).exists()) return home;
    return _hasDriveList ? '' : paths.rootPrefix(Directory.current.path);
  }

  @override
  String? parent(String path) {
    if (path.isEmpty) return null;
    final parent = paths.dirname(path);
    if (parent != path) return parent;
    return _hasDriveList ? '' : null;
  }

  @override
  Future<List<TransferEntry>> list(String directory) async {
    if (directory.isEmpty && _hasDriveList) {
      final drives =
          await listDrives?.call() ??
          [for (final d in await getAllWindowsDrives()) d.path];
      return [
        for (final drive in drives)
          TransferEntry(
            name: drive.replaceAll(RegExp(r'[\\/]+$'), ''),
            path: drive.endsWith(r'\') ? drive : '$drive\\',
            isDirectory: true,
          ),
      ];
    }
    final entries = <TransferEntry>[];
    // Links are listed but not followed, so profile junctions such as
    // "Application Data" cannot loop a recursive transfer.
    await for (final entity in Directory(directory).list(followLinks: false)) {
      try {
        final isLink = entity is Link;
        final stat = await FileStat.stat(entity.path);
        if (stat.type == FileSystemEntityType.notFound) continue;
        final isDirectory = stat.type == FileSystemEntityType.directory;
        entries.add(
          TransferEntry(
            name: paths.basename(entity.path),
            path: entity.path,
            isDirectory: isDirectory,
            isLink: isLink,
            size: isDirectory ? 0 : stat.size,
            modified: stat.modified,
          ),
        );
      } catch (_) {
        // pagefile.sys, System Volume Information and other entries the
        // user may not stat stay out of the listing instead of failing it.
      }
    }
    return entries;
  }

  @override
  Future<bool?> kind(String path) async =>
      switch (await FileSystemEntity.type(path)) {
        FileSystemEntityType.notFound => null,
        FileSystemEntityType.directory => true,
        _ => false,
      };

  @override
  Future<void> createDirectory(String path) => Directory(path).create();

  @override
  Stream<Uint8List> read(String path) => File(path).openRead().map(
    (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
  );

  @override
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    void Function(int written) onProgress,
  ) async {
    final sink = File(path).openWrite();
    var written = 0;
    try {
      await sink.addStream(
        data.map((chunk) {
          written += chunk.length;
          onProgress(written);
          return chunk;
        }),
      );
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> deleteFile(String path) => File(path).delete();
}

/// The remote side, over an SFTP subsystem the caller owns.
class SftpTransferFileSystem implements TransferFileSystem {
  SftpTransferFileSystem(this.client);
  final SftpClient client;

  @override
  p.Context get paths => p.posix;

  @override
  Future<String> home() async {
    try {
      final home = await client.absolute('.');
      if (home.isNotEmpty) return home;
    } catch (_) {}
    return '/';
  }

  @override
  String? parent(String path) {
    final parent = p.posix.dirname(path);
    return parent == path ? null : parent;
  }

  @override
  Future<List<TransferEntry>> list(String directory) async {
    final entries = <TransferEntry>[];
    for (final name in await client.listdir(directory)) {
      if (name.filename == '.' || name.filename == '..') continue;
      final path = p.posix.join(directory, name.filename);
      var attrs = name.attr;
      final isLink = attrs.isSymbolicLink;
      if (isLink) {
        try {
          attrs = await client.stat(path);
        } catch (_) {
          continue; // A dangling link has nothing to transfer.
        }
      }
      entries.add(
        TransferEntry(
          name: name.filename,
          path: path,
          isDirectory: attrs.isDirectory,
          isLink: isLink,
          size: attrs.isDirectory ? 0 : attrs.size ?? 0,
          modified: attrs.modifyTime == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(attrs.modifyTime! * 1000),
        ),
      );
    }
    return entries;
  }

  @override
  Future<bool?> kind(String path) async {
    try {
      return (await client.stat(path)).isDirectory;
    } on SftpStatusError catch (e) {
      if (e.code == SftpStatusCode.noSuchFile) return null;
      rethrow;
    }
  }

  @override
  Future<void> createDirectory(String path) => client.mkdir(path);

  @override
  Stream<Uint8List> read(String path) async* {
    final file = await client.open(path);
    try {
      yield* file.read();
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    void Function(int written) onProgress,
  ) async {
    final file = await client.open(
      path,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      await file.write(data, onProgress: onProgress).done;
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> deleteFile(String path) => client.remove(path);
}

enum TransferConflictPolicy { replace, skip }

enum TransferFailureKind {
  /// The operation threw; see [TransferFailure.error].
  error,

  /// The name cannot exist on the destination (Windows reserved characters,
  /// device names, trailing dots or spaces).
  invalidName,

  /// A linked folder; transfers never follow links.
  link,

  /// A file stands where a folder goes, or the reverse.
  typeConflict,

  /// Another item of the batch differs only by letter case, which a Windows
  /// destination would merge into one.
  caseConflict,
}

class TransferFailure {
  final String path;
  final TransferFailureKind kind;
  final Object? error;
  const TransferFailure(this.path, this.kind, [this.error]);
}

class TransferProgress {
  final int filesDone, filesTotal, bytesDone, bytesTotal;
  final String current;
  const TransferProgress({
    required this.filesDone,
    required this.filesTotal,
    required this.bytesDone,
    required this.bytesTotal,
    required this.current,
  });
  double? get fraction => bytesTotal > 0
      ? (bytesDone / bytesTotal).clamp(0.0, 1.0)
      : filesTotal > 0
      ? filesDone / filesTotal
      : null;
}

class TransferReport {
  final int transferred, skipped;
  final List<TransferFailure> failures;
  final bool cancelled;
  const TransferReport({
    required this.transferred,
    required this.skipped,
    required this.failures,
    required this.cancelled,
  });
}

class TransferCancelled implements Exception {
  const TransferCancelled();
}

class _Step {
  final String source, target;
  final bool isDirectory;
  final int size;
  const _Step(this.source, this.target, this.isDirectory, this.size);
}

/// Copies entries from one [TransferFileSystem] into a folder of another.
///
/// Folders are copied recursively and merged into existing folders. Existing
/// files follow the policy [resolveConflicts] returns for the top-level names
/// that already exist; returning null cancels before anything is written.
class SftpTransferTask {
  SftpTransferTask({
    required this.from,
    required this.to,
    required this.sources,
    required this.destination,
    this.resolveConflicts,
    this.onProgress,
    this.progressInterval = const Duration(milliseconds: 100),
  });

  final TransferFileSystem from, to;
  final List<TransferEntry> sources;
  final String destination;
  final Future<TransferConflictPolicy?> Function(List<String> names)?
  resolveConflicts;
  final void Function(TransferProgress progress)? onProgress;
  final Duration progressInterval;

  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;

  static final _windowsInvalid = RegExp(r'[<>:"/\\|?*\x00-\x1f]');
  static final _windowsDevice = RegExp(
    r'^(con|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³])$',
    caseSensitive: false,
  );

  bool _validName(String name) {
    if (to.paths.style != p.Style.windows) {
      return name.isNotEmpty && !name.contains('/');
    }
    return name.isNotEmpty &&
        !_windowsInvalid.hasMatch(name) &&
        !name.endsWith('.') &&
        !name.endsWith(' ') &&
        !_windowsDevice.hasMatch(name.split('.').first.trimRight());
  }

  Future<TransferReport> run() async {
    final failures = <TransferFailure>[];
    final steps = <_Step>[];
    final caseInsensitive = to.paths.style == p.Style.windows;
    final planned = <String>{};

    Future<void> plan(TransferEntry entry, String targetDir) async {
      if (_cancelled) throw const TransferCancelled();
      if (!_validName(entry.name)) {
        failures.add(
          TransferFailure(entry.path, TransferFailureKind.invalidName),
        );
        return;
      }
      final target = to.paths.join(targetDir, entry.name);
      if (caseInsensitive && !planned.add(target.toLowerCase())) {
        failures.add(
          TransferFailure(entry.path, TransferFailureKind.caseConflict),
        );
        return;
      }
      if (!entry.isDirectory) {
        steps.add(_Step(entry.path, target, false, entry.size));
        return;
      }
      if (entry.isLink) {
        failures.add(TransferFailure(entry.path, TransferFailureKind.link));
        return;
      }
      steps.add(_Step(entry.path, target, true, 0));
      final List<TransferEntry> children;
      try {
        children = await from.list(entry.path);
      } catch (e) {
        failures.add(TransferFailure(entry.path, TransferFailureKind.error, e));
        return;
      }
      for (final child in children) {
        // Nested links are skipped silently, like a file manager's copy.
        if (child.isLink && child.isDirectory) continue;
        await plan(child, target);
      }
    }

    var transferred = 0, skipped = 0;
    try {
      TransferConflictPolicy? policy;
      final conflicts = <String>[];
      for (final entry in sources) {
        if (await to.kind(to.paths.join(destination, entry.name)) != null) {
          conflicts.add(entry.name);
        }
      }
      if (conflicts.isNotEmpty) {
        policy = await resolveConflicts?.call(conflicts);
        if (policy == null) throw const TransferCancelled();
      }
      for (final entry in sources) {
        await plan(entry, destination);
      }

      final files = steps.where((s) => !s.isDirectory).length;
      final bytesTotal = steps.fold<int>(0, (sum, s) => sum + s.size);
      var filesDone = 0, bytesDone = 0;
      final clock = Stopwatch()..start();
      var lastReport = -progressInterval.inMicroseconds;
      void report(String current, int bytes, {bool force = false}) {
        final now = clock.elapsedMicroseconds;
        if (!force && now - lastReport < progressInterval.inMicroseconds) {
          return;
        }
        lastReport = now;
        onProgress?.call(
          TransferProgress(
            filesDone: filesDone,
            filesTotal: files,
            bytesDone: bytes,
            bytesTotal: bytesTotal,
            current: current,
          ),
        );
      }

      Stream<Uint8List> guarded(Stream<Uint8List> data) async* {
        await for (final chunk in data) {
          if (_cancelled) throw const TransferCancelled();
          yield chunk;
        }
      }

      // Folders that could not be created; their contents are not attempted.
      final blocked = <String>[];
      for (final step in steps) {
        if (_cancelled) throw const TransferCancelled();
        final name = from.paths.basename(step.source);
        if (blocked.any((dir) => to.paths.isWithin(dir, step.target))) {
          if (!step.isDirectory) {
            filesDone++;
            bytesDone += step.size;
          }
          continue;
        }
        report(name, bytesDone, force: true);
        // Without a conflict nothing below the destination existed, so only
        // a merge needs to look before writing.
        final existing = policy == null ? null : await to.kind(step.target);
        if (step.isDirectory) {
          if (existing == false) {
            failures.add(
              TransferFailure(step.source, TransferFailureKind.typeConflict),
            );
            blocked.add(step.target);
          } else if (existing == null) {
            try {
              await to.createDirectory(step.target);
            } catch (e) {
              failures.add(
                TransferFailure(step.source, TransferFailureKind.error, e),
              );
              blocked.add(step.target);
            }
          }
          continue;
        }
        if (existing == true) {
          failures.add(
            TransferFailure(step.source, TransferFailureKind.typeConflict),
          );
        } else if (existing == false && policy == TransferConflictPolicy.skip) {
          skipped++;
        } else {
          final base = bytesDone;
          var started = false;
          try {
            await to.write(step.target, guarded(from.read(step.source)), (
              written,
            ) {
              started = true;
              report(name, base + written.clamp(0, step.size));
            });
            transferred++;
          } on TransferCancelled {
            await _discard(step.target, started || existing == null);
            rethrow;
          } catch (e) {
            failures.add(
              TransferFailure(step.source, TransferFailureKind.error, e),
            );
            await _discard(step.target, started || existing == null);
          }
        }
        filesDone++;
        bytesDone += step.size;
        report(name, bytesDone, force: true);
      }
      return TransferReport(
        transferred: transferred,
        skipped: skipped,
        failures: failures,
        cancelled: false,
      );
    } on TransferCancelled {
      return TransferReport(
        transferred: transferred,
        skipped: skipped,
        failures: failures,
        cancelled: true,
      );
    }
  }

  /// Removes a partially written file. A replaced file is already truncated,
  /// so it goes as well once writing began.
  Future<void> _discard(String path, bool written) async {
    if (!written) return;
    try {
      if (await to.kind(path) == false) await to.deleteFile(path);
    } catch (_) {}
  }
}
