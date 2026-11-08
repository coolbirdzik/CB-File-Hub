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
import 'subtitle_srt.dart';

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

  /// Full players generate to the end of the media, paused or not. A compact
  /// preview (the file browser pane) stays within [previewRunwayMs] of the
  /// playhead so selecting a video does not process the whole file.
  final bool continuous;
  static const previewRunwayMs = 30000;

  /// Writes SRT sidecars in the automatic file modes.
  final SubtitleSrtWriter srtWriter;
  String? _exportToken;
  bool _committedThisGeneration = false;
  bool _exportPrompt = false;
  bool _nonLocalReported = false;
  SubtitleExportNotice? _exportNotice;
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

  /// Smoothed native recognition time; null until one chunk was measured.
  double? _recognitionMs;

  /// Measured time to load the speech worker, the cost of killing it.
  int? _workerLoadMs;

  /// Set after a cache failure that may have lost evicted cues; the session
  /// then regenerates in memory instead of trusting stale processed ranges.
  bool _cacheDisabled = false;

  /// Advanced by seeks. A chunk started for an older cursor is abandoned
  /// without unloading models; [_generation] still guards setting changes.
  int _epoch = 0;
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
      player.state.position.inMilliseconds > _nextMs + 2000 &&
      _unprocessedAt(player.state.position.inMilliseconds) ==
          player.state.position.inMilliseconds;
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
    this.continuous = true,
    SubtitleSrtWriter? srtWriter,
  }) : srtWriter = srtWriter ?? SubtitleSrtWriter(preferences.prefs),
       createWorker = createWorker ?? SubtitleWorker.new,
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
      // A new file mode may need a sidecar for subtitles that are already done.
      _checkExport();
      notifyListeners();
    }
  }

  /// "Ask" mode: true once after the whole video was generated in this
  /// session. The UI consumes it and offers a save action; it never opens a
  /// dialog by itself.
  bool takeExportPrompt() {
    final prompt = _exportPrompt;
    _exportPrompt = false;
    return prompt;
  }

  /// The latest automatic sidecar result, consumed by the UI once.
  SubtitleExportNotice? takeExportNotice() {
    final notice = _exportNotice;
    _exportNotice = null;
    return notice;
  }

  /// Language code used in exported file names (`video.<code>.srt`).
  String get exportLanguage => preferences.resolvedTarget;

  /// Every finished cue of the current settings, for an SRT file. Cached
  /// sessions read SQLite because only a window is kept in memory.
  Future<List<LocalSubtitleCue>> exportCues() async {
    final key = _cacheKey;
    if (cache != null && key != null) {
      final snapshot = await cache!.read(
        key,
        0,
        player.state.duration.inMilliseconds + 1,
      );
      return snapshot.cues;
    }
    return [..._cues]..sort((a, b) => a.startMs.compareTo(b.startMs));
  }

  /// Whole-media modes process regions before the playhead once everything
  /// after it is done, so the file covers the entire video.
  bool get _fillsWholeMedia =>
      continuous && preferences.fileMode != SubtitleFileMode.appOnly;

  int _nextWorkStart() {
    final ahead = _unprocessedAt(_cursor);
    if (_schedulable(ahead) || !_fillsWholeMedia) return ahead;
    final first = _unprocessedAt(0);
    return _schedulable(first) ? first : ahead;
  }

  void _checkExport() {
    // Previews never write files: selecting a short clip must not litter.
    if (_disposed || !continuous || !preferences.enabled) return;
    final mode = preferences.fileMode;
    if (mode == SubtitleFileMode.appOnly || !progress.reachedEnd) return;
    final token = mode == SubtitleFileMode.askWhenDone
        ? '$_generation|${mode.name}'
        : '$_generation|${mode.name}|${preferences.bilingual}';
    if (_exportToken == token) return;
    _exportToken = token;
    if (mode == SubtitleFileMode.askWhenDone) {
      // Reopening a video that was finished earlier does not prompt again.
      if (_committedThisGeneration) {
        _exportPrompt = true;
        notifyListeners();
      }
      return;
    }
    unawaited(_writeSidecar(mode, _generation));
  }

  Future<void> _writeSidecar(SubtitleFileMode mode, int generation) async {
    final video = subtitleLocalVideoPath(player.subtitleCacheSource);
    if (video == null) {
      if (!_nonLocalReported) {
        _nonLocalReported = true;
        _exportNotice = const SubtitleExportNotice(localOnly: true);
        notifyListeners();
      }
      return;
    }
    try {
      final cues = await exportCues();
      if (_disposed || generation != _generation || cues.isEmpty) return;
      final result = await srtWriter.write(
        videoPath: video,
        language: exportLanguage,
        mode: mode,
        bytes: srtBytes(formatSrt(cues, bilingual: preferences.bilingual)),
      );
      if (_disposed || !result.changed) return;
      _exportNotice = SubtitleExportNotice(path: result.path);
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      _exportNotice = SubtitleExportNotice(error: e);
      notifyListeners();
    }
  }

  /// Generation continues from the playhead to the end of the media, also
  /// while paused; only disposing the session (leaving or closing the player)
  /// or disabling subtitles stops it.
  bool get _needsWork =>
      !_disposed &&
      preferences.enabled &&
      _seekDebounce?.isActive != true &&
      phase != SubtitlePhase.failed &&
      phase != SubtitlePhase.missingModels &&
      (_schedulable(_nextWorkStart()) ||
          (_cacheKey != null &&
              player.state.position.inMilliseconds - _cacheReadPosition >=
                  10000));

  bool _schedulable(int position) =>
      position < player.state.duration.inMilliseconds &&
      (continuous ||
          position <= player.state.position.inMilliseconds + previewRunwayMs);

  /// The next position to recognize. Falling more than eight seconds behind
  /// playback skips ahead to the playhead instead of restarting the session.
  int get _cursor {
    final position = player.state.position.inMilliseconds;
    return _nextMs < position - 8000 ? position : _nextMs;
  }

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
    _committedThisGeneration = false;
    _cacheRevision = null;
    _cacheReadPosition = -100000;
    _cacheTrack = null;
    _cacheState = cache == null
        ? SubtitleCacheState.unavailable
        : _cacheDisabled
        ? SubtitleCacheState.failed
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
    // Continuous playback changes at most ~400 ms/tick at 2x; a larger jump is
    // a seek. It moves the cursor but keeps finished cues and warm models.
    final elapsed = _clock.elapsedMilliseconds - _lastTickMs;
    _lastTickMs = _clock.elapsedMilliseconds;
    final expectedAdvance = math.max(
      1800,
      elapsed * player.state.rate * 1.5 + 500,
    );
    if (position < _lastPosition - 500 ||
        position > _lastPosition + expectedAdvance) {
      _seek(position);
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
    _drive();
  }

  /// A position-only change. Finished cues, processed ranges, the cache key
  /// and loaded models stay valid; only work for the old cursor is abandoned.
  void _seek(int position) {
    if (_disposed) return;
    if (phase == SubtitlePhase.failed || phase == SubtitlePhase.missingModels) {
      // Nothing warm survives a failure; a seek retries as it always did.
      _restart(debounce: true);
      return;
    }
    _lastPosition = position;
    final pending = _pending;
    final next = _unprocessedAt(position);
    if (pending != null &&
        next >= pending.start.inMilliseconds &&
        next < pending.end.inMilliseconds) {
      // Seeking within finished media (arrow keys, small drags) still needs
      // the chunk being generated next; keep it and only show cached cues.
      _cacheReadPosition = -100000;
      unawaited(_readCacheWindow(_generation, position));
      notifyListeners();
      return;
    }
    _epoch++;
    _nextMs = position;
    _partialCue = null;
    _pending = null;
    _prefetched = null;
    // Native recognition cannot be interrupted. Wait for the stale request
    // when that is quicker than reloading the weights; without measurements
    // (a cold first chunk) reload, as before continuous generation.
    final task = _recognitionTask;
    final expected = _recognitionMs, load = _workerLoadMs;
    if (task != null &&
        !task.done &&
        (expected == null ||
            load == null ||
            expected - task.runningMs > load)) {
      _dropWorker();
    }
    if (_stage != SubtitleWorkStage.loadingSpeech &&
        _stage != SubtitleWorkStage.loadingTranslation) {
      _stage = SubtitleWorkStage.idle;
    }
    if (phase == SubtitlePhase.processing) phase = SubtitlePhase.ready;
    _cacheReadPosition = -100000;
    unawaited(_readCacheWindow(_generation, position));
    _seekDebounce?.cancel();
    _seekDebounce = Timer(const Duration(milliseconds: 200), () {
      _seekDebounce = null;
      _drive();
    });
    notifyListeners();
  }

  /// Shows cached cues at a new position without waiting for a busy chunk.
  Future<void> _readCacheWindow(int generation, int position) async {
    final key = _cacheKey;
    if (cache == null || key == null) return;
    try {
      final snapshot = await cache!.read(
        key,
        math.max(0, position - 60000),
        position + 30000,
      );
      if (_disposed || generation != _generation || key != _cacheKey) return;
      // A changed revision is handled by the next chunk, which restarts.
      if (snapshot.revision != _cacheRevision) return;
      _mergeCues(snapshot.cues);
      notifyListeners();
    } catch (_) {
      // The next chunk reads the cache again and records any failure.
    }
  }

  void _mergeCues(Iterable<LocalSubtitleCue> cues) {
    final byTime = {
      for (final c in [..._cues, ...cues]) '${c.startMs}:${c.endMs}': c,
    };
    _cues
      ..clear()
      ..addAll(byTime.values)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    _trimCues();
  }

  /// Cached cues can be read again, so only a window around the playhead is
  /// kept. Without a cache every generated cue stays in memory (a few MB for a
  /// feature film); dropping them would leave processed ranges blank forever.
  void _trimCues() {
    if (cache == null || _cacheKey == null) return;
    final position = player.state.position.inMilliseconds;
    _cues.removeWhere(
      (c) =>
          (c.endMs < position - 60000 || c.startMs > position + 120000) &&
          // Overlap trimming of the next chunk needs the cue before it.
          (c.endMs < _nextMs - 10000 || c.startMs > _nextMs),
    );
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
    if (cache == null || _cacheDisabled) return;
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
      _mergeCues(snapshot.cues);
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
      if (_cacheRevision != null) {
        // An earlier read succeeded, so evicted cues relied on the cache.
        _cacheDisabled = true;
        restart();
        return;
      }
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
    final epoch = _epoch;
    // Settings changes and seeks both make this chunk's results unusable.
    bool stale() => generation != _generation || epoch != _epoch;
    final target = preferences.resolvedTarget;
    final chunkCues = <LocalSubtitleCue>[];
    var committed = false;
    try {
      final selected = await player.subtitleAudioTrackOrdinal();
      if (stale()) return;
      await _readCache(generation, source, selected);
      if (stale()) return;
      final duration = player.state.duration.inMilliseconds;
      _nextMs = _nextWorkStart();
      if (!_schedulable(_nextMs)) {
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
      if (stale()) return;
      // Warm the translator beside the speech model. In full players Auto
      // detection usually finds a foreign language, so it is prepared then
      // too; this costs memory when the audio is in the subtitle language.
      // Previews wait for a detected language, as clicking through files
      // would otherwise load and unload translation weights repeatedly.
      if (preferences.resolvedSourceLanguage != target &&
          (continuous || preferences.resolvedSourceLanguage != 'auto') &&
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
      if (stale()) return;
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
        final loading = Stopwatch()..start();
        try {
          await worker.start(speech.localPath);
          _workerLoadMs = loading.elapsedMilliseconds;
        } finally {
          if (identical(_worker, worker)) _workerLoading = false;
        }
      }
      if (stale()) return;
      // Model startup can finish after playback has moved on. Keep the warm
      // model and start where the user is, without decoding expired chunks.
      _nextMs = _nextWorkStart();
      if (!_schedulable(_nextMs)) {
        phase = SubtitlePhase.ready;
        _stage = SubtitleWorkStage.idle;
        _pending = null;
        return;
      }
      final chunkStart = _nextMs;
      final key = _cacheKey;
      if (cache != null &&
          key != null &&
          _cacheRevision != null &&
          chunkStart > 0 &&
          !_cues.any(
            (c) => c.endMs > chunkStart - 10000 && c.startMs < chunkStart,
          )) {
        // A backfill chunk starts far from the playhead window.
        try {
          final before = await cache!.read(
            key,
            math.max(0, chunkStart - 10000),
            chunkStart,
          );
          if (stale()) return;
          if (before.revision == _cacheRevision) _mergeCues(before.cues);
        } catch (_) {
          // Overlap trimming is best effort; the chunk itself still runs.
        }
      }
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
      final measured = task.elapsedMs;
      if (measured != null) {
        final previous = _recognitionMs;
        _recognitionMs = previous == null
            ? measured.toDouble()
            : previous * .7 + measured * .3;
      }
      if (stale()) return;
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
      if (stale()) return;
      // One recognition request runs ahead, overlapping CPU/GPU recognition
      // with translation. No PCM or model tensors cross into this isolate.
      final next = _unprocessedAt(end);
      if (_schedulable(next)) {
        _prefetched = _recognize(
          generation,
          source,
          selected,
          next,
          _chunkEnd(next, duration),
        );
      }
      LocalSubtitleCue? previous;
      for (final cue in _cues) {
        if (cue.startMs < chunkStart &&
            (previous == null || cue.endMs > previous.endMs)) {
          previous = cue;
        }
      }
      for (final raw in segments) {
        if (stale()) return;
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
            if (stale()) return;
            if (preparation != null) {
              Error.throwWithStackTrace(preparation.$1, preparation.$2);
            }
            _work(SubtitleWorkStage.translating, translation.displayName);
            final output = StringBuffer();
            final translator = _translator!;
            _translationBusy = true;
            try {
              // Leaving this loop cancels the HTTP stream, so a seek stops
              // the old request without unloading llama-server.
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
                if (stale()) return;
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
        if (stale()) return;
        previous = LocalSubtitleCue(from, to, original, text);
        _partialCue = null;
        chunkCues.add(previous);
        // Publish complete translated cues immediately; the timeline and DB
        // commit still wait for the whole chunk to finish successfully.
        _cues.add(previous);
      }
      // Every segment is finished: a seek arriving now must not discard it.
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
          // Saved cues outside the playhead window were evicted from memory
          // and can no longer be read back; regenerate without the cache.
          _cacheDisabled = true;
          restart();
          return;
        }
      }
      // The chunk's range was recognized even if a seek arrived during the
      // cache write; its cues are complete and remain valid.
      committed = true;
      _committedThisGeneration = true;
      _cues.sort((a, b) => a.startMs.compareTo(b.startMs));
      _markProcessed(chunkStart, end);
      if (epoch == _epoch) _nextMs = end;
      _pending = null;
      _stage = SubtitleWorkStage.idle;
      _trimCues();
      phase = SubtitlePhase.ready;
    } catch (e) {
      // A seek may have stopped the worker under this chunk; that is not a
      // failure of the subtitle pipeline.
      if (generation == _generation && epoch == _epoch && !_disposed) {
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
      // An abandoned chunk is redone later; keeping its partial cues would
      // duplicate them when the range is recognized again.
      if (!committed && chunkCues.isNotEmpty) {
        _cues.removeWhere(chunkCues.contains);
      }
      if (_busyGeneration == generation) _busyGeneration = null;
      if (!_disposed && generation == _generation) _checkExport();
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

  /// Native time for a successful request, used to decide whether a seek
  /// waits for it or reloads the worker.
  int? elapsedMs;
  final _watch = Stopwatch()..start();
  int get runningMs => _watch.elapsedMilliseconds;
  late final Future<_RecognitionOutcome> future;
  _RecognitionTask(
    this.generation,
    this.start,
    this.end,
    this.track,
    Future<Map<String, dynamic>> request,
  ) {
    final watch = _watch;
    // A discarded prefetch must absorb cancellation errors until consumed.
    future = request.then(
      (value) {
        done = true;
        elapsedMs = watch.elapsedMilliseconds;
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

/// One automatic sidecar outcome for the player to announce.
class SubtitleExportNotice {
  final String? path;
  final Object? error;

  /// The source is an http/SMB proxy; its folder cannot be written.
  final bool localOnly;
  const SubtitleExportNotice({this.path, this.error, this.localOnly = false});
}
