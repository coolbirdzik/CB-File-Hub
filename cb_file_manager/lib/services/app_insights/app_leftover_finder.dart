import 'dart:io';

import '../disk_cleaner/disk_tree_node.dart';
import 'app_insights_models.dart';
import 'app_storage_analyzer.dart';

/// Where a leftover folder was found.
enum AppLeftoverLocation {
  localAppData,
  roamingAppData,
  localLowAppData,
  programData,
  userPrograms,
  programFiles,
  macContainers,
  macGroupContainers,
  macApplicationSupport,
  macCaches,
  linuxConfig,
  linuxData,
  linuxCache,
  linuxFlatpak,
  linuxSnap,
}

/// Why a folder is reported as a leftover.
enum AppLeftoverReason {
  /// Neither an installed app nor its publisher matches the folder.
  noInstalledApp,

  /// An installed app has the same name, but this folder carries an older
  /// version number than the one installed.
  olderVersion,
}

class AppLeftoverCandidate {
  final String path;

  /// Folder name, prefixed with its vendor folder when nested
  /// (`JetBrains\PyCharm2021.3`).
  final String displayName;
  final AppLeftoverLocation location;
  final AppLeftoverReason reason;
  final int sizeBytes;
  final int fileCount;

  /// The scan skipped part of this folder; [sizeBytes] is a lower bound.
  final bool isPartial;

  /// The installed app an [AppLeftoverReason.olderVersion] folder was
  /// compared with.
  final String? relatedAppName;

  const AppLeftoverCandidate({
    required this.path,
    required this.displayName,
    required this.location,
    required this.reason,
    required this.sizeBytes,
    this.fileCount = 0,
    this.isPartial = false,
    this.relatedAppName,
  });

  AppLeftoverCandidate withMeasurement({
    required int sizeBytes,
    required int fileCount,
    required bool isPartial,
  }) {
    return AppLeftoverCandidate(
      path: path,
      displayName: displayName,
      location: location,
      reason: reason,
      sizeBytes: sizeBytes,
      fileCount: fileCount,
      isPartial: isPartial,
      relatedAppName: relatedAppName,
    );
  }
}

/// What a leftover scan compares folders with.
class AppLeftoverInventory {
  final List<InstalledAppInfo> apps;
  final bool isPartial;

  /// Installed Flatpak app ids, or null when `flatpak` could not answer.
  final Set<String>? flatpakApps;

  /// Installed snap names, or null when `snap` could not answer.
  final Set<String>? snaps;

  const AppLeftoverInventory({
    required this.apps,
    this.isPartial = false,
    this.flatpakApps,
    this.snaps,
  });
}

class AppLeftoverReport {
  final String drivePath;
  final List<AppLeftoverCandidate> candidates;
  final DateTime generatedAt;

  /// The app inventory or the scan was incomplete.
  final bool isPartial;

  /// No Win32 app inventory was available, so nothing could be compared and
  /// [candidates] is empty on purpose.
  final bool inventoryUnavailable;

  const AppLeftoverReport({
    required this.drivePath,
    required this.candidates,
    required this.generatedAt,
    this.isPartial = false,
    this.inventoryUnavailable = false,
  });

  int get totalBytes =>
      candidates.fold<int>(0, (sum, candidate) => sum + candidate.sizeBytes);
}

/// Finds app-data and install folders that no installed app accounts for.
///
/// Like [AppStorageAnalyzer], this never touches the filesystem: the measured
/// [DiskTreeNode] graph of a full-disk scan and the installed-app inventory
/// are its only inputs. Matching errs towards "owned", because a missed
/// leftover only costs space while a false one invites deleting live data.
///
/// Folders of a publisher that still has an installed app, and folders that
/// contain an install location, are never reported whole: they also hold
/// shared parts (Apple's `MobileSync` backups, an Electron app's storage).
/// Only older-version siblings inside them are reported.
class AppLeftoverFinder {
  static const int defaultMinimumBytes = 1024 * 1024;

  const AppLeftoverFinder();

