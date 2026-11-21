import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'windows_engine_host.dart';

/// Transfers a tab snapshot to a fresh Flutter process. Snapshots can outgrow
/// a Windows environment variable, and the opener keeps its tabs until the
/// destination confirms that it can show them.
final class WindowsTabWindowLaunch {
  WindowsTabWindowLaunch._(this._socket, this.encodedTabs);

  static const _portKey = 'CB_TAB_LAUNCH_PORT';
  static const _tokenKey = 'CB_TAB_LAUNCH_TOKEN';
  static const _timeout = Duration(seconds: 15);
  static const physicalPositionKey = 'CB_TAB_LAUNCH_PHYSICAL_POSITION';

  final Socket _socket;
  final String? encodedTabs;
  bool _ready = false;

  static Future<bool> start(
    Map<String, String> environment, {
    String? encodedTabs,
  }) async {
    final random = Random.secure();
    final token = base64UrlEncode(
      List.generate(24, (_) => random.nextInt(256)),
    );
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final result = Completer<bool>();
    final connections = <Socket>{};
    Socket? child;
    server.listen((socket) async {
      connections.add(socket);
      final lines = _lines(socket);
      try {
        if (!await lines.moveNext().timeout(const Duration(seconds: 3)) ||
            lines.current != token ||
            child != null) {
          return;
        }
        child = socket;
        socket.writeln(jsonEncode(encodedTabs));
        await socket.flush();
        final shown = await lines.moveNext() && lines.current == 'ready';
        if (!result.isCompleted) result.complete(shown);
      } catch (_) {
        if (identical(child, socket) && !result.isCompleted) {
          result.complete(false);
        }
      } finally {
        socket.destroy();
        connections.remove(socket);
        await lines.cancel();
      }
    });
    try {
      await WindowsEngineHost.startWindowProcess({
        ...environment,
        _portKey: '${server.port}',
        _tokenKey: token,
      });
      return await result.future.timeout(_timeout, onTimeout: () => false);
    } finally {
      await server.close();
      for (final socket in connections) {
        socket.destroy();
      }
    }
  }

  static Future<WindowsTabWindowLaunch?> connect(
    Map<String, String> environment,
  ) async {
    final token = environment[_tokenKey];
    if (token == null) return null;
    final port = int.parse(environment[_portKey]!);
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: _timeout,
    );
    final lines = _lines(socket);
    try {
      socket.writeln(token);
      await socket.flush();
      if (!await lines.moveNext().timeout(_timeout)) {
        throw StateError('The opening window disconnected');
      }
      final launch = WindowsTabWindowLaunch._(
        socket,
        jsonDecode(lines.current) as String?,
      );
      // Cancel startup if the opener exits or times out. Once ready, the
      // new window owns its lifetime and can outlive the opener.
      unawaited(launch._watchOpener(lines));
      return launch;
    } catch (_) {
      socket.destroy();
      await lines.cancel();
      rethrow;
    }
  }

  Future<void> _watchOpener(StreamIterator<String> lines) async {
    try {
      await lines.moveNext();
    } catch (_) {
      // A broken connection also means the opener is gone.
    } finally {
      await lines.cancel();
      if (!_ready) await WindowsEngineHost.closeOrExit(1);
    }
  }

  Future<void> markReady() async {
    _ready = true;
    try {
      _socket.writeln('ready');
      await _socket.flush();
    } finally {
      _socket.destroy();
    }
  }

  static StreamIterator<String> _lines(Socket socket) => StreamIterator(
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter()),
  );
}
