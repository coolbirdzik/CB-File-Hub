import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/gguf_llama_cpp_runtime.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/media/local_subtitle_session.dart';
import 'package:cb_file_manager/services/media/media_kit_playback.dart';
import 'package:cb_file_manager/services/media/subtitle_activity.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_job_runner.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_models.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_queue.dart';
import 'package:cb_file_manager/services/system/system_resources.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_scanner.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_store.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_generated_metadata.dart';
import 'package:cb_file_manager/services/media/subtitle_cache.dart';
import 'package:cb_file_manager/services/media/subtitle_srt.dart';
import 'package:cb_file_manager/services/media/subtitle_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _settings = SubtitleBatchSettings(
  speechModel: 'whisper/small',
  sourceLanguage: 'auto',
  translationModel: 'tencent/Hy-MT2-1.8B-GGUF',
  targetLanguage: 'vi',
);

class _Platform extends mk.PlatformPlayer {
  _Platform(Duration duration)
    : super(configuration: const mk.PlayerConfiguration()) {
    state = state.copyWith(duration: duration);
  }
}

class _Playback extends PlaybackPlayer {
  String? path;
  _Playback(Duration duration)
    : super(player: mk.Player(platformPlayer: _Platform(duration)));
  @override
  Future<void> open(PlaybackMedia media, {bool play = true}) async {
    path = media.uri;
  }

  @override
  String? get subtitleSource => path;
  @override
  Future<int> subtitleAudioTrackOrdinal() async => 0;
}

class _Worker extends SubtitleWorker {
  bool stopped = false;
  int requests = 0;
  final starts = <int>[];
  Completer<void>? gate;

  /// Requests after this many wait for [gate].
  int openRequests;
  _Worker([this.gate, this.openRequests = 0]);
  @override
  Future<void> start(String model) async {}
  @override
  Future<Map<String, dynamic>> request(Map<String, Object?> command) async {
    requests++;
    final start = command['start_ms']! as int;
    starts.add(start);
    if (requests > openRequests) await gate?.future;
    return {
      'language': 'en',
      'segments': [
        {
          'start_ms': start,
          'end_ms': start + (command['duration_ms']! as int),
          'text': 'line $start',
        },
      ],
    };
  }

  @override
  Future<void> stop() async => stopped = true;
}

/// Scripted outcomes for queue tests that do not need a player.
class _ScriptedRunner extends SubtitleBatchJobRunner {
  final outcomes = <String, SubtitleBatchOutcome>{};

  /// Outcomes of the next run only.
  final once = <String, SubtitleBatchOutcome>{};
  final ran = <String>[];
  Completer<void>? hold;
  SubtitleBatchAbort? lastAbort;

  /// The latest run of each path.
  final aborts = <String, SubtitleBatchAbort>{};
  int active = 0, maxActive = 0;
  @override
  Future<SubtitleBatchOutcome> run(
    SubtitleBatchJob job, {
    required SubtitleBatchAbort abort,
    void Function(double progress)? onProgress,
    void Function(Duration processed)? onProcessed,
  }) async {
    ran.add(job.path);
    lastAbort = abort;
    aborts[job.path] = abort;
    active++;
    if (active > maxActive) maxActive = active;
    try {
      onProgress?.call(.5);
      if (hold != null) {
        await Future.any([hold!.future, abort.future]);
        if (abort.aborted) {
          return SubtitleBatchOutcome(
            SubtitleBatchOutcomeKind.aborted,
            message: abort.reason,
          );
        }
      }
      return once.remove(job.path) ??
          outcomes[job.path] ??
          const SubtitleBatchOutcome(SubtitleBatchOutcomeKind.done);
    } finally {
      active--;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late SubtitleBatchStore store;
  late Directory sandbox;
  var clock = DateTime(2026, 11, 25);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    clock = DateTime(2026, 11, 25);
    store = SubtitleBatchStore(openDatabase: () async => db, now: () => clock);
    sandbox = await Directory.systemTemp.createTemp('subtitle-batch-');
    SubtitleActivity.resetForTest();
    // Heartbeats are written without awaiting; keep them out of the sandbox
    // so deleting it never races an open file handle.
    SubtitleActivity.fileOverride = p.join(
      Directory.systemTemp.path,
      'cb-subtitle-activity-test-$pid',
    );
  });
  tearDown(() async {
    await db.close();
    await sandbox.delete(recursive: true);
  });

