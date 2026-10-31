import 'package:cb_file_manager/config/fluent_theme_config.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/desktop_acrylic_theme_bridge.dart';
import 'package:cb_file_manager/design_system/fluent_surface_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final dynamicBackdrop in [false, true]) {
      test(
        '$brightness dynamic=$dynamicBackdrop has one bounded opacity ramp',
        () {
          final base = brightness == Brightness.dark
              ? ThemeConfig.getDarkTheme()
              : ThemeConfig.getLightTheme();
          List<double>? previous;
          for (final strength in [0.0, 0.5, 1.0, 1.5, 2.0]) {
            final material = createDesktopAcrylicMaterialBridgeTheme(
              baseTheme: base,
              brightness: brightness,
              strength: strength,
              preferTransparentBackdrop: dynamicBackdrop,
              platform: TargetPlatform.windows,
            );
            final fluent = FluentThemeConfig.getTheme(
              brightness == Brightness.dark
                  ? AppThemeType.dark
                  : AppThemeType.light,
              acrylicStrength: strength,
              preferTransparentBackdrop: dynamicBackdrop,
              platform: TargetPlatform.windows,
            );
            final shell = FluentSurfaceTokens.fromTheme(material);
            final opacities = [
              material.scaffoldBackgroundColor.a,
              material.colorScheme.surface.a,
              material.colorScheme.surfaceContainer.a,
              material.colorScheme.surfaceContainerLow.a,
              material.colorScheme.surfaceContainerLowest.a,
              shell.toolbarTintAlpha,
              shell.drawerTintAlpha,
            ];
            for (var i = 0; i < opacities.length; i++) {
              expect(opacities[i], inInclusiveRange(0, 1));
              if (strength == 0) expect(opacities[i], 1);
              if (previous != null) expect(opacities[i], lessThan(previous[i]));
            }
            expect(
              fluent.scaffoldBackgroundColor.a,
              material.scaffoldBackgroundColor.a,
            );
            expect(fluent.cardColor.a, material.cardColor.a);
            expect(fluent.acrylicBackgroundColor.a, shell.toolbarTintAlpha);
            expect(
              shell.drawerTintAlpha,
              greaterThanOrEqualTo(shell.toolbarTintAlpha),
            );
            expect(material.dialogTheme.backgroundColor!.a, 1);
            expect(fluent.menuColor.a, 1);
            previous = opacities;
          }
        },
      );
    }
  }
}
