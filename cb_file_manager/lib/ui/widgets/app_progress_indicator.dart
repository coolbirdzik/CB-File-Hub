import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    Key? key,
    this.height = 3.0,
    this.backgroundColor,
    this.valueColor,
    this.borderRadius,
    this.showGlow = true,
    this.value,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveBackgroundColor = backgroundColor ??
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
    Key? key,
    Color? backgroundColor,
    Color? valueColor,
    bool showGlow = false,
  }) : super(
            key: key,
            height: 2.0,
            backgroundColor: backgroundColor,
            valueColor: valueColor,
            showGlow: showGlow);
}

/// Thick version for prominent loading states
class AppProgressIndicatorThick extends AppProgressIndicator {
  const AppProgressIndicatorThick({
    Key? key,
    Color? backgroundColor,
    Color? valueColor,
    bool showGlow = true,
  }) : super(
            key: key,
            height: 4.0,
            backgroundColor: backgroundColor,
            valueColor: valueColor,
            showGlow: showGlow);
}

/// Rounded version with more pronounced curves
class AppProgressIndicatorRounded extends AppProgressIndicator {
  const AppProgressIndicatorRounded({
    Key? key,
    Color? backgroundColor,
    Color? valueColor,
    bool showGlow = true,
  }) : super(
            key: key,
            height: 6.0,
            borderRadius: const BorderRadius.all(Radius.circular(3.0)),
            backgroundColor: backgroundColor,
            valueColor: valueColor,
            showGlow: showGlow);
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
    Key? key,
    this.height = 4.0,
    this.backgroundColor,
    this.valueColor,
    this.showGlow = false,
    this.value,
    this.animated = true,
  }) : super(key: key);

  @override
  State<AppProgressIndicatorBeautiful> createState() =>
      _AppProgressIndicatorBeautifulState();
}

class _AppProgressIndicatorBeautifulState
    extends State<AppProgressIndicatorBeautiful> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

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

    final effectiveBackgroundColor = widget.backgroundColor ??
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.15);

    final effectiveValueColor = widget.valueColor ?? colorScheme.primary;

    return AnimatedBuilder(
      animation:
          widget.animated ? _fadeAnimation : const AlwaysStoppedAnimation(1.0),
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

/// Reusable dot-bounce loader for indeterminate, inline loading states.
///
/// Renders 3 dots that bounce in a staggered wave — a compact "agent is
/// thinking" indicator suitable for AI activity, toolbar states, action
/// buttons, and any inline spot where a bar/circle spinner feels too heavy.
class AppWaveLoader extends StatefulWidget {
  final double size;
  final Color? color;

  const AppWaveLoader({
    Key? key,
    this.size = 24,
    this.color,
  }) : super(key: key);

  @override
  State<AppWaveLoader> createState() => _AppWaveLoaderState();
}

class _AppWaveLoaderState extends State<AppWaveLoader>
    with SingleTickerProviderStateMixin {
  static const _dotCount = 3;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final width = widget.size;
    final height = widget.size;
    final dotSize = math.max(3.0, width / 7.5);
    final gap = math.max(2.0, width / 14);

    return SizedBox(
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_dotCount, (index) {
              final staggerOffset = index / _dotCount;
              final t = (_controller.value + staggerOffset) % 1.0;
              final scale = 0.4 + 0.6 *
                  (math.sin(t * 2 * math.pi - math.pi / 2) + 1) / 2;
              final alpha = 0.3 + 0.7 * scale;

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: gap / 2),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: alpha),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
