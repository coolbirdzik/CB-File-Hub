import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart' as mk;
import 'package:shared_preferences/shared_preferences.dart';

import '../local_subtitle_session.dart';
import '../media_kit_playback.dart';
import '../subtitle_preferences.dart';
import '../subtitle_services.dart';
import '../subtitle_srt.dart';
import '../subtitle_translation_pool.dart';
import '../subtitle_worker.dart';
import 'subtitle_batch_models.dart';
import 'subtitle_batch_processes.dart';
import 'subtitle_batch_store.dart';
import 'subtitle_generated_metadata.dart';

/// Settings of one batch job. Nothing is read from or written to the
/// player's subtitle preferences, and the app language never changes them.
class SubtitleBatchPreferences extends SubtitlePreferences {
  final SubtitleBatchSettings settings;
  SubtitleBatchPreferences(super.prefs, this.settings);

  @override
  bool get enabled => true;
  @override
  String get speechModel => settings.speechModel;
  @override
  String get translationModel => settings.translationModel;
  @override
  String get sourceLanguage => settings.sourceLanguage;
  @override
  String get targetLanguage => settings.targetLanguage;
  @override
  String get resolvedTarget => settings.targetLanguage;
  @override
  bool get bilingual => settings.bilingual;

  /// The runner writes the file itself, so it knows the resulting path.
  @override
  SubtitleFileMode get fileMode => SubtitleFileMode.appOnly;
}

enum SubtitleBatchOutcomeKind { done, skipped, failed, blocked, aborted }

class SubtitleBatchOutcome {
  final SubtitleBatchOutcomeKind kind;
  final String? message;
  final String? outputPath;
  final SubtitleGeneratedMetadata? metadata;

  /// For [SubtitleBatchOutcomeKind.blocked]: the model that is not installed.
  final String? missingModel;
  const SubtitleBatchOutcome(
    this.kind, {
    this.message,
    this.outputPath,
    this.metadata,
    this.missingModel,
  });
}

/// Lets the queue stop a running job: cancel, pause, or yield to playback.
class SubtitleBatchAbort {
  final _completer = Completer<String>();
  bool get aborted => _completer.isCompleted;
  String? reason;
  Future<String> get future => _completer.future;
  void abort(String why) {
    if (aborted) return;
    reason = why;
    _completer.complete(why);
  }
}

typedef SubtitleBatchSessionFactory =
    LocalSubtitleSession Function(
      PlaybackPlayer player,
      SubtitlePreferences preferences,
    );

/// Generates subtitles for one video: a muted, video-less player provides the
/// same duration and audio track the interactive player would, so the work is
/// stored under the same subtitle cache key and reused when the video is
/// opened later.
class SubtitleBatchJobRunner {
  static final _translationPool = SubtitleTranslationPool(
    slots: SubtitleBatchStore.maxParallelJobs,
    onProcessStarted: SubtitleBatchProcesses.instance.register,
  );
  final PlaybackPlayer Function() createPlayer;
  final Future<SharedPreferences> Function() loadPrefs;
  final Future<SubtitleBatchSessionFactory> Function() sessionFactory;
  final SubtitleSrtWriter Function(SharedPreferences prefs) createWriter;
  final Duration openTimeout;

  /// A session with nothing left to schedule that has not covered the whole
  /// video is stuck; one making no progress for [stallTimeout] is too.
  final Duration idleTimeout, stallTimeout, watchInterval;

