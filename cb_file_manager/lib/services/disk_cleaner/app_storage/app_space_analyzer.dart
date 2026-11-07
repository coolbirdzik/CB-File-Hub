import 'dart:io';

import 'package:path/path.dart' as p;

import '../../app_insights/app_insights_models.dart';
import '../../app_insights/app_leftover_finder.dart';
import '../../app_insights/posix_app_leftover_finder.dart';
import '../editor_storage/editor_root_sizes.dart';
import '../editor_storage/editor_storage_analyzer.dart';
import '../editor_storage/editor_storage_models.dart';
import 'app_space_models.dart';
import 'chromium_layout.dart';
import 'running_processes.dart';
import '../storage_path_context.dart';

/// Where the current user's per-app folders are.
class AppSpaceEnvironment {
  /// `macos`, `windows` or `linux`.
  final String operatingSystem;
  final String home;
  final String? appData;
  final String? localAppData;
  final String? xdgConfig;
  final String? xdgData;
  final String? xdgCache;

  const AppSpaceEnvironment({
    required this.operatingSystem,
    required this.home,
    this.appData,
    this.localAppData,
    this.xdgConfig,
    this.xdgData,
    this.xdgCache,
  });

  static AppSpaceEnvironment? current() {
    final env = Platform.environment;
    final os = Platform.operatingSystem;
    final home = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
    if (home == null || home.isEmpty) return null;
    if (os != 'macos' && os != 'linux' && os != 'windows') return null;
    String? absolute(String key) {
      final value = env[key];
      return value != null && value.startsWith('/') ? value : null;
    }

    return AppSpaceEnvironment(
      operatingSystem: os,
      home: home,
      appData: env['APPDATA'],
      localAppData: env['LOCALAPPDATA'],
      xdgConfig: absolute('XDG_CONFIG_HOME'),
      xdgData: absolute('XDG_DATA_HOME'),
      xdgCache: absolute('XDG_CACHE_HOME'),
    );
  }

  // The OS selects the app layout; the home path selects its filesystem syntax.
  // This also permits exercising another OS's layout in a local fixture.
  p.Context get path => storagePathContext(home);

  EditorStorageEnvironment get editor => EditorStorageEnvironment(
    operatingSystem: operatingSystem,
    home: home,
    appData: appData,
  );
}

/// What a base folder's children are, before looking inside them.
enum _Base {
  appSupport,
  caches,
  logs,
  containers,
  groupContainers,
  webData,
  savedState,
  config,
  data,
  cache,
  flatpak,
  roaming,
  local,
  localLow,
  packages,
}

/// Measures, per installed app, what it keeps on disk and what of that can
/// go: its bundle or install folder, caches, logs, crash dumps, web storage
/// and the rest of its data. VS Code family editors also get their
/// extensions and workspaces ([EditorStorageAnalyzer]).
///
/// Folders are attributed to apps by the same rules the Leftovers page uses
/// ([PosixAppOwnership], [AppTokenIndex]); folders with no installed app are
/// left to that page. What is safe follows the folder layout, not the app
/// name: Chromium caches, old logs and crash dumps are checked; a whole
/// `Caches/<app>` folder is offered unchecked; documents, containers, web
/// storage and shared vendor data are only shown. Nothing is offered for an
/// app that is running.
///
/// Only reads. Every folder is sized in one [EditorRootSizer] walk, in
/// chunks so [analyze] can report progress.
class AppSpaceAnalyzer {
  /// Logs, crash dumps and downloads younger than this may be in use.
  static const minAge = Duration(days: 1);

  /// Windows folders shared by many apps or by Windows itself.
  static const _windowsShared = {
    'microsoft',
    'packages',
    'temp',
    'programs',
    'crashdumps',
    'd3dscache',
    'connecteddevicesplatform',
    'comms',
    'publishers',
    'placesdb',
    'virtualstore',
    'history',
    'iconcache.db',
    'nvidia',
    'nvidia corporation',
    'squirreltemp',
  };

  final AppSpaceEnvironment environment;
  final List<InstalledAppInfo> apps;
  final RunningProcesses processes;
  final EditorRootSizer sizer;
  final DateTime Function() now;
  final bool Function(int pid) isProcessAlive;

