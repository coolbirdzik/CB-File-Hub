import 'package:flutter/material.dart';

/// Animated thinking text with a gradient shimmer effect that slides
/// from left to right, giving the appearance of "processing".
class ShimmerThinkingText extends StatefulWidget {
  final String text;

  const ShimmerThinkingText({
    Key? key,
    required this.text,
  }) : super(key: key);

  @override
  State<ShimmerThinkingText> createState() => _ShimmerThinkingTextState();
}

class _ShimmerThinkingTextState extends State<ShimmerThinkingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final highlightColor = theme.colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final shimmerPosition = _controller.value * 2.0 - 0.5;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: [
                (shimmerPosition - 0.3).clamp(0.0, 1.0),
                shimmerPosition.clamp(0.0, 1.0),
                (shimmerPosition + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: Text(
            widget.text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      },
    );
  }
}
