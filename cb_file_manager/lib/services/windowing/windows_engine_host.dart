import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../media/media_kit_playback.dart';

/// Each Windows window runs its own engine and Dart isolate in the same host.
/// Startup options belong to the engine; changing process environment variables
/// would race with every other window.
abstract final class WindowsEngineHost {
  static const channel = MethodChannel('cb_file_manager/engine_windows');
  static bool _available = false;
  static bool _primary = true;
  static String _engineId = 'primary';
  static Map<String, String>? _environment;
  static bool _closed = false;
  static Future<void> Function()? onCloseRequested;
  static final _retained = <String, bool>{};

  static bool get isAvailable => _available;
  static bool get isPrimary => _primary;
  static String get engineId => _engineId;
  static Map<String, String> get environment =>
      _environment ?? Platform.environment;
  static Map<String, String> newWindowEnvironment() => {
    for (final entry in environment.entries)
      if (!entry.key.startsWith('CB_')) entry.key: entry.value,
  };

  static Future<void> initialize() async {
    if (!Platform.isWindows ||
        const bool.fromEnvironment('CB_E2E') ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    await _loadStartup();
  }

  @visibleForTesting
  static Future<void> initializeForTesting() => _loadStartup();

  @visibleForTesting
  static void resetForTesting() {
    channel.setMethodCallHandler(null);
    _available = false;
    _primary = true;
    _engineId = 'primary';
    _environment = null;
    _closed = false;
    onCloseRequested = null;
    _retained.clear();
  }

  static Future<void> _loadStartup() async {
    final startup = await channel.invokeMapMethod<String, dynamic>('startup');
    if (startup == null) throw StateError('Windows engine host unavailable');
    _primary = startup['primary'] == true;
    _engineId = '${startup['engineId']}';
    final overrides = Map<String, String>.from(startup['environment'] as Map);
    _environment = {
      for (final entry in Platform.environment.entries)
        if (_primary || !entry.key.startsWith('CB_')) entry.key: entry.value,
      ...overrides,
    };
    _available = true;
    channel.setMethodCallHandler((call) async {
      // The host asks every engine before the process quits and tears them
      // all down.
      if (call.method == 'releaseMedia') return _releaseMedia();
      if (call.method == 'closeRequested') {
        final handler = onCloseRequested;
        try {
          if (handler != null) return await handler();
        } catch (e, st) {
          // A failed hand-off must not leave a window the user cannot close.
          debugPrint('Engine close handler failed: $e\n$st');
        }
        await close();
      }
    });
  }

  static Future<bool> open(Map<String, String> environment) async {
    if (!_available) throw StateError('Windows engine host not initialized');
    return await channel.invokeMethod<bool>('create', {
          'environment': {
            for (final entry in environment.entries)
              if (entry.key.startsWith('CB_')) entry.key: entry.value,
          },
        }) ??
        false;
  }

  /// Retains the primary engine as coordinator while other windows are open.
  static Future<void> close() async {
    _closed = true;
    if (_destroyedWhenClosed) await _releaseMedia();
    await channel.invokeMethod<void>('close');
  }

  /// Mirrors the host: it hides the primary or a retained engine's window and
  /// destroys any other engine.
  static bool get _destroyedWhenClosed =>
      !_primary && !_retained.containsValue(true);

  /// Native callbacks into a destroyed isolate abort the whole process.
  static Future<void> _releaseMedia() async {
    try {
      await PlaybackPlayer.disposeAll();
    } catch (e, st) {
      debugPrint('Releasing media before engine teardown failed: $e\n$st');
    }
  }

  static Future<void> closeOrExit([int code = 0]) async {
    if (_available) {
      await close();
    } else {
      exit(code);
    }
  }

  static Future<void> setRole(String role) {
    _closed = false;
    return channel.invokeMethod<void>('setRole', role);
  }

  /// Keeps this engine alive after its window closes while [busy]. Finite work
  /// ([keepsProcess]) also keeps the process alive after the last window
  /// closes; open-ended work such as seeding torrents ends with the app.
  static Future<void> retainWhileBusy(
    String reason,
    bool busy, {
    bool keepsProcess = true,
  }) async {
    if (!_available) return;
    if (_retained[reason] == busy) return;
    _retained[reason] = busy;
    // Releasing the last reason destroys an engine whose window was closed.
    if (_closed && _destroyedWhenClosed) await _releaseMedia();
    await channel.invokeMethod<void>('retain', {
      'reason': reason,
      'busy': busy,
      'keepsProcess': keepsProcess,
    });
  }
}