  AppLeftoverReport find({
    required DiskTreeNode root,
    required List<InstalledAppInfo> apps,
    Map<String, String>? environment,
    List<FullDiskScanCoverageIssue> coverageIssues =
        const <FullDiskScanCoverageIssue>[],
    Iterable<String> excludedPaths = const <String>[],
    bool inventoryIsPartial = false,
    int minimumBytes = defaultMinimumBytes,
    DateTime? generatedAt,
  }) {
    final drivePath = AppStorageAnalyzer.normalizeWindowsPath(root.fullPath);
    final generated = generatedAt ?? DateTime.now();
    // Without the uninstall-registry list every folder would look orphaned.
    if (!apps.any((app) => app.source == InstalledAppSource.win32)) {
      return AppLeftoverReport(
        drivePath: root.fullPath,
        candidates: const <AppLeftoverCandidate>[],
        generatedAt: generated,
        isPartial: true,
        inventoryUnavailable: true,
      );
    }

    final env = _upperKeys(environment ?? Platform.environment);
    final bases = _bases(env)
        .where(
          (base) => AppStorageAnalyzer.isSameOrDescendant(base.path, drivePath),
        )
        .toList(growable: false);
    final context = _FinderContext(
      index: AppTokenIndex(apps),
      anchors: _anchors(apps, env, bases.map((base) => base.path)),
      excluded: excludedPaths
          .where((path) => path.trim().isNotEmpty)
          .map(AppStorageAnalyzer.normalizeWindowsPath)
          .toList(growable: false),
      coverageIssues: coverageIssues,
      minimumBytes: minimumBytes,
    );

    final candidates = <String, AppLeftoverCandidate>{};
    for (final base in bases) {
      final node = findNode(root, base.path);
      if (node == null) continue;
      for (final candidate in _evaluateLevel(
        context,
        node.children,
        base.location,
        parentName: null,
      )) {
        candidates.putIfAbsent(
          AppStorageAnalyzer.normalizeWindowsPath(candidate.path),
          () => candidate,
        );
      }
    }

    final sorted = candidates.values.toList(growable: false)
      ..sort((a, b) {
        final size = b.sizeBytes.compareTo(a.sizeBytes);
        return size != 0 ? size : a.path.compareTo(b.path);
      });
    return AppLeftoverReport(
      drivePath: root.fullPath,
      candidates: sorted,
      generatedAt: generated,
      isPartial: inventoryIsPartial || sorted.any((item) => item.isPartial),
    );
  }

