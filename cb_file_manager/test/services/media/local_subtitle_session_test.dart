import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/config/language_controller.dart';
import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/local_ai/gguf_llama_cpp_runtime.dart';
import 'package:cb_file_manager/services/media/local_subtitle_session.dart';
import 'package:cb_file_manager/services/media/media_kit_playback.dart';
import 'package:cb_file_manager/services/media/subtitle_preferences.dart';
import 'package:cb_file_manager/services/media/subtitle_worker.dart';
import 'package:cb_file_manager/services/media/subtitle_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:shared_preferences/shared_preferences.dart';

class _Platform extends mk.PlatformPlayer {
  _Platform() : super(configuration: const mk.PlayerConfiguration()) {
    state = state.copyWith(duration: const Duration(minutes: 2));
  }
}

class _Playback extends PlaybackPlayer {
  int audioTrack = 0;
  _Playback(_Platform native)
    : super(player: mk.Player(platformPlayer: native));
  @override
  String get subtitleSource => 'test.wav';
  @override
  Future<int> subtitleAudioTrackOrdinal() async => audioTrack;
}

class _Worker extends SubtitleWorker {
  String language = 'en';
  String? recognizedText;
  bool stopped = false;
  final requests = <Map<String, Object?>>[];
  Completer<Map<String, dynamic>>? gate;
  Completer<void>? startGate;
  @override
  Future<void> start(String model) async {
    await startGate?.future;
  }

