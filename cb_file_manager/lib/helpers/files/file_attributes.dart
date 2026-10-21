import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as pathlib;
import 'package:win32/win32.dart' as win32;

/// Short attribute letters for the Details view's Attributes column, like
/// Windows Explorer's (R, H, S, A, C, E, O, L).
///
/// On Windows they come from `GetFileAttributesW`; elsewhere only read-only
/// (from the mode bits) and hidden (dot files) apply.
class FileAttributes {
  FileAttributes._();

  static const _maxCacheSize = 4000;
  static final Map<String, String> _cache = {};

  static const _letters = <int, String>{
    0x1: 'R', // FILE_ATTRIBUTE_READONLY
    0x2: 'H', // FILE_ATTRIBUTE_HIDDEN
    0x4: 'S', // FILE_ATTRIBUTE_SYSTEM
    0x20: 'A', // FILE_ATTRIBUTE_ARCHIVE
    0x800: 'C', // FILE_ATTRIBUTE_COMPRESSED
    0x4000: 'E', // FILE_ATTRIBUTE_ENCRYPTED
    0x1000: 'O', // FILE_ATTRIBUTE_OFFLINE
    0x400: 'L', // FILE_ATTRIBUTE_REPARSE_POINT
  };

  /// The attribute letters of [path]. [stat] is used where the platform has
  /// no attribute call. Results are cached per path; [invalidate] drops one.
  static String describe(String path, FileStat? stat) {
    final cached = _cache[path];
    if (cached != null) return cached;
    final windows = _windowsAttributes(path);
    final value = windows ?? _fromStat(path, stat);
    if (windows == null && stat == null) return value;
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return _cache[path] = value;
  }

  static void invalidate(String path) => _cache.remove(path);

  static String? _windowsAttributes(String path) {
    // UNC paths would cost a network round trip on the UI thread.
    if (!Platform.isWindows || path.startsWith(r'\\')) return null;
    final pathPtr = path.toNativeUtf16();
    try {
      final int attributes = win32.GetFileAttributes(
        win32.PCWSTR(pathPtr),
      ).value;
      if (attributes == 0xFFFFFFFF) return null;
      return [
        for (final entry in _letters.entries)
          if (attributes & entry.key != 0) entry.value,
      ].join();
    } catch (_) {
      return null;
    } finally {
      malloc.free(pathPtr);
    }
  }

  static String _fromStat(String path, FileStat? stat) {
    final readOnly = stat != null && stat.mode & 0x80 == 0; // owner write
    final hidden = pathlib.basename(path).startsWith('.');
    return '${readOnly ? 'R' : ''}${hidden ? 'H' : ''}';
  }
}
