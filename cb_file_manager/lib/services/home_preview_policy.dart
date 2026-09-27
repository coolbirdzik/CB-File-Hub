import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import 'smart_album_service.dart';

/// Checks every preview source, including loose folder-cache entries. A path
/// shared with any NSFW collection is excluded even if a safe album uses it too.
class HomePreviewPolicy {
  final Database database;
  final Set<String> _covers = {};
  final List<String> _roots = [];

  HomePreviewPolicy._(this.database);

  static String _key(String path) {
    final normalized = path.replaceAll('\\', '/');
    final result = p.posix.normalize(normalized);
    return Platform.isWindows ? result.toLowerCase() : result;
  }

  static Future<HomePreviewPolicy> load(Database database) async {
    final policy = HomePreviewPolicy._(database);
    final covers = await database.rawQuery('''
      SELECT cover_image_path FROM albums WHERE is_nsfw = 1
      UNION ALL
      SELECT cover_image_path FROM video_libraries WHERE is_nsfw = 1
    ''');
    policy._covers.addAll(
      covers
          .map((row) => row['cover_image_path'])
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .map(_key),
    );
    final roots = await database.rawQuery('''
      SELECT c.directories FROM album_configs c
      JOIN albums a ON a.id = c.album_id WHERE a.is_nsfw = 1
      UNION ALL
      SELECT c.directories FROM video_library_configs c
      JOIN video_libraries v ON v.id = c.video_library_id WHERE v.is_nsfw = 1
    ''');
    for (final row in roots) {
      // Conservatively exclude the entire source tree from ambient previews.
      policy._roots.addAll(
        (row['directories'] as String)
            .split(',')
            .map((path) => path.trim())
            .where((path) => path.isNotEmpty)
            .map(_key),
      );
    }
    final albums = await database.query(
      'albums',
      columns: ['id'],
      where: 'is_nsfw = 1',
    );
    for (final album in albums) {
      final roots = await SmartAlbumService.instance.getScanRoots(
        album['id'] as int,
      );
      policy._roots.addAll(roots.where((path) => path.isNotEmpty).map(_key));
    }
    return policy;
  }

  Future<List<String>> filter(Iterable<String> candidates) async {
    final paths = candidates.where((path) => path.isNotEmpty).toSet().toList();
    if (paths.isEmpty) return [];
    final keys = paths.map(_key).toSet();
    final denied = <String>{..._covers};
    // SQLite LOWER/NOCASE only handles ASCII. Normalize in Dart so Vietnamese
    // Windows paths and equivalent separators/dot segments cannot bypass NSFW.
    // Read membership in pages to keep memory bounded even for large galleries.
    for (final source in [
      ('album_files', 'albums', 'album_id'),
      ('video_library_files', 'video_libraries', 'video_library_id'),
    ]) {
      var lastId = 0;
      while (true) {
        final rows = await database.rawQuery(
          '''
          SELECT f.id, f.file_path FROM ${source.$1} f
          JOIN ${source.$2} g ON g.id = f.${source.$3}
          WHERE g.is_nsfw = 1 AND f.id > ? ORDER BY f.id LIMIT 256
        ''',
          [lastId],
        );
        for (final row in rows) {
          final key = _key(row['file_path'] as String);
          if (keys.contains(key)) denied.add(key);
        }
        if (rows.length < 256 || keys.every(denied.contains)) break;
        lastId = rows.last['id'] as int;
      }
    }
    return paths
        .where((path) {
          final key = _key(path);
          return !denied.contains(key) &&
              !_roots.any(
                (root) =>
                    key == root ||
                    key.startsWith(root.endsWith('/') ? root : '$root/'),
              );
        })
        .toList(growable: false);
  }
}
