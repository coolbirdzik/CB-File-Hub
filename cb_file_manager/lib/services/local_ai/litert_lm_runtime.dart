import 'dart:async';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import '../../models/local_ai/local_ai_advisor_model.dart';
import '../../utils/app_logger.dart';

/// Local chat runtime for `.litertlm` models (LiteRT-LM via flutter_edge_ai).
///
/// Speed comes from three things the previous per-request runtime lacked:
/// - the model stays loaded between requests; it is only reloaded when the
///   model file or the context window changes;
/// - it runs on the GPU (OpenCL on Android, Metal on iOS) with Multi-Token
///   Prediction when the bundle has a drafter; LiteRT-LM falls back to the
///   CPU by itself when the GPU cannot load it;
/// - one chat session is kept while a conversation only grows, so an agent's
///   tool rounds prefill just the new tool results instead of the whole
///   system prompt and history every time (the KV cache is reused).
class LiteRtLmLocalAiChatRuntime
    implements
        LocalAiChatRuntime,
        LocalAiConversationRuntime,
        LocalAiModelFileHolder {
  final PreferredBackend preferredBackend;
  final bool speculativeDecoding;

  LiteRtLmLocalAiChatRuntime({
    this.preferredBackend = PreferredBackend.gpu,
    this.speculativeDecoding = true,
  });

  static Future<void>? _initialization;

  /// Model files that decoded nothing on the GPU; they load on the CPU.
  final _cpuOnly = <String>{};

  InferenceModel? _model;
  String? _modelPath;
  int? _contextTokens;
  _Session? _session;

  /// Requests run one at a time: a LiteRT-LM session holds one generation.
  Future<void> _queue = Future.value();

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
  }) => sendConversationStream(
    model: model,
    messages: [
      {'role': 'user', 'content': message},
    ],
    systemPrompt: systemPrompt,
    maxTokens: maxTokens,
  );

  @override
  Stream<String> sendConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
  }) async* {
    if (!model.localPath.toLowerCase().endsWith('.litertlm')) {
      throw UnsupportedError(
        'The installed model artifact is ${model.runtimeArtifactId ?? model.localPath}. '
        'This runtime needs a .litertlm model.',
      );
    }
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    await previous;
    var finished = false;
    try {
      final type = modelTypeFor(model);
      for (var attempt = 0; ; attempt++) {
        final inference = await _load(model, maxTokens);
        final session = await _sessionFor(
          inference,
          messages,
          systemPrompt,
          maxTokens,
        );
        var turn = renderTurn(
          messages.sublist(session.history.length),
          hasEarlierTurns: session.history.isNotEmpty,
        );
        // Hybrid Qwen3 only stops reasoning on this soft switch.
        if (type == ModelType.qwen3) turn = '$turn /no_think';
        await session.session.addQueryChunk(
          Message.text(text: turn, isUser: true),
        );

        final answer = StringBuffer();
        var thought = 0;
        var thinking = false;
        await for (final response in ModelThinkingFilter.filterThinkingStream(
          session.session.getResponseAsync().map(TextResponse.new),
          modelType: type,
        )) {
          // Reasoning stays visible to the caller between <think> tags, which
          // the agent strips from the answer and shows as reasoning, instead
          // of vanishing and leaving a turn that only reasoned empty.
          if (response is ThinkingResponse) {
            if (response.content.isEmpty) continue;
            if (!thinking) {
              thinking = true;
              yield '<think>';
            }
            thought += response.content.length;
            yield response.content;
          } else if (response is TextResponse && response.token.isNotEmpty) {
            if (thinking) {
              thinking = false;
              yield '</think>';
            }
            answer.write(response.token);
            yield response.token;
          }
        }
        if (thinking) yield '</think>';

        if (answer.isEmpty && thought == 0) {
          final backend = inference.activeBackend;
          AppLogger.warning(
            '[LocalAI] ${model.displayName} produced no tokens on '
            '${backend?.name ?? "an unknown backend"} (attempt ${attempt + 1}).',
          );
          // Some bundles load on the GPU and then decode nothing at FP16;
          // the CPU runs the same file correctly, so retry there once.
          if (attempt == 0 && backend != PreferredBackend.cpu) {
            _cpuOnly.add(model.localPath);
            await releaseModelFiles();
            continue;
          }
        } else if (answer.isEmpty) {
          AppLogger.warning(
            '[LocalAI] ${model.displayName} only reasoned ($thought chars) '
            'and wrote no answer.',
          );
        }
        session.history = [
          ...messages,
          {'role': 'assistant', 'content': answer.toString()},
        ];
        finished = true;
        return;
      }
    } finally {
      if (!finished) {
        // Stopped or failed mid-turn: the session's history no longer matches
        // what the caller will send next, so the next request starts afresh.
        final session = _session;
        _session = null;
        if (session != null) {
          try {
            await session.session.stopGeneration();
          } catch (_) {}
          await _closeQuietly(session.session.close);
        }
      }
      done.complete();
    }
  }

  /// Text for one user turn holding [pending] messages. A fresh session that
  /// joins a conversation midway gets the earlier turns as a transcript,
  /// because LiteRT-LM only takes user turns from the app.
  static String renderTurn(
    List<Map<String, String>> pending, {
    required bool hasEarlierTurns,
  }) {
    if (pending.length == 1 && pending.single['role'] == 'user') {
      return pending.single['content'] ?? '';
    }
    final buffer = StringBuffer();
    if (!hasEarlierTurns && pending.length > 1) {
      buffer.writeln('Conversation so far:');
      buffer.writeln();
    }
    for (final message in pending) {
      buffer.writeln('[${message['role']}]');
      buffer.writeln(message['content']);
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  /// Whether [messages] only extend [history]: same turns, then new ones that
  /// the model did not write. Assistant turns are compared by role, since the
  /// caller may strip reasoning from what this session generated.
  static bool continues(
    List<Map<String, String>> history,
    List<Map<String, String>> messages,
  ) {
    if (history.isEmpty || messages.length <= history.length) return false;
    for (var i = 0; i < history.length; i++) {
      final before = history[i];
      final now = messages[i];
      if (before['role'] != now['role']) return false;
      if (before['role'] != 'assistant' &&
          before['content'] != now['content']) {
        return false;
      }
    }
    return messages
        .skip(history.length)
        .every((message) => message['role'] != 'assistant');
  }

  /// Picks the ChatML/Gemma template family LiteRT-LM needs for [model].
  static ModelType modelTypeFor(InstalledLocalModel model) {
    final name = '${model.catalogId} ${model.localPath}'.toLowerCase();
    if (name.contains('functiongemma') || name.contains('mobile_actions')) {
      return ModelType.functionGemma;
    }
    if (name.contains('gemma-4') ||
        name.contains('gemma4') ||
        name.contains('gemma_4')) {
      return ModelType.gemma4;
    }
    if (name.contains('gemma')) return ModelType.gemmaIt;
    if (name.contains('qwen3.5') ||
        name.contains('qwen3_5') ||
        name.contains('qwen3.6')) {
      return ModelType.qwen35;
    }
    if (name.contains('2507') || name.contains('qwen2')) return ModelType.qwen;
    if (name.contains('qwen3')) return ModelType.qwen3;
    if (name.contains('deepseek')) return ModelType.deepSeek;
    if (name.contains('llama')) return ModelType.llama;
    if (name.contains('phi')) return ModelType.phi;
    return ModelType.general;
  }

  Future<InferenceModel> _load(InstalledLocalModel model, int maxTokens) async {
    final loaded = _model;
    if (loaded != null &&
        _modelPath == model.localPath &&
        _contextTokens == maxTokens) {
      return loaded;
    }
    await releaseModelFiles();
    await (_initialization ??= FlutterEdgeAi.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
    ));
    await FlutterEdgeAi.installModel(
      modelType: modelTypeFor(model),
      fileType: ModelFileType.litertlm,
    ).fromFile(model.localPath).install();
    final backend = _cpuOnly.contains(model.localPath)
        ? PreferredBackend.cpu
        : preferredBackend;
    final inference = await FlutterEdgeAi.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: backend,
      enableSpeculativeDecoding: speculativeDecoding,
      maxConcurrentSessions: 1,
    );
    AppLogger.info(
      '[LocalAI] LiteRT-LM loaded ${model.displayName} '
      '(context $maxTokens, requested ${backend.name}, '
      'running ${inference.activeBackend?.name ?? "unknown"})',
    );
    _model = inference;
    _modelPath = model.localPath;
    _contextTokens = maxTokens;
    return inference;
  }

  /// A raw LiteRT-LM session, not an [InferenceChat]: the chat hides any
  /// reasoning when thinking is off (a turn that only reasoned comes back
  /// empty) and replays its own history when its token estimate runs out.
  Future<_Session> _sessionFor(
    InferenceModel inference,
    List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens,
  ) async {
    final current = _session;
    if (current != null &&
        current.systemPrompt == systemPrompt &&
        continues(current.history, messages)) {
      return current;
    }
    _session = null;
    if (current != null) await _closeQuietly(current.session.close);
    final session = await inference.createSession(
      temperature: 0.3,
      topK: 64,
      topP: 0.95,
      systemInstruction: systemPrompt,
      enableThinking: false,
      maxOutputTokens: maxTokens ~/ 4 < 2048 ? maxTokens ~/ 4 : 2048,
    );
    return _session = _Session(session, systemPrompt);
  }

  static Future<void> _closeQuietly(Future<void> Function() close) async {
    try {
      await close();
    } catch (e) {
      AppLogger.warning(
        '[LocalAI] Closing LiteRT-LM resource failed',
        error: e,
      );
    }
  }

  /// Unloads the model so its file can be moved or deleted.
  @override
  Future<void> releaseModelFiles() async {
    final session = _session;
    _session = null;
    if (session != null) await _closeQuietly(session.session.close);
    final model = _model;
    _model = null;
    _modelPath = null;
    _contextTokens = null;
    if (model != null) await _closeQuietly(model.close);
  }

  @override
  Future<void> dispose() => releaseModelFiles();
}

class _Session {
  final InferenceModelSession session;
  final String? systemPrompt;

  /// The conversation as the caller sent it, plus the answer generated last.
  List<Map<String, String>> history = const [];

  _Session(this.session, this.systemPrompt);
}
