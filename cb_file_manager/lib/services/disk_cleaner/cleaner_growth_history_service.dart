import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'disk_tree_node.dart';

class CleanerFolderGrowth {
  final String path;
  final int previousSizeBytes;
  final int currentSizeBytes;

  const CleanerFolderGrowth({
    required this.path,
    required this.previousSizeBytes,
    required this.currentSizeBytes,
  });

  int get increasedBytes => currentSizeBytes - previousSizeBytes;
}

class CleanerGrowthComparison {
  final DateTime? baselineAt;
  final List<CleanerFolderGrowth> folders;

  const CleanerGrowthComparison({
    required this.baselineAt,
    required this.folders,
  });

  bool get hasBaseline => baselineAt != null;
}

/// Stores the latest completed Cleaner scan per drive and reports meaningful
/// directory growth against that baseline.
///
/// This history is informational only. It is deliberately separate from junk
/// classification and deletion selection.
class CleanerGrowthHistoryService {
  static const int minimumGrowthBytes = 32 * 1024 * 1024;
  static const int maximumSnapshotDirectories = 5000;
  static const int maximumReportedFolders = 50;
  static const String _keyPrefix = 'cleaner.folder_growth.v1.';

  final SharedPreferences _preferences;

  const CleanerGrowthHistoryService(this._preferences);

  Future<CleanerGrowthComparison> compareAndStore(
    FullDiskScanResult result, {
    DateTime? scannedAt,
  }) async {
    final capturedAt = scannedAt ?? DateTime.now();
    final key = _snapshotKey(result.root.fullPath);
    final previous = _readSnapshot(_preferences.getString(key));
    final current = await _createSnapshot(result, capturedAt);

    final folders = previous == null
        ? const <CleanerFolderGrowth>[]
        : await _compare(previous, current);

    final saved = await _preferences.setString(
      key,
      jsonEncode(current.toJson()),
    );
    if (!saved) {
      throw StateError('Unable to persist the Cleaner growth baseline.');
    }
    return CleanerGrowthComparison(
      baselineAt: previous?.capturedAt,
      folders: folders,
    );
  }

