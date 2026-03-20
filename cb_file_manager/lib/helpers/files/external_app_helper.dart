import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'windows_app_icon.dart';
import 'dart:ui' as ui;
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import '../core/user_preferences.dart';

class AppInfo {
  final String packageName;
  final String appName;
  final Widget icon;
  final bool isInstalled;

  AppInfo({
    required this.packageName,
    required this.appName,
    required this.icon,
    this.isInstalled = false,
  });
}

class ExternalAppHelper {
  static const MethodChannel _channel =
      MethodChannel('cb_file_manager/external_apps');

  /// Cache for Windows app icons
  static final Map<String, Widget> _windowsAppIconCache = {};

  /// Get list of installed apps that can handle this file type
  static Future<List<AppInfo>> getInstalledAppsForFile(String filePath) async {
    if (Platform.isAndroid) {
      return _getAndroidAppsForFile(filePath);
    } else if (Platform.isWindows) {
      return _getWindowsAppsForFile(filePath);
    }
    return [];
  }

  /// Test APK info for debugging
  static Future<Map<String, dynamic>?> testApkInfo(String filePath) async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod('testApkInfo', {
        'filePath': filePath,
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Error testing APK info: $e');
      return null;
    }
  }

  /// Get installed app info for APK file (shows the actual app icon if installed)
  static Future<AppInfo?> getApkInstalledAppInfo(String filePath) async {
    if (!Platform.isAndroid) {
      debugPrint('APK_DEBUG: Not Android platform');
      return null;
    }

    debugPrint('APK_DEBUG: Getting APK info for: $filePath');

    try {
      final result = await _channel.invokeMethod('getApkInstalledAppInfo', {
        'filePath': filePath,
      });

      debugPrint('APK_DEBUG: Native result: $result');

      if (result == null) {
        debugPrint('APK_DEBUG: Native returned null');
        return null;
      }

      final packageName = result['packageName'] as String?;
      final appName = result['appName'] as String?;
      final iconBytes = result['iconBytes'] as List<int>?;
      final isInstalled = result['isInstalled'] as bool? ?? false;

      debugPrint(
          'APK_DEBUG: Package: $packageName, App: $appName, Installed: $isInstalled, IconBytes: ${iconBytes?.length}');

      if (packageName == null || appName == null) {
        debugPrint('APK_DEBUG: Missing package name or app name');
        return null;
      }

      Widget icon;
      if (iconBytes != null && iconBytes.isNotEmpty) {
        debugPrint('APK_DEBUG: Creating icon from ${iconBytes.length} bytes');
        debugPrint('APK_DEBUG: First 20 bytes: ${iconBytes.take(20).toList()}');

        try {
          final uint8List = Uint8List.fromList(iconBytes);
          debugPrint(
              'APK_DEBUG: Created Uint8List with ${uint8List.length} bytes');

          icon = Image.memory(
            uint8List,
            width: 36,
            height: 36,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('APK_DEBUG: Image.memory error: $error');
              debugPrint('APK_DEBUG: StackTrace: $stackTrace');
              return Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isInstalled ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  isInstalled
                      ? PhosphorIconsLight.androidLogo
                      : PhosphorIconsLight.deviceMobile,
                  size: 24,
                  color: Colors.white,
                ),
              );
            },
          );
          debugPrint('APK_DEBUG: Successfully created Image.memory widget');
        } catch (e) {
          debugPrint('APK_DEBUG: Error creating icon from bytes: $e');
          icon = Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isInstalled ? Colors.green : Colors.orange,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              isInstalled
                  ? PhosphorIconsLight.androidLogo
                  : PhosphorIconsLight.deviceMobile,
              size: 24,
              color: Colors.white,
            ),
          );
        }
      } else {
        debugPrint('APK_DEBUG: No icon bytes, using fallback icon');
        // No icon bytes, use fallback icon
        icon = Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isInstalled ? Colors.green : Colors.orange,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            isInstalled
                ? PhosphorIconsLight.androidLogo
                : PhosphorIconsLight.deviceMobile,
            size: 24,
            color: Colors.white,
          ),
        );
      }

      debugPrint('APK_DEBUG: Returning AppInfo for $appName');
      return AppInfo(
        packageName: packageName,
        appName: appName,
        icon: icon,
        isInstalled: isInstalled,
      );
    } catch (e) {
      debugPrint('APK_DEBUG: Error getting APK installed app info: $e');
      return null;
    }
  }

  /// Open file with a specific app
  static Future<bool> openFileWithApp(
      String filePath, String packageName) async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod('openFileWithApp', {
          'filePath': filePath,
          'packageName': packageName,
        });
        return result ?? false;
      } else if (Platform.isWindows) {
        // Special case for shell_open
        if (packageName == 'shell_open') {
          final process = await Process.start('explorer', [filePath]);
          await process.exitCode;
          return true;
        } else {
          // On Windows, the packageName is actually the path to the executable
          final result = Process.runSync(packageName, [filePath]);
          return result.exitCode == 0;
        }
      }
      return false;
    } catch (e) {
      // debugPrint('Error opening file with app: $e');
      return false;
    }
  }

  /// Get Android apps that can handle this file type
  static Future<List<AppInfo>> _getAndroidAppsForFile(String filePath) async {
    try {
      final List<AppInfo> apps = [];
      if (Platform.isAndroid && FileTypeUtils.isVideoFile(filePath)) {
        apps.add(AppInfo(
          packageName: '__cb_video_player__',
          appName: 'CB File Hub Video Player',
          icon: const Icon(PhosphorIconsLight.playCircle, size: 36),
        ));
      }
      final extension = filePath.split('.').last.toLowerCase();
      final List<dynamic> result =
          await _channel.invokeMethod('getInstalledAppsForFile', {
        'filePath': filePath,
        'extension': extension,
      });

      apps.addAll(result.map<AppInfo>((app) {
        return AppInfo(
          packageName: app['packageName'],
          appName: app['appName'],
          icon: app['iconBytes'] != null
              ? Image.memory(app['iconBytes'], width: 36, height: 36)
              : const Icon(PhosphorIconsLight.androidLogo, size: 36),
        );
      }));
      return apps;
    } catch (e) {
      // debugPrint('Error getting Android apps: $e');
      return [];
    }
  }

  /// Get Windows apps that can handle this file type.
  /// Scans registry (OpenWithList, App Paths) by file extension, then falls
  /// back to associated app + hardcoded list when registry returns nothing.
  static Future<List<AppInfo>> _getWindowsAppsForFile(String filePath) async {
    try {
      final List<AppInfo> apps = [];
      final extension = filePath.split('.').last.toLowerCase();

      // On Windows, offer CB File Hub Video Player as an option for video files
      if (Platform.isWindows && FileTypeUtils.isVideoFile(filePath)) {
        apps.add(AppInfo(
          packageName: '__cb_video_player__',
          appName: 'CB File Hub Video Player',
          icon: const Icon(PhosphorIconsLight.playCircle, size: 36),
        ));
      }

      // Prefer: scan registry by file format (OpenWithList + App Paths)
      final scanned = await WindowsAppIcon.getAppsForExtension(extension);
      if (scanned.isNotEmpty) {
        for (final e in scanned) {
          final path = e['path'] ?? '';
          final name = e['name'] ?? _getAppNameFromPath(path);
          if (path.isEmpty) continue;
          if (File(path).existsSync()) {
            apps.add(AppInfo(
              packageName: path,
              appName: name,
              icon: await _getWindowsAppIcon(path),
            ));
          }
        }
        apps.add(AppInfo(
          packageName: 'shell_open',
          appName: 'Default Program',
          icon: const Icon(PhosphorIconsLight.arrowSquareOut, size: 36),
        ));
        return apps;
      }

      // Fallback: associated app when getAppsForExtension returns empty.
      // Other apps are fetched from Windows (OpenWithList, App Paths) via getAppsForExtension.
      String? associatedAppPath =
          await WindowsAppIcon.getAssociatedAppPath(extension);
      if (associatedAppPath != null && associatedAppPath.isNotEmpty) {
        final String appName = _getAppNameFromPath(associatedAppPath);
        final Widget appIcon = await _getWindowsAppIcon(associatedAppPath);
        apps.add(AppInfo(
          packageName: associatedAppPath,
          appName: appName,
          icon: appIcon,
        ));
      }

      apps.add(AppInfo(
        packageName: 'shell_open',
        appName: 'Default Program',
        icon: const Icon(PhosphorIconsLight.arrowSquareOut, size: 36),
      ));

      return apps;
    } catch (e) {
      return [];
    }
  }

  /// Get icon for a Windows app
  static Future<Widget> _getWindowsAppIcon(String execPath) async {
    // Check cache first
    if (_windowsAppIconCache.containsKey(execPath)) {
      return _windowsAppIconCache[execPath]!;
    }

    try {
      // Try to extract native icon
      ui.Image? nativeIcon = await WindowsAppIcon.extractIconFromFile(execPath);

      if (nativeIcon != null) {
        // debugPrint('Error getting Windows app icon: $e');
        final Widget iconWidget = RawImage(
          image: nativeIcon,
          width: 36,
          height: 36,
          fit: BoxFit.contain,
        );

        _windowsAppIconCache[execPath] = iconWidget;
        return iconWidget;
      }
    } catch (e) {
      // ...existing code...
    }

    // Fallback to using appropriate built-in icons based on app name
    IconData iconData;
    final String filename = execPath.split('\\').last.toLowerCase();

    if (filename.contains('paint')) {
      iconData = PhosphorIconsLight.paintBrush;
    } else if (filename.contains('word')) {
      iconData = PhosphorIconsLight.fileText;
    } else if (filename.contains('excel')) {
      iconData = PhosphorIconsLight.table;
    } else if (filename.contains('powerpnt')) {
      iconData = PhosphorIconsLight.presentationChart;
    } else if (filename.contains('vlc') || filename.contains('wmplayer')) {
      iconData = PhosphorIconsLight.videoCamera;
    } else if (filename.contains('acrobat') || filename.contains('reader')) {
      iconData = PhosphorIconsLight.filePdf;
    } else {
      iconData = PhosphorIconsLight.appWindow;
    }

    final Widget iconWidget = Icon(iconData, size: 36);
    _windowsAppIconCache[execPath] = iconWidget;
    return iconWidget;
  }

  /// Get application name from executable path
  static String _getAppNameFromPath(String execPath) {
    try {
      // Extract filename without extension
      final filename = execPath.split('\\').last;
      final appName = filename.split('.').first;

      // Try to make it more readable
      String readable = appName.replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'), (Match m) => '${m[1]} ${m[2]}');

      // Capitalize first letter of each word
      readable = readable.split(' ').map((word) {
        if (word.isEmpty) return '';
        return word[0].toUpperCase() + word.substring(1);
      }).join(' ');

      return readable;
    } catch (e) {
      return execPath.split('\\').last;
    }
  }

  /// Open file with Android system chooser dialog
  static Future<bool> openWithSystemChooser(String filePath) async {
    try {
      if (!Platform.isAndroid) {
        return false;
      }

      final result = await _channel.invokeMethod('openWithSystemChooser', {
        'filePath': filePath,
      });

      return result ?? false;
    } catch (e) {
      // ...existing code...
      return false;
    }
  }

  /// Open file with system default app (no chooser). Windows: explorer; Android: ACTION_VIEW.
  static Future<bool> openWithSystemDefault(String filePath) async {
    try {
      if (Platform.isWindows) {
        final process = await Process.start('explorer', [filePath]);
        await process.exitCode;
        return true;
      }
      if (Platform.isAndroid) {
        final r = await _channel
            .invokeMethod('openWithSystemDefault', {'filePath': filePath});
        return r == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Open a video file with the user's preferred external app (if configured).
  /// Returns true when a preferred app exists and launch succeeded.
  static Future<bool> openWithPreferredVideoApp(String filePath) async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();
      final preferred = await prefs.getPreferredVideoPlayerApp();
      if (preferred == null ||
          preferred.isEmpty ||
          preferred == '__cb_video_player__') {
        return false;
      }

      if (preferred == 'shell_open') {
        return await openWithSystemDefault(filePath);
      }

      return await openFileWithApp(filePath, preferred);
    } catch (_) {
      return false;
    }
  }

  /// On Android: get video path/URI from launch intent (Open with / default app).
  /// Returns map with 'path' and/or 'contentUri'; both empty if none.
  static Future<Map<String, String>> getLaunchVideoPath() async {
    if (!Platform.isAndroid) return {'path': '', 'contentUri': ''};
    try {
      final r = await _channel.invokeMethod('getLaunchVideoPath');
      if (r == null || r is! Map) return {'path': '', 'contentUri': ''};
      final m = Map<String, dynamic>.from(r);
      return {
        'path': '${m['path'] ?? ''}',
        'contentUri': '${m['contentUri'] ?? ''}',
      };
    } catch (_) {
      return {'path': '', 'contentUri': ''};
    }
  }

  /// On Android: open app's Settings (Open by default). No-op on other platforms.
  static Future<bool> openDefaultAppSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await _channel.invokeMethod('openDefaultAppSettings');
      return r == true;
    } catch (_) {
      return false;
    }
  }
}
