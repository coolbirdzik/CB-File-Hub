import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/local_ai/local_ai_advisor_model.dart';
import '../local_ai/gguf_llama_cpp_runtime.dart';
import '../local_ai/local_ai_advisor_service.dart';
import 'media_kit_playback.dart';
import 'subtitle_preferences.dart';
import 'subtitle_worker.dart';
import 'subtitle_progress.dart';
import 'subtitle_cache.dart';

export 'subtitle_progress.dart';
export 'subtitle_cache.dart' show LocalSubtitleCue;

/// Bounded look-ahead for seekable desktop media. Native code owns all PCM and
/// model work; this class schedules small cue messages against the media clock.
class LocalSubtitleSession extends ChangeNotifier {
  final PlaybackPlayer player;
  final SubtitlePreferences preferences;
  final LocalAiAdvisorService models;
  final SubtitleCache? cache;
  final Future<String?> Function()? sourceFingerprint;
  String? _cacheKey;
  bool _cacheChecked = false;
  int? _cacheRevision;
  int _cacheReadPosition = -100000;
  int? _cacheTrack;
  SubtitleCacheState _cacheState = SubtitleCacheState.unavailable;
  bool get canRegenerate => cache != null && _cacheKey != null;
  final SubtitleWorker Function() createWorker;
  final GgufLlamaCppLocalAiChatRuntime Function() createTranslator;
  Future<(Object, StackTrace)?>? _translationPreparation;
  final Future<String> Function(InstalledLocalModel, String, String)?
  translateText;
  final List<LocalSubtitleCue> _cues = [];
  LocalSubtitleCue? _partialCue;
  final List<SubtitleTimeRange> _completed = [];
  SubtitleTimeRange? _pending;
  SubtitleWorkStage _stage = SubtitleWorkStage.idle;
  String? _modelName;
  String? _detectedLanguage;
  int _lastProgressSecond = -1;
  bool _lastLagging = false;
  int _lastDurationMs = 0;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _releases = <LocalModelPurpose, void Function()>{};
  SubtitleWorker? _worker;
  String? _workerModelPath, _translatorModelPath;
  bool _workerLoading = false, _translationBusy = false;
  _RecognitionTask? _recognitionTask, _prefetched;
  int _lookAheadMs = 12000;
  double _processingMs = 0;
  late String _settingsSnapshot = _settingsSignature;
  late String _modelsSnapshot = _modelsSignature;
  late String _audioSelection = player.state.track.audio.id;
  final _clock = Stopwatch()..start();
  int _lastTickMs = 0;
  GgufLlamaCppLocalAiChatRuntime? _translator;
  Timer? _timer;
  Timer? _refreshTimer;
  Timer? _seekDebounce;
  bool _refreshing = false;
  int _generation = 0, _nextMs = 0, _lastPosition = 0;
  int? _busyGeneration;
  bool _disposed = false;
  SubtitlePhase phase = SubtitlePhase.off;
  String? error;
  String _text = '', _original = '';
  String get text => _text;
  String get original => _original;
  bool get lagging =>
      preferences.enabled &&
      (phase == SubtitlePhase.processing || phase == SubtitlePhase.loading) &&
      player.state.position.inMilliseconds > _nextMs + 2000;
  List<LocalSubtitleCue> get cues => List.unmodifiable(_cues);
  SubtitleProgress get progress => SubtitleProgress(
    phase: phase,
    stage: _stage,
    modelName: _modelName,
    duration: player.state.duration,
    position: player.state.position,
    completed: List.unmodifiable(_completed),
    pending: _pending,
    lagging: lagging,
    error: error,
    cacheState: _cacheState,
    sourceLanguage: preferences.resolvedSourceLanguage == 'auto'
        ? (_detectedLanguage ?? 'auto')
        : preferences.resolvedSourceLanguage,
    targetLanguage: preferences.resolvedTarget,
  );

  void _work(SubtitleWorkStage stage, String name) {
    _stage = stage;
    _modelName = name;
    notifyListeners();
  }

