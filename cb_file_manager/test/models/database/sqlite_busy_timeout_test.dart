import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Each desktop window is its own process with its own connection to the
/// shared database. Two connections from two factories stand in for them:
/// the holder runs on this isolate, the writer on sqflite's worker isolate,
/// so the writer can wait for the lock while the holder still commits.
void main() {
  sqfliteFfiInit();
  late Directory dir;
  late String dbPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cb_busy_timeout_');
    dbPath = p.join(dir.path, 'shared.sqlite');
    final setup = await databaseFactoryFfiNoIsolate.openDatabase(dbPath);
    await setup.execute('PRAGMA journal_mode = WAL');
    await setup.execute('CREATE TABLE t (v INTEGER)');
    await setup.close();
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  /// Holds a write transaction on one connection for [hold] while another
  /// connection writes in a transaction; returns the writer's error, if any.
  Future<Object?> writeWhileLocked({
    required Future<void> Function(Database db)? configure,
    Duration hold = const Duration(milliseconds: 400),
  }) async {
    final options = OpenDatabaseOptions(
      onConfigure: configure,
      singleInstance: false,
    );
    final holder = await databaseFactoryFfiNoIsolate.openDatabase(
      dbPath,
      options: options,
    );
    final writer = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: options,
    );
    final locked = Completer<void>();
    final holding = holder.transaction((txn) async {
      await txn.insert('t', {'v': 1});
      locked.complete();
      await Future<void>.delayed(hold);
    });
    await locked.future;
    Object? error;
    try {
      await writer.transaction((txn) => txn.insert('t', {'v': 2}));
    } catch (e) {
      error = e;
    }
    await holding;
    await writer.close();
    await holder.close();
    return error;
  }

  test('without a busy timeout a concurrent write fails as locked', () async {
    final error = await writeWhileLocked(configure: null);
    expect(error, isA<DatabaseException>());
    expect(error.toString(), contains('database is locked'));
  });

  test('the shared connection settings wait for the other writer', () async {
    final error = await writeWhileLocked(
      configure: SqliteDatabaseProvider.configureConnection,
    );
    expect(error, isNull);
    final db = await databaseFactoryFfiNoIsolate.openDatabase(dbPath);
    final rows = await db.rawQuery('SELECT v FROM t ORDER BY v');
    await db.close();
    expect(rows.map((r) => r['v']), [1, 2]);
  });
}