  @override
  Future<Map<String, dynamic>> request(Map<String, Object?> command) async {
    requests.add(command);
    if (gate != null) return gate!.future;
    final start = command['start_ms']! as int;
    return {
      'language': language,
      'segments': [
        {
          'start_ms': start,
          'end_ms': start + (command['duration_ms']! as int),
          'text':
              recognizedText ?? (start == 0 ? 'hello world' : 'world again'),
        },
      ],
    };
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

class _Translator extends GgufLlamaCppLocalAiChatRuntime {
  Stream<String> Function()? output;
  int preparations = 0;
  bool disposed = false;
  Completer<void>? gate;
  Object? preparationError;
  @override
  Future<void> prepareModel({
    required InstalledLocalModel model,
    int contextTokens = 2048,
  }) async {
    preparations++;
    if (preparationError != null) throw preparationError!;
    await gate?.future;
  }

  @override
  Stream<String> sendDirectConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
  }) async* {
    if (output != null) {
      yield* output!();
    } else {
      yield 'Bản dịch';
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (gate != null && !gate!.isCompleted) {
      gate!.completeError(StateError('disposed'));
    }
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late SharedPreferences prefs;
  late SubtitlePreferences preferences;
  late LocalAiAdvisorService models;
  late _Platform native;
  late _Playback player;
  final sessions = <LocalSubtitleSession>[];
  Database? cacheDb;
  Future<SubtitleCache> createCache() async {
    sqfliteFfiInit();
    cacheDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    return SubtitleCache(openDatabase: () async => cacheDb!);
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('subtitle-session-');
    final speech = File('${sandbox.path}/speech.bin');
    await speech.writeAsBytes([1]);
    final translation = File('${sandbox.path}/translation.gguf');
    await translation.writeAsBytes([1]);
    SharedPreferences.setMockInitialValues({
      'ai_subtitles_enabled': true,
      'ai_subtitles_target': 'en',
      'local_ai_installed_models': jsonEncode([
        InstalledLocalModel(
          catalogId: 'whisper/small',
          displayName: 'speech',
          localPath: speech.path,
          sizeBytes: 1,
          installedAt: DateTime(2026),
          purpose: LocalModelPurpose.speech,
        ).toJson(),
        InstalledLocalModel(
          catalogId: 'tencent/Hy-MT2-1.8B-GGUF',
          displayName: 'translation',
          localPath: translation.path,
          sizeBytes: 1,
          installedAt: DateTime(2026),
          purpose: LocalModelPurpose.translation,
        ).toJson(),
      ]),
    });
    prefs = await SharedPreferences.getInstance();
    preferences = SubtitlePreferences(prefs);
    models = LocalAiAdvisorService(
      prefs: prefs,
      documentsDirectoryProvider: () async => sandbox,
    );
    native = _Platform();
    player = _Playback(native);
  });
  tearDown(() async {
    for (final session in sessions) {
      session.dispose();
    }
    sessions.clear();
    preferences.dispose();
    await player.dispose();
    await models.dispose();
    await cacheDb?.close();
    cacheDb = null;
    await sandbox.delete(recursive: true);
  });
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  LocalSubtitleSession session(
    SubtitleWorker Function() factory, {
    Future<String> Function(InstalledLocalModel, String, String)? translate,
    SubtitleCache? cache,
    Future<String?> Function()? fingerprint,
    GgufLlamaCppLocalAiChatRuntime Function()? runtime,
  }) {
    final s = LocalSubtitleSession(
      player: player,
      preferences: preferences,
      models: models,
      createWorker: factory,
      translateText: translate,
      cache: cache,
      sourceFingerprint: fingerprint ?? () async => 'movie-v1',
      createTranslator: runtime,
    );
    sessions.add(s);
    return s;
  }

  test(
    'overlap keeps the new portion instead of discarding the next cue',
    () async {
      final worker = _Worker();
      final s = session(() => worker);
      await until(() => s.cues.length >= 2);
      expect(s.cues[0].text, 'hello world');
      expect(s.cues[1].text, 'again');
      expect(s.cues[1].startMs, 8000);
      expect(s.cues[1].endMs, 16000);
    },
  );
  test('a seek cancels native work and discards a late result', () async {
    final first = _Worker()..gate = Completer<Map<String, dynamic>>();
    final next = _Worker();
    var count = 0;
    final s = session(() => count++ == 0 ? first : next);
    await until(() => first.requests.isNotEmpty);
    native.state = native.state.copyWith(position: const Duration(seconds: 50));
    await until(() => first.stopped);
    first.gate!.complete({
      'language': 'en',
      'segments': [
        {'start_ms': 0, 'end_ms': 8000, 'text': 'stale'},
      ],
    });
    await until(() => next.requests.isNotEmpty && s.cues.isNotEmpty);
    expect(s.cues.any((c) => c.original == 'stale'), isFalse);
    expect(s.cues.first.startMs, greaterThanOrEqualTo(49200));
  });
  test('target changes discard an in-flight translation', () async {
    await preferences.setTarget('vi');
    final translation = Completer<String>();
    var calls = 0;
    final s = session(
      _Worker.new,
      translate: (_, text, target) {
        calls++;
        return translation.future;
      },
    );
    await until(() => calls == 1);
    await preferences.setTarget('en');
    translation.complete('old Vietnamese target');
    await until(() => s.cues.isNotEmpty);
    expect(s.cues.first.text, 'hello world');
    expect(s.cues.any((c) => c.text == 'old Vietnamese target'), isFalse);
  });
  test(
    'model management releases the worker before deleting its weights',
    () async {
      final worker = _Worker();
      final s = session(() => worker);
      await until(() => s.cues.isNotEmpty);
      await models.uninstallModel('whisper/small');
      expect(worker.stopped, isTrue);
      expect(await File('${sandbox.path}/speech.bin').exists(), isFalse);
      await until(() => s.phase == SubtitlePhase.missingModels);
    },
  );
  test('same-language captions skip translation', () async {
    var translated = false;
    final s = session(
      _Worker.new,
      translate: (_, text, target) async {
        translated = true;
        return 'translated';
      },
    );
    await until(() => s.cues.isNotEmpty);
    expect(translated, isFalse);
    expect(s.cues.first.text, 'hello world');
  });

  test(
    'Japanese audio passes ja to recognition and translates original Japanese to Vietnamese',
    () async {
      await preferences.setSource('ja');
      await preferences.setTarget('vi');
      final worker = _Worker()
        ..language = 'ja'
        ..recognizedText = 'こんにちは、世界。';
      final s = session(
        () => worker,
        translate: (_, text, target) async {
          expect(text, 'こんにちは、世界。');
          expect(target, 'vi');
          return 'Xin chào thế giới.';
        },
      );
      await until(() => s.cues.isNotEmpty);
      expect(worker.requests.first['language'], 'ja');
      expect(s.cues.first.original, 'こんにちは、世界。');
      expect(s.cues.first.text, 'Xin chào thế giới.');
    },
  );

  test('Japanese audio kept as Japanese needs no translation model', () async {
    await preferences.setSource('ja');
    await preferences.setTarget('ja');
    await File('${sandbox.path}/translation.gguf').delete();
    var translated = false;
    final worker = _Worker()
      ..language = 'ja'
      ..recognizedText = 'おはようございます。';
    final s = session(
      () => worker,
      translate: (_, text, target) async {
        translated = true;
        return 'unexpected';
      },
    );
    await until(() => s.cues.isNotEmpty);
    expect(translated, isFalse);
    expect(s.cues.first.text, 'おはようございます。');
    expect(s.phase, SubtitlePhase.ready);
  });
  test(
    'progress distinguishes model loading, recognition and completed silence',
    () async {
      final loaded = Completer<void>();
      final recognized = Completer<Map<String, dynamic>>();
      final worker = _Worker()
        ..startGate = loaded
        ..gate = recognized;
      final s = session(() => worker);
      await until(() => s.progress.modelName == 'speech');
      expect(s.progress.stage, SubtitleWorkStage.loadingSpeech);
      expect(s.progress.processedUntil, isNull);
      loaded.complete();
      await until(() => worker.requests.isNotEmpty);
      expect(s.progress.stage, SubtitleWorkStage.recognizing);
      expect(s.progress.pending!.end, const Duration(seconds: 8));
      expect(s.progress.completed, isEmpty);
      worker.gate = Completer<Map<String, dynamic>>();
      recognized.complete({'language': 'en', 'segments': []});
      await until(() => s.progress.processedUntil != null);
      expect(s.cues, isEmpty);
      expect(s.progress.processedUntil, const Duration(seconds: 8));
    },
  );
  test(
    'translated progress advances only after translation finishes',
    () async {
      await preferences.setTarget('vi');
      final translated = Completer<String>();
      final nextTranslation = Completer<String>();
      var translationCalls = 0;
      final worker = _Worker();
      final s = session(
        () => worker,
        translate: (_, text, target) => ++translationCalls == 1
            ? translated.future
            : nextTranslation.future,
      );
      await until(() => s.progress.stage == SubtitleWorkStage.translating);
      expect(s.progress.modelName, 'translation');
      expect(s.progress.processedUntil, isNull);
      expect(s.progress.pending!.start, Duration.zero);
      expect(worker.requests.length, 2); // Recognition overlaps translation.
      worker.gate = Completer<Map<String, dynamic>>();
      translated.complete('Xin chào');
      await until(() => s.progress.processedUntil != null);
      expect(s.progress.processedUntil, const Duration(seconds: 8));
      nextTranslation.complete('Đoạn tiếp theo');
    },
  );
  test(
    'a seek starts progress at that position, without a completed prefix',
    () async {
      native.state = native.state.copyWith(
        position: const Duration(seconds: 50),
      );
      final worker = _Worker();
      final s = session(() => worker);
      await until(() => s.progress.completed.isNotEmpty);
      expect(s.progress.completed.first.start, const Duration(seconds: 50));
      expect(
        s.progress.processedUntil,
        greaterThanOrEqualTo(const Duration(seconds: 58)),
      );
      worker.gate = Completer<Map<String, dynamic>>();
      s.restart();
      expect(s.progress.completed, isEmpty);
      expect(s.progress.processedUntil, isNull);
    },
  );
  test(
    'follow-app is a persistent setting and explicit target overrides it',
    () async {
      await preferences.setTarget(SubtitlePreferences.followApp);
      await LanguageController().changeLanguage('vi');
      expect(preferences.resolvedTarget, 'vi');
      await preferences.setTarget('ja');
      await LanguageController().changeLanguage('tr');
      expect(preferences.resolvedTarget, 'ja');
      final restored = SubtitlePreferences(prefs);
      expect(restored.targetLanguage, 'ja');
      restored.dispose();
      await LanguageController().changeLanguage('en');
    },
  );
  test(
    'reopen uses saved translated cues without loading either model',
    () async {
      final cache = await createCache();
      await preferences.setTarget('vi');
      var translations = 0;
      final first = session(
        () => _Worker(),
        cache: cache,
        translate: (_, text, lang) async {
          translations++;
          return 'Xin chào';
        },
      );
      await until(
        () => first.progress.processedUntil == const Duration(seconds: 16),
      );
      expect(translations, 2);
      first.dispose();
      sessions.remove(first);
      await File('${sandbox.path}/speech.bin').delete();
      await File('${sandbox.path}/translation.gguf').delete();
      var started = 0;
      final next = session(() {
        started++;
        return _Worker();
      }, cache: cache);
      await until(() => next.progress.cacheState == SubtitleCacheState.reused);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(started, 0);
      expect(next.cues.first.text, 'Xin chào');
      expect(next.cues.first.original, 'hello world');
      expect(next.progress.completed.single.end, const Duration(seconds: 16));
    },
  );

  test(
    'language change misses old cache and clear regenerates current version',
    () async {
      final cache = await createCache();
      var started = 0;
      final worker = _Worker();
      final s = session(
        () {
          started++;
          return worker;
        },
        cache: cache,
        translate: (_, text, lang) async => 'translated',
      );
      await until(
        () => s.progress.processedUntil == const Duration(seconds: 16),
      );
      await preferences.setTarget('vi');
      await until(
        () =>
            worker.requests.length == 4 &&
            s.progress.processedUntil == const Duration(seconds: 16),
      );
      expect((await cache.stats()).entries, 2);
      await s.regenerate();
      await until(
        () =>
            worker.requests.length == 6 &&
            s.progress.processedUntil == const Duration(seconds: 16),
      );
      expect((await cache.stats()).entries, 2);
      expect(started, 1); // Reuse loaded speech weights across target/clear.
    },
  );

  test(
    'silent cached chunks are reused and seek does not mark a prefix complete',
    () async {
      final cache = await createCache();
      native.state = native.state.copyWith(
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 66),
      );
      final worker = _Worker()..gate = Completer<Map<String, dynamic>>();
      final first = session(() => worker, cache: cache);
      await until(() => worker.requests.isNotEmpty);
      worker.gate!.complete({'language': 'en', 'segments': []});
      await until(
        () => first.progress.processedUntil == const Duration(seconds: 66),
      );
      first.dispose();
      sessions.remove(first);
      var started = 0;
      final next = session(() {
        started++;
        return _Worker();
      }, cache: cache);
      await until(() => next.progress.cacheState == SubtitleCacheState.reused);
      expect(next.progress.completed.single.start, const Duration(seconds: 50));
      expect(next.progress.reachedEnd, isFalse);
      expect(next.cues, isEmpty);
      expect(started, 0);
    },
  );