  SubtitleBatchJobRunner({
    PlaybackPlayer Function()? createPlayer,
    Future<SharedPreferences> Function()? loadPrefs,
    Future<SubtitleBatchSessionFactory> Function()? sessionFactory,
    SubtitleSrtWriter Function(SharedPreferences prefs)? createWriter,
    this.openTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 45),
    this.stallTimeout = const Duration(minutes: 10),
    this.watchInterval = const Duration(seconds: 5),
  }) : createPlayer = createPlayer ?? PlaybackPlayer.new,
       loadPrefs = loadPrefs ?? SharedPreferences.getInstance,
       sessionFactory = sessionFactory ?? _defaultSessions,
       createWriter = createWriter ?? SubtitleSrtWriter.new;

  static Future<SubtitleBatchSessionFactory> _defaultSessions() async {
    final services = await SubtitleServices.load();
    return (player, preferences) => LocalSubtitleSession(
      player: player,
      preferences: preferences,
      models: services.models,
      cache: services.cache,
      interactive: false,
      wholeMedia: true,
      translationPool: _translationPool,
      createWorker: () => SubtitleWorker(
        onProcessStarted: SubtitleBatchProcesses.instance.register,
      ),
    );
  }

  /// Fraction of the timeline that is recognized and translated.
  static double progressOf(SubtitleProgress progress) {
    final total = progress.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (processedOf(progress).inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// Media time that is recognized and translated.
  static Duration processedOf(SubtitleProgress progress) {
    var done = Duration.zero;
    for (final range in progress.completed) {
      done += range.end - range.start;
    }
    return done;
  }

  Future<SubtitleBatchOutcome> run(
    SubtitleBatchJob job, {
    required SubtitleBatchAbort abort,
    void Function(double progress)? onProgress,
    void Function(Duration processed)? onProcessed,
  }) async {
    final settings = job.settings;
    if (!await File(job.path).exists()) {
      return const SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.failed,
        message: 'File not found',
      );
    }
    if (settings.skipExisting && settings.outputMode.writesAutomatically) {
      final existing = await existingSubtitleSidecar(
        job.path,
        settings.targetLanguage,
      );
      if (existing != null) {
        return SubtitleBatchOutcome(
          SubtitleBatchOutcomeKind.skipped,
          outputPath: existing,
          message: 'Subtitle already exists',
        );
      }
    }
    final prefs = await loadPrefs();
    final factory = await sessionFactory();
    if (abort.aborted) return _aborted(abort);

    final player = createPlayer();
    SubtitleBatchPreferences? preferences;
    LocalSubtitleSession? session;
    void Function()? listener;
    Timer? watchdog;
    try {
      await _prepareHeadless(player);
      // A file on a stalled drive can hang the open itself.
      try {
        await player
            .open(PlaybackMedia(job.path), play: false)
            .timeout(openTimeout);
      } on TimeoutException {
        return const SubtitleBatchOutcome(
          SubtitleBatchOutcomeKind.failed,
          message: SubtitleBatchFailure.openTimedOut,
        );
      }
      final opened = await _waitForDuration(player, abort);
      if (abort.aborted) return _aborted(abort);
      if (!opened) {
        return const SubtitleBatchOutcome(
          SubtitleBatchOutcomeKind.failed,
          message: 'Cannot read the video duration',
        );
      }
      preferences = SubtitleBatchPreferences(prefs, settings);
      final created = factory(player, preferences);
      session = created;
      final result = Completer<SubtitleBatchOutcome>();
      var lastReported = -1.0;
      var processed = Duration.zero;
      var progressedAt = DateTime.now();
      DateTime? idleSince;
      listener = () {
        if (result.isCompleted) return;
        final progress = created.progress;
        final fraction = progressOf(progress);
        final done = processedOf(progress);
        if (done != processed) {
          processed = done;
          progressedAt = DateTime.now();
          onProcessed?.call(done);
        }
        // Between chunks the session is ready for a moment; only an
        // uninterrupted ready state counts as idle.
        if (!_idle(progress)) idleSince = null;
        if (fraction - lastReported >= .005 || fraction == 1) {
          lastReported = fraction;
          onProgress?.call(fraction);
        }
        if (progress.reachedEnd) {
          result.complete(
            const SubtitleBatchOutcome(SubtitleBatchOutcomeKind.done),
          );
        } else if (created.phase == SubtitlePhase.failed) {
          result.complete(
            SubtitleBatchOutcome(
              SubtitleBatchOutcomeKind.failed,
              message: created.error ?? 'Subtitle processing failed',
            ),
          );
        } else if (created.phase == SubtitlePhase.missingModels) {
          result.complete(
            SubtitleBatchOutcome(
              SubtitleBatchOutcomeKind.blocked,
              missingModel: progress.modelName,
            ),
          );
        }
      };
      created.addListener(listener);
      listener();
      watchdog = Timer.periodic(watchInterval, (_) {
        if (result.isCompleted) return;
        // Duration/coverage can change without a session notification (for
        // example the native player publishes its final duration). Recheck
        // completion before deciding that the job has stalled.
        listener?.call();
        if (result.isCompleted) return;
        final progress = created.progress;
        final now = DateTime.now();
        final fraction = progressOf(progress);
        final percent = (fraction * 100).floor();
        // Ready, with no chunk pending, means the session has nothing left
        // to schedule. Every chunk sets processing before it waits.
        if (_idle(progress) && !progress.reachedEnd) {
          if (idleSince == null || progressedAt.isAfter(idleSince!)) {
            idleSince = now;
          }
          final idle = now.difference(idleSince!);
          // Never export an incomplete timeline just because the displayed
          // percentage rounds to 100. reachedEnd uses the same millisecond
          // precision as the scheduler and cache.
          if (idle >= idleTimeout) {
            result.complete(
              SubtitleBatchOutcome(
                SubtitleBatchOutcomeKind.failed,
                message: '${SubtitleBatchFailure.stalledIdle} $percent%',
              ),
            );
          }
          return;
        }
        idleSince = null;
        if (now.difference(progressedAt) >= stallTimeout) {
          result.complete(
            SubtitleBatchOutcome(
              SubtitleBatchOutcomeKind.failed,
              message:
                  '${SubtitleBatchFailure.stalledSlow} $percent% '
                  '(${progress.stage.name})',
            ),
          );
        }
      });
      final outcome = await Future.any([
        result.future,
        abort.future.then((_) => _aborted(abort)),
      ]);
      if (outcome.kind != SubtitleBatchOutcomeKind.done) return outcome;
      return await _export(job, created, prefs);
    } catch (e) {
      if (abort.aborted) return _aborted(abort);
      return SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.failed,
        message: e.toString(),
      );
    } finally {
      watchdog?.cancel();
      if (listener != null) session?.removeListener(listener);
      session?.dispose();
      preferences?.dispose();
      try {
        await player.dispose().timeout(const Duration(seconds: 5));
      } catch (_) {
        // A stuck decoder must not stall the rest of the queue.
      }
    }
  }

  Future<SubtitleBatchOutcome> _export(
    SubtitleBatchJob job,
    LocalSubtitleSession session,
    SharedPreferences prefs,
  ) async {
    final settings = job.settings;
    SubtitleGeneratedMetadata metadata({String? path, List<int>? bytes}) =>
        SubtitleGeneratedMetadata(
          settings: settings,
          generatedAt: DateTime.now(),
          cacheKey: session.generatedCacheKey,
          outputPath: path,
          outputSha256: bytes == null
              ? null
              : SubtitleGeneratedMetadata.hash(bytes),
        );
    if (!settings.outputMode.writesAutomatically) {
      return SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.done,
        metadata: metadata(),
      );
    }
    final cues = await session.exportCues();
    if (cues.isEmpty) {
      return SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.done,
        message: 'No speech found',
        metadata: metadata(),
      );
    }
    final bytes = srtBytes(formatSrt(cues, bilingual: settings.bilingual));
    final write = await createWriter(prefs).write(
      videoPath: job.path,
      language: settings.targetLanguage,
      mode: settings.outputMode,
      bytes: bytes,
    );
    final generated = metadata(path: write.path, bytes: bytes);
    // The database copy is authoritative even on a volume that disallows
    // an additional metadata file.
    try {
      await generated.writeSidecar();
    } on FileSystemException catch (_) {}
    return SubtitleBatchOutcome(
      SubtitleBatchOutcomeKind.done,
      outputPath: write.path,
      metadata: generated,
    );
  }

  static bool _idle(SubtitleProgress progress) =>
      progress.phase == SubtitlePhase.ready &&
      progress.stage == SubtitleWorkStage.idle &&
      progress.pending == null;

  static SubtitleBatchOutcome _aborted(SubtitleBatchAbort abort) =>
      SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.aborted,
        message: abort.reason,
      );

  /// No window, no sound: only metadata (duration, audio tracks) is needed.
  /// framePreview is not used because it disables the audio track, which the
  /// session needs to pick the same track as the interactive player.
  static Future<void> _prepareHeadless(PlaybackPlayer player) async {
    if (player.controller.platform case final mk.NativePlayer native) {
      for (final (key, value) in const [('vid', 'no'), ('ao', 'null')]) {
        try {
          await native.setProperty(key, value);
        } catch (_) {
          // Older libmpv builds may refuse a property; the volume still is 0.
        }
      }
    }
    try {
      await player.controller.setVolume(0);
    } catch (_) {}
  }

  Future<bool> _waitForDuration(
    PlaybackPlayer player,
    SubtitleBatchAbort abort,
  ) async {
    if (player.state.duration > Duration.zero) return true;
    final ready = Completer<bool>();
    final subscription = player.stream.duration.listen((duration) {
      if (duration > Duration.zero && !ready.isCompleted) {
        ready.complete(true);
      }
    });
    final errors = player.stream.error.listen((error) {
      if (!ready.isCompleted &&
          !PlaybackPlayer.isRecoverableAudioDecodeError(error)) {
        ready.complete(false);
      }
    });
    try {
      return await Future.any([
        ready.future,
        abort.future.then((_) => false),
      ]).timeout(openTimeout, onTimeout: () => false);
    } finally {
      await subscription.cancel();
      await errors.cancel();
    }
  }
}
