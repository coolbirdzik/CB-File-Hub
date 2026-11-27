import 'dart:async';

import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_job_runner.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_models.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_queue.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_store.dart';
import 'package:cb_file_manager/services/system/system_resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _settings = SubtitleBatchSettings(
  speechModel: 'whisper/small',
  sourceLanguage: 'auto',
  translationModel: 'tencent/Hy-MT2-1.8B-GGUF',
  targetLanguage: 'vi',
);

class _Runner extends SubtitleBatchJobRunner {
  var runs = 0;
  Completer<void>? cleanup;
  SubtitleBatchAbort? lastAbort;

  @override
  Future<SubtitleBatchOutcome> run(
    SubtitleBatchJob job, {
    required SubtitleBatchAbort abort,
    void Function(double progress)? onProgress,
    void Function(Duration processed)? onProcessed,
  }) async {
    runs++;
    lastAbort = abort;
    if (cleanup != null) {
      await abort.future;
      await cleanup!.future;
      return SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.aborted,
        message: abort.reason,
      );
    }
    return const SubtitleBatchOutcome(SubtitleBatchOutcomeKind.done);
  }
}

class _Store extends SubtitleBatchStore {
  _Store(Database database, {required DateTime Function() now})
    : super(openDatabase: () async => database, now: now);

  var finishFailures = 0;
  var finishCalls = 0;
  Completer<void>? failedWrite;
  Completer<void>? claimed;
  Completer<void>? returnClaim;
  Completer<void>? retryLease;
  Completer<void>? ownerLeaseGate;
  Completer<void>? ownerLeaseEntered;
  var resets = 0;
  var renewals = 0;

  @override
  Future<SubtitleBatchLease> tryLease(String owner, Duration ttl) async {
    if (owner == 'recovery-test') {
      if (ownerLeaseEntered case final entered? when !entered.isCompleted) {
        entered.complete();
      }
      await ownerLeaseGate?.future;
      if (finishCalls > 0) await retryLease?.future;
    }
    final lease = await super.tryLease(owner, ttl);
    if (owner == 'recovery-test' && lease == SubtitleBatchLease.renewed) {
      renewals++;
    }
    return lease;
  }

  @override
  Future<void> resetRunning() async {
    resets++;
    await super.resetRunning();
  }

  @override
  Future<bool> finish(
    SubtitleBatchJob job,
    SubtitleBatchStatus status, {
    double? progress,
    String? message,
    String? outputPath,
  }) async {
    finishCalls++;
    if (finishFailures > 0) {
      finishFailures--;
      failedWrite?.complete();
      failedWrite = null;
      throw StateError('database is locked');
    }
    return super.finish(
      job,
      status,
      progress: progress,
      message: message,
      outputPath: outputPath,
    );
  }

  @override
  Future<SubtitleBatchJob?> claimNext({int? ruleId}) async {
    final job = await super.claimNext(ruleId: ruleId);
    if (job != null && claimed != null) {
      claimed!.complete();
      await returnClaim!.future;
    }
    return job;
  }
}

