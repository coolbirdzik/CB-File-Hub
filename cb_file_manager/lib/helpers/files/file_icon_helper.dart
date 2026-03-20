import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'external_app_helper.dart';
import 'windows_app_icon.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import '../../utils/app_logger.dart';

/// Helper class to get file icons, including app icons for file types
class FileIconHelper {
  // Cache for file extensions icons
  static final Map<String, Widget> _iconCache = {};

  // Cache for app paths by extension
  static final Map<String, String> _appPathCache = {};

  /// Get an icon for a file. If possible, return the icon of the default application.
  /// If no default app is found, return an appropriate icon based on file type.
  static Future<Widget> getIconForFile(File file, {double size = 24}) async {
    final String extension = _getFileExtension(file);

    // For APK files, use file-specific cache key to avoid cache conflicts
    final String cacheKey =
        extension == 'apk' ? '${file.path}_$size' : '${extension}_$size';
    AppLogger.debug('APK_ICON_DEBUG:Cache key: $cacheKey');
    AppLogger.debug(
        'APK_ICON_DEBUG:Cache contains key: ${_iconCache.containsKey(cacheKey)}');

    if (_iconCache.containsKey(cacheKey)) {
      AppLogger.debug('APK_ICON_DEBUG:Using cached icon for: $cacheKey');
      final cachedIcon = _iconCache[cacheKey]!;
      AppLogger.debug(
          'APK_ICON_DEBUG:Cached icon type: ${cachedIcon.runtimeType}');
      return cachedIcon;
    }

    AppLogger.debug('APK_ICON_DEBUG:No cached icon for: $cacheKey');

    // For images and videos, return a generic icon
    if (_isImageFile(extension)) {
      final icon =
          Icon(PhosphorIconsLight.image, size: size, color: Colors.blue);
      _iconCache[cacheKey] = icon;
      return icon;
    }

    if (_isVideoFile(extension)) {
      final icon =
          Icon(PhosphorIconsLight.videoCamera, size: size, color: Colors.red);
      _iconCache[cacheKey] = icon;
      return icon;
    }

    // Try to get the application icon for this file type
    try {
      // For APK files on Android, try to get the installed app icon
      if (extension == 'apk' && Platform.isAndroid) {
        AppLogger.debug('APK_ICON_DEBUG:Processing APK file: ${file.path}');

        // Test APK info first
        final testInfo = await ExternalAppHelper.testApkInfo(file.path);
        if (testInfo != null) {
          AppLogger.debug('APK_ICON_DEBUG:Test info: $testInfo');
        }

        final appInfo =
            await ExternalAppHelper.getApkInstalledAppInfo(file.path);
        if (appInfo != null) {
          AppLogger.debug(
              'APK_ICON_DEBUG:Got app info: ${appInfo.appName} (installed: ${appInfo.isInstalled})');
          AppLogger.debug(
              'APK_ICON_DEBUG:App icon type: ${appInfo.icon.runtimeType}');

          // Use the installed app icon
          final Widget appIcon = SizedBox(
            width: size,
            height: size,
            child: appInfo.icon,
          );
          AppLogger.debug(
              'APK_ICON_DEBUG:Created appIcon widget: ${appIcon.runtimeType}');
          _iconCache[cacheKey] = appIcon;
          AppLogger.debug('APK_ICON_DEBUG:Cached appIcon with key: $cacheKey');
          AppLogger.debug('APK_ICON_DEBUG:Returning appIcon widget');
          return appIcon;
        } else {
          AppLogger.debug(
              'APK_ICON_DEBUG:No app info returned for APK, using fallback');
          // Use fallback APK icon
          final Widget fallbackIcon = Icon(
            PhosphorIconsLight.deviceMobile,
            size: size,
            color: Colors.green,
          );
          AppLogger.debug(
              'APK_ICON_DEBUG:Created fallback icon: ${fallbackIcon.runtimeType}');
          _iconCache[cacheKey] = fallbackIcon;
          AppLogger.debug(
              'APK_ICON_DEBUG:Cached fallback icon with key: $cacheKey');
          AppLogger.debug('APK_ICON_DEBUG:Returning fallback icon');
          return fallbackIcon;
        }
      }

      // For other file types or non-Android platforms
      String? appPath;

      // Check cache first
      if (_appPathCache.containsKey(extension)) {
        appPath = _appPathCache[extension];
      } else {
        // Get the default application path for this extension (Windows only)
        if (Platform.isWindows) {
          appPath = await WindowsAppIcon.getAssociatedAppPath(extension);
          if (appPath != null && appPath.isNotEmpty) {
            _appPathCache[extension] = appPath;
          }
        }
      }

      if (appPath != null && appPath.isNotEmpty) {
        // Get the default app info
        final apps = await ExternalAppHelper.getInstalledAppsForFile(file.path);
        if (apps.isNotEmpty) {
          // Use the first app icon
          final Widget appIcon = SizedBox(
            width: size,
            height: size,
            child: apps[0].icon,
          );
          _iconCache[cacheKey] = appIcon;
          return appIcon;
        }
      }
    } catch (e) {
      debugPrint('Error getting app icon: $e');
    }

    // Fallback to generic file type icons using registry
    final iconData = FileTypeRegistry.getIcon('.$extension');
    final iconColor = FileTypeRegistry.getColor('.$extension');

    final icon = Icon(iconData, size: size, color: iconColor);

    if (extension == 'apk') {
      AppLogger.debug(
          'APK_ICON_DEBUG:Created generic APK icon: ${icon.runtimeType}');
    }

    _iconCache[cacheKey] = icon;
    AppLogger.debug('APK_ICON_DEBUG:Cached generic icon with key: $cacheKey');
    AppLogger.debug('APK_ICON_DEBUG:Returning generic icon');
    return icon;
  }

