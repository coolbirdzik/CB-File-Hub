import 'dart:io';

import 'package:cb_file_manager/utils/app_logger.dart';

/// Public result type returned by [DirectoryListingCacheService.getListing].
///
/// The cache stores only path strings internally to keep RAM usage low. Callers
/// receive freshly-created [File]/[Directory] wrappers on lookup.
class ListingCacheEntry {
  final List<File> files;
  final List<Directory> folders;
  final Map<String, FileStat> stats;

  ListingCacheEntry({
    required this.files,
    required this.folders,
    required this.stats,
  });
}

/// Internal lightweight cache entry.
class _ListingEntry {
  final List<String> filePaths;
  final List<String> folderPaths;
  final Map<String, FileStat>? stats;
  final DateTime savedAt;

  _ListingEntry({
    required this.filePaths,
    required this.folderPaths,
    required this.stats,
    required this.savedAt,
  });

  int get itemCount => filePaths.length + folderPaths.length;
}

/// In-memory LRU cache for folder directory listings.
///
/// This intentionally stores only paths, not [File]/[Directory] objects, and it
/// skips very large folders. The goal is fast navigate-back for common folders
/// without keeping huge object graphs in RAM.
class DirectoryListingCacheService {
  static DirectoryListingCacheService? _instance;
  static DirectoryListingCacheService get instance =>
      _instance ??= DirectoryListingCacheService._();

  DirectoryListingCacheService._();

  // Keep only a small working set. Windows Explorer-like behavior is mostly
  // useful for recently visited folders, not a long browsing history.
  static const int _maxEntries = 8;

  // Do not cache massive folders in memory. Re-scanning is cheaper than keeping
  // tens of thousands of strings/FileStats alive for the whole session.
  static const int _maxItemsPerEntry = 2500;

  // FileStat is the heaviest part of a listing cache entry. Keep it only for
  // smaller folders; large folders still get path cache for name/type sorting,
  // but date/size sorting may rebuild stats if needed.
  static const int _maxStatsItemsPerEntry = 800;

  static const Duration _ttl = Duration(minutes: 5);

  final Map<String, _ListingEntry> _cache = {};
  final List<String> _lruOrder = [];

  ListingCacheEntry? getListing(String path) {
    final normalized = _normalize(path);
    final entry = _cache[normalized];
    if (entry == null) return null;

    if (DateTime.now().difference(entry.savedAt) > _ttl) {
      _evict(normalized);
      return null;
    }

    _touch(normalized);
    return ListingCacheEntry(
      files: entry.filePaths.map((p) => File(p)).toList(growable: false),
      folders:
          entry.folderPaths.map((p) => Directory(p)).toList(growable: false),
      stats: entry.stats == null
          ? <String, FileStat>{}
          : Map<String, FileStat>.from(entry.stats!),
    );
  }

  void storeListing({
    required String path,
    required List<File> files,
    required List<Directory> folders,
    required Map<String, FileStat> stats,
  }) {
    final itemCount = files.length + folders.length;
    final normalized = _normalize(path);

    if (itemCount > _maxItemsPerEntry) {
      AppLogger.perf(
        '[DirListingCache] skipped "$normalized" ($itemCount items > $_maxItemsPerEntry)',
      );
      _evict(normalized);
      return;
    }

    final keepStats = itemCount <= _maxStatsItemsPerEntry;
    _cache[normalized] = _ListingEntry(
      filePaths: files.map((f) => f.path).toList(growable: false),
      folderPaths: folders.map((d) => d.path).toList(growable: false),
      stats: keepStats ? Map<String, FileStat>.from(stats) : null,
      savedAt: DateTime.now(),
    );
    _touch(normalized);
    AppLogger.perf(
      '[DirListingCache] stored "$normalized" ($itemCount items, stats=${keepStats ? 'yes' : 'no'})',
    );
  }

  void invalidate(String path) {
    final normalized = _normalize(path);
    if (_cache.containsKey(normalized)) {
      AppLogger.perf('[DirListingCache] invalidated "$normalized"');
      _evict(normalized);
    }

    final parent = _parentDir(normalized);
    if (parent != null && _cache.containsKey(parent)) {
      AppLogger.perf('[DirListingCache] invalidated parent "$parent"');
      _evict(parent);
    }
  }

  /// Removes moved or deleted items from every cached directory listing.
  ///
  /// Unlike [invalidate], this keeps the rest of the source listing warm so
  /// navigating back after a cut-and-paste does not require a full disk scan.
  void removePaths(Iterable<String> paths) {
    final removed = paths.map(_comparisonKey).toSet();
    if (removed.isEmpty) return;

    for (final cachePath in _cache.keys.toList(growable: false)) {
      final entry = _cache[cachePath];
      if (entry == null) continue;

      final filePaths = entry.filePaths
          .where((path) => !removed.contains(_comparisonKey(path)))
          .toList(growable: false);
      final folderPaths = entry.folderPaths
          .where((path) => !removed.contains(_comparisonKey(path)))
          .toList(growable: false);
      if (filePaths.length == entry.filePaths.length &&
          folderPaths.length == entry.folderPaths.length) {
        continue;
      }

      final stats =
          entry.stats == null ? null : Map<String, FileStat>.from(entry.stats!)
            ?..removeWhere((path, _) => removed.contains(_comparisonKey(path)));
      _cache[cachePath] = _ListingEntry(
        filePaths: filePaths,
        folderPaths: folderPaths,
        stats: stats,
        savedAt: DateTime.now(),
      );
      _touch(cachePath);
      AppLogger.perf(
        '[DirListingCache] removed moved/deleted paths from "$cachePath"',
      );
    }
  }

  void clearAll() {
    _cache.clear();
    _lruOrder.clear();
  }

  int get entryCount => _cache.length;

  int get totalCachedItems =>
      _cache.values.fold<int>(0, (sum, entry) => sum + entry.itemCount);

  String get debugPaths => _cache.keys.join('\n  ');

  static String _normalize(String path) {
    return path.replaceAll(RegExp(r'[/\\]+$'), '');
  }

  static String _comparisonKey(String path) {
    final normalized = _normalize(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  void _touch(String normalized) {
    _lruOrder.remove(normalized);
    _lruOrder.add(normalized);
    _evictOldestIfNeeded();
  }

  void _evict(String normalized) {
    _cache.remove(normalized);
    _lruOrder.remove(normalized);
  }

  void _evictOldestIfNeeded() {
    while (_cache.length > _maxEntries && _lruOrder.isNotEmpty) {
      final oldest = _lruOrder.removeAt(0);
      _cache.remove(oldest);
    }
  }

  String? _parentDir(String path) {
    final isWindows = path.length > 1 && path[1] == ':';
    if (isWindows) {
      final segments = path.split(RegExp(r'[/\\]'));
      if (segments.length <= 2) return null;
      return segments.take(segments.length - 1).join(r'\');
    }

    if (path == '/') return null;
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash <= 0) return '/';
    return path.substring(0, lastSlash);
  }
}
