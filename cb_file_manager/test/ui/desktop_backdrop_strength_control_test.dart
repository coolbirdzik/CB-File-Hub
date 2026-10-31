import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/desktop_acrylic_theme_bridge.dart';
import 'package:cb_file_manager/design_system/fluent_surface_tokens.dart';
import 'package:cb_file_manager/design_system/macos_glass_theme.dart';
import 'package:cb_file_manager/providers/theme_provider.dart';
import 'package:cb_file_manager/ui/screens/settings/desktop_backdrop_strength_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/theme_provider_test_support.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets(
      '$platform slider labels, previews and commits the OS preference',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'desktop_acrylic_strength': 1.0,
          'desktop_glass_strength': 1.0,
        });
        final provider = await loadThemeProvider(platform);
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>.value(
            value: provider,
            child: Consumer<ThemeProvider>(
              builder: (_, theme, _) => MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: createDesktopAcrylicMaterialBridgeTheme(
                  baseTheme: theme.themeData,
                  brightness: Brightness.light,
                  strength: theme.desktopBackdropStrength,
                  glassBlurStrength: theme.desktopGlassBlurStrength,
                  preferTransparentBackdrop: true,
                  platform: platform,
                ),
                home: const Scaffold(body: DesktopBackdropStrengthControl()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final glass = platform == TargetPlatform.macOS;
        expect(
          find.text(glass ? 'Glass transparency' : 'Acrylic transparency'),
          findsOneWidget,
        );
        expect(find.byType(Slider), findsNWidgets(glass ? 2 : 1));
        final slider = tester.widget<Slider>(find.byType(Slider).first);
        expect(slider.max, glass ? 2 : 1);
        expect(slider.value, glass ? 1 : 0.5);
        expect(slider.label, glass ? '100%' : '50%');
        final prefs = await SharedPreferences.getInstance();
        final key = glass
            ? 'desktop_glass_strength'
            : 'desktop_acrylic_strength';
        final other = glass
            ? 'desktop_acrylic_strength'
            : 'desktop_glass_strength';
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Slider).first),
        );
        await gesture.moveBy(const Offset(180, 0));
        await tester.pump(
          glass ? Duration.zero : const Duration(milliseconds: 80),
        );
        final preview = provider.desktopBackdropStrength;
        expect(preview, greaterThan(1));
        expect(prefs.getDouble(key), 1);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(prefs.getDouble(key), preview);
        expect(prefs.getDouble(other), 1);
        final theme = Theme.of(tester.element(find.byType(Slider).first));
        if (glass) {
          expect(theme.extension<MacosGlassTheme>()!.strength, preview);
          final blurGesture = await tester.startGesture(
            tester.getCenter(find.byType(Slider).last),
          );
          await blurGesture.moveBy(const Offset(-160, 0));
          await tester.pump();
          final blurPreview = provider.desktopGlassBlurStrength;
          expect(blurPreview, lessThan(1));
          expect(prefs.containsKey('desktop_glass_blur_strength'), isFalse);
          expect(provider.desktopBackdropStrength, preview);
          await blurGesture.up();
          await tester.pumpAndSettle();
          expect(prefs.getDouble('desktop_glass_blur_strength'), blurPreview);
          expect(
            Theme.of(
              tester.element(find.byType(Slider).last),
            ).extension<MacosGlassTheme>()!.blurStrength,
            blurPreview,
          );
        } else {
          expect(theme.extension<MacosGlassTheme>(), isNull);
          expect(prefs.containsKey('desktop_glass_blur_strength'), isFalse);
          final rect = tester.getRect(find.byType(Slider));
          await tester.tapAt(Offset(rect.left + 4, rect.center.dy));
          await tester.pumpAndSettle();
          expect(provider.desktopBackdropStrength, 0);
          expect(prefs.getDouble(key), 0);
          final opaque = FluentSurfaceTokens.fromTheme(
            Theme.of(tester.element(find.byType(Slider))),
          );
          expect(opaque.canvas.a, 1);
          expect(opaque.toolbarTintAlpha, 1);
          expect(opaque.drawerTintAlpha, 1);
          final reloaded = await loadThemeProvider(platform);
          expect(reloaded.desktopBackdropStrength, 0);
          reloaded.dispose();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      },
    );
  }

  testWidgets(
    'Windows drag keeps the thumb local and commits the latest value',
    (tester) async {
      SharedPreferences.setMockInitialValues({'desktop_acrylic_strength': 1.0});
      final provider = await loadThemeProvider(TargetPlatform.windows);
      var notifications = 0;
      provider.addListener(() => notifications++);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: DesktopBackdropStrengthControl()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final preview = tester.widget<Slider>(find.byType(Slider)).value;
      expect(preview, greaterThan(0.5));
      expect(notifications, 0);
      expect(provider.desktopBackdropStrength, 1);
      await tester.pump(const Duration(milliseconds: 16));
      expect(notifications, 1);
      expect(provider.desktopBackdropStrength, preview * 2);

      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      final finalValue = tester.widget<Slider>(find.byType(Slider)).value * 2;
      await gesture.up();
      await tester.pumpAndSettle();
      expect(provider.desktopBackdropStrength, finalValue);
      expect(notifications, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('desktop_acrylic_strength'), finalValue);
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        notifications,
        2,
        reason: 'A stale preview replaced the committed value',
      );

      // Leaving settings with a queued preview must not update the app later.
      final pending = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      await pending.moveBy(const Offset(-40, 0));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await pending.up();
      await tester.pump(const Duration(milliseconds: 160));
      expect(notifications, 2);
      provider.dispose();
    },
  );
}