  Future<void> until(bool Function() condition, {int tries = 300}) async {
    for (var i = 0; i < tries && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  Future<String> video(String name) async {
    final file = File(p.join(sandbox.path, name));
    await file.create(recursive: true);
    await file.writeAsBytes([0]);
    return file.path;
  }

  group('store', () {
    test(
      'deleted focused rule stops its scope and rejects late scan results',
      () async {
        SubtitleBatchRule makeRule(String name, String folder) =>
            SubtitleBatchRule(
              name: name,
              folders: [folder],
              speechModel: _settings.speechModel,
              sourceLanguage: _settings.sourceLanguage,
              translationModel: _settings.translationModel,
              targetLanguage: _settings.targetLanguage,
            );
        final rule = await store.saveRule(makeRule('Remove me', 'a'));
        final other = await store.saveRule(makeRule('Keep me', 'b'));
        await store.enqueue(
          ['a.mp4'],
          settings: _settings,
          ruleId: rule.id,
          ruleName: rule.name,
        );
        await store.enqueue(
          ['b.mp4'],
          settings: _settings,
          ruleId: other.id,
          ruleName: other.name,
        );
        await store.setRunRule(rule.id);
        await store.setRunRequested(true);
        await store.deleteRule(rule.id!);
        expect(await store.runRequested(), isFalse);
        expect(await store.runRule(), isNull);
        expect((await store.rules()).map((r) => r.id), [other.id]);
        expect(
          await store.enqueue(
            ['late.mp4'],
            settings: _settings,
            ruleId: rule.id,
            ruleName: rule.name,
          ),
          0,
        );
        expect((await store.jobs()).map((j) => j.path), ['b.mp4']);
      },
    );

    test(
      'pending jobs follow original video modification time, not enqueue time',
      () async {
        final older = await video('older.mp4');
        final newer = await video('newer.mp4');
        final missing = p.join(sandbox.path, 'missing.mp4');
        await File(older).setLastModified(DateTime(2025, 1, 1));
        await File(newer).setLastModified(DateTime(2025, 2, 1));
        await store.enqueue(
          [missing, older, newer],
          settings: _settings,
          ruleName: 'r',
        );
        expect((await store.jobs()).map((job) => job.path), [
          newer,
          older,
          missing,
        ]);
        expect((await store.claimNext())!.path, newer);
        final oldRow = (await store.jobs()).firstWhere(
          (job) => job.path == older,
        );
        await File(older).setLastModified(DateTime(2025, 3, 1));
        clock = clock.add(const Duration(days: 1));
        expect(
          await store.enqueue([older], settings: _settings, ruleName: 'r'),
          0,
        );
        final refreshed = (await store.job(oldRow.id))!;
        expect(refreshed.fileModifiedAt, DateTime(2025, 3, 1));
        expect(refreshed.updatedAt, oldRow.updatedAt);
        expect((await store.claimNext())!.path, older);
        expect((await store.claimNext())!.path, missing);
      },
    );

    test(
      'processing priority is saved and can change while a job runs',
      () async {
        final older = await video('old.mp4');
        final newer = await video('new.mp4');
        final tied = await video('tie.mp4');
        final missing = p.join(sandbox.path, 'unknown.mp4');
        await File(older).setLastModified(DateTime(2025, 1, 1));
        await File(tied).setLastModified(DateTime(2025, 1, 1));
        await File(newer).setLastModified(DateTime(2025, 2, 1));
        await store.enqueue(
          [missing, newer, older, tied],
          settings: _settings,
          ruleName: 'r',
        );
        expect(await store.processingOrder(), SubtitleBatchOrder.newestFirst);
        final running = (await store.claimNext())!;
        expect(running.path, newer);

        await store.setProcessingOrder(SubtitleBatchOrder.oldestFirst);
        final reopened = SubtitleBatchStore(openDatabase: () async => db);
        expect(
          await reopened.processingOrder(),
          SubtitleBatchOrder.oldestFirst,
        );
        expect((await reopened.jobs()).map((j) => j.path), [
          newer,
          older,
          tied,
          missing,
        ]);
        expect(
          (await reopened.job(running.id))!.status,
          SubtitleBatchStatus.running,
        );
        expect((await reopened.claimNext())!.path, older);
        expect((await reopened.claimNext())!.path, tied);
        expect((await reopened.claimNext())!.path, missing);
        await reopened.setProcessingOrder(SubtitleBatchOrder.newestFirst);
        expect(await store.processingOrder(), SubtitleBatchOrder.newestFirst);
      },
    );

    test(
      'cached database is migrated before date-dependent queries without resetting jobs',
      () async {
        final path = await video('existing.mp4');
        final modified = DateTime(2025, 3, 5);
        await File(path).setLastModified(modified);
        await store.enqueue([path], settings: _settings, ruleName: 'r');
        final running = (await store.claimNext())!;
        await store.finish(
          running,
          SubtitleBatchStatus.done,
          outputPath: '$path.srt',
        );
        await db.execute('DROP INDEX subtitle_batch_jobs_modified');
        await db.execute(
          'ALTER TABLE subtitle_batch_jobs DROP COLUMN file_modified_at',
        );
        final reopened = SubtitleBatchStore(openDatabase: () async => db);
        // Simulate a connection already initialized before the metadata
        // feature is used (as when Flutter hot reload retains the store).
        await reopened.rules();
        expect(
          (await db.rawQuery(
            'PRAGMA table_info(subtitle_batch_jobs)',
          )).map((row) => row['name']),
          isNot(contains('file_modified_at')),
        );
        final results = await Future.wait([reopened.jobs(), reopened.jobs()]);
        final job = results.first.single;
        expect(results.last.single.fileModifiedAt, modified);
        expect(job.id, running.id);
        expect(job.status, SubtitleBatchStatus.done);
        expect(job.outputPath, '$path.srt');
        expect(job.fileModifiedAt, modified);
      },
    );

    test('queues a video once per settings and claims in order', () async {
      expect(
        await store.enqueue(['a', 'b'], settings: _settings, ruleName: 'r'),
        2,
      );
      expect(
        await store.enqueue(['b', 'c'], settings: _settings, ruleName: 'r'),
        1,
      );
      final other = SubtitleBatchSettings.fromJson({
        ..._settings.toJson(),
        'target': 'en',
      });
      expect(await store.enqueue(['a'], settings: other, ruleName: 'r'), 1);
      expect((await store.claimNext())!.path, 'a');
      expect((await store.claimNext())!.path, 'b');
      final counts = await store.counts();
      expect(counts[SubtitleBatchStatus.running], 2);
      expect(counts[SubtitleBatchStatus.pending], 2);
    });

    test(
      'rules are independent: each owns, counts and edits its jobs',
      () async {
        expect(
          await store.enqueue(
            ['a', 'b'],
            settings: _settings,
            ruleId: 1,
            ruleName: 'one',
          ),
          2,
        );
        expect(
          await store.enqueue(
            ['a'],
            settings: _settings,
            ruleId: 2,
            ruleName: 'two',
          ),
          1,
          reason: 'the same video and settings in another rule is its own job',
        );
        expect(
          await store.enqueue(
            ['a'],
            settings: _settings,
            ruleId: 1,
            ruleName: 'one',
          ),
          0,
        );
        expect((await store.jobs(ruleId: 1)).map((j) => j.path), ['a', 'b']);
        expect((await store.jobs(ruleId: 2)).single.ruleId, 2);
        expect((await store.counts(ruleId: 2))[SubtitleBatchStatus.pending], 1);
        final perRule = await store.ruleCounts();
        expect(perRule[1]![SubtitleBatchStatus.pending], 2);
        expect(perRule[2]![SubtitleBatchStatus.pending], 1);

        // Editing rule 1 moves its waiting jobs only.
        final running = (await store.claimNext())!;
        expect(running.ruleId, 1);
        final english = SubtitleBatchSettings.fromJson({
          ..._settings.toJson(),
          'target': 'en',
        });
        await store.updateRuleJobs(1, ruleName: 'uno', settings: english);
        final one = {for (final j in await store.jobs(ruleId: 1)) j.path: j};
        expect(one['a']!.settings.targetLanguage, 'vi', reason: 'running');
        expect(one['b']!.settings.targetLanguage, 'en');
        expect(one['b']!.ruleName, 'uno');
        expect(
          (await store.jobs(ruleId: 2)).single.settings.targetLanguage,
          'vi',
        );

        // Rule 2's "a" is a twin: it ran, and failed, together with rule 1's.
        await store.finish(running, SubtitleBatchStatus.failed);
        expect(await store.retryFailed(ruleId: 2), 1);
        expect(
          (await store.jobs(ruleId: 1)).firstWhere((j) => j.path == 'a').status,
          SubtitleBatchStatus.failed,
          reason: 'retrying one rule leaves the other alone',
        );

        await store.deleteRule(1);
        expect(await store.jobs(ruleId: 1), isEmpty);
        expect(await store.jobs(), hasLength(1));
      },
    );

    test('twins in several rules are generated once for all', () async {
      Future<void> queue(int rule, List<String> paths) => store.enqueue(
        paths,
        settings: _settings,
        ruleId: rule,
        ruleName: 'rule $rule',
      );
      await queue(1, ['a', 'b']);
      await queue(2, ['a']);
      final claimed = (await store.claimNext())!;
      expect(claimed.ruleId, 1, reason: 'the first in the queue runs it');
      expect(
        (await store.jobs(ruleId: 2)).single.status,
        SubtitleBatchStatus.running,
        reason: 'rule 2 shows the same video running',
      );
      await store.reportProgress(claimed, .4);
      expect((await store.jobs(ruleId: 2)).single.progress, .4);

      // A rule queued while it runs joins the running generation.
      await queue(3, ['a']);
      expect(
        (await store.jobs(ruleId: 3)).single.status,
        SubtitleBatchStatus.running,
      );

      // Cancelling it for one rule keeps it running for the others.
      await store.cancel([claimed.id]);
      expect(await store.runningTwins(claimed), 2);

      expect(
        await store.finish(
          claimed,
          SubtitleBatchStatus.done,
          progress: 1,
          outputPath: 'Subs/a.vi.srt',
        ),
        isTrue,
      );
      for (final rule in [2, 3]) {
        final job = (await store.jobs(ruleId: rule)).single;
        expect(job.status, SubtitleBatchStatus.done);
        expect(job.outputPath, 'Subs/a.vi.srt');
      }
      expect(
        (await store.job(claimed.id))!.status,
        SubtitleBatchStatus.cancelled,
      );

      // A later rule shows the finished result right away.
      await queue(4, ['a']);
      final late = (await store.jobs(ruleId: 4)).single;
      expect(late.status, SubtitleBatchStatus.done);
      expect(late.outputPath, 'Subs/a.vi.srt');

      // Different settings are not twins.
      await store.enqueue(
        ['a'],
        settings: SubtitleBatchSettings.fromJson({
          ..._settings.toJson(),
          'target': 'en',
        }),
        ruleId: 5,
        ruleName: 'rule 5',
      );
      expect(
        (await store.jobs(ruleId: 5)).single.status,
        SubtitleBatchStatus.pending,
      );
    });

    test('a version 1 queue is migrated to per-rule jobs', () async {
      final legacy = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(legacy.close);
      await legacy.execute('''CREATE TABLE subtitle_batch_jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL,
        rule_id INTEGER, rule_name TEXT, settings TEXT NOT NULL,
        signature TEXT NOT NULL, status TEXT NOT NULL,
        progress REAL NOT NULL DEFAULT 0, message TEXT, output_path TEXT,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        UNIQUE(path, signature))''');
      await legacy.execute(
        'CREATE INDEX subtitle_batch_jobs_status '
        'ON subtitle_batch_jobs(status, id)',
      );
      for (final (path, rule) in [('a', 3), ('b', null)]) {
        await legacy.insert('subtitle_batch_jobs', {
          'path': path,
          'rule_id': rule,
          'rule_name': 'old',
          'settings': '{}',
          'signature': _settings.signature,
          'status': 'done',
          'created_at': 1,
          'updated_at': 1,
        });
      }
      final migrated = SubtitleBatchStore(openDatabase: () async => legacy);
      final jobs = {for (final j in await migrated.jobs()) j.path: j};
      expect(jobs['a']!.ruleId, 3);
      expect(jobs['b']!.ruleId, isNull);
      expect(
        await migrated.enqueue(
          ['a'],
          settings: _settings,
          ruleId: 4,
          ruleName: 'new',
        ),
        1,
      );
    });

    test('a cancelled job is not overwritten by a late result', () async {
      await store.enqueue(['a'], settings: _settings, ruleName: 'r');
      final job = (await store.claimNext())!;
      await store.cancel([job.id]);
      expect(await store.finish(job, SubtitleBatchStatus.done), isFalse);
      expect((await store.job(job.id))!.status, SubtitleBatchStatus.cancelled);
      await store.retry([job.id]);
      expect((await store.job(job.id))!.status, SubtitleBatchStatus.pending);
    });

    test('a stale lease can be taken over, a fresh one cannot', () async {
      const ttl = Duration(seconds: 20);
      expect(await store.tryLease('a', ttl), SubtitleBatchLease.acquired);
      expect(await store.tryLease('a', ttl), SubtitleBatchLease.renewed);
      expect(await store.tryLease('b', ttl), SubtitleBatchLease.denied);
      clock = clock.add(const Duration(seconds: 30));
      expect(await store.tryLease('b', ttl), SubtitleBatchLease.acquired);
    });

    test(
      'process telemetry belongs only to the current, unexpired lease',
      () async {
        const ttl = Duration(seconds: 20);
        await store.tryLease('a', ttl);
        await store.publishProcessIds('a', [100, 101, 101]);
        expect(await store.queueProcessIds(ttl), [100, 101]);
        await store.publishProcessIds('b', [999]);
        expect(await store.queueProcessIds(ttl), [100, 101]);
        clock = clock.add(const Duration(seconds: 21));
        expect(await store.queueProcessIds(ttl), isEmpty);
        await store.tryLease('b', ttl);
        expect(await store.queueProcessIds(ttl), isEmpty);
        await store.publishProcessIds('b', [200]);
        expect(await store.queueProcessIds(ttl), [200]);
        await store.releaseLease('b');
        expect(await store.queueProcessIds(ttl), isEmpty);
      },
    );

    test('rules round-trip', () async {
      final saved = await store.saveRule(
        const SubtitleBatchRule(
          name: 'Anime',
          folders: ['D:/Anime'],
          extensions: ['mkv'],
          namePattern: '*S01*',
          speechModel: 'whisper/small',
          sourceLanguage: 'ja',
          translationModel: 'tencent/Hy-MT2-1.8B-GGUF',
          targetLanguage: 'app',
        ),
      );
      final rules = await store.rules();
      expect(rules.single.id, saved.id);
      expect(rules.single.sourceLanguage, 'ja');
      expect(rules.single.resolve('vi').targetLanguage, 'vi');
      expect(rules.single.matches('D:/Anime/Show S01E02.mkv'), isTrue);
      expect(rules.single.matches('D:/Anime/Show S02E02.mkv'), isFalse);
      expect(rules.single.matches('D:/Anime/Show S01E02.mp4'), isFalse);
    });
  });

  test('scanner skips videos that already have the sidecar', () async {
    final done = await video('show/a.mkv');
    await video('show/b.mkv');
    await video('show/nested/c.mp4');
    await video('show/notes.txt');
    await File(
      p.join(p.dirname(done), 'Subs', 'a.vi.srt'),
    ).create(recursive: true);
    final scanner = SubtitleBatchScanner(
      store: store,
      libraryFiles: (_) async => const [],
    );
    final rule = SubtitleBatchRule(
      name: 'r',
      folders: [p.join(sandbox.path, 'show')],
      speechModel: _settings.speechModel,
      sourceLanguage: 'auto',
      translationModel: _settings.translationModel,
      targetLanguage: 'vi',
    );
    final report = await scanner.enqueueRule(rule, appLanguage: 'en');
    expect(report.found, 3);
    expect(report.skippedExisting, 1);
    expect(report.added, 2);
    final flat = await scanner.videos(rule.copyWith(recursive: false));
    expect(flat.map(p.basename), ['a.mkv', 'b.mkv']);
  });

  group('queue', () {
    late _ScriptedRunner runner;
    late SubtitleBatchQueue queue;
    var watching = false;
    late StreamController<void> modelsInstalled;
    setUp(() {
      watching = false;
      runner = _ScriptedRunner();
      modelsInstalled = StreamController<void>.broadcast();
      queue = SubtitleBatchQueue(
        store: store,
        runner: runner,
        playbackActive: () async => watching,
        tick: const Duration(hours: 1),
        monitorInterval: const Duration(milliseconds: 20),
        owner: 'me',
        modelChanges: () async => modelsInstalled.stream,
        runsJobs: true,
        resources: SystemResourceMonitor(
          sampler: () async => const SystemResourceSample(),
        ),
      );
    });
    tearDown(() async {
      queue.dispose();
      await modelsInstalled.close();
    });

    test('a window that does not host the queue only shows it', () async {
      final viewer = SubtitleBatchQueue(
        store: store,
        runner: runner,
        playbackActive: () async => false,
        tick: const Duration(hours: 1),
        owner: 'viewer',
        modelChanges: () async => const Stream.empty(),
      );
      addTearDown(viewer.dispose);
      await store.enqueue(['a'], settings: _settings, ruleName: 'r');
      await viewer.start();
      await until(() => viewer.state == SubtitleBatchQueueState.otherWindow);
      expect(runner.ran, isEmpty);
      expect(await store.runRequested(), isTrue);
      await queue.pump();
      expect(runner.ran, ['a'], reason: 'the main window picks it up');
    });

    test('does nothing until started, then runs every job', () async {
      await store.enqueue(['a', 'b'], settings: _settings, ruleName: 'r');
      await queue.pump();
      expect(runner.ran, isEmpty);
      expect(queue.state, SubtitleBatchQueueState.paused);
      runner.outcomes['a'] = const SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.failed,
        message: 'boom',
      );
      await queue.start();
      await until(() => queue.state == SubtitleBatchQueueState.idle);
      expect(runner.ran, ['a', 'b']);
      final jobs = {for (final j in await store.jobs()) j.path: j};
      expect(jobs['a']!.status, SubtitleBatchStatus.failed);
      expect(jobs['a']!.message, 'boom');
      expect(jobs['b']!.status, SubtitleBatchStatus.done);
      expect(jobs['b']!.progress, 1);
    });

    test('a missing model blocks the queue instead of failing jobs', () async {
      await store.enqueue(['a', 'b'], settings: _settings, ruleName: 'r');
      runner.outcomes['a'] = const SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.blocked,
        missingModel: 'Whisper',
      );
      await queue.start();
      await until(() => queue.state == SubtitleBatchQueueState.blocked);
      expect(runner.ran, ['a']);
      expect(queue.blockedModel, 'Whisper');
      expect(
        (await store.counts())[SubtitleBatchStatus.pending],
        2,
        reason: 'both jobs wait for the model',
      );
      runner.outcomes.remove('a');
      modelsInstalled.add(null);
      await until(() => queue.state == SubtitleBatchQueueState.idle);
      expect(runner.ran, ['a', 'a', 'b'], reason: 'installing unblocks');
    });

    test('a video two rules share runs once and finishes both', () async {
      await store.enqueue(
        ['a', 'b'],
        settings: _settings,
        ruleId: 1,
        ruleName: 'one',
      );
      await store.enqueue(
        ['a'],
        settings: _settings,
        ruleId: 2,
        ruleName: 'two',
      );
      runner.hold = Completer<void>();
      await queue.start();
      await until(() => queue.currentJobId != null);
      // Rule 1 no longer wants it, rule 2 still does: it keeps running.
      await queue.cancel([queue.currentJobId!]);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(runner.lastAbort!.aborted, isFalse);
      runner.hold!.complete();
      await until(() => queue.state == SubtitleBatchQueueState.idle);
      expect(runner.ran, ['a', 'b']);
      expect(
        (await store.jobs(ruleId: 2)).single.status,
        SubtitleBatchStatus.done,
      );
    });

    test('Start runs only the focused rule', () async {
      await store.enqueue(
        ['a', 'b'],
        settings: _settings,
        ruleId: 1,
        ruleName: 'one',
      );
      await store.enqueue(
        ['b', 'c'],
        settings: _settings,
        ruleId: 2,
        ruleName: 'two',
      );
      await queue.start(ruleId: 2);
      await until(() => queue.state == SubtitleBatchQueueState.idle);
      expect(runner.ran, ['b', 'c'], reason: 'rule 1 alone waits');
      final one = {for (final j in await store.jobs(ruleId: 1)) j.path: j};
      expect(one['a']!.status, SubtitleBatchStatus.pending);
      expect(
        one['b']!.status,
        SubtitleBatchStatus.done,
        reason: 'its twin in rule 2 was generated',
      );
      expect(await store.runRule(), 2);

      await queue.start();
      await until(() => runner.ran.length == 3);
      await until(() => queue.state == SubtitleBatchQueueState.idle);
      expect(runner.ran.last, 'a');
    });

    test('starting another rule puts the running video back', () async {
      await store.enqueue(
        ['a'],
        settings: _settings,
        ruleId: 1,
        ruleName: 'one',
      );
      await store.enqueue(
        ['z'],
        settings: _settings,
        ruleId: 2,
        ruleName: 'two',
      );
      runner.hold = Completer<void>();
      await queue.start(ruleId: 1);
      await until(() => queue.currentJobId != null);
      await queue.start(ruleId: 2);
      await until(() => runner.ran.length == 2);
      expect(runner.ran, ['a', 'z']);
      expect(
        (await store.jobs(ruleId: 1)).single.status,
        SubtitleBatchStatus.pending,
      );
      runner.hold!.complete();
    });

    test('cancelling the running job aborts it', () async {
      await store.enqueue(['a', 'b'], settings: _settings, ruleName: 'r');
      runner.hold = Completer<void>();
      await queue.start();
      await until(() => queue.currentJobId != null);
      final id = queue.currentJobId!;
      await queue.cancel([id]);
      await until(() => runner.ran.length == 2);
      expect((await store.job(id))!.status, SubtitleBatchStatus.cancelled);
      runner.hold!.complete();
      await until(() => queue.state == SubtitleBatchQueueState.idle);
    });

    test('yields to a watched video and resumes the same job', () async {
      await store.enqueue(['a'], settings: _settings, ruleName: 'r');
      runner.hold = Completer<void>();
      await queue.start();
      await until(() => queue.currentJobId != null);
      watching = true;
      await until(
        () =>
            queue.state == SubtitleBatchQueueState.waitingForPlayback &&
            queue.currentJobId == null,
      );
      final job = (await store.jobs()).single;
      expect(job.status, SubtitleBatchStatus.pending);
      expect(job.progress, .5, reason: 'progress is kept for the resume');
      watching = false;
      runner.hold!.complete();
      await queue.pump();
      await until(() => queue.state == SubtitleBatchQueueState.idle);
      expect(runner.ran, ['a', 'a']);
      expect((await store.jobs()).single.status, SubtitleBatchStatus.done);
    });

    test('a new runner resets jobs a crashed runner left running', () async {
      await store.enqueue(['a'], settings: _settings, ruleName: 'r');
      await store.claimNext();
      await store.setRunRequested(true);
      await queue.pump();
      expect(runner.ran, ['a']);
      expect((await store.jobs()).single.status, SubtitleBatchStatus.done);
    });

    test('another window holding the lease keeps this one idle', () async {
      await store.enqueue(['a'], settings: _settings, ruleName: 'r');
      await store.tryLease('other', const Duration(seconds: 20));
      await queue.start();
      await until(() => queue.state == SubtitleBatchQueueState.otherWindow);
      expect(runner.ran, isEmpty);
    });

    test('a slow read is retried before the job fails', () async {
      await store.enqueue(['a'], settings: _settings, ruleName: 'r');
      runner.outcomes['a'] = const SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.failed,
        message: 'Bad state: Audio read failed',
      );
      await queue.start();
      await until(() => queue.state == SubtitleBatchQueueState.idle);
      expect(runner.ran, List.filled(SubtitleBatchFailure.maxAttempts, 'a'));
      final job = (await store.jobs()).single;
      expect(job.status, SubtitleBatchStatus.failed);
      expect(
        SubtitleBatchFailure.kind(job.message),
        SubtitleBatchFailureKind.slowRead,
      );
    });

    test('a retried job that then succeeds is done', () async {
      await store.enqueue(['a'], settings: _settings, ruleName: 'r');
      runner.once['a'] = const SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.failed,
        message: 'Bad state: Subtitle runtime exited',
      );
      await queue.start();
      await until(() => queue.state == SubtitleBatchQueueState.idle);
      expect(runner.ran, ['a', 'a']);
      expect((await store.jobs()).single.status, SubtitleBatchStatus.done);
    });

