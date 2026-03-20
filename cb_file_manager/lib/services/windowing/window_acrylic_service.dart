import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/design_system_config.dart';
import 'windows_native_tab_drag_drop_service.dart';

/// Acrylic service entry point.
///
/// Applies desktop window acrylic backdrop using platform-native APIs.
class WindowAcrylicService {
  bool get _supportsAcrylicPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool _isWindows10() {
    if (!Platform.isWindows) return false;
    final os = Platform.operatingSystemVersion.toLowerCase();
    return os.contains('windows 10');
  }

  Future<void> applyDesktopAcrylicBackground({
    required bool isDesktopPlatform,
    required bool isPipWindow,
    required bool isDarkMode,
  }) async {
    if (!DesignSystemConfig.enableDesktopAcrylicWindowBackground) {
      debugPrint('[WindowAcrylic] Skipped: feature flag disabled');
      return;
    }
    if (!isDesktopPlatform || isPipWindow) return;
    if (!_supportsAcrylicPlatform) return;

    if (_isWindows10() && !DesignSystemConfig.keepAcrylicOnWindows10) {
      debugPrint('[WindowAcrylic] Skipped: Windows 10 and feature flag disables it');
      return;
    }

    if (Platform.isWindows) {
      try {
        await WindowsNativeTabDragDropService.setWindowsSystemBackdrop(
          enabled: true,
          preferAcrylic: true,
          isDarkMode: isDarkMode,
        );
      } on MissingPluginException catch (e) {
        debugPrint('[WindowAcrylic] MissingPluginException: native plugin not available. '
            'Ensure the Windows plugin is built. Details: $e');
      } catch (e) {
        debugPrint('[WindowAcrylic] Error applying native backdrop: $e');
      }
    }
  }
}
