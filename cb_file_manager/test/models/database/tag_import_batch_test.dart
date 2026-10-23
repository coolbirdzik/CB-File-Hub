import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late SqliteDatabaseProvider provider;
  late DatabaseManager manager;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_tag_import_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    manager = DatabaseManager.getInstance();
    await manager.initialize();
    provider = SqliteDatabaseProvider();
    await provider.initialize();
  });
  tearDownAll(() async {
    await manager.close();
    await provider.close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  setUp(() async {
    final db = await provider.getDatabase();
    await db.delete('file_tags');
  });

  test(
    'batch normalization and last-write-wins equal individual inserts',
    () async {
      final rows = [
        ('one', '  Work '),
        ('two', 'Ảnh'),
        ('one', 'WORK'),
        ('three', '  '),
      ];
      expect(await provider.addTagsToFiles(rows), [true, true, true, true]);
      expect(await provider.getTagsForFile('one'), ['WORK']);
      expect(await provider.getTagsForFile('two'), ['Ảnh']);
      expect(await provider.getTagsForFile('three'), isEmpty);
      expect(await provider.countUniqueTaggedFiles(), 2);
    },
  );

  test('one rejected row does not stop later rows in the transaction', () async {
    final db = await provider.getDatabase();
    await db.execute(
      "CREATE TEMP TRIGGER reject_test_tag BEFORE INSERT ON file_tags WHEN NEW.file_path = 'rejected' BEGIN SELECT RAISE(FAIL, 'test rejected'); END",
    );
    try {
      expect(
        await provider.addTagsToFiles([
          ('one', 'a'),
          ('rejected', 'b'),
          ('two', 'c'),
        ]),
        [true, false, true],
      );
      expect(await provider.getTagsForFile('one'), ['a']);
      expect(await provider.getTagsForFile('two'), ['c']);
    } finally {
      await db.execute('DROP TRIGGER reject_test_tag');
    }
  });

  test(
    'modern imports probe each chunk, skip missing files and cross chunk boundaries',
    () async {
      final existing = await File(
        p.join(root.path, 'existing.jpg'),
      ).writeAsString('image');
      final missing = p.join(root.path, 'missing.jpg');
      final backup = await File(p.join(root.path, 'tags.json')).writeAsString(
        jsonEncode({
          'tags': {
            for (var i = 0; i < 520; i++) 'tag$i': [existing.path, missing],
          },
        }),
      );
      expect(await manager.importDatabase(backup.path), isTrue);
      expect((await manager.getTagsForFile(existing.path)).length, 520);
      expect(await manager.getTagsForFile(missing), isEmpty);
      expect(
        await manager.importDatabase(backup.path, skipFileExistenceCheck: true),
        isTrue,
      );
      expect((await manager.getTagsForFile(missing)).length, 520);
    },
  );

  test('legacy import preserves tags for missing and remote paths', () async {
    final backup = await File(p.join(root.path, 'legacy.json')).writeAsString(
      jsonEncode({
        'ftp://host/image.jpg': ['Vacation'],
        p.join(root.path, 'not-on-disk'): ['Offline'],
        'exportDate': '2025-01-01',
      }),
    );
    expect(await manager.importDatabase(backup.path), isTrue);
    expect(await manager.getTagsForFile('ftp://host/image.jpg'), ['Vacation']);
    expect(await manager.getTagsForFile(p.join(root.path, 'not-on-disk')), [
      'Offline',
    ]);
  });

  test(
    'unified JSON preserves import counts and preferences callback',
    () async {
      final existing = await File(
        p.join(root.path, 'present.txt'),
      ).writeAsString('text');
      final backup = await File(p.join(root.path, 'unified.json'))
          .writeAsString(
            jsonEncode({
              'database': {
                'tags': {
                  ' Work ': [existing.path, 'missing-path'],
                },
              },
              'preferences': {'theme': 'dark'},
            }),
          );
      Map<String, Object?>? prefs;
      final summary = await manager.importUnified(
        filePath: backup.path,
        onRestorePreferences: (value) => prefs = value,
      );
      expect(summary, {
        'importedTagCount': 1,
        'skippedFileCount': 1,
        'failedCount': 0,
        'preferencesCount': 1,
        'format': 'json',
      });
      expect(prefs, {'theme': 'dark'});
      expect(await manager.getTagsForFile(existing.path), ['Work']);
    },
  );

  test('SQLite imports retain row counters while batching writes', () async {
    final dbPath = p.join(root.path, 'backup.db');
    final backup = await provider.getDatabaseFactory().openDatabase(dbPath);
    await backup.execute('CREATE TABLE file_tags (file_path TEXT, tag TEXT)');
    await backup.insert('file_tags', {'file_path': 'missing-one', 'tag': 'a'});
    await backup.insert('file_tags', {'file_path': 'missing-two', 'tag': 'b'});
    await backup.close();
    final summary = await manager.importUnified(
      filePath: dbPath,
      onRestorePreferences: (_) {},
      skipFileExistenceCheck: true,
    );
    expect(summary?['importedTagCount'], 2);
    expect(summary?['failedCount'], 0);
    expect(await manager.getTagsForFile('missing-two'), ['b']);
  });
}
