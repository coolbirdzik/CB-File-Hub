/// Typed volume metadata for the drive manager UI.
enum DriveKind {
  fixed,
  removable,
  network,
  optical,
  ram,
  internal,
  unknown,
}

enum DriveGroup {
  fixed,
  removable,
  network,
  other,
}

class DriveSpaceInfo {
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;

  const DriveSpaceInfo({
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
  });

  const DriveSpaceInfo.empty()
      : totalBytes = 0,
        freeBytes = 0,
        usedBytes = 0;

  bool get hasDetails => totalBytes > 0;

  double get usageRatio {
    if (totalBytes <= 0) return 0;
    return (usedBytes / totalBytes).clamp(0.0, 1.0);
  }

  static DriveSpaceInfo fromTotalFree(int totalBytes, int freeBytes) {
    final safeTotal = totalBytes < 0 ? 0 : totalBytes;
    final safeFree = freeBytes < 0 ? 0 : freeBytes;
    final used = safeTotal > safeFree ? safeTotal - safeFree : 0;
    return DriveSpaceInfo(
      totalBytes: safeTotal,
      freeBytes: safeFree,
      usedBytes: used,
    );
  }
}

class DriveInfo {
  final String path;
  final String displayName;
  final String label;
  final DriveKind kind;
  final String filesystem;
  final String? volumeSerial;
  final DriveSpaceInfo space;
  final bool isRemovable;
  final bool canEject;
  final bool canRename;
  final bool requiresAdmin;
  final bool isSystemVolume;
  final bool isPrimary;
  final String? uuid;
  final String? description;

  const DriveInfo({
    required this.path,
    required this.displayName,
    this.label = '',
    this.kind = DriveKind.unknown,
    this.filesystem = '',
    this.volumeSerial,
    this.space = const DriveSpaceInfo.empty(),
    this.isRemovable = false,
    this.canEject = false,
    this.canRename = false,
    this.requiresAdmin = false,
    this.isSystemVolume = false,
    this.isPrimary = false,
    this.uuid,
    this.description,
  });

  DriveGroup get group {
    switch (kind) {
      case DriveKind.fixed:
      case DriveKind.internal:
      case DriveKind.ram:
        return DriveGroup.fixed;
      case DriveKind.removable:
        return DriveGroup.removable;
      case DriveKind.network:
        return DriveGroup.network;
      case DriveKind.optical:
      case DriveKind.unknown:
        return DriveGroup.other;
    }
  }

  String get kindLabel {
    switch (kind) {
      case DriveKind.fixed:
        return 'Local Disk';
      case DriveKind.removable:
        return 'Removable';
      case DriveKind.network:
        return 'Network';
      case DriveKind.optical:
        return 'Optical';
      case DriveKind.ram:
        return 'RAM Disk';
      case DriveKind.internal:
        return 'Internal storage';
      case DriveKind.unknown:
        return 'Storage';
    }
  }

  String get subtitle {
    final parts = <String>[];
    if (filesystem.isNotEmpty) parts.add(filesystem);
    parts.add(kindLabel);
    if (requiresAdmin) parts.add('Restricted');
    return parts.join(' · ');
  }

  DriveInfo copyWith({
    String? path,
    String? displayName,
    String? label,
    DriveKind? kind,
    String? filesystem,
    String? volumeSerial,
    DriveSpaceInfo? space,
    bool? isRemovable,
    bool? canEject,
    bool? canRename,
    bool? requiresAdmin,
    bool? isSystemVolume,
    bool? isPrimary,
    String? uuid,
    String? description,
  }) {
    return DriveInfo(
      path: path ?? this.path,
      displayName: displayName ?? this.displayName,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      filesystem: filesystem ?? this.filesystem,
      volumeSerial: volumeSerial ?? this.volumeSerial,
      space: space ?? this.space,
      isRemovable: isRemovable ?? this.isRemovable,
      canEject: canEject ?? this.canEject,
      canRename: canRename ?? this.canRename,
      requiresAdmin: requiresAdmin ?? this.requiresAdmin,
      isSystemVolume: isSystemVolume ?? this.isSystemVolume,
      isPrimary: isPrimary ?? this.isPrimary,
      uuid: uuid ?? this.uuid,
      description: description ?? this.description,
    );
  }

  /// Normalize a Windows drive root to `X:\` form.
  static String normalizeWindowsRoot(String drivePath) {
    var path = drivePath.trim().replaceAll('/', '\\');
    if (path.isEmpty) return path;
    if (path.length >= 2 && path[1] == ':') {
      final letter = path[0].toUpperCase();
      return '$letter:\\';
    }
    if (!path.endsWith('\\')) path = '$path\\';
    return path;
  }

  /// True when [path] is the Windows system drive (usually `C:\`).
  /// Pass [systemDrive] as `C:` / `C:\` from `Platform.environment['SystemDrive']`.
  static bool isWindowsSystemDrive(String drivePath, {String? systemDrive}) {
    final root = normalizeWindowsRoot(drivePath).toUpperCase();
    final sys = (systemDrive ?? 'C:').trim().toUpperCase();
    final letter = sys.isNotEmpty ? sys[0] : 'C';
    return root == '$letter:\\';
  }

  static int groupSortOrder(DriveGroup group) {
    switch (group) {
      case DriveGroup.fixed:
        return 0;
      case DriveGroup.removable:
        return 1;
      case DriveGroup.network:
        return 2;
      case DriveGroup.other:
        return 3;
    }
  }
}