  test(
    'clearing cache during translation rejects old work and restarts',
    () async {
      final cache = await createCache();
      await preferences.setTarget('vi');
      final pending = Completer<String>();
      var translations = 0;
      final s = session(
        () => _Worker(),
        cache: cache,
        translate: (_, text, lang) async {
          return ++translations == 1 ? pending.future : 'fresh';
        },
      );
      await until(() => translations == 1);
      await cache.clear();
      pending.complete('stale');
      await until(
        () => s.progress.processedUntil == const Duration(seconds: 16),
      );
      expect(s.cues.every((c) => c.text == 'fresh'), isTrue);
      expect((await cache.stats()).entries, 1);
    },
  );

  test(
    'audio track, source language, source version and speech model isolate cache',
    () async {
      final cache = await createCache();
      var source = 'movie-v1';
      var started = 0;
      final worker = _Worker();
      final s = session(
        () {
          started++;
          return worker;
        },
        cache: cache,
        fingerprint: () async => source,
      );
      await until(
        () => s.progress.processedUntil == const Duration(seconds: 16),
      );
      player.audioTrack = 1;
      s.restart();
      await until(
        () =>
            worker.requests.length == 4 &&
            s.progress.processedUntil == const Duration(seconds: 16),
      );
      await preferences.setSource('ja');
      await until(
        () =>
            worker.requests.length == 6 &&
            s.progress.processedUntil == const Duration(seconds: 16),
      );
      source = 'movie-replaced';
      s.restart();
      await until(
        () =>
            worker.requests.length == 8 &&
            s.progress.processedUntil == const Duration(seconds: 16),
      );
      await preferences.setSpeechModel('whisper/base');
      await until(() => s.phase == SubtitlePhase.missingModels);
      expect(s.cues, isEmpty);
      expect((await cache.stats()).entries, 4);
      expect(started, 1);
    },
  );

