import 'package:cb_file_manager/design_system/primitives/cb_loading_text.dart';
import 'package:material_ui/material_ui.dart';

/// Activity stays visible even while a single large item is being processed.
class OperationActivityIcon extends StatelessWidget {
  const OperationActivityIcon({
    super.key,
    required this.running,
    required this.icon,
    required this.color,
    this.size = 24,
  });

  final bool running;
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: running && !reduceMotion
              ? Padding(
                  key: const ValueKey('running'),
                  padding: const EdgeInsets.all(2),
                  child: CbLoadingText(compact: true, highlightColor: color),
                )
              : Icon(icon, key: ValueKey(icon), size: size, color: color),
        ),
      ),
    );
  }
}

/// Interpolates actual progress; a null value retains indeterminate activity.
class OperationProgressBar extends StatelessWidget {
  const OperationProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.backgroundColor,
    this.height = 7,
  });

  final double? value;
  final Color color;
  final Color? backgroundColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final target = value?.clamp(0.0, 1.0);
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: target ?? 0, end: target ?? 0),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        builder: (context, fraction, _) => LinearProgressIndicator(
          value: target == null ? (reduceMotion ? 0 : null) : fraction,
          minHeight: height,
          borderRadius: BorderRadius.circular(99),
          color: color,
          backgroundColor: backgroundColor,
        ),
      ),
    );
  }
}
