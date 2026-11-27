import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../system/system_resources.dart';
import '../subtitle_activity.dart';
import '../subtitle_services.dart';
import 'subtitle_batch_auto_scaler.dart';
import 'subtitle_batch_processes.dart';
import 'subtitle_batch_job_runner.dart';
import 'subtitle_batch_models.dart';
import 'subtitle_batch_store.dart';

enum SubtitleBatchQueueState {
  /// The user has not started the queue (or paused it).
  paused,

  /// Started, nothing pending.
  idle,
  running,

  /// A video is being watched with AI subtitles; the queue yields to it.
  waitingForPlayback,

  /// A required model is not installed. Jobs stay pending.
  blocked,

  /// Another window runs the queue.
  otherWindow,
}

/// Abort reasons that put the job back in line.
class SubtitleBatchAbortReason {
  static const paused = 'paused';
  static const playback = 'playback';
  static const cancelled = 'cancelled';
  static const removed = 'removed';
  static const lease = 'lease';
}

/// One job being generated.
class _Slot {
  final SubtitleBatchJob job;
  final abort = SubtitleBatchAbort();
  final done = Completer<void>();
  double progress;

  /// Media time the session reported last; the first report (restored from
  /// the cache) is not counted as work.
  Duration? processed;
  _Slot(this.job) : progress = job.progress;
}

/// Runs queued jobs, up to [SubtitleBatchStore.parallelJobs] at a time.
///
/// Only the main window processes jobs ([runsJobs]); it polls from startup, so
/// pressing Start in any window is picked up within one [tick]. Other windows
/// only show the queue. A lease in the shared database additionally keeps two
/// processes from ever running jobs at the same time.
class SubtitleBatchQueue extends ChangeNotifier {
  static final instance = SubtitleBatchQueue();

  static bool get supported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  final SubtitleBatchStore store;
  final SubtitleBatchJobRunner runner;
  final Future<bool> Function() playbackActive;
  final Duration tick;
  final Duration monitorInterval;
  final Duration leaseTtl;
  final String owner;
  final Future<Stream<void>> Function() modelChanges;
  final SystemResourceMonitor resources;
  late final SystemResourceMonitor queueResources;
  final SubtitleBatchAutoScaler autoScaler;
  final DateTime Function() now;

  /// Set in the main window. Elsewhere the queue is shown but not run, so
  /// closing a secondary window never strands a job or its model processes.
  bool runsJobs;

  SubtitleBatchQueue({
    SubtitleBatchStore? store,
    SubtitleBatchJobRunner? runner,
    Future<bool> Function()? playbackActive,
    this.tick = const Duration(seconds: 3),
    this.monitorInterval = const Duration(seconds: 2),
    this.leaseTtl = const Duration(seconds: 20),
    String? owner,
    Future<Stream<void>> Function()? modelChanges,
    this.runsJobs = false,
    SystemResourceMonitor? resources,
    SystemResourceMonitor? queueResources,
    SubtitleBatchAutoScaler? autoScaler,
    DateTime Function()? now,
  }) : modelChanges = modelChanges ?? _installedModelChanges,
       resources = resources ?? SystemResourceMonitor.instance,
       autoScaler =
           autoScaler ??
           SubtitleBatchAutoScaler(
             maxLimit: SubtitleBatchStore.maxParallelJobs,
           ),
       now = now ?? DateTime.now,
       store = store ?? SubtitleBatchStore.instance,
       runner = runner ?? SubtitleBatchJobRunner(),
       playbackActive = playbackActive ?? SubtitleActivity.isActive,
       owner =
           owner ??
           '$pid-${DateTime.now().microsecondsSinceEpoch}-'
               '${math.Random().nextInt(1 << 30)}' {
    this.queueResources =
        queueResources ??
        SystemResourceMonitor(
          sampler: SystemResourceMonitor.processSampler(
            () async => runsJobs && _holdsLease
                ? SubtitleBatchProcesses.instance.ids
                : await this.store.queueProcessIds(leaseTtl),
          ),
        );
  }

  SubtitleBatchQueueState _state = SubtitleBatchQueueState.paused;
  SubtitleBatchQueueState get state => _state;

  static Future<Stream<void>> _installedModelChanges() async =>
      (await SubtitleServices.load()).models.onInstalledModelsChanged;

  /// Display name of the model that blocks the queue.
  String? blockedModel;

  /// The jobs this window is generating, oldest first.
  List<SubtitleBatchJob> get activeJobs => [
    for (final slot in _slots.values) slot.job,
  ];

  /// Live progress of a job generated here; null for any other job.
  double? liveProgress(int jobId) => _slots[jobId]?.progress;