  test(
    'cache errors do not prevent recognition or expose unsaved results as saved',
    () async {
      final failing = SubtitleCache(
        openDatabase: () async => throw StateError('unavailable'),
      );
      final s = session(() => _Worker(), cache: failing);
      await until(
        () => s.progress.processedUntil == const Duration(seconds: 16),
      );
      expect(s.phase, SubtitlePhase.ready);
      expect(s.progress.cacheState, SubtitleCacheState.failed);
      expect(s.cues, isNotEmpty);
    },
  );

  test(
    'completed translated cues appear while the next cue is still translating',
    () async {
      await preferences.setTarget('vi');
      native.state = native.state.copyWith(
        position: const Duration(seconds: 2),
      );
      final worker = _Worker()..gate = Completer<Map<String, dynamic>>();
      worker.gate!.complete({
        'language': 'en',
        'segments': [
          {'start_ms': 1200, 'end_ms': 4000, 'text': 'first sentence'},
          {'start_ms': 4000, 'end_ms': 8000, 'text': 'second sentence'},
        ],
      });
      final pending = Completer<String>();
      var translated = 0;
      final s = session(
        () => worker,
        translate: (_, text, target) async =>
            ++translated == 1 ? 'Câu đầu tiên' : pending.future,
      );
      await until(() => translated == 2 && s.text == 'Câu đầu tiên');
      expect(s.progress.completed, isEmpty);
      expect(worker.requests.length, 2); // Exactly one recognition prefetch.
      pending.complete('Câu thứ hai');
    },
  );

