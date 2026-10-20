import 'dart:ui';

import 'package:cb_file_manager/providers/theme_provider.dart';
import 'package:cb_file_manager/ui/utils/desktop_acrylic_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/theme_provider_test_support.dart';

void main() {
  testWidgets(
    'macOS wallpaper shares Glass strength and dynamic mode removes the image',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'desktop_glass_strength': 2.0,
        'acrylic_backdrop_mode': 'wallpaper',
        'acrylic_backdrop_image_path': '/missing-glass-test-wallpaper.png',
      });
      final provider = await loadThemeProvider(TargetPlatform.macOS);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: DesktopAcrylicBackdrop(
              brightness: Brightness.light,
              child: SizedBox.expand(key: ValueKey('content')),
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
        ImageFilter.blur(sigmaX: 28, sigmaY: 28),
      );
      final tintFinder = find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.byType(ColoredBox),
      );
      final tint = tester.widget<ColoredBox>(tintFinder);
      expect(tint.color.a, closeTo(0.32, 0.005));
      await provider.setDesktopGlassBlurStrength(0);
      await tester.pump();
      expect(
        tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
        ImageFilter.blur(sigmaX: 0, sigmaY: 0),
      );
      expect(tester.widget<ColoredBox>(tintFinder).color.a, tint.color.a);
      await provider.setDesktopGlassBlurStrength(2);
      await tester.pump();
      expect(
        tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
        ImageFilter.blur(sigmaX: 56, sigmaY: 56),
      );
      await provider.setDesktopBackdropStrength(0, persist: false);
      await tester.pump();
      expect(tester.widget<ColoredBox>(tintFinder).color.a, 1);
      await provider.setBackdropMode(AcrylicBackdropMode.dynamic);
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byKey(const ValueKey('content')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    },
  );
}
