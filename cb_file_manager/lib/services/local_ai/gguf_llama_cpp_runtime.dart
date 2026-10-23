import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/local_ai/local_ai_advisor_model.dart';
import '../../utils/app_logger.dart';
import 'windows_process_reaper.dart';
import 'llama_cpp_chat_client.dart';
import 'llama_cpp_server_launch.dart';

/// Local chat runtime backed by a bundled llama-server process.
///
/// Instead of calling llama.cpp through FFI inside a Dart isolate (which
/// crashes during GPU tensor upload because Vulkan is initialized on a
/// non-main thread and conflicts with the Flutter engine's own GPU use), this
/// runtime launches the official `llama-server.exe` as a separate OS process
/// and talks to it over HTTP. The server is the same binary that runs fine
/// standalone, so GPU offload via the bundled Vulkan backend works reliably.
/// Android launches the APK's native CPU executable from nativeLibraryDir.
/// macOS resolves its signed, architecture-specific bundle helper via AppKit.
///
/// The server process is started once for a given (model, context size) pair
/// and reused across requests. It is only restarted when the selected model or
/// the configured context window changes.
class GgufLlamaCppLocalAiChatRuntime
    implements
        LocalAiChatRuntime,
        LocalAiConversationRuntime,
        LocalAiDirectConversationRuntime,
        LocalAiModelFileHolder {
  /// GPU layers to offload. 99 offloads all layers to the GPU (via the bundled
  /// Vulkan backend); the server falls back to CPU for layers the GPU cannot
  /// fit. Set to 0 to force CPU-only inference.
  final int nGpuLayers;

  /// Windows server filename. Android and macOS resolve their native helpers.
  final String serverExecutableName;

  /// Maximum number of tokens the model may generate for a single response
  /// (llama.cpp `n_predict`). This is the response-length cap and is distinct
  /// from the context window (`maxTokens`), which bounds prompt + history +
  /// output. It is additionally clamped to never exceed the context window.
  /// Set to -1 to let the model generate until it emits an end-of-sequence
  /// token (bounded only by the context window).
  final int maxResponseTokens;

  GgufLlamaCppLocalAiChatRuntime({
    this.nGpuLayers = 99,
    this.serverExecutableName = 'llama-server.exe',
    this.maxResponseTokens = 2048,
  });

  Process? _serverProcess;
  int? _serverPort;
  String? _loadedModelPath;
  int? _loadedContextSize;

  final HttpClient _httpClient = HttpClient();

  /// Kill-on-close Job Object so the OS reaps the server if the app dies.
  final WindowsProcessReaper _killOnCloseJob = WindowsProcessReaper.instance;

  @override
  Future<String> sendMessage({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in sendMessageStream(
      model: model,
      message: message,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
    )) {
      // Skip status messages so the returned string is pure model output.
      if (chunk.startsWith(_statusPrefix)) continue;
      buffer.write(chunk);
    }
    return buffer.toString().trim();
  }

  @override
  Stream<String> sendMessageStream({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  }) {
    if (!model.localPath.toLowerCase().endsWith('.gguf')) {
      return Stream.error(
        UnsupportedError(
          'GgufLlamaCppLocalAiChatRuntime only supports .gguf artifacts. '
          'Got: ${model.localPath}',
        ),
      );
    }

    return sendConversationStream(
      model: model,
      messages: [
        {'role': 'user', 'content': message},
      ],
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
    );
  }

  @override
  Stream<String> sendConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
  }) => _sendConversationStream(
    model: model,
    messages: messages,
    systemPrompt: systemPrompt,
    maxTokens: maxTokens,
  );

  @override
  Stream<String> sendDirectConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
  }) => _sendConversationStream(
    model: model,
    messages: messages,
    systemPrompt: systemPrompt,
    maxTokens: maxTokens,
    enableThinking: false,
  );

  Stream<String> _sendConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
    bool? enableThinking,
  }) async* {
    final modelPath = model.localPath;
    // Restart the server if the model or context window changed.
    final needsRestart =
        _serverProcess != null &&
        (_loadedModelPath != modelPath || _loadedContextSize != maxTokens);
    if (needsRestart) {
      await _stopServer();
    }

    if (_serverProcess == null) {
      yield* _startServer(modelPath: modelPath, maxTokens: maxTokens);
    }

    final port = _serverPort;
    if (port == null) {
      throw StateError('Local AI server is not ready after startup.');
    }

    final nPredict = maxResponseTokens < 0
        ? maxTokens
        : (maxResponseTokens < maxTokens ? maxResponseTokens : maxTokens);
    yield* LlamaCppChatClient(_httpClient).stream(
      baseUri: Uri.parse('http://127.0.0.1:$port'),
      messages: [
        {
          'role': 'system',
          'content': systemPrompt?.trim().isNotEmpty == true
              ? systemPrompt!.trim()
              : 'You are a helpful assistant.',
        },
        ...messages,
      ],
      maxResponseTokens: nPredict,
      catalogId: model.catalogId,
      enableThinking: enableThinking,
    );
  }

  /// Launches the bundled server, waits for the /health endpoint to
  /// report ready, and yields `[STATUS]` progress messages while loading.
  Stream<String> _startServer({
    required String modelPath,
    required int maxTokens,
  }) async* {
    final launch = await LlamaCppServerLaunch.resolve(
      platform: defaultTargetPlatform,
      desktopExecutableName: serverExecutableName,
    );
    final serverPath = launch.executablePath;
    if (!File(serverPath).existsSync()) {
      throw StateError(
        'Bundled local AI server not found at $serverPath. '
        '${launch.isAndroid ? 'Rebuild and reinstall the APK with its native runtime.' : 'Ensure $serverExecutableName is shipped in the "llama" subfolder next to the app executable.'}',
      );
    }
    if (!File(modelPath).existsSync()) {
      throw FileSystemException('Local model file not found', modelPath);
    }

    yield '${_statusPrefix}Starting local AI server...';

    final port = await _findFreePort();
    final process = await Process.start(
      serverPath,
      launch.arguments(
        modelPath: modelPath,
        port: port,
        contextTokens: maxTokens,
        gpuLayers: nGpuLayers,
      ),
      workingDirectory: launch.workingDirectory,
      environment: launch.environment,
    );
    _serverProcess = process;
    _serverPort = port;

    // Assign the server to a kill-on-close Job Object so Windows terminates it
    // automatically if this app process dies (crash, taskkill, or normal exit),
    // preventing orphaned llama-server.exe processes that would hold VRAM/port.
    if (Platform.isWindows) {
      _killOnCloseJob.assignProcess(process.pid);
    }

    // Drain output so the process does not block on a full pipe buffer.
    process.stdout.drain<void>();
    // Preserve a bounded tail: Android loader/model errors used to disappear
    // into drain(), leaving only a generic readiness failure in the UI.
    var stderrTail = '';
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) {
          stderrTail += chunk;
          if (stderrTail.length > 8192) {
            stderrTail = stderrTail.substring(stderrTail.length - 8192);
          }
        })
        .asFuture<void>();

    // Surface early process death (e.g. bad model, port in use).
    unawaited(
      process.exitCode.then((code) {
        if (identical(_serverProcess, process)) {
          AppLogger.error(
            '[LocalAI] llama-server exited unexpectedly: '
            'pid=${process.pid}, exit=$code '
            '(0x${(code & 0xffffffff).toRadixString(16).padLeft(8, '0')}).',
          );
          _serverProcess = null;
          _serverPort = null;
          _loadedModelPath = null;
          _loadedContextSize = null;
        }
      }),
    );

    yield '${_statusPrefix}Loading model (this may take 10-30 seconds)...';

    final ready = await _waitForHealth(port, process);
    if (!ready) {
      await _stopServer();
      await stderrDone.timeout(const Duration(seconds: 2), onTimeout: () {});
      final details = stderrTail.trim();
      if (details.isNotEmpty) {
        AppLogger.error('[LocalAI] llama-server startup failed:\n$details');
      }
      throw StateError(
        'Local AI server failed to become ready (model load timed out or the '
        'server exited).${details.isEmpty ? '' : '\n$details'}',
      );
    }

    _loadedModelPath = modelPath;
    _loadedContextSize = maxTokens;
    yield '${_statusPrefix}Ready';
  }

  /// Polls GET /health until it returns {"status":"ok"} or the timeout elapses.
  /// Returns false if the server process exits first or the timeout is hit.
  Future<bool> _waitForHealth(int port, Process process) async {
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    var processAlive = true;
    unawaited(process.exitCode.then((_) => processAlive = false));

    while (DateTime.now().isBefore(deadline)) {
      if (!processAlive) return false;
      try {
        final request = await _httpClient
            .getUrl(Uri.parse('http://127.0.0.1:$port/health'))
            .timeout(const Duration(seconds: 3));
        final response = await request.close().timeout(
          const Duration(seconds: 3),
        );
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode == 200 && body.contains('"status"')) {
          if (body.contains('"ok"')) return true;
        }
      } catch (_) {
        // Server not accepting connections yet; keep polling.
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> _stopServer() async {
    final process = _serverProcess;
    _serverProcess = null;
    _serverPort = null;
    _loadedModelPath = null;
    _loadedContextSize = null;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// Stops the server so Windows releases its lock on the model file. The
  /// next request starts it again.
  @override
  Future<void> releaseModelFiles() => _stopServer();

  /// Stops the server process and releases the HTTP client.
  @override
  Future<void> dispose() async {
    await _stopServer();
    _httpClient.close(force: true);
  }
}

/// Prefix used to mark status/progress messages so the bloc can route them to
/// the "thinking" indicator instead of the chat content.
const String _statusPrefix = '[STATUS]';
