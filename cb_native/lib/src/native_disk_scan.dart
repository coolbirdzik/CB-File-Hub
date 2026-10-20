import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_search.dart' show CbNative;

/// A whole-directory junk rule. [upperPath] and [upperPrefix] must already be
/// `toUpperCase()`d by the caller, exactly as the Dart scanner compares them.
class NativeWholeDirRule {
  const NativeWholeDirRule({
    required this.upperPath,
    required this.upperPrefix,
    required this.category,
  });

  final String upperPath;
  final String upperPrefix;
  final int category;
}

/// A file-glob junk rule; [upperBasePath] and [upperGlobs] are upper-cased.
/// Globs support `*` and `?` like `_globToRegex` in the Dart scanner.
class NativeGlobRule {
  const NativeGlobRule({
    required this.upperBasePath,
    required this.category,
    required this.upperGlobs,
  });

  final String upperBasePath;
  final int category;
  final List<String> upperGlobs;
}

enum NativeDirStatus { scanned, inaccessible, maxDepthReached }

class NativeSubdir {
  const NativeSubdir({
    required this.id,
    required this.name,
    required this.lastWriteFileTime,
    required this.lastAccessFileTime,
    required this.category,
    this.fileId,
  });

  final int id;
  final String name;

  /// Raw Windows FILETIME ticks (100 ns since 1601 UTC).
  final int lastWriteFileTime;
  final int lastAccessFileTime;

  /// Index into the caller's category list, or -1.
  final int category;

  /// The NTFS file reference number, when the scan collected them.
  final int? fileId;
}

class NativeFileRow {
  const NativeFileRow({
    required this.name,
    required this.size,
    required this.lastWriteFileTime,
    required this.lastAccessFileTime,
    required this.category,
  });

  final String name;
  final int size;
  final int lastWriteFileTime;
  final int lastAccessFileTime;
  final int category;
}

/// One directory's own contents. Records arrive parent-first: a directory's
/// record always precedes the records of the subdirectories it lists.
class NativeDirRecord {
  const NativeDirRecord({
    required this.id,
    required this.status,
    required this.subdirs,
    required this.retainedFiles,
    required this.oldLargeFiles,
    required this.foldedBytes,
    required this.foldedFiles,
    required this.foldedJunkBytes,
    required this.foldedEntries,
    required this.ownBytes,
    required this.ownFiles,
    required this.newestActivityFileTime,
    required this.reparseNames,
  });

  /// 0 is the scan root; other ids come from a parent's [subdirs].
  final int id;
  final NativeDirStatus status;
  final List<NativeSubdir> subdirs;

  /// The largest direct files, ascending by size.
  final List<NativeFileRow> retainedFiles;

  /// Every direct file at or above the old-large threshold.
  final List<NativeFileRow> oldLargeFiles;
  final int foldedBytes;
  final int foldedFiles;
  final int foldedJunkBytes;
  final int foldedEntries;

  /// Direct files only; subdirectories report their own.
  final int ownBytes;
  final int ownFiles;

  /// Newest FILETIME among the direct entries (files' write or access,
  /// subfolders' own write); 0 when there are none.
  final int newestActivityFileTime;

  /// Direct entries skipped because they are reparse points.
  final List<String> reparseNames;
}

class NativeDiskScanBatch {
  const NativeDiskScanBatch(this.records, {required this.finished});

  final List<NativeDirRecord> records;
  final bool finished;
}

class NativeDiskScanProgress {
  const NativeDiskScanProgress({
    required this.directories,
    required this.files,
    required this.bytes,
    required this.currentPath,
  });

  final int directories;
  final int files;
  final int bytes;
  final String currentPath;
}

