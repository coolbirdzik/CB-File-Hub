import 'package:cb_file_manager/design_system/primitives/cb_loading_text.dart';

import 'package:material_ui/material_ui.dart';

/// Custom progress indicator widget used throughout the app
/// Provides consistent styling and animations
class AppProgressIndicator extends StatelessWidget {
  final double? height;
  final Color? backgroundColor;
  final Color? valueColor;
  final BorderRadius? borderRadius;
  final bool showGlow;
  final double? value; // Add this to support determinate progress

  const AppProgressIndicator({
    super.key,
    this.height = 3.0,
    this.backgroundColor,
    this.valueColor,
    this.borderRadius,
    this.showGlow = true,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveBackgroundColor =
        backgroundColor ??
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    final effectiveValueColor = valueColor ?? colorScheme.primary;
    final effectiveBorderRadius =
        borderRadius ?? BorderRadius.circular(height! / 2);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: effectiveBackgroundColor,
        borderRadius: effectiveBorderRadius,
      ),
      child: ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: Stack(
          children: [
            LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(effectiveValueColor),
              minHeight: height,
            ),
            if (showGlow)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  borderRadius: effectiveBorderRadius,
                  boxShadow: const [],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Thin version for subtle loading states
class AppProgressIndicatorThin extends AppProgressIndicator {
  const AppProgressIndicatorThin({
    super.key,
    super.backgroundColor,
    super.valueColor,
    super.showGlow = false,
  }) : super(height: 2.0);
}

/// Thick version for prominent loading states
class AppProgressIndicatorThick extends AppProgressIndicator {
  const AppProgressIndicatorThick({
    super.key,
    super.backgroundColor,
    super.valueColor,
    super.showGlow,
  }) : super(height: 4.0);
}

/// Rounded version with more pronounced curves
class AppProgressIndicatorRounded extends AppProgressIndicator {
  const AppProgressIndicatorRounded({
    super.key,
    super.backgroundColor,
    super.valueColor,
    super.showGlow,
  }) : super(
         height: 6.0,
         borderRadius: const BorderRadius.all(Radius.circular(3.0)),
       );
}

/// Clean and simple progress bar with subtle animations
class AppProgressIndicatorBeautiful extends StatefulWidget {
  final double height;
  final Color? backgroundColor;
  final Color? valueColor;
  final bool showGlow;
  final double? value;
  final bool animated;

  const AppProgressIndicatorBeautiful({
    super.key,
    this.height = 4.0,
    this.backgroundColor,
    this.valueColor,
    this.showGlow = false,
    this.value,
    this.animated = true,
  });

  @override
  State<AppProgressIndicatorBeautiful> createState() =>
      _AppProgressIndicatorBeautifulState();
}

class _AppProgressIndicatorBeautifulState
    extends State<AppProgressIndicatorBeautiful>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    if (widget.animated) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveBackgroundColor =
        widget.backgroundColor ??
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.15);

    final effectiveValueColor = widget.valueColor ?? colorScheme.primary;

    return AnimatedBuilder(
      animation: widget.animated
          ? _fadeAnimation
          : const AlwaysStoppedAnimation(1.0),
      builder: (context, child) {
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: effectiveBackgroundColor,
            borderRadius: BorderRadius.circular(widget.height / 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.height / 2),
            child: LinearProgressIndicator(
              value: widget.value,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                effectiveValueColor.withValues(
                  alpha: widget.animated ? _fadeAnimation.value : 1.0,
                ),
              ),
              minHeight: widget.height,
            ),
          ),
        );
      },
    );
  }
}

/// Compact loading marker for existing inline activity slots. The text sweep
/// uses the same design-system implementation as full loading labels.
class AppWaveLoader extends StatelessWidget {
  final double size;
  final Color? color;

  const AppWaveLoader({super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CbLoadingText(compact: true, highlightColor: color),
  );
}
