enum SubtitlePhase { off, missingModels, loading, processing, ready, failed }

enum SubtitleWorkStage {
  idle,
  loadingSpeech,
  recognizing,
  loadingTranslation,
  translating,
  readingCache,
}

enum SubtitleCacheState {
  unavailable,
  checking,
  automatic,
  reused,
  saved,
  failed,
}

/// Original-media time, independent of playback rate and wall-clock time.
class SubtitleTimeRange {
  final Duration start;
  final Duration end;
  const SubtitleTimeRange(this.start, this.end);
}

/// Only completed recognition AND translation count as processed. Silence is
/// processed too, so progress must not be derived from visible subtitle cues.
class SubtitleProgress {
  final SubtitlePhase phase;
  final SubtitleWorkStage stage;
  final String? modelName;
  final Duration duration;
  final Duration position;
  final List<SubtitleTimeRange> completed;
  final SubtitleTimeRange? pending;
  final bool lagging;
  final String? error;
  final SubtitleCacheState cacheState;
  final String? sourceLanguage, targetLanguage;

  const SubtitleProgress({
    required this.phase,
    this.stage = SubtitleWorkStage.idle,
    this.modelName,
    required this.duration,
    required this.position,
    this.completed = const [],
    this.pending,
    this.lagging = false,
    this.error,
    this.cacheState = SubtitleCacheState.unavailable,
    this.sourceLanguage,
    this.targetLanguage,
  });

  bool get busy =>
      phase == SubtitlePhase.loading || phase == SubtitlePhase.processing;
  Duration? get processedUntil => completed.isEmpty ? null : completed.last.end;
  bool get reachedEnd =>
      duration > Duration.zero &&
      completed.length == 1 &&
      completed.first.start == Duration.zero &&
      completed.first.end >= duration;
}
