import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

import '../design_system/cb_tokens.dart';
import '../design_system/tokens/cb_geometry_tokens.dart';
import 'theme_config.dart';

/// Fluent theme mapping that preserves existing app theme preferences.
class FluentThemeConfig {
  const FluentThemeConfig._();

  static fluent.FluentThemeData getTheme(
    AppThemeType themeType, {
    AppAccentColor accentColor = ThemeConfig.defaultAccentColor,
    AppFontColor fontColor = ThemeConfig.defaultFontColor,
    AppUiFont uiFont = ThemeConfig.defaultUiFont,
    double acrylicStrength = 1.00,
    bool preferTransparentBackdrop = false,
  }) {
    final materialTheme = ThemeConfig.getTheme(
      themeType,
      accentColor: accentColor,
      fontColor: fontColor,
      uiFont: uiFont,
    );
    final fluentAccentColor = _resolveAccentColor(accentColor);
    final isDark = materialTheme.brightness == Brightness.dark;
    final double normalizedStrength = acrylicStrength
        .clamp(0.0, 2.0)
        .toDouble();
    double opacityByStrength({
      required double solidAtMin,
      required double glassAtMax,
    }) {
      return solidAtMin + (glassAtMax - solidAtMin) * normalizedStrength;
    }

    // Keep both hosts on the same semantic surface ramp. Home inherits the
    // Material bridge canvas from the tab shell, so the Fluent scaffold must
    // use the same Cb canvas rather than an independent Fluent neutral.
    final colors = materialTheme.cb.colors;
    final scaffoldBase = colors.canvas;
    final cardBase = colors.surfaceRaised;
    final menuBase = colors.surfaceOverlay;

    final scaffoldColor = scaffoldBase.withValues(
      alpha: isDark
          ? opacityByStrength(
              solidAtMin: 0.96,
              glassAtMax: preferTransparentBackdrop ? 0.76 : 0.88,
            )
          : opacityByStrength(
              solidAtMin: 0.995,
              glassAtMax: preferTransparentBackdrop ? 0.84 : 0.96,
            ),
    );
    final cardColor = cardBase.withValues(
      alpha: isDark
          ? opacityByStrength(
              solidAtMin: 0.98,
              glassAtMax: preferTransparentBackdrop ? 0.84 : 0.94,
            )
          : opacityByStrength(
              solidAtMin: 0.99,
              glassAtMax: preferTransparentBackdrop ? 0.88 : 0.97,
            ),
    );
    final menuColor = menuBase.withValues(
      alpha: isDark
          ? opacityByStrength(
              solidAtMin: 0.995,
              glassAtMax: preferTransparentBackdrop ? 0.90 : 0.98,
            )
          : opacityByStrength(
              solidAtMin: 0.995,
              glassAtMax: preferTransparentBackdrop ? 0.90 : 0.98,
            ),
    );

    return fluent.FluentThemeData(
      brightness: materialTheme.brightness,
      accentColor: fluentAccentColor,
      scaffoldBackgroundColor: scaffoldColor,
      acrylicBackgroundColor: scaffoldBase.withValues(
        alpha: isDark
            ? opacityByStrength(
                solidAtMin: 0.98,
                glassAtMax: preferTransparentBackdrop ? 0.82 : 0.92,
              )
            : opacityByStrength(
                solidAtMin: 0.99,
                glassAtMax: preferTransparentBackdrop ? 0.88 : 0.97,
              ),
      ),
      micaBackgroundColor: scaffoldBase.withValues(
        alpha: isDark
            ? opacityByStrength(
                solidAtMin: 0.96,
                glassAtMax: preferTransparentBackdrop ? 0.70 : 0.82,
              )
            : opacityByStrength(
                solidAtMin: 0.99,
                glassAtMax: preferTransparentBackdrop ? 0.84 : 0.96,
              ),
      ),
      menuColor: menuColor,
      cardColor: cardColor,
      shadowColor: materialTheme.shadowColor,
      visualDensity: materialTheme.visualDensity,
      buttonTheme: _buttonTheme(),
    );
  }

  /// Rounds every Fluent button to match the rest of the app: a soft
  /// rounded rect ([CbRadii.button]), whether it carries a label
  /// ([fluent.Button], [fluent.FilledButton]) or is icon-only
  /// ([fluent.IconButton]). Only [Button] and its two subclasses are used
  /// directly in this app, so only their three style slots need a shape
  /// here — [fluent.OutlinedButton] and [fluent.HyperlinkButton] are unused
  /// and keep Fluent's defaults.
  static fluent.ButtonThemeData _buttonTheme() {
    const rounded = WidgetStatePropertyAll<ShapeBorder>(
      RoundedRectangleBorder(borderRadius: CbRadii.buttonAll),
    );
    return const fluent.ButtonThemeData(
      defaultButtonStyle: fluent.ButtonStyle(shape: rounded),
      filledButtonStyle: fluent.ButtonStyle(shape: rounded),
      // Fluent's own icon-button padding is asymmetric (WinUI's rectangular
      // touch target); symmetric padding keeps the box square so the
      // rounded corners read evenly on every side.
      iconButtonStyle: fluent.ButtonStyle(
        shape: rounded,
        padding: WidgetStatePropertyAll(EdgeInsets.all(CbSpacing.sm)),
      ),
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
