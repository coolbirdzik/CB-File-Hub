import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PlatformPaths {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// Get the appropriate Pictures directory for the current platform
  static Future<String> getPicturesPath() async {
    if (Platform.isWindows) {
      // Windows: Use Pictures folder
      final documentsDir = await getApplicationDocumentsDirectory();
      final picturesPath = '${documentsDir.parent.path}\\Pictures';
      return picturesPath;
    } else if (Platform.isMacOS) {
      // macOS: Use Pictures folder
      final homeDir = Platform.environment['HOME'] ?? '';
      return '$homeDir/Pictures';
    } else if (Platform.isLinux) {
      // Linux: Use Pictures folder
      final homeDir = Platform.environment['HOME'] ?? '';
      return '$homeDir/Pictures';
    } else if (Platform.isAndroid) {
      // Android: Use DCIM and Pictures
      return '/storage/emulated/0/Pictures';
    } else if (Platform.isIOS) {
      // iOS: Use app documents directory
      final documentsDir = await getApplicationDocumentsDirectory();
      return documentsDir.path;
    }

    // Fallback
    final documentsDir = await getApplicationDocumentsDirectory();
    return documentsDir.path;
  }

  /// Get the appropriate Downloads directory for the current platform
  static Future<String> getDownloadsPath() async {
    if (Platform.isWindows) {
      // Windows: Use Downloads folder
      final documentsDir = await getApplicationDocumentsDirectory();
      final downloadsPath = '${documentsDir.parent.path}\\Downloads';
      return downloadsPath;
    } else if (Platform.isMacOS) {
      // macOS: Use Downloads folder
      final homeDir = Platform.environment['HOME'] ?? '';
      return '$homeDir/Downloads';
    } else if (Platform.isLinux) {
      // Linux: Use Downloads folder
      final homeDir = Platform.environment['HOME'] ?? '';
      return '$homeDir/Downloads';
    } else if (Platform.isAndroid) {
      // Android: Use Download folder
      return '/storage/emulated/0/Download';
    } else if (Platform.isIOS) {
      // iOS: Use app documents directory (iOS doesn't have a Downloads folder)
      final documentsDir = await getApplicationDocumentsDirectory();
      return documentsDir.path;
    }

    // Fallback
    final documentsDir = await getApplicationDocumentsDirectory();
    return documentsDir.path;
  }

  /// Get the appropriate Camera photos directory for the current platform
  static Future<String> getCameraPath() async {
    if (Platform.isWindows) {
      // Windows: Use Pictures folder (no specific camera folder)
      final documentsDir = await getApplicationDocumentsDirectory();
      final picturesPath = '${documentsDir.parent.path}\\Pictures';
      return picturesPath;
    } else if (Platform.isMacOS) {
      // macOS: Use Pictures folder
      final homeDir = Platform.environment['HOME'] ?? '';
      return '$homeDir/Pictures';
    } else if (Platform.isLinux) {
      // Linux: Use Pictures folder
      final homeDir = Platform.environment['HOME'] ?? '';
      return '$homeDir/Pictures';
    } else if (Platform.isAndroid) {
      // Android: Use DCIM/Camera
      return '/storage/emulated/0/DCIM/Camera';
    } else if (Platform.isIOS) {
      // iOS: Use app documents directory
      final documentsDir = await getApplicationDocumentsDirectory();
      return documentsDir.path;
    }

    // Fallback
    final documentsDir = await getApplicationDocumentsDirectory();
    return documentsDir.path;
  }

  /// Get the appropriate root directory for "All Images"
  static Future<String> getAllImagesPath() async {
    if (Platform.isWindows) {
      // Windows: Use Pictures folder as root
      final documentsDir = await getApplicationDocumentsDirectory();
      final picturesPath = '${documentsDir.parent.path}\\Pictures';
      return picturesPath;
    } else if (Platform.isMacOS) {
      // macOS: Use Pictures folder
      final homeDir = Platform.environment['HOME'] ?? '';
      return '$homeDir/Pictures';
    } else if (Platform.isLinux) {
      // Linux: Use Pictures folder
      final homeDir = Platform.environment['HOME'] ?? '';
      return '$homeDir/Pictures';
    } else if (Platform.isAndroid) {
      // Android: Use storage root
      return '/storage/emulated/0';
    } else if (Platform.isIOS) {
      // iOS: Use app documents directory
      final documentsDir = await getApplicationDocumentsDirectory();
      return documentsDir.path;
    }

    // Fallback
    final documentsDir = await getApplicationDocumentsDirectory();
    return documentsDir.path;
  }

  /// Get platform-specific display names
  static String getCameraDisplayName() {
    if (isDesktop) {
      return 'Pictures';
    } else {
      return 'Camera Photos';
    }
  }

  static String getDownloadsDisplayName() {
    return 'Downloads';
  }

  static String getAllImagesDisplayName() {
    if (isDesktop) {
      return 'All Pictures';
    } else {
      return 'All Images';
    }
  }
}
