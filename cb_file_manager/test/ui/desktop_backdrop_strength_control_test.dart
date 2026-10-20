import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/desktop_acrylic_theme_bridge.dart';
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
          find.text(glass ? 'Glass transparency' : 'Desktop acrylic strength'),
          findsOneWidget,
        );
        expect(find.byType(Slider), findsNWidgets(glass ? 2 : 1));
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
        await tester.pump();
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
        }
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      },
    );
  }
}
