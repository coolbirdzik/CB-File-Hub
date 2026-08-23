import 'package:flutter/material.dart';

import 'cb_tokens.dart';
import 'tokens/cb_geometry_tokens.dart';

/// Semantic surfaces used by the desktop Fluent browser shell.
///
/// The Fluent host and the Material compatibility theme are built side by
/// side. Keeping this projection on top of [CbTokens] prevents the browser
/// shell from drifting back to Fluent resource colours that do not match the
/// transparent Home surface behind it.
@immutable
class FluentSurfaceTokens {
  final Color canvas;
  final Color chromeTint;
  final Color toolbar;
  final Color chromeStroke;
  final double toolbarTintAlpha;
  final double drawerTintAlpha;
  final double chromeBlur;
  final Color control;
  final Color controlHover;
  final Color controlPressed;
  final Color stroke;
  final Color strokeSubtle;
  final Color focusRing;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color icon;

  const FluentSurfaceTokens({
    required this.canvas,
    required this.chromeTint,
    required this.toolbar,
    required this.chromeStroke,
    required this.toolbarTintAlpha,
    required this.drawerTintAlpha,
    required this.chromeBlur,
    required this.control,
    required this.controlHover,
    required this.controlPressed,
    required this.stroke,
    required this.strokeSubtle,
    required this.focusRing,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.icon,
  });

  /// Projects the active Material bridge theme onto the Fluent shell.
  ///
  /// [ThemeData.scaffoldBackgroundColor] is intentional here: the desktop
  /// bridge may carry the configured native-backdrop alpha, and Home already
  /// inherits this exact value from the tab shell.
  factory FluentSurfaceTokens.fromTheme(ThemeData theme) {
    final colors = theme.cb.colors;
    final isDark = theme.brightness == Brightness.dark;
    // Both desktop chrome surfaces use this same tint family. Light mode
    // steps down to the recessed neutral; dark mode derives a restrained
    // shade from the Home canvas instead of introducing a black panel.
    final chromeTint = isDark
        ? Color.alphaBlend(
            colors.scrim.withValues(alpha: 0.16),
            colors.canvas,
          )
        : colors.surfaceSunken;
    final toolbarTintAlpha = isDark ? 0.52 : 0.64;
    final drawerTintAlpha = isDark ? 0.60 : 0.72;
    return FluentSurfaceTokens(
      canvas: theme.scaffoldBackgroundColor,
      chromeTint: chromeTint,
      toolbar: chromeTint.withValues(alpha: toolbarTintAlpha),
      chromeStroke: colors.stroke,
      toolbarTintAlpha: toolbarTintAlpha,
      drawerTintAlpha: drawerTintAlpha,
      chromeBlur: 18,
      control: colors.surfaceSunken,
      controlHover: colors.surfaceHover,
      controlPressed: colors.surfacePressed,
      stroke: colors.stroke,
      strokeSubtle: colors.strokeSubtle,
      focusRing: colors.focusRing,
      textPrimary: colors.textPrimary,
      textSecondary: colors.textSecondary,
      textDisabled: colors.textDisabled,
      icon: colors.icon,
    );
  }

  factory FluentSurfaceTokens.of(BuildContext context) =>
      FluentSurfaceTokens.fromTheme(Theme.of(context));

  static const double toolbarHeight = 52;
  static const double controlHeight = 34;
  static const EdgeInsetsDirectional toolbarPadding =
      EdgeInsetsDirectional.fromSTEB(16, 6, 10, 6);
  static const BorderRadius toolbarRadius = CbRadii.mdAll;
  static const BorderRadius controlRadius = CbRadii.smAll;
}
