import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'macos_glass_theme.dart';

/// Shared desktop chrome, composited with the Flutter controls above it.
///
/// macOS supplies a native behind-window material, while these surfaces blur
/// Flutter content. Decorative AppKit platform views must not be embedded here:
/// their engine-owned containers participate in native hit testing even when
/// the material's own hitTest returns nil.
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
    final isMacOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    final reduceTransparency = MediaQuery.highContrastOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glass = isMacOS
        ? Theme.of(context).extension<MacosGlassTheme>() ??
              MacosGlassTheme(
                strength: 1,
                brightness: Theme.of(context).brightness,
              )
        : null;
    final effectiveBlur = glass?.blurSigma ?? blurSigma;
    final surfaceAlpha = reduceTransparency
        ? 1.0
        : glass?.chromeOpacity ?? tintAlpha.clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceTint =
        glass?.readableSurface(
          tint,
          opacity: surfaceAlpha,
          foregrounds: [colorScheme.onSurface, colorScheme.onSurfaceVariant],
        ) ??
        tint.withValues(alpha: surfaceAlpha);
    final tintOverlay = DecoratedBox(
      decoration: BoxDecoration(color: surfaceTint),
    );
    final backdrop = effectiveBlur > 0 && !reduceTransparency
        ? Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: effectiveBlur,
                sigmaY: effectiveBlur,
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
          if (isMacOS)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.08 : 0.4,
                      ),
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
