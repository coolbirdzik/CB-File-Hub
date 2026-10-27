import '../app_insights/app_insights_models.dart';
import 'cleaner_categories.dart';
import 'cleaner_installed_apps.dart';
import 'cleaner_models.dart';

/// What a junk file is, for explaining it before it is removed.
enum CleanerItemKind {
  webCache,
  codeCache,
  gpuCache,
  appCache,
  thumbnailCache,
  tempFile,
  installer,
  log,
  crashReport,
  deletedFile,
  other,
  packageDownload,
  buildCache,
  analysisCache,
}

/// What removing an item costs the user.
enum CleanerItemImpact {
  /// The app recreates it when it needs it again.
  rebuilt,

  /// Nothing uses it any more.
  leftover,

  /// Only useful for troubleshooting or reporting a crash.
  diagnostic,

  /// Cannot be restored.
  permanent,

  /// A later install or restore may download this archive again.
  redownload,
}

/// Which app made a junk item and what the item is.
///
/// Display only: nothing here decides what gets cleaned. Selection stays with
/// [CleanerCategories] and [CleanerQuickClean].
class CleanerItemOrigin {
  /// Display name of the app that created the item; null when unknown.
  final String? app;

  /// True when [app] is only the name of the folder holding the item, not a
  /// recognised app.
  final bool appIsFolder;

  final CleanerItemKind kind;

  /// The installed app [app] was matched to, for its icon and an "installed"
  /// label. Null when the app is not in the installed-app inventory, which
  /// misses portable and command-line tools, so null never means uninstalled.
  final InstalledAppInfo? installedApp;

  const CleanerItemOrigin({
    this.app,
    this.appIsFolder = false,
    required this.kind,
    this.installedApp,
  });

  /// Groups items that share an app and a kind.
  String get key {
    final installed = installedApp;
    if (installed != null) return 'app:${installed.id}/${kind.name}';
    return '${appIsFolder ? 'dir:' : ''}${app?.toLowerCase() ?? '?'}/${kind.name}';
  }

  CleanerItemImpact get impact => switch (kind) {
    CleanerItemKind.webCache ||
    CleanerItemKind.codeCache ||
    CleanerItemKind.gpuCache ||
    CleanerItemKind.buildCache ||
    CleanerItemKind.analysisCache ||
    CleanerItemKind.appCache ||
    CleanerItemKind.thumbnailCache => CleanerItemImpact.rebuilt,
    CleanerItemKind.tempFile ||
    CleanerItemKind.installer ||
    CleanerItemKind.other => CleanerItemImpact.leftover,
    CleanerItemKind.log ||
    CleanerItemKind.crashReport => CleanerItemImpact.diagnostic,
    CleanerItemKind.deletedFile => CleanerItemImpact.permanent,
    CleanerItemKind.packageDownload => CleanerItemImpact.redownload,
  };

  @override
  bool operator ==(Object other) =>
      other is CleanerItemOrigin &&
      other.app == app &&
      other.appIsFolder == appIsFolder &&
      other.kind == kind &&
      other.installedApp?.id == installedApp?.id;

  @override
  int get hashCode => Object.hash(app, appIsFolder, kind, installedApp?.id);

  @override
  String toString() => 'CleanerItemOrigin($key)';
}

/// Works out [CleanerItemOrigin] from a junk item's path.
///
/// Signals, strongest first: the executable named by a crash dump or error
/// report, the owner of the cleaner rule the path falls under, a known vendor
/// folder, a known %TEMP% scratch-folder prefix, then the installed apps
/// ([CleanerInstalledApps]: install folder, then exact folder or file name),
/// and finally the folder the item sits in. Random-looking folder names are
/// left unattributed rather than guessed at.
class CleanerItemOrigins {
  CleanerItemOrigins._();

