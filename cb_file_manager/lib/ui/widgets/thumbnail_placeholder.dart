import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// A decorative, static surface. Waiting and failed thumbnails stay distinct.
class ThumbnailPlaceholder extends StatelessWidget {
  const ThumbnailPlaceholder({
    super.key,
    this.isVideo = false,
    this.failed = false,
    this.visible = true,
  });

  final bool isVideo;
  final bool failed;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible && !failed) return const SizedBox.expand();
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortest = math.min(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final size = shortest.isFinite
              ? (shortest * .35).clamp(12.0, 28.0)
              : 24.0;
          return ColoredBox(
            color: colors.surfaceContainerHighest.withValues(alpha: .35),
            child: Center(
              child: Icon(
                failed
                    ? PhosphorIconsLight.imageBroken
                    : isVideo
                    ? PhosphorIconsLight.videoCamera
                    : PhosphorIconsLight.image,
                size: size,
                color: colors.onSurfaceVariant.withValues(
                  alpha: failed ? .65 : .25,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
