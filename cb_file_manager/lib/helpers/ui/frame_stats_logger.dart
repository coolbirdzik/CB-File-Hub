import 'dart:io';

import 'package:flutter/scheduler.dart';

/// Prints frame build/raster timings every few seconds when the process runs
/// with `CB_FRAME_STATS=1`, so scrolling and loading can be compared between
/// renderers or builds without attaching DevTools.
abstract final class FrameStatsLogger {
  static const _window = Duration(seconds: 5);
  static const _budgetUs = 16667;
  static bool _started = false;
  static final List<FrameTiming> _pending = <FrameTiming>[];
  static DateTime _windowStart = DateTime.now();

  static bool get enabled => Platform.environment['CB_FRAME_STATS'] == '1';

  static void startIfEnabled() {
    if (_started || !enabled) return;
    _started = true;
    _windowStart = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    _pending.addAll(timings);
    final now = DateTime.now();
    if (now.difference(_windowStart) < _window) return;
    _windowStart = now;
    if (_pending.isEmpty) return;
    final build = _pending.map((t) => t.buildDuration.inMicroseconds).toList()
      ..sort();
    final raster = _pending.map((t) => t.rasterDuration.inMicroseconds).toList()
      ..sort();
    final janky = _pending
        .where(
          (t) =>
              t.buildDuration.inMicroseconds > _budgetUs ||
              t.rasterDuration.inMicroseconds > _budgetUs,
        )
        .length;
    print(
      'FrameStats n=${_pending.length} janky=$janky '
      'build_ms p50=${_ms(build, 50)} p90=${_ms(build, 90)} '
      'p99=${_ms(build, 99)} max=${_ms(build, 100)} '
      'raster_ms p50=${_ms(raster, 50)} p90=${_ms(raster, 90)} '
      'p99=${_ms(raster, 99)} max=${_ms(raster, 100)}',
    );
    _pending.clear();
  }

  static String _ms(List<int> sortedUs, int percentile) {
    final index = ((sortedUs.length - 1) * percentile / 100).round();
    return (sortedUs[index] / 1000).toStringAsFixed(1);
  }
}
