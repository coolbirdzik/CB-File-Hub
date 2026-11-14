import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// Snapshot before export; apply only after publishing the final filenames.
/// Windows preserves raw FILETIME precision and creation time as well as mtime.
class SourceFileTimestamps {
  const SourceFileTimestamps._(this.modified, this.created, this._windowsTimes);

  final DateTime modified;
  final DateTime? created;
  final (int, int, int, int)? _windowsTimes;

  static Future<SourceFileTimestamps> capture(String path) async {
    if (Platform.isWindows) return Isolate.run(() => _readWindows(path));
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Cannot read source file dates.', path);
    }
    // FileStat.changed is inode change time, not portable creation time.
    return SourceFileTimestamps._(stat.modified, null, null);
  }

  Future<void> applyTo(List<String> paths) async {
    final times = _windowsTimes;
    if (times != null) {
      await Isolate.run(() {
        for (final path in paths) {
          _writeWindows(path, times);
        }
      });
    } else {
      for (final path in paths) {
        await File(path).setLastModified(modified);
      }
    }
  }

  static SourceFileTimestamps _readWindows(String path) {
    final info = calloc<win32.BY_HANDLE_FILE_INFORMATION>();
    try {
      _withWindowsHandle(path, win32.GENERIC_READ, (handle) {
        final result = win32.GetFileInformationByHandle(handle, info);
        if (!result.value) {
          throw FileSystemException(
            'Cannot read source file dates.',
            path,
            OSError('', result.error),
          );
        }
      });
      final creation = info.ref.ftCreationTime;
      final modification = info.ref.ftLastWriteTime;
      return SourceFileTimestamps._(
        _date(modification.dwLowDateTime, modification.dwHighDateTime),
        _date(creation.dwLowDateTime, creation.dwHighDateTime),
        (
          creation.dwLowDateTime,
          creation.dwHighDateTime,
          modification.dwLowDateTime,
          modification.dwHighDateTime,
        ),
      );
    } finally {
      calloc.free(info);
    }
  }

  static DateTime _date(int low, int high) =>
      DateTime.fromMicrosecondsSinceEpoch(
        (((high << 32) | low) ~/ 10) - 11644473600000000,
        isUtc: true,
      );

  static void _writeWindows(String path, (int, int, int, int) times) {
    final created = calloc<win32.FILETIME>();
    final modified = calloc<win32.FILETIME>();
    try {
      created.ref
        ..dwLowDateTime = times.$1
        ..dwHighDateTime = times.$2;
      modified.ref
        ..dwLowDateTime = times.$3
        ..dwHighDateTime = times.$4;
      _withWindowsHandle(path, win32.FILE_WRITE_ATTRIBUTES, (handle) {
        final result = win32.SetFileTime(handle, created, null, modified);
        if (!result.value) {
          throw FileSystemException(
            'Cannot preserve source file dates.',
            path,
            OSError('', result.error),
          );
        }
      });
    } finally {
      calloc.free(created);
      calloc.free(modified);
    }
  }

  static void _withWindowsHandle(
    String path,
    int access,
    void Function(win32.HANDLE) action,
  ) {
    final name = path.toNativeUtf16();
    try {
      final result = win32.CreateFile(
        win32.PCWSTR(name),
        access,
        win32.FILE_SHARE_READ |
            win32.FILE_SHARE_WRITE |
            win32.FILE_SHARE_DELETE,
        null,
        win32.OPEN_EXISTING,
        win32.FILE_ATTRIBUTE_NORMAL,
        null,
      );
      final handle = result.value;
      if (!handle.isValid) {
        throw FileSystemException(
          'Cannot open file for dates.',
          path,
          OSError('', result.error),
        );
      }
      try {
        action(handle);
      } finally {
        win32.CloseHandle(handle);
      }
    } finally {
      calloc.free(name);
    }
  }
}
