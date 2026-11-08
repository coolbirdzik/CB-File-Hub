import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../models/database/sqlite_database_provider.dart';
import 'media_kit_playback.dart';
import 'subtitle_progress.dart';

class LocalSubtitleCue {
  final int startMs, endMs;
  final String original, text;
  const LocalSubtitleCue(this.startMs, this.endMs, this.original, this.text);
  List<Object> toJson() => [startMs, endMs, original, text];
  factory LocalSubtitleCue.fromJson(List<dynamic> value) => LocalSubtitleCue(
    value[0] as int,
    value[1] as int,
    value[2] as String,
    value[3] as String,
  );
}

class SubtitleCacheSnapshot {
  final int revision;
  final List<SubtitleTimeRange> ranges;
  final List<LocalSubtitleCue> cues;
  const SubtitleCacheSnapshot(this.revision, this.ranges, this.cues);
}

class SubtitleCacheStats {
  final int entries, bytes;
  const SubtitleCacheStats(this.entries, this.bytes);
}

/// Disposable text in the application's shared SQLite DB, including silent
/// completed chunks. Each chunk is committed only after translation succeeds.
class SubtitleCache {
  static final instance = SubtitleCache();
  final Future<Database> Function() _open;
  Future<Database>? _ready;
  SubtitleCache({Future<Database> Function()? openDatabase})
    : _open = openDatabase ?? SqliteDatabaseProvider().getDatabase;

  Future<Database> _database() =>
      _ready ??= _initialize().catchError((Object e) {
        _ready = null;
        throw e;
      });

  Future<Database> _initialize() async {
    final db = await _open();
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?)",
      ['subtitle_cache_meta', 'subtitle_cache_chunks'],
    );
    if (tables.length == 2 &&
        (await db.query(
          'subtitle_cache_meta',
          columns: ['id'],
          where: 'id = 1',
        )).isNotEmpty) {
      return db;
    }
    await db.transaction((txn) async {
      await txn.execute('''CREATE TABLE IF NOT EXISTS subtitle_cache_meta (
        id INTEGER PRIMARY KEY CHECK(id = 1), revision INTEGER NOT NULL)''');
      await txn.rawInsert(
        'INSERT OR IGNORE INTO subtitle_cache_meta VALUES(1, 0)',
      );
      await txn.execute('''CREATE TABLE IF NOT EXISTS subtitle_cache_chunks (
        cache_key TEXT NOT NULL, start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL, cues TEXT NOT NULL, bytes INTEGER NOT NULL,
        PRIMARY KEY(cache_key, start_ms))''');
    });
    return db;
  }

  Future<int> revision() async => _revision(await _database());
  Future<int> _revision(DatabaseExecutor db) async =>
      (await db.query('subtitle_cache_meta')).single['revision'] as int;

  Future<SubtitleCacheSnapshot> read(String key, int from, int to) async {
    final db = await _database();
    // Revision, coverage and windowed cues must come from one SQLite snapshot.
    // Decode/merge after the SELECT releases the shared connection's lock.
    final rows = await db.rawQuery(
      '''SELECT m.revision, c.start_ms, c.end_ms,
      CASE WHEN c.end_ms > ? AND c.start_ms < ? THEN c.cues END AS cues
      FROM subtitle_cache_meta m
      LEFT JOIN subtitle_cache_chunks c ON c.cache_key = ?
      WHERE m.id = 1 ORDER BY c.start_ms''',
      [from, to, key],
    );
    final ranges = <SubtitleTimeRange>[];
    final cues = <LocalSubtitleCue>[];
    for (final row in rows) {
      if (row['start_ms'] == null) continue;
      final start = Duration(milliseconds: row['start_ms'] as int);
      final end = Duration(milliseconds: row['end_ms'] as int);
      if (ranges.isNotEmpty && ranges.last.end >= start) {
        final old = ranges.removeLast();
        ranges.add(SubtitleTimeRange(old.start, old.end > end ? old.end : end));
      } else {
        ranges.add(SubtitleTimeRange(start, end));
      }
      final payload = row['cues'] as String?;
      if (payload != null) {
        cues.addAll(
          (jsonDecode(payload) as List).map(
            (c) => LocalSubtitleCue.fromJson(c as List<dynamic>),
          ),
        );
      }
    }
    return SubtitleCacheSnapshot(rows.first['revision'] as int, ranges, cues);
  }

  /// Revision checked inside the write transaction: a late worker, including
  /// one in a different video process, cannot resurrect cleared cache.
  Future<bool> save(
    String key,
    int revision,
    int start,
    int end,
    List<LocalSubtitleCue> cues,
  ) async {
    final payload = jsonEncode(cues.map((c) => c.toJson()).toList());
    final db = await _database();
    return db.transaction((txn) async {
      if (await _revision(txn) != revision) return false;
      // Concurrent players must reuse the first completed result.
      final overlap = await txn.query(
        'subtitle_cache_chunks',
        columns: ['start_ms'],
        where: 'cache_key = ? AND end_ms > ? AND start_ms < ?',
        whereArgs: [key, start, end],
        limit: 1,
      );
      if (overlap.isNotEmpty) return false;
      await txn.insert('subtitle_cache_chunks', {
        'cache_key': key,
        'start_ms': start,
        'end_ms': end,
        'cues': payload,
        'bytes': utf8.encode(payload).length,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  Future<void> clear({String? key}) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete(
        'subtitle_cache_chunks',
        where: key == null ? null : 'cache_key = ?',
        whereArgs: key == null ? null : [key],
      );
      await txn.rawUpdate(
        'UPDATE subtitle_cache_meta SET revision = revision + 1',
      );
    });
  }

  Future<SubtitleCacheStats> stats() async {
    final db = await _database();
    final row = (await db.rawQuery(
      '''SELECT COUNT(DISTINCT cache_key) AS entries,
      COALESCE(SUM(bytes), 0) AS bytes FROM subtitle_cache_chunks''',
    )).single;
    return SubtitleCacheStats(row['entries'] as int, row['bytes'] as int);
  }
}

String subtitleCacheDigest(List<Object?> parts) =>
    sha256.convert(utf8.encode(jsonEncode(parts))).toString();

/// Never store source paths, URL credentials or tokens in the cache. Local and
/// UNC files are validated by size/mtime. HTTP needs an origin validator; an
/// unversioned URL is deliberately not reused across playback sessions.
Future<String?> subtitleSourceFingerprint(
  String original,
  String resolved,
) async {
  final uri = playbackSourceUri(original);
  final resolvedUri = playbackSourceUri(resolved);
  if (resolvedUri.scheme == 'file') {
    final stat = await File.fromUri(resolvedUri).stat();
    if (stat.type != FileSystemEntityType.file) return null;
    return subtitleCacheDigest([
      uri.toString(),
      stat.size,
      stat.modified.microsecondsSinceEpoch,
    ]);
  }
  if (resolvedUri.scheme != 'http' && resolvedUri.scheme != 'https') {
    return null;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client
        .headUrl(resolvedUri)
        .timeout(const Duration(seconds: 3));
    final response = await request.close().timeout(const Duration(seconds: 3));
    final etag = response.headers.value(HttpHeaders.etagHeader);
    final modified = response.headers.value(HttpHeaders.lastModifiedHeader);
    if (response.statusCode != 200 || (etag == null && modified == null)) {
      return null;
    }
    return subtitleCacheDigest([
      uri.toString(),
      etag,
      modified,
      response.contentLength,
    ]);
  } finally {
    client.close(force: true);
  }
}
