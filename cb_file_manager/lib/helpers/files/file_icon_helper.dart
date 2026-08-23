import 'dart:io';
import 'dart:typed_data';
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

  static Future<String?> _defaultWindowsHandlerForExtension(
      String extension) async {
    final dottedExt = extension.startsWith('.') ? extension : '.$extension';
    final appPath = await WindowsAppIcon.getAssociatedAppPath(dottedExt);
    if (appPath != null && appPath.isNotEmpty && File(appPath).existsSync()) {
      return appPath;
    }
    return null;
  }

  static Future<Widget?> _windowsIconFromAppPath(String appPath, double size) async {
    if (appPath.isEmpty || !File(appPath).existsSync()) return null;
    final nativeIcon = await WindowsAppIcon.extractIconFromFile(appPath);
    if (nativeIcon == null) return null;
    return SizedBox(
      width: size,
      height: size,
      child: RawImage(
        image: nativeIcon,
        fit: BoxFit.contain,
      ),
    );
  }

  // ─── Extension-keyed icon cache (batch-warmed, sync lookup) ───────────────
  /// Stores pre-rendered icon widgets keyed by "${extension}_$size".
  static final Map<String, Widget> _extensionIconCache = {};

  /// Track in-flight warmup to avoid duplicate batch calls.
  static Future<void>? _warmupFuture;

  /// Pre-warm icon cache for all extensions visible in the current list.
  /// Call once after listing arrives, before items render.
  /// Safe to call multiple times — only fetches missing extensions.
  static Future<void> warmExtensionIcons(Set<String> extensions,
      {int size = 32}) async {
    if (!Platform.isWindows) return;

    // Filter to only non-media extensions that aren't already cached
    final missing = extensions.where((ext) {
      if (ext.isEmpty) return false;
      final normalizedExt = ext.startsWith('.') ? ext : '.$ext';
      final category = FileTypeRegistry.getCategory(normalizedExt);
      if (category == FileCategory.image || category == FileCategory.video) {
        return false;
      }
      return !_extensionIconCache.containsKey('${ext}_$size');
    }).toList();

    if (missing.isEmpty) return;

    // Avoid duplicate concurrent warmups
    _warmupFuture = _doWarmup(missing, size);
    await _warmupFuture;
    _warmupFuture = null;
  }

  static Future<void> _doWarmup(List<String> extensions, int size) async {
    try {
      final raw = await WindowsAppIcon.extractIconsForExtensions(
        extensions,
        iconSize: size,
      );
      for (final entry in raw.entries) {
        final pixels = entry.value;
        if (pixels != null && pixels.isNotEmpty) {
          final widget = _buildIconWidgetFromPixels(pixels, size);
          if (widget != null) {
            _extensionIconCache['${entry.key}_$size'] = widget;
          }
        }
      }
    } catch (e) {
      // Silently fail — fallback icons will be used
    }
  }

  /// Build a widget from RGBA pixel data by encoding to BMP in memory.
  /// Uses Image.memory which Flutter manages (no manual dispose needed).
  static Widget? _buildIconWidgetFromPixels(Uint8List rgbaPixels, int size) {
    // Determine dimensions from pixel count (square icon assumed from native)
    final int pixelCount = rgbaPixels.length ~/ 4;
    final int dim = _sqrt(pixelCount);
    if (dim * dim != pixelCount) return null;

    // Encode as 32-bit BMP (BGRA, bottom-up) — fast, no compression overhead
    final bmpBytes = _encodeBmp32(rgbaPixels, dim, dim);

    return SizedBox(
      width: size.toDouble(),
      height: size.toDouble(),
      child: Image.memory(
        bmpBytes,
        width: size.toDouble(),
        height: size.toDouble(),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        // Prevent Flutter from caching these separately in ImageCache
        cacheWidth: dim,
        cacheHeight: dim,
      ),
    );
  }

  /// Encode RGBA pixels as a 32-bit BMP (with alpha channel).
  /// BMP is trivial to encode and Flutter's image decoder handles it natively.
  static Uint8List _encodeBmp32(Uint8List rgbaPixels, int width, int height) {
    final int rowSize = width * 4; // No padding needed for 32-bit
    final int imageSize = rowSize * height;
    final int fileSize =
        54 + imageSize; // 14 (file header) + 40 (DIB header) + pixels

    final ByteData bmp = ByteData(fileSize);

    // BMP File Header (14 bytes)
    bmp.setUint8(0, 0x42); // 'B'
    bmp.setUint8(1, 0x4D); // 'M'
    bmp.setUint32(2, fileSize, Endian.little);
    bmp.setUint32(6, 0, Endian.little); // reserved
    bmp.setUint32(10, 54, Endian.little); // pixel data offset

    // DIB Header (BITMAPINFOHEADER, 40 bytes)
    bmp.setUint32(14, 40, Endian.little); // header size
    bmp.setInt32(18, width, Endian.little);
    bmp.setInt32(22, -height, Endian.little); // negative = top-down
    bmp.setUint16(26, 1, Endian.little); // color planes
    bmp.setUint16(28, 32, Endian.little); // bits per pixel
    bmp.setUint32(30, 0, Endian.little); // compression (BI_RGB)
    bmp.setUint32(34, imageSize, Endian.little);
    bmp.setUint32(38, 2835, Endian.little); // horizontal resolution (72 DPI)
    bmp.setUint32(42, 2835, Endian.little); // vertical resolution
    bmp.setUint32(46, 0, Endian.little); // colors in palette
    bmp.setUint32(50, 0, Endian.little); // important colors

    // Pixel data: convert RGBA → BGRA (BMP native order)
    final Uint8List bmpBytes = bmp.buffer.asUint8List();
    int offset = 54;
    for (int i = 0; i < rgbaPixels.length; i += 4) {
      bmpBytes[offset] = rgbaPixels[i + 2]; // B
      bmpBytes[offset + 1] = rgbaPixels[i + 1]; // G
      bmpBytes[offset + 2] = rgbaPixels[i]; // R
      bmpBytes[offset + 3] = rgbaPixels[i + 3]; // A
      offset += 4;
    }

    return bmpBytes;
  }

  /// Integer square root helper.
  static int _sqrt(int n) {
    if (n <= 0) return 0;
    int x = n;
    int y = (x + 1) ~/ 2;
    while (y < x) {
      x = y;
      y = (x + n ~/ x) ~/ 2;
    }
    return x;
  }

  /// Synchronous lookup — never triggers async work during scroll.
  /// Returns null on cache miss (caller should use fallback phosphor icon).
  static Widget? getExtensionIconSync(String extension, {int size = 32}) {
    return _extensionIconCache['${extension}_$size'];
  }

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
      } else if (Platform.isWindows) {
        appPath = await _defaultWindowsHandlerForExtension(extension);
        if (appPath != null && appPath.isNotEmpty) {
          _appPathCache[extension] = appPath;
        }
      }

      if (appPath != null && appPath.isNotEmpty) {
        final appIcon = await _windowsIconFromAppPath(appPath, size);
        if (appIcon != null) {
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
      } else if (Platform.isWindows) {
        appPath = await _defaultWindowsHandlerForExtension(extension);
        if (appPath != null && appPath.isNotEmpty) {
          _appPathCache[extension] = appPath;
        }
      }

      if (appPath != null && appPath.isNotEmpty) {
        return _windowsIconFromAppPath(appPath, size);
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
