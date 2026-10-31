import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/providers/theme_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup can await saved appearance before building its first frame',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_theme': 'dark',
        'acrylic_backdrop_mode': 'wallpaper',
        'acrylic_backdrop_image_path': 'C:/wallpaper.png',
        'desktop_acrylic_strength': 0.6,
      });
      final provider = ThemeProvider(platform: TargetPlatform.windows);
      await provider.ready;

      expect(provider.currentTheme, AppThemeType.dark);
      expect(provider.isWallpaperMode, isTrue);
      expect(provider.backdropImagePath, 'C:/wallpaper.png');
      expect(provider.desktopBackdropStrength, 0.6);
      provider.dispose();
    },
  );
}
