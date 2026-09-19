import 'dart:ui';

import 'package:flutter/widgets.dart';

/// A Fluent desktop material surface with app-owned tint compositing.
///
/// The blur is deliberately one [BackdropFilter] per surface. A zero blur
/// remains a translucent tint surface for environments where backdrop
/// filtering is unavailable. There is deliberately no border: chrome is
/// separated from the canvas by its tint alone (flat design).
class FluentChromeSurface extends StatelessWidget {
  final Color tint;
  final double tintAlpha;
  final double blurSigma;
  final BorderRadius borderRadius;
  final Widget child;

  const FluentChromeSurface({
    super.key,
    required this.tint,
    required this.tintAlpha,
    required this.blurSigma,
    required this.borderRadius,
    required this.child,
  });

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
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
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
        ],
      ),
    );
  }
}
