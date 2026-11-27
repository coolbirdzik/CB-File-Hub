import 'dart:math' as math;

import '../../system/system_resources.dart';

/// Why the automatic limit is what it is, for the screen.
enum SubtitleBatchAutoReason {
  /// Measuring the speed of the current number of videos.
  measuring,

  /// Trying one more video to see whether the queue gets faster.
  probing,

  /// The last extra video made the queue faster and was kept.
  faster,

  /// The last extra video did not make the queue faster: the machine is
  /// limited elsewhere (disk, GPU busy with another app...).
  noGain,

  /// Too little free RAM or VRAM for another video.
  lowMemory,

  /// Reads timed out or a worker crashed; fewer videos run at once.
  failures,
}

/// Chooses how many videos run at once by measuring the queue's speed.
///
/// Free CPU alone says little: a busy disk or a GPU shared with a game can
/// leave the CPU idle while more jobs only slow each other down. So the
/// scaler adds one video at a time and keeps it only when the processed
/// media time per second grows clearly; memory is a guard, never a reason.
class SubtitleBatchAutoScaler {
  final int maxLimit;

  /// Throughput is compared over this much time per step.
  final Duration window;

  /// New videos load their models first; that time is not measured.
  final Duration warmup;

  /// After an extra video did not help, wait this long before trying again.
  final Duration holdAfterRevert;

  /// Free memory a further video needs: speech and translation models.
  final int ramPerJob, vramPerJob;

  /// Below this the limit drops, also while videos run.
  final int minFreeRam, minFreeVram;

  /// An extra video must raise throughput by this fraction to stay.
  final double minGain;

  SubtitleBatchAutoScaler({
    this.maxLimit = 4,
    this.window = const Duration(seconds: 90),
    this.warmup = const Duration(seconds: 45),
    this.holdAfterRevert = const Duration(minutes: 10),
    this.ramPerJob = 3 << 30,
    this.vramPerJob = 2 << 30,
    this.minFreeRam = 3 << 29,
    this.minFreeVram = 1 << 28,
    this.minGain = .15,
  });

  int _limit = 1;
  int get limit => _limit;
  SubtitleBatchAutoReason reason = SubtitleBatchAutoReason.measuring;

  /// Media milliseconds per second at the kept limit.
  double? baseline;

  bool _probing = false;
  DateTime? _holdUntil;
  DateTime? _measureFrom;
  int _measureBase = 0;

  /// Starts a fresh measurement, e.g. when the queue starts again.
  void restart(DateTime now, int processedMs) {
    _probing = false;
    baseline = null;
    _measure(now, processedMs, warm: true);
    reason = SubtitleBatchAutoReason.measuring;
  }

  void _measure(DateTime now, int processedMs, {required bool warm}) {
    _measureFrom = warm ? now.add(warmup) : now;
    _measureBase = processedMs;
    _warming = warm;
  }

  bool _warming = false;

  void _lower(DateTime now, int processedMs, SubtitleBatchAutoReason why) {
    _limit = math.max(1, _limit - 1);
    _probing = false;
    _holdUntil = now.add(holdAfterRevert);
    reason = why;
    _measure(now, processedMs, warm: false);
  }

  /// A read timeout or a crashed worker: run fewer videos for a while.
  void onTransientFailure(DateTime now, int processedMs) {
    if (_limit > 1) _lower(now, processedMs, SubtitleBatchAutoReason.failures);
  }

  /// Call periodically. [processedMs] is the media time all jobs have
  /// processed so far (never decreasing); [running] the videos running now;
  /// [pending] whether more are waiting. Returns the limit.
  int update({
    required DateTime now,
    required int processedMs,
    required int running,
    required bool pending,
    SystemResourceSample? resources,
  }) {
    if (_measureFrom == null) {
      _measure(now, processedMs, warm: true);
      return _limit;
    }
    final ram = resources?.ramAvailable;
    final vram = resources?.vramFree;
    if (_limit > 1 &&
        ((ram != null && ram < minFreeRam) ||
            (vram != null && vram < minFreeVram))) {
      _lower(now, processedMs, SubtitleBatchAutoReason.lowMemory);
      return _limit;
    }
    final from = _measureFrom!;
    if (now.isBefore(from)) return _limit;
    if (_warming) {
      // Models are loading until now; their time is not throughput.
      _measure(now, processedMs, warm: false);
      return _limit;
    }
    final elapsed = now.difference(from);
    if (elapsed < window) return _limit;
    final speed =
        (processedMs - _measureBase) / math.max(1, elapsed.inMilliseconds);
    if (_probing) {
      _probing = false;
      final kept = baseline;
      if (kept != null && speed < kept * (1 + minGain)) {
        _lower(now, processedMs, SubtitleBatchAutoReason.noGain);
        return _limit;
      }
      reason = SubtitleBatchAutoReason.faster;
    }
    // Only a full set of slots measures what this limit can do.
    if (running >= _limit) baseline = speed;
    _measure(now, processedMs, warm: false);
    final hold = _holdUntil;
    final roomy =
        (ram == null || ram >= ramPerJob) &&
        (vram == null || vram >= vramPerJob);
    if (_limit < maxLimit &&
        running >= _limit &&
        pending &&
        baseline != null &&
        (hold == null || !now.isBefore(hold))) {
      if (!roomy) {
        reason = SubtitleBatchAutoReason.lowMemory;
        return _limit;
      }
      _limit++;
      _probing = true;
      reason = SubtitleBatchAutoReason.probing;
      _measure(now, processedMs, warm: true);
    }
    return _limit;
  }
}
