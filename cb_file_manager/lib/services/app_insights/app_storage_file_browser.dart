import 'dart:io';
import 'dart:isolate';

import 'package:cb_native/cb_native.dart';
import 'package:path/path.dart' as p;

class AppStorageFileEntry {
  final String path;
  final bool isDirectory;

  /// Directory sizes require a recursive scan; leave them unknown here.
  final int? sizeBytes;

  const AppStorageFileEntry({
    required this.path,
    required this.isDirectory,
    this.sizeBytes,
  });

  String get name => p.basename(path);
}

/// Lists only the folder being inspected, including hidden/config files.
/// Links are omitted and file contents are never read.
class AppStorageFileBrowser {
  static Future<List<AppStorageFileEntry>> listDirectory(
    String path, {
    bool useNative = true,
  }) async {
    if (useNative) {
      final native = await NativeFs.listDirectory(path, stats: true);
      if (native != null) {
        return [
          for (final entry in native.folders)
            AppStorageFileEntry(path: entry.path, isDirectory: true),
          for (final entry in native.files)
            AppStorageFileEntry(
              path: entry.path,
              isDirectory: false,
              sizeBytes: entry.size,
            ),
        ];
      }
    }
    return Isolate.run(() => _listDirectory(path));
  }

  static List<AppStorageFileEntry> _listDirectory(String path) {
    final entries = <AppStorageFileEntry>[];
    for (final entity in Directory(path).listSync(followLinks: false)) {
      if (entity is Directory) {
        entries.add(AppStorageFileEntry(path: entity.path, isDirectory: true));
      } else if (entity is File) {
        final stat = entity.statSync();
        if (stat.type != FileSystemEntityType.file) {
          throw FileSystemException(
            'Could not read file metadata',
            entity.path,
          );
        }
        entries.add(
          AppStorageFileEntry(
            path: entity.path,
            isDirectory: false,
            sizeBytes: stat.size,
          ),
        );
      }
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }
}
