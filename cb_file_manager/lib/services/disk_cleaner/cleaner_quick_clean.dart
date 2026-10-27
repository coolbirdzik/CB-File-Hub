import 'cleaner_categories.dart';
import 'cleaner_models.dart';
import 'cleaner_cache_rules.dart';
import 'cleaner_paths.dart';
import 'cleaner_xcode_cache.dart';
import 'cleaner_audited_rules.dart';

/// Selection rules for the Cleaner's one-tap "quick clean".
///
/// Quick clean deletes without the user auditing individual paths, so it takes
/// only the strictest subset of the junk categories:
/// - nothing that bypasses the Recycle Bin. `recycle_bin` items are always
///   deleted permanently by the clean pipeline, so that category is left out;
/// - browser and app items only inside folders that are caches by name, so a
///   rule pointing at a broader folder (Spotify storage, Zoom data, a Firefox
///   profile) cannot take settings, offline content or databases;
/// - crash dumps and error reports, but not the `*.log` rules that walk all of
///   AppData: LevelDB and IndexedDB use `NNNNNN.log` as their write-ahead log;
/// - nothing modified recently, since a running app or installer may still
///   own it.
///
/// Installed dependencies remain outside the regenerable-download rules.
class CleanerQuickClean {
  CleanerQuickClean._();

  /// Files touched more recently than this may still belong to a running app.
  static const Duration minAge = Duration(hours: 24);

  /// Windows Disk Cleanup only removes temporary files older than a week;
  /// quick clean keeps the same margin for `%TEMP%`.
  static const Duration tempMinAge = Duration(days: 7);

  static const Set<String> _quickCategoryIds = {
    'windows_temp',
    'browser_cache',
    'thumbnail_cache',
    'app_cache',
    'crash_dumps_logs',
    'system_cache',
    'package_download_cache',
    'electron_cache',
    CleanerXcodeCache.categoryId,
    ...CleanerAuditedRules.cleanableIds,
  };

  /// Categories whose items must sit inside one of [_cacheSegments].
  static const Set<String> _cacheOnlyCategoryIds = {
    'browser_cache',
    'app_cache',
  };

  static const Set<String> _cacheSegments = {
    'cache',
    'caches',
    'cache_data',
    'cache2',
    'code cache',
    'gpucache',
    'cacheddata',
    'startupcache',
    'dawncache',
    'dawngraphitecache',
    'dawnwebgpucache',
    'grshadercache',
    'shadercache',
    'graphitedawncache',
  };

  static const Set<String> _crashSegments = {
    'crashdumps',
    'wer',
    'diagnosticreports',
  };

  /// Folders that hold app databases, never taken even under a cache rule.
  static const Set<String> _databaseSegments = {
    'leveldb',
    'indexeddb',
    'local storage',
    'session storage',
    'databases',
    'service worker',
    'cachestorage',
    'node_modules',
    'site-packages',
    '.venv',
    'venv',
  };

  /// Category IDs quick clean scans on [operatingSystem] (the host by
  /// default). A category must also be `safe` and need no administrator
  /// rights there; macOS `app_cache` is `careful`, so it is not scanned.
  static List<String> categoryIds({String? operatingSystem}) =>
      CleanerCategories.all(operatingSystem: operatingSystem)
          .where(
            (c) =>
                _quickCategoryIds.contains(c.id) &&
                c.safety == CleanerSafety.safe &&
                !c.requiresAdmin,
          )
          .map((c) => c.id)
          .toList(growable: false);

  /// Whether quick clean should scan [rule] of [categoryId]. Skipping the
  /// AppData-wide `*.log` rules also saves the slowest walk of the scan.
  static bool includesRule(String categoryId, CleanerPathRule rule) {
    if (!_quickCategoryIds.contains(categoryId)) return false;
    if (_segments(rule.source.relative).any(_databaseSegments.contains)) {
      return false;
    }
    if (categoryId != 'crash_dumps_logs') return true;
    return _segments(rule.source.relative).any(_crashSegments.contains);
  }

  /// Whether [item] may be removed by quick clean at [now].
  static bool isEligible(JunkItem item, DateTime now) {
    if (!_quickCategoryIds.contains(item.categoryId)) return false;
    if (item.isRecycleBinItem || item.isUserSelected || item.isContainerOnly) {
      return false;
    }
    final modified = item.lastModified;
    if (modified == null) return false;
    final floor = switch (item.categoryId) {
      'windows_temp' => tempMinAge,
      'system_cache' ||
      'package_download_cache' => CleanerCacheRules.downloadMinAge,
      CleanerXcodeCache.categoryId => CleanerXcodeCache.minAge,
      'developer_analysis_cache' ||
      'developer_download_cache' ||
      'electron_crash_reports' => CleanerAuditedRules.minAge,
      _ => minAge,
    };
    if (now.difference(modified) < floor) return false;

    final segments = _segments(item.path);
    if (item.categoryId == CleanerXcodeCache.categoryId &&
        !CleanerXcodeCache.isGeneratedFile(item.path)) {
      return false;
    }
    if (segments.any(_databaseSegments.contains)) return false;
    final name = segments.lastOrNull;
    if (name == null ||
        name == 'lock' ||
        name.endsWith('.lock') ||
        name.endsWith('.lck')) {
      return false;
    }
    if (CleanerAuditedRules.cleanableIds.contains(item.categoryId)) {
      if (!CleanerAuditedRules.matchesCleanablePath(
        item.categoryId,
        item.path,
      )) {
        return false;
      }
      if (item.categoryId == 'electron_crash_reports') {
        return name.endsWith('.dmp');
      }
      if (item.path
          .replaceAll(r'\', '/')
          .toLowerCase()
          .contains('/comfy desktop/download-cache/')) {
        return const ['.7z', '.zip', '.tar.gz', '.tar.zst'].any(name.endsWith);
      }
      return true;
    }
    if (const {
      'system_cache',
      'package_download_cache',
      'electron_cache',
    }.contains(item.categoryId)) {
      return CleanerCacheRules.matchesPath(item.categoryId, item.path);
    }

    if (_cacheOnlyCategoryIds.contains(item.categoryId)) {
      // Only look below AppData (Windows) or Library (macOS), so a user or
      // drive named "Cache" cannot make every path look like a cache.
      final root = segments.indexWhere((s) => s == 'appdata' || s == 'library');
      if (root < 0) return false;
      return segments.skip(root + 1).any(_cacheSegments.contains);
    }
    if (item.categoryId == 'crash_dumps_logs') {
      return segments.any(_crashSegments.contains);
    }
    return true;
  }

  /// [report] narrowed to the items quick clean may remove, dropping
  /// categories left empty.
  static ScanReport select(ScanReport report, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final itemsByCategory = <String, List<JunkItem>>{};
    final seen = <String>{};
    for (final entry in report.itemsByCategory.entries) {
      final items = entry.value
          .where(
            (item) =>
                isEligible(item, at) && seen.add(CleanerPaths.key(item.path)),
          )
          .toList(growable: false);
      if (items.isNotEmpty) itemsByCategory[entry.key] = items;
    }
    return ScanReport(
      drivesScanned: report.drivesScanned,
      itemsByCategory: itemsByCategory,
      warnings: report.warnings,
      scannedAt: report.scannedAt,
    );
  }

  static List<String> _segments(String path) => path
      .toLowerCase()
      .split(RegExp(r'[\\/]'))
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}
