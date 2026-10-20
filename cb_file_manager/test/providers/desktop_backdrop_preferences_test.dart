import 'package:cb_file_manager/providers/theme_provider.dart';
import '../support/theme_provider_test_support.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Glass blur previews, commits and reloads independently of transparency',
    () async {
      SharedPreferences.setMockInitialValues({'desktop_glass_strength': 1.6});
      final mac = await loadThemeProvider(TargetPlatform.macOS);
      final prefs = await SharedPreferences.getInstance();
      expect(mac.desktopGlassBlurStrength, 1);
      await mac.setDesktopGlassBlurStrength(0.4, persist: false);
      expect(mac.desktopGlassBlurStrength, 0.4);
      expect(mac.desktopBackdropStrength, 1.6);
      expect(prefs.containsKey('desktop_glass_blur_strength'), isFalse);
      await mac.setDesktopGlassBlurStrength(0.4);
      final reloaded = await loadThemeProvider(TargetPlatform.macOS);
      expect(reloaded.desktopGlassBlurStrength, 0.4);
      expect(reloaded.desktopBackdropStrength, 1.6);
      await reloaded.setDesktopGlassBlurStrength(0);
      final cleared = await loadThemeProvider(TargetPlatform.macOS);
      expect(cleared.desktopGlassBlurStrength, 0);
      await cleared.setDesktopGlassBlurStrength(12);
      expect(cleared.desktopGlassBlurStrength, 2);
      await cleared.setDesktopGlassBlurStrength(double.nan);
      expect(cleared.desktopGlassBlurStrength, 1);
      expect(prefs.containsKey('desktop_acrylic_strength'), isFalse);
      mac.dispose();
      reloaded.dispose();
      cleared.dispose();
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'macOS migrates legacy strength once and stores Glass independently',
    () async {
      SharedPreferences.setMockInitialValues({'desktop_acrylic_strength': 0.4});
      final mac = await loadThemeProvider(TargetPlatform.macOS);
      final prefs = await SharedPreferences.getInstance();
      expect(mac.desktopBackdropStrength, 0.4);
      expect(prefs.getDouble('desktop_glass_strength'), 0.4);
      await mac.setDesktopBackdropStrength(1.7, persist: false);
      expect(mac.desktopBackdropStrength, 1.7);
      expect(prefs.getDouble('desktop_glass_strength'), 0.4);
      // Releasing a slider commits the same value used by the final preview.
      await mac.setDesktopBackdropStrength(1.7);
      expect(prefs.getDouble('desktop_glass_strength'), 1.7);
      expect(prefs.getDouble('desktop_acrylic_strength'), 0.4);
      mac.dispose();

      final windows = await loadThemeProvider(TargetPlatform.windows);
      expect(windows.desktopBackdropStrength, 0.4);
      await windows.setDesktopBackdropStrength(0.8, persist: false);
      await windows.setDesktopBackdropStrength(0.8);
      expect(prefs.getDouble('desktop_acrylic_strength'), 0.8);
      expect(prefs.getDouble('desktop_glass_strength'), 1.7);
      windows.dispose();

      final restored = await loadThemeProvider(TargetPlatform.macOS);
      expect(restored.desktopBackdropStrength, 1.7);
      await restored.setDesktopBackdropStrength(0, persist: false);
      await restored.setDesktopBackdropStrength(0);
      restored.dispose();
      final cleared = await loadThemeProvider(TargetPlatform.macOS);
      expect(cleared.desktopBackdropStrength, 0);
      expect(prefs.getDouble('desktop_acrylic_strength'), 0.8);
      cleared.dispose();
    },
  );

  test(
    'macOS startup respects the saved Glass and wallpaper configuration',
    () async {
      SharedPreferences.setMockInitialValues({'desktop_glass_strength': 1.6});
      expect(await ThemeProvider.readInitialMacosGlassStrength(), 1.6);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('acrylic_backdrop_mode', 'wallpaper');
      expect(await ThemeProvider.readInitialMacosGlassStrength(), 0);
      expect(prefs.getDouble('desktop_glass_strength'), 1.6);
    },
  );

  test('Windows does not create or migrate a Glass preference', () async {
    SharedPreferences.setMockInitialValues({'desktop_acrylic_strength': 1.2});
    final windows = await loadThemeProvider(TargetPlatform.windows);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('desktop_glass_strength'), isFalse);
    await windows.setDesktopBackdropStrength(2);
    expect(prefs.getDouble('desktop_acrylic_strength'), 2);
    expect(prefs.containsKey('desktop_glass_strength'), isFalse);
    windows.dispose();
  });

  test('stored and preview Glass strength stay finite and bounded', () async {
    SharedPreferences.setMockInitialValues({'desktop_glass_strength': 12.0});
    final mac = await loadThemeProvider(TargetPlatform.macOS);
    expect(mac.desktopBackdropStrength, 2);
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        'desktop_glass_strength',
      ),
      2,
    );
    await mac.setDesktopBackdropStrength(-3);
    expect(mac.desktopBackdropStrength, 0);
    await mac.setDesktopBackdropStrength(double.nan);
    expect(mac.desktopBackdropStrength, 1);
    mac.dispose();
  });
}
