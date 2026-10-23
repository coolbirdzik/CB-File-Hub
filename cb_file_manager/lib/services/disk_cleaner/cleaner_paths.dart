import 'dart:io';
import 'package:path/path.dart' as p;

/// Filesystem identity for Cleaner. POSIX paths stay case-sensitive; the APFS
/// Data-volume mount and its firmlink paths identify the same data.
abstract final class CleanerPaths {
  static bool supports(String operatingSystem) =>
      operatingSystem == 'windows' || operatingSystem == 'macos';
  static bool get isSupported => supports(Platform.operatingSystem);
  static String get defaultRoot => Platform.isWindows ? r'C:\' : '/';
  static bool isPosix(String path) => path.startsWith('/');
  static String key(String path) {
    if (isPosix(path)) {
      var value = p.posix.normalize(path);
      const data = '/System/Volumes/Data';
      if (value == data) return '/';
      if (value.startsWith('$data/')) value = value.substring(data.length);
      return value;
    }
    var value = path.trim().replaceAll('/', r'\').toUpperCase();
    while (value.length > 3 && value.endsWith(r'\')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String prefix(String path) {
    final value = key(path);
    final separator = isPosix(value) ? '/' : r'\';
    return value.endsWith(separator) ? value : '$value$separator';
  }

  static bool contains(String parent, String child) =>
      key(parent) == key(child) || key(child).startsWith(prefix(parent));
  static Iterable<String> ancestors(String path) sync* {
    var current = key(path);
    final context = isPosix(current) ? p.posix : p.windows;
    while (current.isNotEmpty) {
      yield current;
      final parent = context.dirname(current);
      if (parent == current || parent == '.') break;
      current = parent;
    }
  }
}
