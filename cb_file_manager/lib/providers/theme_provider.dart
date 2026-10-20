import 'package:flutter/foundation.dart';
import '../design_system/macos_glass_theme.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme_config.dart';
import '../config/fluent_theme_config.dart';
import '../services/windowing/system_wallpaper_service.dart';

/// Backdrop source for platform-specific desktop materials.
enum AcrylicBackdropMode {
  /// Uses the system native acrylic / mica backdrop (dynamic, transparent).
  dynamic,

  /// Uses the system desktop wallpaper as the backdrop behind the app.
  wallpaper,
}

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'app_theme';
  static const String _accentColorKey = 'app_accent_color';
  static const String _fontColorKey = 'app_font_color';
  static const String _uiFontKey = 'app_ui_font';
  static const String _desktopAcrylicStrengthKey = 'desktop_acrylic_strength';
  static const String _desktopGlassStrengthKey = 'desktop_glass_strength';
  static const String _desktopGlassBlurStrengthKey =
      'desktop_glass_blur_strength';
  static const String _backdropModeKey = 'acrylic_backdrop_mode';
  static const String _backdropImagePathKey = 'acrylic_backdrop_image_path';
  static const double _defaultDesktopAcrylicStrength = 1.00;
  final TargetPlatform platform;

  AppThemeType _currentTheme = AppThemeType.light;
  AppAccentColor _currentAccentColor = ThemeConfig.defaultAccentColor;
  AppFontColor _currentFontColor = ThemeConfig.defaultFontColor;
  AppUiFont _currentUiFont = ThemeConfig.defaultUiFont;
  double _desktopAcrylicStrength = _defaultDesktopAcrylicStrength;
  double _desktopGlassStrength = _defaultDesktopAcrylicStrength;
  double _desktopGlassBlurStrength = 1;
  AcrylicBackdropMode _backdropMode = AcrylicBackdropMode.dynamic;
  String? _backdropImagePath;

  AppThemeType get currentTheme => _currentTheme;
  AppAccentColor get currentAccentColor => _currentAccentColor;
  AppFontColor get currentFontColor => _currentFontColor;
  AppUiFont get currentUiFont => _currentUiFont;
  double get desktopAcrylicStrength => _desktopAcrylicStrength;
  bool get usesMacosGlass => platform == TargetPlatform.macOS;
  double get desktopGlassStrength => _desktopGlassStrength;
  double get desktopGlassBlurStrength => _desktopGlassBlurStrength;
  double get desktopBackdropStrength =>
      usesMacosGlass ? _desktopGlassStrength : _desktopAcrylicStrength;
  AcrylicBackdropMode get backdropMode => _backdropMode;
  String? get backdropImagePath => _backdropImagePath;
  bool get isWallpaperMode => _backdropMode == AcrylicBackdropMode.wallpaper;
  ThemeData get themeData => ThemeConfig.getTheme(
    _currentTheme,
    accentColor: _currentAccentColor,
    fontColor: _currentFontColor,
    uiFont: _currentUiFont,
  );
  fluent.FluentThemeData get fluentThemeData => FluentThemeConfig.getTheme(
    _currentTheme,
    accentColor: _currentAccentColor,
    fontColor: _currentFontColor,
    uiFont: _currentUiFont,
    acrylicStrength: desktopBackdropStrength,
    glassBlurStrength: desktopGlassBlurStrength,
    platform: platform,
    preferTransparentBackdrop: _backdropMode == AcrylicBackdropMode.dynamic,
  );

  // For backward compatibility
  ThemeMode get themeMode {
    switch (_currentTheme) {
      case AppThemeType.light:
        return ThemeMode.light;
      case AppThemeType.dark:
        return ThemeMode.dark;
    }
  }

  bool get isDarkMode => themeMode == ThemeMode.dark;

  ThemeProvider({TargetPlatform? platform})
    : platform = platform ?? defaultTargetPlatform {
    _loadTheme();
  }

  static double _readGlassStrength(SharedPreferences prefs) =>
      MacosGlassTheme.normalizeStrength(
        prefs.getDouble(_desktopGlassStrengthKey) ??
            prefs.getDouble(_desktopAcrylicStrengthKey) ??
            _defaultDesktopAcrylicStrength,
      );

  /// Apply the saved macOS appearance before the first Flutter frame.
  static Future<double> readInitialMacosGlassStrength() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_backdropModeKey) ==
        AcrylicBackdropMode.wallpaper.name) {
      return 0;
    }
    return _readGlassStrength(prefs);
  }

  AppThemeType _parseStoredTheme(String rawTheme) {
    switch (rawTheme.trim().toLowerCase()) {
      case 'dark':
      case 'amoled':
        return AppThemeType.dark;
      case 'light':
      case 'blue':
      case 'green':
      case 'purple':
      case 'orange':
      default:
        return AppThemeType.light;
    }
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString(_themeKey) ?? 'light';
    final accentString =
        prefs.getString(_accentColorKey) ?? ThemeConfig.defaultAccentColor.name;
    final fontColorString =
        prefs.getString(_fontColorKey) ?? ThemeConfig.defaultFontColor.name;
    final uiFontString =
        prefs.getString(_uiFontKey) ?? ThemeConfig.defaultUiFont.name;
    final acrylicStrength =
        prefs.getDouble(_desktopAcrylicStrengthKey) ??
        _defaultDesktopAcrylicStrength;
    final backdropModeStr = prefs.getString(_backdropModeKey);
    final backdropImagePath = prefs.getString(_backdropImagePathKey);

    _currentTheme = _parseStoredTheme(themeString);
    _currentAccentColor = AppAccentColor.values.firstWhere(
      (accent) => accent.name == accentString,
      orElse: () => ThemeConfig.defaultAccentColor,
    );
    _currentFontColor = AppFontColor.values.firstWhere(
      (fontColor) => fontColor.name == fontColorString,
      orElse: () => ThemeConfig.defaultFontColor,
    );
    _currentUiFont = AppUiFont.values.firstWhere(
      (uiFont) => uiFont.name == uiFontString,
      orElse: () => ThemeConfig.defaultUiFont,
    );
    _desktopAcrylicStrength = MacosGlassTheme.normalizeStrength(
      acrylicStrength,
    );
    // Seed the new macOS preference from the previous shared control once.
    // Subsequent glass changes never overwrite the Windows acrylic setting.
    final storedGlassStrength = prefs.getDouble(_desktopGlassStrengthKey);
    _desktopGlassStrength = _readGlassStrength(prefs);
    _desktopGlassBlurStrength = MacosGlassTheme.normalizeStrength(
      prefs.getDouble(_desktopGlassBlurStrengthKey) ?? 1,
    );
    if (usesMacosGlass && storedGlassStrength != _desktopGlassStrength) {
      await prefs.setDouble(_desktopGlassStrengthKey, _desktopGlassStrength);
    }
    _backdropMode = backdropModeStr == AcrylicBackdropMode.wallpaper.name
        ? AcrylicBackdropMode.wallpaper
        : AcrylicBackdropMode.dynamic;
    _backdropImagePath = backdropImagePath;

    notifyListeners();

    // Auto-load system wallpaper if in wallpaper mode and no custom image set
    if (_backdropMode == AcrylicBackdropMode.wallpaper &&
        (_backdropImagePath == null || _backdropImagePath!.isEmpty)) {
      _loadSystemWallpaper();
    }
  }

  Future<void> setTheme(AppThemeType theme) async {
    _currentTheme = theme;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme.name);
  }

  Future<void> setAccentColor(
    AppAccentColor accentColor, {
    bool persist = true,
  }) async {
    if (_currentAccentColor == accentColor) return;
    _currentAccentColor = accentColor;
    notifyListeners();

    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentColorKey, accentColor.name);
  }

  Future<void> setFontColor(
    AppFontColor fontColor, {
    bool persist = true,
  }) async {
    if (_currentFontColor == fontColor) return;
    _currentFontColor = fontColor;
    notifyListeners();

    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontColorKey, fontColor.name);
  }

  Future<void> setUiFont(AppUiFont uiFont, {bool persist = true}) async {
    if (_currentUiFont == uiFont) return;
    _currentUiFont = uiFont;
    notifyListeners();

    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uiFontKey, uiFont.name);
  }

  // Legacy method for backward compatibility
  Future<void> setThemeMode(ThemeMode themeMode) async {
    switch (themeMode) {
      case ThemeMode.light:
        await setTheme(AppThemeType.light);
        break;
      case ThemeMode.dark:
        await setTheme(AppThemeType.dark);
        break;
      case ThemeMode.system:
        await setTheme(AppThemeType.light);
        break;
    }
  }

  Future<void> toggleTheme() async {
    if (_currentTheme == AppThemeType.light) {
      await setTheme(AppThemeType.dark);
    } else {
      await setTheme(AppThemeType.light);
    }
  }

  Future<void> setDesktopBackdropStrength(
    double strength, {
    bool persist = true,
  }) => _setDesktopStrength(strength, glass: usesMacosGlass, persist: persist);

  Future<void> setDesktopAcrylicStrength(
    double strength, {
    bool persist = true,
  }) => _setDesktopStrength(strength, glass: false, persist: persist);

  Future<void> setDesktopGlassStrength(
    double strength, {
    bool persist = true,
  }) => _setDesktopStrength(strength, glass: true, persist: persist);

  Future<void> _setDesktopStrength(
    double strength, {
    required bool glass,
    required bool persist,
  }) async {
    final normalized = MacosGlassTheme.normalizeStrength(strength);
    final current = glass ? _desktopGlassStrength : _desktopAcrylicStrength;
    if (current != normalized) {
      if (glass) {
        _desktopGlassStrength = normalized;
      } else {
        _desktopAcrylicStrength = normalized;
      }
      notifyListeners();
    }

    await _saveDesktopValue(
      glass ? _desktopGlassStrengthKey : _desktopAcrylicStrengthKey,
      normalized,
      persist,
    );
  }

  Future<void> setDesktopGlassBlurStrength(
    double strength, {
    bool persist = true,
  }) async {
    final normalized = MacosGlassTheme.normalizeStrength(strength);
    if (_desktopGlassBlurStrength != normalized) {
      _desktopGlassBlurStrength = normalized;
      notifyListeners();
    }
    await _saveDesktopValue(_desktopGlassBlurStrengthKey, normalized, persist);
  }

  Future<void> _saveDesktopValue(String key, double value, bool persist) async {
    // Release commits the previewed value even when it is already on screen.
    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> setBackdropMode(AcrylicBackdropMode mode) async {
    if (_backdropMode == mode) return;
    _backdropMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backdropModeKey, mode.name);

    // When switching to wallpaper mode, auto-load system wallpaper
    if (mode == AcrylicBackdropMode.wallpaper &&
        (_backdropImagePath == null || _backdropImagePath!.isEmpty)) {
      await _loadSystemWallpaper();
    }
  }

  /// Fetches the system desktop wallpaper and sets it as the backdrop image.
  Future<void> _loadSystemWallpaper() async {
    final path = await SystemWallpaperService.getWallpaperPath();
    if (path != null && path.isNotEmpty) {
      _backdropImagePath = path;
      notifyListeners();
    }
  }

  /// Manually refresh the system wallpaper (e.g. if user changed their desktop
  /// wallpaper and wants the app to pick up the new one).
  Future<void> refreshSystemWallpaper() async {
    final path = await SystemWallpaperService.getWallpaperPath();
    if (path != null && path.isNotEmpty && path != _backdropImagePath) {
      _backdropImagePath = path;
      notifyListeners();
    }
  }

  Future<void> setBackdropImagePath(String? path) async {
    if (_backdropImagePath == path) return;
    _backdropImagePath = path;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_backdropImagePathKey);
    } else {
      await prefs.setString(_backdropImagePathKey, path);
    }
  }
}