Future<void> _until(Future<bool> Function() condition) async {
  for (var i = 0; i < 300; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Queue did not settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;
  late _Store store;
  late _Runner runner;
  late SubtitleBatchQueue queue;
  var disposed = false;
  var clock = DateTime(2026, 11, 25);

  void disposeQueue() {
    if (disposed) return;
    disposed = true;
    queue.dispose();
  }

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    clock = DateTime(2026, 11, 25);
    store = _Store(database, now: () => clock);
    runner = _Runner();
    disposed = false;
    queue = SubtitleBatchQueue(
      store: store,
      runner: runner,
      playbackActive: () async => false,
      tick: const Duration(milliseconds: 20),
      monitorInterval: const Duration(milliseconds: 10),
      modelChanges: () async => const Stream.empty(),
      runsJobs: true,
      owner: 'recovery-test',
      resources: SystemResourceMonitor(
        sampler: () async => const SystemResourceSample(),
      ),
    );
    await store.enqueue(['movie.mkv'], settings: _settings, ruleName: 'r');
  });

  tearDown(() async {
    disposeQueue();
    if (store.returnClaim case final claim? when !claim.isCompleted) {
      claim.complete();
    }
    if (store.retryLease case final retry? when !retry.isCompleted) {
      retry.complete();
    }
    if (store.ownerLeaseGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    if (runner.cleanup case final cleanup? when !cleanup.isCompleted) {
      cleanup.complete();
    }
    await _until(
      () async =>
          await store.tryLease('replacement', const Duration(seconds: 20)) !=
          SubtitleBatchLease.denied,
    );
    await database.close();
  });

  test(
    'an exhausted result write is recovered after bounded retries',
    () async {
      store.finishFailures = 3;
      await queue.start();
      await _until(
        () async =>
            (await store.jobs()).single.status == SubtitleBatchStatus.done,
      );
      expect(store.finishCalls, 4);
      expect(
        runner.runs,
        2,
        reason: 'the abandoned row becomes runnable again',
      );
    },
  );

  test(
    'a temporary result write failure does not strand a running row',
    () async {
      store.finishFailures = 2;
      await queue.start();
      await _until(() async => store.finishCalls > 0);
      await _until(
        () async =>
            (await store.jobs()).single.status == SubtitleBatchStatus.done,
      );
      expect(
        runner.runs,
        1,
        reason: 'retry writing the result, not generation',
      );
      expect(store.finishCalls, 3);
      await queue.pump();
      expect(queue.activeJobs, isEmpty);
    },
  );

  test(
    'a retried old result cannot finish a replacement runner\'s row',
    () async {
      store.finishFailures = 1;
      store.retryLease = Completer<void>();
      final failedWrite = store.failedWrite = Completer<void>();
      await queue.start();
      await failedWrite.future;
      await store.releaseLease('recovery-test');
      expect(
        await store.tryLease('replacement', const Duration(seconds: 20)),
        SubtitleBatchLease.acquired,
      );
      await store.resetRunning();
      final replacement = await store.claimNext();
      store.retryLease!.complete();
      await _until(() async => queue.activeJobs.isEmpty);
      expect(
        (await store.job(replacement!.id))!.status,
        SubtitleBatchStatus.running,
      );
      expect(
        store.finishCalls,
        1,
        reason: 'the old result stops on lease loss',
      );
    },
  );

  test('reacquiring a released lease cannot authorize an old result', () async {
    store.finishFailures = 1;
    store.retryLease = Completer<void>();
    final failedWrite = store.failedWrite = Completer<void>();
    await queue.start();
    await failedWrite.future;
    await store.releaseLease('recovery-test');
    await store.tryLease('replacement', const Duration(seconds: 20));
    await store.resetRunning();
    final replacement = await store.claimNext();
    await store.releaseLease('replacement');
    // Keep the scheduler from taking over again after discarding the old result.
    await store.setRunRequested(false);
    store.retryLease!.complete();
    await _until(() async => queue.activeJobs.isEmpty);
    expect(
      (await store.job(replacement!.id))!.status,
      SubtitleBatchStatus.running,
    );
    expect(store.finishCalls, 1);
  });

  test('disposing keeps the lease until the stopped runner requeues', () async {
    runner.cleanup = Completer<void>();
    await queue.start();
    await _until(() async => runner.runs == 1);
    disposeQueue();
    expect(
      await store.tryLease('replacement', const Duration(seconds: 20)),
      SubtitleBatchLease.denied,
    );
    runner.cleanup!.complete();
    await _until(
      () async =>
          (await store.jobs()).single.status == SubtitleBatchStatus.pending,
    );
  });

  test(
    'slow abort cleanup renews ownership beyond the lease lifetime',
    () async {
      runner.cleanup = Completer<void>();
      await queue.start();
      await _until(() async => runner.runs == 1);
      disposeQueue();
      for (var step = 0; step < 3; step++) {
        final renewals = store.renewals;
        clock = clock.add(const Duration(seconds: 19));
        await _until(() async => store.renewals > renewals);
        expect(
          await store.tryLease('replacement', const Duration(seconds: 20)),
          SubtitleBatchLease.denied,
          reason: 'the decoder still owns the file while it stops',
        );
      }
      runner.cleanup!.complete();
      await _until(
        () async =>
            (await store.jobs()).single.status == SubtitleBatchStatus.pending,
      );
    },
  );

  test(
    'a scheduling pass cannot reacquire ownership for an old worker',
    () async {
      runner.cleanup = Completer<void>();
      await queue.start();
      await _until(() async => runner.runs == 1);
      store.ownerLeaseGate = Completer<void>();
      await store.releaseLease('recovery-test');
      await store.tryLease('replacement', const Duration(seconds: 20));
      await store.resetRunning();
      final replacement = await store.claimNext();
      await store.releaseLease('replacement');
      queue.schedule();
      store.ownerLeaseGate!.complete();
      await _until(() async => runner.lastAbort!.aborted);
      expect(runner.lastAbort!.reason, SubtitleBatchAbortReason.lease);
      await store.setRunRequested(false);
      runner.cleanup!.complete();
      await _until(() async => queue.activeJobs.isEmpty);
      expect(
        (await store.job(replacement!.id))!.status,
        SubtitleBatchStatus.running,
      );
    },
  );

  test(
    'disposing during a claim returns the job without starting it',
    () async {
      store.claimed = Completer<void>();
      store.returnClaim = Completer<void>();
      await queue.start();
      await store.claimed!.future;
      disposeQueue();
      store.returnClaim!.complete();
      await _until(
        () async =>
            (await store.jobs()).single.status == SubtitleBatchStatus.pending,
      );
      expect(runner.runs, 0);
      expect(queue.activeJobs, isEmpty);
      await _until(
        () async =>
            await store.tryLease('replacement', const Duration(seconds: 20)) ==
            SubtitleBatchLease.acquired,
      );
    },
  );

  test(
    'pausing during lease acquisition does not reset or claim rows',
    () async {
      store.ownerLeaseEntered = Completer<void>();
      store.ownerLeaseGate = Completer<void>();
      await queue.start();
      await store.ownerLeaseEntered!.future;
      await queue.pause();
      store.ownerLeaseGate!.complete();
      await queue.pump();
      expect(store.resets, 0);
      expect(runner.runs, 0);
      expect(queue.state, SubtitleBatchQueueState.paused);
    },
  );

  test(
    'disposing during lease acquisition does not reset or claim rows',
    () async {
      store.ownerLeaseEntered = Completer<void>();
      store.ownerLeaseGate = Completer<void>();
      await queue.start();
      await store.ownerLeaseEntered!.future;
      disposeQueue();
      store.ownerLeaseGate!.complete();
      await _until(
        () async =>
            await store.tryLease('replacement', const Duration(seconds: 20)) ==
            SubtitleBatchLease.acquired,
      );
      expect(store.resets, 0);
      expect(runner.runs, 0);
    },
  );
}
