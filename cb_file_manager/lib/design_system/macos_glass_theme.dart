import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Separate translucency and blur, with readable tint floors for macOS.
/// Native backgrounds are unknown, so text contrast is checked against both
/// black and white before a surface can reveal them.
class MacosGlassTheme extends ThemeExtension<MacosGlassTheme> {
  final double strength;
  final double blurStrength;
  final Brightness brightness;

  MacosGlassTheme({
    required double strength,
    double blurStrength = 1,
    required this.brightness,
  }) : strength = normalizeStrength(strength),
       blurStrength = normalizeStrength(blurStrength);

  static double normalizeStrength(double value) =>
      value.isFinite ? value.clamp(0.0, 2.0).toDouble() : 1.0;

  double get _amount => strength / 2;
  bool get _dark => brightness == Brightness.dark;
  double _opacity(double clear) => lerpDouble(1, clear, _amount)!;

  double get canvasOpacity => _opacity(_dark ? 0.78 : 0.82);
  double get surfaceOpacity => _opacity(0.90);
  double get containerOpacity => _opacity(0.88);
  double get lowContainerOpacity => _opacity(0.86);
  double get lowestContainerOpacity => _opacity(0.84);
  double get chromeOpacity => _opacity(_dark ? 0.64 : 0.72);
  double get blurSigma => strength == 0 ? 0 : 28 * blurStrength;
  double get wallpaperTintOpacity => _opacity(_dark ? 0.24 : 0.32);

  /// Adds only as much tint as the active text palette requires. Blur cannot
  /// supply contrast against a large bright/dark patch in a wallpaper.
  Color readableSurface(
    Color tint, {
    required double opacity,
    required Iterable<Color> foregrounds,
  }) {
    final solid = tint.withValues(alpha: 1);
    final inks = foregrounds.toList();
    double contrast(Color foreground, Color background) {
      final ink = Color.alphaBlend(foreground, background);
      final a = ink.computeLuminance();
      final b = background.computeLuminance();
      return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
    }

    // Preserve the authored palette if it deliberately uses a muted tone.
    // Transparency must never lower it below its opaque contrast or 4.5:1.
    final targets = [
      for (final ink in inks) contrast(ink, solid).clamp(1.0, 4.5),
    ];
    bool readable(double alpha) {
      final surface = solid.withValues(alpha: alpha);
      for (final backdrop in [Colors.black, Colors.white]) {
        final background = Color.alphaBlend(surface, backdrop);
        for (var i = 0; i < inks.length; i++) {
          if (contrast(inks[i], background) + 0.000001 < targets[i]) {
            return false;
          }
        }
      }
      return true;
    }

    var lower = opacity.clamp(0.0, 1.0);
    if (readable(lower)) return solid.withValues(alpha: lower);
    var upper = 1.0;
    for (var i = 0; i < 12; i++) {
      final middle = (lower + upper) / 2;
      if (readable(middle)) {
        upper = middle;
      } else {
        lower = middle;
      }
    }
    // Leave one alpha step of headroom for 8-bit rasterization.
    return solid.withValues(alpha: (upper + 1 / 255).clamp(0.0, 1.0));
  }

  @override
  MacosGlassTheme copyWith({
    double? strength,
    double? blurStrength,
    Brightness? brightness,
  }) => MacosGlassTheme(
    strength: strength ?? this.strength,
    blurStrength: blurStrength ?? this.blurStrength,
    brightness: brightness ?? this.brightness,
  );

  @override
  MacosGlassTheme lerp(covariant MacosGlassTheme? other, double t) {
    if (other == null) return this;
    return MacosGlassTheme(
      strength: lerpDouble(strength, other.strength, t)!,
      blurStrength: lerpDouble(blurStrength, other.blurStrength, t)!,
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}