  /// The oldest job this window is generating, if any.
  SubtitleBatchJob? get currentJob => _slots.values.firstOrNull?.job;
  int? get currentJobId => currentJob?.id;
  double get currentProgress => _slots.values.firstOrNull?.progress ?? 0;

  /// Bumped whenever jobs may have changed, for screens to reload.
  int revision = 0;

  /// Whether the number of videos at once is chosen automatically, and the
  /// number in effect. Known after the first scheduling pass.
  bool autoParallel = true;
  int parallelLimit = 1;

  /// Media milliseconds processed by this window's jobs, for the scaler.
  int _processedMs = 0;
  bool _pendingLeft = true;
  bool _watchingResources = false;

  /// Transient failures per video and settings, for automatic retries.
  final _attempts = <String, int>{};

  Timer? _timer;
  Future<void>? _pass;
  bool _passAgain = false;
  bool _holdsLease = false;
  bool _recoverRunning = false;
  final _slots = <int, _Slot>{};
  bool _disposed = false;
  StreamSubscription<void>? _models;
  bool _watchingModels = false;

  void _set(SubtitleBatchQueueState state) {
    if (_state == state) return;
    _state = state;
    if (!_disposed) notifyListeners();
  }

  void _changed() {
    revision++;
    if (!_disposed) notifyListeners();
  }

  /// Starts polling. Cheap: one small query per [tick].
  void ensureStarted() {
    if (_disposed) return;
    if (runsJobs && !_watchingModels) {
      // Installing the missing model in Settings unblocks the queue even
      // when its screen is not open.
      _watchingModels = true;
      unawaited(
        modelChanges().then((changes) {
          if (_disposed) return;
          _models = changes.listen((_) => clearBlock());
        }, onError: (Object e) => debugPrint('Subtitle queue models: $e')),
      );
    }
    _timer ??= Timer.periodic(tick, (_) => schedule());
    schedule();
  }

  /// Runs the videos of [ruleId], or of every rule when null. Switching to
  /// another rule puts a video only the old scope wanted back in line.
  Future<void> start({int? ruleId}) async {
    blockedModel = null;
    await store.setRunRule(ruleId);
    await store.setRunRequested(true);
    autoScaler.restart(now(), _processedMs);
    if (ruleId != null) {
      for (final slot in _slots.values.toList()) {
        if (!await store.servesRule(slot.job, ruleId)) {
          slot.abort.abort(SubtitleBatchAbortReason.paused);
        }
      }
    }
    ensureStarted();
    _changed();
  }

  Future<void> pause() async {
    await store.setRunRequested(false);
    for (final slot in _slots.values) {
      slot.abort.abort(SubtitleBatchAbortReason.paused);
    }
    _set(SubtitleBatchQueueState.paused);
    schedule();
  }

  /// Raising the limit starts more jobs at once; lowering it lets the
  /// running ones finish.
  Future<void> setParallelJobs(int value) async {
    await store.setParallelJobs(value);
    _changed();
    schedule();
  }

  /// Installing a model clears the block; the next tick tries again.
  void clearBlock() {
    if (blockedModel == null) return;
    blockedModel = null;
    schedule();
  }

  Future<void> cancel(Iterable<int> ids) async {
    await store.cancel(ids.toList());
    await _stopIfUnwanted(SubtitleBatchAbortReason.cancelled);
    _changed();
  }

  Future<void> remove(Iterable<int> ids) async {
    await store.remove(ids.toList());
    await _stopIfUnwanted(SubtitleBatchAbortReason.removed);
    _changed();
  }

  /// The running video serves every rule that queued it; it stops only
  /// once none of them still wants it.
  Future<void> _stopIfUnwanted(String reason) async {
    for (final slot in _slots.values.toList()) {
      if (await store.runningTwins(slot.job) == 0) slot.abort.abort(reason);
    }
  }

  Future<void> retry(Iterable<int> ids) async {
    await store.retry(ids);
    _changed();
    schedule();
  }

  /// [ruleId] limits the action to one rule's jobs.
  Future<int> retryFailed({int? ruleId}) async {
    final count = await store.retryFailed(ruleId: ruleId);
    _changed();
    schedule();
    return count;
  }

  Future<int> clearFinished({int? ruleId}) async {
    final count = await store.clearFinished(ruleId: ruleId);
    _changed();
    return count;
  }

  /// Deletes a rule with its jobs, stopping its job if it is running here.
  /// A runner in another process notices the missing row within a tick.
  Future<void> deleteRule(int ruleId) async {
    await store.deleteRule(ruleId);
    await _stopIfUnwanted(SubtitleBatchAbortReason.removed);
    _changed();
    schedule();
  }

