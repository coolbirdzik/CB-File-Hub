import 'package:flutter/animation.dart';

/// Motion tokens.
///
/// Material's default motion (200–300ms, `easeInOut`) is tuned for phone
/// transitions and feels sluggish on a pointer-driven desktop app where the
/// user expects a click to land instantly. Durations here are short, and the
/// standard curve is asymmetric — fast out of the gate, gently settling — so
/// interactions feel responsive rather than animated.
class CbDurations {
  const CbDurations._();

  /// 80ms — hover/press feedback. Anything slower feels laggy under a cursor.
  static const Duration instant = Duration(milliseconds: 80);

  /// 140ms — the default: local state changes, small reveals, selection.
  static const Duration fast = Duration(milliseconds: 140);

  /// 220ms — panels, popovers, expanding rows.
  static const Duration normal = Duration(milliseconds: 220);

  /// 320ms — full-surface transitions, dialogs, page changes.
  static const Duration slow = Duration(milliseconds: 320);

  /// 1200ms — ambient loops (shimmer, indeterminate progress).
  static const Duration ambient = Duration(milliseconds: 1200);
}

/// Easing curves.
class CbCurves {
  const CbCurves._();

  /// The default for anything entering or changing in place.
  static const Curve standard = Curves.easeOutCubic;

  /// Elements leaving the screen — accelerate away, no lingering.
  static const Curve exit = Curves.easeInCubic;

  /// Two-way transitions that both start and end at rest.
  static const Curve inOut = Curves.easeInOutCubic;

  /// A single, restrained overshoot for affirmative moments only
  /// (an item landing after a drop, a success check). Not for routine UI.
  static const Curve emphasized = Curves.easeOutBack;
}
