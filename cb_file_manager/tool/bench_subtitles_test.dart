// Opt-in service/component benchmark. Does not open or control the app and is
// not an E2E runner. Pass local paths with CB_SUBTITLE_BENCH_* dart-defines.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/gguf_llama_cpp_runtime.dart';
import 'package:cb_file_manager/services/local_ai/llama_cpp_server_launch.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/media/local_subtitle_session.dart';
import 'package:cb_file_manager/services/media/media_kit_playback.dart';
import 'package:cb_file_manager/services/media/subtitle_cache.dart';
import 'package:cb_file_manager/services/media/subtitle_preferences.dart';
import 'package:cb_file_manager/services/media/subtitle_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const source = String.fromEnvironment('CB_SUBTITLE_BENCH_SOURCE');
const speech = String.fromEnvironment('CB_SUBTITLE_BENCH_SPEECH');
const translation = String.fromEnvironment('CB_SUBTITLE_BENCH_TRANSLATION');
const workerPath = String.fromEnvironment('CB_SUBTITLE_BENCH_WORKER');
const llamaPath = String.fromEnvironment('CB_SUBTITLE_BENCH_LLAMA');
const start = int.fromEnvironment(
  'CB_SUBTITLE_BENCH_START_MS',
  defaultValue: 600000,
);
const seekPosition = int.fromEnvironment(
  'CB_SUBTITLE_BENCH_SEEK_MS',
  defaultValue: 120000,
);
const duration = int.fromEnvironment(
  'CB_SUBTITLE_BENCH_DURATION_MS',
  defaultValue: 7200000,
);
const runSeconds = int.fromEnvironment(
  'CB_SUBTITLE_BENCH_SECONDS',
  defaultValue: 15,
);
const output = String.fromEnvironment(
  'CB_SUBTITLE_BENCH_OUTPUT',
  defaultValue: 'build/subtitle-performance-session.json',
);

class _Timeline extends mk.PlatformPlayer {
  _Timeline() : super(configuration: const mk.PlayerConfiguration()) {
    state = state.copyWith(
      duration: const Duration(milliseconds: duration),
      position: const Duration(milliseconds: start),
    );
  }
}

