import '../../app_insights/app_insights_models.dart';
import '../docker/docker_storage.dart';
import '../editor_storage/editor_storage_models.dart';

/// What a file or folder holds for its app.
enum AppSpaceKind {
  /// The app itself: its `.app` bundle or install folder.
  install,

  /// Caches the app rebuilds or downloads again.
  cache,

  /// Session and diagnostic logs.
  logs,

  /// Crash dumps.
  crashReports,

  /// Downloaded installers (VSIX).
  extensionDownloads,

  /// Web storage of embedded web views: cookies, IndexedDB, service workers.
  webStorage,

  /// Documents, databases, accounts and other state the app keeps.
  userData,

  /// Data shared by apps of the same vendor (macOS group containers and
  /// vendor folders).
  sharedData,

  /// Preferences and saved window state.
  settings,
}

/// How safe it is to remove an [AppSpaceItem].
enum AppSpaceTier {
  /// Regenerable by a known layout (Chromium cache folders, old logs and
  /// crash dumps, old VSIX downloads): checked when results arrive.
  safe,

  /// Usually regenerable, but kept by default: a whole `Caches/<app>`
  /// folder or a logs folder an app may still read.
  optional,

  /// Only shown. Never selectable.
  review,
}

class AppSpaceItem {
  final String path;
  final AppSpaceKind kind;
  final AppSpaceTier tier;
  final int bytes;

  /// The cleanup row of its own, when [kind] would mix things a person wants
  /// to choose between (Xcode's Device Support and Derived Data are caches).
  final AppCleanKind? cleanGroup;

  /// Shown in place of the path in its cleanup row.
  final String? label;

  const AppSpaceItem({
    required this.path,
    required this.kind,
    required this.tier,
    required this.bytes,
    this.cleanGroup,
    this.label,
  });

  bool get isCleanable => tier != AppSpaceTier.review;
}

/// Everything found for one installed app.
class AppSpaceEntry {
  final InstalledAppInfo app;

  /// A process runs from the app's bundle or install folder: its caches and
  /// current logs are then not offered.
  final bool isRunning;
  final List<AppSpaceItem> items;

  /// For VS Code family editors: extensions, their storage and workspaces.
  /// Its data folder is not repeated in [items].
  final EditorStorageReport? editor;

  /// Folders whose size could not be read (no permission).
  final int unreadable;

  const AppSpaceEntry({
    required this.app,
    required this.isRunning,
    required this.items,
    this.editor,
    this.unreadable = 0,
  });

  String get key => app.id;

  int get itemBytes => items.fold<int>(0, (sum, item) => sum + item.bytes);

  int get totalBytes => itemBytes + (editor?.totalBytes ?? 0);

  int bytesOf(AppSpaceKind kind) => items
      .where((item) => item.kind == kind)
      .fold<int>(0, (sum, item) => sum + item.bytes);

  int tierBytes(AppSpaceTier tier) => items
      .where((item) => item.tier == tier)
      .fold<int>(0, (sum, item) => sum + item.bytes);

  /// Safe bytes here and in the editor report.
  int get safeBytes => tierBytes(AppSpaceTier.safe) + (editor?.safeBytes ?? 0);

  AppSpaceEntry withoutPaths(Set<String> removed) => AppSpaceEntry(
    app: app,
    isRunning: isRunning,
    items: [
      for (final item in items)
        if (!removed.contains(item.path)) item,
    ],
    editor: editor?.withoutPaths(removed),
    unreadable: unreadable,
  );
}

class AppSpaceReport {
  /// Largest first.
  final List<AppSpaceEntry> entries;
  final DateTime generatedAt;

  /// False while app bundles are still being measured: their install sizes
  /// are missing.
  final bool complete;

  /// Docker's images, containers, volumes and build cache, read through its
  /// CLI. Null until read (it arrives with the complete report).
  final DockerReport? docker;

  const AppSpaceReport({
    required this.entries,
    required this.generatedAt,
    this.complete = true,
    this.docker,
  });

  AppSpaceReport withDocker(DockerReport? docker) => AppSpaceReport(
    entries: entries,
    generatedAt: generatedAt,
    complete: complete,
    docker: docker,
  );

  /// The installed app that Docker's images and containers belong to: they
  /// are shown inside its row. Docker without an app (Colima, a plain dockerd)
  /// has no such entry and keeps a row of its own.
  AppSpaceEntry? get dockerApp {
    final status = docker?.status;
    if (status == null || status == DockerStatus.notInstalled) return null;
    return entries.where((entry) {
      final app = entry.app;
      if (app.source == InstalledAppSource.executable) return false;
      final name = app.displayName.toLowerCase();
      return app.packageFamilyName?.toLowerCase() == 'com.docker.docker' ||
          name == 'docker' ||
          name == 'docker desktop';
    }).firstOrNull;
  }

