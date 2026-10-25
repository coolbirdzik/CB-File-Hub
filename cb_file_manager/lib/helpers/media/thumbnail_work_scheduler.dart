import 'dart:async';

import 'package:cb_file_manager/ui/utils/scroll_velocity_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Bounds thumbnail metadata work and starts it after scrolling stops.
///
/// Owners cancel queued work when their tiles leave the grid. Already-running
/// I/O is allowed to finish; callers still check their widget/path lifetime.
class ThumbnailWorkScheduler {
  ThumbnailWorkScheduler({this.maxConcurrent = 2, this.maxStartsPerFrame = 2})
    : assert(maxConcurrent > 0),
      assert(maxStartsPerFrame > 0) {
    ScrollVelocityNotifier.instance.addListener(_scrollChanged);
  }

  static final instance = ThumbnailWorkScheduler();
  final int maxConcurrent;
  final int maxStartsPerFrame;
  final _pending = <Object, Future<void> Function()>{};
  final _active = <Object>{};
  bool _scheduled = false;
  bool _disposed = false;

  void schedule(Object owner, Future<void> Function() work) {
    if (_disposed) return;
    _pending[owner] = work;
    _scheduleFrame();
  }

  void cancel(Object owner) => _pending.remove(owner);

  void _scrollChanged() => _scheduleFrame();

  void _scheduleFrame() {
    if (_disposed ||
        _scheduled ||
        _pending.isEmpty ||
        _active.length >= maxConcurrent ||
        ScrollVelocityNotifier.instance.isScrolling) {
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _drain();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _drain() {
    if (_disposed || ScrollVelocityNotifier.instance.isScrolling) return;
    var started = 0;
    for (final owner in _pending.keys.toList(growable: false)) {
      if (_active.length >= maxConcurrent || started >= maxStartsPerFrame) {
        break;
      }
      if (_active.contains(owner)) continue;
      final work = _pending.remove(owner)!;
      _active.add(owner);
      started++;
      unawaited(_run(owner, work));
    }
    if (started > 0) _scheduleFrame();
  }

  Future<void> _run(Object owner, Future<void> Function() work) async {
    try {
      await work();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'thumbnail metadata scheduler',
        ),
      );
    } finally {
      _active.remove(owner);
      _scheduleFrame();
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    ScrollVelocityNotifier.instance.removeListener(_scrollChanged);
  }
}