  static CleanerItemOrigin of(JunkItem item, {CleanerInstalledApps? apps}) {
    final origin = _builtIn(item);
    if (apps == null ||
        apps.isEmpty ||
        origin.kind == CleanerItemKind.deletedFile) {
      return origin;
    }
    return _withInstalled(origin, item, apps);
  }

  static CleanerItemOrigin _builtIn(JunkItem item) {
    if (item.isRecycleBinItem || item.categoryId == 'recycle_bin') {
      return const CleanerItemOrigin(kind: CleanerItemKind.deletedFile);
    }
    final segments = item.path
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return const CleanerItemOrigin(kind: CleanerItemKind.other);
    }
    final lower = segments.map((s) => s.toLowerCase()).toList(growable: false);
    final name = lower.last;
    final category = item.categoryId;
    if (category == 'xcode_build_cache') {
      return const CleanerItemOrigin(
        app: 'Xcode',
        kind: CleanerItemKind.buildCache,
      );
    }

    if (category == 'thumbnail_cache') {
      return const CleanerItemOrigin(
        app: 'Windows Explorer',
        kind: CleanerItemKind.thumbnailCache,
      );
    }
    if (category == 'package_download_cache' ||
        category == 'developer_download_cache') {
      return CleanerItemOrigin(
        app: _ruleOwner(lower),
        kind: CleanerItemKind.packageDownload,
      );
    }
    if (category == 'developer_analysis_cache' ||
        category == 'electron_crash_reports') {
      return CleanerItemOrigin(
        app: _ruleOwner(lower),
        kind: category == 'developer_analysis_cache'
            ? CleanerItemKind.analysisCache
            : CleanerItemKind.crashReport,
      );
    }
    if (category == 'system_cache') {
      return const CleanerItemOrigin(
        app: 'Windows',
        kind: CleanerItemKind.gpuCache,
      );
    }

    final crashApp = _crashApp(segments, lower);
    final isCrash =
        crashApp != null ||
        lower.any(_crashSegments.contains) ||
        _crashExtensions.any(name.endsWith);
    if (isCrash) {
      return CleanerItemOrigin(
        app: crashApp,
        kind: CleanerItemKind.crashReport,
      );
    }

    if (category == 'windows_temp') return _temp(segments, lower, name);

