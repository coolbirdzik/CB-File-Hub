import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
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

  /// Reads [length] bytes of [path] from [offset]; to the end when null.
  Stream<Uint8List> read(String path, {int offset = 0, int? length});

  /// How many reads and writes are worth running at once.
  int get streams;

  /// Lets go of whatever idle [streams] hold open, once a transfer ends.
  void releaseStreams();

  /// Writes [data] to [path], replacing it. [onProgress] receives the bytes
  /// written to this file so far.
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    void Function(int written) onProgress,
  );
  Future<void> deleteFile(String path);

  /// Removes an empty folder.
  Future<void> deleteDirectory(String path);

  /// Moves or renames [from] to [to], which must not exist yet.
  Future<void> rename(String from, String to);
}

/// Writes one file out of order, so several streams can fill it at once.
abstract class TransferFileWriter {
  Future<void> writeAt(int position, Uint8List data);
  Future<void> close();
}

/// A [TransferFileSystem] whose files can be written out of order.
abstract class RandomAccessTransferTarget {
  /// Creates or replaces [path] with room for [size] bytes.
  Future<TransferFileWriter> openWriter(String path, int size);
}

class _LocalFileWriter implements TransferFileWriter {
  _LocalFileWriter(this._file);
  final RandomAccessFile _file;

  /// A RandomAccessFile runs one operation at a time.
  Future<void> _tail = Future.value();

  @override
  Future<void> writeAt(int position, Uint8List data) {
    final done = _tail.then((_) async {
      await _file.setPosition(position);
      await _file.writeFrom(data);
    });
    _tail = done.then((_) {}, onError: (_) {});
    return done;
  }

  @override
  Future<void> close() => _tail.then((_) => _file.close());
}

