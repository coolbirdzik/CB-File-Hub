import 'dart:io';

import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v3 galleries migrate with NSFW off and retain existing records',
    () async {
      final root = await Directory.systemTemp.createTemp('cb-nsfw-migration-');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => root.path);
      final provider = SqliteDatabaseProvider();
      final folder = await Directory(
        p.join(root.path, 'CBFileHub_v2'),
      ).create();
      try {
        final old = await provider.getDatabaseFactory().openDatabase(
          p.join(folder.path, 'cb_file_hub.sqlite'),
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: (db, _) async {
              for (final table in ['albums', 'video_libraries']) {
                await db.execute(
                  'CREATE TABLE $table (id INTEGER PRIMARY KEY, name TEXT)',
                );
                await db.insert(table, {'id': 1, 'name': 'Existing gallery'});
              }
            },
          ),
        );
        await old.close();
        final db = await provider.getDatabase();
        expect(await db.getVersion(), 4);
        for (final table in ['albums', 'video_libraries']) {
          expect((await db.query(table)).single, {
            'id': 1,
            'name': 'Existing gallery',
            'is_nsfw': 0,
          });
          await db.update(table, {'is_nsfw': 1}, where: 'id = 1');
          expect((await db.query(table)).single['is_nsfw'], 1);
        }
      } finally {
        await SqliteDatabaseProvider.closeSharedDatabase();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'v3 database that already has is_nsfw (downgraded by an older build) opens',
    () async {
      final root = await Directory.systemTemp.createTemp('cb-nsfw-migration-');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => root.path);
      final provider = SqliteDatabaseProvider();
      final folder = await Directory(
        p.join(root.path, 'CBFileHub_v2'),
      ).create();
      try {
        final old = await provider.getDatabaseFactory().openDatabase(
          p.join(folder.path, 'cb_file_hub.sqlite'),
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: (db, _) async {
              for (final table in ['albums', 'video_libraries']) {
                await db.execute(
                  'CREATE TABLE $table (id INTEGER PRIMARY KEY, name TEXT, '
                  'is_nsfw INTEGER NOT NULL DEFAULT 0)',
                );
                await db.insert(table, {
                  'id': 1,
                  'name': 'Existing gallery',
                  'is_nsfw': 1,
                });
              }
            },
          ),
        );
        await old.close();
        final db = await provider.getDatabase();
        expect(await db.getVersion(), 4);
        for (final table in ['albums', 'video_libraries']) {
          expect((await db.query(table)).single['is_nsfw'], 1);
        }
      } finally {
        await SqliteDatabaseProvider.closeSharedDatabase();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await root.delete(recursive: true);
      }
    },
  );
}