  AppSpaceAnalyzer({
    required this.environment,
    required this.apps,
    required this.processes,
    EditorRootSizer? sizer,
    DateTime Function()? now,
    bool Function(int pid)? isProcessAlive,
  }) : sizer = sizer ?? editorRootSizes,
       now = now ?? DateTime.now,
       isProcessAlive =
           isProcessAlive ?? EditorStorageAnalyzer.defaultProcessAlive;

  p.Context get _path => environment.path;

  /// [onPartial] receives the report once the data folders are sized and
  /// before the app bundles are (those hold the most files: Xcode alone has
  /// hundreds of thousands), so the list can show while they are measured.
  Future<AppSpaceReport> analyze({
    void Function(int done, int total)? onProgress,
    void Function(AppSpaceReport partial)? onPartial,
    int chunkSize = 400,
  }) async {
    final editors = await EditorStorageAnalyzer(
      environment: environment.editor,
      sizer: sizer,
      now: now,
      isProcessAlive: isProcessAlive,
    ).analyze();
    final editorRoots = {
      for (final report in editors)
        if (report.dataRoot case final root?) _key(root): report,
    };

    final plans = <String, _AppPlan>{};
    final roots = <String>[];
    _AppPlan planFor(InstalledAppInfo app) => plans.putIfAbsent(
      app.id,
      () => _AppPlan(
        app,
        processes.runs(app, installExecutables: _installExecutables(app)),
      ),
    );
    void add(
      _AppPlan plan,
      String path,
      AppSpaceKind kind, {
      AppSpaceTier tier = AppSpaceTier.review,
    }) {
      roots.add(path);
      plan.items.add(_Item(path, kind, tier, roots.length - 1));
    }

    final ownership = PosixAppOwnership(apps);
    final names = AppTokenIndex(apps);
    final attachedEditors = <EditorStorageReport>{};
    for (final (base, basePath) in _bases()) {
      for (final child in _list(basePath)) {
        if (!child.isDirectory && base != _Base.savedState) continue;
        if (child.name.startsWith('.')) continue;
        final owner = _owner(base, child.name, ownership, names);
        final app = owner.app;
        if (app == null) continue;
        final plan = planFor(app);
        final editor = editorRoots[_key(child.path)];
        if (editor != null) {
          plan.editor ??= editor;
          attachedEditors.add(editor);
          continue;
        }
        if (owner.kind == AppFolderOwnerKind.vendor ||
            base == _Base.groupContainers) {
          add(plan, child.path, AppSpaceKind.sharedData);
          continue;
        }
        _planFolder(plan, base, child, add);
      }
    }

    // Editors whose data folder belongs to no listed app still show.
    for (final editor in editors) {
      if (attachedEditors.contains(editor)) continue;
      final match = apps.where(
        (app) =>
            names.matchProductName(editor.editor.dataFolder) == app ||
            app.displayName.toLowerCase() == editor.editor.name.toLowerCase(),
      );
      final app = match.isNotEmpty
          ? match.first
          : InstalledAppInfo(
              id: 'editor:${editor.editor.dataFolder}',
              displayName: editor.editor.name,
              source: InstalledAppSource.executable,
            );
      planFor(app).editor ??= editor;
    }

    // Bundles last: they are the slowest to walk.
    final dataRoots = roots.length;
    final installs = <String>{};
    for (final app in apps) {
      // Commands on PATH and packages have no folder of their own.
      if (app.source == InstalledAppSource.executable) continue;
      final install = app.installLocation;
      if (install == null ||
          install.isEmpty ||
          !installs.add(_key(install)) ||
          !_isDirectory(install)) {
        continue;
      }
      // Windows lists system components under the Windows folder.
      if (environment.operatingSystem == 'windows' &&
          install.toLowerCase().contains(r'\windows\')) {
        continue;
      }
      add(planFor(app), install, AppSpaceKind.install);
    }

    final sizes = <EditorRootSize>[];
    onProgress?.call(0, roots.length);
    Future<void> sizeUpTo(int limit) async {
      while (sizes.length < limit) {
        final end = (sizes.length + chunkSize).clamp(0, limit);
        sizes.addAll(await sizer(roots.sublist(sizes.length, end)));
        onProgress?.call(sizes.length, roots.length);
      }
    }

    AppSpaceReport report({required bool complete}) => AppSpaceReport(
      entries: [
        for (final plan in plans.values)
          if (plan.build(sizes) case final entry when entry.totalBytes > 0)
            entry,
      ]..sort((a, b) => b.totalBytes.compareTo(a.totalBytes)),
      generatedAt: now(),
      complete: complete,
    );

    await sizeUpTo(dataRoots);
    if (dataRoots < roots.length) onPartial?.call(report(complete: false));
    await sizeUpTo(roots.length);
    return report(complete: true);
  }

  List<(_Base, String)> _bases() {
    final home = environment.home;
    final path = _path;
    switch (environment.operatingSystem) {
      case 'macos':
        final library = path.join(home, 'Library');
        return [
          (_Base.appSupport, path.join(library, 'Application Support')),
          (_Base.caches, path.join(library, 'Caches')),
          (_Base.logs, path.join(library, 'Logs')),
          (_Base.containers, path.join(library, 'Containers')),
          (_Base.groupContainers, path.join(library, 'Group Containers')),
          (_Base.webData, path.join(library, 'HTTPStorages')),
          (_Base.webData, path.join(library, 'WebKit')),
          (_Base.savedState, path.join(library, 'Saved Application State')),
        ];
      case 'linux':
        return [
          (_Base.config, environment.xdgConfig ?? path.join(home, '.config')),
          (
            _Base.data,
            environment.xdgData ?? path.join(home, '.local', 'share'),
          ),
          (_Base.cache, environment.xdgCache ?? path.join(home, '.cache')),
          (_Base.flatpak, path.join(home, '.var', 'app')),
        ];
      case 'windows':
        final local = environment.localAppData;
        return [
          if (environment.appData case final roaming?) (_Base.roaming, roaming),
          if (local != null) ...[
            (_Base.local, local),
            (_Base.localLow, path.join(path.dirname(local), 'LocalLow')),
            (_Base.packages, path.join(local, 'Packages')),
          ],
        ];
    }
    return const [];
  }

  AppFolderOwner _owner(
    _Base base,
    String name,
    PosixAppOwnership ownership,
    AppTokenIndex names,
  ) {
    InstalledAppInfo? byId(String id) {
      final lower = id.toLowerCase();
      for (final app in apps) {
        if (app.packageFamilyName?.toLowerCase() == lower) return app;
      }
      return null;
    }

    AppFolderOwner app(InstalledAppInfo? match) => match == null
        ? AppFolderOwner.none
        : AppFolderOwner(AppFolderOwnerKind.app, match);

    switch (base) {
      case _Base.appSupport:
      case _Base.logs:
      case _Base.webData:
        return ownership.of(AppLeftoverLocation.macApplicationSupport, name);
      case _Base.caches:
        return ownership.of(AppLeftoverLocation.macCaches, name);
      case _Base.savedState:
        if (!name.endsWith('.savedState')) return AppFolderOwner.none;
        return ownership.of(
          AppLeftoverLocation.macApplicationSupport,
          name.substring(0, name.length - '.savedState'.length),
        );
      case _Base.containers:
        return ownership.of(AppLeftoverLocation.macContainers, name);
      case _Base.groupContainers:
        return ownership.of(AppLeftoverLocation.macGroupContainers, name);
      case _Base.config:
        return ownership.of(AppLeftoverLocation.linuxConfig, name);
      case _Base.data:
        return ownership.of(AppLeftoverLocation.linuxData, name);
      case _Base.cache:
        return ownership.of(AppLeftoverLocation.linuxCache, name);
      case _Base.flatpak:
      case _Base.packages:
        return app(byId(name));
      case _Base.roaming:
      case _Base.local:
      case _Base.localLow:
        if (_windowsShared.contains(name.toLowerCase())) {
          return AppFolderOwner.system;
        }
        return app(names.matchProductName(name));
    }
  }

  void _planFolder(
    _AppPlan plan,
    _Base base,
    _Entry folder,
    void Function(
      _AppPlan plan,
      String path,
      AppSpaceKind kind, {
      AppSpaceTier tier,
    })
    add,
  ) {
    // While the app runs it may hold or rewrite any of this.
    final cacheTier = plan.running
        ? AppSpaceTier.review
        : AppSpaceTier.optional;
    switch (base) {
      case _Base.caches:
      case _Base.cache:
        add(plan, folder.path, AppSpaceKind.cache, tier: cacheTier);
      case _Base.logs:
        add(plan, folder.path, AppSpaceKind.logs, tier: cacheTier);
      case _Base.webData:
        add(plan, folder.path, AppSpaceKind.webStorage);
      case _Base.savedState:
        add(plan, folder.path, AppSpaceKind.settings);
      case _Base.groupContainers:
        add(plan, folder.path, AppSpaceKind.sharedData);
      case _Base.containers:
        _planContainer(plan, folder.path, cacheTier, add);
      case _Base.flatpak:
      case _Base.packages:
        // `~/.var/app/<id>/cache`, `Packages/<family>/LocalCache`.
        for (final child in _list(folder.path)) {
          final lower = child.name.toLowerCase();
          final isCache =
              lower == 'cache' || lower == 'localcache' || lower == 'tempstate';
          add(
            plan,
            child.path,
            isCache ? AppSpaceKind.cache : AppSpaceKind.userData,
            tier: isCache ? cacheTier : AppSpaceTier.review,
          );
        }
      case _Base.appSupport:
      case _Base.config:
      case _Base.data:
      case _Base.roaming:
      case _Base.local:
      case _Base.localLow:
        final children = _list(folder.path).toList();
        if (ChromiumLayout.matches(children.map((c) => c.name))) {
          _planChromium(plan, children, add);
          return;
        }
        final rest = base == _Base.config
            ? AppSpaceKind.settings
            : AppSpaceKind.userData;
        final caches = children.where(
          (c) => c.isDirectory && _isCacheName(c.name),
        );
        if (caches.isEmpty) {
          add(plan, folder.path, rest);
          return;
        }
        // Children one by one, so the cache folder is sized on its own.
        for (final child in children) {
          final isCache = child.isDirectory && _isCacheName(child.name);
          add(
            plan,
            child.path,
            isCache ? AppSpaceKind.cache : rest,
            tier: isCache ? cacheTier : AppSpaceTier.review,
          );
        }
    }
  }

  static bool _isCacheName(String name) {
    final lower = name.toLowerCase();
    return lower == 'cache' || lower == 'caches';
  }

  /// `Containers/<id>/Data/Library/Caches` is the app's cache; the rest of
  /// the container (documents, preferences, databases) is user data.
  void _planContainer(
    _AppPlan plan,
    String container,
    AppSpaceTier cacheTier,
    void Function(
      _AppPlan plan,
      String path,
      AppSpaceKind kind, {
      AppSpaceTier tier,
    })
    add,
  ) {
    final path = _path;
    final library = path.join(container, 'Data', 'Library');
    final caches = path.join(library, 'Caches');
    if (!_isDirectory(caches)) {
      add(plan, container, AppSpaceKind.userData);
      return;
    }
    for (final child in _list(container)) {
      if (child.name != 'Data') add(plan, child.path, AppSpaceKind.userData);
    }
    for (final child in _list(path.join(container, 'Data'))) {
      if (child.name != 'Library') add(plan, child.path, AppSpaceKind.userData);
    }
    for (final child in _list(library)) {
      if (child.name != 'Caches') add(plan, child.path, AppSpaceKind.userData);
    }
    add(plan, caches, AppSpaceKind.cache, tier: cacheTier);
  }

  /// The same rules as the editors' data folder: caches go when the app is
  /// closed; logs except the newest session, crash dumps and VSIX downloads
  /// once a day old; web storage and everything else stays.
  void _planChromium(
    _AppPlan plan,
    List<_Entry> children,
    void Function(
      _AppPlan plan,
      String path,
      AppSpaceKind kind, {
      AppSpaceTier tier,
    })
    add,
  ) {
    final cutoff = now().subtract(minAge);
    bool old(_Entry entry) {
      final modified = entry.modified();
      return modified != null && !modified.isAfter(cutoff);
    }

    void aged(String folder, AppSpaceKind kind, {bool keepNewest = false}) {
      final entries = _list(folder).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (var i = 0; i < entries.length; i++) {
        final newest = keepNewest && i == entries.length - 1;
        add(
          plan,
          entries[i].path,
          kind,
          tier: !newest && old(entries[i])
              ? AppSpaceTier.safe
              : AppSpaceTier.review,
        );
      }
    }

    for (final child in children) {
      final lower = child.name.toLowerCase();
      if (child.isDirectory && ChromiumLayout.cacheFolders.contains(lower)) {
        add(
          plan,
          child.path,
          AppSpaceKind.cache,
          tier: plan.running ? AppSpaceTier.review : AppSpaceTier.safe,
        );
      } else if (child.isDirectory && lower == 'logs') {
        aged(child.path, AppSpaceKind.logs, keepNewest: true);
      } else if (child.isDirectory && lower == 'cachedextensionvsixs') {
        aged(child.path, AppSpaceKind.extensionDownloads);
      } else if (child.isDirectory && lower == 'crashpad') {
        for (final entry in _list(child.path)) {
          final reports = ChromiumLayout.crashReportFolders.contains(
            entry.name.toLowerCase(),
          );
          if (!(entry.isDirectory && reports)) {
            add(plan, entry.path, AppSpaceKind.crashReports);
            continue;
          }
          for (final dump in _list(entry.path)) {
            add(
              plan,
              dump.path,
              AppSpaceKind.crashReports,
              tier:
                  !dump.isDirectory &&
                      dump.name.toLowerCase().endsWith('.dmp') &&
                      old(dump)
                  ? AppSpaceTier.safe
                  : AppSpaceTier.review,
            );
          }
        }
      } else if (ChromiumLayout.webStorageFolders.contains(lower)) {
        add(plan, child.path, AppSpaceKind.webStorage);
      } else {
        add(plan, child.path, AppSpaceKind.userData);
      }
    }
  }

  /// `.exe` files at the top of a Windows app's install folder.
  List<String> _installExecutables(InstalledAppInfo app) {
    final install = app.installLocation;
    if (environment.operatingSystem != 'windows' ||
        install == null ||
        install.isEmpty) {
      return const [];
    }
    return [
      for (final entry in _list(install))
        if (!entry.isDirectory && entry.name.toLowerCase().endsWith('.exe'))
          entry.path,
    ];
  }

  String _key(String path) => environment.operatingSystem == 'linux'
      ? _path.normalize(path)
      : _path.normalize(path).toLowerCase();

  static bool _isDirectory(String path) =>
      FileSystemEntity.isDirectorySync(path);

  Iterable<_Entry> _list(String folder) sync* {
    final List<FileSystemEntity> entities;
    try {
      entities = Directory(folder).listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entity in entities) {
      yield _Entry(
        entity.path,
        _path.basename(entity.path),
        entity is Directory,
      );
    }
  }
}

class _Entry {
  final String path;
  final String name;
  final bool isDirectory;

  const _Entry(this.path, this.name, this.isDirectory);

  DateTime? modified() {
    try {
      return FileStat.statSync(path).modified;
    } on FileSystemException {
      return null;
    }
  }
}

class _Item {
  final String path;
  final AppSpaceKind kind;
  final AppSpaceTier tier;
  final int root;

  const _Item(this.path, this.kind, this.tier, this.root);
}

class _AppPlan {
  final InstalledAppInfo app;
  final bool running;
  final items = <_Item>[];
  EditorStorageReport? editor;

  _AppPlan(this.app, this.running);

  AppSpaceEntry build(List<EditorRootSize> sizes) => AppSpaceEntry(
    app: app,
    isRunning: running || (editor?.isRunning ?? false),
    items: [
      for (final item in items)
        if (item.root < sizes.length && sizes[item.root].exists)
          AppSpaceItem(
            path: item.path,
            kind: item.kind,
            tier: item.tier,
            bytes: sizes[item.root].bytes,
          ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes)),
    editor: editor,
    unreadable:
        items
            .where((item) => item.root < sizes.length)
            .fold<int>(0, (sum, item) => sum + sizes[item.root].unreadable) +
        (editor?.unreadable ?? 0),
  );
}
