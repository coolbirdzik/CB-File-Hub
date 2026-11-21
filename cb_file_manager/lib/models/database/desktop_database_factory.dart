import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../services/windowing/windows_engine_host.dart';

/// A single FFI worker owns SQLite handles for all Windows engines. Other
/// engines send sqflite requests to that worker, never loading/opening SQLite
/// on their UI isolates. The coordinator engine outlives the other windows.
abstract final class DesktopDatabaseFactory {
  static DatabaseFactory? _sharedFactory;
  static bool _loaderInitialized = false;
  static int _activeTransactions = 0;
  static Future<void> _transactionRetention = Future<void>.value();

  static DatabaseFactory get instance {
    if (WindowsEngineHost.isAvailable) {
      if (WindowsEngineHost.isPrimary && !_loaderInitialized) {
        sqfliteFfiInit();
        _loaderInitialized = true;
      }
      return _sharedFactory ??= createSharedFactory(
        'CBFileHub.SQLiteWorker.v1',
      );
    }
    if (!_loaderInitialized) {
      sqfliteFfiInit();
      _loaderInitialized = true;
    }
    return databaseFactoryFfi;
  }

  /// Named separately so unit tests can exercise real worker sharing without
  /// joining a running application's port registration.
  static DatabaseFactory createSharedFactory(String workerName) =>
      createDatabaseFactoryFfi(
        isolatePortServer: _SqlitePortServer(workerName),
      );

  /// Keeps the transaction's client alive until it sends COMMIT or ROLLBACK.
  /// The shared worker would otherwise keep an abandoned transaction open.
  static Future<T> withTransactionLifetime<T>(Future<T> Function() action) {
    if (!WindowsEngineHost.isAvailable) return action();
    return _runRetained(action);
  }

  static Future<T> _runRetained<T>(Future<T> Function() action) async {
    const reason = 'sqlite-transaction';
    if (_activeTransactions++ == 0) {
      _transactionRetention = _transactionRetention.then(
        (_) => WindowsEngineHost.retainWhileBusy(reason, true),
      );
    }
    try {
      await _transactionRetention;
      return await action();
    } finally {
      if (--_activeTransactions == 0) {
        _transactionRetention = WindowsEngineHost.retainWhileBusy(reason, false)
            .catchError((Object error) {
              debugPrint('Could not release SQLite engine retention: $error');
            });
        await _transactionRetention;
      }
    }
  }
}

extension AppDatabaseTransaction on Database {
  Future<T> runAppTransaction<T>(Future<T> Function(Transaction txn) action) =>
      DesktopDatabaseFactory.withTransactionLifetime(() => transaction(action));
}

class _SqlitePortServer implements SqfliteFfiIsolatePortServer {
  const _SqlitePortServer(this.name);
  final String name;

  @override
  SendPort? lookupPort() => IsolateNameServer.lookupPortByName(name);

  @override
  bool registerPort(SendPort sendPort) =>
      IsolateNameServer.registerPortWithName(sendPort, name);

  @override
  bool unregisterPort() => IsolateNameServer.removePortNameMapping(name);
}
