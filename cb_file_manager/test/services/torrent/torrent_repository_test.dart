import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cb_file_manager/services/torrent/torrent_metainfo.dart';
import 'package:cb_file_manager/services/torrent/torrent_repository.dart';
import 'package:cb_file_manager/services/torrent/magnet_link.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'torrent_fixtures.dart';

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

  test('scan fingerprints and stored paths include every index page', () async {
    final batch = db.batch();
    for (var i = 0; i < 2050; i++) {
      final hash = i.toString().padLeft(40, '0');
      batch.insert('torrents', {
        'hash': hash,
        'name': 'Torrent $i',
        'torrent_path': '/archive/$hash.torrent',
        'category': 'other',
        'total_bytes': 1,
        'file_count': 1,
        'added_at': 1,
        'metainfo_version': 1,
      });
      for (final folder in ['a', 'b']) {
        batch.insert('torrent_sources', {
          'path': '/$folder/$hash.torrent',
          'hash': hash,
          'modified': i,
          'size': 100,
        });
      }
    }
    await batch.commit(noResult: true);
    final fingerprints = await repo.scanSources().toList();
    final paths = await repo.storedPaths().toList();
    expect(fingerprints, hasLength(4100));
    expect(fingerprints.map((row) => row['path']).toSet(), hasLength(4100));
    expect(paths.toSet(), hasLength(2050));
    expect(await repo.knownFileNames(), hasLength(2050));
    expect((await repo.page()).entries, hasLength(80));
  });

  test('migrates the previous index without losing entries', () async {
    await db.execute('DROP TABLE torrent_sources');
    await db.execute('DROP TABLE torrents');
    await db.execute('''CREATE TABLE torrents (
      hash TEXT PRIMARY KEY, name TEXT NOT NULL, torrent_path TEXT NOT NULL,
      category TEXT NOT NULL, group_name TEXT NOT NULL DEFAULT '',
      total_bytes INTEGER NOT NULL, file_count INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'library', download_dir TEXT, gid TEXT,
      completed_bytes INTEGER NOT NULL DEFAULT 0,
      download_speed INTEGER NOT NULL DEFAULT 0, error TEXT,
      added_at INTEGER NOT NULL)''');
    await db.insert('torrents', {
      'hash': 'a' * 40,
      'name': 'Existing torrent',
      'torrent_path': '/existing.torrent',
      'category': 'video',
      'total_bytes': 100,
      'file_count': 2,
      'added_at': 1,
    });
    await repo.initialize();
    await repo.initialize();
    expect((await repo.page()).entries.single.name, 'Existing torrent');
    expect((await repo.page()).entries.single.sourceUri, isNull);
    final entry = (await repo.page()).entries.single;
    expect(entry.seeders, isNull);
    expect(entry.connections, isNull);
    expect(entry.uploadedBytes, isNull);
    expect(entry.uploadSpeed, 0);
    expect(entry.pieceCount, isNull);
    expect(entry.trackers, isEmpty);
    expect(entry.isPrivate, isNull);
    final columns = await db.rawQuery('PRAGMA table_info(torrents)');
    expect(columns.where((c) => c['name'] == 'source_uri').length, 1);
    for (final name in [
      'seeders',
      'connections',
      'upload_speed',
      'uploaded_bytes',
    ]) {
      expect(columns.where((c) => c['name'] == name).length, 1);
    }
    expect((await repo.page(query: 'torrent existing')).total, 1);
  });

  test(
    'deduplicates by info hash and retains source locations and task state',
    () async {
      final info = TorrentMetainfo.parse(torrentBytes());
      expect(
        await repo.import(info, '/archive/a', '/source/a', 10, 200),
        isTrue,
      );
      final addedAt = (await repo.get(info.hash))!.addedAt;
      await repo.update(info.hash, {
        'status': 'paused',
        'download_dir': '/downloads',
        'completed_bytes': 3,
      });
      expect(
        await repo.import(info, '/archive/b', '/source/b', 11, 201),
        isFalse,
      );
      expect((await repo.page()).total, 1);
      expect(await repo.sources(info.hash), ['/source/a', '/source/b']);
      final entry = (await repo.get(info.hash))!;
      expect(entry.status, 'paused');
      expect(entry.completedBytes, 3);
      expect(entry.torrentPath, '/archive/b');
      expect(entry.addedAt, addedAt);
      expect(await repo.sourceUnchanged('/source/b', 11, 201), isTrue);
      expect(await repo.sourceUnchanged('/source/b', 12, 201), isFalse);
    },
  );

  test('first addition survives magnet merges, metainfo and updates', () async {
    final info = TorrentMetainfo.parse(torrentBytes());
    final first = await repo.importMagnet(
      MagnetLink.fromMetadata(hash: info.hash, name: info.name),
    );
    await repo.importMagnet(
      MagnetLink.fromMetadata(
        hash: info.hash,
        name: info.name,
        trackers: ['https://tracker.example/announce'],
      ),
      touch: true,
    );
    expect((await repo.get(info.hash))!.addedAt, first.addedAt);
    await repo.import(info, '/archive', '/source', 1000000, 200);
    expect((await repo.get(info.hash))!.addedAt, first.addedAt);
    await repo.update(info.hash, {'added_at': 1, 'status': 'paused'});
    await repo.update(info.hash, {'added_at': 2});
    final updated = (await repo.get(info.hash))!;
    expect(updated.addedAt, first.addedAt);
    expect(updated.status, 'paused');
    await repo.initialize();
    expect((await repo.get(info.hash))!.addedAt, first.addedAt);
  });

  test(
    'persists torrent metadata columns and preserves task counters on reimport',
    () async {
      final info = TorrentMetainfo(
        'b' * 40,
        'With metadata',
        100,
        2,
        'video',
        trackers: ['https://tracker.example/announce'],
        comment: 'Test',
        createdBy: 'Client',
        creationDate: 1700000000000,
        isPrivate: true,
        pieceLength: 16384,
        pieceCount: 1,
      );
      await repo.import(info, '/archive', '/source', 10, 250);
      await repo.update(info.hash, {
        'status': 'active',
        'completed_bytes': 40,
        'seeders': 3,
      });
      await repo.import(info, '/archive', '/source', 5000000, 250);
      await repo.import(info, '/archive', '/older-source', 1000000, 250);
      final entry = (await repo.get(info.hash))!;
      expect(entry.trackers, info.trackers);
      expect(entry.comment, 'Test');
      expect(entry.createdBy, 'Client');
      expect(entry.torrentCreatedAt!.millisecondsSinceEpoch, 1700000000000);
      expect(entry.isPrivate, isTrue);
      expect(entry.pieceLength, 16384);
      expect(entry.pieceCount, 1);
      expect(entry.metainfoBytes, 250);
      expect(entry.status, 'active');
      expect(entry.completedBytes, 40);
      expect(entry.seeders, 3);
      expect(entry.modifiedAt.millisecondsSinceEpoch, 5000);
    },
  );

  test(
    '5000 indexed rows use bounded disjoint pages and correct filters',
    () async {
      final batch = db.batch();
      for (var index = 0; index < 5000; index++) {
        batch.insert('torrents', {
          'hash': index.toRadixString(16).padLeft(40, '0'),
          'name': 'Torrent $index',
          'torrent_path': '/$index.torrent',
          'category': index.isEven ? 'video' : 'audio',
          'total_bytes': index,
          'file_count': 1,
          'added_at': index,
          'status': index % 3 == 0 ? 'complete' : 'library',
        });
      }
      await batch.commit(noResult: true);
      final first = await repo.page();
      final second = await repo.page(offset: 80);
      expect(first.total, 5000);
      expect(first.entries.length, 80);
      expect(second.entries.length, 80);
      expect(
        first.entries
            .map((e) => e.hash)
            .toSet()
            .intersection(second.entries.map((e) => e.hash).toSet()),
        isEmpty,
      );
      final filtered = await repo.page(status: 'complete', category: 'video');
      expect(filtered.total, 834);
      expect(
        filtered.entries.every(
          (e) => e.category == 'video' && e.status == 'complete',
        ),
        isTrue,
      );
      expect((await repo.page(offset: 4990)).entries.length, 10);
      expect((await repo.page(limit: 100000)).entries.length, 1000);
      final largeFirst = await repo.page(limit: 1000);
      final largeSecond = await repo.page(limit: 1000, offset: 1000);
      expect(largeFirst.entries, hasLength(1000));
      expect(largeSecond.entries, hasLength(1000));
      expect(
        largeFirst.entries
            .map((e) => e.hash)
            .toSet()
            .intersection(largeSecond.entries.map((e) => e.hash).toSet()),
        isEmpty,
      );
      final largest = await repo.page(sort: SortOption.sizeDesc, offset: 80);
      expect(largest.entries.first.totalBytes, 4919);
      expect(largest.entries.last.totalBytes, 4840);
      final newest = await repo.page(sort: SortOption.dateCreatedDesc);
      expect(newest.entries.first.name, 'Torrent 4999');
      final names = await repo.page(sort: SortOption.nameDesc);
      expect(names.entries.first.name, 'Torrent 999');
      final regex = await repo.page(
        query: r'^Torrent [0-9]*9$',
        useRegex: true,
        sort: SortOption.sizeDesc,
        offset: 80,
        limit: 20,
      );
      expect(regex.total, 500);
      expect(regex.entries.first.name, 'Torrent 4199');
      expect(regex.entries.last.name, 'Torrent 4009');
      expect(
        (await repo.page(
          query: '.',
          useRegex: true,
          isCancelled: () => true,
        )).entries,
        isEmpty,
      );
    },
  );

  test(
    'search treats wildcards literally and matches assigned groups',
    () async {
      final info = TorrentMetainfo.parse(torrentBytes(name: '100%_match.txt'));
      await repo.import(info, '/a', '/a', 0, 1);
      await repo.update(info.hash, {'group_name': 'Favorites'});
      expect((await repo.page(query: '%_')).total, 1);
      expect((await repo.page(query: '%not')).total, 0);
      expect((await repo.page(query: 'Favorites')).total, 1);
      expect((await repo.page(query: info.hash)).total, 1);
    },
  );

  test(
    'shared Unicode search handles word order, groups, metadata updates and regex',
    () async {
      final info = TorrentMetainfo.parse(torrentBytes(name: 'Bộ_phim Đêm.mp4'));
      await repo.import(info, '/a', '/a', 5000000, 1);
      await repo.update(info.hash, {'group_name': 'Ưa thích'});
      expect((await repo.page(query: 'dem bo')).total, 1);
      expect((await repo.page(query: 'thich phim')).total, 1);
      expect((await repo.page(query: 'Ưa thích')).total, 1);
      expect((await repo.page(query: r'Đêm\.mp4$', useRegex: true)).total, 1);
      expect((await repo.page(query: '[', useRegex: false)).total, 1);
      await expectLater(
        repo.page(query: '[', useRegex: true),
        throwsFormatException,
      );
      await repo.update(info.hash, {
        'name': 'Cà phê mới',
        'group_name': 'Sưu tầm',
      });
      expect((await repo.page(query: 'phe tam')).total, 1);
      expect((await repo.page(query: 'phim')).total, 0);
      expect(
        (await repo.get(info.hash))!.modifiedAt.millisecondsSinceEpoch,
        5000,
      );
    },
  );

  test(
    'name order matches browser Unicode casing across page boundaries and metadata changes',
    () async {
      for (final name in ['ÉCHO.txt', 'éb.txt', 'Alpha.txt']) {
        final info = TorrentMetainfo.parse(torrentBytes(name: name));
        await repo.import(info, '/$name', '/$name', 1, 1);
      }
      expect(
        (await repo.page(
          limit: 1,
          sort: SortOption.nameAsc,
        )).entries.single.name,
        'Alpha.txt',
      );
      expect(
        (await repo.page(
          limit: 1,
          offset: 1,
          sort: SortOption.nameAsc,
        )).entries.single.name,
        'éb.txt',
      );
      expect(
        (await repo.page(
          sort: SortOption.nameDesc,
          limit: 1,
        )).entries.single.name,
        'ÉCHO.txt',
      );
      final echo = (await repo.page(sort: SortOption.nameDesc)).entries.first;
      await repo.update(echo.hash, {'name': 'Éa.txt'});
      expect(
        (await repo.page(
          limit: 1,
          offset: 1,
          sort: SortOption.nameAsc,
        )).entries.single.name,
        'Éa.txt',
      );
    },
  );

  test('newest source files are first by default across all pages', () async {
    for (var i = 0; i < 180; i++) {
      final info = TorrentMetainfo.parse(torrentBytes(name: '$i.txt'));
      await repo.import(info, '/$i', '/$i', i * 1000000, 1);
      // Adding an older file later must not make it the newest source file.
      await db.update(
        'torrents',
        {'added_at': 1000000 - i},
        where: 'hash = ?',
        whereArgs: [info.hash],
      );
    }
    expect((await repo.page()).entries.first.name, '179.txt');
    expect((await repo.page(offset: 80)).entries.first.name, '99.txt');
    expect((await repo.page(offset: 160)).entries.last.name, '0.txt');
  });

  test(
    'pending tasks paginate by key and removal cleans source rows',
    () async {
      for (var i = 0; i < 5; i++) {
        final info = TorrentMetainfo.parse(torrentBytes(name: '$i.txt'));
        await repo.import(info, '/$i', '/$i', i, 1);
        await repo.update(info.hash, {'status': i == 0 ? 'error' : 'paused'});
      }
      final first = await repo.pending(limit: 2);
      final second = await repo.pending(after: first.last.hash, limit: 2);
      expect([...first, ...second].map((e) => e.hash).toSet().length, 4);
      await repo.remove(first.first.hash);
      expect(await repo.sources(first.first.hash), isEmpty);
      expect(await repo.get(first.first.hash), isNull);
    },
  );
}
