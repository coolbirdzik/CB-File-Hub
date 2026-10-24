import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:cb_file_manager/models/database/desktop_database_factory.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Map<String, Object?>> _client(
  String workerName,
  String databasePath,
  int writes,
) async {
  // A window's client isolate only uses a SendPort. It never initializes FFI
  // and never owns a native SQLite handle that an engine finalizer can close.
  final factory = DesktopDatabaseFactory.createSharedFactory(workerName);
  final db = await factory.openDatabase(databasePath);
  for (var i = 0; i < writes; i++) {
    final rows = await db.query(
      'preferences',
      where: 'key = ?',
      whereArgs: ['show_file_tags'],
      limit: 1,
    );
    if (rows.single['bool_value'] != 1) throw StateError('Preference changed');
    await db.transaction(
      (txn) => txn.rawUpdate('UPDATE counter SET value = value + 1'),
    );
  }
  // Exiting a client (like closing a window) must not close the owner handle.
  return {'worker': IsolateNameServer.lookupPortByName(workerName)};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final workerName =
      'cb-sqlite-test-$pid-${DateTime.now().microsecondsSinceEpoch}';
  late Directory root;
  late String dbPath;
  late Database db;
  late SendPort ownerPort;

  setUpAll(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('cb-shared-sqlite-');
    dbPath = p.join(root.path, 'shared.sqlite');
    final factory = DesktopDatabaseFactory.createSharedFactory(workerName);
    db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        onConfigure: SqliteDatabaseProvider.configureConnection,
      ),
    );
    await db.execute(
      'CREATE TABLE preferences (key TEXT PRIMARY KEY, bool_value INTEGER)',
    );
    await db.insert('preferences', {'key': 'show_file_tags', 'bool_value': 1});
    await db.execute('CREATE TABLE counter (value INTEGER)');
    await db.insert('counter', {'value': 0});
    ownerPort = IsolateNameServer.lookupPortByName(workerName)!;
  });
  tearDownAll(() async {
    await db.close();
    IsolateNameServer.removePortNameMapping(workerName);
    await root.delete(recursive: true);
  });

  test(
    'concurrent window clients share one worker and preserve transaction updates',
    () async {
      final results = await Future.wait(
        List.generate(
          6,
          (_) => Isolate.run(() => _client(workerName, dbPath, 20)),
        ),
      );
      expect(results.map((r) => r['worker']), everyElement(ownerPort));
      expect((await db.query('counter')).single['value'], 120);
      // These SELECTs use exactly the shape of the reported failing query.
      for (var i = 0; i < 25; i++) {
        final row = await db.query(
          'preferences',
          where: 'key = ?',
          whereArgs: ['show_file_tags'],
          limit: 1,
        );
        expect(row.single['bool_value'], 1);
      }
    },
  );

  test(
    'new clients can attach after earlier client isolates have exited',
    () async {
      final before = (await db.query('counter')).single['value'] as int;
      for (var i = 0; i < 4; i++) {
        final result = await Isolate.run(() => _client(workerName, dbPath, 1));
        expect(result['worker'], ownerPort);
      }
      expect((await db.query('counter')).single['value'], before + 4);
    },
  );
}
