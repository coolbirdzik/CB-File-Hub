import 'package:flutter/widgets.dart';

import '../tokens/cb_motion_tokens.dart';

/// Shared motion for short-lived surfaces attached to a control.
class CbPopoverTransition extends StatefulWidget {
  final Animation<double> animation;
  final Offset hiddenOffset;
  final Widget child;

  const CbPopoverTransition({
    super.key,
    required this.animation,
    required this.child,
    this.hiddenOffset = const Offset(0, -4),
  });

  static bool reduceMotionOf(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  /// Material menus do not expose their internal row/size transitions. Keep
  /// that reveal short and front-loaded instead of the default 300ms cascade.
  static const menuStyle = AnimationStyle(
    duration: CbDurations.popoverOpen,
    curve: CbCurves.standard,
    // PopupMenuRoute uses the forward duration for both directions. Reach
    // zero after 70ms of reversing, even though route cleanup takes 120ms.
    reverseCurve: Interval(5 / 12, 1, curve: CbCurves.exit),
  );

  static AnimationStyle menuStyleOf(BuildContext context) =>
      reduceMotionOf(context) ? AnimationStyle.noAnimation : menuStyle;

  @override
  State<CbPopoverTransition> createState() => _CbPopoverTransitionState();
}

class _CbPopoverTransitionState extends State<CbPopoverTransition> {
  late CurvedAnimation _progress;

  @override
  void initState() {
    super.initState();
    _bindAnimation();
  }

  void _bindAnimation() {
    _progress = CurvedAnimation(
      parent: widget.animation,
      curve: CbCurves.standard,
      reverseCurve: CbCurves.exit,
    );
  }

  @override
  void didUpdateWidget(CbPopoverTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _progress.dispose();
      _bindAnimation();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (CbPopoverTransition.reduceMotionOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          opacity: _progress.value,
          child: Transform.translate(
            offset: widget.hiddenOffset * (1 - _progress.value),
            child: child,
          ),
        );
      },
    );
  }
}
