/// Platform-agnostic models used by Cleaner App Insights.
///
/// These types deliberately contain no Flutter or Windows API dependencies so
/// inventory, attribution, AI formatting, and UI filtering can be tested with
/// deterministic fixtures.

enum InstalledAppSource { win32, msix }

enum AppUsageSource { userAssist, prefetch }

enum UsageEvidenceConfidence { high, medium }

enum MeasurementQuality { measured, estimated, partial, unknown }

enum AttributionConfidence { confirmed, likely, shared }

enum AppStorageKind {
  install,
  localData,
  roamingData,
  packageData,
  programData,
  cache,
  logs,
  shared,
  unknown,
}

class InstalledAppInfo {
  final String id;
  final String displayName;
  final String? publisher;
  final String? version;
  final InstalledAppSource source;
  final String? installLocation;
  final String? displayIconPath;
  final String? packageFamilyName;
  final DateTime? installedOrUpdatedAt;
  final int? estimatedSizeBytes;
  final bool canManage;
  final List<String> executablePaths;
  final List<String> warnings;

  const InstalledAppInfo({
    required this.id,
    required this.displayName,
    required this.source,
    this.publisher,
    this.version,
    this.installLocation,
    this.displayIconPath,
    this.packageFamilyName,
    this.installedOrUpdatedAt,
    this.estimatedSizeBytes,
    this.canManage = true,
    this.executablePaths = const <String>[],
    this.warnings = const <String>[],
  });

  InstalledAppInfo copyWith({
    String? id,
    String? displayName,
    String? publisher,
    String? version,
    InstalledAppSource? source,
    String? installLocation,
    String? displayIconPath,
    String? packageFamilyName,
    DateTime? installedOrUpdatedAt,
    int? estimatedSizeBytes,
    bool? canManage,
    List<String>? executablePaths,
    List<String>? warnings,
  }) {
    return InstalledAppInfo(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      publisher: publisher ?? this.publisher,
      version: version ?? this.version,
      source: source ?? this.source,
      installLocation: installLocation ?? this.installLocation,
      displayIconPath: displayIconPath ?? this.displayIconPath,
      packageFamilyName: packageFamilyName ?? this.packageFamilyName,
      installedOrUpdatedAt: installedOrUpdatedAt ?? this.installedOrUpdatedAt,
      estimatedSizeBytes: estimatedSizeBytes ?? this.estimatedSizeBytes,
      canManage: canManage ?? this.canManage,
      executablePaths: executablePaths ?? this.executablePaths,
      warnings: warnings ?? this.warnings,
    );
  }
}

class AppUsageEvidence {
  final DateTime? lastOpenedAt;
  final AppUsageSource? source;
  final UsageEvidenceConfidence? confidence;
  final String? matchedTarget;

  const AppUsageEvidence({
    this.lastOpenedAt,
    this.source,
    this.confidence,
    this.matchedTarget,
  });

  bool get isKnown => lastOpenedAt != null;

  bool isStale({
    required DateTime now,
    required Duration threshold,
  }) {
    final lastOpened = lastOpenedAt;
    if (lastOpened == null || lastOpened.isAfter(now)) return false;
    return now.difference(lastOpened) >= threshold;
  }
}

class AppStorageEntry {
  final String path;
  final AppStorageKind kind;
  final int sizeBytes;
  final MeasurementQuality measurementQuality;
  final AttributionConfidence attributionConfidence;
  final String? categoryId;
  final bool isCleanable;
  final List<String> warnings;

  const AppStorageEntry({
    required this.path,
    required this.kind,
    required this.sizeBytes,
    required this.measurementQuality,
    required this.attributionConfidence,
    this.categoryId,
    this.isCleanable = false,
    this.warnings = const <String>[],
  });

  bool get isConfirmed =>
      attributionConfidence == AttributionConfidence.confirmed;

  bool get isPossible => attributionConfidence == AttributionConfidence.likely;
}

class AppStorageProfile {
  final InstalledAppInfo app;
  final AppUsageEvidence usage;
  final List<AppStorageEntry> entries;
  final List<String> warnings;

  const AppStorageProfile({
    required this.app,
    this.usage = const AppUsageEvidence(),
    this.entries = const <AppStorageEntry>[],
    this.warnings = const <String>[],
  });

  int get confirmedSizeBytes => entries
      .where((entry) => entry.isConfirmed)
      .fold<int>(0, (sum, entry) => sum + entry.sizeBytes);

  int get possibleSizeBytes => entries
      .where((entry) => entry.isPossible)
      .fold<int>(0, (sum, entry) => sum + entry.sizeBytes);

  int get cleanableBytes => entries
      .where((entry) => entry.isCleanable && entry.isConfirmed)
      .fold<int>(0, (sum, entry) => sum + entry.sizeBytes);

  int get bestKnownSizeBytes {
    if (confirmedSizeBytes > 0) return confirmedSizeBytes;
    return app.estimatedSizeBytes ?? 0;
  }

  MeasurementQuality get measurementQuality {
    if (confirmedSizeBytes == 0 && (app.estimatedSizeBytes ?? 0) > 0) {
      return MeasurementQuality.estimated;
    }
    if (entries.any(
      (entry) => entry.measurementQuality == MeasurementQuality.partial,
    )) {
      return MeasurementQuality.partial;
    }
    if (confirmedSizeBytes > 0) return MeasurementQuality.measured;
    return MeasurementQuality.unknown;
  }

  bool isStale({
    required DateTime now,
    required Duration threshold,
  }) {
    return usage.isStale(now: now, threshold: threshold);
  }
}

class AppStorageReport {
  final String drivePath;
  final List<AppStorageProfile> apps;
  final List<AppStorageEntry> sharedOrUnattributed;
  final List<String> warnings;
  final DateTime generatedAt;
  final bool isPartial;

  const AppStorageReport({
    required this.drivePath,
    required this.apps,
    required this.generatedAt,
    this.sharedOrUnattributed = const <AppStorageEntry>[],
    this.warnings = const <String>[],
    this.isPartial = false,
  });

  int get confirmedSizeBytes => apps.fold<int>(
        0,
        (sum, profile) => sum + profile.confirmedSizeBytes,
      );

  int get cleanableBytes => apps.fold<int>(
        0,
        (sum, profile) => sum + profile.cleanableBytes,
      );

  AppStorageProfile? findApp(String id) {
    for (final profile in apps) {
      if (profile.app.id == id) return profile;
    }
    return null;
  }
}

class InstalledAppInventoryResult {
  final List<InstalledAppInfo> apps;
  final List<String> warnings;
  final bool isPartial;

  const InstalledAppInventoryResult({
    required this.apps,
    this.warnings = const <String>[],
    this.isPartial = false,
  });
}
