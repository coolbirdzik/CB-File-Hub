import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/design_system/desktop_acrylic_theme_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop Fluent surfaces project the Home canvas in both themes', () {
    for (final theme in [
      createDesktopAcrylicMaterialBridgeTheme(
        baseTheme: ThemeConfig.getLightTheme(),
        brightness: Brightness.light,
        strength: 1.25,
        preferTransparentBackdrop: true,
      ),
      createDesktopAcrylicMaterialBridgeTheme(
        baseTheme: ThemeConfig.getDarkTheme(),
        brightness: Brightness.dark,
        strength: 1.25,
        preferTransparentBackdrop: true,
      ),
    ]) {
      final surfaces = FluentSurfaceTokens.fromTheme(theme);
      final colors = theme.cb.colors;

      // Home is transparent on desktop and inherits this exact shell canvas.
      expect(surfaces.canvas, theme.scaffoldBackgroundColor);
      expect(surfaces.toolbar.a, lessThan(1.0));
      expect(surfaces.drawerTintAlpha, lessThan(1.0));
      expect(surfaces.toolbarTintAlpha, lessThan(1.0));
      expect(surfaces.control, colors.surfaceSunken);
      expect(surfaces.strokeSubtle, colors.strokeSubtle);
      expect(FluentSurfaceTokens.controlRadius, CbRadii.smAll);
    }
  });

  test('light and dark projections keep the same surface hierarchy', () {
    final light = FluentSurfaceTokens.fromTheme(
      createDesktopAcrylicMaterialBridgeTheme(
        baseTheme: ThemeConfig.getLightTheme(),
        brightness: Brightness.light,
        strength: 1.25,
        preferTransparentBackdrop: true,
      ),
    );
    final dark = FluentSurfaceTokens.fromTheme(
      createDesktopAcrylicMaterialBridgeTheme(
        baseTheme: ThemeConfig.getDarkTheme(),
        brightness: Brightness.dark,
        strength: 1.25,
        preferTransparentBackdrop: true,
      ),
    );

    for (final surfaces in [light, dark]) {
      final compositedToolbar = Color.alphaBlend(
        surfaces.toolbar,
        surfaces.canvas,
      );
      final compositedDrawer = Color.alphaBlend(
        surfaces.chromeTint.withValues(alpha: surfaces.drawerTintAlpha),
        surfaces.canvas,
      );
      expect(
        compositedToolbar.computeLuminance(),
        lessThan(surfaces.canvas.computeLuminance()),
      );
      expect(
        compositedDrawer.computeLuminance(),
        lessThan(surfaces.canvas.computeLuminance()),
      );
      expect(surfaces.chromeBlur, greaterThan(0));
      expect(surfaces.toolbarTintAlpha, lessThan(surfaces.drawerTintAlpha));
    }

    expect(light.control, isNot(light.toolbar));
    expect(dark.control, isNot(dark.toolbar));
    expect(FluentSurfaceTokens.toolbarRadius, CbRadii.mdAll);
    expect(FluentSurfaceTokens.controlRadius, CbRadii.smAll);
  });
}
