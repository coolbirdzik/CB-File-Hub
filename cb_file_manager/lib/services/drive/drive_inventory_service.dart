import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart' as win32;

import '../../helpers/core/filesystem_utils.dart';
import '../../helpers/core/io_extensions.dart';
import 'android_storage_volumes.dart';
import 'drive_info.dart';

/// Process-local inventory of mounted drives/volumes.
class DriveInventoryService {
  DriveInventoryService._();

  static const Duration cacheFreshness = Duration(minutes: 5);

  static List<DriveInfo>? _cached;
  static DateTime? _cachedAt;

  static List<DriveInfo>? get cachedSnapshot => _cached;

  static bool get hasFreshCache {
    if (_cached == null || _cached!.isEmpty || _cachedAt == null) return false;
    return DateTime.now().difference(_cachedAt!) < cacheFreshness;
  }

  static void invalidateCache() {
    _cached = null;
    _cachedAt = null;
  }

  /// Load drives, updating the process-wide cache.
  static Future<List<DriveInfo>> load({bool forceRefresh = false}) async {
    if (!forceRefresh && hasFreshCache) {
      return List<DriveInfo>.from(_cached!);
    }

    final List<DriveInfo> entries;
    if (Platform.isWindows) {
      entries = await _loadWindows();
    } else if (Platform.isAndroid) {
      entries = await _loadAndroid();
    } else {
      entries = await _loadFallback();
    }

    entries.sort(_compareDrives);
    _cached = entries;
    _cachedAt = DateTime.now();
    return List<DriveInfo>.from(entries);
  }

  static int _compareDrives(DriveInfo a, DriveInfo b) {
    final groupCmp = DriveInfo.groupSortOrder(a.group)
        .compareTo(DriveInfo.groupSortOrder(b.group));
    if (groupCmp != 0) return groupCmp;
    return a.path.toLowerCase().compareTo(b.path.toLowerCase());
  }

  static Future<List<DriveInfo>> _loadWindows() async {
    final systemDrive = Platform.environment['SystemDrive'];
    final directories = await getAllWindowsDrives();
    final results = await Future.wait(
      directories.map((dir) => _windowsDriveInfo(dir, systemDrive)),
    );
    return results;
  }

  static Future<DriveInfo> _windowsDriveInfo(
    Directory dir,
    String? systemDrive,
  ) async {
    final root = DriveInfo.normalizeWindowsRoot(dir.path);
    final volume = await _readWindowsVolume(root);
    final space = await _readWindowsSpace(root);
    final kind = _windowsDriveKind(root);
    final isSystem = DriveInfo.isWindowsSystemDrive(
      root,
      systemDrive: systemDrive,
    );
    final requiresAdmin = dir.getProperty('requiresAdmin') == true;
    final isRemovable = kind == DriveKind.removable || kind == DriveKind.optical;
    final label = volume.label;
    final displayName = label.isNotEmpty ? '$root ($label)' : root;

    return DriveInfo(
      path: root,
      displayName: displayName,
      label: label,
      kind: kind,
      filesystem: volume.filesystem,
      volumeSerial: volume.serial,
      space: space,
      isRemovable: isRemovable,
      canEject: isRemovable && !isSystem,
      canRename: !isSystem && kind != DriveKind.network && kind != DriveKind.optical,
      requiresAdmin: requiresAdmin,
      isSystemVolume: isSystem,
      isPrimary: isSystem,
    );
  }

  static DriveKind _windowsDriveKind(String root) {
    final pathPtr = root.toNativeUtf16();
    try {
      final type = win32.GetDriveType(pathPtr);
      switch (type) {
        case win32.DRIVE_REMOVABLE:
          return DriveKind.removable;
        case win32.DRIVE_FIXED:
          return DriveKind.fixed;
        case win32.DRIVE_REMOTE:
          return DriveKind.network;
        case win32.DRIVE_CDROM:
          return DriveKind.optical;
        case win32.DRIVE_RAMDISK:
          return DriveKind.ram;
        default:
          return DriveKind.unknown;
      }
    } catch (_) {
      return DriveKind.unknown;
    } finally {
      calloc.free(pathPtr);
    }
  }

