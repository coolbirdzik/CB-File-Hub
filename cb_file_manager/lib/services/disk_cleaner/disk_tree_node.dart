/// Tree node representing a directory or file in the full disk scan.
///
/// Used by the full-disk TreeSize-style view. Each node tracks its own size
/// (for files) or the sum of children sizes (for directories), plus metadata
/// about whether it matches a known junk category.
class DiskTreeNode {
  /// Display name (last path segment).
  final String name;

  /// Full absolute path.
  final String fullPath;

  /// True if this node is a file (leaf), false if directory.
  final bool isFile;

  /// Size in bytes. For directories, this is the sum of all descendant files.
  int sizeBytes;

  /// Number of files in this subtree (1 for leaf files).
  int fileCount;

  /// Children nodes (empty for files). Sorted by size descending after scan.
  final List<DiskTreeNode> children;

  /// If this node (or its subtree) matches a known junk category, this is set
  /// to the category ID. Null means "not junk / unknown".
  String? junkCategoryId;

  /// Whether the user has selected this node for deletion.
  bool isSelectedForDeletion;

  /// Whether this node is expanded in the UI.
  bool isExpanded;

  /// Cached flag: true if this node or any descendant is selected for deletion.
  /// Reset to null when selection changes to force recalculation.
  bool? _hasSelectionInSubtree;

  DiskTreeNode({
    required this.name,
    required this.fullPath,
    this.isFile = false,
    this.sizeBytes = 0,
    this.fileCount = 0,
    List<DiskTreeNode>? children,
    this.junkCategoryId,
    this.isSelectedForDeletion = false,
    this.isExpanded = false,
  }) : children = children ?? [];

  /// Percentage of parent's size.
  double percentOf(int parentSize) =>
      parentSize > 0 ? sizeBytes / parentSize : 0.0;

  /// Whether this node or any descendant is junk.
  bool get isJunk => junkCategoryId != null;

  /// Whether any child is junk (for partial highlighting).
  bool get hasJunkChildren {
    for (final child in children) {
      if (child.isJunk || child.hasJunkChildren) return true;
    }
    return false;
  }

  /// Total junk bytes in this subtree.
  int get junkBytes {
    if (isJunk) return sizeBytes;
    int total = 0;
    for (final child in children) {
      total += child.junkBytes;
    }
    return total;
  }

  /// Whether this node or any descendant has been selected for deletion.
  /// Uses caching to avoid O(n²) repeated traversal during tree filtering.
  bool get hasSelectionInSubtree {
    if (_hasSelectionInSubtree != null) return _hasSelectionInSubtree!;

    if (isSelectedForDeletion && fullPath.isNotEmpty) {
      _hasSelectionInSubtree = true;
      return true;
    }

    for (final child in children) {
      if (child.hasSelectionInSubtree) {
        _hasSelectionInSubtree = true;
        return true;
      }
    }

    _hasSelectionInSubtree = false;
    return false;
  }

  /// Invalidate the selection cache for this node and all ancestors.
  /// Call this after modifying isSelectedForDeletion.
  void invalidateSelectionCache() {
    _hasSelectionInSubtree = null;
    for (final child in children) {
      child.invalidateSelectionCache();
    }
  }

  /// Sort children by size descending (recursive).
  void sortBySize() {
    children.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    for (final child in children) {
      child.sortBySize();
    }
  }
}

/// Progress event from the full disk scan isolate.
class FullDiskScanProgress {
  /// Number of directories scanned so far.
  final int directoriesScanned;

  /// Number of files counted so far.
  final int filesScanned;

  /// Total bytes counted so far.
  final int bytesScanned;

  /// Current directory being scanned.
  final String currentPath;

  const FullDiskScanProgress({
    required this.directoriesScanned,
    required this.filesScanned,
    required this.bytesScanned,
    required this.currentPath,
  });
}

/// Why a path was not measured completely during a full-disk scan.
enum FullDiskScanCoverageIssueReason {
  inaccessible,
  maxDepthReached,
  reparsePoint,
  cancelled,
  scanInProgress,
}

/// A path whose size is absent or incomplete in a [FullDiskScanResult].
class FullDiskScanCoverageIssue {
  final String path;
  final FullDiskScanCoverageIssueReason reason;

  /// Optional native error code or a short diagnostic intended for logs.
  final String? detail;

  const FullDiskScanCoverageIssue({
    required this.path,
    required this.reason,
    this.detail,
  });
}

/// Result of a full disk scan.
class FullDiskScanResult {
  /// Root node of the tree (the drive root, e.g. C:\).
  final DiskTreeNode root;

  /// Total scan duration.
  final Duration duration;

  /// Directories that could not be accessed (permission denied, etc.).
  ///
  /// Kept for compatibility with existing Cleaner consumers. New code should
  /// use [coverageIssues], which also describes depth and reparse-point gaps.
  final List<String> inaccessible;

  /// Every known gap in the final tree's measurement coverage.
  final List<FullDiskScanCoverageIssue> coverageIssues;

  const FullDiskScanResult({
    required this.root,
    required this.duration,
    this.inaccessible = const <String>[],
    this.coverageIssues = const <FullDiskScanCoverageIssue>[],
  });

  bool get isPartial => inaccessible.isNotEmpty || coverageIssues.isNotEmpty;
}
