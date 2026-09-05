import 'dart:io';

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionStateService {
  PermissionStateService._();

  static final PermissionStateService instance = PermissionStateService._();

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
    // iOS doesn't have this permission
    return true;
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

  Future<bool> requestAllFilesAccess() async {
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
