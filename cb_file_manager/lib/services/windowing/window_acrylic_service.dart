import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../config/design_system_config.dart';
import '../../design_system/macos_glass_theme.dart';
import 'windows_native_tab_drag_drop_service.dart';

/// Native desktop backdrop routing: Windows Acrylic and macOS Glass.
class WindowAcrylicService {
  final TargetPlatform _platform;

  WindowAcrylicService({TargetPlatform? platform})
    : _platform = platform ?? defaultTargetPlatform;
  static const _macosWindow = MethodChannel('cb_file_manager/macos_window');

  static Future<void> disableMacosBackground({required bool isDarkMode}) async {
    if (!Platform.isMacOS) return;
    await _macosWindow.invokeMethod<void>('setGlassBackground', {
      'enabled': false,
      'dark': isDarkMode,
    });
  }

  bool get _supportsAcrylicPlatform =>
      _platform == TargetPlatform.windows ||
      _platform == TargetPlatform.linux ||
      _platform == TargetPlatform.macOS;

  bool _isWindows10() {
    if (_platform != TargetPlatform.windows || !Platform.isWindows) {
      return false;
    }
    final os = Platform.operatingSystemVersion.toLowerCase();
    return os.contains('windows 10');
  }

  Future<void> applyDesktopAcrylicBackground({
    required bool isDesktopPlatform,
    required bool isPipWindow,
    required bool isDarkMode,
    double strength = 1.0,
  }) async {
    if (!DesignSystemConfig.enableDesktopAcrylicWindowBackground) {
      debugPrint('[WindowAcrylic] Skipped: feature flag disabled');
      return;
    }
    if (!isDesktopPlatform || isPipWindow) return;
    if (!_supportsAcrylicPlatform) return;

    if (_isWindows10() && !DesignSystemConfig.keepAcrylicOnWindows10) {
      debugPrint(
        '[WindowAcrylic] Skipped: Windows 10 and feature flag disables it',
      );
      return;
    }

    if (_platform == TargetPlatform.macOS) {
      final glassStrength = MacosGlassTheme.normalizeStrength(strength);
      await _macosWindow.invokeMethod<void>('setGlassBackground', {
        'enabled': glassStrength > 0,
        'strength': glassStrength,
        'dark': isDarkMode,
      });
    } else if (_platform == TargetPlatform.windows) {
      try {
        await WindowsNativeTabDragDropService.setWindowsSystemBackdrop(
          enabled: true,
          preferAcrylic: true,
          isDarkMode: isDarkMode,
        );
      } on MissingPluginException catch (e) {
        debugPrint(
          '[WindowAcrylic] MissingPluginException: native plugin not available. '
          'Ensure the Windows plugin is built. Details: $e',
        );
      } catch (e) {
        debugPrint('[WindowAcrylic] Error applying native backdrop: $e');
      }
    }
  }
}
