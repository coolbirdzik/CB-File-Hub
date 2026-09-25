import 'dart:io';

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class PermissionStateService {
  PermissionStateService._();

  static final PermissionStateService instance = PermissionStateService._();

  static const MethodChannel _macosWindowChannel = MethodChannel(
    'cb_file_manager/macos_window',
  );

  Future<bool> hasStorageOrPhotosPermission() async {
    // An E2E run reinstalls the app for every pass, so the runtime permissions
    // are always missing and every folder listing would fail. The run only
    // browses directories the app owns, which need no permission anyway.
    if (kCbE2E) return true;

    if (Platform.isAndroid) {
      try {
        final videos = await Permission.videos.isGranted;
        final photos = await Permission.photos.isGranted;
        final audio = await Permission.audio.isGranted;
        final storage = await Permission.storage.isGranted;
        final manage = await Permission.manageExternalStorage.isGranted;
        return videos || photos || audio || storage || manage;
      } catch (e) {
        debugPrint('Error checking Android storage/media permissions: $e');
        return false;
      }
    }

    if (Platform.isIOS) {
      try {
        final photos = await Permission.photos.isGranted;
        return photos;
      } catch (e) {
        debugPrint('Error checking iOS photos permission: $e');
        return false;
      }
    }

    // Desktop/web default allow
    return true;
  }

  Future<bool> hasAllFilesAccessPermission() async {
    if (Platform.isAndroid) {
      try {
        final manage = await Permission.manageExternalStorage.isGranted;
        return manage;
      } catch (e) {
        debugPrint(
          'Error checking Android manage external storage permission: $e',
        );
        return false;
      }
    }
    if (Platform.isMacOS) return _hasMacosFullDiskAccess();
    // iOS doesn't have this permission
    return true;
  }

  /// macOS has no API to query Full Disk Access, so probe files that TCC only
  /// lets FDA apps open. Stat still works without it, so a probe that exists
  /// but cannot be opened means access is missing.
  bool _hasMacosFullDiskAccess() {
    final home = Platform.environment['HOME'] ?? '';
    final probes = <String>[
      '$home/Library/Application Support/com.apple.TCC/TCC.db',
      '/Library/Application Support/com.apple.TCC/TCC.db',
      '$home/Library/Safari/Bookmarks.plist',
    ];
    var probed = false;
    for (final path in probes) {
      final file = File(path);
      if (!file.existsSync()) continue;
      probed = true;
      try {
        file.openSync().closeSync();
        return true;
      } on FileSystemException {
        continue;
      }
    }
    // Nothing to probe: do not block the user on a check we cannot make.
    return !probed;
  }

  Future<bool> hasLocalNetworkPermission() async {
    // Not directly supported by permission_handler; treat as granted.
    // iOS Local Network permission is declared via Info.plist and prompted by sockets.
    return true;
  }

  Future<bool> hasNotificationsPermission() async {
    try {
      final status = await Permission.notification.isGranted;
      return status;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasInstallPackagesPermission() async {
    if (Platform.isAndroid) {
      try {
        final status = await Permission.requestInstallPackages.isGranted;
        return status;
      } catch (e) {
        debugPrint('Error checking Android install packages permission: $e');
        return false;
      }
    }
    // iOS doesn't have this permission
    return true;
  }

  Future<bool> requestStorageOrPhotos() async {
    if (Platform.isAndroid) {
      try {
        // On Android 13+ use granular media permissions. Try all relevant ones.
        final videos = await Permission.videos.request();
        if (videos.isGranted || videos.isLimited) return true;

        final photos = await Permission.photos.request();
        if (photos.isGranted || photos.isLimited) return true;

        final audio = await Permission.audio.request();
        if (audio.isGranted || audio.isLimited) return true;

        // For older Android versions (<=12) or OEM behaviors, also request legacy storage.
        final storage = await Permission.storage.request();
        if (storage.isGranted) return true;

        // As a last resort, request manage external storage (All files access) when applicable.
        final manage = await Permission.manageExternalStorage.request();
        if (manage.isGranted) return true;

        // If nothing is granted, guide user to App Settings for All files access toggle.
        await openAppSettings();
        return false;
      } catch (e) {
        debugPrint('Error requesting Android media/storage permissions: $e');
        return false;
      }
    }
    if (Platform.isIOS) {
      try {
        final status = await Permission.photos.request();
        return status.isGranted || status.isLimited;
      } catch (e) {
        debugPrint('Error requesting iOS photos permission: $e');
        return false;
      }
    }
    return true;
  }

  /// On macOS, [macosHelperTitle] and [macosHelperMessage] label the card
  /// that walks the user through dragging the app into the settings list.
  Future<bool> requestAllFilesAccess({
    String? macosHelperTitle,
    String? macosHelperMessage,
  }) async {
    if (Platform.isAndroid) {
      try {
        final manage = await Permission.manageExternalStorage.request();
        if (manage.isGranted) return true;

        // If not granted, open settings for manual grant
        await openAppSettings();
        return false;
      } catch (e) {
        debugPrint(
          'Error requesting Android manage external storage permission: $e',
        );
        await openAppSettings();
        return false;
      }
    }
    if (Platform.isMacOS) {
      if (_hasMacosFullDiskAccess()) return true;
      // No app may add itself to Full Disk Access. Open the list and float a
      // draggable app icon beside it (macos/Runner/MainFlutterWindow.swift);
      // dropping it in makes macOS ask the user to approve with Touch ID.
      try {
        await launchUrl(
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
          ),
        );
        await _macosWindowChannel.invokeMethod<void>(
          'showFullDiskAccessHelper',
          <String, String>{
            'title': macosHelperTitle ?? '',
            'message': macosHelperMessage ?? '',
          },
        );
      } catch (e) {
        debugPrint('Error opening macOS Full Disk Access settings: $e');
      }
      return false;
    }
    // iOS doesn't have this permission
    return true;
  }

  Future<bool> requestLocalNetwork() async {
    // No direct runtime request available; networking attempt will trigger prompt on iOS.
    return true;
  }

  Future<bool> requestNotifications() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestInstallPackages() async {
    if (Platform.isAndroid) {
      try {
        final status = await Permission.requestInstallPackages.request();
        return status.isGranted;
      } catch (e) {
        debugPrint('Error requesting Android install packages permission: $e');
        return false;
      }
    }
    // iOS doesn't have this permission
    return true;
  }
}
