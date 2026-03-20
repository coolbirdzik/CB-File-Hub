import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

import '../providers/theme_provider.dart';
import 'theme_config.dart';
import 'fluent_theme_config.dart';

export 'app_constants.dart';
export 'app_initializer.dart';

/// Resolves Material themes with optional desktop acrylic bridge overlay.
///
/// The "acrylic bridge" maps Material surface colors to transparent layers
/// that let the native Windows acrylic/mica backdrop show through.
class AppThemeResolver {
  // ─── Brightness-aware theme resolution ──────────────────────────────────

  static ThemeData resolveMaterialLightTheme(ThemeProvider provider) {
    return provider.currentTheme == AppThemeType.dark
        ? ThemeConfig.getLightTheme(accentColor: provider.currentAccentColor)
        : provider.themeData;
  }

  static ThemeData resolveMaterialDarkTheme(ThemeProvider provider) {
    return provider.currentTheme == AppThemeType.dark
        ? provider.themeData
        : ThemeConfig.getDarkTheme(accentColor: provider.currentAccentColor);
  }

  static fluent.FluentThemeData resolveFluentLightTheme(
      ThemeProvider provider) {
    return provider.currentTheme == AppThemeType.dark
        ? FluentThemeConfig.getTheme(
            AppThemeType.light,
            accentColor: provider.currentAccentColor,
            acrylicStrength: provider.desktopAcrylicStrength,
          )
        : provider.fluentThemeData;
  }

  static fluent.FluentThemeData resolveFluentDarkTheme(ThemeProvider provider) {
    return provider.currentTheme == AppThemeType.dark
        ? provider.fluentThemeData
        : FluentThemeConfig.getTheme(
            AppThemeType.dark,
            accentColor: provider.currentAccentColor,
            acrylicStrength: provider.desktopAcrylicStrength,
          );
  }

  // ─── Native backdrop dark-mode detection ─────────────────────────────────

  static bool resolveNativeBackdropDarkMode(
      ThemeProvider provider, Brightness platformBrightness) {
    if (provider.themeMode == ThemeMode.dark) return true;
    if (provider.themeMode == ThemeMode.light) {
      return provider.currentTheme == AppThemeType.dark;
    }
    return platformBrightness == Brightness.dark;
  }

  // ─── Acrylic bridge ──────────────────────────────────────────────────────

  /// Creates a Material theme that blends with native Windows acrylic.
  ///
  /// Each surface layer is given a transparent fill whose opacity scales
  /// with [acrylicStrength] (0 = solid, 2 = fully glass).
  static ThemeData createAcrylicBridgeTheme({
    required ThemeData baseTheme,
    required Brightness brightness,
    required double acrylicStrength,
  }) {
    final double normalizedStrength = acrylicStrength.clamp(0.0, 2.0);
    final bool isLight = brightness == Brightness.light;
    const Color fluentLightBackground2 = Color(0xFFF3F4F7);
    const Color fluentLightBackground3 = Color(0xFFFFFFFF);

    double opacityFor(double solidAtMin, double glassAtMax) {
      return solidAtMin + (glassAtMax - solidAtMin) * normalizedStrength;
    }

    double scaffoldOpacity() =>
        isLight ? opacityFor(0.99, 0.92) : opacityFor(0.90, 0.34);

    double appBarOpacity() =>
        isLight ? opacityFor(0.99, 0.93) : opacityFor(0.94, 0.46);

    double surfaceOpacity() =>
        isLight ? opacityFor(0.99, 0.90) : opacityFor(0.88, 0.40);

    double containerOpacity() =>
        isLight ? opacityFor(0.98, 0.88) : opacityFor(0.84, 0.36);

    double lowContainerOpacity() =>
        isLight ? opacityFor(0.98, 0.86) : opacityFor(0.80, 0.32);

    double lowestContainerOpacity() =>
        isLight ? opacityFor(0.97, 0.84) : opacityFor(0.76, 0.28);

    final colorScheme = baseTheme.colorScheme;
    final Color lightSurfaceBase =
        isLight ? fluentLightBackground3 : colorScheme.surface;
    final Color lightContainerBase =
        isLight ? fluentLightBackground2 : colorScheme.surfaceContainer;

    final bridged = colorScheme.copyWith(
      surface: lightSurfaceBase.withValues(alpha: surfaceOpacity()),
      surfaceBright:
          (isLight ? fluentLightBackground3 : colorScheme.surfaceBright)
              .withValues(alpha: surfaceOpacity()),
      surfaceDim: (isLight ? fluentLightBackground2 : colorScheme.surfaceDim)
          .withValues(alpha: surfaceOpacity()),
      surfaceContainer:
          lightContainerBase.withValues(alpha: containerOpacity()),
      surfaceContainerHigh:
          lightContainerBase.withValues(alpha: containerOpacity()),
      surfaceContainerHighest:
          lightContainerBase.withValues(alpha: containerOpacity()),
      surfaceContainerLow:
          lightSurfaceBase.withValues(alpha: lowContainerOpacity()),
      surfaceContainerLowest:
          lightSurfaceBase.withValues(alpha: lowestContainerOpacity()),
      inverseSurface:
          colorScheme.inverseSurface.withValues(alpha: surfaceOpacity()),
      surfaceTint: Colors.transparent,
    );

    final cardColor = lightContainerBase.withValues(alpha: containerOpacity());
    // Dialog: always solid for readability
    final dialogColor = lightContainerBase;
    // Menu: always solid like dialog — no transparency
    final menuColor = lightContainerBase;

    return baseTheme.copyWith(
      colorScheme: bridged,
      scaffoldBackgroundColor: baseTheme.scaffoldBackgroundColor
          .withValues(alpha: scaffoldOpacity()),
      canvasColor: baseTheme.canvasColor.withValues(alpha: scaffoldOpacity()),
      cardColor: cardColor,
      cardTheme: baseTheme.cardTheme.copyWith(color: cardColor),
      dialogTheme: baseTheme.dialogTheme.copyWith(backgroundColor: dialogColor),
      popupMenuTheme: baseTheme.popupMenuTheme.copyWith(color: menuColor),
      bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
        backgroundColor: dialogColor,
        modalBackgroundColor: dialogColor,
      ),
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: (baseTheme.appBarTheme.backgroundColor ??
                baseTheme.scaffoldBackgroundColor)
            .withValues(alpha: appBarOpacity()),
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  // ─── Convenience helpers ─────────────────────────────────────────────────

  static ThemeData resolveMaterialTheme({
    required ThemeData light,
    required ThemeData dark,
    required ThemeProvider provider,
    required double acrylicStrength,
    required bool useAcrylicVisuals,
  }) {
    final base = provider.currentTheme == AppThemeType.dark ? dark : light;
    if (!useAcrylicVisuals) return base;
    return createAcrylicBridgeTheme(
      baseTheme: base,
      brightness: provider.currentTheme == AppThemeType.dark
          ? Brightness.dark
          : Brightness.light,
      acrylicStrength: acrylicStrength,
    );
  }
}
