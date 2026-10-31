import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// One translucency ramp for the Fluent host and Material compatibility UI.
/// Stored strength remains 0..2; the appearance control displays it as 0..100%.
class DesktopAcrylicTheme extends ThemeExtension<DesktopAcrylicTheme> {
  final double strength;
  final Brightness brightness;
  final bool dynamicBackdrop;

  DesktopAcrylicTheme({
    required double strength,
    required this.brightness,
    required this.dynamicBackdrop,
  }) : strength = strength.isFinite ? strength.clamp(0.0, 2.0) : 1.0;

  bool get _dark => brightness == Brightness.dark;
  double _opacity(double clearest) => lerpDouble(1, clearest, strength / 2)!;

  double get canvasOpacity => _opacity(
    _dark ? (dynamicBackdrop ? 0.24 : 0.34) : (dynamicBackdrop ? 0.62 : 0.92),
  );
  double get chromeOpacity => _opacity(
    _dark ? (dynamicBackdrop ? 0.36 : 0.46) : (dynamicBackdrop ? 0.70 : 0.93),
  );
  double get drawerOpacity => _opacity(
    _dark ? (dynamicBackdrop ? 0.50 : 0.60) : (dynamicBackdrop ? 0.80 : 0.96),
  );
  double get surfaceOpacity => _opacity(
    _dark ? (dynamicBackdrop ? 0.30 : 0.40) : (dynamicBackdrop ? 0.72 : 0.90),
  );
  double get containerOpacity => _opacity(
    _dark ? (dynamicBackdrop ? 0.28 : 0.36) : (dynamicBackdrop ? 0.68 : 0.88),
  );
  double get lowContainerOpacity => _opacity(
    _dark ? (dynamicBackdrop ? 0.24 : 0.32) : (dynamicBackdrop ? 0.62 : 0.86),
  );
  double get lowestContainerOpacity => _opacity(
    _dark ? (dynamicBackdrop ? 0.20 : 0.28) : (dynamicBackdrop ? 0.56 : 0.84),
  );
  double get blurSigma => strength == 0 ? 0 : 18;

  @override
  DesktopAcrylicTheme copyWith({
    double? strength,
    Brightness? brightness,
    bool? dynamicBackdrop,
  }) => DesktopAcrylicTheme(
    strength: strength ?? this.strength,
    brightness: brightness ?? this.brightness,
    dynamicBackdrop: dynamicBackdrop ?? this.dynamicBackdrop,
  );

  @override
  DesktopAcrylicTheme lerp(covariant DesktopAcrylicTheme? other, double t) {
    if (other == null) return this;
    return DesktopAcrylicTheme(
      strength: lerpDouble(strength, other.strength, t)!,
      brightness: t < 0.5 ? brightness : other.brightness,
      dynamicBackdrop: t < 0.5 ? dynamicBackdrop : other.dynamicBackdrop,
    );
  }
}
