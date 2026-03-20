import 'dart:ui';
import 'package:flutter/material.dart';

/// A utility class to implement Fluent Design System inspired background effects
class FluentBackground extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final bool enableBlur;
  final double opacity;

  /// Creates a fluent design background with blur effect
  ///
  /// [child] is the widget to display on top of the blurred background
  /// [blurAmount] controls the intensity of the blur (default: 15.0)
  /// [backgroundColor] is the color to apply over the blur (default: white with 60% opacity)
  /// [borderRadius] allows customizing the corners (default: none)
  /// [enableBlur] allows turning off blur effect for low-end devices (default: true)
  /// [opacity] controls the opacity of the background color (default: 0.6)
  const FluentBackground({
    Key? key,
    required this.child,
    this.blurAmount = 15.0,
    this.backgroundColor,
    this.borderRadius,
    this.enableBlur = true,
    this.opacity = 0.6,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultColor =
        theme.scaffoldBackgroundColor.withValues(alpha: opacity);
    final bgColor = backgroundColor ?? defaultColor;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        children: [
          // Blur effect
          if (enableBlur)
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurAmount,
                sigmaY: blurAmount,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: borderRadius,
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: borderRadius,
              ),
            ),

          // Child content
          child,
        ],
      ),
    );
  }

  /// Factory method for creating an app bar with fluent design
  static AppBar appBar({
    required BuildContext context,
    required Widget title,
    Widget? leading,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
    double? elevation,
    Color? backgroundColor,
    double blurAmount = 10.0,
    double opacity = 0.5,
  }) {
    final theme = Theme.of(context);
    final defaultColor =
        theme.scaffoldBackgroundColor.withValues(alpha: opacity);
    final bgColor = backgroundColor ?? defaultColor;

    return AppBar(
      leading: leading,
      title: title,
      actions: actions,
      bottom: bottom,
      elevation: elevation ?? 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
          child: Container(
            color: bgColor,
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
    );
  }

  /// Create a fluent design background for cards and containers
  static Widget container({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16.0),
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12.0)),
    double blurAmount = 10.0,
    Color? backgroundColor,
    double opacity = 0.7,
    bool enableBlur = true,
  }) {
    final theme = Theme.of(context);
    final defaultColor = theme.cardColor.withValues(alpha: opacity);
    final bgColor = backgroundColor ?? defaultColor;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: [
          // Blur effect
          if (enableBlur)
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurAmount,
                sigmaY: blurAmount,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: borderRadius,
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: borderRadius,
              ),
            ),

          // Content with padding
          Padding(
            padding: padding,
            child: child,
          ),
        ],
      ),
    );
  }
}
