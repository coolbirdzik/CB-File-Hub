import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

class WindowsAppIcon {
  static const MethodChannel _channel =
      MethodChannel('cb_file_manager/app_icon');

  /// Cache for extracted icons
  static final Map<String, ui.Image> _iconCache = {};

  /// Batch extract file-type icons for a list of extensions.
  /// Uses SHGetFileInfo with SHGFI_USEFILEATTRIBUTES on native side —
  /// no real file needed, just the extension string.
  /// Returns a map of extension -> {iconData: Uint8List, width: int, height: int}
  /// or null for extensions where extraction failed.
  static Future<Map<String, Uint8List?>> extractIconsForExtensions(
    List<String> extensions, {
    int iconSize = 32,
  }) async {
    if (!Platform.isWindows || extensions.isEmpty) return {};

    try {
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('extractIconsForExtensions', {
        'extensions': extensions,
        'iconSize': iconSize,
      });

      if (result == null) return {};

      final Map<String, Uint8List?> output = {};
      for (final entry in result.entries) {
        final ext = entry.key as String;
        final value = entry.value;
        if (value is Map) {
          final iconData = value['iconData'];
          if (iconData is Uint8List) {
            // Convert BGRA to RGBA
            final Uint8List rgbaData = Uint8List(iconData.length);
            for (int i = 0; i < iconData.length; i += 4) {
              rgbaData[i] = iconData[i + 2]; // R (from B)
              rgbaData[i + 1] = iconData[i + 1]; // G
              rgbaData[i + 2] = iconData[i]; // B (from R)
              rgbaData[i + 3] = iconData[i + 3]; // A
            }
            output[ext] = rgbaData;
          } else {
            output[ext] = null;
          }
        } else {
          output[ext] = null;
        }
      }
      return output;
    } catch (e) {
      return {};
    }
  }

  /// Get the associated application for a file extension
  static Future<String?> getAssociatedAppPath(String extension) async {
    if (!Platform.isWindows) return null;

    try {
      final String? result =
          await _channel.invokeMethod<String>('getAssociatedAppPath', {
        'extension': extension,
      });
      return result;
    } catch (e) {
      // Removed debugPrint statement
      return null;
    }
  }

  /// Extract icon from an executable file
  static Future<ui.Image?> extractIconFromFile(String exePath) async {
    if (!Platform.isWindows) return null;

    // Check cache first
    if (_iconCache.containsKey(exePath)) {
      return _iconCache[exePath];
    }

    try {
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('extractIconFromFile', {
        'exePath': exePath,
      });

      if (result != null) {
        final Uint8List iconData = result['iconData'] as Uint8List;
        final int width = result['width'] as int;
        final int height = result['height'] as int;

        // Convert BGRA to RGBA format
        final Uint8List rgbaData = Uint8List(iconData.length);
        for (int i = 0; i < iconData.length; i += 4) {
          rgbaData[i] = iconData[i + 2]; // R (from B)
          rgbaData[i + 1] = iconData[i + 1]; // G
          rgbaData[i + 2] = iconData[i]; // B (from R)
          rgbaData[i + 3] = iconData[i + 3]; // A
        }

        final Completer<ui.Image> completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          rgbaData,
          width,
          height,
          ui.PixelFormat.rgba8888,
          completer.complete,
        );

        final ui.Image image = await completer.future;
        _iconCache[exePath] = image;
        return image;
      }

      return null;
    } catch (e) {
      // Removed debugPrint statement
      return null;
    }
  }

  /// Get the application icon for a file extension
  static Future<ui.Image?> getIconForExtension(String extension) async {
    if (!Platform.isWindows) return null;

    final String? appPath = await getAssociatedAppPath(extension);
    if (appPath == null || appPath.isEmpty) return null;

    return extractIconFromFile(appPath);
  }

  /// Get all apps that can handle a file extension (from Windows registry
  /// OpenWithList and App Paths). Returns list of maps: [{'path': '...', 'name': '...'}]
  static Future<List<Map<String, String>>> getAppsForExtension(
      String extension) async {
    if (!Platform.isWindows) return [];

    try {
      final List<dynamic>? result =
          await _channel.invokeMethod<List<dynamic>>('getAppsForExtension', {
        'extension': extension,
      });
      if (result == null) return [];
      final List<Map<String, String>> apps = [];
      for (final e in result) {
        if (e is Map) {
          final path = e['path'] as String?;
          final name = e['name'] as String?;
          if (path != null && path.isNotEmpty) {
            apps.add({'path': path, 'name': name ?? path});
          }
        }
      }
      return apps;
    } catch (e) {
      return [];
    }
  }

  /// Register this app as the default for video files on Windows.
  /// [exePath] should be Platform.resolvedExecutable.
  static Future<bool> setSelfAsDefaultForVideo(String exePath) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'setSelfAsDefaultForVideo',
        {'exePath': exePath},
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Registers [extensions] with Windows Open-with / Default-apps (HKCU).
  /// Does not change the current default unless [setAsDefault] is true.
  static Future<bool> registerFileAssociations({
    required String exePath,
    required List<String> extensions,
    bool setAsDefault = false,
  }) async {
    if (!Platform.isWindows || extensions.isEmpty) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'registerFileAssociations',
        {
          'exePath': exePath,
          'extensions': extensions,
          'setAsDefault': setAsDefault,
        },
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setSelfAsDefaultForArchives(String exePath) {
    return registerFileAssociations(
      exePath: exePath,
      extensions: const [
        '.zip',
        '.rar',
        '.7z',
        '.tar',
        '.gz',
        '.bz2',
        '.tgz',
        '.tbz2',
        '.txz',
      ],
      setAsDefault: true,
    );
  }

  // ─── Brand Detection (for create-file dialog) ────────────────────────────────

  /// Windows: Detects which office suites are installed via the native plugin.
  static Future<Set<String>> getInstalledBrands() async {
    if (!Platform.isWindows) return {};
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('getInstalledAppBrands');
      return Set<String>.from(result ?? []);
    } catch (_) {
      return {};
    }
  }
}