/// This computer. On Windows the empty path lists the drives.
class LocalTransferFileSystem
    implements TransferFileSystem, RandomAccessTransferTarget {
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
  Stream<Uint8List> read(String path, {int offset = 0, int? length}) =>
      File(path)
          .openRead(offset, length == null ? null : offset + length)
          .map(
            (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
          );

  @override
  int get streams => 1;

  @override
  void releaseStreams() {}

  @override
  Future<TransferFileWriter> openWriter(String path, int size) async {
    final file = await File(path).open(mode: FileMode.write);
    try {
      await file.truncate(size);
    } catch (_) {
      await file.close();
      rethrow;
    }
    return _LocalFileWriter(file);
  }

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

  @override
  Future<void> deleteDirectory(String path) => Directory(path).delete();

  @override
  Future<void> rename(String from, String to) async =>
      switch (await FileSystemEntity.type(from, followLinks: false)) {
        FileSystemEntityType.directory => Directory(from).rename(to),
        FileSystemEntityType.link => Link(from).rename(to),
        _ => File(from).rename(to),
      };
}

/// One more SSH connection to the same host, carrying its own SFTP channel.
class SftpLane {
  const SftpLane({
    required this.client,
    required this.done,
    required this.close,
  });
  final SftpClient client;

  /// Completes when the connection ends.
  final Future<void> done;
  final void Function() close;
}

class _Lane {
  _Lane(this.client, [this.close]);
  final SftpClient client;
  final void Function()? close;
  int active = 0;
}

/// The remote side, over an SFTP subsystem the caller owns.
///
/// One SSH connection is one TCP stream, so with [openLane] every further
/// concurrent read or write gets a connection of its own, up to [maxStreams].
/// A server that refuses more connections leaves everything on [client].
class SftpTransferFileSystem implements TransferFileSystem {
  SftpTransferFileSystem(this.client, {this.openLane, this.maxStreams = 4});
  final SftpClient client;
  final Future<SftpLane> Function()? openLane;
  final int maxStreams;

  late final _primary = _Lane(client);
  final _lanes = <_Lane>[];
  int _opening = 0;
  bool _refused = false;

  @override
  int get streams => openLane == null ? 1 : maxStreams;

  Future<_Lane> _acquire() async {
    _Lane idlest() =>
        [_primary, ..._lanes].reduce((a, b) => b.active < a.active ? b : a);
    var lane = idlest();
    final open = openLane;
    if (lane.active > 0 &&
        open != null &&
        !_refused &&
        1 + _lanes.length + _opening < maxStreams) {
      _opening++;
      try {
        final opened = await open();
        final extra = _Lane(opened.client, opened.close);
        _lanes.add(extra);
        unawaited(
          opened.done
              .then((_) {}, onError: (_) {})
              .whenComplete(() => _lanes.remove(extra)),
        );
        lane = extra;
      } catch (_) {
        _refused = true;
        lane = idlest();
      } finally {
        _opening--;
      }
    }
    lane.active++;
    return lane;
  }

  @override
  void releaseStreams() {
    _refused = false;
    for (final lane in _lanes.where((lane) => lane.active == 0).toList()) {
      _lanes.remove(lane);
      lane.close?.call();
    }
  }

  /// Closes every extra connection, used or not.
  void closeLanes() {
    for (final lane in _lanes.toList()) {
      lane.close?.call();
    }
    _lanes.clear();
  }

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
  Stream<Uint8List> read(String path, {int offset = 0, int? length}) async* {
    final lane = await _acquire();
    try {
      final file = await lane.client.open(path);
      try {
        // Without a range the library sizes the read itself, which also
        // covers files that report no size.
        yield* offset == 0 && length == null
            ? file.read()
            : file.read(offset: offset, length: length);
      } finally {
        await file.close();
      }
    } finally {
      lane.active--;
    }
  }

  @override
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    void Function(int written) onProgress,
  ) async {
    final lane = await _acquire();
    try {
      final file = await lane.client.open(
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
    } finally {
      lane.active--;
    }
  }

  @override
  Future<void> deleteFile(String path) => client.remove(path);

  @override
  Future<void> deleteDirectory(String path) => client.rmdir(path);

  @override
  Future<void> rename(String from, String to) => client.rename(from, to);
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

  /// A move found an item of the same name in the destination.
  exists,
}

class TransferFailure {
  final String path;
  final TransferFailureKind kind;
  final Object? error;
  const TransferFailure(this.path, this.kind, [this.error]);
}

/// Deletes [entries] and everything below them on [fs]. A link is removed
/// itself, never followed.
Future<List<TransferFailure>> deleteTransferEntries(
  TransferFileSystem fs,
  List<TransferEntry> entries,
) async {
  Future<void> remove(TransferEntry entry) async {
    if (!entry.isDirectory || entry.isLink) return fs.deleteFile(entry.path);
    for (final child in await fs.list(entry.path)) {
      await remove(child);
    }
    await fs.deleteDirectory(entry.path);
  }

  final failures = <TransferFailure>[];
  for (final entry in entries) {
    try {
      await remove(entry);
    } catch (e) {
      failures.add(TransferFailure(entry.path, TransferFailureKind.error, e));
    }
  }
  return failures;
}

/// Moves [entries] into the folder [destination] of the same [fs]. Nothing
/// is replaced: a name that already exists there is reported instead.
Future<List<TransferFailure>> moveTransferEntries(
  TransferFileSystem fs,
  List<TransferEntry> entries,
  String destination,
) async {
  final failures = <TransferFailure>[];
  for (final entry in entries) {
    final target = fs.paths.join(destination, entry.name);
    try {
      if (await fs.kind(target) != null) {
        failures.add(TransferFailure(entry.path, TransferFailureKind.exists));
      } else {
        await fs.rename(entry.path, target);
      }
    } catch (e) {
      failures.add(TransferFailure(entry.path, TransferFailureKind.error, e));
    }
  }
  return failures;
}

class TransferProgress {
  final int filesDone, filesTotal, bytesDone, bytesTotal;
  final String current;

  /// Throughput over the last few seconds.
  final double bytesPerSecond;
  const TransferProgress({
    required this.filesDone,
    required this.filesTotal,
    required this.bytesDone,
    required this.bytesTotal,
    required this.current,
    this.bytesPerSecond = 0,
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

/// A large file several streams fill together.
class _Split {
  _Split(this.step, this.writer);
  final _Step step;
  final TransferFileWriter writer;

  /// Segments not finished yet.
  int pieces = 0;
  int written = 0;
  Object? error;
}

class _Piece {
  const _Piece(this.split, this.offset, this.length);
  final _Split split;
  final int offset, length;
}

/// Copies entries from one [TransferFileSystem] into a folder of another.
///
/// Folders are copied recursively and merged into existing folders. Existing
/// files follow the policy [resolveConflicts] returns for the top-level names
/// that already exist; returning null cancels before anything is written.
///
/// As many files move at once as the two sides have [TransferFileSystem.streams].
/// A file of two [segmentSize]s or more is cut into segments those streams
/// share, when the destination can be written out of order.
class SftpTransferTask {
  SftpTransferTask({
    required this.from,
    required this.to,
    required this.sources,
    required this.destination,
    this.resolveConflicts,
    this.onProgress,
    this.progressInterval = const Duration(milliseconds: 100),
    this.segmentSize = 8 * 1024 * 1024,
  });

  final TransferFileSystem from, to;
  final List<TransferEntry> sources;
  final String destination;
  final Future<TransferConflictPolicy?> Function(List<String> names)?
  resolveConflicts;
  final void Function(TransferProgress progress)? onProgress;
  final Duration progressInterval;
  final int segmentSize;

  /// The span [TransferProgress.bytesPerSecond] averages over.
  static const _speedWindow = Duration(seconds: 3);

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

      final files = [
        for (final step in steps)
          if (!step.isDirectory) step,
      ];
      final bytesTotal = steps.fold<int>(0, (sum, s) => sum + s.size);
      // [settled] counts finished files in full, [live] what the running
      // ones wrote so far, and [moved] only bytes that really travelled.
      var filesDone = 0, settled = 0, live = 0, moved = 0;
      var current = '';
      final clock = Stopwatch()..start();
      var lastReport = -progressInterval.inMicroseconds;
      final samples = Queue<(int, int)>()..add((0, 0));
      void report({bool force = false}) {
        final now = clock.elapsedMicroseconds;
        if (!force && now - lastReport < progressInterval.inMicroseconds) {
          return;
        }
        lastReport = now;
        samples.add((now, moved));
        while (samples.length > 2 &&
            now - samples.first.$1 > _speedWindow.inMicroseconds) {
          samples.removeFirst();
        }
        final span = now - samples.first.$1;
        onProgress?.call(
          TransferProgress(
            filesDone: filesDone,
            filesTotal: files.length,
            bytesDone: settled + live,
            bytesTotal: bytesTotal,
            current: current,
            bytesPerSecond: span > 0
                ? (moved - samples.first.$2) * 1e6 / span
                : 0,
          ),
        );
      }

      void settle(_Step step, int written) {
        live -= written;
        settled += step.size;
        filesDone++;
        report(force: true);
      }

      Stream<Uint8List> guarded(Stream<Uint8List> data) async* {
        await for (final chunk in data) {
          if (_cancelled) throw const TransferCancelled();
          yield chunk;
        }
      }

      // Folders that could not be created; their contents are not attempted.
      final blocked = <String>[];
      bool isBlocked(_Step step) =>
          blocked.any((dir) => to.paths.isWithin(dir, step.target));

      for (final step in steps.where((s) => s.isDirectory)) {
        if (_cancelled) throw const TransferCancelled();
        if (isBlocked(step)) continue;
        current = from.paths.basename(step.source);
        report(force: true);
        // Without a conflict nothing below the destination existed, so only
        // a merge needs to look before writing.
        final existing = policy == null ? null : await to.kind(step.target);
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
      }

      final target = to;
      final parallel = math.max(1, math.max(from.streams, to.streams));
      final pieces = Queue<_Piece>();
      final open = <_Split>{};

      Future<void> whole(_Step step, bool? existing) async {
        var written = 0, total = 0;
        var started = false;
        try {
          await to.write(step.target, guarded(from.read(step.source)), (sent) {
            started = true;
            moved += sent - total;
            total = sent;
            final shown = sent.clamp(0, step.size);
            live += shown - written;
            written = shown;
            report();
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
        settle(step, written);
      }

      Future<void> finish(_Split split) async {
        open.remove(split);
        try {
          await split.writer.close();
        } catch (e) {
          split.error ??= e;
        }
        if (_cancelled) {
          await _discard(split.step.target, true);
          return;
        }
        if (split.error != null) {
          failures.add(
            TransferFailure(
              split.step.source,
              TransferFailureKind.error,
              split.error,
            ),
          );
          await _discard(split.step.target, true);
        } else {
          transferred++;
        }
        settle(split.step, split.written);
      }

      Future<void> split(_Step step, bool? existing) async {
        final TransferFileWriter writer;
        try {
          writer = await (target as RandomAccessTransferTarget).openWriter(
            step.target,
            step.size,
          );
        } catch (e) {
          failures.add(
            TransferFailure(step.source, TransferFailureKind.error, e),
          );
          await _discard(step.target, existing == null);
          settle(step, 0);
          return;
        }
        final job = _Split(step, writer);
        open.add(job);
        for (var offset = 0; offset < step.size; offset += segmentSize) {
          job.pieces++;
          pieces.add(
            _Piece(job, offset, math.min(segmentSize, step.size - offset)),
          );
        }
      }

      Future<void> piece(_Piece piece) async {
        final job = piece.split;
        try {
          if (job.error != null) return;
          var position = piece.offset;
          await for (final chunk in guarded(
            from.read(
              job.step.source,
              offset: piece.offset,
              length: piece.length,
            ),
          )) {
            if (job.error != null) return;
            await job.writer.writeAt(position, chunk);
            position += chunk.length;
            job.written += chunk.length;
            live += chunk.length;
            moved += chunk.length;
            report();
          }
          if (position != piece.offset + piece.length) {
            // The file shrank after it was listed.
            job.error ??= const FileSystemException('Unexpected end of file');
          }
        } on TransferCancelled {
          rethrow;
        } catch (e) {
          job.error ??= e;
        } finally {
          if (--job.pieces == 0) await finish(job);
        }
      }

      Future<void> file(_Step step) async {
        if (isBlocked(step)) {
          settled += step.size;
          filesDone++;
          return;
        }
        current = from.paths.basename(step.source);
        report(force: true);
        final existing = policy == null ? null : await to.kind(step.target);
        if (existing == true) {
          failures.add(
            TransferFailure(step.source, TransferFailureKind.typeConflict),
          );
          settle(step, 0);
        } else if (existing == false && policy == TransferConflictPolicy.skip) {
          skipped++;
          settle(step, 0);
        } else if (parallel > 1 &&
            target is RandomAccessTransferTarget &&
            step.size >= segmentSize * 2) {
          await split(step, existing);
        } else {
          await whole(step, existing);
        }
      }

      var next = 0, preparing = 0;
      Completer<void>? wake;
      Future<void> worker() async {
        try {
          while (!_cancelled) {
            // Segments of a file under way go first, so free streams join it.
            if (pieces.isNotEmpty) {
              await piece(pieces.removeFirst());
            } else if (next < files.length) {
              final step = files[next++];
              preparing++;
              try {
                await file(step);
              } finally {
                preparing--;
                wake?.complete();
                wake = null;
              }
            } else if (preparing == 0) {
              return;
            } else {
              // A file being opened may still hand out segments.
              await (wake ??= Completer<void>()).future;
            }
          }
        } on TransferCancelled {
          // Reported once every stream has stopped.
        }
      }

      try {
        await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
      } finally {
        for (final job in open.toList()) {
          try {
            await job.writer.close();
          } catch (_) {}
          await _discard(job.step.target, true);
        }
      }
      if (_cancelled) throw const TransferCancelled();
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