  void _markProcessed(int start, int end) {
    if (end <= start) return;
    final from = Duration(milliseconds: start);
    final to = Duration(milliseconds: end);
    final sorted = [..._completed, SubtitleTimeRange(from, to)]
      ..sort((a, b) => a.start.compareTo(b.start));
    _completed.clear();
    for (final range in sorted) {
      if (_completed.isNotEmpty && _completed.last.end >= range.start) {
        final old = _completed.removeLast();
        _completed.add(
          SubtitleTimeRange(
            old.start,
            old.end > range.end ? old.end : range.end,
          ),
        );
      } else {
        _completed.add(range);
      }
    }
  }

  LocalSubtitleSession({
    required this.player,
    required this.preferences,
    required this.models,
    SubtitleWorker Function()? createWorker,
    GgufLlamaCppLocalAiChatRuntime Function()? createTranslator,
    this.translateText,
    this.cache,
    this.sourceFingerprint,
  }) : createWorker = createWorker ?? SubtitleWorker.new,
       createTranslator =
           createTranslator ??
           (() => GgufLlamaCppLocalAiChatRuntime(
             maxResponseTokens: 512,
             allowCpuFallback: true,
             parallelSlots: 1,
             threads: (Platform.numberOfProcessors ~/ 2).clamp(1, 6),
           )) {
    _audioSelection = player.state.track.audio.id;
    preferences.addListener(_preferencesChanged);
    _subscriptions.add(
      models.onInstalledModelsChanged.listen((_) {
        if (_modelsSnapshot != _modelsSignature) restart();
      }),
    );
    _subscriptions.add(
      player.stream.track.listen((track) {
        if (track.audio.id != _audioSelection) {
          _audioSelection = track.audio.id;
          _restart(debounce: true);
        }
      }),
    );
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refresh(),
    );
    restart();
  }

  Future<void> _refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      await models.refreshInstalledModels();
      if (!_disposed) await preferences.refresh();
      if (!_disposed &&
          cache != null &&
          _cacheRevision != null &&
          await cache!.revision() != _cacheRevision) {
        restart();
      }
    } catch (_) {
      // A transient preference-store read must not interrupt ongoing playback.
    } finally {
      _refreshing = false;
    }
  }

  InstalledLocalModel? _model(String id, LocalModelPurpose purpose) {
    for (final model in models.getManagedModels()) {
      if (model.catalogId == id && model.purpose == purpose) return model;
    }
    return null;
  }

  String get _settingsSignature =>
      '${preferences.enabled}|${preferences.speechModel}|'
      '${preferences.translationModel}|${preferences.resolvedSourceLanguage}|${preferences.resolvedTarget}';
  String get _modelsSignature => [
    _model(preferences.speechModel, LocalModelPurpose.speech)?.toJson(),
    _model(
      preferences.translationModel,
      LocalModelPurpose.translation,
    )?.toJson(),
  ].toString();

  void _preferencesChanged() {
    if (_settingsSnapshot != _settingsSignature) {
      restart();
    } else {
      // Display-only changes must not unload models or invalidate finished text.
      notifyListeners();
    }
  }

  bool get _needsWork =>
      !_disposed &&
      preferences.enabled &&
      _seekDebounce?.isActive != true &&
      phase != SubtitlePhase.failed &&
      phase != SubtitlePhase.missingModels &&
      ((_nextMs < player.state.duration.inMilliseconds &&
              _nextMs <= player.state.position.inMilliseconds + _lookAheadMs) ||
          (_cacheKey != null &&
              player.state.position.inMilliseconds - _cacheReadPosition >=
                  10000));

  void _drive() {
    if (_needsWork && _busyGeneration == null) unawaited(_process(_generation));
  }

  void _dropWorker() {
    final old = _worker;
    _worker = null;
    _workerModelPath = null;
    _workerLoading = false;
    _releases.remove(LocalModelPurpose.speech)?.call();
    if (old != null) unawaited(old.stop());
  }

  void _dropTranslator() {
    final old = _translator;
    _translator = null;
    _translatorModelPath = null;
    _translationBusy = false;
    _translationPreparation = null;
    _releases.remove(LocalModelPurpose.translation)?.call();
    if (old != null) unawaited(old.dispose());
  }

  void restart() => _restart();

  void _restart({bool debounce = false}) {
    if (_disposed) return;
    _settingsSnapshot = _settingsSignature;
    _modelsSnapshot = _modelsSignature;
    _seekDebounce?.cancel();
    _seekDebounce = null;
    final speechPath = _model(
      preferences.speechModel,
      LocalModelPurpose.speech,
    )?.localPath;
    final translationPath = _model(
      preferences.translationModel,
      LocalModelPurpose.translation,
    )?.localPath;
    if (!preferences.enabled ||
        _workerModelPath != speechPath ||
        _workerLoading ||
        _recognitionTask?.done == false) {
      _dropWorker();
    }
    if (!preferences.enabled ||
        _translatorModelPath != translationPath ||
        _translationBusy) {
      _dropTranslator();
    }
    _recognitionTask = null;
    _prefetched = null;
    _generation++;
    _nextMs = player.state.position.inMilliseconds;
    _lastPosition = _nextMs;
    _lastTickMs = _clock.elapsedMilliseconds;
    _cues.clear();
    _partialCue = null;
    _completed.clear();
    _cacheKey = null;
    _cacheChecked = false;
    _cacheRevision = null;
    _cacheReadPosition = -100000;
    _cacheTrack = null;
    _cacheState = cache == null
        ? SubtitleCacheState.unavailable
        : SubtitleCacheState.checking;
    _pending = null;
    _stage = preferences.enabled
        ? SubtitleWorkStage.loadingSpeech
        : SubtitleWorkStage.idle;
    _modelName = models.catalogEntryFor(preferences.speechModel)?.displayName;
    _detectedLanguage = null;
    _lastProgressSecond = -1;
    _text = '';
    _original = '';
    error = null;
    phase = preferences.enabled ? SubtitlePhase.loading : SubtitlePhase.off;
    notifyListeners();
    if (preferences.enabled) {
      if (debounce) {
        _seekDebounce = Timer(const Duration(milliseconds: 200), () {
          _seekDebounce = null;
          _drive();
        });
      } else {
        unawaited(_process(_generation));
      }
    }
  }

  void _tick() {
    if (_disposed || !preferences.enabled) return;
    final position = player.state.position.inMilliseconds;
    // Continuous playback changes at most ~400 ms/tick at 2x; a larger jump
    // cancels both native and translation work instead of showing stale text.
    final elapsed = _clock.elapsedMilliseconds - _lastTickMs;
    _lastTickMs = _clock.elapsedMilliseconds;
    final expectedAdvance = math.max(
      1800,
      elapsed * player.state.rate * 1.5 + 500,
    );
    if (position < _lastPosition - 500 ||
        position > _lastPosition + expectedAdvance) {
      _restart(debounce: true);
      return;
    }
    _lastPosition = position;
    final visible = [
      ..._cues,
      ?_partialCue,
    ].where((c) => c.startMs <= position && position < c.endMs).toList();
    final text = visible.map((c) => c.text).join('\n');
    final original = visible.map((c) => c.original).join('\n');
    final currentLagging = lagging;
    final currentDuration = player.state.duration.inMilliseconds;
    if (text != _text ||
        original != _original ||
        position ~/ 1000 != _lastProgressSecond ||
        currentLagging != _lastLagging ||
        currentDuration != _lastDurationMs) {
      _text = text;
      _original = original;
      _lastProgressSecond = position ~/ 1000;
      _lastLagging = currentLagging;
      _lastDurationMs = currentDuration;
      notifyListeners();
    }
    if (_nextMs < position - 8000 && _busyGeneration == null) {
      restart();
      return;
    }
    _drive();
  }

  /// Clears this video/configuration and cancels work before starting again.
  Future<void> regenerate() async {
    final key = _cacheKey;
    if (cache == null || key == null) return;
    _generation++;
    try {
      await cache!.clear(key: key);
      if (!_disposed) restart();
    } catch (_) {
      if (!_disposed) {
        _cacheState = SubtitleCacheState.failed;
        restart();
      }
      rethrow;
    }
  }

  String _modelVersion(String id) {
    final entry = models.catalogEntryFor(id);
    return '${entry?.sha256 ?? entry?.revision ?? 'unknown'}:${entry?.artifactFileName ?? id}';
  }

  Future<void> _readCache(int generation, String source, int track) async {
    if (cache == null) return;
    try {
      if (_cacheTrack != null && _cacheTrack != track) {
        restart();
        return;
      }
      _cacheTrack = track;
      if (!_cacheChecked) {
        _work(SubtitleWorkStage.readingCache, '');
        final fingerprint =
            await (sourceFingerprint?.call() ??
                subtitleSourceFingerprint(
                  player.subtitleCacheSource ?? source,
                  source,
                ));
        if (generation != _generation) return;
        _cacheChecked = true;
        if (fingerprint == null) {
          _cacheState = SubtitleCacheState.unavailable;
          return;
        }
        _cacheKey = subtitleCacheDigest([
          preferences.resolvedSourceLanguage == 'auto'
              ? 'subtitle-pipeline-auto-v2'
              : 'subtitle-pipeline-v1',
          fingerprint,
          player.state.duration.inMilliseconds,
          track,
          preferences.speechModel,
          _modelVersion(preferences.speechModel),
          preferences.resolvedSourceLanguage,
          preferences.translationModel,
          _modelVersion(preferences.translationModel),
          preferences.resolvedTarget,
        ]);
      }
      final key = _cacheKey;
      if (key == null) return;
      final position = player.state.position.inMilliseconds;
      final snapshot = await cache!.read(
        key,
        math.max(0, position - 60000),
        position + 30000,
      );
      if (generation != _generation) return;
      if (_cacheRevision != null && snapshot.revision != _cacheRevision) {
        restart();
        return;
      }
      _cacheRevision = snapshot.revision;
      _cacheReadPosition = position;
      _completed
        ..clear()
        ..addAll(snapshot.ranges);
      final byTime = {
        for (final c in [..._cues, ...snapshot.cues])
          '${c.startMs}:${c.endMs}': c,
      };
      _cues
        ..clear()
        ..addAll(byTime.values);
      _cues.sort((a, b) => a.startMs.compareTo(b.startMs));
      _cues.removeWhere((c) => c.endMs < position - 60000);
      _cacheState = snapshot.ranges.isEmpty
          ? SubtitleCacheState.automatic
          : SubtitleCacheState.reused;
      for (final range in _completed) {
        if (_nextMs >= range.start.inMilliseconds &&
            _nextMs < range.end.inMilliseconds) {
          _nextMs = range.end.inMilliseconds;
        }
      }
    } catch (_) {
      if (generation != _generation) return;
      _cacheChecked = true;
      _cacheKey = null;
      _cacheState = SubtitleCacheState.failed;
    }
  }

  Future<void> _releaseForManagement() async {
    final worker = _worker;
    final translator = _translator;
    _worker = null;
    _translator = null;
    _workerModelPath = null;
    _translatorModelPath = null;
    _translationPreparation = null;
    for (final release in _releases.values) {
      release();
    }
    _releases.clear();
    _prefetched = null;
    _recognitionTask = null;
    _generation++;
    _cues.clear();
    _partialCue = null;
    _completed.clear();
    _pending = null;
    _stage = SubtitleWorkStage.idle;
    _text = '';
    _original = '';
    phase = SubtitlePhase.missingModels;
    await Future.wait([
      if (worker != null) worker.stop(),
      if (translator != null) translator.dispose(),
    ]);
    if (!_disposed) notifyListeners();
  }

  int _unprocessedAt(int position) {
    for (final range in _completed) {
      if (position >= range.start.inMilliseconds &&
          position < range.end.inMilliseconds) {
        position = range.end.inMilliseconds;
      }
    }
    return position;
  }

  int _chunkEnd(int position, int duration) {
    var end = math.min(duration, position + 8000);
    for (final range in _completed) {
      if (range.start.inMilliseconds > position) {
        end = math.min(end, range.start.inMilliseconds);
        break;
      }
    }
    return end;
  }

  _RecognitionTask _recognize(
    int generation,
    String source,
    int selected,
    int chunkStart,
    int end,
  ) {
    final start = math.max(0, chunkStart - 800);
    final hint = player.subtitleAudioLanguageForOrdinal(selected);
    final task = _RecognitionTask(
      generation,
      chunkStart,
      end,
      selected,
      _worker!.request({
        'command': 'transcribe',
        'source': source,
        'start_ms': start,
        'duration_ms': math.max(1000, end - start),
        'audio_track': math.max(0, selected),
        'language': preferences.resolvedSourceLanguage,
        if (hint != null &&
            subtitleSourceLanguagesFor(
              preferences.speechModel,
            ).containsKey(hint))
          'language_hint': hint,
      }),
    );
    _recognitionTask = task;
    return task;
  }

  void _prepareTranslation(InstalledLocalModel model) {
    if (_translator != null || translateText != null) return;
    final runtime = createTranslator();
    _translator = runtime;
    _translatorModelPath = model.localPath;
    _translationBusy = true;
    _releases[LocalModelPurpose.translation] = models.registerModelUse(
      model.catalogId,
      _releaseForManagement,
    );
    _translationPreparation = runtime
        .prepareModel(model: model)
        .then<(Object, StackTrace)?>(
          (_) {
            if (identical(_translator, runtime)) _translationBusy = false;
            return null;
          },
          onError: (Object error, StackTrace trace) {
            if (identical(_translator, runtime)) _translationBusy = false;
            return (error, trace);
          },
        );
  }

  Future<void> _process(int generation) async {
    if (_disposed || _busyGeneration != null || generation != _generation) {
      return;
    }
    final source = player.subtitleSource;
    if (source == null) return;
    if (_nextMs < player.state.position.inMilliseconds - 8000) {
      restart();
      return;
    }
    if (player.state.duration == Duration.zero) {
      if (player.state.position.inSeconds > 5) {
        phase = SubtitlePhase.failed;
        _stage = SubtitleWorkStage.idle;
        error =
            'This source has no seekable timeline. Live streams are not supported yet.';
        notifyListeners();
      }
      return;
    }
    _busyGeneration = generation;
    final processing = Stopwatch()..start();
    final target = preferences.resolvedTarget;
    try {
      final selected = await player.subtitleAudioTrackOrdinal();
      if (generation != _generation) return;
      await _readCache(generation, source, selected);
      if (generation != _generation) return;
      final duration = player.state.duration.inMilliseconds;
      if (_nextMs >= duration ||
          _nextMs > player.state.position.inMilliseconds + _lookAheadMs) {
        phase = SubtitlePhase.ready;
        _stage = SubtitleWorkStage.idle;
        _modelName = null;
        _pending = null;
        return;
      }
      final speech = _model(preferences.speechModel, LocalModelPurpose.speech);
      if (speech == null || !await File(speech.localPath).exists()) {
        if (generation != _generation) return;
        phase = SubtitlePhase.missingModels;
        _stage = SubtitleWorkStage.idle;
        _modelName = models
            .catalogEntryFor(preferences.speechModel)
            ?.displayName;
        return;
      }
      if (generation != _generation) return;
      if (preferences.resolvedSourceLanguage != 'auto' &&
          preferences.resolvedSourceLanguage != target &&
          _translator == null &&
          translateText == null) {
        final model = _model(
          preferences.translationModel,
          LocalModelPurpose.translation,
        );
        if (model != null &&
            await File(model.localPath).exists() &&
            generation == _generation) {
          _prepareTranslation(model);
        }
      }
      if (generation != _generation) return;
      if (_worker == null) {
        phase = SubtitlePhase.loading;
        _work(SubtitleWorkStage.loadingSpeech, speech.displayName);
        final worker = createWorker();
        _worker = worker;
        _workerModelPath = speech.localPath;
        _workerLoading = true;
        _releases[LocalModelPurpose.speech] = models.registerModelUse(
          speech.catalogId,
          _releaseForManagement,
        );
        try {
          await worker.start(speech.localPath);
        } finally {
          if (identical(_worker, worker)) _workerLoading = false;
        }
      }
      if (generation != _generation) return;
      if (_nextMs < player.state.position.inMilliseconds - 8000) {
        // Model startup can finish after playback has moved on. Keep the warm
        // model and start where the user is, without decoding expired chunks.
        _nextMs = player.state.position.inMilliseconds;
      }
      if (_nextMs >= duration) {
        phase = SubtitlePhase.ready;
        _stage = SubtitleWorkStage.idle;
        _pending = null;
        return;
      }
      final chunkStart = _nextMs;
      final start = math.max(0, _nextMs - 800);
      final end = _chunkEnd(chunkStart, duration);
      _pending = SubtitleTimeRange(
        Duration(milliseconds: chunkStart),
        Duration(milliseconds: end),
      );
      phase = SubtitlePhase.processing;
      _work(SubtitleWorkStage.recognizing, speech.displayName);
      final queued = _prefetched;
      _prefetched = null;
      final task =
          queued != null &&
              queued.generation == generation &&
              queued.start == chunkStart &&
              queued.end == end &&
              queued.track == selected
          ? queued
          : _recognize(generation, source, selected, chunkStart, end);
      final result = (await task.future).value;
      if (generation != _generation) return;
      final language =
          result['language'] as String? ?? preferences.resolvedSourceLanguage;
      _detectedLanguage = language;
      final segments = result['segments'] as List<dynamic>? ?? [];
      final needsTranslation = segments.isNotEmpty && language != target;
      final translation = _model(
        preferences.translationModel,
        LocalModelPurpose.translation,
      );
      if (needsTranslation &&
          (translation == null ||
              !await File(translation.localPath).exists())) {
        phase = SubtitlePhase.missingModels;
        _stage = SubtitleWorkStage.idle;
        _pending = null;
        _modelName = models
            .catalogEntryFor(preferences.translationModel)
            ?.displayName;
        notifyListeners();
        return;
      }
      if (generation != _generation) return;
      // A single bounded look-ahead request overlaps CPU/GPU recognition with
      // translation. No PCM or model tensors cross into the Flutter isolate.
      final next = _unprocessedAt(end);
      if (next < duration &&
          next <= player.state.position.inMilliseconds + _lookAheadMs) {
        _prefetched = _recognize(
          generation,
          source,
          selected,
          next,
          _chunkEnd(next, duration),
        );
      }
      final chunkCues = <LocalSubtitleCue>[];
      LocalSubtitleCue? previous;
      for (final cue in _cues) {
        if (cue.startMs < chunkStart &&
            (previous == null || cue.endMs > previous.endMs)) {
          previous = cue;
        }
      }
      for (final raw in segments) {
        if (generation != _generation) return;
        final segment = raw as Map<String, dynamic>;
        var original = (segment['text'] as String).trim();
        var from = (segment['start_ms'] as num).toInt().clamp(start, end);
        final to = (segment['end_ms'] as num).toInt().clamp(from, end);
        if (original.isEmpty || to <= from) continue;
        if (previous != null && from < previous.endMs) {
          if (to <= previous.endMs) continue;
          original = trimSubtitleOverlap(previous.original, original);
          from = previous.endMs;
          if (original.isEmpty) continue;
        }
        String text = original;
        if (needsTranslation && translation != null) {
          if (translateText != null) {
            _work(SubtitleWorkStage.translating, translation.displayName);
            text = await translateText!(translation, original, target);
          } else {
            _work(
              _translator == null || _translationBusy
                  ? SubtitleWorkStage.loadingTranslation
                  : SubtitleWorkStage.translating,
              translation.displayName,
            );
            _prepareTranslation(translation);
            final preparation = await _translationPreparation;
            if (generation != _generation) return;
            if (preparation != null) {
              Error.throwWithStackTrace(preparation.$1, preparation.$2);
            }
            _work(SubtitleWorkStage.translating, translation.displayName);
            final output = StringBuffer();
            final translator = _translator!;
            _translationBusy = true;
            try {
              await for (final chunk in translator.sendDirectConversationStream(
                model: translation,
                maxTokens: 2048,
                messages: [
                  {
                    'role': 'user',
                    'content':
                        'Translate the following text into ${subtitleLanguageEnglishName(target)}. '
                        'Output only the translation without explanation.\n$original',
                  },
                ],
              )) {
                if (generation != _generation) return;
                if (chunk == '[STATUS]Ready' || !chunk.startsWith('[STATUS]')) {
                  if (_stage != SubtitleWorkStage.translating) {
                    _work(
                      SubtitleWorkStage.translating,
                      translation.displayName,
                    );
                  }
                }
                if (!chunk.startsWith('[STATUS]')) {
                  output.write(chunk);
                  _partialCue = LocalSubtitleCue(
                    from,
                    to,
                    original,
                    output.toString().trim(),
                  );
                }
              }
            } finally {
              if (identical(_translator, translator)) _translationBusy = false;
            }
            text = output.toString().trim();
            if (text.isEmpty) throw StateError('Translation returned no text');
          }
        }
        if (generation != _generation) return;
        previous = LocalSubtitleCue(from, to, original, text);
        _partialCue = null;
        chunkCues.add(previous);
        // Publish complete translated cues immediately; the timeline and DB
        // commit still wait for the whole chunk to finish successfully.
        _cues.add(previous);
      }
      if (generation != _generation) return;
      if (cache != null && _cacheKey != null && _cacheRevision != null) {
        try {
          final saved = await cache!.save(
            _cacheKey!,
            _cacheRevision!,
            chunkStart,
            end,
            chunkCues,
          );
          if (generation != _generation) return;
          if (!saved) {
            restart();
            return;
          }
          _cacheState = SubtitleCacheState.saved;
        } catch (_) {
          if (generation != _generation) return;
          _cacheState = SubtitleCacheState.failed;
          _cacheKey = null;
        }
      }
      _cues.sort((a, b) => a.startMs.compareTo(b.startMs));
      _markProcessed(chunkStart, end);
      _nextMs = end;
      _pending = null;
      _stage = SubtitleWorkStage.idle;
      // Keep at most two minutes of cues and no more than 256 segments.
      _cues.removeWhere(
        (c) => c.endMs < player.state.position.inMilliseconds - 60000,
      );
      if (_cues.length > 256) _cues.removeRange(0, _cues.length - 256);
      phase = SubtitlePhase.ready;
      _processingMs = _processingMs == 0
          ? processing.elapsedMilliseconds.toDouble()
          : _processingMs * .75 + processing.elapsedMilliseconds * .25;
      _lookAheadMs = (8000 + _processingMs * player.state.rate * 2)
          .round()
          .clamp(12000, 40000);
    } catch (e) {
      if (generation == _generation && !_disposed) {
        phase = SubtitlePhase.failed;
        _stage = SubtitleWorkStage.idle;
        _pending = null;
        error = e.toString();
        _partialCue = null;
        _dropWorker();
        _dropTranslator();
        _prefetched = null;
      }
    } finally {
      if (_busyGeneration == generation) _busyGeneration = null;
      if (!_disposed) notifyListeners();
      // Fill the runway without an extra 100–200 ms polling gap per chunk.
      if (_needsWork) scheduleMicrotask(_drive);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _refreshTimer?.cancel();
    _seekDebounce?.cancel();
    preferences.removeListener(_preferencesChanged);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    for (final release in _releases.values) {
      release();
    }
    final worker = _worker;
    final translator = _translator;
    if (worker != null) unawaited(worker.stop());
    if (translator != null) unawaited(translator.dispose());
    super.dispose();
  }
}

