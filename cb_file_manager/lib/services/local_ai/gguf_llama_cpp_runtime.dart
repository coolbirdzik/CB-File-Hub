import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/local_ai/local_ai_advisor_model.dart';
import 'windows_process_reaper.dart';
import 'llama_cpp_chat_client.dart';

/// Local chat runtime backed by the bundled `llama-server.exe` process.
///
/// Instead of calling llama.cpp through FFI inside a Dart isolate (which
/// crashes during GPU tensor upload because Vulkan is initialized on a
/// non-main thread and conflicts with the Flutter engine's own GPU use), this
/// runtime launches the official `llama-server.exe` as a separate OS process
/// and talks to it over HTTP. The server is the same binary that runs fine
/// standalone, so GPU offload via the bundled Vulkan backend works reliably.
///
/// The server process is started once for a given (model, context size) pair
/// and reused across requests. It is only restarted when the selected model or
/// the configured context window changes.
class GgufLlamaCppLocalAiChatRuntime
    implements LocalAiChatRuntime, LocalAiConversationRuntime {
  /// GPU layers to offload. 99 offloads all layers to the GPU (via the bundled
  /// Vulkan backend); the server falls back to CPU for layers the GPU cannot
  /// fit. Set to 0 to force CPU-only inference.
  final int nGpuLayers;

  /// Filename of the bundled server executable, resolved next to the app exe.
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
    );
  }

  /// Launches the bundled `llama-server.exe`, waits for the /health endpoint to
  /// report ready, and yields `[STATUS]` progress messages while loading.
  Stream<String> _startServer({
    required String modelPath,
    required int maxTokens,
  }) async* {
    // The server lives in a "llama" subfolder, not next to the app exe. The app
    // ships Flutter's own vulkan-1.dll (ANGLE/media_kit) whose ABI differs from
    // the system Vulkan loader; since Windows prefers a DLL next to the launched
    // exe, launching from the app root would load that vulkan-1.dll and segfault
    // inside ggml-vulkan. The subfolder has no vulkan-1.dll, so the loader falls
    // back to the real System32 Vulkan loader and GPU offload works.
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final serverDir = '$exeDir${sep}llama';
    final serverPath = '$serverDir$sep$serverExecutableName';
    if (!File(serverPath).existsSync()) {
      throw StateError(
        'Bundled local AI server not found at $serverPath. '
        'Ensure $serverExecutableName is shipped in the "llama" subfolder '
        'next to the app executable.',
      );
    }
    if (!File(modelPath).existsSync()) {
      throw FileSystemException('Local model file not found', modelPath);
    }

    yield '${_statusPrefix}Starting local AI server...';

    final port = await _findFreePort();
    final process = await Process.start(serverPath, <String>[
      '-m',
      modelPath,
      '--host',
      '127.0.0.1',
      '--port',
      '$port',
      '-c',
      '$maxTokens',
      '-ngl',
      '$nGpuLayers',
      '--no-ui',
    ], workingDirectory: serverDir);
    _serverProcess = process;
    _serverPort = port;

    // Assign the server to a kill-on-close Job Object so Windows terminates it
    // automatically if this app process dies (crash, taskkill, or normal exit),
    // preventing orphaned llama-server.exe processes that would hold VRAM/port.
    if (Platform.isWindows) {
      _killOnCloseJob.assignProcess(process.pid);
    }

    // Drain stdout/stderr so the process does not block on a full pipe buffer.
    process.stdout.drain<void>();
    process.stderr.drain<void>();

    // Surface early process death (e.g. bad model, port in use).
    unawaited(
      process.exitCode.then((code) {
        if (identical(_serverProcess, process)) {
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
      throw StateError(
        'Local AI server failed to become ready (model load timed out or the '
        'server exited).',
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