/// Parallel Disk Cleaner scan of one directory subtree on Rust threads.
///
/// Starting and polling never block on the filesystem. Always [dispose].
class NativeDiskScan implements Finalizable {
  NativeDiskScan._(this._handle) {
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  /// Frees the handle if this object is dropped without [dispose]. The Disk
  /// Cleaner cancels by killing the scanning isolate, so this is the normal
  /// cleanup path there; Rust also stops walking on its own once nobody has
  /// polled for a while, so a killed owner never leaves a full-disk walk
  /// running in the background.
  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      b.cb_disk_scan_free,
    ),
  );

  Pointer<b.DiskScanHandle> _handle;

  /// Returns null when the native library is unavailable.
  static NativeDiskScan? start({
    required String root,
    required int startDepth,
    required int maxDepth,
    required int maxChildrenPerDirectory,
    required int minDisplayEntryBytes,
    required int oldLargeFileBytes,
    int inheritedCategory = -1,
    int threads = 0,
    List<NativeWholeDirRule> wholeDirRules = const [],
    List<NativeGlobRule> globRules = const [],
    bool collectFileIds = false,
  }) {
    if (!CbNative.isAvailable || root.isEmpty) return null;
    final config = WireWriter()
      ..str(root)
      ..u32(startDepth)
      ..u32(maxDepth)
      ..i64(maxChildrenPerDirectory)
      ..i64(minDisplayEntryBytes)
      ..i64(oldLargeFileBytes)
      ..i32(inheritedCategory)
      ..u32(threads)
      ..u32(wholeDirRules.length);
    for (final rule in wholeDirRules) {
      config
        ..str(rule.upperPath)
        ..str(rule.upperPrefix)
        ..i32(rule.category);
    }
    config.u32(globRules.length);
    for (final rule in globRules) {
      config
        ..str(rule.upperBasePath)
        ..i32(rule.category)
        ..u32(rule.upperGlobs.length);
      for (final glob in rule.upperGlobs) {
        config.str(glob);
      }
    }
    config.boolean(collectFileIds);

    return using((arena) {
      final arg = Utf8Arg.bytes(config.takeBytes(), arena);
      final outHandle = arena<Pointer<b.DiskScanHandle>>();
      final status = b.cb_disk_scan_start(arg.ptr, arg.length, outHandle);
      if (status != b.statusOk) return null;
      return NativeDiskScan._(outHandle.value);
    });
  }

  bool get isDisposed => _handle == nullptr;

  NativeDiskScanBatch poll() {
    if (isDisposed) return const NativeDiskScanBatch([], finished: true);
    return using((arena) {
      final outPtr = arena<Pointer<Uint8>>();
      final outLen = arena<Size>();
      final finished = b.cb_disk_scan_poll(_handle, outPtr, outLen) == 1;
      final bytes = takeBuffer(outPtr.value, outLen.value);
      return NativeDiskScanBatch(
        _RecordReader(bytes).readAll(),
        finished: finished,
      );
    });
  }

  /// Tells the scan its owner is still alive while a long batch is being
  /// applied; Rust abandons a scan that is not polled for 15 seconds.
  void keepAlive() => progress();

  NativeDiskScanProgress progress() {
    if (isDisposed) {
      return const NativeDiskScanProgress(
        directories: 0,
        files: 0,
        bytes: 0,
        currentPath: '',
      );
    }
    return using((arena) {
      final counts = arena<Uint64>(3);
      final outPtr = arena<Pointer<Uint8>>();
      final outLen = arena<Size>();
      b.cb_disk_scan_progress(_handle, counts, outPtr, outLen);
      return NativeDiskScanProgress(
        directories: counts[0],
        files: counts[1],
        bytes: counts[2],
        currentPath: utf8.decode(
          takeBuffer(outPtr.value, outLen.value),
          allowMalformed: true,
        ),
      );
    });
  }

  void cancel() {
    if (!isDisposed) b.cb_disk_scan_cancel(_handle);
  }

  /// Cancels the scan and frees the handle. Never waits for workers.
  void dispose() {
    if (isDisposed) return;
    _finalizer.detach(this);
    b.cb_disk_scan_free(_handle.cast());
    _handle = nullptr;
  }
}

/// Decodes the records written by `DirectoryRecord::write` in disk_scan.rs.
class _RecordReader {
  _RecordReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _offset = 0;

  List<NativeDirRecord> readAll() {
    final records = <NativeDirRecord>[];
    while (_offset < _bytes.length) {
      records.add(_record());
    }
    return records;
  }

  int _u8() => _data.getUint8(_offset++);

  int _u32() {
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int _i32() {
    final value = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int _u64() {
    // Sizes and FILETIMEs stay far below 2^63, so the signed read is exact.
    final value = _data.getInt64(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  String _str() {
    final length = _u32();
    final value = utf8.decode(
      Uint8List.sublistView(_bytes, _offset, _offset + length),
      allowMalformed: true,
    );
    _offset += length;
    return value;
  }

  List<NativeFileRow> _files() => List.generate(_u32(), (_) {
    final size = _u64();
    final lastWrite = _u64();
    final lastAccess = _u64();
    final category = _i32();
    return NativeFileRow(
      name: _str(),
      size: size,
      lastWriteFileTime: lastWrite,
      lastAccessFileTime: lastAccess,
      category: category,
    );
  });

  NativeDirRecord _record() {
    final id = _u32();
    final status = switch (_u8()) {
      1 => NativeDirStatus.inaccessible,
      2 => NativeDirStatus.maxDepthReached,
      _ => NativeDirStatus.scanned,
    };
    final subdirs = List.generate(_u32(), (_) {
      final childId = _u32();
      final lastWrite = _u64();
      final lastAccess = _u64();
      final category = _i32();
      final fileId = _u64();
      return NativeSubdir(
        id: childId,
        name: _str(),
        lastWriteFileTime: lastWrite,
        lastAccessFileTime: lastAccess,
        category: category,
        fileId: fileId == 0 ? null : fileId,
      );
    });
    final retained = _files();
    final oldLarge = _files();
    return NativeDirRecord(
      id: id,
      status: status,
      subdirs: subdirs,
      retainedFiles: retained,
      oldLargeFiles: oldLarge,
      foldedBytes: _u64(),
      foldedFiles: _u64(),
      foldedJunkBytes: _u64(),
      foldedEntries: _u64(),
      ownBytes: _u64(),
      ownFiles: _u64(),
      newestActivityFileTime: _u64(),
      reparseNames: List.generate(_u32(), (_) => _str()),
    );
  }
}