  test(
    'idle seeks and bilingual changes keep the loaded speech worker',
    () async {
      final worker = _Worker();
      var started = 0;
      final s = session(() {
        started++;
        return worker;
      });
      await until(
        () => s.progress.processedUntil == const Duration(seconds: 16),
      );
      await preferences.setBilingual(true);
      expect(s.cues, isNotEmpty);
      expect(worker.requests.length, 2);
      native.state = native.state.copyWith(
        position: const Duration(seconds: 50),
      );
      await until(
        () =>
            s.progress.completed.isNotEmpty &&
            s.progress.completed.first.start == const Duration(seconds: 50),
      );
      expect(started, 1);
      expect(worker.stopped, isFalse);
    },
  );

  test(
    'speech and translation models prepare concurrently and stay warm on an idle seek',
    () async {
      await preferences.setSource('ja');
      await preferences.setTarget('vi');
      final speechReady = Completer<void>();
      final worker = _Worker()
        ..startGate = speechReady
        ..language = 'ja';
      final runtime = _Translator()..gate = Completer<void>();
      var created = 0;
      final s = session(
        () => worker,
        runtime: () {
          created++;
          return runtime;
        },
      );
      await until(
        () =>
            runtime.preparations == 1 &&
            s.progress.stage == SubtitleWorkStage.loadingSpeech,
      );
      expect(s.cues, isEmpty);
      runtime.gate!.complete();
      speechReady.complete();
      await until(
        () => s.progress.processedUntil == const Duration(seconds: 16),
      );
      native.state = native.state.copyWith(
        position: const Duration(seconds: 50),
      );
      await until(
        () =>
            s.progress.completed.isNotEmpty &&
            s.progress.completed.first.start == const Duration(seconds: 50),
      );
      expect(created, 1);
      expect(runtime.preparations, 1);
      expect(runtime.disposed, isFalse);
    },
  );