    final owner = _ruleOwner(lower) ?? _vendor(lower);
    final folder = owner == null ? _appDataFolder(segments, lower) : null;
    return CleanerItemOrigin(
      app: owner ?? folder,
      appIsFolder: owner == null && folder != null,
      kind: _cacheKind(category, lower, name),
    );
  }

  // ---------------------------------------------------------------------------
  // Installed apps
  // ---------------------------------------------------------------------------

  /// Names for Windows itself, which the inventory does not list.
  static const Set<String> _unlinked = {'Windows', 'Windows Explorer'};

  static CleanerItemOrigin _withInstalled(
    CleanerItemOrigin origin,
    JunkItem item,
    CleanerInstalledApps apps,
  ) {
    final app = origin.app;
    if (app != null && !origin.appIsFolder) {
      if (_unlinked.contains(app)) return origin;
      final installed = _linkKnown(app, apps);
      if (installed == null) return origin;
      // A crash dump names only the executable; show the app instead.
      final name = app.toLowerCase().endsWith('.exe')
          ? CleanerInstalledApps.displayName(installed)
          : app;
      return CleanerItemOrigin(
        app: name,
        kind: origin.kind,
        installedApp: installed,
      );
    }

    final segments = item.path
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    final lower = segments.map((s) => s.toLowerCase()).toList(growable: false);
    final installed =
        apps.byInstallRoot(lower) ??
        _byNames(_nameCandidates(item.categoryId, segments, lower), apps);
    if (installed == null) return origin;
    return CleanerItemOrigin(
      app: CleanerInstalledApps.displayName(installed),
      kind: origin.kind,
      installedApp: installed,
    );
  }

  /// The installed entry for a name this file already produced: through its
  /// executables, then its exact name.
  static InstalledAppInfo? _linkKnown(String app, CleanerInstalledApps apps) {
    if (app.toLowerCase().endsWith('.exe')) return apps.byExe(app);
    for (final exe in _exesByApp[app] ?? const <String>{}) {
      final installed = apps.byExe(exe);
      if (installed != null) return installed;
    }
    return apps.byExactName(app);
  }

  /// Executables of the apps this file names, from the rule hints.
  static final Map<String, Set<String>> _exesByApp = () {
    final map = <String, Set<String>>{};
    void add(String app, String exe) =>
        (map[app] ??= <String>{}).add(exe.toLowerCase());
    for (final entry in _extraExeNames.entries) {
      add(entry.value, entry.key);
    }
    for (final rule in _hintedRules()) {
      for (final hint in rule.appOwnerHints) {
        if (hint.toLowerCase().endsWith('.exe')) {
          add(rule.appOwnerHints.first, hint);
        }
      }
    }
    for (final (app, exe) in const [
      ('Brave', 'brave.exe'),
      ('Opera', 'opera.exe'),
      ('Vivaldi', 'vivaldi.exe'),
    ]) {
      add(app, exe);
    }
    return map;
  }();

  /// Folder and file names that may name the app, most specific first.
  static List<String> _nameCandidates(
    String category,
    List<String> segments,
    List<String> lower,
  ) {
    if (category == 'windows_temp') {
      final root = _tempRoot(lower);
      if (root < 0 || root + 1 >= segments.length) return const [];
      // A file directly in %TEMP%: only its own name.
      if (root + 1 == segments.length - 1) return [segments.last];
      final top = segments[root + 1];
      // A file's own name counts only right below the top folder
      // (`Pkg\WarpSetup.exe`): deeper files are named after their content,
      // not after the app that made the folder.
      final shallowFile = root + 2 == segments.length - 1;
      if (!_isRandom(top)) return [top, if (shallowFile) segments.last];
      // `cnj5fx13.dxy\resources\app\…`: look a few folders deeper.
      return [
        for (var i = root + 2; i < segments.length - 1 && i <= root + 6; i++)
          if (!_isRandom(segments[i])) segments[i],
        if (shallowFile) segments.last,
      ];
    }
    for (var i = 0; i < lower.length - 2; i++) {
      final base =
          (lower[i] == 'appdata' &&
              (lower[i + 1] == 'local' || lower[i + 1] == 'roaming')) ||
          (lower[i] == 'library' && lower[i + 1] == 'caches');
      if (!base) continue;
      return [
        for (var j = i + 2; j < segments.length - 1 && j <= i + 3; j++)
          if (!_isRandom(segments[j])) segments[j],
      ];
    }
    return const [];
  }

  static InstalledAppInfo? _byNames(
    List<String> names,
    CleanerInstalledApps apps,
  ) {
    for (final name in names) {
      final app = apps.byName(name);
      if (app != null) return app;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Kinds
  // ---------------------------------------------------------------------------

  static const Set<String> _gpuSegments = {
    'gpucache',
    'shadercache',
    'grshadercache',
    'graphitedawncache',
    'dawncache',
    'dawngraphitecache',
    'dawnwebgpucache',
  };

  static const Set<String> _codeSegments = {'code cache', 'cacheddata'};

  static const Set<String> _webSegments = {
    'cache',
    'cache2',
    'cache_data',
    'cachestorage',
    'service worker',
    'startupcache',
    'media cache',
  };

  static const Set<String> _crashSegments = {
    'crashdumps',
    'wer',
    'diagnosticreports',
    'crashpad',
    'crashes',
  };

  static const List<String> _crashExtensions = [
    '.dmp',
    '.mdmp',
    '.hdmp',
    '.wer',
    '.ips',
    '.crash',
  ];

  static const List<String> _logExtensions = [
    '.log',
    '.log.old',
    '.etl',
    '.trace',
  ];

  static const List<String> _installerExtensions = [
    '.msi',
    '.msp',
    '.msu',
    '.cab',
    '.exe',
    '.msix',
    '.msixbundle',
    '.appx',
    '.zip',
    '.7z',
    '.rar',
    '.nupkg',
  ];

  static CleanerItemKind _cacheKind(
    String category,
    List<String> lower,
    String name,
  ) {
    if (lower.any(_gpuSegments.contains)) return CleanerItemKind.gpuCache;
    if (lower.any(_codeSegments.contains)) return CleanerItemKind.codeCache;
    if (_logExtensions.any(name.endsWith)) return CleanerItemKind.log;
    if ((category == 'browser_cache' || category == 'electron_cache') &&
        lower.any(_webSegments.contains)) {
      return CleanerItemKind.webCache;
    }
    if (category == 'browser_cache' ||
        category == 'app_cache' ||
        category == 'electron_cache') {
      return CleanerItemKind.appCache;
    }
    return CleanerItemKind.other;
  }

  // ---------------------------------------------------------------------------
  // Crash reports
  // ---------------------------------------------------------------------------

  /// `CrashDumps\chrome.exe.1234.dmp`
  static final RegExp _dumpName = RegExp(
    r'^(.+?\.exe)\.\d+\.[a-z]*dmp$',
    caseSensitive: false,
  );

  /// `WER\ReportArchive\AppCrash_chrome.exe_6c3f…`
  static final RegExp _werFolder = RegExp(
    r'^(?:AppCrash|AppHang|BEX64|BEX|NonCritical|Critical|CLR20r3)_(.+?\.exe)_',
    caseSensitive: false,
  );

  /// `WER\ReportArchive\Kernel_141_…`, `LiveKernelEvent_…`
  static final RegExp _werKernel = RegExp(
    r'^(?:Kernel|LiveKernelEvent|BlueScreen)_',
    caseSensitive: false,
  );

  /// `DiagnosticReports/Safari-2026-10-01-120000.ips`
  static final RegExp _macReport = RegExp(r'^(.+?)[-_]\d{4}-\d{2}-\d{2}');

  static String? _crashApp(List<String> segments, List<String> lower) {
    if (lower.contains('crashdumps')) {
      final match = _dumpName.firstMatch(segments.last);
      if (match != null) return _exeName(match.group(1)!);
    }
    if (lower.contains('wer')) {
      for (final segment in segments) {
        final match = _werFolder.firstMatch(segment);
        if (match != null) return _exeName(match.group(1)!);
        if (_werKernel.hasMatch(segment)) return 'Windows';
      }
    }
    if (lower.contains('diagnosticreports')) {
      final match = _macReport.firstMatch(segments.last);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// A friendly name for [exe] when a rule or [_extraExeNames] knows it, the
  /// executable's own name otherwise.
  static String _exeName(String exe) =>
      _exeNames[exe.toLowerCase()] ?? _extraExeNames[exe.toLowerCase()] ?? exe;

  static const Map<String, String> _extraExeNames = {
    'explorer.exe': 'Windows Explorer',
    'firefox.exe': 'Firefox',
    'msedgewebview2.exe': 'Microsoft Edge WebView2',
    'onedrive.exe': 'OneDrive',
    'steam.exe': 'Steam',
    'searchhost.exe': 'Windows Search',
    'cb_file_manager.exe': 'CB File Hub',
  };

  // ---------------------------------------------------------------------------
  // Rule owners and vendors
  // ---------------------------------------------------------------------------

  static List<CleanerPathRule> _hintedRules() => [
    for (final os in const ['windows', 'macos'])
      for (final category in CleanerCategories.all(operatingSystem: os))
        for (final rule in category.rules)
          if (rule.appOwnerHints.isNotEmpty) rule,
  ];

  /// Rule paths as lower-case segment runs, each with its owner's name.
  /// Longest first, so a nested rule beats its parent.
  static final List<(List<String>, String)> _ruleOwners = () {
    final owners = [
      for (final rule in _hintedRules())
        if (rule.source.relative.isNotEmpty)
          (
            rule.source.relative
                .toLowerCase()
                .split(RegExp(r'[\\/]'))
                .where((s) => s.isNotEmpty)
                .toList(growable: false),
            rule.appOwnerHints.first,
          ),
    ];
    owners.sort((a, b) => b.$1.length.compareTo(a.$1.length));
    return owners;
  }();

  static final Map<String, String> _exeNames = {
    for (final rule in _hintedRules())
      for (final hint in rule.appOwnerHints)
        if (hint.toLowerCase().endsWith('.exe'))
          hint.toLowerCase(): rule.appOwnerHints.first,
  };

  /// Vendor folders for apps whose rules carry no owner hint (Firefox's
  /// profile rule, the macOS caches) or for other profiles of a hinted app.
  static const List<(List<String>, String)> _vendors = [
    (['mozilla', 'firefox'], 'Firefox'),
    (['google', 'chrome'], 'Google Chrome'),
    (['microsoft', 'edge'], 'Microsoft Edge'),
    (['bravesoftware', 'brave-browser'], 'Brave'),
    (['opera software'], 'Opera'),
    (['vivaldi'], 'Vivaldi'),
    (['com.apple.safari'], 'Safari'),
    (['caches', 'firefox'], 'Firefox'),
    (['caches', 'microsoft edge'], 'Microsoft Edge'),
    (['com.google.chrome'], 'Google Chrome'),
    (['com.spotify.client'], 'Spotify'),
    (['com.microsoft.vscode'], 'Microsoft Visual Studio Code'),
  ];

  static String? _ruleOwner(List<String> lower) {
    for (final (run, owner) in _ruleOwners) {
      if (_containsRun(lower, run)) return owner;
    }
    return null;
  }

  static String? _vendor(List<String> lower) {
    for (final (run, name) in _vendors) {
      if (_containsRun(lower, run)) return name;
    }
    return null;
  }

  static bool _containsRun(List<String> haystack, List<String> run) {
    if (run.isEmpty || run.length > haystack.length) return false;
    outer:
    for (var i = 0; i <= haystack.length - run.length; i++) {
      for (var j = 0; j < run.length; j++) {
        if (haystack[i + j] != run[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  /// The folder directly under `AppData\Local`, `AppData\Roaming` or
  /// `Library/Caches`, which is usually named after the app.
  static String? _appDataFolder(List<String> segments, List<String> lower) {
    for (var i = 0; i < lower.length - 2; i++) {
      final base =
          (lower[i] == 'appdata' &&
              (lower[i + 1] == 'local' || lower[i + 1] == 'roaming')) ||
          (lower[i] == 'library' && lower[i + 1] == 'caches');
      if (!base) continue;
      final folder = segments[i + 2];
      // The last segment is the file itself.
      if (i + 2 >= segments.length - 1 || _isRandom(folder)) return null;
      return folder;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // %TEMP%
  // ---------------------------------------------------------------------------

  /// Folder-name prefixes that apps use for their scratch folders in %TEMP%.
  static final List<(RegExp, String, bool)> _tempFolders = [
    (RegExp(r'^is-[0-9a-z]+\.tmp$'), 'Inno Setup', true),
    (RegExp(r'^_mei\d+$'), 'PyInstaller', false),
    (RegExp(r'^msi[0-9a-f]+\.tmp$'), 'Windows Installer', true),
    (RegExp(r'^pip-'), 'pip', false),
    (RegExp(r'^npm-'), 'npm', false),
    (RegExp(r'^vscode'), 'Microsoft Visual Studio Code', false),
    (RegExp(r'^msedge'), 'Microsoft Edge', false),
    (RegExp(r'^chrome_'), 'Google Chrome', false),
    (RegExp(r'^nvidia'), 'NVIDIA', false),
    (RegExp(r'^winget'), 'WinGet', false),
    (RegExp(r'^chocolatey'), 'Chocolatey', false),
    (RegExp(r'^(dotnet|\.net)'), '.NET', false),
    (RegExp(r'^outlook logging$'), 'Outlook', false),
    (RegExp(r'^discord'), 'Discord', false),
    (RegExp(r'^steam'), 'Steam', false),
    (RegExp(r'^onedrive'), 'OneDrive', false),
    (RegExp(r'^zoom($|[ _])'), 'Zoom', false),
    (RegExp(r'^(ms-)?teams'), 'Microsoft Teams', false),
    (RegExp(r'^flutter_tools'), 'Flutter', false),
    (RegExp(r'^gradle'), 'Gradle', false),
  ];

  /// File names apps drop straight into %TEMP%.
  static final List<(RegExp, String)> _tempFiles = [
    (RegExp(r'^msi[0-9a-z]+\.log$'), 'Windows Installer'),
    // `dd_setup_…_Microsoft.VisualStudio.….log`, `dd_BackgroundDownload_…`.
    (
      RegExp(r'^dd_(setup|bootstrapper|backgrounddownload|client|installer)_'),
      'Visual Studio Installer',
    ),
    (RegExp(r'^chrome_installer'), 'Google Chrome'),
    (RegExp(r'^msedge_installer'), 'Microsoft Edge'),
  ];

  /// GUIDs, hex or numeric IDs and `tmpXXXX` names say nothing about the app.
  static final RegExp _random = RegExp(
    r'^(\{?[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\}?'
    r'|(?=.*\d)[0-9a-f._-]{6,}'
    r'|tmp[0-9a-z]*(\.tmp)?'
    r'|~.*'
    r'|.*\.tmp'
    r'|scoped_dir.*'
    r'|\d+)$',
    caseSensitive: false,
  );

  static bool _isRandom(String name) => _random.hasMatch(name);

  static CleanerItemOrigin _temp(
    List<String> segments,
    List<String> lower,
    String name,
  ) {
    var kind = CleanerItemKind.tempFile;
    if (_logExtensions.any(name.endsWith)) {
      kind = CleanerItemKind.log;
    } else if (_installerExtensions.any(name.endsWith)) {
      kind = CleanerItemKind.installer;
    }

    final root = _tempRoot(lower);
    if (root < 0 || root + 1 >= segments.length) {
      return CleanerItemOrigin(kind: kind);
    }
    // A file directly in %TEMP%.
    if (root + 1 == segments.length - 1) {
      for (final (pattern, app) in _tempFiles) {
        if (pattern.hasMatch(name)) {
          return CleanerItemOrigin(app: app, kind: kind);
        }
      }
      return CleanerItemOrigin(kind: kind);
    }

    final folder = segments[root + 1];
    final folderLower = lower[root + 1];
    for (final (pattern, app, installer) in _tempFolders) {
      if (pattern.hasMatch(folderLower)) {
        return CleanerItemOrigin(
          app: app,
          kind: installer && kind == CleanerItemKind.tempFile
              ? CleanerItemKind.installer
              : kind,
        );
      }
    }
    final owner = _ruleOwner(lower) ?? _vendor(lower);
    if (owner != null) return CleanerItemOrigin(app: owner, kind: kind);
    if (_isRandom(folder)) return CleanerItemOrigin(kind: kind);
    return CleanerItemOrigin(app: folder, appIsFolder: true, kind: kind);
  }

  /// Index of the `Temp` segment: `AppData\Local\Temp` when present, else the
  /// first `Temp` or `Tmp`.
  static int _tempRoot(List<String> lower) {
    for (var i = 2; i < lower.length; i++) {
      if (lower[i] == 'temp' &&
          lower[i - 1] == 'local' &&
          lower[i - 2] == 'appdata') {
        return i;
      }
    }
    return lower.indexWhere((s) => s == 'temp' || s == 'tmp');
  }
}
