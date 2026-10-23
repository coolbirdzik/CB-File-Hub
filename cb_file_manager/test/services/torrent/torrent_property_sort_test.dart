import 'dart:convert';

import 'package:cb_file_manager/services/torrent/torrent_repository.dart';
import 'package:cb_file_manager/services/torrent/torrent_sort.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late TorrentRepository repo;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    repo = TorrentRepository(db);
    await repo.initialize();
  });
  tearDown(() => db.close());

  Future<void> insert(
    String hash,
    String name,
    Map<String, Object?> values,
  ) async {
    await db.insert('torrents', {
      'hash': hash,
      'name': name,
      'torrent_path': '/archive/$hash.torrent',
      'category': 'video',
      'total_bytes': 200,
      'file_count': 1,
      'added_at': 1,
      'status': 'active',
      'download_dir': '/downloads',
      'completed_bytes': 20,
      'piece_count': 1,
    });
    if (values.isNotEmpty) await repo.update(hash, values);
  }

  final pairs = <String, (Map<String, Object?>, Map<String, Object?>)>{
    'status': ({'status': 'active'}, {'status': 'waiting'}),
    'progress': ({'completed_bytes': 20}, {'completed_bytes': 100}),
    'downSpeed': ({'download_speed': 20}, {'download_speed': 100}),
    'upSpeed': ({'upload_speed': 20}, {'upload_speed': 100}),
    'seeds': ({'seeders': 2}, {'seeders': 10}),
    'peers': ({'connections': 2}, {'connections': 10}),
    'eta': ({'download_speed': 20}, {'download_speed': 2}),
    'downloaded': ({'completed_bytes': 20}, {'completed_bytes': 100}),
    'uploaded': ({'uploaded_bytes': 20}, {'uploaded_bytes': 100}),
    'ratio': ({'uploaded_bytes': 5}, {'uploaded_bytes': 30}),
    'files': ({'file_count': 2}, {'file_count': 10}),
    'group': ({'group_name': 'Alpha'}, {'group_name': 'Zulu'}),
    'destination': ({'download_dir': '/a'}, {'download_dir': '/z'}),
    'hash': ({}, {}),
    'remaining': ({'completed_bytes': 190}, {'completed_bytes': 20}),
    'tracker': (
      {
        'trackers': jsonEncode(['https://a.example']),
      },
      {
        'trackers': jsonEncode(['https://z.example']),
      },
    ),
    'trackerCount': (
      {
        'trackers': jsonEncode(['a', 'b']),
      },
      {'trackers': jsonEncode(List.generate(10, (i) => '$i'))},
    ),
    'torrentCreated': ({'torrent_created_at': 20}, {'torrent_created_at': 100}),
    'createdBy': ({'created_by': 'Alpha'}, {'created_by': 'Zulu'}),
    'comment': ({'comment': 'Alpha'}, {'comment': 'Zulu'}),
    'private': ({'is_private': 0}, {'is_private': 1}),
    'pieceSize': ({'piece_length': 20}, {'piece_length': 100}),
    'pieceCount': ({'piece_count': 2}, {'piece_count': 10}),
    'metainfoSize': ({'metainfo_bytes': 20}, {'metainfo_bytes': 100}),
    'torrentFile': (
      {'torrent_path': '/a.torrent'},
      {'torrent_path': '/z.torrent'},
    ),
    'source': (
      {'source_uri': 'https://a.example'},
      {'source_uri': 'https://z.example'},
    ),
    'error': ({'error': 'Alpha'}, {'error': 'Zulu'}),
    'taskId': ({'gid': 'a'}, {'gid': 'z'}),
  };
  for (final pair in pairs.entries) {
    test(
      '${pair.key} sorts both ways before normal and regex pagination',
      () async {
        final low = '1' * 40, high = '2' * 40;
        await insert(low, 'Z Torrent', pair.value.$1);
        await insert(high, 'A Torrent', pair.value.$2);
        for (final ascending in [true, false]) {
          for (final regex in [false, true]) {
            final sort = TorrentSort(pair.key, ascending: ascending);
            final first = await repo.page(
              limit: 1,
              detailSort: sort,
              query: 'Torrent',
              useRegex: regex,
            );
            final next = await repo.page(
              offset: 1,
              limit: 1,
              detailSort: sort,
              query: 'Torrent',
              useRegex: regex,
            );
            expect(first.total, 2);
            expect(first.entries.single.hash, ascending ? low : high);
            expect(next.entries.single.hash, ascending ? high : low);
          }
        }
      },
    );
  }

  test(
    'unknown live measurements stay last, zero remains a known value',
    () async {
      await insert('1' * 40, 'Zero', {'seeders': 0});
      await insert('2' * 40, 'Ten', {'seeders': 10});
      await insert('3' * 40, 'Unknown', {'seeders': null});
      await insert('4' * 40, 'Paused', {'seeders': 100, 'status': 'paused'});
      for (final ascending in [true, false]) {
        final result = await repo.page(
          detailSort: TorrentSort('seeds', ascending: ascending),
        );
        expect(
          result.entries.take(2).map((e) => e.name),
          ascending ? ['Zero', 'Ten'] : ['Ten', 'Zero'],
        );
        expect(result.entries.skip(2).map((e) => e.name), [
          'Paused',
          'Unknown',
        ]);
      }
    },
  );

  test('rejects sort expressions outside the whitelist', () async {
    await expectLater(
      repo.page(detailSort: const TorrentSort('name; DROP TABLE torrents')),
      throwsArgumentError,
    );
    expect((await repo.page()).total, 0);
  });

  test('every torrent detail property is covered', () {
    expect(pairs.keys.toSet(), TorrentSort.expressions.keys.toSet());
  });

  test(
    'upgrades old tracker metadata without requiring source files',
    () async {
      await db.execute('DROP TABLE torrent_sources');
      await db.execute('DROP TABLE torrents');
      await db.execute('''CREATE TABLE torrents (
      hash TEXT PRIMARY KEY, name TEXT NOT NULL, torrent_path TEXT NOT NULL,
      category TEXT NOT NULL, group_name TEXT NOT NULL DEFAULT '',
      total_bytes INTEGER NOT NULL, file_count INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'library', download_dir TEXT, gid TEXT,
      completed_bytes INTEGER NOT NULL DEFAULT 0,
      download_speed INTEGER NOT NULL DEFAULT 0, error TEXT,
      added_at INTEGER NOT NULL, trackers TEXT, piece_count INTEGER)''');
      for (var i = 0; i < 300; i++) {
        await db.insert('torrents', {
          'hash': i.toString().padLeft(40, '0'),
          'name': 'Torrent $i',
          'torrent_path': '/missing/$i.torrent',
          'category': 'other',
          'total_bytes': 1,
          'file_count': 1,
          'added_at': 1,
          'piece_count': 1,
          'trackers': jsonEncode([
            'https://${(299 - i).toString().padLeft(3, '0')}.example',
          ]),
        });
      }
      await repo.initialize();
      await repo.initialize();
      final result = await repo.page(
        limit: 1,
        detailSort: const TorrentSort('tracker'),
      );
      expect(result.entries.single.hash, '299'.padLeft(40, '0'));
      expect(result.total, 300);
      expect(
        (await db.query(
          'torrents',
          columns: ['sort_tracker_count'],
        )).every((row) => row['sort_tracker_count'] == 1),
        isTrue,
      );
    },
  );
}
