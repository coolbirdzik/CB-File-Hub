import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:flutter/foundation.dart';

typedef VideoWindowProcessLauncher = Future<void> Function({
  required String executable,
  required List<String> arguments,
  required Map<String, String> environment,
  required String workingDirectory,
});

typedef VideoWindowReuseRequester = Future<bool> Function(String filePath);

/// Owns the single built-in desktop video-player window.
///
/// The first video starts a lightweight process of this executable. Later
/// videos are sent to that process over loopback IPC so the source changes in
/// place without creating another player window.
class VideoWindowService {
  static const String envFlagKey = 'CB_VIDEO_WINDOW';
  static const String envArgsKey = 'CB_VIDEO_WINDOW_ARGS';
  static const String envInitiallyMaximizedKey =
      'CB_VIDEO_WINDOW_INITIALLY_MAXIMIZED';

  static VideoWindowProcessLauncher _processLauncher = _launchDetachedProcess;
  static VideoWindowReuseRequester _reuseRequester = _playInExistingWindow;

  static bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// The player publishes its ephemeral loopback port here. A fixed port is
  /// unsuitable because Windows can reserve arbitrary chunks of port space.
  static File get _portFile => File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}cb_file_hub_video_window.port',
      );

  static ServerSocket? _server;
  static int? _ownedPort;

  /// Reuses the current player window, or starts it for [filePath].
  static Future<bool> openVideoWindow(
    String filePath, {
    bool initiallyMaximized = false,
  }) async {
    if (!isSupported || filePath.trim().isEmpty) return false;

    if (await _reuseRequester(filePath)) return true;

    try {
      final executable = Platform.resolvedExecutable;
      final workingDir = File(executable).parent.path;

      final env = Map<String, String>.from(Platform.environment);
      env[envFlagKey] = '1';
      env[envArgsKey] = jsonEncode(<String, dynamic>{'path': filePath});
      env[envInitiallyMaximizedKey] = initiallyMaximized ? '1' : '0';
      // A player window must never inherit the parent's tab/window payload.
      env.remove('CB_STARTUP_TABS');
      env.remove('CB_PIP_MODE');
      env.remove('CB_PIP_ARGS');
      // Boot on the lightweight secondary-window path.
      env[WindowStartupPayload.envSecondaryWindowKey] = '1';
      env[WindowStartupPayload.envStartHiddenKey] = '0';
      env[WindowStartupPayload.envWindowRoleKey] = 'video';
      env[WindowStartupPayload.envStartDraggingKey] = '0';
      env.remove(WindowStartupPayload.envWindowPositionXKey);
      env.remove(WindowStartupPayload.envWindowPositionYKey);

      final lowerExecutable = executable.toLowerCase();
      final isDartRuntime = lowerExecutable.endsWith(r'\dart.exe') ||
          lowerExecutable.endsWith('/dart');
      final launchArgs = isDartRuntime
          ? Platform.executableArguments.where((argument) {
              final lower = argument.toLowerCase();
              return !(lower.startsWith('--vm-service') ||
                  lower.startsWith('--observatory-port') ||
                  lower.startsWith('--dds-port') ||
                  lower.startsWith('--devtools-server-address'));
            }).toList(growable: false)
          : const <String>[];

      await _processLauncher(
        executable: executable,
        arguments: launchArgs,
        environment: env,
        workingDirectory: workingDir,
      );
      return true;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to open the video player window.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Sends [filePath] to a player process that is already listening.
  ///
  /// This is public so an OS file-association launch can reuse the existing
  /// player and immediately terminate its otherwise redundant process.
  static Future<bool> tryPlayInExistingWindow(String filePath) {
    if (!isSupported || filePath.trim().isEmpty) {
      return Future<bool>.value(false);
    }
    return _playInExistingWindow(filePath);
  }

  static Future<void> _launchDetachedProcess({
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

  static Future<int?> _readPublishedPort() async {
    try {
      if (!await _portFile.exists()) return null;
      final port = int.tryParse((await _portFile.readAsString()).trim());
      if (port == null || port <= 0 || port > 65535) return null;
      return port;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _playInExistingWindow(String filePath) async {
    final port = await _readPublishedPort();
    if (port == null) return false;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 600),
      );
      socket.write(
        '${jsonEncode(<String, dynamic>{'type': 'play', 'path': filePath})}\n',
      );
      await socket.flush();

      final reply = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2));
      final decoded = jsonDecode(reply);
      final reused = decoded is Map && decoded['type'] == 'ok';
      AppLogger.info(
        'Video window: reuse on port $port -> ${reused ? 'ok' : 'refused'}',
      );
      return reused;
    } catch (error) {
      AppLogger.info('Video window: port $port unreachable ($error).');
      // The player may have been closed before Flutter could run widget
      // disposal. Remove only the port file we just proved unreachable; the
      // next open can then spawn immediately without retrying stale IPC.
      try {
        if (await _portFile.exists() &&
            (await _portFile.readAsString()).trim() == '$port') {
          await _portFile.delete();
        }
      } catch (_) {}
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Starts the IPC endpoint owned by the dedicated player process.
  static Future<void> startPlayerIpcServer(
    void Function(String filePath) onPlay,
  ) async {
    if (!isSupported || _server != null) return;
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      _ownedPort = server.port;
      await _portFile.writeAsString('${server.port}', flush: true);
      AppLogger.info('Video window: listening on port ${server.port}');
      server.listen((socket) {
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (line.trim().isEmpty) return;
          try {
            final decoded = jsonDecode(line);
            if (decoded is Map &&
                decoded['type'] == 'play' &&
                decoded['path'] is String &&
                (decoded['path'] as String).trim().isNotEmpty) {
              onPlay(decoded['path'] as String);
              socket.write('${jsonEncode(<String, dynamic>{'type': 'ok'})}\n');
              return;
            }
          } catch (_) {}
          socket.write('${jsonEncode(<String, dynamic>{'type': 'error'})}\n');
        }, onDone: socket.destroy, onError: (_) => socket.destroy());
      });
    } catch (error) {
      AppLogger.warning('Video player window IPC unavailable: $error');
    }
  }

  static Future<void> stopPlayerIpcServer() async {
    final ownedPort = _ownedPort;
    _ownedPort = null;
    final server = _server;
    _server = null;
    try {
      await server?.close();
    } catch (_) {}
    try {
      if (ownedPort != null &&
          await _portFile.exists() &&
          (await _portFile.readAsString()).trim() == '$ownedPort') {
        await _portFile.delete();
      }
    } catch (_) {}
  }

  @visibleForTesting
  static set processLauncherForTesting(VideoWindowProcessLauncher launcher) {
    _processLauncher = launcher;
  }

  @visibleForTesting
  static set reuseRequesterForTesting(VideoWindowReuseRequester requester) {
    _reuseRequester = requester;
  }

  @visibleForTesting
  static void resetForTesting() {
    _processLauncher = _launchDetachedProcess;
    _reuseRequester = _playInExistingWindow;
  }

  /// Video path this process was started with, or null for a normal window.
  static String? startupVideoPath() {
    if (!isSupported || Platform.environment[envFlagKey] != '1') return null;
    final raw = Platform.environment[envArgsKey];
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final path = decoded['path'];
        if (path is String && path.trim().isNotEmpty) return path;
      }
    } catch (_) {}
    return null;
  }

  static bool startupInitiallyMaximized() {
    return isSupported && Platform.environment[envInitiallyMaximizedKey] == '1';
  }
}
