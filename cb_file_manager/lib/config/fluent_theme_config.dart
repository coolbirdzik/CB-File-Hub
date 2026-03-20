import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

import 'theme_config.dart';

/// Fluent theme mapping that preserves existing app theme preferences.
class FluentThemeConfig {
  const FluentThemeConfig._();

  static fluent.FluentThemeData getTheme(
    AppThemeType themeType, {
    AppAccentColor accentColor = ThemeConfig.defaultAccentColor,
    double acrylicStrength = 1.00,
  }) {
    final materialTheme = ThemeConfig.getTheme(
      themeType,
      accentColor: accentColor,
    );
    final fluentAccentColor = _resolveAccentColor(accentColor);
    final isDark = materialTheme.brightness == Brightness.dark;
    final double normalizedStrength =
        acrylicStrength.clamp(0.0, 2.0).toDouble();
    const Color fluentLightBackground2 = Color(0xFFF4F5F8);
    const Color fluentLightBackground3 = Color(0xFFFFFFFF);
    const Color fluentLightCard = Color(0xFFF0F1F5);

    double opacityByStrength({
      required double solidAtMin,
      required double glassAtMax,
    }) {
      return solidAtMin + (glassAtMax - solidAtMin) * normalizedStrength;
    }

    final scaffoldBase =
        isDark ? materialTheme.colorScheme.surface : fluentLightBackground3;
    final cardBase = isDark ? materialTheme.cardColor : fluentLightCard;
    final menuBase =
        isDark ? materialTheme.colorScheme.surface : fluentLightBackground2;

    final scaffoldColor = scaffoldBase.withValues(
      alpha: isDark
          ? opacityByStrength(solidAtMin: 0.90, glassAtMax: 0.16)
          : opacityByStrength(solidAtMin: 0.99, glassAtMax: 0.92),
    );
    final cardColor = cardBase.withValues(
      alpha: isDark
          ? opacityByStrength(solidAtMin: 0.96, glassAtMax: 0.56)
          : opacityByStrength(solidAtMin: 0.98, glassAtMax: 0.90),
    );
    final menuColor = menuBase.withValues(
      alpha: isDark
          ? opacityByStrength(solidAtMin: 0.98, glassAtMax: 0.68)
          : opacityByStrength(solidAtMin: 0.99, glassAtMax: 0.92),
    );

    return fluent.FluentThemeData(
      brightness: materialTheme.brightness,
      accentColor: fluentAccentColor,
      scaffoldBackgroundColor: scaffoldColor,
      acrylicBackgroundColor: scaffoldBase.withValues(
        alpha: isDark
            ? opacityByStrength(solidAtMin: 0.95, glassAtMax: 0.62)
            : opacityByStrength(solidAtMin: 0.98, glassAtMax: 0.90),
      ),
      micaBackgroundColor: scaffoldBase.withValues(
        alpha: isDark
            ? opacityByStrength(solidAtMin: 0.90, glassAtMax: 0.42)
            : opacityByStrength(solidAtMin: 0.97, glassAtMax: 0.88),
      ),
      menuColor: menuColor,
      cardColor: cardColor,
      shadowColor: materialTheme.shadowColor,
      visualDensity: materialTheme.visualDensity,
    );
  }

  static fluent.AccentColor _resolveAccentColor(AppAccentColor accentColor) {
    switch (accentColor) {
      case AppAccentColor.blue:
        return fluent.Colors.blue;
      case AppAccentColor.teal:
        return fluent.Colors.teal;
      case AppAccentColor.green:
        return fluent.Colors.green;
      case AppAccentColor.lime:
        // Note: fluent.Colors has no lime; using yellow as closest match.
        // If lime support is needed, create a custom AccentColor.
        return fluent.Colors.yellow;
      case AppAccentColor.yellow:
        return fluent.Colors.yellow;
      case AppAccentColor.orange:
        return fluent.Colors.orange;
      case AppAccentColor.red:
        return fluent.Colors.red;
      case AppAccentColor.magenta:
        return fluent.Colors.magenta;
      case AppAccentColor.purple:
        return fluent.Colors.purple;
    }
  }
}