  /// Saves an edited rule and moves its waiting jobs to the new settings.
  Future<void> applyRule(
    SubtitleBatchRule rule, {
    required String appLanguage,
  }) async {
    final id = rule.id;
    if (id == null) return;
    await store.updateRuleJobs(
      id,
      ruleName: rule.name,
      settings: rule.resolve(appLanguage),
    );
    _changed();
  }

  /// Called after jobs were queued.
  void notifyEnqueued() {
    _changed();
    schedule();
  }

  /// Starts jobs into free slots without waiting for them.
  void schedule() => unawaited(_schedule());

  /// Schedules, then waits until this window runs no job.
  Future<void> pump() async {
    await _schedule();
    while (_slots.isNotEmpty && !_disposed) {
      await Future.any([for (final slot in _slots.values) slot.done.future]);
      // A finished job schedules the next one itself; wait for that claim.
      await _schedule();
    }
  }

  /// One pass at a time; a request during a pass runs it again, and every
  /// caller waits for that.
  Future<void> _schedule() {
    if (_disposed) return Future.value();
    if (_pass case final pass?) {
      _passAgain = true;
      return pass;
    }
    return _pass = _passes().whenComplete(() => _pass = null);
  }

  Future<void> _passes() async {
    try {
      do {
        _passAgain = false;
        await _fill();
      } while (_passAgain && !_disposed);
    } catch (e) {
      // A pass still running at dispose may find its database closed.
      if (!_disposed) debugPrint('Subtitle queue: $e');
    }
  }

  /// Claims jobs until every slot is busy or none is runnable.
  Future<void> _fill() async {
    if (_disposed) return;
    if (!runsJobs) {
      _set(
        await store.runRequested()
            ? SubtitleBatchQueueState.otherWindow
            : SubtitleBatchQueueState.paused,
      );
      return;
    }
    final run = await store.runRequested();
    final configured = await store.parallelJobs();
    if (_disposed) return;
    autoParallel = configured == SubtitleBatchStore.autoParallelJobs;
    _watchResources(run && autoParallel);
    if (!run) {
      // Stopping jobs keep their rows until they are back in line.
      if (_holdsLease && _slots.isEmpty) {
        _holdsLease = false;
        await store.releaseLease(owner);
      }
      _set(SubtitleBatchQueueState.paused);
      return;
    }
    // A stopping job still owns its row and file; start nothing until it is
    // back in line. Its completion schedules again.
    if (_slots.values.any((slot) => slot.abort.aborted)) return;
    // A result write exhausted its short retries. Wait for the remaining
    // workers before resetting its leftover row; never reset live rows.
    if (_recoverRunning && _slots.isNotEmpty) return;
    final hadSlots = _slots.isNotEmpty;
    final lease = await store.tryLease(owner, leaseTtl);
    if (lease == SubtitleBatchLease.denied ||
        (lease == SubtitleBatchLease.acquired &&
            (hadSlots || _slots.isNotEmpty))) {
      _holdsLease = false;
      if (lease == SubtitleBatchLease.acquired) await store.releaseLease(owner);
      for (final slot in _slots.values) {
        slot.abort.abort(SubtitleBatchAbortReason.lease);
      }
      _set(SubtitleBatchQueueState.otherWindow);
      return;
    }
    if (_disposed) {
      _holdsLease = true;
      return;
    }
    // A pause or shutdown can arrive while the database renews the lease.
    // Recheck before resetting rows or claiming work from that old snapshot.
    final stillRunning = await store.runRequested();
    if (_disposed || !stillRunning) {
      _holdsLease = true;
      if (!_disposed) {
        for (final slot in _slots.values) {
          slot.abort.abort(SubtitleBatchAbortReason.paused);
        }
        if (_slots.isEmpty) {
          _holdsLease = false;
          await store.releaseLease(owner);
        }
        _set(SubtitleBatchQueueState.paused);
      }
      return;
    }
    if (_slots.isEmpty &&
        (!_holdsLease ||
            lease == SubtitleBatchLease.acquired ||
            _recoverRunning)) {
      // The previous runner is gone; its running jobs were interrupted.
      // Never while jobs run here: their rows are live.
      await store.resetRunning();
      _recoverRunning = false;
    }
    _holdsLease = true;
    // Telemetry is best effort and must never interfere with job scheduling.
    try {
      await store.publishProcessIds(owner, SubtitleBatchProcesses.instance.ids);
    } catch (_) {}
    if (blockedModel != null) {
      _set(SubtitleBatchQueueState.blocked);
      return;
    }
    if (await store.pauseWhileWatching() && await playbackActive()) {
      _set(SubtitleBatchQueueState.waitingForPlayback);
      return;
    }
    final limit = parallelLimit = autoParallel
        ? autoScaler.update(
            now: now(),
            processedMs: _processedMs,
            running: _slots.length,
            pending: _pendingLeft,
            resources: resources.latest,
          )
        : configured;
    final rule = await store.runRule();
    // Deleting the focused rule clears its scope and pauses the queue in one
    // transaction. A pass that read `run = true` earlier must not interpret
    // that cleared scope as permission to claim jobs from every other rule.
    if (!await store.runRequested()) {
      _set(SubtitleBatchQueueState.paused);
      return;
    }
    _pendingLeft = true;
    while (_slots.length < limit && !_disposed && blockedModel == null) {
      final job = await store.claimNext(ruleId: rule);
      if (job == null) {
        _pendingLeft = false;
        break;
      }
      if (_disposed) {
        // dispose may run while SQLite is claiming the row. It has not seen
        // this slot, so return it before releasing the lease.
        await _persistResult(_Slot(job), () => store.requeue(job));
        return;
      }
      final slot = _Slot(job);
      _slots[job.id] = slot;
      unawaited(_run(slot));
    }
    if (blockedModel != null) {
      _set(SubtitleBatchQueueState.blocked);
    } else {
      _set(
        _slots.isEmpty
            ? SubtitleBatchQueueState.idle
            : SubtitleBatchQueueState.running,
      );
    }
  }

