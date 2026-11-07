import '../../app_insights/app_insights_models.dart';
import 'app_space_models.dart';

/// The Apps page on macOS and Linux, built from the App storage scan rather
/// than from a full-drive scan (Windows): one walk of the per-user app
/// folders and app bundles feeds both pages.
abstract final class AppSpaceInsights {
  /// Commands on `PATH` and packages are not apps a person opens; App
  /// storage still lists them when they own data.
  static bool isListed(InstalledAppInfo app) =>
      app.source != InstalledAppSource.executable;

  static AppStorageReport toAppStorageReport(
    AppSpaceReport report, {
    Map<String, AppUsageEvidence> usageByAppId = const {},
    List<String> warnings = const [],
    bool? isPartial,
  }) {
    return AppStorageReport(
      drivePath: '/',
      generatedAt: report.generatedAt,
      // App bundles not measured (a cancelled scan): sizes are lower bounds.
      // Callers pass false while the scan still runs and says so itself.
      isPartial: isPartial ?? !report.complete,
      warnings: warnings,
      apps: [
        for (final entry in report.entries)
          if (isListed(entry.app))
            AppStorageProfile(
              app: entry.app,
              usage: usageByAppId[entry.app.id] ?? const AppUsageEvidence(),
              entries: _entries(entry),
            ),
      ],
    );
  }

  static List<AppStorageEntry> _entries(AppSpaceEntry entry) {
    final quality = entry.unreadable > 0
        ? MeasurementQuality.partial
        : MeasurementQuality.measured;
    final entries = <AppStorageEntry>[
      for (final item in entry.items)
        AppStorageEntry(
          path: item.path,
          kind: kindOf(item.kind),
          sizeBytes: item.bytes,
          measurementQuality: quality,
          attributionConfidence: item.kind == AppSpaceKind.sharedData
              ? AttributionConfidence.shared
              : AttributionConfidence.confirmed,
          isCleanable: item.isCleanable,
        ),
    ];
    final editor = entry.editor;
    if (editor != null) {
      final cleanable = editor.safeBytes;
      if (editor.dataRoot case final root?) {
        final bytes = editor.totalBytes - editor.extensionInstallBytes;
        entries.add(
          AppStorageEntry(
            path: root,
            kind: AppStorageKind.localData,
            sizeBytes: bytes,
            measurementQuality: quality,
            attributionConfidence: AttributionConfidence.confirmed,
            isCleanable: cleanable > 0,
          ),
        );
      }
      if (editor.extensionsRoot case final root?) {
        entries.add(
          AppStorageEntry(
            path: root,
            kind: AppStorageKind.localData,
            sizeBytes: editor.extensionInstallBytes,
            measurementQuality: quality,
            attributionConfidence: AttributionConfidence.confirmed,
          ),
        );
      }
    }
    return entries;
  }

  static AppStorageKind kindOf(AppSpaceKind kind) => switch (kind) {
    AppSpaceKind.install => AppStorageKind.install,
    AppSpaceKind.cache => AppStorageKind.cache,
    AppSpaceKind.logs || AppSpaceKind.crashReports => AppStorageKind.logs,
    AppSpaceKind.sharedData => AppStorageKind.shared,
    AppSpaceKind.userData ||
    AppSpaceKind.settings ||
    AppSpaceKind.webStorage ||
    AppSpaceKind.extensionDownloads => AppStorageKind.localData,
  };
}

/// macOS apps the Apps page never moves to the Trash: Apple's own (under
/// `/System`, or with a `com.apple.` bundle id, such as Safari in
/// `/Applications`) and CB File Hub itself.
bool macAppIsProtected(
  String bundle, {
  String? bundleId,
  required String ownExecutable,
}) {
  final path = bundle.endsWith('/')
      ? bundle.substring(0, bundle.length - 1)
      : bundle;
  return path.startsWith('/System/') ||
      (bundleId?.toLowerCase().startsWith('com.apple.') ?? false) ||
      ownExecutable == path ||
      ownExecutable.startsWith('$path/');
}