  static Future<_WindowsVolumeMeta> _readWindowsVolume(String root) async {
    final drive = root.endsWith('\\') ? root : '$root\\';
    final volumeNameBuffer = calloc<Uint16>(win32.MAX_PATH + 1).cast<Utf16>();
    final fileSystemNameBuffer =
        calloc<Uint16>(win32.MAX_PATH + 1).cast<Utf16>();
    final volumeSerialNumber = calloc<Uint32>();
    final maximumComponentLength = calloc<Uint32>();
    final fileSystemFlags = calloc<Uint32>();
    final pathPtr = drive.toNativeUtf16();

    try {
      final result = win32.GetVolumeInformation(
        pathPtr,
        volumeNameBuffer,
        win32.MAX_PATH + 1,
        volumeSerialNumber,
        maximumComponentLength,
        fileSystemFlags,
        fileSystemNameBuffer,
        win32.MAX_PATH + 1,
      );
      if (result == 0) {
        return const _WindowsVolumeMeta();
      }
      final label = volumeNameBuffer.toDartString();
      final fs = fileSystemNameBuffer.toDartString();
      final serial = volumeSerialNumber.value
          .toRadixString(16)
          .padLeft(8, '0')
          .toUpperCase();
      return _WindowsVolumeMeta(
        label: label,
        filesystem: fs,
        serial: serial,
      );
    } catch (e) {
      debugPrint('DriveInventoryService volume info failed for $root: $e');
      return const _WindowsVolumeMeta();
    } finally {
      calloc.free(volumeNameBuffer);
      calloc.free(fileSystemNameBuffer);
      calloc.free(volumeSerialNumber);
      calloc.free(maximumComponentLength);
      calloc.free(fileSystemFlags);
      calloc.free(pathPtr);
    }
  }

  static Future<DriveSpaceInfo> _readWindowsSpace(String root) async {
    final drive = root.endsWith('\\') ? root : '$root\\';
    final lpFreeBytesAvailable = calloc<Uint64>();
    final lpTotalNumberOfBytes = calloc<Uint64>();
    final lpTotalNumberOfFreeBytes = calloc<Uint64>();
    final pathPtr = drive.toNativeUtf16();

    try {
      final result = win32.GetDiskFreeSpaceEx(
        pathPtr,
        lpFreeBytesAvailable,
        lpTotalNumberOfBytes,
        lpTotalNumberOfFreeBytes,
      );
      if (result == 0) return const DriveSpaceInfo.empty();
      return DriveSpaceInfo.fromTotalFree(
        lpTotalNumberOfBytes.value,
        lpFreeBytesAvailable.value,
      );
    } catch (_) {
      return const DriveSpaceInfo.empty();
    } finally {
      calloc.free(lpFreeBytesAvailable);
      calloc.free(lpTotalNumberOfBytes);
      calloc.free(lpTotalNumberOfFreeBytes);
      calloc.free(pathPtr);
    }
  }

  static Future<List<DriveInfo>> _loadAndroid() async {
    final volumes = await AndroidStorageVolumes.listVolumes();
    if (volumes.isNotEmpty) {
      return volumes.map(_androidVolumeToDrive).toList();
    }

    // Fallback to path discovery when the plugin is missing.
    final dirs = await getAllStorageLocations();
    return dirs.map((dir) {
      final path = dir.path;
      final isPrimary = path.contains('emulated') || path == '/sdcard';
      final isRemovable = !isPrimary;
      final name = isPrimary
          ? 'Internal storage'
          : (path.split('/').where((p) => p.isNotEmpty).last);
      return DriveInfo(
        path: path,
        displayName: name,
        label: name,
        kind: isPrimary ? DriveKind.internal : DriveKind.removable,
        isRemovable: isRemovable,
        canEject: isRemovable,
        canRename: false,
        isSystemVolume: isPrimary,
        isPrimary: isPrimary,
      );
    }).toList();
  }

  static DriveInfo _androidVolumeToDrive(AndroidStorageVolume volume) {
    final isPrimary = volume.isPrimary;
    final kind = isPrimary
        ? DriveKind.internal
        : (volume.isRemovable ? DriveKind.removable : DriveKind.fixed);
    final label = volume.label.isNotEmpty
        ? volume.label
        : (isPrimary
            ? 'Internal storage'
            : (volume.description.isNotEmpty
                ? volume.description
                : volume.path));
    return DriveInfo(
      path: volume.path,
      displayName: label,
      label: volume.label,
      kind: kind,
      filesystem: volume.filesystem,
      space: DriveSpaceInfo.fromTotalFree(volume.totalBytes, volume.freeBytes),
      isRemovable: volume.isRemovable && !isPrimary,
      canEject: volume.canEject && !isPrimary,
      canRename: !isPrimary,
      isSystemVolume: isPrimary,
      isPrimary: isPrimary,
      uuid: volume.uuid,
      description: volume.description,
    );
  }

  static Future<List<DriveInfo>> _loadFallback() async {
    final dirs = await getAllStorageLocations();
    return dirs
        .map(
          (dir) => DriveInfo(
            path: dir.path,
            displayName: dir.path,
            kind: DriveKind.fixed,
          ),
        )
        .toList();
  }
}

class _WindowsVolumeMeta {
  final String label;
  final String filesystem;
  final String? serial;

  const _WindowsVolumeMeta({
    this.label = '',
    this.filesystem = '',
    this.serial,
  });
}