  /// Samples the machine's load only while the automatic limit needs it.
  void _watchResources(bool watch) {
    if (watch == _watchingResources || !resources.supported) return;
    _watchingResources = watch;
    watch ? resources.acquire() : resources.release();
  }

  Future<void> _run(_Slot slot) async {
    try {
      await _generate(slot);
    } catch (e) {
      debugPrint('Subtitle queue job: $e');
      _recoverRunning = true;
    } finally {
      _slots.remove(slot.job.id);
      slot.done.complete();
      _changed();
      schedule();
    }
  }

  Future<void> _generate(_Slot slot) async {
    final job = slot.job;
    final abort = slot.abort;
    _set(SubtitleBatchQueueState.running);
    _changed();
    var progress = job.progress;
    var reported = job.progress;
    Future<void>? monitoring;
    final monitor = Timer.periodic(monitorInterval, (_) {
      if (monitoring != null) return;
      monitoring = () async {
        try {
          await _monitor(job, abort);
          if (!abort.aborted && progress != reported) {
            final value = progress;
            await store.reportProgress(job, value);
            reported = value;
          }
        } catch (e) {
          debugPrint('Subtitle queue monitor: $e');
        }
      }().whenComplete(() => monitoring = null);
    });
    SubtitleBatchOutcome outcome;
    try {
      outcome = await runner.run(
        job,
        abort: abort,
        onProgress: (value) {
          // Resumed jobs restart from the cache; never show progress shrink.
          progress = math.max(progress, value);
          slot.progress = progress;
          if (!_disposed) notifyListeners();
        },
        onProcessed: (value) {
          final last = slot.processed;
          slot.processed = value;
          if (last != null && value > last) {
            _processedMs += (value - last).inMilliseconds;
          }
        },
      );
    } catch (e) {
      outcome = SubtitleBatchOutcome(
        SubtitleBatchOutcomeKind.failed,
        message: e.toString(),
      );
    } finally {
      monitor.cancel();
      // A timer cancellation does not stop a callback already awaiting SQLite.
      // Drain it before writing a final status or giving up the lease.
      await monitoring;
    }
    if (outcome.kind != SubtitleBatchOutcomeKind.failed &&
        outcome.kind != SubtitleBatchOutcomeKind.aborted) {
      _attempts.remove(_attemptKey(job));
    }
    switch (outcome.kind) {
      case SubtitleBatchOutcomeKind.done:
        await _persistResult(slot, () async {
          if (outcome.metadata case final metadata?) {
            await store.recordGenerated(job, metadata);
          }
          return store.finish(
            job,
            SubtitleBatchStatus.done,
            progress: 1,
            message: outcome.message,
            outputPath: outcome.outputPath,
          );
        });
      case SubtitleBatchOutcomeKind.skipped:
        await _persistResult(
          slot,
          () => store.finish(
            job,
            SubtitleBatchStatus.skipped,
            message: outcome.message,
            outputPath: outcome.outputPath,
          ),
        );
      case SubtitleBatchOutcomeKind.failed:
        final key = _attemptKey(job);
        final attempts = (_attempts[key] ?? 0) + 1;
        if (SubtitleBatchFailure.transient(outcome.message) &&
            attempts < SubtitleBatchFailure.maxAttempts &&
            !_disposed) {
          // Load, not the file, failed it: try again with fewer at once.
          _attempts[key] = attempts;
          if (autoParallel) autoScaler.onTransientFailure(now(), _processedMs);
          await _persistResult(
            slot,
            () => store.requeue(
              job,
              message: outcome.message,
              progress: progress,
            ),
          );
        } else {
          _attempts.remove(key);
          await _persistResult(
            slot,
            () => store.finish(
              job,
              SubtitleBatchStatus.failed,
              progress: progress,
              message: outcome.message,
            ),
          );
        }
      case SubtitleBatchOutcomeKind.blocked:
        blockedModel = outcome.missingModel ?? '';
        await _persistResult(slot, () => store.requeue(job));
        _set(SubtitleBatchQueueState.blocked);
      case SubtitleBatchOutcomeKind.aborted:
        // The new lease holder already reset the row and may be running it.
        if (outcome.message == SubtitleBatchAbortReason.lease) break;
        // Cancel and remove already changed the row; requeue only applies
        // to a job that is still marked running.
        await _persistResult(
          slot,
          () => store.requeue(job, progress: progress),
        );
    }
  }

