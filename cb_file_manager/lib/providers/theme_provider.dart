import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme_config.dart';
import '../config/fluent_theme_config.dart';
import '../services/windowing/system_wallpaper_service.dart';

/// Backdrop mode for acrylic effects.
enum AcrylicBackdropMode {
  /// Uses the system native acrylic / mica backdrop (dynamic, transparent).
  dynamic,

  /// Uses the system desktop wallpaper as the backdrop behind the app.
  wallpaper,
}

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'app_theme';
  static const String _accentColorKey = 'app_accent_color';
  static const String _desktopAcrylicStrengthKey = 'desktop_acrylic_strength';
  static const String _backdropModeKey = 'acrylic_backdrop_mode';
  static const String _backdropImagePathKey = 'acrylic_backdrop_image_path';
  static const double _defaultDesktopAcrylicStrength = 1.00;
  static const double _minimumDesktopAcrylicStrength = 0.0;

  AppThemeType _currentTheme = AppThemeType.light;
  AppAccentColor _currentAccentColor = ThemeConfig.defaultAccentColor;
  double _desktopAcrylicStrength = _defaultDesktopAcrylicStrength;
  AcrylicBackdropMode _backdropMode = AcrylicBackdropMode.dynamic;
  String? _backdropImagePath;

  AppThemeType get currentTheme => _currentTheme;
  AppAccentColor get currentAccentColor => _currentAccentColor;
  double get desktopAcrylicStrength => _desktopAcrylicStrength;
  AcrylicBackdropMode get backdropMode => _backdropMode;
  String? get backdropImagePath => _backdropImagePath;
  bool get isWallpaperMode => _backdropMode == AcrylicBackdropMode.wallpaper;
  ThemeData get themeData => ThemeConfig.getTheme(
        _currentTheme,
        accentColor: _currentAccentColor,
      );
  fluent.FluentThemeData get fluentThemeData => FluentThemeConfig.getTheme(
        _currentTheme,
        accentColor: _currentAccentColor,
        acrylicStrength: _desktopAcrylicStrength,
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

  ThemeData get lightTheme => ThemeConfig.lightTheme;
  ThemeData get darkTheme => ThemeConfig.darkTheme;

  ThemeProvider() {
    _loadTheme();
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
    final acrylicStrength = prefs.getDouble(_desktopAcrylicStrengthKey) ??
        _defaultDesktopAcrylicStrength;
    final backdropModeStr = prefs.getString(_backdropModeKey);
    final backdropImagePath = prefs.getString(_backdropImagePathKey);

    _currentTheme = _parseStoredTheme(themeString);
    _currentAccentColor = AppAccentColor.values.firstWhere(
      (accent) => accent.name == accentString,
      orElse: () => ThemeConfig.defaultAccentColor,
    );
    _desktopAcrylicStrength =
        acrylicStrength.clamp(_minimumDesktopAcrylicStrength, 2.0).toDouble();
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

  Future<void> setDesktopAcrylicStrength(
    double strength, {
    bool persist = true,
  }) async {
    final normalized =
        strength.clamp(_minimumDesktopAcrylicStrength, 2.0).toDouble();
    if (_desktopAcrylicStrength == normalized) return;

    _desktopAcrylicStrength = normalized;
    notifyListeners();

    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_desktopAcrylicStrengthKey, _desktopAcrylicStrength);
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
