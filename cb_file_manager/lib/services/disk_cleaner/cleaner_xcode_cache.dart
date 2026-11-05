import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_insights/app_insights_models.dart';
import 'cleaner_models.dart';

abstract final class CleanerXcodeCache {
  static const categoryId = 'xcode_build_cache';
  static const minAge = Duration(days: 7);
  static const relativeRoot = 'Library/Developer/Xcode/DerivedData';

  static const category = CleanerCategory(
    id: categoryId,
    displayName: 'Old Xcode build files',
    description:
        'Generated build products, intermediates, indexes and module caches unchanged for a week. Close Xcode and stop builds first. Sources, package checkouts, archives and dSYMs are kept; the next build and indexing may take longer.',
    safety: CleanerSafety.safe,
    defaultEnabled: true,
    rules: [
      CleanerPathRule(
        source: PathSource.env('HOME', relativeRoot),
        scope: CleanerRuleScope.xcodeBuildOutputs,
        minAge: minAge,
        excludeGlobs: ['LOCK', '*.lock', '*.lck'],
        appOwnerHints: ['Xcode', 'com.apple.dt.Xcode'],
        storageKind: AppStorageKind.cache,
      ),
    ],
  );

  /// Xcode's own cache, Simulator caches and logs, and device symbols.
  static const junkCategoryId = 'xcode_junk';

  /// DeviceSupport folders are only taken when nothing in them changed for
  /// this long; Xcode copies them again (several minutes) from the device.
  static const deviceSupportMinAge = Duration(days: 90);
  static const deviceSupportPlatforms = ['iOS', 'watchOS', 'tvOS', 'visionOS'];

  static const xcodeCacheRoot = 'Library/Caches/com.apple.dt.Xcode';
  static const simulatorCacheRoot = 'Library/Developer/CoreSimulator/Caches';
  static const simulatorLogRoot = 'Library/Logs/CoreSimulator';
  static const _locks = ['LOCK', '*.lock', '*.lck'];

  // The URL cache index stays; a missing blob is only a cache miss, but a
  // removed SQLite file next to a surviving WAL is not.
  static const _databaseGlobs = [
    '*.db',
    '*.db-wal',
    '*.db-shm',
    '*.sqlite',
    '*.sqlite-wal',
    '*.sqlite-shm',
  ];

  static const junkCategory = CleanerCategory(
    id: junkCategoryId,
    displayName: 'Old Xcode caches and device symbols',
    description:
        'Xcode download cache, Simulator caches and logs unchanged for a week, and device debug symbols (DeviceSupport) unchanged for 90 days. Close Xcode and Simulator first. Projects, archives, simulators and their apps are kept; Xcode copies device symbols again the next time that device is used for debugging.',
    safety: CleanerSafety.safe,
    defaultEnabled: true,
    rules: [
      CleanerPathRule(
        source: PathSource.env('HOME', xcodeCacheRoot),
        minAge: minAge,
        excludeGlobs: [..._locks, ..._databaseGlobs],
        appOwnerHints: ['Xcode', 'com.apple.dt.Xcode'],
        storageKind: AppStorageKind.cache,
      ),
      CleanerPathRule(
        source: PathSource.env('HOME', simulatorCacheRoot),
        minAge: minAge,
        excludeGlobs: _locks,
        appOwnerHints: ['Simulator', 'com.apple.iphonesimulator'],
        storageKind: AppStorageKind.cache,
      ),
      CleanerPathRule(
        source: PathSource.env('HOME', simulatorLogRoot),
        minAge: minAge,
        excludeGlobs: _locks,
        appOwnerHints: ['Simulator', 'com.apple.iphonesimulator'],
        storageKind: AppStorageKind.logs,
      ),
      CleanerPathRule(
        source: PathSource.env(
          'HOME',
          'Library/Developer/Xcode/iOS DeviceSupport',
        ),
        scope: CleanerRuleScope.xcodeDeviceSupport,
        minAge: deviceSupportMinAge,
        appOwnerHints: ['Xcode', 'com.apple.dt.Xcode'],
        storageKind: AppStorageKind.cache,
      ),
      CleanerPathRule(
        source: PathSource.env(
          'HOME',
          'Library/Developer/Xcode/watchOS DeviceSupport',
        ),
        scope: CleanerRuleScope.xcodeDeviceSupport,
        minAge: deviceSupportMinAge,
        appOwnerHints: ['Xcode', 'com.apple.dt.Xcode'],
        storageKind: AppStorageKind.cache,
      ),
      CleanerPathRule(
        source: PathSource.env(
          'HOME',
          'Library/Developer/Xcode/tvOS DeviceSupport',
        ),
        scope: CleanerRuleScope.xcodeDeviceSupport,
        minAge: deviceSupportMinAge,
        appOwnerHints: ['Xcode', 'com.apple.dt.Xcode'],
        storageKind: AppStorageKind.cache,
      ),
      CleanerPathRule(
        source: PathSource.env(
          'HOME',
          'Library/Developer/Xcode/visionOS DeviceSupport',
        ),
        scope: CleanerRuleScope.xcodeDeviceSupport,
        minAge: deviceSupportMinAge,
        appOwnerHints: ['Xcode', 'com.apple.dt.Xcode'],
        storageKind: AppStorageKind.cache,
      ),
    ],
  );