  Future<List<CleanerFolderGrowth>> _compare(
    _CleanerGrowthSnapshot previous,
    _CleanerGrowthSnapshot current,
  ) async {
    final previousByPath = <String, _CleanerDirectorySnapshot>{
      for (final folder in previous.folders)
        _normalizePath(folder.path): folder,
    };
    // Snapshots written before folder-level coverage state was introduced
    // contain an unbounded list of raw issue paths. Build the index once so a
    // comparison remains linear in the retained folder count instead of
    // scanning every issue for every folder.
    final legacyIncompleteIndex = previous.incompletePaths.isEmpty
        ? null
        : await _IncompletePathIndex.build(previous.incompletePaths);
    final growth = <CleanerFolderGrowth>[];

    for (var index = 0; index < current.folders.length; index++) {
      final folder = current.folders[index];
      if (index % 256 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final normalizedPath = _normalizePath(folder.path);
      final oldFolder = previousByPath[normalizedPath];
      if (oldFolder == null ||
          folder.hasIncompleteCoverage ||
          oldFolder.hasIncompleteCoverage ||
          (legacyIncompleteIndex?.overlaps(normalizedPath) ?? false)) {
        continue;
      }
      final increasedBytes = folder.sizeBytes - oldFolder.sizeBytes;
      if (increasedBytes < minimumGrowthBytes) continue;
      growth.add(
        CleanerFolderGrowth(
          path: folder.path,
          previousSizeBytes: oldFolder.sizeBytes,
          currentSizeBytes: folder.sizeBytes,
        ),
      );
    }

    // Prefer the most specific useful folder when the same increase rolls up
    // through several ancestors (for example Cache -> AppData -> Users).
    growth.sort((a, b) => _pathDepth(b.path).compareTo(_pathDepth(a.path)));
    final retained = <CleanerFolderGrowth>[];
    final largestRetainedDescendantGrowth = <String, int>{};
    for (var index = 0; index < growth.length; index++) {
      final candidate = growth[index];
      final candidatePath = _normalizePath(candidate.path);
      final descendantGrowth = largestRetainedDescendantGrowth[candidatePath];
      final explainedByDescendant =
          descendantGrowth != null &&
          descendantGrowth * 100 >= candidate.increasedBytes * 80;
      if (!explainedByDescendant) {
        retained.add(candidate);
        _recordGrowthForAncestors(
          largestRetainedDescendantGrowth,
          candidatePath,
          candidate.increasedBytes,
        );
      }
      if (index % 256 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    retained.sort((a, b) => b.increasedBytes.compareTo(a.increasedBytes));
    return retained.take(maximumReportedFolders).toList(growable: false);
  }

  void _recordGrowthForAncestors(
    Map<String, int> largestGrowthByAncestor,
    String path,
    int increasedBytes,
  ) {
    var ancestor = path;
    while (true) {
      final separator = ancestor.lastIndexOf(r'\');
      if (separator < 0) return;
      ancestor = ancestor.substring(0, separator);
      final current = largestGrowthByAncestor[ancestor] ?? 0;
      if (increasedBytes > current) {
        largestGrowthByAncestor[ancestor] = increasedBytes;
      }
    }
  }

  Future<_CleanerGrowthSnapshot> _createSnapshot(
    FullDiskScanResult result,
    DateTime capturedAt,
  ) async {
    final folders = <_CleanerDirectorySnapshot>[];
    final pendingDirectories = <DiskTreeNode>[result.root];
    var visitedEntries = 0;

    while (pendingDirectories.isNotEmpty) {
      final node = pendingDirectories.removeLast();
      if (!identical(node, result.root)) {
        folders.add(
          _CleanerDirectorySnapshot(
            path: node.fullPath,
            sizeBytes: node.sizeBytes,
          ),
        );
      }
      for (final child in node.children) {
        if (!child.isFile) pendingDirectories.add(child);
        visitedEntries++;
        if (visitedEntries % 2048 == 0) {
          // Full-disk trees can contain millions of file nodes. Yield between
          // batches so history bookkeeping never monopolizes the UI isolate.
          await Future<void>.delayed(Duration.zero);
        }
      }

      // Bound memory before the final sort while retaining the largest folders.
      if (folders.length >= maximumSnapshotDirectories * 2) {
        folders.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        folders.removeRange(maximumSnapshotDirectories, folders.length);
        await Future<void>.delayed(Duration.zero);
      }
    }

    folders.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

    final retainedFolders = folders
        .take(maximumSnapshotDirectories)
        .toList(growable: false);
    // Keep the source lazy: a scan can report hundreds of thousands of issue
    // paths, so materializing a second raw Set here would create one large
    // synchronous UI-isolate burst before the cooperative index can yield.
    final incompleteIndex = await _IncompletePathIndex.build(
      _coveragePaths(result),
    );
    final foldersWithCoverage = <_CleanerDirectorySnapshot>[];
    for (var index = 0; index < retainedFolders.length; index++) {
      final folder = retainedFolders[index];
      foldersWithCoverage.add(
        folder.copyWith(
          hasIncompleteCoverage: incompleteIndex.overlaps(
            _normalizePath(folder.path),
          ),
        ),
      );
      if (index % 256 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return _CleanerGrowthSnapshot(
      capturedAt: capturedAt,
      folders: foldersWithCoverage,
      // New snapshots carry coverage on each retained folder. Keep this
      // legacy field empty so a scan with tens of thousands of coverage gaps
      // cannot write an equally large baseline to SharedPreferences.
      incompletePaths: const <String>[],
    );
  }

  _CleanerGrowthSnapshot? _readSnapshot(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return _CleanerGrowthSnapshot.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Iterable<String> _coveragePaths(FullDiskScanResult result) sync* {
    yield* result.inaccessible;
    for (final issue in result.coverageIssues) {
      yield issue.path;
    }
  }

  String _snapshotKey(String drivePath) {
    final encoded = base64Url
        .encode(utf8.encode(_normalizePath(drivePath)))
        .replaceAll('=', '');
    return '$_keyPrefix$encoded';
  }

  static String _normalizePath(String path) {
    var normalized = path.replaceAll('/', r'\').trim();
    while (normalized.endsWith(r'\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toUpperCase();
  }

  static int _pathDepth(String path) {
    return _normalizePath(path).split(r'\').length;
  }
}

class _CleanerGrowthSnapshot {
  final DateTime capturedAt;
  final List<_CleanerDirectorySnapshot> folders;
  final List<String> incompletePaths;

  const _CleanerGrowthSnapshot({
    required this.capturedAt,
    required this.folders,
    required this.incompletePaths,
  });

  factory _CleanerGrowthSnapshot.fromJson(Map<String, dynamic> json) {
    final rawFolders = json['folders'];
    final rawIncompletePaths = json['incompletePaths'];
    return _CleanerGrowthSnapshot(
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      folders: rawFolders is List
          ? rawFolders
                .whereType<Map>()
                .map(
                  (folder) => _CleanerDirectorySnapshot.fromJson(
                    Map<String, dynamic>.from(folder),
                  ),
                )
                .toList(growable: false)
          : const <_CleanerDirectorySnapshot>[],
      incompletePaths: rawIncompletePaths is List
          ? rawIncompletePaths.whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'capturedAt': capturedAt.toIso8601String(),
    'folders': folders.map((folder) => folder.toJson()).toList(),
    'incompletePaths': incompletePaths,
  };
}

class _CleanerDirectorySnapshot {
  final String path;
  final int sizeBytes;
  final bool hasIncompleteCoverage;

  const _CleanerDirectorySnapshot({
    required this.path,
    required this.sizeBytes,
    this.hasIncompleteCoverage = false,
  });

  factory _CleanerDirectorySnapshot.fromJson(Map<String, dynamic> json) {
    return _CleanerDirectorySnapshot(
      path: json['path'] as String,
      sizeBytes: json['sizeBytes'] as int,
      hasIncompleteCoverage: json['hasIncompleteCoverage'] == true,
    );
  }

  _CleanerDirectorySnapshot copyWith({bool? hasIncompleteCoverage}) {
    return _CleanerDirectorySnapshot(
      path: path,
      sizeBytes: sizeBytes,
      hasIncompleteCoverage:
          hasIncompleteCoverage ?? this.hasIncompleteCoverage,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': path,
    'sizeBytes': sizeBytes,
    'hasIncompleteCoverage': hasIncompleteCoverage,
  };
}

/// Normalized, boundary-aware index for legacy raw coverage paths.
///
/// A folder overlaps an incomplete path when it is the same path, an ancestor
/// of it, or a descendant of it. The sorted list makes descendant lookups a
/// single lower-bound probe, while the set makes ancestor lookups proportional
/// to path depth rather than to the number of issue paths.
class _IncompletePathIndex {
  static const int _sortBatchSize = 512;

  final Set<String> _paths;
  final List<String> _sortedPaths;

  const _IncompletePathIndex(this._paths, this._sortedPaths);

  static Future<_IncompletePathIndex> build(Iterable<String> rawPaths) async {
    final paths = <String>{};
    var processed = 0;
    for (final rawPath in rawPaths) {
      final normalized = CleanerGrowthHistoryService._normalizePath(rawPath);
      if (normalized.isNotEmpty && normalized != 'CANCELLED') {
        paths.add(normalized);
      }
      processed++;
      if (processed % 256 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final sortedPaths = await _sortCooperatively(paths);
    return _IncompletePathIndex(paths, sortedPaths);
  }

  static Future<List<String>> _sortCooperatively(Set<String> paths) async {
    if (paths.isEmpty) return <String>[];

    final chunks = <List<String>>[];
    var chunk = <String>[];
    for (final path in paths) {
      chunk.add(path);
      if (chunk.length == _sortBatchSize) {
        chunk.sort();
        chunks.add(chunk);
        chunk = <String>[];
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (chunk.isNotEmpty) {
      chunk.sort();
      chunks.add(chunk);
      await Future<void>.delayed(Duration.zero);
    }

    var sortedChunks = chunks;
    while (sortedChunks.length > 1) {
      final mergedChunks = <List<String>>[];
      for (var index = 0; index < sortedChunks.length; index += 2) {
        if (index + 1 == sortedChunks.length) {
          mergedChunks.add(sortedChunks[index]);
        } else {
          mergedChunks.add(
            await _mergeSortedChunks(
              sortedChunks[index],
              sortedChunks[index + 1],
            ),
          );
        }
      }
      sortedChunks = mergedChunks;
      await Future<void>.delayed(Duration.zero);
    }
    return sortedChunks.single;
  }

  static Future<List<String>> _mergeSortedChunks(
    List<String> left,
    List<String> right,
  ) async {
    final merged = <String>[];
    var leftIndex = 0;
    var rightIndex = 0;
    while (leftIndex < left.length || rightIndex < right.length) {
      if (rightIndex == right.length ||
          (leftIndex < left.length &&
              left[leftIndex].compareTo(right[rightIndex]) <= 0)) {
        merged.add(left[leftIndex++]);
      } else {
        merged.add(right[rightIndex++]);
      }
      if (merged.length % _sortBatchSize == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return merged;
  }

  bool overlaps(String rawFolderPath) {
    final folderPath = CleanerGrowthHistoryService._normalizePath(
      rawFolderPath,
    );
    if (folderPath.isEmpty) return false;

    var ancestor = folderPath;
    while (true) {
      if (_paths.contains(ancestor)) return true;
      final separator = ancestor.lastIndexOf(r'\');
      if (separator < 0) break;
      ancestor = ancestor.substring(0, separator);
    }

    final descendantPrefix = '$folderPath\\';
    final descendantIndex = _lowerBound(_sortedPaths, descendantPrefix);
    return descendantIndex < _sortedPaths.length &&
        _sortedPaths[descendantIndex].startsWith(descendantPrefix);
  }

  static int _lowerBound(List<String> values, String target) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (values[middle].compareTo(target) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}
