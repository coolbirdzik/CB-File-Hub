import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Toast notification theme — all dimensions and opacity values centralised
/// so AppToast stays in sync with the active theme without duplicating magic
/// numbers across the codebase.
class AppToastTheme extends ThemeExtension<AppToastTheme> {
  // Icon container
  final double iconBoxSize;
  final double iconSize;
  final double iconBoxRadius;

  // Container
  final double containerRadius;
  final double hPadding;
  final double vPadding;
  final double maxWidth;

  // Blur
  final double blurSigmaDesktopLight;
  final double blurSigmaDesktopDark;
  final double blurSigmaMobile;

  // Colours / opacity
  final double surfaceOpacity;
  final double borderOpacity;
  final double shadowOpacityLight;
  final double shadowOpacityDark;
  final double iconAccentOpacity;

  // Durations
  final Duration durationSuccess;
  final Duration durationInfo;
  final Duration durationWarning;
  final Duration durationError;

  const AppToastTheme({
    required this.iconBoxSize,
    required this.iconSize,
    required this.iconBoxRadius,
    required this.containerRadius,
    required this.hPadding,
    required this.vPadding,
    required this.maxWidth,
    required this.blurSigmaDesktopLight,
    required this.blurSigmaDesktopDark,
    required this.blurSigmaMobile,
    required this.surfaceOpacity,
    required this.borderOpacity,
    required this.shadowOpacityLight,
    required this.shadowOpacityDark,
    required this.iconAccentOpacity,
    required this.durationSuccess,
    required this.durationInfo,
    required this.durationWarning,
    required this.durationError,
  });

  @override
  AppToastTheme copyWith({
    double? iconBoxSize,
    double? iconSize,
    double? iconBoxRadius,
    double? containerRadius,
    double? hPadding,
    double? vPadding,
    double? maxWidth,
    double? blurSigmaDesktopLight,
    double? blurSigmaDesktopDark,
    double? blurSigmaMobile,
    double? surfaceOpacity,
    double? borderOpacity,
    double? shadowOpacityLight,
    double? shadowOpacityDark,
    double? iconAccentOpacity,
    Duration? durationSuccess,
    Duration? durationInfo,
    Duration? durationWarning,
    Duration? durationError,
  }) =>
      AppToastTheme(
        iconBoxSize: iconBoxSize ?? this.iconBoxSize,
        iconSize: iconSize ?? this.iconSize,
        iconBoxRadius: iconBoxRadius ?? this.iconBoxRadius,
        containerRadius: containerRadius ?? this.containerRadius,
        hPadding: hPadding ?? this.hPadding,
        vPadding: vPadding ?? this.vPadding,
        maxWidth: maxWidth ?? this.maxWidth,
        blurSigmaDesktopLight:
            blurSigmaDesktopLight ?? this.blurSigmaDesktopLight,
        blurSigmaDesktopDark: blurSigmaDesktopDark ?? this.blurSigmaDesktopDark,
        blurSigmaMobile: blurSigmaMobile ?? this.blurSigmaMobile,
        surfaceOpacity: surfaceOpacity ?? this.surfaceOpacity,
        borderOpacity: borderOpacity ?? this.borderOpacity,
        shadowOpacityLight: shadowOpacityLight ?? this.shadowOpacityLight,
        shadowOpacityDark: shadowOpacityDark ?? this.shadowOpacityDark,
        iconAccentOpacity: iconAccentOpacity ?? this.iconAccentOpacity,
        durationSuccess: durationSuccess ?? this.durationSuccess,
        durationInfo: durationInfo ?? this.durationInfo,
        durationWarning: durationWarning ?? this.durationWarning,
        durationError: durationError ?? this.durationError,
      );

  @override
  AppToastTheme lerp(ThemeExtension<AppToastTheme>? other, double t) {
    if (other is! AppToastTheme) return this;
    return AppToastTheme(
      iconBoxSize: lerpDouble(iconBoxSize, other.iconBoxSize, t)!,
      iconSize: lerpDouble(iconSize, other.iconSize, t)!,
      iconBoxRadius: lerpDouble(iconBoxRadius, other.iconBoxRadius, t)!,
      containerRadius: lerpDouble(containerRadius, other.containerRadius, t)!,
      hPadding: lerpDouble(hPadding, other.hPadding, t)!,
      vPadding: lerpDouble(vPadding, other.vPadding, t)!,
      maxWidth: lerpDouble(maxWidth, other.maxWidth, t)!,
      blurSigmaDesktopLight:
          lerpDouble(blurSigmaDesktopLight, other.blurSigmaDesktopLight, t)!,
      blurSigmaDesktopDark:
          lerpDouble(blurSigmaDesktopDark, other.blurSigmaDesktopDark, t)!,
      blurSigmaMobile: lerpDouble(blurSigmaMobile, other.blurSigmaMobile, t)!,
      surfaceOpacity: lerpDouble(surfaceOpacity, other.surfaceOpacity, t)!,
      borderOpacity: lerpDouble(borderOpacity, other.borderOpacity, t)!,
      shadowOpacityLight:
          lerpDouble(shadowOpacityLight, other.shadowOpacityLight, t)!,
      shadowOpacityDark:
          lerpDouble(shadowOpacityDark, other.shadowOpacityDark, t)!,
      iconAccentOpacity:
          lerpDouble(iconAccentOpacity, other.iconAccentOpacity, t)!,
      durationSuccess: Duration(
        milliseconds: lerpDouble(durationSuccess.inMilliseconds,
                other.durationSuccess.inMilliseconds, t)!
            .round(),
      ),
      durationInfo: Duration(
        milliseconds: lerpDouble(durationInfo.inMilliseconds,
                other.durationInfo.inMilliseconds, t)!
            .round(),
      ),
      durationWarning: Duration(
        milliseconds: lerpDouble(durationWarning.inMilliseconds,
                other.durationWarning.inMilliseconds, t)!
            .round(),
      ),
      durationError: Duration(
        milliseconds: lerpDouble(durationError.inMilliseconds,
                other.durationError.inMilliseconds, t)!
            .round(),
      ),
    );
  }
}
