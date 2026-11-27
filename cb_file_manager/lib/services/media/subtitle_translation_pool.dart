import 'dart:io';

import '../../models/local_ai/local_ai_advisor_model.dart';
import '../local_ai/gguf_llama_cpp_runtime.dart';

/// A session owns a handle, not necessarily the underlying llama process.
abstract interface class SubtitleTranslator {
  Future<void> prepareModel({required InstalledLocalModel model});

  Stream<String> sendDirectConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    required int maxTokens,
  });

  Future<void> dispose();
}

/// Interactive playback still owns its dedicated, low-latency server.
class DedicatedSubtitleTranslator implements SubtitleTranslator {
  final GgufLlamaCppLocalAiChatRuntime runtime;
  DedicatedSubtitleTranslator(this.runtime);

  @override
  Future<void> prepareModel({required InstalledLocalModel model}) =>
      runtime.prepareModel(model: model);

  @override
  Stream<String> sendDirectConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    required int maxTokens,
  }) => runtime.sendDirectConversationStream(
    model: model,
    messages: messages,
    maxTokens: maxTokens,
  );

  @override
  Future<void> dispose() => runtime.dispose();
}

/// One llama.cpp server per translation artifact in the queue runner isolate.
/// Independent HTTP connections allow llama.cpp to continuously batch requests
/// without any session owning (or killing) another session's inference.
class SubtitleTranslationPool {
  final int slots;
  final GgufLlamaCppLocalAiChatRuntime Function(int slots) createRuntime;
  final _entries = <String, _TranslationEntry>{};
  final _closing = <String, Future<void>>{};

  SubtitleTranslationPool({
    required this.slots,
    GgufLlamaCppLocalAiChatRuntime Function(int slots)? createRuntime,
    void Function(Process)? onProcessStarted,
  }) : assert(slots >= 1 && slots <= 8),
       createRuntime =
           createRuntime ??
           ((slots) => _defaultRuntime(slots, onProcessStarted));

  static GgufLlamaCppLocalAiChatRuntime _defaultRuntime(
    int slots,
    void Function(Process)? onProcessStarted,
  ) => GgufLlamaCppLocalAiChatRuntime(
    onProcessStarted: onProcessStarted,
    parallelSlots: slots,
    maxResponseTokens: 512,
    allowCpuFallback: true,
    backgroundInference: true,
    threads: (Platform.numberOfProcessors ~/ 2).clamp(1, 6),
  );

  SubtitleTranslator acquire(InstalledLocalModel model) {
    final key = model.localPath;
    final entry = _entries.putIfAbsent(
      key,
      () => _TranslationEntry(
        model,
        createRuntime(slots),
        // llama.cpp divides its total context across the parallel slots.
        contextTokens: 2048 * slots,
        predecessor: _closing[key],
      ),
    );
    entry.users++;
    return _PooledSubtitleTranslator(entry, () => _release(key, entry));
  }

  Future<void> _release(String key, _TranslationEntry entry) async {
    if (--entry.users != 0) return;
    _entries.remove(key);
    final closing = entry.close();
    _closing[key] = closing;
    try {
      await closing;
    } finally {
      if (identical(_closing[key], closing)) _closing.remove(key);
    }
  }
}

class _TranslationEntry {
  final InstalledLocalModel model;
  final GgufLlamaCppLocalAiChatRuntime runtime;
  final int contextTokens;
  final Future<void>? predecessor;
  int users = 0;
  bool _closed = false;
  Future<void>? _preparing;

  _TranslationEntry(
    this.model,
    this.runtime, {
    required this.contextTokens,
    required this.predecessor,
  });

  Future<void> prepare() {
    if (_closed) return Future.error(StateError('Subtitle translator closed'));
    return _preparing ??= _prepare().whenComplete(() => _preparing = null);
  }

  Future<void> _prepare() async {
    // Re-acquisition while the last lease is closing must not load another
    // copy of the same weights before the old process releases its VRAM.
    await predecessor;
    if (_closed) throw StateError('Subtitle translator closed');
    await runtime.prepareSharedModel(
      model: model,
      contextTokens: contextTokens,
    );
  }

  Future<void> close() async {
    _closed = true;
    final preparing = _preparing;
    await runtime.dispose();
    // Dispose interrupts a pending start; wait for it to finish before a
    // successor starts another native process for this model.
    if (preparing != null) {
      try {
        await preparing;
      } catch (_) {
        // Closing can intentionally interrupt model initialization.
      }
    }
    await predecessor;
  }
}

class _PooledSubtitleTranslator implements SubtitleTranslator {
  final _TranslationEntry _entry;
  final Future<void> Function() _release;
  final _client = HttpClient();
  Future<void>? _disposal;

  _PooledSubtitleTranslator(this._entry, this._release);

  void _check(InstalledLocalModel model) {
    if (_disposal != null || _entry.model.localPath != model.localPath) {
      throw StateError('Subtitle translation lease is no longer valid');
    }
  }

  @override
  Future<void> prepareModel({required InstalledLocalModel model}) async {
    _check(model);
    try {
      await _entry.prepare();
    } catch (error) {
      // The queue already retries unavailable worker runtimes, restoring the
      // saved ranges rather than failing every job attached to this server.
      throw StateError('Subtitle runtime is unavailable (translation): $error');
    }
    _check(model);
  }

  @override
  Stream<String> sendDirectConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    required int maxTokens,
  }) async* {
    // A dead server is restarted once by the entry, not once per request.
    await prepareModel(model: model);
    try {
      await for (final chunk
          in _entry.runtime.sendPreparedDirectConversationStream(
            model: model,
            messages: messages,
            requestClient: _client,
            contextTokens: _entry.contextTokens,
          )) {
        yield chunk;
      }
    } catch (error) {
      if (error is SocketException ||
          error is HttpException ||
          (error is StateError &&
              (error.message ==
                      'Shared subtitle translation server is not ready' ||
                  error.message ==
                      'The local model response was interrupted. Please retry.'))) {
        throw StateError(
          'Subtitle runtime is unavailable (translation): $error',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    // Force-close only this job's socket, even during a streamed response.
    _client.close(force: true);
    await _release();
  }
}
