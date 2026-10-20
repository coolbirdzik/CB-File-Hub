import 'package:flutter/widgets.dart';

import '../tokens/cb_motion_tokens.dart';

/// Retains a panel until its exit finishes, including interrupted transitions.
class CbPanelReveal extends StatefulWidget {
  final bool visible;
  final Widget? child;
  final Offset hiddenOffset;
  final Alignment alignment;
  final bool reserveWidth;
  final VoidCallback? onDismissed;

  const CbPanelReveal({
    super.key,
    required this.visible,
    required this.child,
    this.hiddenOffset = const Offset(0, -0.04),
    this.alignment = Alignment.topRight,
    this.reserveWidth = false,
    this.onDismissed,
  });

  @override
  State<CbPanelReveal> createState() => _CbPanelRevealState();
}

class _CbPanelRevealState extends State<CbPanelReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CbDurations.normal,
    reverseDuration: CbDurations.fast,
  )..addStatusListener(_onStatusChanged);
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: CbCurves.standard,
    reverseCurve: CbCurves.exit,
  );
  Widget? _retainedChild;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _retainedChild = widget.child;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    _animate();
  }

  @override
  void didUpdateWidget(CbPanelReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) _retainedChild = widget.child;
    if (widget.visible != oldWidget.visible) _animate();
  }

  void _animate() {
    if (_reduceMotion) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || widget.visible) return;
    // Completion can run while the parent is rebuilding in reduced motion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.visible || !_controller.isDismissed) return;
      setState(() => _retainedChild = null);
      widget.onDismissed?.call();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_retainedChild == null) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !widget.visible,
      child: ExcludeFocus(
        excluding: !widget.visible,
        child: ExcludeSemantics(
          excluding: !widget.visible,
          child: AnimatedBuilder(
            animation: _progress,
            child: _retainedChild,
            builder: (context, child) {
              Widget panel = FadeTransition(
                opacity: _progress,
                child: FractionalTranslation(
                  translation: widget.hiddenOffset * (1 - _progress.value),
                  child: child,
                ),
              );
              if (widget.reserveWidth) {
                panel = ClipRect(
                  child: Align(
                    alignment: widget.alignment,
                    widthFactor: _progress.value,
                    child: panel,
                  ),
                );
              } else {
                panel = Transform.scale(
                  scale: 0.97 + 0.03 * _progress.value,
                  alignment: widget.alignment,
                  child: panel,
                );
              }
              return panel;
            },
          ),
        ),
      ),
    );
  }
}
