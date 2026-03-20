import 'dart:io';

import 'package:flutter/foundation.dart';

/// Service to retrieve the current desktop wallpaper path.
class SystemWallpaperService {
  const SystemWallpaperService._();

  /// Returns the path to the current desktop wallpaper image,
  /// or `null` if it cannot be determined.
  static Future<String?> getWallpaperPath() async {
    if (Platform.isWindows) {
      return _getWindowsWallpaper();
    }
    // macOS / Linux support can be added later.
    return null;
  }

  /// Reads the Windows desktop wallpaper path from the registry.
  static Future<String?> _getWindowsWallpaper() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Control Panel\Desktop',
        '/v',
        'Wallpaper',
      ]);
      if (result.exitCode != 0) return null;
      final output = result.stdout as String;
      // Output format:
      //     Wallpaper    REG_SZ    C:\Users\...\wallpaper.jpg
      final match =
          RegExp(r'Wallpaper\s+REG_SZ\s+(.+)').firstMatch(output.trim());
      if (match == null) return null;
      final path = match.group(1)?.trim();
      if (path == null || path.isEmpty) return null;
      // Verify the file exists
      if (!File(path).existsSync()) {
        debugPrint('SystemWallpaperService: wallpaper file not found: $path');
        return null;
      }
      return path;
    } catch (e) {
      debugPrint('SystemWallpaperService: failed to read wallpaper: $e');
      return null;
    }
  }
}