  /// Whether [path] must be dropped from category [id] even though a scan
  /// rule reported it. False for categories other than the two Xcode ones.
  static bool rejects(String id, String path) => switch (id) {
    categoryId => !isGeneratedFile(path),
    junkCategoryId => !isJunkFile(path),
    _ => false,
  };

  /// DeviceSupport version folders under [platformRoot] whose every file and
  /// folder is older than [minAge] at [now], except the newest one.
  ///
  /// All or nothing: Xcode trusts a version folder whose markers remain, so a
  /// folder with only some symbols removed would never be copied again. A
  /// folder holding a link, or one that cannot be read completely, is kept.
  static List<String> discoverStaleDeviceSupport(
    String platformRoot,
    List<String> warnings, {
    DateTime? now,
    Duration minAge = deviceSupportMinAge,
  }) {
    final at = now ?? DateTime.now();
    final folders = <(String, DateTime)>[];
    try {
      if (!_realDirectory(platformRoot)) return const [];
      for (final entity in Directory(
        platformRoot,
      ).listSync(followLinks: false)) {
        if (entity is! Directory || !_realDirectory(entity.path)) continue;
        final latest = _latestChange(entity);
        if (latest != null) folders.add((entity.path, latest));
      }
    } on FileSystemException catch (error) {
      warnings.add(
        '$junkCategoryId: ${error.message} (${error.path ?? platformRoot})',
      );
      return const [];
    }
    if (folders.length < 2) return const [];
    folders.sort((a, b) => b.$2.compareTo(a.$2));
    return [
      for (final (path, latest) in folders.skip(1))
        if (at.difference(latest) >= minAge) path,
    ];
  }

