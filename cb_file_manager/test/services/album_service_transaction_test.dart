import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late AlbumService service;
  late Directory root;
  late SqliteDatabaseProvider provider;
  late Database database;
  late FileStat readableStat;
  late int albumId;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_album_transactions_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    provider = SqliteDatabaseProvider();
    await provider.initialize();
    database = await provider.getDatabase();
    expect(
      database.path,
      p.join(root.path, 'CBFileHub_v2', 'cb_file_hub.sqlite'),
    );
    service = AlbumService.instance;
    final fixture = await File(
      p.join(root.path, 'fixture.jpg'),
    ).writeAsString('image fixture');
    readableStat = await fixture.stat();
  });

  setUp(() async {
    await database.delete('album_files');
    await database.delete('albums');
    final now = DateTime.now().millisecondsSinceEpoch;
    albumId = await database.insert('albums', {
      'name': 'Transaction regression album',
      'created_at': now,
      'modified_at': now,
    });
  });

  tearDownAll(() async {
    await service.dispose();
    await provider.close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test('slow file stats do not block unrelated database queries', () async {
    final statStarted = Completer<void>();
    final statResult = Completer<FileStat>();
    final filePath = p.join(root.path, 'slow.jpg');
    final importing = _addWithStats(albumId, [filePath], (_) {
      statStarted.complete();
      return statResult.future;
    });

    try {
      await statStarted.future.timeout(const Duration(seconds: 10));
      final rows = await database
          .query('albums', where: 'id = ?', whereArgs: [albumId])
          .timeout(const Duration(seconds: 2));
      expect(rows.single['id'], albumId);
      expect(await database.query('album_files'), isEmpty);
      await database.insert('album_files', {
        'album_id': albumId,
        'file_path': filePath,
        'order_index': 0,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
    } finally {
      statResult.complete(readableStat);
      await importing;
    }

    expect(await importing, 0);
    expect((await service.getAlbumFiles(albumId)).single.filePath, filePath);
  });

  test('bulk metadata checks do not hold the database lock', () async {
    final filePaths = [
      for (var i = 0; i < 513; i++) p.join(root.path, 'image_$i.jpg'),
    ];
    final nextBatchStarted = Completer<void>();
    final nextBatchStat = Completer<FileStat>();
    final importing = _addWithStats(albumId, filePaths, (filePath) {
      if (filePath == filePaths.last) {
        nextBatchStarted.complete();
        return nextBatchStat.future;
      }
      return Future.value(readableStat);
    });

    try {
      await nextBatchStarted.future.timeout(const Duration(seconds: 10));
      final rows = await database
          .rawQuery(
            'SELECT COUNT(*) AS count FROM album_files WHERE album_id = ?',
            [albumId],
          )
          .timeout(const Duration(seconds: 2));
      expect(rows.single['count'], 0);
    } finally {
      nextBatchStat.complete(readableStat);
      await importing;
    }

    expect(await importing, filePaths.length);
    final files = await service.getAlbumFiles(albumId);
    expect(files.map((file) => file.filePath), filePaths);
    expect(files.map((file) => file.orderIndex), [
      for (var i = 0; i < filePaths.length; i++) i,
    ]);
  });

  test('bulk imports preserve duplicate handling, counts and order', () async {
    final existing = p.join(root.path, 'existing.jpg');
    final first = p.join(root.path, 'first.jpg');
    final inaccessible = p.join(root.path, 'inaccessible.jpg');
    final second = p.join(root.path, 'second.jpg');
    await database.insert('album_files', {
      'album_id': albumId,
      'file_path': existing,
      'order_index': 0,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    });

    final added = await _addWithStats(
      albumId,
      [existing, first, first, inaccessible, second],
      (filePath) => filePath == inaccessible
          ? Future.error(FileSystemException('Cannot stat file', filePath))
          : Future.value(readableStat),
    );

    expect(added, 2);
    final files = await service.getAlbumFiles(albumId);
    expect(files.map((file) => file.filePath), [existing, first, second]);
    expect(files.map((file) => file.orderIndex), [0, 1, 2]);
  });

  test('SQL failures roll back the whole bulk import', () async {
    final filePaths = [
      for (var i = 0; i < 513; i++) p.join(root.path, 'rollback_$i.jpg'),
    ];
    await database.execute('''
      CREATE TEMP TRIGGER reject_album_import BEFORE INSERT ON album_files
      WHEN NEW.order_index = 512
      BEGIN SELECT RAISE(ABORT, 'test rejected album file'); END
    ''');

    try {
      await expectLater(
        _addWithStats(albumId, filePaths, (_) => Future.value(readableStat)),
        throwsA(
          isA<DatabaseException>().having(
            (error) => error.toString(),
            'message',
            contains('test rejected album file'),
          ),
        ),
      );
      final rows = await database.rawQuery(
        'SELECT COUNT(*) AS count FROM album_files',
      );
      expect(rows.single['count'], 0);
    } finally {
      await database.execute('DROP TRIGGER reject_album_import');
    }
  });
}

Future<int> _addWithStats(
  int albumId,
  List<String> filePaths,
  Future<FileStat> Function(String) stat,
) => IOOverrides.runZoned(
  () => AlbumService.instance.addFilesToAlbum(albumId, filePaths),
  createFile: (filePath) => _StatFile(filePath, () => stat(filePath)),
);

class _StatFile implements File {
  _StatFile(this.path, this._stat);

  @override
  final String path;
  final Future<FileStat> Function() _stat;

  @override
  Future<FileStat> stat() => _stat();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
