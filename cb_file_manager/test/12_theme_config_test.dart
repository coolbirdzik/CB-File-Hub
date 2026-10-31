import 'package:cb_file_manager/config/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('base themes are reused and appearance changes stay distinct', () {
    final base = ThemeConfig.getLightTheme();
    expect(identical(base, ThemeConfig.getLightTheme()), isTrue);
    final dark = ThemeConfig.getDarkTheme();
    expect(identical(dark, ThemeConfig.getDarkTheme()), isTrue);
    expect(dark.brightness, Brightness.dark);
    final green = ThemeConfig.getLightTheme(accentColor: AppAccentColor.green);
    expect(green.colorScheme.primary, isNot(base.colorScheme.primary));
    final redText = ThemeConfig.getLightTheme(fontColor: AppFontColor.red);
    expect(redText.colorScheme.onSurface, isNot(base.colorScheme.onSurface));
  });

  test('base theme cache preserves platform-specific defaults', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final windows = ThemeConfig.getLightTheme();
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final macos = ThemeConfig.getLightTheme();
    expect(windows.platform, TargetPlatform.windows);
    expect(macos.platform, TargetPlatform.macOS);
  });

  test('12.01 addressBarFillColor respects brightness', () {
    expect(
      ThemeConfig.addressBarFillColorFor(Brightness.light),
      Colors.black.withValues(alpha: 0.07),
    );
    expect(
      ThemeConfig.addressBarFillColorFor(Brightness.dark),
      Colors.white.withValues(alpha: 0.10),
    );
  });
}