  test(
    'failed translation preparation is discarded so retry can recover',
    () async {
      await preferences.setSource('ja');
      await preferences.setTarget('vi');
      final first = _Translator()..preparationError = StateError('load failed');
      final recovered = _Translator();
      var created = 0;
      final s = session(
        () => _Worker()..language = 'ja',
        runtime: () => created++ == 0 ? first : recovered,
      );
      await until(() => s.phase == SubtitlePhase.failed);
      expect(first.disposed, isTrue);
      s.restart();
      await until(() => s.cues.isNotEmpty);
      expect(s.cues.first.text, 'Bản dịch');
      expect(created, 2);
    },
  );

  test(
    'installing an unrelated chat model does not interrupt subtitle work',
    () async {
      final worker = _Worker();
      var created = 0;
      final s = session(() {
        created++;
        return worker;
      });
      await until(
        () => s.progress.processedUntil == const Duration(seconds: 16),
      );
      final registry =
          jsonDecode(prefs.getString('local_ai_installed_models')!) as List;
      registry.add(
        InstalledLocalModel(
          catalogId: 'chat/other',
          displayName: 'Chat',
          localPath: 'chat.gguf',
          sizeBytes: 1,
          installedAt: DateTime(2026),
        ).toJson(),
      );
      await prefs.setString('local_ai_installed_models', jsonEncode(registry));
      await models.refreshInstalledModels();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(created, 1);
      expect(worker.stopped, isFalse);
      expect(s.cues, isNotEmpty);
    },
  );

  test(
    'translation tokens are visible before completion and only final text enters cache',
    () async {
      final cache = await createCache();
      await preferences.setSource('ja');
      await preferences.setTarget('vi');
      native.state = native.state.copyWith(
        position: const Duration(seconds: 2),
      );
      final stream = StreamController<String>();
      var sends = 0;
      final runtime = _Translator()
        ..output = () =>
            sends++ == 0 ? stream.stream : Stream.value('Tiếp theo');
      final s = session(
        () => _Worker()..language = 'ja',
        runtime: () => runtime,
        cache: cache,
      );
      await until(() => stream.hasListener);
      stream.add('Xin chào');
      await until(() => s.text == 'Xin chào');
      expect(s.cues, isEmpty);
      expect(s.progress.completed, isEmpty);
      expect((await cache.stats()).entries, 0);
      stream.add(' thế giới');
      await stream.close();
      await until(() => s.cues.isNotEmpty && s.progress.completed.isNotEmpty);
      expect(s.cues.first.text, 'Xin chào thế giới');
      expect((await cache.stats()).entries, 1);
    },
  );

  test('overlap matching respects words and unspaced text', () {
    expect(
      trimSubtitleOverlap('Xin chào thế giới', 'thế giới hôm nay'),
      'hôm nay',
    );
    expect(trimSubtitleOverlap('你好世界', '世界和平'), '和平');
    expect(trimSubtitleOverlap('time', 'timeless story'), 'timeless story');
  });
}