  /// Walks [root] by path segments instead of visiting the whole tree.
  static DiskTreeNode? findNode(DiskTreeNode root, String path) {
    final rootPath = AppStorageAnalyzer.normalizeWindowsPath(root.fullPath);
    final target = AppStorageAnalyzer.normalizeWindowsPath(path);
    if (target == rootPath) return root;
    if (!AppStorageAnalyzer.isSameOrDescendant(target, rootPath)) return null;
    final relative = target.substring(
      rootPath.endsWith(r'\') ? rootPath.length : rootPath.length + 1,
    );
    var node = root;
    for (final segment in relative.split(r'\')) {
      DiskTreeNode? next;
      for (final child in node.children) {
        if (!child.isFile && child.name.toUpperCase() == segment) {
          next = child;
          break;
        }
      }
      if (next == null) return null;
      node = next;
    }
    return node;
  }

  List<AppLeftoverCandidate> _evaluateLevel(
    _FinderContext context,
    List<DiskTreeNode> children,
    AppLeftoverLocation location, {
    required String? parentName,
  }) {
    final isTopLevel = parentName == null;
    final results = <AppLeftoverCandidate>[];
    final versioned = <_VersionedFolder>[];

    for (final child in children) {
      if (child.isFile || child.isAggregate || child.fullPath.isEmpty) {
        continue;
      }
      final name = child.name;
      if (_isIgnoredName(location, name, topLevel: isTopLevel)) continue;
      final path = AppStorageAnalyzer.normalizeWindowsPath(child.fullPath);
      if (context.excluded.any(
        (excluded) =>
            AppStorageAnalyzer.isSameOrDescendant(path, excluded) ||
            AppStorageAnalyzer.isSameOrDescendant(excluded, path),
      )) {
        continue;
      }

      // Installed paths are the strongest evidence and win over names.
      var containsAnchor = false;
      var insideAnchor = false;
      for (final anchor in context.anchors) {
        if (AppStorageAnalyzer.isSameOrDescendant(path, anchor)) {
          insideAnchor = true;
          break;
        }
        if (AppStorageAnalyzer.isSameOrDescendant(anchor, path)) {
          containsAnchor = true;
        }
      }
      if (insideAnchor) continue;
      final token = _token(name);
      if (containsAnchor) {
        versioned.add(_VersionedFolder(child, token, owned: true));
        if (isTopLevel && context.index.matchProduct(token) == null) {
          results.addAll(
            _evaluateLevel(context, child.children, location, parentName: name),
          );
        }
        continue;
      }

      if (token.length < 3) continue;
      final product = context.index.matchProduct(token);
      if (product != null) {
        versioned.add(_VersionedFolder(child, token, product: product));
        continue;
      }
      if (!isTopLevel) continue;

      if (context.index.matchVendor(token) != null) {
        results.addAll(
          _evaluateLevel(context, child.children, location, parentName: name),
        );
        continue;
      }

      final candidate = _candidate(
        context,
        child,
        location,
        parentName: parentName,
        reason: AppLeftoverReason.noInstalledApp,
      );
      if (candidate != null) results.add(candidate);
    }

    results.addAll(
      _olderVersions(context, versioned, location, parentName: parentName),
    );
    return results;
  }

  /// Flags folders like `PyCharm2021.3` next to `PyCharm2024.1` when no
  /// installed app carries the older version number.
  List<AppLeftoverCandidate> _olderVersions(
    _FinderContext context,
    List<_VersionedFolder> folders,
    AppLeftoverLocation location, {
    required String? parentName,
  }) {
    final byStem = <String, List<_VersionedFolder>>{};
    for (final folder in folders) {
      if (folder.stem.length < 3 || folder.version.isEmpty) continue;
      byStem.putIfAbsent(folder.stem, () => <_VersionedFolder>[]).add(folder);
    }

    final results = <AppLeftoverCandidate>[];
    for (final group in byStem.values) {
      if (group.length < 2) continue;
      final newest = group.reduce(
        (a, b) => _compareVersions(a.version, b.version) >= 0 ? a : b,
      );
      for (final folder in group) {
        final product = folder.product;
        if (identical(folder, newest) || folder.owned || product == null) {
          continue;
        }
        if (_compareVersions(folder.version, newest.version) >= 0) continue;
        if (context.index.hasInstalledVersion(folder.stem, folder.version)) {
          continue;
        }
        final candidate = _candidate(
          context,
          folder.node,
          location,
          parentName: parentName,
          reason: AppLeftoverReason.olderVersion,
          relatedAppName: product.displayName,
        );
        if (candidate != null) results.add(candidate);
      }
    }
    return results;
  }

  AppLeftoverCandidate? _candidate(
    _FinderContext context,
    DiskTreeNode node,
    AppLeftoverLocation location, {
    required String? parentName,
    required AppLeftoverReason reason,
    String? relatedAppName,
  }) {
    if (node.isSystemProtected || node.sizeBytes < context.minimumBytes) {
      return null;
    }
    final path = AppStorageAnalyzer.normalizeWindowsPath(node.fullPath);
    final partial = context.coverageIssues.any(
      (issue) =>
          AppStorageAnalyzer.isSameOrDescendant(issue.path, path) ||
          AppStorageAnalyzer.isSameOrDescendant(path, issue.path),
    );
    return AppLeftoverCandidate(
      path: node.fullPath,
      displayName: parentName == null ? node.name : '$parentName\\${node.name}',
      location: location,
      reason: reason,
      sizeBytes: node.sizeBytes,
      fileCount: node.fileCount,
      isPartial: partial,
      relatedAppName: relatedAppName,
    );
  }

  /// The folders whose children are checked, as spelled in [environment]
  /// (so listings keep their real casing).
  static List<String> baseDirectories(Map<String, String> environment) {
    return _bases(
      _upperKeys(environment),
      normalize: false,
    ).map((base) => base.path).toList(growable: false);
  }

  static String _trimSeparator(String path) {
    final value = path.replaceAll('/', r'\');
    return value.length > 3 && value.endsWith(r'\')
        ? value.substring(0, value.length - 1)
        : value;
  }

  static Map<String, String> _upperKeys(Map<String, String> environment) =>
      <String, String>{
        for (final entry in environment.entries)
          entry.key.toUpperCase(): entry.value.trim(),
      };

  static List<_Base> _bases(Map<String, String> env, {bool normalize = true}) {
    final bases = <_Base>[];
    final seen = <String>{};
    void add(String? path, AppLeftoverLocation location) {
      if (path == null || path.isEmpty || path.contains('%')) return;
      final normalized = AppStorageAnalyzer.normalizeWindowsPath(path);
      if (normalized.length <= 3) return;
      if (!seen.add(normalized)) return;
      bases.add(_Base(normalize ? normalized : _trimSeparator(path), location));
    }

    final rawLocal = env['LOCALAPPDATA'];
    add(rawLocal, AppLeftoverLocation.localAppData);
    add(env['APPDATA'], AppLeftoverLocation.roamingAppData);
    if (rawLocal != null && rawLocal.isNotEmpty) {
      final local = _trimSeparator(rawLocal);
      final separator = local.lastIndexOf(r'\');
      if (separator > 2) {
        add(
          '${local.substring(0, separator)}\\LocalLow',
          AppLeftoverLocation.localLowAppData,
        );
      }
      add('$local\\Programs', AppLeftoverLocation.userPrograms);
    }
    add(env['PROGRAMDATA'], AppLeftoverLocation.programData);
    add(env['PROGRAMFILES'], AppLeftoverLocation.programFiles);
    add(env['PROGRAMFILES(X86)'], AppLeftoverLocation.programFiles);
    add(env['PROGRAMW6432'], AppLeftoverLocation.programFiles);
    return bases;
  }

  /// Install directories of every app. Anchors that would cover a whole base
  /// folder (a bogus `InstallLocation` of `C:\ProgramData`, say) are dropped,
  /// since they would hide every folder in it.
  static List<String> _anchors(
    List<InstalledAppInfo> apps,
    Map<String, String> env,
    Iterable<String> bases,
  ) {
    final baseList = bases.toList(growable: false);
    final anchors = <String>{};
    void add(String? raw, {bool isFile = false}) {
      if (raw == null || raw.trim().isEmpty) return;
      final expanded = raw.replaceAllMapped(
        RegExp(r'%([^%]+)%'),
        (match) => env[match.group(1)!.toUpperCase()] ?? match.group(0)!,
      );
      if (expanded.contains('%')) return;
      var path = AppStorageAnalyzer.normalizeWindowsPath(expanded);
      if (isFile) {
        final separator = path.lastIndexOf(r'\');
        if (separator <= 2) return;
        path = path.substring(0, separator);
      }
      if (path.length <= 3) return;
      if (baseList.any(
        (base) => AppStorageAnalyzer.isSameOrDescendant(base, path),
      )) {
        return;
      }
      anchors.add(path);
    }

    for (final app in apps) {
      add(app.installLocation);
      add(app.displayIconPath, isFile: true);
      for (final executable in app.executablePaths) {
        add(executable, isFile: true);
      }
    }
    return anchors.toList(growable: false);
  }

  static bool _isIgnoredName(
    AppLeftoverLocation location,
    String name, {
    required bool topLevel,
  }) {
    final upper = name.toUpperCase();
    if (upper.startsWith('.') || upper.startsWith(r'$')) return true;
    if (_guidPattern.hasMatch(name)) return true;
    if (!topLevel) return false;
    if (_ignoredPrefixes.any(upper.startsWith)) return true;
    if (_ignoredEverywhere.contains(upper)) return true;
    switch (location) {
      case AppLeftoverLocation.localAppData:
      case AppLeftoverLocation.roamingAppData:
      case AppLeftoverLocation.localLowAppData:
        return _ignoredAppData.contains(upper);
      case AppLeftoverLocation.userPrograms:
        return _ignoredUserPrograms.contains(upper);
      case AppLeftoverLocation.programData:
      case AppLeftoverLocation.programFiles:
        return _ignoredMachineFolders.contains(upper);
      default:
        // macOS and Linux bases are handled by PosixAppLeftoverFinder.
        return true;
    }
  }

  static final RegExp _guidPattern = RegExp(
    r'^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$',
    caseSensitive: false,
  );

  static const List<String> _ignoredPrefixes = <String>[
    'MICROSOFT',
    'WINDOWS',
    'REGID.',
    'CRASH',
    'CHOCOLATEY',
  ];

  /// Windows, driver, installer-cache and toolchain folders that no
  /// uninstall entry describes, plus generic names shared by many apps.
  static const Set<String> _ignoredEverywhere = <String>{
    'PACKAGES',
    'PACKAGE CACHE',
    'INSTALLSHIELD INSTALLATION INFORMATION',
    'DOWNLOADED INSTALLATIONS',
    'TEMP',
    'TMP',
    'CACHE',
    'BACKUP',
    'STATE',
    'TRACES',
    'USER DATA',
    'APPLICATION DATA',
    'HISTORY',
    'TEMPORARY INTERNET FILES',
    'COMMS',
    'CONNECTEDDEVICESPLATFORM',
    'D3DSCACHE',
    'DIAGNOSTICS',
    'ELEVATEDDIAGNOSTICS',
    'GROUPPOLICY',
    'ISOLATEDSTORAGE',
    'PEERDISTREPUB',
    'PLACEHOLDERTILELOGOFOLDER',
    'PUBLISHERS',
    'VIRTUALSTORE',
    'PACKAGEMANAGEMENT',
    'TOASTNOTIFICATIONMANAGERCOMPAT',
    'SQUIRRELTEMP',
    'WSL',
    'DIFX',
    'VULKANRT',
    'AMD',
    'ATI',
    'INTEL',
    'NVIDIA',
    'NVIDIA CORPORATION',
    'REALTEK',
    'SYNAPTICS',
    'CEF',
    'ELECTRON',
    'FONTCONFIG',
    'GTK-3.0',
    'MIME',
    'NODE',
    'NPM',
    'NPM-CACHE',
    'NODE-GYP',
    'MS-PLAYWRIGHT',
    'PIP',
    'PYPA',
    'PYPOETRY',
    'UV',
    'YARN',
    'PNPM',
    'PNPM-CACHE',
    'PNPM-STATE',
    'GO-BUILD',
    'GOPLS',
    'DENO',
    'DART',
    'PUB',
    'KOTLIN',
    'VCPKG',
    'NUGET',
    'SENTRY',
    'SSH',
    'USOPRIVATE',
    'USOSHARED',
  };

  static const Set<String> _ignoredAppData = <String>{
    'PROGRAMS',
    'APPS',
    'ASSEMBLY',
    'IDENTITIES',
    'MEDIA CENTER PROGRAMS',
  };

  static const Set<String> _ignoredUserPrograms = <String>{'COMMON'};

  static const Set<String> _ignoredMachineFolders = <String>{
    'COMMON FILES',
    'INTERNET EXPLORER',
    'MODIFIABLEWINDOWSAPPS',
    'MSBUILD',
    'REFERENCE ASSEMBLIES',
    'UNINSTALL INFORMATION',
    'DOTNET',
    'HYPER-V',
    'IIS',
    'IIS EXPRESS',
    'SOFTWAREDISTRIBUTION',
    'DESKTOP',
    'DOCUMENTS',
    'FAVORITES',
    'START MENU',
    'TEMPLATES',
    'DBG',
    'ORACLE',
    'JAVA',
  };
}

class _Base {
  final String path;
  final AppLeftoverLocation location;

  const _Base(this.path, this.location);
}

class _FinderContext {
  final AppTokenIndex index;
  final List<String> anchors;
  final List<String> excluded;
  final List<FullDiskScanCoverageIssue> coverageIssues;
  final int minimumBytes;

  const _FinderContext({
    required this.index,
    required this.anchors,
    required this.excluded,
    required this.coverageIssues,
    required this.minimumBytes,
  });
}

class _VersionedFolder {
  final DiskTreeNode node;
  final String stem;
  final List<int> version;
  final bool owned;
  final InstalledAppInfo? product;

  _VersionedFolder(this.node, String token, {this.owned = false, this.product})
    : stem = _lettersOnly(token),
      version = _numbers(node.name);
}

/// Name tokens of every installed app, split into product identities and
/// publisher identities. Matching errs towards a match: a missed leftover
/// only costs space, a false one invites deleting live data.
class AppTokenIndex {
  final List<(String, InstalledAppInfo)> _productTokens =
      <(String, InstalledAppInfo)>[];
  final Map<String, InstalledAppInfo> _productWords =
      <String, InstalledAppInfo>{};

  /// Long name words a folder may start with (`ComfyUI` for Comfy Desktop).
  final List<(String, InstalledAppInfo)> _productWordPrefixes =
      <(String, InstalledAppInfo)>[];
  final List<(String, InstalledAppInfo)> _vendorTokens =
      <(String, InstalledAppInfo)>[];
  final List<InstalledAppInfo> _apps;

  AppTokenIndex(this._apps) {
    for (final app in _apps) {
      final products = <String>{
        _token(app.displayName),
        _lettersOnly(_token(_stripVersion(app.displayName))),
        _basenameToken(app.installLocation),
        _basenameToken(app.displayIconPath, stripExtension: true),
        for (final executable in app.executablePaths)
          _basenameToken(executable, stripExtension: true),
        ..._packageTokens(app.packageFamilyName),
      }..removeWhere((token) => token.length < 3);
      for (final token in products) {
        _productTokens.add((token, app));
      }
      for (final word in _words(app.displayName)) {
        _productWords.putIfAbsent(word, () => app);
        if (word.length >= 5) _productWordPrefixes.add((word, app));
      }
      // `IDM` for Internet Download Manager.
      final acronym = _acronym(app.displayName);
      if (acronym.length >= 3) _productWords.putIfAbsent(acronym, () => app);

      final vendors = <String>{
        ..._publisherTokens(app.publisher),
        _parentToken(app.installLocation),
      }..removeWhere((token) => token.length < 3);
      for (final token in vendors) {
        _vendorTokens.add((token, app));
      }
    }
  }

  /// Product, then publisher match for a raw folder name.
  InstalledAppInfo? matchName(String folderName) {
    final token = _token(folderName);
    if (token.length < 3) return null;
    return matchProduct(token) ?? matchVendor(token);
  }

  InstalledAppInfo? matchProduct(String folder) {
    final stem = _lettersOnly(folder);
    final exact = _productWords[folder] ?? _productWords[stem];
    if (exact != null) return exact;
    for (final (token, app) in _productTokens) {
      if (_tokensMatch(folder, token) ||
          (stem.length >= 4 && _tokensMatch(stem, token))) {
        return app;
      }
    }
    for (final (word, app) in _productWordPrefixes) {
      if (folder.startsWith(word)) return app;
    }
    return null;
  }

  InstalledAppInfo? matchVendor(String folder) {
    for (final (token, app) in _vendorTokens) {
      if (folder == token || (token.length >= 5 && folder.startsWith(token))) {
        return app;
      }
    }
    return null;
  }

  /// Whether an app named like [stem] is installed with [version].
  bool hasInstalledVersion(String stem, List<int> version) {
    final digits = version.join();
    for (final app in _apps) {
      final names = <String>{
        _lettersOnly(_token(app.displayName)),
        ..._words(app.displayName),
      };
      if (!names.any((name) => name.contains(stem))) continue;
      for (final source in <String?>[app.displayName, app.version]) {
        if (source == null) continue;
        final installed = _numbers(source);
        if (installed.isEmpty) continue;
        if (_startsWith(installed, version) ||
            installed.join().startsWith(digits)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _tokensMatch(String folder, String token) {
    if (folder == token) return true;
    if (folder.length >= 4 &&
        (token.startsWith(folder) || token.endsWith(folder))) {
      return true;
    }
    return token.length >= 5 &&
        (folder.startsWith(token) || folder.endsWith(token));
  }

  static String _acronym(String displayName) {
    final words = _stripVersion(displayName)
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.length < 3) return '';
    return words.map((word) => word[0]).join();
  }

  static Iterable<String> _words(String value) sync* {
    for (final word in value.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
      if (word.length < 3 || RegExp(r'^\d+$').hasMatch(word)) continue;
      if (_genericWords.contains(word)) continue;
      yield word;
    }
  }

  static Iterable<String> _packageTokens(String? packageFamilyName) sync* {
    final family = packageFamilyName?.trim();
    if (family == null || family.isEmpty) return;
    final name = family.split('_').first;
    yield _token(name);
    for (final part in name.split('.')) {
      final token = _token(part);
      if (!_genericWords.contains(token)) yield token;
    }
  }

  static Iterable<String> _publisherTokens(String? publisher) sync* {
    if (publisher == null || publisher.trim().isEmpty) return;
    // `CN=...` subjects come from MSIX packages without a display name.
    final cleaned = publisher.replaceFirstMapped(
      RegExp(r'^CN=([^,]+).*$', caseSensitive: false),
      (match) => match.group(1)!,
    );
    final words = cleaned
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length > 1 && !_corporateWords.contains(word))
        .toList(growable: false);
    if (words.isEmpty) return;
    yield words.join();
    if (words.first.length >= 4 && !_genericWords.contains(words.first)) {
      yield words.first;
    }
  }

  static String _basenameToken(String? path, {bool stripExtension = false}) {
    if (path == null || path.trim().isEmpty) return '';
    var name = path
        .replaceAll('/', r'\')
        .split(r'\')
        .lastWhere((segment) => segment.isNotEmpty, orElse: () => '');
    name = name.replaceFirst(RegExp(r',\s*-?\d+$'), '').replaceAll('"', '');
    if (stripExtension) name = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return _token(name);
  }

  static String _parentToken(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    final segments = path
        .replaceAll('/', r'\')
        .split(r'\')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length < 3) return '';
    final parent = segments[segments.length - 2];
    final upper = parent.toUpperCase();
    // Base folders are not vendors.
    if (upper.startsWith('PROGRAM') ||
        upper == 'APPDATA' ||
        upper == 'LOCAL' ||
        upper == 'ROAMING' ||
        upper == 'USERS') {
      return '';
    }
    return _token(parent);
  }

  static String _stripVersion(String value) => value
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'\bv?\d+(\.\d+)*\b', caseSensitive: false), ' ');

  static const Set<String> _genericWords = <String>{
    'the',
    'and',
    'for',
    'bit',
    'x64',
    'x86',
    'arm64',
    'version',
    'edition',
    'update',
    'microsoft',
    'windows',
    'app',
    'apps',
    'tool',
    'tools',
    'data',
    'client',
    'desktop',
    'setup',
    'installer',
    'runtime',
    'driver',
    'drivers',
    'software',
    'service',
    'services',
    'manager',
    'player',
    'pro',
    'free',
    'community',
    'professional',
    'enterprise',
    'standard',
    'plus',
    'user',
    'system',
    'core',
    'package',
    'components',
  };

  static const Set<String> _corporateWords = <String>{
    'inc',
    'incorporated',
    'llc',
    'ltd',
    'limited',
    'corp',
    'corporation',
    'co',
    'company',
    'gmbh',
    'ag',
    'sro',
    'srl',
    'sa',
    'bv',
    'ab',
    'oy',
    'pty',
    'plc',
    'kk',
    'technologies',
    'technology',
    'software',
    'systems',
    'the',
    'and',
    'ou',
    'as',
  };
}

String _token(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

String _lettersOnly(String token) => token.replaceAll(RegExp(r'[0-9]+'), '');

List<int> _numbers(String value) => RegExp(r'\d+')
    .allMatches(value)
    .map((match) => int.tryParse(match.group(0)!) ?? 0)
    .toList(growable: false);

bool _startsWith(List<int> value, List<int> prefix) {
  if (prefix.length > value.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (value[index] != prefix[index]) return false;
  }
  return true;
}

int _compareVersions(List<int> left, List<int> right) {
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index++) {
    final a = index < left.length ? left[index] : 0;
    final b = index < right.length ? right[index] : 0;
    if (a != b) return a.compareTo(b);
  }
  return 0;
}
