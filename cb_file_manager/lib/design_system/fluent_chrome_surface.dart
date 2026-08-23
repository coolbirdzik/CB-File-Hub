import 'dart:ui';

import 'package:flutter/widgets.dart';

/// A Fluent desktop material surface with app-owned tint compositing.
///
/// The blur is deliberately one [BackdropFilter] per surface. A zero blur
/// remains a translucent tint-and-stroke surface for environments where
/// backdrop filtering is unavailable.
class FluentChromeSurface extends StatelessWidget {
  final Color tint;
  final double tintAlpha;
  final double blurSigma;
  final BorderRadius borderRadius;
  final Border? border;
  final Widget child;

  const FluentChromeSurface({
    Key? key,
    required this.tint,
    required this.tintAlpha,
    required this.blurSigma,
    required this.borderRadius,
    this.border,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tintOverlay = DecoratedBox(
      decoration: BoxDecoration(
        color: tint.withValues(alpha: tintAlpha.clamp(0.0, 1.0)),
      ),
    );
    final backdrop = blurSigma > 0
        ? Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: const SizedBox.expand(),
            ),
          )
        : const SizedBox.shrink();

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          backdrop,
          Positioned.fill(child: tintOverlay),
          child,
          if (border != null)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(border: border),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
