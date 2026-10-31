import 'package:sqflite_common/sqlite_api.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;

import '../../helpers/core/text_utils.dart';
import '../../ui/screens/folder_list/folder_list_state.dart';

import 'torrent_entry.dart';
import 'torrent_sort.dart';
import 'torrent_metainfo.dart';
import 'magnet_link.dart';
import 'qbittorrent_resume.dart';

/// The index lives in the app database; metainfo and payloads may live on any
/// user-selected volume. Queries never materialize the whole library.
class TorrentRepository {
  static const schemaVersion = 4;
  static const maxPageSize = 1000;
  static const sortOptions = {
    SortOption.nameAsc,
    SortOption.nameDesc,
    SortOption.dateAsc,
    SortOption.dateDesc,
    SortOption.dateCreatedAsc,
    SortOption.dateCreatedDesc,
    SortOption.sizeAsc,
    SortOption.sizeDesc,
    SortOption.typeAsc,
    SortOption.typeDesc,
  };
  final Database db;
  TorrentRepository(this.db);

  Future<void> initialize() async {
    await db.execute('''CREATE TABLE IF NOT EXISTS torrents (
      hash TEXT PRIMARY KEY, name TEXT NOT NULL, torrent_path TEXT NOT NULL,
      category TEXT NOT NULL, group_name TEXT NOT NULL DEFAULT '',
      total_bytes INTEGER NOT NULL, file_count INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'library', download_dir TEXT, gid TEXT,
      completed_bytes INTEGER NOT NULL DEFAULT 0,
      download_speed INTEGER NOT NULL DEFAULT 0, error TEXT,
      added_at INTEGER NOT NULL, source_uri TEXT)''');
    await db.transaction((txn) async {
      final columns = await txn.rawQuery('PRAGMA table_info(torrents)');
      for (final definition in {
        'upload_speed': 'INTEGER NOT NULL DEFAULT 0',
        'uploaded_bytes': 'INTEGER',
        'seeders': 'INTEGER',
        'connections': 'INTEGER',
        'trackers': 'TEXT',
        'comment': 'TEXT',
        'created_by': 'TEXT',
        'torrent_created_at': 'INTEGER',
        'is_private': 'INTEGER',
        'piece_length': 'INTEGER',
        'piece_count': 'INTEGER',
        'metainfo_bytes': 'INTEGER',
        'metainfo_version': 'INTEGER NOT NULL DEFAULT 0',
        'qbittorrent_resume_path': 'TEXT',
        'qbittorrent_resume_digest': 'TEXT',
        'source_uris': 'TEXT',
        'sort_tracker': 'TEXT',
        'sort_tracker_count': 'INTEGER',
      }.entries) {
        if (!columns.any((column) => column['name'] == definition.key)) {
          await txn.execute(
            'ALTER TABLE torrents ADD COLUMN ${definition.key} ${definition.value}',
          );
        }
      }
      if (!columns.any((column) => column['name'] == 'sort_tracker') ||
          !columns.any((column) => column['name'] == 'sort_tracker_count')) {
        var after = '';
        while (true) {
          final rows = await txn.query(
            'torrents',
            columns: ['hash', 'trackers'],
            where: 'hash > ?',
            whereArgs: [after],
            orderBy: 'hash',
            limit: 256,
          );
          if (rows.isEmpty) break;
          final batch = txn.batch();
          for (final row in rows) {
            after = row['hash'] as String;
            batch.update(
              'torrents',
              _trackerSort(row['trackers'] as String?),
              where: 'hash = ?',
              whereArgs: [after],
            );
          }
          await batch.commit(noResult: true);
        }
      }
      if (!columns.any((column) => column['name'] == 'source_uri')) {
        await txn.execute('ALTER TABLE torrents ADD COLUMN source_uri TEXT');
      }
      if (!columns.any((column) => column['name'] == 'modified_at')) {
        await txn.execute(
          'ALTER TABLE torrents ADD COLUMN modified_at INTEGER',
        );
      }
      if (!columns.any((column) => column['name'] == 'search_name')) {
        await txn.execute('ALTER TABLE torrents ADD COLUMN search_name TEXT');
        await txn.execute('ALTER TABLE torrents ADD COLUMN search_group TEXT');
      }
      if (!columns.any((column) => column['name'] == 'sort_name')) {
        await txn.execute('ALTER TABLE torrents ADD COLUMN sort_name TEXT');
      }
      if (!columns.any((column) => column['name'] == 'search_name') ||
          !columns.any((column) => column['name'] == 'sort_name')) {
        // Upgrade old indexes in bounded batches without touching source files.
        var after = '';
        while (true) {
          final rows = await txn.query(
            'torrents',
            columns: ['hash', 'name', 'group_name'],
            where: 'hash > ?',
            whereArgs: [after],
            orderBy: 'hash',
            limit: 256,
          );
          if (rows.isEmpty) break;
          final batch = txn.batch();
          for (final row in rows) {
            after = row['hash'] as String;
            batch.update(
              'torrents',
              {
                'search_name': TextUtils.searchKey(row['name'] as String),
                'sort_name': (row['name'] as String).toLowerCase(),
                'search_group': TextUtils.searchKey(
                  row['group_name'] as String,
                ),
              },
              where: 'hash = ?',
              whereArgs: [after],
            );
          }
          await batch.commit(noResult: true);
        }
      }
    });
    await db.execute(
      'CREATE INDEX IF NOT EXISTS torrent_status ON torrents(status, hash)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS torrent_category ON torrents(category, hash)',
    );
    for (final definition in [
      'torrent_name_sort ON torrents(COALESCE(sort_name, lower(name)), hash)',
      'torrent_size ON torrents(total_bytes, hash)',
      'torrent_added ON torrents(added_at, hash)',
      'torrent_modified ON torrents(COALESCE(modified_at, added_at), hash)',
      'torrent_type_sort ON torrents(category, COALESCE(sort_name, lower(name)), hash)',
    ]) {
      await db.execute('CREATE INDEX IF NOT EXISTS $definition');
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS torrent_sources (
      path TEXT PRIMARY KEY, hash TEXT NOT NULL REFERENCES torrents(hash) ON DELETE CASCADE,
      modified INTEGER NOT NULL, size INTEGER NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS torrent_source_hash ON torrent_sources(hash)',
    );
  }

  Future<bool> sourceUnchanged(String path, int modified, int size) async {
    final rows = await db.query(
      'torrent_sources',
      columns: ['hash'],
      where: 'path = ? AND modified = ? AND size = ?',
      whereArgs: [path, modified, size],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Refresh needs names only, with no filesystem checks or metainfo rows.
  Future<Set<String>> knownFileNames() async {
    final names = <String>{};
    Future<void> append(String table, String cursor, String pathColumn) async {
      var after = '';
      while (true) {
        final rows = await db.query(
          table,
          columns: {cursor, pathColumn}.toList(),
          where: '$cursor > ?',
          whereArgs: [after],
          orderBy: cursor,
          limit: 2048,
        );
        if (rows.isEmpty) return;
        for (final row in rows) {
          after = row[cursor] as String;
          final path = row[pathColumn] as String;
          if (path.isNotEmpty) names.add(p.basename(path).toLowerCase());
        }
      }
    }

    await append('torrent_sources', 'path', 'path');
    await append('torrents', 'hash', 'torrent_path');
    return names;
  }

  /// Compact fingerprints only; scan startup reads the index in bounded pages.
  Stream<Map<String, Object?>> scanSources() async* {
    var after = '';
    while (true) {
      final rows = await db.rawQuery(
        '''SELECT s.path, s.hash, s.modified, s.size, t.torrent_path, t.metainfo_version
        FROM torrent_sources s JOIN torrents t ON t.hash = s.hash
        WHERE s.path > ? ORDER BY s.path LIMIT 512''',
        [after],
      );
      if (rows.isEmpty) return;
      for (final row in rows) {
        after = row['path'] as String;
        yield row;
      }
    }
  }

  Stream<String> storedPaths() async* {
    await for (final file in storedFiles()) {
      yield file.path;
    }
  }

  Stream<({String hash, String path})> storedFiles() async* {
    var after = '';
    while (true) {
      final rows = await db.query(
        'torrents',
        columns: ['hash', 'torrent_path'],
        where: 'hash > ?',
        whereArgs: [after],
        orderBy: 'hash',
        limit: 512,
      );
      if (rows.isEmpty) return;
      for (final row in rows) {
        after = row['hash'] as String;
        final path = row['torrent_path'] as String;
        if (path.isNotEmpty) yield (hash: after, path: path);
      }
    }
  }

  Future<void> recordSource(
    String hash,
    String path,
    int modified,
    int size,
  ) async {
    await db.insert('torrent_sources', {
      'path': path,
      'hash': hash,
      'modified': modified,
      'size': size,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<TorrentEntry> importMagnet(MagnetLink link, {bool touch = false}) =>
      db.transaction((txn) async {
        final rows = await txn.query(
          'torrents',
          where: 'hash = ?',
          whereArgs: [link.hash],
          limit: 1,
        );
        final previous = rows.isEmpty
            ? null
            : TorrentEntry.fromMap(rows.single);
        final name = previous == null || previous.name == link.hash
            ? link.name
            : previous.name;
        final trackers = <String>{
          ...linkTrackers(link.uri),
          ...?previous?.trackers,
        };
        MagnetLink combined = link;
        if (previous?.sourceUri != null) {
          try {
            final original = MagnetLink.parse(previous!.sourceUri!);
            if (original.hash == link.hash) {
              combined = original.merge(link, displayName: name);
            }
          } on FormatException {
            // Keep non-magnet source URLs in source_uris below.
          }
        }
        combined = combined.withTrackers(trackers);
        trackers.addAll(linkTrackers(combined.uri));
        final now = DateTime.now().millisecondsSinceEpoch;
        await txn.rawInsert(
          '''INSERT OR IGNORE INTO torrents
      (hash, name, torrent_path, category, total_bytes, file_count, added_at, source_uri)
      VALUES (?, ?, '', 'other', 0, 0, ?, ?)''',
          [link.hash, name, now, combined.uri],
        );
        await txn.update(
          'torrents',
          {
            'source_uri': combined.uri,
            'source_uris': jsonEncode(
              {...?previous?.sourceUris, link.uri}.toList(),
            ),
            'trackers': jsonEncode(trackers.toList()),
            ..._trackerSort(jsonEncode(trackers.toList())),
            'name': name,
            'search_name': TextUtils.searchKey(name),
            'sort_name': name.toLowerCase(),
            'search_group': TextUtils.searchKey(previous?.group ?? ''),
            if (touch) 'modified_at': now,
          },
          where: 'hash = ?',
          whereArgs: [link.hash],
        );
        return TorrentEntry.fromMap(
          (await txn.query(
            'torrents',
            where: 'hash = ?',
            whereArgs: [link.hash],
            limit: 1,
          )).single,
        );
      });

  static List<String> linkTrackers(String uri) =>
      Uri.parse(uri).queryParametersAll['tr'] ?? const [];

  Future<void> recordSourceUri(String hash, String uri) =>
      db.transaction((txn) async {
        final rows = await txn.query(
          'torrents',
          where: 'hash = ?',
          whereArgs: [hash],
          limit: 1,
        );
        if (rows.isEmpty) return;
        final previous = TorrentEntry.fromMap(rows.single);
        await txn.update(
          'torrents',
          {
            'source_uris': jsonEncode({...previous.sourceUris, uri}.toList()),
            'source_uri':
                previous.sourceUri?.toLowerCase().startsWith('magnet:') == true
                ? previous.sourceUri
                : uri,
          },
          where: 'hash = ?',
          whereArgs: [hash],
        );
      });

  Future<void> importQbittorrentResume(
    QbittorrentResume resume,
    String archive,
    String digest, {
    required bool missingMetainfo,
  }) async {
    final previous = await get(resume.magnet.hash);
    await importMagnet(resume.magnet);
    final values = <String, Object?>{
      'qbittorrent_resume_path': archive,
      'qbittorrent_resume_digest': digest,
      if (previous?.downloadDir == null && resume.downloadDirectory != null)
        'download_dir': resume.downloadDirectory,
      if ((previous?.group.isEmpty ?? true) && resume.group != null) ...{
        'group_name': resume.group,
        'search_group': TextUtils.searchKey(resume.group!),
      },
      if (missingMetainfo) ...{
        'torrent_path': '',
        'name': resume.magnet.name,
        'search_name': TextUtils.searchKey(resume.magnet.name),
        'sort_name': resume.magnet.name.toLowerCase(),
        'trackers': jsonEncode(resume.trackers),
      },
    };
    // Never translate qBit's piece flags/cumulative traffic into verified aria2
    // progress, and never reset this app's existing download task or counters.
    await update(resume.magnet.hash, values);
  }

  Future<bool> import(
    TorrentMetainfo info,
    String archivePath,
    String source,
    int modified,
    int size,
  ) => db.transaction((txn) async {
    final previousRows = await txn.query(
      'torrents',
      where: 'hash = ?',
      whereArgs: [info.hash],
      limit: 1,
    );
    final previous = previousRows.isEmpty
        ? null
        : TorrentEntry.fromMap(previousRows.single);
    await txn.rawInsert(
      '''INSERT OR IGNORE INTO torrents
      (hash, name, torrent_path, category, total_bytes, file_count, added_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        info.hash,
        info.name,
        archivePath,
        info.category,
        info.totalBytes,
        info.fileCount,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    // `changes()` is connection-local and read inside the same transaction.
    final changed =
        (await txn.rawQuery('SELECT changes() AS n')).first['n'] == 1;
    await txn.insert('torrent_sources', {
      'path': source,
      'hash': info.hash,
      'modified': modified,
      'size': size,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // Re-import repairs a missing archive without resetting download state.
    await txn.update(
      'torrents',
      {
        'torrent_path': archivePath,
        'name': info.name,
        'category': info.category,
        'total_bytes': info.totalBytes,
        'file_count': info.fileCount,
        'trackers': jsonEncode(
          {...?previous?.trackers, ...info.trackers}.toList(),
        ),
        ..._trackerSort(
          jsonEncode({...?previous?.trackers, ...info.trackers}.toList()),
        ),
        'comment': info.comment,
        'created_by': info.createdBy,
        'torrent_created_at': info.creationDate,
        'is_private': info.isPrivate == null ? null : (info.isPrivate! ? 1 : 0),
        'piece_length': info.pieceLength,
        'piece_count': info.pieceCount,
        'metainfo_bytes': size,
        'metainfo_version': 1,
        'search_name': TextUtils.searchKey(info.name),
        'sort_name': info.name.toLowerCase(),
      },
      where: 'hash = ?',
      whereArgs: [info.hash],
    );
    // A duplicate in an older source/archive must not push a newer torrent
    // down the list just because that directory was scanned last.
    await txn.rawUpdate(
      'UPDATE torrents SET modified_at = MAX(COALESCE(modified_at, 0), ?) WHERE hash = ?',
      [modified ~/ 1000, info.hash],
    );
    return changed;
  });

  Future<int?> offsetInNewestOrder(String hash) async {
    final rows = await db.query(
      'torrents',
      columns: ['added_at', 'modified_at'],
      where: 'hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final date = rows.single['modified_at'] ?? rows.single['added_at'];
    final count = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM torrents WHERE '
      'COALESCE(modified_at, added_at) > ? OR '
      '(COALESCE(modified_at, added_at) = ? AND hash < ?)',
      [date, date, hash],
    );
    return count.single['n'] as int;
  }

  Future<TorrentPage> page({
    int offset = 0,
    int limit = 80,
    String query = '',
    String? status,
    String? category,
    SortOption sort = SortOption.dateDesc,
    TorrentSort? detailSort,
    bool useRegex = false,
    bool Function()? isCancelled,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    final regex = useRegex && query.trim().isNotEmpty
        ? RegExp(query.trim(), caseSensitive: false)
        : null;
    if (regex == null && query.trim().isNotEmpty) {
      for (final word in TextUtils.searchKey(
        query,
      ).split(' ').where((s) => s.isNotEmpty)) {
        where.add(
          "instr(COALESCE(search_name, lower(name)) || ' ' || "
          "COALESCE(search_group, lower(group_name)) || ' ' || hash, ?) > 0",
        );
        args.add(word);
      }
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    if (category != null) {
      where.add('category = ?');
      args.add(category);
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    // SQLite NOCASE only folds ASCII. Match the file browser's Dart lowercase
    // comparison for non-ASCII names too, while sorting before pagination.
    const nameOrder = 'COALESCE(sort_name, lower(name))';
    final order =
        detailSort?.orderBy ??
        switch (sort) {
          SortOption.nameDesc => '$nameOrder DESC',
          SortOption.sizeAsc => 'total_bytes ASC',
          SortOption.sizeDesc => 'total_bytes DESC',
          SortOption.dateAsc => 'COALESCE(modified_at, added_at) ASC',
          SortOption.dateDesc => 'COALESCE(modified_at, added_at) DESC',
          SortOption.dateCreatedAsc => 'added_at ASC',
          SortOption.dateCreatedDesc => 'added_at DESC',
          SortOption.typeAsc => 'category ASC, $nameOrder ASC',
          SortOption.typeDesc => 'category DESC, $nameOrder ASC',
          _ => '$nameOrder ASC',
        };
    final start = offset < 0 ? 0 : offset;
    final take = limit.clamp(1, maxPageSize);
    // A transaction keeps count/page consistent while scanning imports rows.
    return db.transaction((txn) async {
      if (regex != null) {
        final entries = <TorrentEntry>[];
        var count = 0, scanned = 0;
        while (true) {
          if (isCancelled?.call() ?? false) return const TorrentPage([], 0);
          final rows = await txn.rawQuery(
            'SELECT * FROM torrents $clause ORDER BY $order, hash LIMIT 256 OFFSET ?',
            [...args, scanned],
          );
          if (rows.isEmpty) break;
          scanned += rows.length;
          for (final row in rows) {
            if (![
              'name',
              'group_name',
              'hash',
            ].any((field) => regex.hasMatch(row[field] as String))) {
              continue;
            }
            if (count >= start && entries.length < take) {
              entries.add(TorrentEntry.fromMap(row));
            }
            count++;
          }
        }
        return TorrentPage(entries, count);
      }
      final count =
          (await txn.rawQuery(
                'SELECT COUNT(*) AS n FROM torrents $clause',
                args,
              )).first['n']
              as int;
      final rows = await txn.rawQuery(
        'SELECT * FROM torrents $clause ORDER BY $order, hash LIMIT ? OFFSET ?',
        [...args, take, start],
      );
      return TorrentPage(rows.map(TorrentEntry.fromMap).toList(), count);
    });
  }

  Future<TorrentEntry?> get(String hash) async {
    final rows = await db.query(
      'torrents',
      where: 'hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return rows.isEmpty ? null : TorrentEntry.fromMap(rows.first);
  }

  Future<void> update(String hash, Map<String, Object?> values) async {
    // The first import owns this timestamp, including imports from other clients.
    final changes = Map<String, Object?>.of(values)..remove('added_at');
    if (changes.isEmpty) return;
    await db.update(
      'torrents',
      {
        ...changes,
        if (values.containsKey('trackers'))
          ..._trackerSort(values['trackers'] as String?),
        if (values['name'] is String)
          'search_name': TextUtils.searchKey(values['name'] as String),
        if (values['name'] is String)
          'sort_name': (values['name'] as String).toLowerCase(),
        if (values['group_name'] is String)
          'search_group': TextUtils.searchKey(values['group_name'] as String),
      },
      where: 'hash = ?',
      whereArgs: [hash],
    );
  }

  static Map<String, Object?> _trackerSort(String? encoded) {
    final trackers = encoded == null ? const [] : jsonDecode(encoded) as List;
    return {
      'sort_tracker': trackers.isEmpty
          ? null
          : (trackers.first as String).toLowerCase(),
      'sort_tracker_count': trackers.length,
    };
  }

  Future<List<TorrentEntry>> pending({
    String after = '',
    int limit = 64,
  }) async {
    final rows = await db.query(
      'torrents',
      where: "status IN ('active', 'waiting', 'paused') AND hash > ?",
      whereArgs: [after],
      orderBy: 'hash',
      limit: limit,
    );
    return rows.map(TorrentEntry.fromMap).toList();
  }

  Future<List<String>> sources(String hash) async => (await db.query(
    'torrent_sources',
    columns: ['path'],
    where: 'hash = ?',
    whereArgs: [hash],
    limit: 200,
  )).map((r) => r['path'] as String).toList();

  Future<void> remove(String hash) => db.transaction((txn) async {
    await txn.delete('torrent_sources', where: 'hash = ?', whereArgs: [hash]);
    await txn.delete('torrents', where: 'hash = ?', whereArgs: [hash]);
  });
}
