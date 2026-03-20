import 'package:flutter/material.dart';
import 'theme_factory.dart';

enum AppThemeType {
  light,
  dark,
}

enum AppAccentColor {
  blue,
  teal,
  green,
  lime,
  yellow,
  orange,
  red,
  magenta,
  purple,
}

class ThemeConfig {
  static const AppAccentColor defaultAccentColor = AppAccentColor.blue;

  static const Map<AppThemeType, String> themeNames = {
    AppThemeType.light: 'Light',
    AppThemeType.dark: 'Dark',
  };

  static const Map<AppAccentColor, String> accentNames = {
    AppAccentColor.blue: 'Blue',
    AppAccentColor.teal: 'Teal',
    AppAccentColor.green: 'Green',
    AppAccentColor.lime: 'Lime',
    AppAccentColor.yellow: 'Yellow',
    AppAccentColor.orange: 'Orange',
    AppAccentColor.red: 'Red',
    AppAccentColor.magenta: 'Magenta',
    AppAccentColor.purple: 'Purple',
  };

  static const Map<AppAccentColor, Color> accentSeedColors = {
    AppAccentColor.blue: Color(0xFF0078D4),
    AppAccentColor.teal: Color(0xFF00B294),
    AppAccentColor.green: Color(0xFF107C10),
    AppAccentColor.lime: Color(0xFF7FBA00),
    AppAccentColor.yellow: Color(0xFFF9C80E),
    AppAccentColor.orange: Color(0xFFF7630C),
    AppAccentColor.red: Color(0xFFE81123),
    AppAccentColor.magenta: Color(0xFFB4009E),
    AppAccentColor.purple: Color(0xFF744DA9),
  };

  static Color getAccentSeedColor(AppAccentColor accentColor) {
    return accentSeedColors[accentColor] ??
        accentSeedColors[defaultAccentColor]!;
  }

  static ThemeData getTheme(
    AppThemeType themeType, {
    AppAccentColor accentColor = defaultAccentColor,
  }) {
    switch (themeType) {
      case AppThemeType.light:
        return getLightTheme(accentColor: accentColor);
      case AppThemeType.dark:
        return getDarkTheme(accentColor: accentColor);
    }
  }

  static ThemeData getLightTheme({
    AppAccentColor accentColor = defaultAccentColor,
  }) {
    final colorScheme = ThemeFactory.createColorScheme(
      seedColor: getAccentSeedColor(accentColor),
      brightness: Brightness.light,
      background: const Color(0xFFFFFFFF),
      surface: const Color(0xFFFFFFFF),
    );

    final theme = ThemeFactory.createTheme(
      colorScheme: colorScheme,
      brightness: Brightness.light,
      options: const ThemeOptions(
        borderRadius: 20.0,
        elevation: 0.0,
        useMaterial3: true,
        cardElevation: 0.0,
      ),
    );

    return theme.copyWith(
      scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      canvasColor: const Color(0xFFFFFFFF),
    );
  }

  static ThemeData getDarkTheme({
    AppAccentColor accentColor = defaultAccentColor,
  }) {
    final colorScheme = ThemeFactory.createColorScheme(
      seedColor: getAccentSeedColor(accentColor),
      brightness: Brightness.dark,
      background: const Color(0xFF0E0E0E),
      surface: const Color(0xFF181818),
    );

    return ThemeFactory.createTheme(
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      options: const ThemeOptions(
        borderRadius: 20.0,
        elevation: 0.0,
        useMaterial3: true,
        cardElevation: 0.0,
      ),
    );
  }

  static ThemeData get lightTheme => getLightTheme();
  static ThemeData get darkTheme => getDarkTheme();

  // --------------------------------------------------------------------
  // Theme tokens and helpers
  // --------------------------------------------------------------------

  /// Address-bar / input container fill colour.
  ///
  /// Intended to be defined in one place so the same tone can be used
  /// throughout the app.  Light mode is a very light black overlay (≈7 %) on
  /// white; dark mode is a subtle white overlay (≈10 %) on dark surfaces.
  ///
  /// You can obtain the value directly via the static helper below, or via
  /// the convenience extension on ThemeData.
  static Color addressBarFillColorFor(Brightness brightness) =>
      brightness == Brightness.light
          ? Colors.black.withValues(alpha: 0.07)
          : Colors.white.withValues(alpha: 0.10);
}