  /// Get the default application icon for a file extension
  static Future<Widget?> getDefaultAppIconForExtension(String extension,
      {double size = 24}) async {
    try {
      // For APK files on Android, try to get the installed app icon
      if (extension == 'apk' && Platform.isAndroid) {
        final tempFile =
            File('temp.$extension'); // Dummy file với extension cần thiết
        final appInfo =
            await ExternalAppHelper.getApkInstalledAppInfo(tempFile.path);
        if (appInfo != null) {
          return SizedBox(
            width: size,
            height: size,
            child: appInfo.icon,
          );
        }
      }

      // For other file types or non-Android platforms
      String? appPath;

      // Check cache first
      if (_appPathCache.containsKey(extension)) {
        appPath = _appPathCache[extension];
      } else {
        // Get the default application path for this extension (Windows only)
        if (Platform.isWindows) {
          appPath = await WindowsAppIcon.getAssociatedAppPath(extension);
          if (appPath != null && appPath.isNotEmpty) {
            _appPathCache[extension] = appPath;
          }
        }
      }

      if (appPath != null && appPath.isNotEmpty) {
        // Sử dụng phương thức public để lấy biểu tượng ứng dụng
        final tempFile =
            File('temp.$extension'); // Dummy file với extension cần thiết
        final apps =
            await ExternalAppHelper.getInstalledAppsForFile(tempFile.path);
        if (apps.isNotEmpty) {
          return SizedBox(
            width: size,
            height: size,
            child: apps[0].icon,
          );
        }
      }
    } catch (e) {
      debugPrint('Error getting default app icon: $e');
    }

    return null;
  }

  /// Clear the icon cache
  static void clearCache() {
    _iconCache.clear();
  }

  /// Clear cache for APK files specifically
  static void clearApkCache() {
    _iconCache.removeWhere((key, value) => key.contains('.apk_'));
  }

  /// Force refresh APK icon (bypass cache)
  static Future<Widget> getApkIconForced(File file, {double size = 24}) async {
    final String cacheKey = '${file.path}_$size';
    _iconCache.remove(cacheKey); // Remove from cache first

    AppLogger.debug(
        'APK_ICON_DEBUG:Force refreshing APK icon for: ${file.path}');
    return await getIconForFile(file, size: size);
  }

  /// Test method to debug APK icon issues
  static Future<void> debugApkIcons() async {
    AppLogger.debug('APK_ICON_DEBUG:=== Starting APK Icon Debug ===');
    AppLogger.debug('APK_ICON_DEBUG:Cache size: ${_iconCache.length}');
    AppLogger.debug('APK_ICON_DEBUG:APK cache entries:');
    _iconCache.forEach((key, value) {
      if (key.contains('.apk')) {
        AppLogger.debug('APK_ICON_DEBUG:  $key -> ${value.runtimeType}');
      }
    });

    // Clear all APK cache
    clearApkCache();
    AppLogger.debug('APK_ICON_DEBUG:Cleared APK cache');
    AppLogger.debug('APK_ICON_DEBUG:New cache size: ${_iconCache.length}');

    // Test creating a simple APK icon
    AppLogger.debug('APK_ICON_DEBUG:Testing simple APK icon creation...');
    const testIcon = Icon(
      PhosphorIconsLight.deviceMobile,
      size: 24,
      color: Colors.green,
    );
    AppLogger.debug(
        'APK_ICON_DEBUG:Test icon created: ${testIcon.runtimeType}');

    // Force clear all cache
    _iconCache.clear();
    AppLogger.debug('APK_ICON_DEBUG:Cleared ALL cache');
    AppLogger.debug('APK_ICON_DEBUG:Final cache size: ${_iconCache.length}');

    AppLogger.debug('APK_ICON_DEBUG:=== End APK Icon Debug ===');
  }

  // Helper methods to identify file types using FileTypeRegistry
  static String _getFileExtension(File file) {
    final fileName = file.path.split('/').last.split('\\').last;
    final lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex == -1) return '';
    return fileName.substring(lastDotIndex).toLowerCase();
  }

  static bool _isImageFile(String extension) {
    return FileTypeRegistry.isCategory(extension, FileCategory.image);
  }

  static bool _isVideoFile(String extension) {
    return FileTypeRegistry.isCategory(extension, FileCategory.video);
  }
}
