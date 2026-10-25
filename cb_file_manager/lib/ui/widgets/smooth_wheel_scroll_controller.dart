import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;
import 'package:flutter/widgets.dart';

/// Animates discrete mouse-wheel notches; touch drags and precise small wheel
/// deltas continue through Flutter's normal scrolling implementation.
class SmoothWheelScrollController extends ScrollController {
  SmoothWheelScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.enabled = true,
  });

  final bool enabled;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SmoothWheelPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
    enabled: enabled,
  );
}

class _SmoothWheelPosition extends ScrollPositionWithSingleContext {
  _SmoothWheelPosition({
    required super.physics,
    required super.context,
    required super.initialPixels,
    required super.keepScrollOffset,
    required super.oldPosition,
    super.debugLabel,
    required this.enabled,
  });

  final bool enabled;

  @override
  void pointerScroll(double delta) {
    final reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context.storageContext) ?? false;
    if (!enabled ||
        reducedMotion ||
        delta.abs() < 40 ||
        !hasContentDimensions) {
      super.pointerScroll(delta);
      return;
    }

    final current = activity;
    final wheel = current is _WheelScrollActivity ? current : null;
    final remaining = wheel == null ? 0.0 : wheel.target - pixels;
    // Reverse immediately instead of finishing the previous notch first.
    final base = remaining.sign == delta.sign ? wheel!.target : pixels;
    final target = (base + delta).clamp(minScrollExtent, maxScrollExtent);
    if (target == pixels) {
      super.pointerScroll(0);
      return;
    }

    updateUserScrollDirection(
      delta < 0 ? ScrollDirection.forward : ScrollDirection.reverse,
    );
    if (wheel != null) {
      wheel.retarget(from: pixels, to: target);
    } else {
      beginActivity(
        _WheelScrollActivity(this, context.vsync, from: pixels, to: target),
      );
    }
  }
}

/// A single ticker survives the whole wheel burst. Restarting animateTo for
/// each packet made its first tick repeat the previous offset, losing one
/// moving frame per packet (about 25 frames/s for a 40 ms wheel interval).
class _WheelScrollActivity extends ScrollActivity {
  _WheelScrollActivity(
    super.delegate,
    TickerProvider vsync, {
    required double from,
    required double to,
  }) : _from = from,
       _lastValue = from,
       target = to {
    _ticker = vsync.createTicker(_tick)..start();
  }

  static const _durationMicros = 120000;
  late final Ticker _ticker;
  double _from;
  double _lastValue;
  double _velocity = 0;
  double target;
  Duration _elapsed = Duration.zero;
  Duration _origin = Duration.zero;
  double _progress = 0;

  void retarget({required double from, required double to}) {
    _from = from;
    _lastValue = from;
    target = to;
    _origin = _elapsed;
    _progress = 0;
  }

  void _tick(Duration elapsed) {
    final deltaMicros = (elapsed - _elapsed).inMicroseconds;
    _elapsed = elapsed;
    _progress = ((elapsed - _origin).inMicroseconds / _durationMicros).clamp(
      0.0,
      1.0,
    );
    final value =
        _from + (target - _from) * Curves.easeOutCubic.transform(_progress);
    if (deltaMicros > 0) {
      _velocity = (value - _lastValue) * 1000000 / deltaMicros;
    }
    _lastValue = value;
    if (delegate.setPixels(value).abs() > precisionErrorTolerance) {
      delegate.goIdle();
      return;
    }
    if (_progress >= 1) delegate.goBallistic(0);
  }

  @override
  bool get shouldIgnorePointer => true;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _velocity;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