class _RecognitionTask {
  final int generation, start, end, track;
  bool done = false;
  late final Future<_RecognitionOutcome> future;
  _RecognitionTask(
    this.generation,
    this.start,
    this.end,
    this.track,
    Future<Map<String, dynamic>> request,
  ) {
    // A discarded prefetch must absorb cancellation errors until consumed.
    future = request.then(
      (value) {
        done = true;
        return _RecognitionOutcome(value, null, null);
      },
      onError: (Object error, StackTrace trace) {
        done = true;
        return _RecognitionOutcome(null, error, trace);
      },
    );
  }
}

class _RecognitionOutcome {
  final Map<String, dynamic>? _value;
  final Object? error;
  final StackTrace? trace;
  const _RecognitionOutcome(this._value, this.error, this.trace);
  Map<String, dynamic> get value {
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return _value!;
  }
}

/// Remove a repeated suffix/prefix from overlapping recognition windows.
/// Word boundaries keep English/Vietnamese matches from eating word fragments;
/// unspaced CJK text uses character overlap instead.
String trimSubtitleOverlap(String previous, String next) {
  final words = RegExp(r'\S+').allMatches(next).toList();
  final previousWords = previous.split(RegExp(r'\s+'));
  String key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[.,!?;:，。！？、]'), '');
  for (
    var count = math.min(words.length, previousWords.length);
    count > 0;
    count--
  ) {
    final tail = previousWords
        .sublist(previousWords.length - count)
        .map(key)
        .join(' ');
    final head = words.take(count).map((m) => key(m.group(0)!)).join(' ');
    if (tail.isNotEmpty && tail == head) {
      return next.substring(words[count - 1].end).trimLeft();
    }
  }
  if (!previous.contains(' ') && !next.contains(' ')) {
    for (
      var n = math.min(128, math.min(previous.length, next.length));
      n > 0;
      n--
    ) {
      if (previous.endsWith(next.substring(0, n))) return next.substring(n);
    }
  }
  return next;
}
