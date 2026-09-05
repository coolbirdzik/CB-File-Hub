import 'package:flutter/material.dart';

import '../design_system/cb_theme_builder.dart';
import '../design_system/tokens/cb_color_tokens.dart';
import 'app_toast_theme.dart';
import 'app_ui_font.dart';

export 'app_ui_font.dart';

enum AppThemeType { light, dark }

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

/// User-selectable primary text colour.
///
/// [system] keeps design-token defaults. [accent] tracks the current accent
/// colour. The remaining values mirror [AppAccentColor] so example / body
/// text can use the same palette.
enum AppFontColor {
  system,
  accent,
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
  static const AppFontColor defaultFontColor = AppFontColor.system;
  static const AppUiFont defaultUiFont = AppUiFontConfig.defaultFont;

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

  static const Map<AppFontColor, String> fontColorNames = {
    AppFontColor.system: 'Default',
    AppFontColor.accent: 'Accent',
    AppFontColor.blue: 'Blue',
    AppFontColor.teal: 'Teal',
    AppFontColor.green: 'Green',
    AppFontColor.lime: 'Lime',
    AppFontColor.yellow: 'Yellow',
    AppFontColor.orange: 'Orange',
    AppFontColor.red: 'Red',
    AppFontColor.magenta: 'Magenta',
    AppFontColor.purple: 'Purple',
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

  static AppAccentColor? accentForFontColor(AppFontColor fontColor) {
    switch (fontColor) {
      case AppFontColor.system:
      case AppFontColor.accent:
        return null;
      case AppFontColor.blue:
        return AppAccentColor.blue;
      case AppFontColor.teal:
        return AppAccentColor.teal;
      case AppFontColor.green:
        return AppAccentColor.green;
      case AppFontColor.lime:
        return AppAccentColor.lime;
      case AppFontColor.yellow:
        return AppAccentColor.yellow;
      case AppFontColor.orange:
        return AppAccentColor.orange;
      case AppFontColor.red:
        return AppAccentColor.red;
      case AppFontColor.magenta:
        return AppAccentColor.magenta;
      case AppFontColor.purple:
        return AppAccentColor.purple;
    }
  }

  /// Readable text tone for [fontColor] on the active surface.
  ///
  /// Returns null for [AppFontColor.system] so tokens keep their defaults.
  static Color? resolveFontColor(
    AppFontColor fontColor,
    Brightness brightness, {
    AppAccentColor accentColor = defaultAccentColor,
  }) {
    final AppAccentColor? seedAccent;
    if (fontColor == AppFontColor.system) {
      seedAccent = null;
    } else if (fontColor == AppFontColor.accent) {
      seedAccent = accentColor;
    } else {
      seedAccent = accentForFontColor(fontColor);
    }
    if (seedAccent == null) return null;
    return CbAccentRamp.from(getAccentSeedColor(seedAccent), brightness).text;
  }

  /// Swatch colour shown in the settings picker (letter "A" example).
  static Color fontColorSwatch(
    AppFontColor fontColor, {
    required Brightness brightness,
    required AppAccentColor accentColor,
    required Color fallback,
  }) {
    return resolveFontColor(fontColor, brightness, accentColor: accentColor) ??
        fallback;
  }

  static ThemeData getTheme(
    AppThemeType themeType, {
    AppAccentColor accentColor = defaultAccentColor,
    AppFontColor fontColor = defaultFontColor,
    AppUiFont uiFont = defaultUiFont,
  }) {
    switch (themeType) {
      case AppThemeType.light:
        return getLightTheme(
          accentColor: accentColor,
          fontColor: fontColor,
          uiFont: uiFont,
        );
      case AppThemeType.dark:
        return getDarkTheme(
          accentColor: accentColor,
          fontColor: fontColor,
          uiFont: uiFont,
        );
    }
  }

  /// Component themes that live outside the design system but still need to
  /// ride along on [ThemeData]. [CbThemeBuilder] owns the extension list, so
  /// anything extra is passed in here rather than bolted on afterwards with
  /// `copyWith` (which would drop [CbTokens]).
  static const List<ThemeExtension> _extraExtensions = [
    AppToastTheme(
      iconBoxSize: 30.0,
      iconSize: 18.0,
      iconBoxRadius: 8.0,
      containerRadius: 12.0,
      hPadding: 12.0,
      vPadding: 10.0,
      maxWidth: 360.0,
      blurSigmaDesktopLight: 18.0,
      blurSigmaDesktopDark: 10.0,
      blurSigmaMobile: 8.0,
      surfaceOpacity: 0.82,
      borderOpacity: 0.22,
      shadowOpacityLight: 0.16,
      shadowOpacityDark: 0.40,
      iconAccentOpacity: 0.14,
      durationSuccess: Duration(milliseconds: 2200),
      durationInfo: Duration(milliseconds: 2200),
      durationWarning: Duration(milliseconds: 2600),
      durationError: Duration(milliseconds: 3200),
    ),
  ];

  static ThemeData getLightTheme({
    AppAccentColor accentColor = defaultAccentColor,
    AppFontColor fontColor = defaultFontColor,
    AppUiFont uiFont = defaultUiFont,
  }) {
    final base = CbThemeBuilder.build(
      brightness: Brightness.light,
      accent: getAccentSeedColor(accentColor),
      textColor: resolveFontColor(
        fontColor,
        Brightness.light,
        accentColor: accentColor,
      ),
      extraExtensions: _extraExtensions,
    );
    return AppUiFontConfig.applyToTheme(base, uiFont);
  }

  static ThemeData getDarkTheme({
    AppAccentColor accentColor = defaultAccentColor,
    AppFontColor fontColor = defaultFontColor,
    AppUiFont uiFont = defaultUiFont,
  }) {
    final base = CbThemeBuilder.build(
      brightness: Brightness.dark,
      accent: getAccentSeedColor(accentColor),
      textColor: resolveFontColor(
        fontColor,
        Brightness.dark,
        accentColor: accentColor,
      ),
      extraExtensions: _extraExtensions,
    );
    return AppUiFontConfig.applyToTheme(base, uiFont);
  }

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
