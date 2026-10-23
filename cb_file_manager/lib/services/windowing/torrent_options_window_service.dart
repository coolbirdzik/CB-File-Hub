import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../torrent/torrent_download_options.dart';
import 'video_window_service.dart'
    show VideoWindowService, VideoWindowProcessLauncher;
import 'window_startup_payload.dart';
import 'torrent_options_window_anchor.dart';
import 'windows_native_tab_drag_drop_service.dart';

/// The form owns no database or download engine. Only validated options return
/// to the shell, which remains responsible for all torrent actions.
class TorrentOptionsWindowService {
  static final instance = TorrentOptionsWindowService._();
  static const role = 'torrent-options';
  static const envPort = 'CB_TORRENT_OPTIONS_PORT';
  static const envToken = 'CB_TORRENT_OPTIONS_TOKEN';

  TorrentOptionsWindowService._()
    : launch = _launchProcess,
      captureAnchor = TorrentOptionsWindowAnchor.capture,
      startupTimeout = const Duration(seconds: 12);

  @visibleForTesting
  TorrentOptionsWindowService.forTesting({
    required this.launch,
    this.captureAnchor = _emptyAnchor,
    this.startupTimeout = const Duration(seconds: 12),
  });

  final VideoWindowProcessLauncher launch;
  final Future<TorrentOptionsWindowAnchor> Function() captureAnchor;
  final Duration startupTimeout;
  ServerSocket? _server;
  Socket? _client;
  Future<void>? _starting;
  Future<void> _queue = Future<void>.value();
  Completer<void>? _ready;
  Completer<TorrentDownloadOptions?>? _result;
  String? _token;
  int _requestId = 0;
  int? _clientPid;

  static bool get isSupported =>
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
      !const bool.fromEnvironment('CB_E2E') &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  /// Start hidden ahead of the first request, then reuse this process.
  Future<void> warmUp() async {
    try {
      await _ensureReady();
    } catch (e) {
      debugPrint('Torrent options window warmup: $e');
    }
  }

  /// The primary shell can warm the form before any torrent tab/database loads.
  Future<void> warmUpIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('torrent.receiveInBackground') == true ||
        prefs.getBool('torrent.showDownloadDialog') == false) {
      return;
    }
    await warmUp();
  }

  Future<void> _ensureReady() async {
    if (_starting != null) return _starting!;
    if (_client != null) return;
    final starting = _start();
    _starting = starting;
    try {
      await starting;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start() async {
    _ready = Completer<void>();
    final random = Random.secure();
    _token = List.generate(
      32,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(_accept);
      final env = Map<String, String>.from(Platform.environment)
        ..remove('CB_STARTUP_TABS')
        ..remove('CB_PIP_MODE')
        ..remove('CB_PIP_ARGS')
        ..remove(VideoWindowService.envFlagKey)
        ..remove(VideoWindowService.envArgsKey)
        ..[WindowStartupPayload.envSecondaryWindowKey] = '1'
        ..[WindowStartupPayload.envStartHiddenKey] = '1'
        ..[WindowStartupPayload.envWindowRoleKey] = role
        ..[envPort] = '${_server!.port}'
        ..[envToken] = _token!;
      final executable = Platform.resolvedExecutable;
      await launch(
        executable: executable,
        arguments: const [],
        environment: env,
        workingDirectory: File(executable).parent.path,
      );
      await _ready!.future.timeout(startupTimeout);
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  void _accept(Socket socket) {
    var authenticated = false;
    final timeout = Timer(const Duration(seconds: 5), () {
      if (!authenticated) socket.destroy();
    });
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              if (line.length > 65536) {
                throw const FormatException('IPC too large');
              }
              final message = jsonDecode(line) as Map<String, dynamic>;
              if (!authenticated) {
                if (message['token'] != _token || _client != null) {
                  socket.destroy();
                  return;
                }
                authenticated = true;
                timeout.cancel();
                _client = socket;
                _clientPid = message['pid'] is int
                    ? message['pid'] as int
                    : null;
                if (!(_ready?.isCompleted ?? true)) _ready!.complete();
                return;
              }
              if (message['id'] != _requestId ||
                  _result == null ||
                  _result!.isCompleted) {
                return;
              }
              if (message['error'] != null) {
                throw StateError('${message['error']}');
              }
              final raw = message['options'];
              _result!.complete(
                raw == null
                    ? null
                    : TorrentDownloadOptions.fromJson(
                        Map<String, dynamic>.from(raw as Map),
                      ),
              );
            } catch (e, stack) {
              if (_client == socket && !(_result?.isCompleted ?? true)) {
                _result!.completeError(e, stack);
              }
              socket.destroy();
              _disconnect(socket);
            }
          },
          onDone: () {
            timeout.cancel();
            _disconnect(socket);
          },
          onError: (Object e) {
            timeout.cancel();
            socket.destroy();
            _disconnect(socket);
          },
          cancelOnError: false,
        );
  }

  void _disconnect(Socket socket) {
    if (_client != socket) return;
    _client = null;
    _clientPid = null;
    if (!(_result?.isCompleted ?? true)) {
      _result!.completeError(
        StateError('Torrent options window closed unexpectedly'),
      );
    }
    unawaited(_server?.close());
    _server = null;
  }

  Future<TorrentDownloadOptions?> show(TorrentDownloadRequest request) {
    final result = Completer<TorrentDownloadOptions?>();
    _queue = _queue.then((_) async {
      try {
        await _ensureReady();
        // Read at dequeue time: the parent can move while another form is open.
        final anchor = await captureAnchor();
        if (Platform.isWindows && _clientPid != null) {
          await WindowsNativeTabDragDropService.allowForegroundWindow(
            pid: _clientPid,
          );
        }
        _requestId++;
        final reply = _result = Completer<TorrentDownloadOptions?>();
        _client!.write(
          '${jsonEncode({'id': _requestId, 'request': request.toJson(), 'anchor': anchor.toJson()})}\n',
        );
        final options = await reply.future;
        if (options != null &&
            request.destinationLocked &&
            !p.equals(
              options.destination,
              p.normalize(request.initialDestination),
            )) {
          throw const FormatException(
            'Active torrent destination cannot change',
          );
        }
        result.complete(options);
      } catch (e, stack) {
        result.completeError(e, stack);
      } finally {
        _result = null;
      }
    });
    return result.future;
  }

  Future<void> dispose() async {
    _client?.destroy();
    _client = null;
    await _server?.close();
    _server = null;
    if (!(_result?.isCompleted ?? true)) _result!.complete(null);
  }

  static Future<TorrentOptionsWindowAnchor> _emptyAnchor() async =>
      const TorrentOptionsWindowAnchor();

  static Future<void> _launchProcess({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
    required String workingDirectory,
  }) async {
    await Process.start(
      executable,
      arguments,
      environment: environment,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detached,
    );
  }
}
