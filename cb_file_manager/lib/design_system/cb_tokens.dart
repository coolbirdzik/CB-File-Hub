import 'package:flutter/material.dart';

import 'tokens/cb_color_tokens.dart';
import 'tokens/cb_elevation_tokens.dart';

/// The design-system handle carried on every [ThemeData].
///
/// Only *colour* lives here, because colour is the only token family that
/// varies between themes. Spacing, radii, type and motion are compile-time
/// constants (`CbSpacing.md`, `CbTypography.body`, …) and are imported
/// directly — no [BuildContext] needed, and no chance of them drifting per
/// screen.
///
/// Read it as `context.cb` (see [CbTokensContext]).
@immutable
class CbTokens extends ThemeExtension<CbTokens> {
  final CbColorTokens colors;
  final Brightness brightness;

  const CbTokens({required this.colors, required this.brightness});

  factory CbTokens.of(Brightness brightness, Color accent) => CbTokens(
        colors: CbColorTokens.of(brightness, accent),
        brightness: brightness,
      );

  bool get isDark => brightness == Brightness.dark;

  // Shadow sets, pre-bound to this theme's shadow colour so call sites do not
  // have to pass it every time.
  List<BoxShadow> get shadowLevel1 =>
      CbElevation.level1(colors.shadow, isDark: isDark);
  List<BoxShadow> get shadowLevel2 =>
      CbElevation.level2(colors.shadow, isDark: isDark);
  List<BoxShadow> get shadowLevel3 =>
      CbElevation.level3(colors.shadow, isDark: isDark);
  List<BoxShadow> get shadowLevel4 =>
      CbElevation.level4(colors.shadow, isDark: isDark);

  @override
  CbTokens copyWith({CbColorTokens? colors, Brightness? brightness}) =>
      CbTokens(
        colors: colors ?? this.colors,
        brightness: brightness ?? this.brightness,
      );

  @override
  CbTokens lerp(ThemeExtension<CbTokens>? other, double t) {
    if (other is! CbTokens) return this;
    return CbTokens(
      colors: _lerpColors(colors, other.colors, t),
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }

  static Color _c(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  static CbColorTokens _lerpColors(CbColorTokens a, CbColorTokens b, double t) {
    return CbColorTokens(
      canvas: _c(a.canvas, b.canvas, t),
      surface: _c(a.surface, b.surface, t),
      surfaceRaised: _c(a.surfaceRaised, b.surfaceRaised, t),
      surfaceOverlay: _c(a.surfaceOverlay, b.surfaceOverlay, t),
      surfaceSunken: _c(a.surfaceSunken, b.surfaceSunken, t),
      surfaceHover: _c(a.surfaceHover, b.surfaceHover, t),
      surfacePressed: _c(a.surfacePressed, b.surfacePressed, t),
      surfaceSelected: _c(a.surfaceSelected, b.surfaceSelected, t),
      textPrimary: _c(a.textPrimary, b.textPrimary, t),
      textSecondary: _c(a.textSecondary, b.textSecondary, t),
      textTertiary: _c(a.textTertiary, b.textTertiary, t),
      textDisabled: _c(a.textDisabled, b.textDisabled, t),
      textInverse: _c(a.textInverse, b.textInverse, t),
      icon: _c(a.icon, b.icon, t),
      iconSubtle: _c(a.iconSubtle, b.iconSubtle, t),
      stroke: _c(a.stroke, b.stroke, t),
      strokeSubtle: _c(a.strokeSubtle, b.strokeSubtle, t),
      strokeStrong: _c(a.strokeStrong, b.strokeStrong, t),
      focusRing: _c(a.focusRing, b.focusRing, t),
      shadow: _c(a.shadow, b.shadow, t),
      scrim: _c(a.scrim, b.scrim, t),
      accent: CbAccentRamp(
        tint: _c(a.accent.tint, b.accent.tint, t),
        tintStrong: _c(a.accent.tintStrong, b.accent.tintStrong, t),
        border: _c(a.accent.border, b.accent.border, t),
        base: _c(a.accent.base, b.accent.base, t),
        hover: _c(a.accent.hover, b.accent.hover, t),
        pressed: _c(a.accent.pressed, b.accent.pressed, t),
        onBase: _c(a.accent.onBase, b.accent.onBase, t),
        text: _c(a.accent.text, b.accent.text, t),
      ),
      status: CbStatusPalette(
        success: _c(a.status.success, b.status.success, t),
        successSurface: _c(a.status.successSurface, b.status.successSurface, t),
        warning: _c(a.status.warning, b.status.warning, t),
        warningSurface: _c(a.status.warningSurface, b.status.warningSurface, t),
        danger: _c(a.status.danger, b.status.danger, t),
        dangerHover: _c(a.status.dangerHover, b.status.dangerHover, t),
        dangerSurface: _c(a.status.dangerSurface, b.status.dangerSurface, t),
        info: _c(a.status.info, b.status.info, t),
        infoSurface: _c(a.status.infoSurface, b.status.infoSurface, t),
      ),
    );
  }

  /// Fallback used when a widget is built outside a themed subtree — notably
  /// in widget tests that pump a bare `MaterialApp`. Returning a usable set is
  /// better than throwing, since a missing extension is a wiring bug rather
  /// than something a widget can recover from.
  static final CbTokens fallback =
      CbTokens.of(Brightness.light, const Color(0xFF0078D4));
}

/// `context.cb` — the shorthand every widget uses to reach the tokens.
extension CbTokensContext on BuildContext {
  CbTokens get cb => Theme.of(this).extension<CbTokens>() ?? CbTokens.fallback;

  /// `context.cbColors` for the common case of only needing colour.
  CbColorTokens get cbColors => cb.colors;
}

/// Same lookup from a [ThemeData] you already hold, for code that builds
/// themes or styles outside the widget tree.
extension CbTokensTheme on ThemeData {
  CbTokens get cb => extension<CbTokens>() ?? CbTokens.fallback;
}
