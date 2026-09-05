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

  /// Stable NTFS file reference number for directory change tracking.
  ///
  /// This is metadata for incremental scans only. It is not a deletion
  /// identity and may be absent on filesystems that do not expose it.
  final int? fileReferenceNumber;

  /// Shared immutable stand-in so childless nodes cost no list allocation.
  ///
  /// A full-disk tree is dominated by file leaves, and giving each of them its
  /// own growable list was costing tens of megabytes per scan for lists that
  /// were never written to.
  static const List<DiskTreeNode> _noChildren = <DiskTreeNode>[];

  /// Null until this node actually gains a child.
  List<DiskTreeNode>? _children;

  /// Children nodes (empty for files). Sorted by size descending after scan.
  ///
  /// The returned list is read-only — mutate through [addChild] or
  /// [replaceChildren] so childless nodes keep sharing [_noChildren].
  List<DiskTreeNode> get children => _children ?? _noChildren;

  /// Appends [child], allocating the backing list on first use.
  void addChild(DiskTreeNode child) {
    (_children ??= <DiskTreeNode>[]).add(child);
  }

  /// Replaces every child, dropping the backing list when [next] is empty.
  void replaceChildren(Iterable<DiskTreeNode> next) {
    if (next.isEmpty) {
      _children = null;
      return;
    }
    _children = next.toList();
  }

  /// If this node (or its subtree) matches a known junk category, this is set
  /// to the category ID. Null means "not junk / unknown".
  String? junkCategoryId;

  /// How many real entries this node stands in for.
  ///
  /// Zero for every scanned file and directory. A positive value marks a
  /// synthetic roll-up row that the scan isolate substituted for entries too
  /// small or too numerous to ship to the UI — see [isAggregate].
  final int aggregatedItemCount;

  /// True when this row summarises entries that were dropped from the tree.
  ///
  /// Aggregate rows carry an empty [fullPath], which every selection, junk and
  /// deletion helper already treats as "not a real target".
  bool get isAggregate => aggregatedItemCount > 0;

  /// Whether the user has selected this node for deletion.
  bool isSelectedForDeletion;

  /// Whether this node is expanded in the UI.
  bool isExpanded;

  /// Cached flag: true if this node or any descendant is selected for deletion.
  /// Reset to null when selection changes to force recalculation.
  bool? _hasSelectionInSubtree;

  bool? _hasJunkChildrenCache;
  int? _junkBytesCache;

  DiskTreeNode({
    required this.name,
    required this.fullPath,
    this.isFile = false,
    this.sizeBytes = 0,
    this.fileCount = 0,
    this.fileReferenceNumber,
    List<DiskTreeNode>? children,
    this.junkCategoryId,
    this.isSelectedForDeletion = false,
    this.isExpanded = false,
    this.aggregatedItemCount = 0,
  }) : _children = (children == null || children.isEmpty) ? null : children;

  /// Percentage of parent's size.
  double percentOf(int parentSize) =>
      parentSize > 0 ? sizeBytes / parentSize : 0.0;

  /// Whether this node or any descendant is junk.
  bool get isJunk => junkCategoryId != null;

  /// Whether any child is junk (for partial highlighting).
  bool get hasJunkChildren {
    final cached = _hasJunkChildrenCache;
    if (cached != null) return cached;
    for (final child in children) {
      if (child.isJunk || child.hasJunkChildren) {
        _hasJunkChildrenCache = true;
        return true;
      }
    }
    _hasJunkChildrenCache = false;
    return false;
  }

  /// Total junk bytes in this subtree.
  int get junkBytes {
    if (isJunk) return sizeBytes;
    final cached = _junkBytesCache;
    if (cached != null) return cached;
    int total = 0;
    for (final child in children) {
      total += child.junkBytes;
    }
    _junkBytesCache = total;
    return total;
  }

  /// Invalidates cached junk aggregates after scan metadata or tree changes.
  void invalidateJunkCache() {
    _hasJunkChildrenCache = null;
    _junkBytesCache = null;
    for (final child in children) {
      child.invalidateJunkCache();
    }
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

  /// Stores junk aggregates calculated outside the UI isolate.
  ///
  /// Full-disk scans can contain many thousands of rows. The scan isolate
  /// computes these values before the result crosses the isolate boundary so
  /// reading [junkBytes] or [hasJunkChildren] after completion is constant-time
  /// on the UI isolate.
  void cacheJunkMetadata({
    required int junkBytes,
    required bool hasJunkChildren,
  }) {
    _junkBytesCache = junkBytes;
    _hasJunkChildrenCache = hasJunkChildren;
  }

  /// Sort children by size descending.
  ///
  /// Pass `recursive: false` to order just this node's children — the scan
  /// sorts each directory as it finishes, so a whole-tree pass afterwards
  /// would only redo work.
  void sortBySize({bool recursive = true}) {
    final children = _children;
    if (children == null) return;
    children.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    if (!recursive) return;
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

  /// True when this progress belongs to a journal-backed incremental scan.
  final bool isIncremental;

  const FullDiskScanProgress({
    required this.directoriesScanned,
    required this.filesScanned,
    required this.bytesScanned,
    required this.currentPath,
    this.isIncremental = false,
  });
}

/// Cursor into one volume's NTFS USN Journal.
class DiskScanJournalCursor {
  final int journalId;
  final int nextUsn;

  const DiskScanJournalCursor({required this.journalId, required this.nextUsn});
}

enum FullDiskScanMode { full, incremental }

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

/// A large path whose filesystem timestamps suggest it has not been active
/// recently.
///
/// This is analysis evidence only. It is never a cleanup target because a
/// large or old path may still contain important user data.
class FullDiskScanInsight {
  final String name;
  final String path;
  final bool isFile;
  final int sizeBytes;
  final DateTime? lastModified;
  final DateTime? lastAccessed;

  const FullDiskScanInsight({
    required this.name,
    required this.path,
    required this.isFile,
    required this.sizeBytes,
    this.lastModified,
    this.lastAccessed,
  });

  /// The cautious filesystem activity hint used by the old-large heuristic.
  ///
  /// Directory access timestamps are commonly refreshed while a scanner walks
  /// the directory, so directory evidence intentionally uses last-modified
  /// only. Files can use the newest available timestamp because their access
  /// time is not changed by enumerating the parent directory.
  DateTime? get lastActivity {
    if (!isFile) return lastModified;
    if (lastModified == null) return lastAccessed;
    if (lastAccessed == null) return lastModified;
    return lastModified!.isAfter(lastAccessed!) ? lastModified : lastAccessed;
  }
}

/// Result of a full disk scan.
class FullDiskScanResult {
  /// Root node of the tree (the drive root, e.g. C:\).
  final DiskTreeNode root;

  /// Nodes actually present in [root] after file-row compaction.
  ///
  /// All scanned directories are retained. Small and excess file leaves may
  /// be represented by aggregate rows. Counted in the scan isolate so callers
  /// do not need to traverse the tree just to report the result size.
  final int nodeCount;

  /// Junk aggregates calculated in the scan isolate.
  ///
  /// Null is retained for results created by older callers or test fixtures.
  final int? junkBytes;
  final int? cleanableCount;

  /// Total scan duration.
  final Duration duration;

  /// Directories that could not be accessed (permission denied, etc.).
  ///
  /// Kept for compatibility with existing Cleaner consumers. New code should
  /// use [coverageIssues], which also describes depth and reparse-point gaps.
  final List<String> inaccessible;

  /// Every known gap in the final tree's measurement coverage.
  final List<FullDiskScanCoverageIssue> coverageIssues;

  /// Bounded, ranked evidence about large paths with old filesystem activity
  /// timestamps. These entries are informational and are not deletion
  /// candidates.
  final List<FullDiskScanInsight> oldLargeItems;

  /// Whether the result reused a previous tree and applied journal changes.
  final FullDiskScanMode scanMode;

  /// Number of parent directories refreshed by an incremental scan.
  final int changedDirectoryCount;

  /// Current journal cursor, when the volume exposes a usable USN Journal.
  final DiskScanJournalCursor? journalCursor;

  /// Why an incremental attempt could not be used and a full scan ran.
  final String? incrementalFallbackReason;

  const FullDiskScanResult({
    required this.root,
    required this.duration,
    this.nodeCount = 0,
    this.junkBytes,
    this.cleanableCount,
    this.inaccessible = const <String>[],
    this.coverageIssues = const <FullDiskScanCoverageIssue>[],
    this.oldLargeItems = const <FullDiskScanInsight>[],
    this.scanMode = FullDiskScanMode.full,
    this.changedDirectoryCount = 0,
    this.journalCursor,
    this.incrementalFallbackReason,
  });

  bool get isPartial => inaccessible.isNotEmpty || coverageIssues.isNotEmpty;
}