  int get totalBytes => entries.fold<int>(0, (sum, e) => sum + e.totalBytes);

  int get safeBytes => entries.fold<int>(0, (sum, e) => sum + e.safeBytes);

  int get unreadable => entries.fold<int>(0, (sum, e) => sum + e.unreadable);

  AppSpaceReport withoutPaths(Set<String> removed) => removed.isEmpty
      ? this
      : AppSpaceReport(
          entries: [for (final e in entries) e.withoutPaths(removed)],
          generatedAt: generatedAt,
          complete: complete,
          docker: docker,
        );
}

/// What a cleanup row removes.
enum AppCleanKind {
  obsoleteExtensions,
  cache,
  extensionDownloads,
  logs,
  crashReports,
  missingWorkspaces,
  xcodeDeviceSupport,
  xcodeArchives,
  xcodeDerivedData,
  xcodeDocumentationCache,
  xcodeOldLogs,
  xcodeOldDocumentationDownloads,
}

/// Targets of one kind and tier in one app, checked together.
class AppCleanGroup {
  final String id;
  final AppSpaceEntry entry;
  final AppCleanKind kind;

  /// [AppSpaceTier.safe] groups start checked, [AppSpaceTier.optional] ones
  /// do not.
  final AppSpaceTier tier;
  final List<EditorCleanTarget> targets;

  const AppCleanGroup({
    required this.id,
    required this.entry,
    required this.kind,
    required this.tier,
    required this.targets,
  });

  int get bytes => targets.fold<int>(0, (sum, t) => sum + t.bytes);

  bool get selectedByDefault => tier == AppSpaceTier.safe;

  static List<AppCleanGroup> of(AppSpaceEntry entry) {
    final groups = <AppCleanGroup>[];
    void add(
      AppCleanKind kind,
      AppSpaceTier tier,
      Iterable<EditorCleanTarget> targets, {
      String source = 'data',
    }) {
      final list = List<EditorCleanTarget>.unmodifiable(targets);
      if (list.isEmpty) return;
      groups.add(
        AppCleanGroup(
          id: '${entry.key}/$source/${kind.name}/${tier.name}',
          entry: entry,
          kind: kind,
          tier: tier,
          targets: list,
        ),
      );
    }

    final editor = entry.editor;
    if (editor != null) {
      for (final group in EditorCleanGroup.of(editor)) {
        final (kind, tier) = switch (group.kind) {
          EditorCleanGroupKind.obsoleteExtensions => (
            AppCleanKind.obsoleteExtensions,
            AppSpaceTier.safe,
          ),
          EditorCleanGroupKind.cache => (AppCleanKind.cache, AppSpaceTier.safe),
          EditorCleanGroupKind.extensionDownloads => (
            AppCleanKind.extensionDownloads,
            AppSpaceTier.safe,
          ),
          EditorCleanGroupKind.logs => (AppCleanKind.logs, AppSpaceTier.safe),
          EditorCleanGroupKind.crashReports => (
            AppCleanKind.crashReports,
            AppSpaceTier.safe,
          ),
          EditorCleanGroupKind.missingWorkspaces => (
            AppCleanKind.missingWorkspaces,
            AppSpaceTier.optional,
          ),
        };
        add(kind, tier, group.targets, source: 'editor');
      }
    }
    for (final tier in [AppSpaceTier.safe, AppSpaceTier.optional]) {
      for (final (kind, clean) in [
        (AppSpaceKind.cache, AppCleanKind.cache),
        (AppSpaceKind.logs, AppCleanKind.logs),
        (AppSpaceKind.crashReports, AppCleanKind.crashReports),
        (AppSpaceKind.extensionDownloads, AppCleanKind.extensionDownloads),
      ]) {
        add(clean, tier, [
          for (final item in entry.items)
            if (item.cleanGroup == null &&
                item.kind == kind &&
                item.tier == tier)
              EditorCleanTarget(item.path, item.bytes, label: item.label),
        ]);
      }
    }
    for (final clean in AppCleanKind.values) {
      add(clean, AppSpaceTier.optional, [
        for (final item in entry.items)
          if (item.cleanGroup == clean && item.isCleanable)
            EditorCleanTarget(item.path, item.bytes, label: item.label),
      ]);
    }
    return groups;
  }
}
