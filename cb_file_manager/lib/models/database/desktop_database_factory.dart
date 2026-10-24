import 'dart:isolate';
import 'dart:ui';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../services/windowing/windows_engine_host.dart';

/// A single FFI worker owns SQLite handles for all Windows engines. Other
/// engines send sqflite requests to that worker, never loading/opening SQLite
/// on their UI isolates. The coordinator engine outlives the other windows.
abstract final class DesktopDatabaseFactory {
  static DatabaseFactory? _sharedFactory;
  static bool _loaderInitialized = false;

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