  /// Keep the slot until its result is durable. A temporary SQLite failure
  /// must not leave a running row with no worker, or generate the video again.
  Future<void> _persistResult<T>(
    _Slot slot,
    Future<T> Function() persist,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (slot.abort.reason == SubtitleBatchAbortReason.lease) return;
      try {
        if (!await _renewLease(slot.abort)) return;
        await persist();
        return;
      } catch (e) {
        debugPrint('Subtitle queue result: $e');
        // Shutdown can close the database. The next lease holder resets rows
        // left running; never keep a disposed queue retrying indefinitely.
        if (_disposed || attempt == 2) rethrow;
        await Future<void>.delayed(monitorInterval);
      }
    }
  }

  static String _attemptKey(SubtitleBatchJob job) =>
      '${job.path}\n${job.settings.signature}';

  /// Automatic retries already made for [job].
  int attemptsOf(SubtitleBatchJob job) => _attempts[_attemptKey(job)] ?? 0;

  Future<void> _releaseWhenStopped() async {
    try {
      await _pass;
      await Future.wait([for (final slot in _slots.values) slot.done.future]);
      if (_holdsLease) {
        _holdsLease = false;
        await store.releaseLease(owner);
      }
    } catch (_) {
      // A closing application's database may already be unavailable.
    }
  }

  Future<void> _monitor(SubtitleBatchJob job, SubtitleBatchAbort abort) async {
    if (!await _renewLease(abort)) return;
    // A stopped worker can still be closing its decoder or model process.
    // Keep its lease alive until cleanup and its final row update finish.
    if (abort.aborted) return;
    final row = await store.job(job.id);
    if (row?.status != SubtitleBatchStatus.running &&
        await store.runningTwins(job) == 0) {
      // Cancelled or removed, here or in another window, by every rule.
      abort.abort(
        row == null
            ? SubtitleBatchAbortReason.removed
            : SubtitleBatchAbortReason.cancelled,
      );
    } else if (!await store.runRequested()) {
      abort.abort(SubtitleBatchAbortReason.paused);
    } else if (await store.runRule() case final rule?
        when !await store.servesRule(job, rule)) {
      // Another window started a different rule.
      abort.abort(SubtitleBatchAbortReason.paused);
    } else if (await store.pauseWhileWatching() && await playbackActive()) {
      abort.abort(SubtitleBatchAbortReason.playback);
      _set(SubtitleBatchQueueState.waitingForPlayback);
    }
  }

  /// A live slot may only renew its original lease. Acquiring an absent lease
  /// means an intervening runner could already have reset and claimed its row.
  Future<bool> _renewLease(SubtitleBatchAbort abort) async {
    final lease = await store.tryLease(owner, leaseTtl);
    if (lease == SubtitleBatchLease.renewed) {
      _holdsLease = true;
      return true;
    }
    _holdsLease = false;
    if (lease == SubtitleBatchLease.acquired) await store.releaseLease(owner);
    abort.abort(SubtitleBatchAbortReason.lease);
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _watchResources(false);
    unawaited(_models?.cancel());
    for (final slot in _slots.values) {
      slot.abort.abort(SubtitleBatchAbortReason.paused);
    }
    // A stopping runner can still be requeuing its row. Keep ownership until
    // that finishes, so it cannot overwrite a replacement runner's claim.
    unawaited(_releaseWhenStopped());
    super.dispose();
  }
}