  /// Newest modification time of [folder] and everything below it; null when
  /// any entry is a link or cannot be read, or when it holds no file. A folder
  /// emptied by an earlier clean must not take the "newest" slot.
  static DateTime? _latestChange(Directory folder) {
    try {
      var latest = folder.statSync().modified;
      var hasFile = false;
      for (final entity in folder.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Link) return null;
        if (entity is File) hasFile = true;
        final modified = entity.statSync().modified;
        if (modified.isAfter(latest)) latest = modified;
      }
      return hasFile ? latest : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Secondary check on every reported [junkCategoryId] file.
  static bool isJunkFile(String path) {
    if (isDeviceSupportFile(path)) return true;
    final normalized = path.replaceAll(r'\', '/');
    for (final root in [xcodeCacheRoot, simulatorCacheRoot, simulatorLogRoot]) {
      final parts = _below(normalized, root);
      if (parts == null || parts.isEmpty) continue;
      final name = parts.last.toLowerCase();
      return !(name == 'lock' ||
          name.endsWith('.lock') ||
          name.endsWith('.lck') ||
          (root == xcodeCacheRoot &&
              const [
                '.db',
                '.db-wal',
                '.db-shm',
                '.sqlite',
                '.sqlite-wal',
                '.sqlite-shm',
              ].any(name.endsWith)));
    }
    return false;
  }

  /// Whether [path] is inside a version folder of a DeviceSupport root.
  static bool isDeviceSupportFile(String path) {
    final normalized = path.replaceAll(r'\', '/');
    for (final platform in deviceSupportPlatforms) {
      final parts = _below(
        normalized,
        'Library/Developer/Xcode/$platform DeviceSupport',
      );
      // A version folder and at least one entry inside it.
      if (parts != null) return parts.length >= 2;
    }
    return false;
  }

  /// Path components of [normalized] below `/<root>/`, or null when it is not
  /// inside it or walks out of it.
  static List<String>? _below(String normalized, String root) {
    final marker = '/$root/';
    final index = normalized.indexOf(marker);
    if (index < 0) return null;
    final parts = normalized
        .substring(index + marker.length)
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.any((part) => part == '.' || part == '..')) return null;
    return parts;
  }

  static const _sharedCaches = {
    'ModuleCache.noindex',
    'CompilationCache.noindex',
    'SDKStatCaches.noindex',
    'SymbolCache.noindex',
  };
  static const _projectOutputs = [
    ['Build', 'Intermediates.noindex'],
    ['Build', 'Intermediates'],
    ['Build', 'Products'],
    ['Index.noindex'],
  ];

  /// Shallow discovery on the scan isolate. Never walks package checkouts,
  /// sources, Archives, simulators or arbitrary folders called "build".
  static List<String> discoverRoots(String derivedData, List<String> warnings) {
    final roots = <String>[];
    try {
      if (!_realDirectory(derivedData)) return roots;
      for (final entity in Directory(
        derivedData,
      ).listSync(followLinks: false)) {
        if (entity is! Directory || !_realDirectory(entity.path)) continue;
        if (_sharedCaches.contains(p.basename(entity.path))) {
          roots.add(entity.path);
          continue;
        }
        for (final output in _projectOutputs) {
          var target = entity.path;
          var exists = true;
          // Check each component so a symlinked Build cannot escape the scope.
          for (final component in output) {
            target = p.join(target, component);
            if (!_realDirectory(target)) {
              exists = false;
              break;
            }
          }
          if (exists) roots.add(target);
        }
      }
    } on FileSystemException catch (error) {
      warnings.add(
        '$categoryId: ${error.message} (${error.path ?? derivedData})',
      );
    }
    return roots;
  }

  static bool _realDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;

  /// Secondary check on every reported file, including native scan hits.
  static bool isGeneratedFile(String path) {
    final normalized = path.replaceAll(r'\', '/');
    const marker = '/$relativeRoot/';
    final index = normalized.indexOf(marker);
    if (index < 0) return false;
    final parts = normalized.substring(index + marker.length).split('/');
    if (parts.any((part) {
      final lower = part.toLowerCase();
      return part == '..' ||
          part == '.' ||
          lower == 'sourcepackages' ||
          lower == 'archives' ||
          lower.endsWith('.xcarchive') ||
          lower.endsWith('.dsym');
    })) {
      return false;
    }
    if (parts.length < 2) return false;
    if (_sharedCaches.contains(parts.first)) return true;
    if (parts.length >= 3 && parts[1] == 'Index.noindex') return true;
    return parts.length >= 4 &&
        parts[1] == 'Build' &&
        const {
          'Products',
          'Intermediates.noindex',
          'Intermediates',
        }.contains(parts[2]);
  }
}
