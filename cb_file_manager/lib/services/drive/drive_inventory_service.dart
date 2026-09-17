import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart' as win32;

import '../../helpers/core/filesystem_utils.dart';
import '../../helpers/core/io_extensions.dart';
import 'android_storage_volumes.dart';
import 'drive_info.dart';
import 'windows_volume_probe.dart';

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
    final groupCmp = DriveInfo.groupSortOrder(
      a.group,
    ).compareTo(DriveInfo.groupSortOrder(b.group));
    if (groupCmp != 0) return groupCmp;
    return a.path.toLowerCase().compareTo(b.path.toLowerCase());
  }

  /// How long the drive list waits for per-volume metadata before it settles
  /// for letters alone. One unreachable network share must not hold the whole
  /// list hostage.
  static const Duration volumeProbeTimeout = Duration(seconds: 6);

  static Future<List<DriveInfo>> _loadWindows() async {
    final systemDrive = Platform.environment['SystemDrive'];
    final directories = await getAllWindowsDrives();
    final roots = <String>[
      for (final dir in directories) DriveInfo.normalizeWindowsRoot(dir.path),
    ];
    if (roots.isEmpty) return <DriveInfo>[];

    // GetDriveType/GetVolumeInformation/GetDiskFreeSpaceEx each block their
    // calling thread until the volume answers, so they run in a background
    // isolate: on the UI isolate a sleeping disk or an offline mapped share
    // froze the window for as long as the OS took to time out.
    var probes = const <String, WindowsVolumeProbe>{};
    try {
      final results = await compute(
        probeWindowsVolumes,
        roots,
      ).timeout(volumeProbeTimeout);
      probes = <String, WindowsVolumeProbe>{
        for (final probe in results) probe.root: probe,
      };
    } on TimeoutException {
      debugPrint(
        'DriveInventoryService: volume probe timed out, '
        'showing drive letters without metadata',
      );
    } catch (e) {
      debugPrint('DriveInventoryService: volume probe failed: $e');
    }

    return <DriveInfo>[
      for (final dir in directories)
        _windowsDriveInfo(
          dir,
          DriveInfo.normalizeWindowsRoot(dir.path),
          probes,
          systemDrive,
        ),
    ];
  }

  static DriveInfo _windowsDriveInfo(
    Directory dir,
    String root,
    Map<String, WindowsVolumeProbe> probes,
    String? systemDrive,
  ) {
    final probe = probes[root];
    final kind = _windowsDriveKind(probe?.driveType ?? win32.DRIVE_UNKNOWN);
    final isSystem = DriveInfo.isWindowsSystemDrive(
      root,
      systemDrive: systemDrive,
    );
    final requiresAdmin = dir.getProperty('requiresAdmin') == true;
    final isRemovable =
        kind == DriveKind.removable || kind == DriveKind.optical;
    final label = probe?.label ?? '';
    final displayName = label.isNotEmpty ? '$root ($label)' : root;

    return DriveInfo(
      path: root,
      displayName: displayName,
      label: label,
      kind: kind,
      filesystem: probe?.filesystem ?? '',
      volumeSerial: probe?.serial,
      space: probe == null
          ? const DriveSpaceInfo.empty()
          : DriveSpaceInfo.fromTotalFree(probe.totalBytes, probe.freeBytes),
      isRemovable: isRemovable,
      canEject: isRemovable && !isSystem,
      canRename:
          !isSystem && kind != DriveKind.network && kind != DriveKind.optical,
      requiresAdmin: requiresAdmin,
      isSystemVolume: isSystem,
      isPrimary: isSystem,
    );
  }

  static DriveKind _windowsDriveKind(int driveType) {
    switch (driveType) {
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
