import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../disk_cleaner/macos_cleaner_platform.dart';
import 'drive_info.dart';

/// One volume Finder would list.
class MacosVolume {
  final String path;
  final String label;
  final String filesystem;
  final int totalBytes;
  final int freeBytes;
  final bool isRoot;
  final bool isLocal;
  final bool isInternal;
  final bool isRemovable;
  final bool isEjectable;

  const MacosVolume({
    required this.path,
    this.label = '',
    this.filesystem = '',
    this.totalBytes = 0,
    this.freeBytes = 0,
    this.isRoot = false,
    this.isLocal = true,
    this.isInternal = false,
    this.isRemovable = false,
    this.isEjectable = false,
  });

  factory MacosVolume.fromMap(Map<dynamic, dynamic> row) {
    final path = row['path'] as String;
    return MacosVolume(
      path: path,
      label: row['label'] as String? ?? '',
      filesystem: row['filesystem'] as String? ?? '',
      totalBytes: (row['totalBytes'] as num?)?.toInt() ?? 0,
      freeBytes: (row['freeBytes'] as num?)?.toInt() ?? 0,
      isRoot: row['isRoot'] as bool? ?? path == '/',
      isLocal: row['isLocal'] as bool? ?? true,
      isInternal: row['isInternal'] as bool? ?? false,
      isRemovable: row['isRemovable'] as bool? ?? false,
      isEjectable: row['isEjectable'] as bool? ?? false,
    );
  }

  String get displayName => label.isNotEmpty ? label : path;

  DriveKind get kind {
    if (!isLocal) return DriveKind.network;
    if (isRoot || (isInternal && !isRemovable && !isEjectable)) {
      return DriveKind.fixed;
    }
    return DriveKind.removable;
  }

  DriveInfo toDrive() => DriveInfo(
    path: path,
    displayName: displayName,
    label: label,
    kind: kind,
    filesystem: filesystem,
    space: DriveSpaceInfo.fromTotalFree(totalBytes, freeBytes),
    isRemovable: kind == DriveKind.removable,
    isSystemVolume: isRoot,
    isPrimary: isRoot,
  );
}

/// The volumes mounted on this Mac, boot volume first.
abstract final class MacosVolumes {
  /// A share that stopped answering must not hold the sidebar back.
  static const Duration timeout = Duration(seconds: 6);

  /// Fires when a volume is mounted, unmounted or renamed.
  static Stream<void> get changes =>
      Platform.isMacOS && !Platform.environment.containsKey('FLUTTER_TEST')
      ? MacosCleanerPlatform.volumeChanges
      : const Stream<void>.empty();

  /// Never empty: without the native list the boot volume is still there.
  static Future<List<MacosVolume>> list() async {
    try {
      final rows = await MacosCleanerPlatform.channel
          .invokeListMethod<dynamic>('getMountedVolumes')
          .timeout(timeout);
      final volumes = <MacosVolume>[
        for (final row in rows ?? const <dynamic>[])
          if (row is Map && row['path'] is String) MacosVolume.fromMap(row),
      ];
      if (volumes.isNotEmpty) return volumes..sort(_compare);
    } on MissingPluginException {
      // Not running on the macOS runner (tests).
    } on PlatformException catch (e) {
      debugPrint('MacosVolumes.list failed: $e');
    } on TimeoutException {
      debugPrint('MacosVolumes.list timed out');
    }
    return const [MacosVolume(path: '/', isRoot: true)];
  }

  static int _compare(MacosVolume a, MacosVolume b) {
    final rank = _rank(a).compareTo(_rank(b));
    if (rank != 0) return rank;
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  static int _rank(MacosVolume volume) =>
      volume.isRoot ? 0 : 1 + DriveInfo.groupSortOrder(volume.toDrive().group);
}
