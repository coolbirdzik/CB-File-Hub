import 'dart:ui';

import 'package:cb_file_manager/config/fluent_theme_config.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/cb_tokens.dart';
import 'package:cb_file_manager/design_system/desktop_acrylic_theme_bridge.dart';
import 'package:cb_file_manager/design_system/fluent_chrome_surface.dart';
import 'package:cb_file_manager/design_system/fluent_surface_tokens.dart';
import 'package:cb_file_manager/design_system/macos_glass_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('macOS $brightness shares a bounded Glass ramp in both hosts', () {
      final base = brightness == Brightness.dark
          ? ThemeConfig.getDarkTheme()
          : ThemeConfig.getLightTheme();
      double previousOpacity = 1.1;
      for (final strength in [0.0, 1.0, 2.0]) {
        for (final dynamicBackdrop in [false, true]) {
          final theme = createDesktopAcrylicMaterialBridgeTheme(
            baseTheme: base,
            brightness: brightness,
            strength: strength,
            preferTransparentBackdrop: dynamicBackdrop,
            platform: TargetPlatform.macOS,
          );
          final glass = theme.extension<MacosGlassTheme>()!;
          final chrome = FluentSurfaceTokens.fromTheme(theme);
          final fluent = FluentThemeConfig.getTheme(
            brightness == Brightness.dark
                ? AppThemeType.dark
                : AppThemeType.light,
            acrylicStrength: strength,
            preferTransparentBackdrop: dynamicBackdrop,
            platform: TargetPlatform.macOS,
          );
          expect(theme.extension<CbTokens>(), isNotNull);
          expect(
            theme.scaffoldBackgroundColor.a,
            greaterThanOrEqualTo(glass.canvasOpacity - 0.005),
          );
          expect(
            fluent.scaffoldBackgroundColor.a,
            closeTo(theme.scaffoldBackgroundColor.a, 0.005),
          );
          expect(
            chrome.toolbarTintAlpha,
            greaterThanOrEqualTo(glass.chromeOpacity),
          );
          expect(chrome.drawerTintAlpha, chrome.toolbarTintAlpha);
          expect(chrome.chromeBlur, glass.blurSigma);
          expect(fluent.menuColor.a, 1);
          expect(theme.dialogTheme.backgroundColor!.a, 1);
          expect(glass.canvasOpacity, inInclusiveRange(0, 1));
          expect(glass.canvasOpacity, lessThanOrEqualTo(previousOpacity));
          previousOpacity = glass.canvasOpacity;
        }
      }
    });
  }

  test('Windows retains the Acrylic theme projection', () {
    final theme = createDesktopAcrylicMaterialBridgeTheme(
      baseTheme: ThemeConfig.getLightTheme(),
      brightness: Brightness.light,
      strength: 1,
      preferTransparentBackdrop: true,
      platform: TargetPlatform.windows,
    );
    expect(theme.extension<MacosGlassTheme>(), isNull);
    expect(theme.scaffoldBackgroundColor.a, closeTo(0.62, 0.005));
    expect(FluentSurfaceTokens.fromTheme(theme).chromeBlur, 18);
  });

  testWidgets(
    'live strength changes chrome tint and blur without native input layers',
    (tester) async {
      final base = ThemeConfig.getLightTheme();
      Future<void> mount(double strength, {bool highContrast = false}) =>
          tester.pumpWidget(
            MaterialApp(
              theme: createDesktopAcrylicMaterialBridgeTheme(
                baseTheme: base,
                brightness: Brightness.light,
                strength: strength,
                preferTransparentBackdrop: true,
              ),
              home: MediaQuery(
                data: MediaQueryData(highContrast: highContrast),
                child: FluentChromeSurface(
                  tint: Colors.white,
                  tintAlpha: 0.8,
                  blurSigma: 18,
                  borderRadius: BorderRadius.circular(16),
                  child: const SizedBox(width: 300, height: 200),
                ),
              ),
            ),
          );
      await mount(0);
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      await mount(2);
      await tester.pumpAndSettle();
      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter.filter, ImageFilter.blur(sigmaX: 28, sigmaY: 28));
      expect(find.byType(AppKitView), findsNothing);
      final tint = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.color != null)
          .first
          .color!;
      expect(tint.a, greaterThanOrEqualTo(0.72));
      await mount(2, highContrast: true);
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test(
    'blur changes independently of transparency and survives theme animation',
    () {
      final clear = MacosGlassTheme(
        strength: 2,
        blurStrength: 0,
        brightness: Brightness.light,
      );
      final frosted = clear.copyWith(blurStrength: 2);
      expect(clear.blurSigma, 0);
      expect(frosted.blurSigma, 56);
      expect(clear.chromeOpacity, frosted.chromeOpacity);
      expect(clear.canvasOpacity, frosted.canvasOpacity);
      expect(clear.lerp(frosted, 0.5).blurSigma, 28);
      expect(frosted.copyWith(strength: 0).blurSigma, 0);
    },
  );

  for (final brightness in Brightness.values) {
    test(
      'macOS $brightness text remains readable against hostile backdrops',
      () {
        double ratio(Color ink, Color background) {
          final a = Color.alphaBlend(ink, background).computeLuminance();
          final b = background.computeLuminance();
          return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
        }

        for (final font in AppFontColor.values) {
          for (final accent in AppAccentColor.values) {
            final base = ThemeConfig.getTheme(
              brightness == Brightness.dark
                  ? AppThemeType.dark
                  : AppThemeType.light,
              fontColor: font,
              accentColor: accent,
            );
            final theme = createDesktopAcrylicMaterialBridgeTheme(
              baseTheme: base,
              brightness: brightness,
              strength: 2,
              glassBlurStrength: 0,
              preferTransparentBackdrop: true,
              platform: TargetPlatform.macOS,
            );
            final fluent = FluentThemeConfig.getTheme(
              brightness == Brightness.dark
                  ? AppThemeType.dark
                  : AppThemeType.light,
              fontColor: font,
              accentColor: accent,
              acrylicStrength: 2,
              glassBlurStrength: 0,
              platform: TargetPlatform.macOS,
            );
            final chrome = FluentSurfaceTokens.fromTheme(theme);
            final surfaces = [
              theme.scaffoldBackgroundColor,
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainer,
              theme.colorScheme.surfaceContainerLowest,
              theme.colorScheme.surfaceContainerLow,
              theme.cardColor,
              theme.appBarTheme.backgroundColor!,
              fluent.scaffoldBackgroundColor,
              fluent.cardColor,
              fluent.acrylicBackgroundColor,
              fluent.micaBackgroundColor,
              chrome.toolbar,
            ];
            for (final surface in surfaces) {
              for (final ink in [
                theme.colorScheme.onSurface,
                theme.colorScheme.onSurfaceVariant,
              ]) {
                final opaqueRatio = ratio(ink, surface.withValues(alpha: 1));
                final minimum = opaqueRatio.clamp(1.0, 4.5);
                if (font == AppFontColor.system) {
                  expect(minimum, 4.5);
                }
                for (final backdrop in [
                  Colors.black,
                  Colors.white,
                  Colors.red,
                  Colors.green,
                  Colors.blue,
                ]) {
                  expect(
                    ratio(ink, Color.alphaBlend(surface, backdrop)),
                    greaterThanOrEqualTo(minimum - 0.001),
                    reason:
                        '$brightness / $font / $accent / $surface / $backdrop',
                  );
                }
              }
            }
          }
        }
      },
    );
  }
}