    for (final message in [
      'Cannot open media audio',
      '${SubtitleBatchFailure.stalledIdle} 100%',
    ]) {
      test('recovers a transient $message using bounded queue retry', () async {
        await store.enqueue(['a'], settings: _settings, ruleName: 'r');
        runner.once['a'] = SubtitleBatchOutcome(
          SubtitleBatchOutcomeKind.failed,
          message: message,
        );
        await queue.start();
        await until(() => queue.state == SubtitleBatchQueueState.idle);
        expect(runner.ran, ['a', 'a']);
        expect((await store.jobs()).single.status, SubtitleBatchStatus.done);
      });
    }

    test('a missing file fails at once', () async {
      await store.enqueue(['a'], settings: _settings, ruleName: 'r');
      runner.outcomes['a'] = const SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.failed,
        message: 'File not found',
      );
      await queue.start();
      await until(() => queue.state == SubtitleBatchQueueState.idle);
      expect(runner.ran, ['a']);
      expect((await store.jobs()).single.status, SubtitleBatchStatus.failed);
    });

    group('parallel jobs', () {
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 100));

      test('the limit defaults to automatic and is clamped', () async {
        expect(await store.parallelJobs(), SubtitleBatchStore.autoParallelJobs);
        await store.setParallelJobs(99);
        expect(await store.parallelJobs(), SubtitleBatchStore.maxParallelJobs);
        await store.setParallelJobs(-3);
        expect(await store.parallelJobs(), SubtitleBatchStore.autoParallelJobs);
      });

      test('automatic starts with one video at a time', () async {
        await store.enqueue(['a', 'b'], settings: _settings, ruleName: 'r');
        runner.hold = Completer<void>();
        await queue.start();
        await until(() => runner.ran.length == 1);
        await settle();
        expect(runner.ran, ['a']);
        expect(queue.autoParallel, isTrue);
        expect(queue.parallelLimit, 1);
        runner.hold!.complete();
        await until(() => queue.state == SubtitleBatchQueueState.idle);
      });

      test('runs up to the chosen number of videos at once', () async {
        await store.enqueue(
          ['a', 'b', 'c'],
          settings: _settings,
          ruleName: 'r',
        );
        await queue.setParallelJobs(2);
        runner.hold = Completer<void>();
        await queue.start();
        await until(() => runner.ran.length == 2);
        await settle();
        expect(runner.ran, ['a', 'b'], reason: 'c waits for a free slot');
        expect(queue.activeJobs.map((j) => j.path), ['a', 'b']);
        expect(queue.state, SubtitleBatchQueueState.running);
        expect(queue.liveProgress(queue.activeJobs.last.id), .5);
        runner.hold!.complete();
        await until(() => queue.state == SubtitleBatchQueueState.idle);
        expect(runner.ran, ['a', 'b', 'c']);
        expect(runner.maxActive, 2);
        expect((await store.jobs()).map((j) => j.status).toSet(), {
          SubtitleBatchStatus.done,
        });
      });

      test('never generates one file twice at the same time', () async {
        await store.enqueue(
          ['a'],
          settings: _settings,
          ruleId: 1,
          ruleName: 'vi',
        );
        await store.enqueue(
          ['a', 'b'],
          settings: SubtitleBatchSettings(
            speechModel: _settings.speechModel,
            sourceLanguage: _settings.sourceLanguage,
            translationModel: _settings.translationModel,
            targetLanguage: 'en',
          ),
          ruleId: 2,
          ruleName: 'en',
        );
        await queue.setParallelJobs(3);
        runner.hold = Completer<void>();
        await queue.start();
        await until(() => runner.ran.length == 2);
        await settle();
        expect(runner.ran, ['a', 'b'], reason: 'the English a waits for a');
        runner.hold!.complete();
        await until(() => queue.state == SubtitleBatchQueueState.idle);
        expect(runner.ran, ['a', 'b', 'a']);
      });

      test('cancel stops only that video; pause stops all', () async {
        await store.enqueue(
          ['a', 'b', 'c'],
          settings: _settings,
          ruleName: 'r',
        );
        await queue.setParallelJobs(2);
        runner.hold = Completer<void>();
        await queue.start();
        await until(() => runner.ran.length == 2);
        final a = queue.activeJobs.firstWhere((j) => j.path == 'a');
        await queue.cancel([a.id]);
        expect(runner.aborts['a']!.aborted, isTrue);
        expect(runner.aborts['b']!.aborted, isFalse);
        await until(() => runner.ran.length == 3);
        expect(runner.ran.last, 'c', reason: 'the free slot is filled');

        await queue.pause();
        expect(runner.aborts['b']!.aborted, isTrue);
        expect(runner.aborts['c']!.aborted, isTrue);
        await until(() => queue.activeJobs.isEmpty);
        final jobs = {for (final j in await store.jobs()) j.path: j.status};
        expect(jobs, {
          'a': SubtitleBatchStatus.cancelled,
          'b': SubtitleBatchStatus.pending,
          'c': SubtitleBatchStatus.pending,
        });
        expect(queue.state, SubtitleBatchQueueState.paused);
      });

      test(
        'switching rule stops only videos the new rule does not want',
        () async {
          await store.enqueue(
            ['a'],
            settings: _settings,
            ruleId: 1,
            ruleName: '1',
          );
          await store.enqueue(
            ['b', 'c'],
            settings: _settings,
            ruleId: 2,
            ruleName: '2',
          );
          await queue.setParallelJobs(2);
          runner.hold = Completer<void>();
          await queue.start();
          await until(() => runner.ran.length == 2);
          await queue.start(ruleId: 2);
          expect(runner.aborts['a']!.aborted, isTrue);
          expect(runner.aborts['b']!.aborted, isFalse);
          await until(() => runner.ran.length == 3);
          expect(runner.ran.last, 'c');
          expect(
            (await store.jobs(ruleId: 1)).single.status,
            SubtitleBatchStatus.pending,
          );
          runner.hold!.complete();
          await until(() => queue.state == SubtitleBatchQueueState.idle);
        },
      );

      test('lowering the limit lets running videos finish', () async {
        await store.enqueue(
          ['a', 'b', 'c'],
          settings: _settings,
          ruleName: 'r',
        );
        await queue.setParallelJobs(2);
        runner.hold = Completer<void>();
        await queue.start();
        await until(() => runner.ran.length == 2);
        await queue.setParallelJobs(1);
        await settle();
        expect(runner.aborts.values.where((a) => a.aborted), isEmpty);
        runner.hold!.complete();
        await until(() => queue.state == SubtitleBatchQueueState.idle);
        expect(runner.ran, ['a', 'b', 'c']);
        expect((await store.jobs()).map((j) => j.status).toSet(), {
          SubtitleBatchStatus.done,
        });
      });

      test('raising the limit fills the new slots right away', () async {
        await store.enqueue(['a', 'b'], settings: _settings, ruleName: 'r');
        runner.hold = Completer<void>();
        await queue.start();
        await until(() => runner.ran.length == 1);
        await queue.setParallelJobs(2);
        await until(() => runner.ran.length == 2);
        expect(queue.activeJobs, hasLength(2));
        runner.hold!.complete();
        await until(() => queue.state == SubtitleBatchQueueState.idle);
      });
    });
  });

  group('job runner', () {
    late SharedPreferences prefs;
    late LocalAiAdvisorService models;
    late SubtitleCache cache;
    late Database cacheDb;
    final workers = <_Worker>[];
    Completer<void>? workerGate;
    var openRequests = 0;

    setUp(() async {
      final speech = File(p.join(sandbox.path, 'speech.bin'));
      await speech.writeAsBytes([1]);
      final translation = File(p.join(sandbox.path, 'translation.gguf'));
      await translation.writeAsBytes([1]);
      SharedPreferences.setMockInitialValues({
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
      models = LocalAiAdvisorService(
        prefs: prefs,
        documentsDirectoryProvider: () async => sandbox,
      );
      cacheDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      cache = SubtitleCache(openDatabase: () async => cacheDb);
      workers.clear();
      workerGate = null;
      openRequests = 0;
    });
    tearDown(() async {
      await models.dispose();
      await cacheDb.close();
    });

    SubtitleBatchJobRunner jobRunner({
      bool withCache = true,
      Duration duration = const Duration(seconds: 16),
      Duration stallTimeout = const Duration(minutes: 10),
      Duration idleTimeout = const Duration(seconds: 45),
    }) => SubtitleBatchJobRunner(
      stallTimeout: stallTimeout,
      idleTimeout: idleTimeout,
      watchInterval: const Duration(milliseconds: 40),
      createPlayer: () => _Playback(duration),
      loadPrefs: () async => prefs,
      createWriter: (prefs) =>
          SubtitleSrtWriter(prefs, setHidden: (_, _) async {}),
      sessionFactory: () async => (player, preferences) {
        final worker = _Worker(workerGate, openRequests);
        workers.add(worker);
        return LocalSubtitleSession(
          player: player,
          preferences: preferences,
          models: models,
          cache: withCache ? cache : null,
          createWorker: () => worker,
          translateText: (_, text, target) async => '[$target] $text',
          createTranslator: GgufLlamaCppLocalAiChatRuntime.new,
          sourceFingerprint: () async => 'fp-${player.subtitleSource}',
          interactive: false,
        );
      },
    );

    SubtitleBatchJob job(String path, {SubtitleBatchSettings? settings}) =>
        SubtitleBatchJob(
          id: 1,
          path: path,
          ruleName: 'r',
          settings: settings ?? _settings,
          status: SubtitleBatchStatus.running,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('generates the whole video and writes the sidecar', () async {
      final path = await video('movie.mkv');
      final progress = <double>[];
      final outcome = await jobRunner().run(
        job(path),
        abort: SubtitleBatchAbort(),
        onProgress: progress.add,
      );
      expect(outcome.kind, SubtitleBatchOutcomeKind.done);
      expect(outcome.outputPath, p.join(sandbox.path, 'Subs', 'movie.vi.srt'));
      final metadata = outcome.metadata!;
      expect(metadata.settings.speechModel, _settings.speechModel);
      expect(metadata.settings.translationModel, _settings.translationModel);
      expect(metadata.cacheKey, isNotNull);
      final sidecar = await SubtitleGeneratedMetadata.readSidecar(
        outcome.outputPath!,
      );
      expect(
        sidecar?.outputSha256,
        SubtitleGeneratedMetadata.hash(
          await File(outcome.outputPath!).readAsBytes(),
        ),
      );
      final srt = await File(outcome.outputPath!).readAsString();
      expect(srt, contains('[vi] line 0'));
      expect(srt, contains('[vi] line 7200'));
      expect(progress.last, 1);
      expect(workers.single.stopped, isTrue, reason: 'models are released');
      expect(SubtitleActivity.local.value, 0, reason: 'batch is not playback');
    });

    test('a second run of a long video reuses the whole cache', () async {
      final path = await video('movie.mkv');
      final settings = SubtitleBatchSettings.fromJson({
        ..._settings.toJson(),
        'output': SubtitleFileMode.appOnly.name,
      });
      // Far beyond the session's ±60 s cue window around the playhead.
      final runner = jobRunner(duration: const Duration(minutes: 10));
      expect(
        (await runner.run(
          job(path, settings: settings),
          abort: SubtitleBatchAbort(),
        )).kind,
        SubtitleBatchOutcomeKind.done,
      );
      expect(workers.first.requests, 75);
      final progress = <double>[];
      final again = await runner.run(
        job(path, settings: settings),
        abort: SubtitleBatchAbort(),
        onProgress: progress.add,
      );
      expect(again.kind, SubtitleBatchOutcomeKind.done);
      expect(workers.last.requests, 0, reason: 'everything came from cache');
      expect(progress.last, 1);
    });

    test('a job resumed after an abort continues where it stopped', () async {
      final path = await video('movie.mkv');
      final runner = jobRunner(duration: const Duration(minutes: 10));
      final abort = SubtitleBatchAbort();
      workerGate = Completer<void>();
      openRequests = 20;
      final first = runner.run(job(path), abort: abort);
      await until(() => workers.isNotEmpty && workers.single.requests > 20);
      abort.abort('playback');
      expect((await first).kind, SubtitleBatchOutcomeKind.aborted);
      workerGate!.complete();
      workerGate = null;
      openRequests = 0;
      final outcome = await runner.run(job(path), abort: SubtitleBatchAbort());
      expect(outcome.kind, SubtitleBatchOutcomeKind.done);
      expect(workers.last.starts.first, greaterThan(100000));
      expect(workers.last.requests, lessThan(60));
      final srt = await File(outcome.outputPath!).readAsString();
      expect(srt, contains('[vi] line 0'));
      expect(srt, contains('[vi] line 591200'));
    });

    test('skips a video whose subtitle already exists', () async {
      final path = await video('movie.mkv');
      await File(p.join(sandbox.path, 'movie.vi.srt')).writeAsString('x');
      final outcome = await jobRunner().run(
        job(path),
        abort: SubtitleBatchAbort(),
      );
      expect(outcome.kind, SubtitleBatchOutcomeKind.skipped);
      expect(workers, isEmpty);
    });

    test('a duration with sub-millisecond precision still finishes', () async {
      // Chunks end at whole milliseconds; completion must use the same
      // precision instead of waiting for the idle watchdog.
      final path = await video('movie.mkv');
      final outcome = await jobRunner(
        duration: const Duration(microseconds: 16000500),
      ).run(job(path), abort: SubtitleBatchAbort());
      expect(outcome.kind, SubtitleBatchOutcomeKind.done);
      final srt = await File(outcome.outputPath!).readAsString();
      expect(srt, contains('[vi] line 7200'));
    });

    test('a slow later chunk is neither idle nor finished', () async {
      final path = await video('movie.mkv');
      final gate = workerGate = Completer<void>();
      openRequests = 1;
      final abort = SubtitleBatchAbort();
      final running = jobRunner(
        duration: const Duration(minutes: 10),
        idleTimeout: const Duration(milliseconds: 150),
      ).run(job(path), abort: abort);
      await until(() => workers.isNotEmpty && workers.single.requests == 2);
      // Far longer than the idle limit while the second chunk waits.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      abort.abort('paused');
      final outcome = await running;
      expect(outcome.kind, SubtitleBatchOutcomeKind.aborted);
      gate.complete();
    });

    test('a job without progress for too long fails as stalled', () async {
      final path = await video('movie.mkv');
      final gate = workerGate = Completer<void>();
      final outcome = await jobRunner(
        stallTimeout: const Duration(milliseconds: 300),
      ).run(job(path), abort: SubtitleBatchAbort());
      expect(outcome.kind, SubtitleBatchOutcomeKind.failed);
      expect(
        SubtitleBatchFailure.kind(outcome.message),
        SubtitleBatchFailureKind.stalledSlow,
      );
      expect(outcome.message, contains('recognizing'));
      expect(workers.single.stopped, isTrue);
      gate.complete();
    });

    test('reports processed media time as it goes', () async {
      final path = await video('movie.mkv');
      final processed = <Duration>[];
      await jobRunner().run(
        job(path),
        abort: SubtitleBatchAbort(),
        onProcessed: processed.add,
      );
      expect(processed, isNotEmpty);
      expect(processed.last, const Duration(seconds: 16));
    });

    test('aborting stops the worker', () async {
      final path = await video('movie.mkv');
      final abort = SubtitleBatchAbort();
      final runner = jobRunner();
      final gate = workerGate = Completer<void>();
      final running = runner.run(job(path), abort: abort, onProgress: (_) {});
      await until(() => workers.isNotEmpty && workers.single.requests > 0);
      abort.abort('paused');
      final outcome = await running;
      expect(outcome.kind, SubtitleBatchOutcomeKind.aborted);
      expect(workers.single.stopped, isTrue);
      gate.complete();
    });

    test('an interactive session reports activity until disposed', () async {
      workerGate = Completer<void>();
      final player = _Playback(const Duration(seconds: 16));
      await player.open(PlaybackMedia(await video('watch.mkv')));
      final preferences = SubtitleBatchPreferences(prefs, _settings);
      final session = LocalSubtitleSession(
        player: player,
        preferences: preferences,
        models: models,
        createWorker: () => _Worker(workerGate),
        translateText: (_, text, _) async => text,
        createTranslator: GgufLlamaCppLocalAiChatRuntime.new,
      );
      final preview = LocalSubtitleSession(
        player: player,
        preferences: preferences,
        models: models,
        createWorker: () => _Worker(workerGate),
        translateText: (_, text, _) async => text,
        createTranslator: GgufLlamaCppLocalAiChatRuntime.new,
        continuous: false,
      );
      addTearDown(preview.dispose);
      await until(() => SubtitleActivity.local.value == 1);
      expect(preview.phase, isNot(SubtitlePhase.off));
      expect(
        SubtitleActivity.local.value,
        1,
        reason: 'a file-browser preview does not make the queue yield',
      );
      expect(await SubtitleActivity.isActive(), isTrue);
      session.dispose();
      expect(SubtitleActivity.local.value, 0);
      workerGate!.complete();
      preferences.dispose();
      await player.dispose();
    });

    test('a missing model reports blocked', () async {
      final path = await video('movie.mkv');
      final settings = SubtitleBatchSettings.fromJson({
        ..._settings.toJson(),
        'speech': 'whisper/large-v3',
      });
      final outcome = await jobRunner().run(
        job(path, settings: settings),
        abort: SubtitleBatchAbort(),
      );
      expect(outcome.kind, SubtitleBatchOutcomeKind.blocked);
    });
  });
}