class _Playback extends PlaybackPlayer {
  _Playback(_Timeline timeline)
    : super(player: mk.Player(platformPlayer: timeline));
  @override
  String get subtitleSource => source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real local subtitle pipeline: startup, playback runway, warm seek and cache',
    () async {
      // This benchmark only talks to its own localhost
      // runtime; use the real HttpClient rather than Flutter's test HTTP stub.
      HttpOverrides.global = null;
      for (final path in [source, speech, translation, workerPath, llamaPath]) {
        expect(
          await File(path).exists(),
          isTrue,
          reason: 'Missing benchmark input: $path',
        );
      }
      final root = await Directory.systemTemp.createTemp('subtitle-benchmark-');
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        '${root.path}/cache.sqlite',
      );
      final cache = SubtitleCache(openDatabase: () async => db);
      InstalledLocalModel model(
        String id,
        String path,
        LocalModelPurpose purpose,
      ) => InstalledLocalModel(
        catalogId: id,
        displayName: id,
        localPath: path,
        sizeBytes: File(path).lengthSync(),
        installedAt: DateTime(2026),
        purpose: purpose,
      );
      // This opt-in file is executed by flutter test, outside the test/ tree.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({
        'ai_subtitles_enabled': true,
        'ai_subtitles_source': 'ja',
        'ai_subtitles_target': 'vi',
        'local_ai_installed_models': jsonEncode([
          model('whisper/small', speech, LocalModelPurpose.speech).toJson(),
          model(
            'tencent/Hy-MT2-1.8B-GGUF',
            translation,
            LocalModelPurpose.translation,
          ).toJson(),
        ]),
      });
      final shared = await SharedPreferences.getInstance();
      final preferences = SubtitlePreferences(shared);
      final models = LocalAiAdvisorService(
        prefs: shared,
        documentsDirectoryProvider: () async => root,
      );
      final timeline = _Timeline();
      final player = _Playback(timeline);
      final workers = <SubtitleWorker>[];
      final translators = <GgufLlamaCppLocalAiChatRuntime>[];
      final sessions = <LocalSubtitleSession>[];
      final watch = Stopwatch()..start();
      final wakeups = <double>[];
      var lastWake = watch.elapsedMicroseconds;
      final jitter = Timer.periodic(const Duration(milliseconds: 16), (_) {
        final now = watch.elapsedMicroseconds;
        wakeups.add(math.max(0, (now - lastWake - 16000) / 1000));
        lastWake = now;
      });
      var phaseStart = 0, positionStart = start;
      final clock = Timer.periodic(const Duration(milliseconds: 50), (_) {
        timeline.state = timeline.state.copyWith(
          position: Duration(
            milliseconds:
                positionStart + watch.elapsedMilliseconds - phaseStart,
          ),
        );
      });
      Future<void> until(String label, bool Function() ready) async {
        for (var i = 0; i < 1500 && !ready(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(ready(), isTrue, reason: label);
      }

      LocalSubtitleSession create() {
        final session = LocalSubtitleSession(
          player: player,
          preferences: preferences,
          models: models,
          cache: cache,
          createWorker: () {
            final worker = SubtitleWorker(executableOverride: workerPath);
            workers.add(worker);
            return worker;
          },
          createTranslator: () {
            final runtime = GgufLlamaCppLocalAiChatRuntime(
              maxResponseTokens: 512,
              allowCpuFallback: true,
              parallelSlots: 1,
              threads: (Platform.numberOfProcessors ~/ 2).clamp(1, 6),
              serverLaunchOverride: LlamaCppServerLaunch(
                executablePath: llamaPath,
                isAndroid: false,
              ),
            );
            translators.add(runtime);
            return runtime;
          },
        );
        sessions.add(session);
        return session;
      }

      try {
        final session = create();
        int? firstVisibleMs;
        int? seekingAt, firstSeekVisibleMs;
        session.addListener(() {
          if (session.text.isNotEmpty) {
            firstVisibleMs ??= watch.elapsedMilliseconds;
            if (seekingAt != null &&
                session.progress.position.inMilliseconds >= seekPosition &&
                session.progress.completed.any(
                  (r) =>
                      r.start <= session.progress.position &&
                      r.end > session.progress.position,
                )) {
              firstSeekVisibleMs ??= watch.elapsedMilliseconds - seekingAt;
            }
          }
        });
        await until(
          'First completed translated cue',
          () =>
              session.cues.isNotEmpty || session.phase == SubtitlePhase.failed,
        );
        expect(
          session.phase,
          isNot(SubtitlePhase.failed),
          reason: session.error,
        );
        final firstCueMs = watch.elapsedMilliseconds;
        final samples = <Map<String, Object?>>[];
        while (watch.elapsedMilliseconds < runSeconds * 1000) {
          samples.add({
            'wall_ms': watch.elapsedMilliseconds,
            'headroom_ms':
                (session.progress.processedUntil?.inMilliseconds ?? start) -
                player.state.position.inMilliseconds,
            'lagging': session.lagging,
            'phase': session.phase.name,
          });
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        // Generation is continuous now, so the pipeline is normally busy
        // here; this measures a warm seek during work, not an idle one.
        expect(
          firstVisibleMs,
          isNotNull,
          reason: 'Translated subtitles must actually become visible',
        );
        final loadedWorkers = workers.length,
            loadedTranslators = translators.length;
        final seeking = watch.elapsedMilliseconds;
        seekingAt = seeking;
        positionStart = seekPosition;
        phaseStart = seeking;
        timeline.state = timeline.state.copyWith(
          position: Duration(milliseconds: positionStart),
        );
        await until(
          'Completed cue after uncached seek',
          () => session.cues.any(
            (c) =>
                c.startMs >= positionStart - 800 &&
                c.startMs < positionStart + 16000,
          ),
        );
        final seekCueMs = watch.elapsedMilliseconds - seeking;
        print(
          jsonEncode({
            'first_cue_ms': firstCueMs,
            'first_visible_ms': firstVisibleMs,
            'seek_cue_ms': seekCueMs,
            'seek_phase': session.phase.name,
            'seek_position_ms': session.progress.position.inMilliseconds,
            'seek_cue_times': session.cues
                .map((c) => [c.startMs, c.endMs])
                .toList(),
          }),
        );
        await until(
          'Visible subtitle after uncached seek',
          () => firstSeekVisibleMs != null,
        );
        expect(
          workers.length,
          loadedWorkers,
          reason: 'A warm seek should keep speech weights loaded',
        );
        expect(
          translators.length,
          loadedTranslators,
          reason: 'A warm seek should keep translation weights loaded',
        );
        session.dispose();
        sessions.remove(session);
        for (final worker in workers) {
          await worker.stop();
        }
        for (final runtime in translators) {
          await runtime.dispose();
        }
        positionStart = start;
        phaseStart = watch.elapsedMilliseconds;
        timeline.state = timeline.state.copyWith(
          position: const Duration(milliseconds: start),
        );
        final reopening = watch.elapsedMilliseconds;
        final reopened = create();
        await until('Cached cue restored', () => reopened.cues.isNotEmpty);
        final cacheCueMs = watch.elapsedMilliseconds - reopening;
        await until('Cached subtitle visible', () => reopened.text.isNotEmpty);
        final cacheVisibleMs = watch.elapsedMilliseconds - reopening;
        expect(
          workers.length,
          loadedWorkers,
          reason: 'Cached playback must not reload a model',
        );
        wakeups.sort();
        final report = {
          'source_language': 'ja',
          'target_language': 'vi',
          'playback_rate': 1,
          'first_translated_cue_ms': firstCueMs,
          'first_visible_subtitle_ms': firstVisibleMs,
          'warm_seek_cue_ms': seekCueMs,
          'warm_seek_visible_ms': firstSeekVisibleMs,
          'cached_reopen_cue_ms': cacheCueMs,
          'cached_reopen_visible_ms': cacheVisibleMs,
          'speech_processes': workers.length,
          'translation_processes': translators.length,
          'event_loop_late_p95_ms': wakeups[(wakeups.length * .95).floor()],
          'event_loop_late_max_ms': wakeups.last,
          'samples': samples,
        };
        await File(
          output,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        print(jsonEncode({...report}..remove('samples')));
      } finally {
        clock.cancel();
        jitter.cancel();
        for (final session in sessions) {
          session.dispose();
        }
        for (final worker in workers) {
          await worker.stop();
        }
        for (final runtime in translators) {
          await runtime.dispose();
        }
        preferences.dispose();
        await player.dispose();
        await models.dispose();
        await db.close();
        await root.delete(recursive: true);
      }
    },
    skip: source.isEmpty ? 'Opt-in: supply CB_SUBTITLE_BENCH_* paths' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
