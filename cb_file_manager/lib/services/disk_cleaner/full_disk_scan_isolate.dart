import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

import 'disk_tree_node.dart';
import 'usn_journal.dart';

/// Files smaller than this are folded into a roll-up row instead of being
/// shipped to the UI individually. Directories are always retained, even when
/// their total size is below this threshold, so the result remains a complete
/// folder inventory.
const int defaultMinDisplayEntryBytes = 1024 * 1024;

/// Upper bound on file rows kept per directory. Directories are never folded;
/// this only bounds the number of individual file rows retained beneath each
/// directory.
const int defaultMaxChildrenPerDirectory = 200;

/// Files are reported as old when their newest available filesystem activity
/// timestamp is at least this many days in the past. Directories use their
/// modified timestamp only because directory access times are contaminated by
/// scanner enumeration on common Windows filesystems.
const int defaultOldLargeItemAgeDays = 180;

/// Minimum size for a file to appear in the old-large evidence list.
const int defaultOldLargeFileBytes = 100 * 1024 * 1024;

/// Minimum measured size for a folder to appear in the old-large evidence
/// list. The folder is evaluated after its children have been scanned.
const int defaultOldLargeDirectoryBytes = 512 * 1024 * 1024;

/// Keep the evidence payload small and useful on a busy system drive.
const int defaultOldLargeItemsPerType = 50;

/// Keep the final old-large evidence payload explicitly bounded even if the
/// per-type retention policy changes independently in the future.
const int defaultMaxOldLargeItems = 100;

String _normalizeComparableWindowsPath(String path) {
  var normalized = path.trim().replaceAll('/', '\\').toUpperCase();
  while (normalized.length > 3 && normalized.endsWith('\\')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _isWindowsPathWithin(String path, String ancestor) {
  final normalizedPath = _normalizeComparableWindowsPath(path);
  final normalizedAncestor = _normalizeComparableWindowsPath(ancestor);
  if (normalizedPath == normalizedAncestor) return true;
  final ancestorPrefix = normalizedAncestor.endsWith('\\')
      ? normalizedAncestor
      : '$normalizedAncestor\\';
  return normalizedPath.startsWith(ancestorPrefix);
}

/// Returns whether a cached old-large insight must be rescanned after a set of
/// dirty directory changes.
///
/// A directory insight is invalidated when either side contains the other:
/// changing a descendant changes its measured total, while changing an
/// ancestor can add or remove the directory itself. File insights only need
/// invalidation when the file is inside a dirty directory.
bool isOldLargeInsightInvalidatedByDirtyDirectories(
  FullDiskScanInsight insight,
  Iterable<String> dirtyDirectories,
) {
  return dirtyDirectories.any((dirtyDirectory) {
    if (_isWindowsPathWithin(insight.path, dirtyDirectory)) return true;
    return !insight.isFile &&
        _isWindowsPathWithin(dirtyDirectory, insight.path);
  });
}

/// Maximum number of nodes copied into an in-progress preview tree.
///
/// This is a global budget for the whole preview, rather than a per-directory
/// limit. The completed result still contains the exact bounded display tree;
/// this only keeps progress snapshots cheap to copy across the isolate port.
const int defaultPreviewNodeBudget = 2048;

/// Maximum number of completed-tree nodes sent in one isolate message.
///
/// Completed scans are sent as acknowledged preorder batches so the receiving
/// isolate can reconstruct the exact tree without one large graph copy.
const int defaultFinalTreeBatchSize = 256;

/// Returns whether [insight] meets the informational old-and-large heuristic.
///
/// Files use a newer access timestamp when available, while directories use
/// last-modified only because scanning can refresh their access timestamp.
bool qualifiesAsOldLargeDiskInsight(
  FullDiskScanInsight insight, {
  DateTime? now,
}) {
  final activity = insight.lastActivity;
  if (activity == null) return false;

  final threshold = insight.isFile
      ? defaultOldLargeFileBytes
      : defaultOldLargeDirectoryBytes;
  if (insight.sizeBytes < threshold) return false;

  final cutoff = (now ?? DateTime.now()).subtract(
    const Duration(days: defaultOldLargeItemAgeDays),
  );
  return !activity.isAfter(cutoff);
}

/// Sorts old-large evidence by size, then path for deterministic presentation.
int compareOldLargeDiskInsights(FullDiskScanInsight a, FullDiskScanInsight b) {
  final sizeOrder = b.sizeBytes.compareTo(a.sizeBytes);
  return sizeOrder != 0 ? sizeOrder : a.path.compareTo(b.path);
}

/// Retains one qualified insight in a bounded, size-ranked list.
///
/// The caller supplies the scan timestamp so incremental scans keep the same
/// age semantics as full scans. Unknown activity is excluded by
/// [qualifiesAsOldLargeDiskInsight].
void retainOldLargeDiskInsight(
  List<FullDiskScanInsight> target,
  FullDiskScanInsight insight, {
  required DateTime now,
  int maxItems = defaultOldLargeItemsPerType,
}) {
  if (maxItems <= 0 || !qualifiesAsOldLargeDiskInsight(insight, now: now)) {
    return;
  }

  if (target.length >= maxItems &&
      compareOldLargeDiskInsights(insight, target.last) >= 0) {
    return;
  }
  target.add(insight);
  target.sort(compareOldLargeDiskInsights);
  if (target.length > maxItems) {
    target.removeRange(maxItems, target.length);
  }
}

/// Combines independently retained folder and file evidence under the final
/// cross-type bound. The returned list is deterministic and size-ranked.
List<FullDiskScanInsight> buildBoundedOldLargeDiskEvidence({
  required Iterable<FullDiskScanInsight> folders,
  required Iterable<FullDiskScanInsight> files,
  int maxItems = defaultMaxOldLargeItems,
}) {
  if (maxItems <= 0) return <FullDiskScanInsight>[];
  final items = <FullDiskScanInsight>[...folders, ...files]
    ..sort(compareOldLargeDiskInsights);
  if (items.length > maxItems) {
    items.removeRange(maxItems, items.length);
  }
  return items;
}

/// Serializable junk rule consumed by the full-disk scan isolate.
///
/// An empty [includeGlobs] marks the whole resolved directory subtree. When
/// globs are present, only matching files under [basePath] are marked.
class FullDiskJunkRule {
  final String basePath;
  final String categoryId;
  final List<String> includeGlobs;

  const FullDiskJunkRule({
    required this.basePath,
    required this.categoryId,
    this.includeGlobs = const <String>[],
  });
}

/// Spawns an isolate that recursively scans [drivePath] and builds a
/// [DiskTreeNode] tree with sizes for every directory.
///
/// Uses Win32 FindFirstFileW/FindNextFileW for maximum speed — each directory
/// entry returns name + size + attributes in a single syscall, eliminating the
/// need for separate stat() calls. ~5-10x faster than Dart's listSync+statSync.
///
/// The worker compacts only the file tail before the result crosses the isolate
/// boundary. A raw system drive may hold millions of file entries, while the
/// Cleaner still needs a complete directory inventory. [minDisplayEntryBytes]
/// and [maxChildrenPerDirectory] therefore bound file rows per directory;
/// every directory and its exact size/file count remain in the result tree.
Future<FullDiskScanHandle> spawnFullDiskScan({
  required String drivePath,
  int maxDepth = 20,
  int minDisplayEntryBytes = defaultMinDisplayEntryBytes,
  int maxChildrenPerDirectory = defaultMaxChildrenPerDirectory,
  int finalTreeBatchSize = defaultFinalTreeBatchSize,
  List<FullDiskJunkRule> junkRules = const <FullDiskJunkRule>[],
  DiskTreeNode? baseRoot,
  DiskScanJournalCursor? journalCursor,
  List<FullDiskScanInsight> baseOldLargeItems = const <FullDiskScanInsight>[],
  List<String> trackedDirtyDirectories = const <String>[],
  bool hasTrackedChanges = false,
  void Function(FullDiskScanResult result)? onCompleted,
}) async {
  final receivePort = ReceivePort();
  final args = _FullScanArgs(
    sendPort: receivePort.sendPort,
    drivePath: drivePath,
    maxDepth: maxDepth,
    minDisplayEntryBytes: minDisplayEntryBytes,
    maxChildrenPerDirectory: maxChildrenPerDirectory,
    finalTreeBatchSize: finalTreeBatchSize,
    junkRules: junkRules,
    baseRoot: baseRoot,
    journalCursor: journalCursor,
    baseOldLargeItems: baseOldLargeItems,
    trackedDirtyDirectories: trackedDirtyDirectories,
    hasTrackedChanges: hasTrackedChanges,
  );

  final isolate = await Isolate.spawn(_fullDiskScanWorker, args);
  final handle = FullDiskScanHandle._(
    isolate: isolate,
    receivePort: receivePort,
    drivePath: drivePath,
  );

  receivePort.listen((dynamic msg) {
    if (handle._cancelled || handle._terminal) return;
    try {
      if (msg is _ProgressMsg) {
        if (!handle._progress.isClosed) {
          handle._progress.add(
            FullDiskScanProgress(
              directoriesScanned: msg.dirs,
              filesScanned: msg.files,
              bytesScanned: msg.bytes,
              currentPath: msg.currentPath,
              isIncremental: msg.isIncremental,
            ),
          );
        }
      } else if (msg is _TreeMsg) {
        if (!handle._treeSnapshots.isClosed) {
          handle._treeSnapshots.add(msg.root);
        }
      } else if (msg is _FinalTreeBatchMsg) {
        handle._finalTreeAssembler.addBatch(
          index: msg.index,
          records: msg.records,
        );
        msg.ackPort.send(_FinalTreeBatchAck(msg.index));
      } else if (msg is _DoneMsg) {
        if (handle._finalTreeAssembler.nodeCount != msg.nodeCount) {
          throw StateError(
            'The final disk scan reconstructed '
            '${handle._finalTreeAssembler.nodeCount} nodes, but the worker '
            'reported ${msg.nodeCount}.',
          );
        }
        final result = FullDiskScanResult(
          root: handle._finalTreeAssembler.root,
          nodeCount: msg.nodeCount,
          junkBytes: msg.junkBytes,
          cleanableCount: msg.cleanableCount,
          duration: DateTime.now().difference(handle._startedAt),
          inaccessible: msg.inaccessible,
          coverageIssues: msg.coverageIssues,
          oldLargeItems: msg.oldLargeItems,
          scanMode: msg.scanMode,
          changedDirectoryCount: msg.changedDirectoryCount,
          journalCursor: msg.journalCursor,
          incrementalFallbackReason: msg.incrementalFallbackReason,
        );
        receivePort.close();
        if (!handle._progress.isClosed) handle._progress.close();
        if (!handle._treeSnapshots.isClosed) handle._treeSnapshots.close();
        try {
          onCompleted?.call(result);
        } catch (error, stackTrace) {
          handle._completeError(error, stackTrace);
          return;
        }
        if (!handle._done.isCompleted) {
          handle._terminal = true;
          handle._done.complete(result);
        }
      }
    } catch (error, stackTrace) {
      handle._completeError(error, stackTrace);
    }
  });

  return handle;
}

/// Handle for an in-flight full disk scan.
class FullDiskScanHandle {
  final Isolate? _isolate;
  final ReceivePort _receivePort;
  final String drivePath;
  // Single-subscription (not broadcast) on purpose: the isolate starts sending
  // as soon as it is spawned, but callers can only attach their listeners
  // after `spawnFullDiskScan` returns. A broadcast controller discards
  // everything emitted in that gap, so the UI could miss the early progress
  // ticks and the first tree snapshots entirely. These controllers buffer
  // until the listener arrives. Each handle is listened to exactly once.
  final StreamController<FullDiskScanProgress> _progress =
      StreamController<FullDiskScanProgress>();
  final StreamController<DiskTreeNode> _treeSnapshots =
      StreamController<DiskTreeNode>();
  final Completer<FullDiskScanResult> _done = Completer<FullDiskScanResult>();
  final _FinalTreeAssembler _finalTreeAssembler = _FinalTreeAssembler();
  final DateTime _startedAt = DateTime.now();
  bool _cancelled = false;
  bool _terminal = false;

  FullDiskScanHandle._({
    required Isolate this._isolate,
    required this._receivePort,
    required this.drivePath,
  });

  /// Creates a completed handle for a tracked snapshot with no dirty
  /// directories. This keeps the public stream/future contract while avoiding
  /// an isolate spawn and a second tree copy.
  FullDiskScanHandle.completed({
    required this.drivePath,
    required FullDiskScanResult result,
  }) : _isolate = null,
       _receivePort = ReceivePort() {
    _treeSnapshots.add(result.root);
    _treeSnapshots.close();
    _progress.close();
    _receivePort.close();
    _done.complete(result);
  }

  Stream<FullDiskScanProgress> get progress => _progress.stream;
  Stream<DiskTreeNode> get treeSnapshots => _treeSnapshots.stream;
  Future<FullDiskScanResult> get future => _done.future;
  bool get isCancelled => _cancelled;

  void _completeError(Object error, StackTrace stackTrace) {
    if (_cancelled || _terminal) return;
    _terminal = true;
    try {
      _isolate?.kill(priority: Isolate.immediate);
    } catch (_) {}
    _receivePort.close();
    if (!_progress.isClosed) _progress.close();
    if (!_treeSnapshots.isClosed) _treeSnapshots.close();
    if (!_done.isCompleted) {
      _done.completeError(error, stackTrace);
    }
  }

  void cancel() {
    if (_cancelled || _terminal) return;
    _cancelled = true;
    _terminal = true;
    try {
      _isolate?.kill(priority: Isolate.immediate);
    } catch (_) {}
    _receivePort.close();
    if (!_progress.isClosed) _progress.close();
    if (!_treeSnapshots.isClosed) _treeSnapshots.close();
    if (!_done.isCompleted) {
      _done.complete(
        FullDiskScanResult(
          root: DiskTreeNode(name: drivePath, fullPath: drivePath),
          duration: DateTime.now().difference(_startedAt),
          inaccessible: const ['cancelled'],
          coverageIssues: <FullDiskScanCoverageIssue>[
            FullDiskScanCoverageIssue(
              path: drivePath,
              reason: FullDiskScanCoverageIssueReason.cancelled,
            ),
          ],
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Isolate worker — Win32 FindFirstFileW/FindNextFileW for fast scanning
// ---------------------------------------------------------------------------

/// FILE_ATTRIBUTE_DIRECTORY constant.
const int _fileAttributeDirectory = 0x10;

/// FILE_ATTRIBUTE_REPARSE_POINT — junctions, symlinks.
const int _fileAttributeReparsePoint = 0x400;

/// Converts a Windows FILETIME (100-nanosecond ticks since 1601 UTC) without
/// issuing another filesystem query.
DateTime? _fileTimeToDateTime(win32.FILETIME fileTime) {
  return _fileTimePartsToDateTime(
    fileTime.dwLowDateTime,
    fileTime.dwHighDateTime,
  );
}

DateTime? _fileTimePartsToDateTime(int low, int high) {
  final ticks = (high << 32) | (low & 0xffffffff);
  const windowsToUnixEpochTicks = 116444736000000000;
  final unixTicks = ticks - windowsToUnixEpochTicks;
  if (unixTicks <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(
    unixTicks ~/ 10000,
    isUtc: true,
  ).toLocal();
}

/// Creates a bounded preview without traversing or allocating the complete
/// scan tree. The per-level cap keeps a single wide directory readable, while
/// [maxNodes] is the hard global ceiling across every level.
DiskTreeNode cloneDiskTreePreview(
  DiskTreeNode node, {
  int maxDepth = 3,
  int maxChildrenPerNode = 40,
  int maxNodes = defaultPreviewNodeBudget,
}) {
  final budget = _PreviewNodeBudget(maxNodes);

  DiskTreeNode clone(DiskTreeNode source, int depth) {
    // The root is always retained. Once the budget is exhausted, callers get
    // a valid prefix node with its exact aggregate totals but no child rows.
    if (budget.remaining <= 0) {
      return DiskTreeNode(
        name: source.name,
        fullPath: source.fullPath,
        isFile: source.isFile,
        sizeBytes: source.sizeBytes,
        fileCount: source.fileCount,
        fileReferenceNumber: source.fileReferenceNumber,
        junkCategoryId: source.junkCategoryId,
        isExpanded: source.isExpanded,
        aggregatedItemCount: source.aggregatedItemCount,
      )..cacheJunkMetadata(
        junkBytes: source.junkBytes,
        hasJunkChildren: source.hasJunkChildren,
      );
    }
    budget.remaining--;

    final result = DiskTreeNode(
      name: source.name,
      fullPath: source.fullPath,
      isFile: source.isFile,
      sizeBytes: source.sizeBytes,
      fileCount: source.fileCount,
      fileReferenceNumber: source.fileReferenceNumber,
      junkCategoryId: source.junkCategoryId,
      isExpanded: source.isExpanded,
      aggregatedItemCount: source.aggregatedItemCount,
    );
    if (depth < maxDepth && source.children.isNotEmpty) {
      final takeCount = source.children.length < maxChildrenPerNode
          ? source.children.length
          : maxChildrenPerNode;
      for (var index = 0; index < takeCount && budget.remaining > 0; index++) {
        final child = source.children[index];
        // At deeper levels, file rows are less useful than the directory
        // shape and are omitted from the progress preview.
        if (depth >= 2 && child.isFile) continue;
        result.addChild(clone(child, depth + 1));
      }
    }
    result.cacheJunkMetadata(
      junkBytes: source.junkBytes,
      hasJunkChildren: source.hasJunkChildren,
    );
    return result;
  }

  return clone(node, 0);
}

class _PreviewNodeBudget {
  int remaining;

  _PreviewNodeBudget(int maxNodes) : remaining = maxNodes < 1 ? 1 : maxNodes;
}

/// Uses the larger kernel directory buffer and avoids querying short names.
///
/// Some filesystem providers do not implement the Ex info level. Retrying the
/// legacy API on an invalid Ex handle preserves the old coverage behavior; an
/// inaccessible directory still reaches the existing coverage reporting path
/// after both calls fail.
win32.HANDLE _findFirstFile(
  Pointer<Utf16> searchPath,
  Pointer<win32.WIN32_FIND_DATA> findData,
) {
  try {
    final handle = win32.FindFirstFileEx(
      win32.PCWSTR(searchPath),
      win32.FindExInfoBasic,
      findData,
      win32.FindExSearchNameMatch,
      win32.FIND_FIRST_EX_LARGE_FETCH,
    ).value;
    if (handle.isValid) return handle;
  } catch (_) {
    // Older Windows/filesystem providers can reject FindFirstFileExW.
  }
  return win32.FindFirstFile(win32.PCWSTR(searchPath), findData).value;
}

void _fullDiskScanWorker(_FullScanArgs args) {
  final sendPort = args.sendPort;
  final inaccessible = <String>[];
  final coverageIssues = <FullDiskScanCoverageIssue>[];
  final oldLargeFiles = <FullDiskScanInsight>[];
  final oldLargeDirectories = <FullDiskScanInsight>[];
  final scanStartedAt = DateTime.now();
  final wholeDirRules = args.junkRules
      .where((rule) => rule.includeGlobs.isEmpty)
      .map(
        (rule) => _WorkerWholeDirRule(
          path: rule.basePath.toUpperCase(),
          prefix: '${rule.basePath.toUpperCase()}\\',
          categoryId: rule.categoryId,
        ),
      )
      .toList(growable: false);
  final globRules = args.junkRules
      .where((rule) => rule.includeGlobs.isNotEmpty)
      .map(
        (rule) => _WorkerGlobRule(
          basePath: rule.basePath.toUpperCase(),
          categoryId: rule.categoryId,
          globs: rule.includeGlobs.map(_globToRegex).toList(growable: false),
        ),
      )
      .toList(growable: false);
  int totalDirs = 0;
  int totalFiles = 0;
  int totalBytes = 0;
  DateTime lastFlush = DateTime.now();
  DateTime lastTreeFlush = DateTime.now();
  DiskTreeNode? rootSnapshot;
  var incrementalScan = false;
  final canReadJournalChanges = DiskUsnJournalReader.canReadChanges(
    args.drivePath,
  );
  // Directory IDs are only needed when a caller explicitly requests a USN
  // refresh. The normal path uses the watcher started by DiskCleanerService;
  // avoiding a CreateFile/GetFileInformationByHandle pair for every folder
  // removes the dominant cold-scan metadata cost. If a journal refresh is
  // later required without IDs, it reports a reason and safely falls back to
  // a complete scan instead of risking stale coverage.
  final collectDirectoryFileIds =
      args.baseRoot != null && args.journalCursor != null;

  String? wholeDirCategory(String path) {
    final upperPath = path.toUpperCase();
    for (final rule in wholeDirRules) {
      if (upperPath == rule.path || upperPath.startsWith(rule.prefix)) {
        return rule.categoryId;
      }
    }
    return null;
  }

  List<_WorkerGlobRule>? globRulesForDirectory(String path) {
    if (globRules.isEmpty) return null;
    final directoryPath = path.toUpperCase();
    List<_WorkerGlobRule>? matches;
    for (final rule in globRules) {
      if (directoryPath != rule.basePath &&
          !directoryPath.startsWith('${rule.basePath}\\')) {
        continue;
      }
      (matches ??= <_WorkerGlobRule>[]).add(rule);
    }
    return matches;
  }

  String? globCategory(String fileName, List<_WorkerGlobRule>? directoryRules) {
    if (directoryRules == null) return null;
    final upperFileName = fileName.toUpperCase();
    for (final rule in directoryRules) {
      if (rule.globs.any((glob) => glob.hasMatch(upperFileName))) {
        return rule.categoryId;
      }
    }
    return null;
  }

  void cacheDirectJunkMetadata(DiskTreeNode node) {
    if (node.isAggregate) return;
    var descendantJunkBytes = 0;
    var hasJunkChildren = false;
    for (final child in node.children) {
      descendantJunkBytes += child.junkBytes;
      if (child.isJunk || child.hasJunkChildren) hasJunkChildren = true;
    }
    node.cacheJunkMetadata(
      junkBytes: node.isJunk ? node.sizeBytes : descendantJunkBytes,
      hasJunkChildren: hasJunkChildren,
    );
  }

  void cacheJunkAggregates(DiskTreeNode node) {
    if (node.isAggregate) return;
    var descendantJunkBytes = 0;
    var hasJunkChildren = false;
    for (final child in node.children) {
      cacheJunkAggregates(child);
      descendantJunkBytes += child.junkBytes;
      if (child.isJunk || child.hasJunkChildren) hasJunkChildren = true;
    }
    node.cacheJunkMetadata(
      junkBytes: node.isJunk ? node.sizeBytes : descendantJunkBytes,
      hasJunkChildren: hasJunkChildren,
    );
  }

  var summarizedNodeCount = 0;
  var summarizedCleanableCount = 0;

  void summarizeTree(DiskTreeNode node) {
    summarizedNodeCount++;
    if (node.fullPath.isNotEmpty && node.isJunk) {
      summarizedCleanableCount++;
    }
    for (final child in node.children) {
      summarizeTree(child);
    }
  }

  void maybeFlush(String path) {
    final now = DateTime.now();
    if (now.difference(lastFlush).inMilliseconds >= 120) {
      lastFlush = now;
      sendPort.send(
        _ProgressMsg(
          dirs: totalDirs,
          files: totalFiles,
          bytes: totalBytes,
          currentPath: path,
          isIncremental: incrementalScan,
        ),
      );
    }
    // Send a bounded preview tree every ~1400ms so UI can expand/collapse what
    // has been scanned so far without copying the entire deep graph.
    final root = rootSnapshot;
    if (root != null && now.difference(lastTreeFlush).inMilliseconds >= 1400) {
      lastTreeFlush = now;
      sendPort.send(_TreeMsg(root: cloneDiskTreePreview(root)));
    }
  }

  /// Scans a directory using Win32 FindFirstFileExW/FindNextFileW.
  /// Mutates [node] with children as they are discovered so partial snapshots
  /// can be streamed while the scan is still running.
  void scanInto(
    DiskTreeNode node,
    int depth, [
    String? inheritedJunkCategory,
    bool replaceExisting = false,
  ]) {
    if (replaceExisting) {
      node.replaceChildren(const <DiskTreeNode>[]);
      node.sizeBytes = 0;
      node.fileCount = 0;
    }
    if (inheritedJunkCategory != null) {
      node.junkCategoryId = inheritedJunkCategory;
    }
    final dirPath = node.fullPath;
    final directoryGlobRules = inheritedJunkCategory == null
        ? globRulesForDirectory(dirPath)
        : null;
    totalDirs++;
    maybeFlush(dirPath);

    if (depth >= args.maxDepth) {
      coverageIssues.add(
        FullDiskScanCoverageIssue(
          path: dirPath,
          reason: FullDiskScanCoverageIssueReason.maxDepthReached,
          detail: 'Maximum scan depth ${args.maxDepth} reached.',
        ),
      );
      return;
    }

    // Prepare search pattern: "C:\path\*"
    final searchPath = dirPath.endsWith('\\') ? '$dirPath*' : '$dirPath\\*';
    final lpFileName = searchPath.toNativeUtf16();
    final findData = calloc<win32.WIN32_FIND_DATA>();
    // Keep only the largest individual file rows for this directory while it
    // is being enumerated. Directories are added immediately and are never
    // capped, so the completed tree contains every folder without retaining a
    // node for every small file in a large directory.
    final retainedFiles = <DiskTreeNode>[];
    var foldedFileBytes = 0;
    var foldedFileCount = 0;
    var foldedJunkBytes = 0;
    var foldedFileEntries = 0;

    void foldFile(DiskTreeNode file) {
      foldedFileBytes += file.sizeBytes;
      foldedFileCount += file.fileCount;
      foldedJunkBytes += file.junkBytes;
      foldedFileEntries += file.isAggregate ? file.aggregatedItemCount : 1;
    }

    void retainFile(DiskTreeNode file) {
      final maxFiles = args.maxChildrenPerDirectory;
      if (maxFiles <= 0) {
        foldFile(file);
        return;
      }

      // Keep the bounded list sorted from smallest to largest. This makes the
      // smallest retained file O(1) to inspect and avoids sorting a huge file
      // list after the directory has been enumerated.
      if (retainedFiles.length >= maxFiles &&
          file.sizeBytes <= retainedFiles.first.sizeBytes) {
        foldFile(file);
        return;
      }

      if (retainedFiles.length >= maxFiles) {
        foldFile(retainedFiles.removeAt(0));
      }
      var low = 0;
      var high = retainedFiles.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (retainedFiles[middle].sizeBytes <= file.sizeBytes) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      retainedFiles.insert(low, file);
    }

    try {
      final hFind = _findFirstFile(lpFileName, findData);
      if (!hFind.isValid) {
        inaccessible.add(dirPath);
        coverageIssues.add(
          FullDiskScanCoverageIssue(
            path: dirPath,
            reason: FullDiskScanCoverageIssueReason.inaccessible,
          ),
        );
        return;
      }

      try {
        do {
          final fileName = findData.ref.cFileName;
          // Skip . and ..
          if (fileName == '.' || fileName == '..') continue;

          final attrs = findData.ref.dwFileAttributes;

          final fullPath = dirPath.endsWith('\\')
              ? '$dirPath$fileName'
              : '$dirPath\\$fileName';

          // Skip reparse points (junctions/symlinks) to avoid infinite loops
          if (attrs & _fileAttributeReparsePoint != 0) {
            coverageIssues.add(
              FullDiskScanCoverageIssue(
                path: fullPath,
                reason: FullDiskScanCoverageIssueReason.reparsePoint,
              ),
            );
            continue;
          }

          final isDir = attrs & _fileAttributeDirectory != 0;

          if (isDir) {
            // Skip known system directories that cause issues
            if (fileName == '\$RECYCLE.BIN' ||
                fileName == 'System Volume Information' ||
                fileName == '\$WinREAgent') {
              continue;
            }
            // Keep the raw FILETIME parts while the child is scanned. DateTime
            // and insight objects are only allocated for folders that exceed
            // the old-large threshold.
            final lastWriteLow = findData.ref.ftLastWriteTime.dwLowDateTime;
            final lastWriteHigh = findData.ref.ftLastWriteTime.dwHighDateTime;
            final lastAccessLow = findData.ref.ftLastAccessTime.dwLowDateTime;
            final lastAccessHigh = findData.ref.ftLastAccessTime.dwHighDateTime;
            final childJunkCategory =
                inheritedJunkCategory ?? wholeDirCategory(fullPath);
            final child = DiskTreeNode(
              name: fileName,
              fullPath: fullPath,
              fileReferenceNumber:
                  collectDirectoryFileIds && canReadJournalChanges
                  ? DiskUsnJournalReader.readFileReferenceNumber(fullPath)
                  : null,
              junkCategoryId: childJunkCategory,
            );
            node.addChild(child);
            scanInto(child, depth + 1, childJunkCategory);
            node.sizeBytes += child.sizeBytes;
            node.fileCount += child.fileCount;
            if (child.sizeBytes >= defaultOldLargeDirectoryBytes) {
              retainOldLargeDiskInsight(
                oldLargeDirectories,
                FullDiskScanInsight(
                  name: fileName,
                  path: fullPath,
                  isFile: false,
                  sizeBytes: child.sizeBytes,
                  lastModified: _fileTimePartsToDateTime(
                    lastWriteLow,
                    lastWriteHigh,
                  ),
                  lastAccessed: _fileTimePartsToDateTime(
                    lastAccessLow,
                    lastAccessHigh,
                  ),
                ),
                now: scanStartedAt,
              );
            }
          } else {
            // File — extract size from high/low DWORDs
            final sizeHigh = findData.ref.nFileSizeHigh;
            final sizeLow = findData.ref.nFileSizeLow;
            final fileSize = (sizeHigh << 32) | sizeLow;
            if (fileSize >= defaultOldLargeFileBytes) {
              final lastModified = _fileTimeToDateTime(
                findData.ref.ftLastWriteTime,
              );
              final lastAccessed = _fileTimeToDateTime(
                findData.ref.ftLastAccessTime,
              );
              retainOldLargeDiskInsight(
                oldLargeFiles,
                FullDiskScanInsight(
                  name: fileName,
                  path: fullPath,
                  isFile: true,
                  sizeBytes: fileSize,
                  lastModified: lastModified,
                  lastAccessed: lastAccessed,
                ),
                now: scanStartedAt,
              );
            }
            // A whole-directory rule is inherited when entering the directory,
            // so files only need the glob rules already selected for this
            // directory. This avoids uppercasing full paths and walking every
            // Cleaner rule for every file on the drive.
            final fileJunkCategory =
                inheritedJunkCategory ??
                globCategory(fileName, directoryGlobRules);

            if (fileSize < args.minDisplayEntryBytes ||
                args.maxChildrenPerDirectory <= 0) {
              // Avoid allocating a temporary node for the common small-file
              // path. The aggregate keeps exact byte/file/junk totals.
              foldedFileBytes += fileSize;
              foldedFileCount++;
              if (fileJunkCategory != null) foldedJunkBytes += fileSize;
              foldedFileEntries++;
            } else {
              final file = DiskTreeNode(
                name: fileName,
                fullPath: fullPath,
                isFile: true,
                sizeBytes: fileSize,
                fileCount: 1,
                junkCategoryId: fileJunkCategory,
              );
              file.cacheJunkMetadata(
                junkBytes: fileJunkCategory == null ? 0 : fileSize,
                hasJunkChildren: false,
              );
              retainFile(file);
            }
            node.sizeBytes += fileSize;
            node.fileCount++;
            totalFiles++;
            totalBytes += fileSize;
          }
        } while (win32.FindNextFile(hFind, findData).value);
      } finally {
        win32.FindClose(hFind);
      }
    } catch (error) {
      inaccessible.add(dirPath);
      coverageIssues.add(
        FullDiskScanCoverageIssue(
          path: dirPath,
          reason: FullDiskScanCoverageIssueReason.inaccessible,
          detail: error.toString(),
        ),
      );
    } finally {
      calloc.free(findData);
      calloc.free(lpFileName);
      for (final file in retainedFiles) {
        node.addChild(file);
      }
      if (foldedFileEntries > 0) {
        final aggregate = DiskTreeNode(
          name: '',
          fullPath: '',
          isFile: true,
          sizeBytes: foldedFileBytes,
          fileCount: foldedFileCount,
          aggregatedItemCount: foldedFileEntries,
        );
        aggregate.cacheJunkMetadata(
          junkBytes: foldedJunkBytes,
          hasJunkChildren: foldedJunkBytes > 0,
        );
        node.addChild(aggregate);
      }
      // Children are sorted only after the bounded file set is complete. This
      // avoids repeated sorting while FindNextFile is still producing rows.
      node.sortBySize(recursive: false);
      cacheDirectJunkMetadata(node);
    }
  }

  final driveName = args.drivePath.endsWith('\\')
      ? args.drivePath
      : '${args.drivePath}\\';
  FullDiskScanMode scanMode = FullDiskScanMode.full;
  var changedDirectoryCount = 0;
  String? incrementalFallbackReason;
  DiskScanJournalCursor? nextJournalCursor;
  late DiskTreeNode root;

  void recalculateDirectory(DiskTreeNode node) {
    if (node.isFile) return;
    var bytes = 0;
    var files = 0;
    for (final child in node.children) {
      bytes += child.sizeBytes;
      files += child.fileCount;
    }
    node.sizeBytes = bytes;
    node.fileCount = files;
    cacheDirectJunkMetadata(node);
  }

  final incrementalRequested =
      args.baseRoot != null &&
      (args.journalCursor != null || args.hasTrackedChanges);
  if (incrementalRequested) {
    root = args.baseRoot!;
    rootSnapshot = root;

    // Build the path and parent indexes once. The previous implementation
    // walked the entire cached tree once to resolve every dirty path and then
    // walked it again to rebuild each ancestor chain. Dirty paths are pruned
    // to their shallowest ancestor below, so these indexes stay valid while
    // each selected subtree is refreshed in place.
    final directoryByPath = <String, DiskTreeNode>{};
    final parentByPath = <String, DiskTreeNode?>{};
    final directoryPathsById = <int, String>{};
    final directoryStack = <DiskTreeNode>[root];
    final parentStack = <DiskTreeNode?>[null];
    while (directoryStack.isNotEmpty) {
      final node = directoryStack.removeLast();
      final parent = parentStack.removeLast();
      final key = _normalizeComparableWindowsPath(node.fullPath);
      directoryByPath[key] = node;
      parentByPath[key] = parent;
      if (node.fileReferenceNumber != null) {
        directoryPathsById[node.fileReferenceNumber!] = node.fullPath;
      }
      for (final child in node.children) {
        if (!child.isFile) {
          directoryStack.add(child);
          parentStack.add(node);
        }
      }
    }

    final dirtyCandidates = <String>{};
    if (args.journalCursor != null && canReadJournalChanges) {
      final journal = DiskUsnJournalReader.readChanges(
        drivePath: args.drivePath,
        previous: args.journalCursor!,
      );
      if (!journal.isUsable || journal.cursor == null) {
        incrementalFallbackReason = journal.failureReason;
      } else {
        nextJournalCursor = journal.cursor;
        for (final change in journal.changes) {
          final parentPath =
              directoryPathsById[change.parentFileReferenceNumber];
          if (parentPath == null) {
            incrementalFallbackReason =
                'The cached tree has no file ID for a changed directory; '
                'a complete scan is required.';
            break;
          }
          dirtyCandidates.add(parentPath);
        }
      }
    } else if (args.journalCursor != null) {
      incrementalFallbackReason =
          'The NTFS USN Journal cannot be read by this process.';
    } else {
      dirtyCandidates.addAll(args.trackedDirtyDirectories);
    }

    if (incrementalFallbackReason == null) {
      final sortedCandidates = dirtyCandidates.toList()
        ..sort((a, b) => a.length.compareTo(b.length));
      final dirtyDirectories = <String>[];
      for (final candidate in sortedCandidates) {
        if (!dirtyDirectories.any(
          (ancestor) => _isWindowsPathWithin(candidate, ancestor),
        )) {
          dirtyDirectories.add(candidate);
        }
      }

      incrementalScan = true;
      scanMode = FullDiskScanMode.incremental;
      changedDirectoryCount = dirtyDirectories.length;
      sendPort.send(
        const _ProgressMsg(
          dirs: 0,
          files: 0,
          bytes: 0,
          currentPath: '',
          isIncremental: true,
        ),
      );

      for (final insight in args.baseOldLargeItems) {
        if (!isOldLargeInsightInvalidatedByDirtyDirectories(
          insight,
          dirtyDirectories,
        )) {
          retainOldLargeDiskInsight(
            insight.isFile ? oldLargeFiles : oldLargeDirectories,
            insight,
            now: scanStartedAt,
          );
        }
      }

      for (final dirtyPath in dirtyDirectories) {
        final key = _normalizeComparableWindowsPath(dirtyPath);
        final target = directoryByPath[key];
        if (target == null) {
          incrementalFallbackReason =
              'A changed directory could not be resolved in the cached tree.';
          incrementalScan = false;
          scanMode = FullDiskScanMode.full;
          break;
        }
        final chain = <DiskTreeNode>[];
        DiskTreeNode? current = target;
        while (current != null) {
          chain.add(current);
          current =
              parentByPath[_normalizeComparableWindowsPath(current.fullPath)];
        }
        final depth = chain.length - 1;
        scanInto(target, depth, target.junkCategoryId, true);
        for (var index = 1; index < chain.length; index++) {
          recalculateDirectory(chain[index]);
        }
      }
    }
  }

  if (!incrementalScan) {
    oldLargeFiles.clear();
    oldLargeDirectories.clear();
    inaccessible.clear();
    coverageIssues.clear();
    changedDirectoryCount = 0;
    root = DiskTreeNode(name: driveName, fullPath: driveName);
    rootSnapshot = root;
    // Every directory is sorted and its file tail is folded by `scanInto` as
    // it completes. All directory nodes remain in the final tree, while the
    // large file tail never has to cross the isolate boundary.
    scanInto(root, 0);
    nextJournalCursor = canReadJournalChanges
        ? DiskUsnJournalReader.readCursor(args.drivePath)
        : null;
  }

  // A full scan caches each directory bottom-up inside scanInto. Rebuilding
  // every aggregate is only necessary after an incremental subtree refresh.
  if (args.junkRules.isNotEmpty &&
      incrementalScan &&
      changedDirectoryCount > 0) {
    cacheJunkAggregates(root);
  }
  summarizeTree(root);
  final cleanableCount = args.junkRules.isEmpty ? 0 : summarizedCleanableCount;
  final oldLargeItems = buildBoundedOldLargeDiskEvidence(
    folders: oldLargeDirectories,
    files: oldLargeFiles,
  );

  _sendFinalTreeBatches(
    sendPort: sendPort,
    root: root,
    batchSize: args.finalTreeBatchSize,
    nodeCount: summarizedNodeCount,
    junkBytes: root.junkBytes,
    cleanableCount: cleanableCount,
    inaccessible: inaccessible,
    coverageIssues: coverageIssues,
    oldLargeItems: oldLargeItems,
    scanMode: scanMode,
    changedDirectoryCount: changedDirectoryCount,
    journalCursor: nextJournalCursor,
    incrementalFallbackReason: incrementalFallbackReason,
  );
}

/// Sends the completed tree as acknowledged preorder batches.
///
/// A single graph message makes the receiving isolate copy the entire tree in
/// one event-loop turn. Keeping only a bounded batch in each message lets the
/// UI isolate interleave reconstruction with other work. The worker waits for
/// the acknowledgement before producing the next batch, so the receive port
/// cannot accumulate an unbounded queue of final-tree payloads.
void _sendFinalTreeBatches({
  required SendPort sendPort,
  required DiskTreeNode root,
  required int batchSize,
  required int nodeCount,
  required int junkBytes,
  required int cleanableCount,
  required List<String> inaccessible,
  required List<FullDiskScanCoverageIssue> coverageIssues,
  required List<FullDiskScanInsight> oldLargeItems,
  required FullDiskScanMode scanMode,
  required int changedDirectoryCount,
  required DiskScanJournalCursor? journalCursor,
  required String? incrementalFallbackReason,
}) {
  final effectiveBatchSize = batchSize < 1 ? 1 : batchSize;
  final acknowledgements = ReceivePort();
  final pending = <_FinalTreeVisit>[_FinalTreeVisit(node: root, depth: 0)];
  var nextBatchIndex = 0;
  var awaitingBatchIndex = -1;

  void sendNextBatch() {
    if (pending.isEmpty) {
      acknowledgements.close();
      sendPort.send(
        _DoneMsg(
          nodeCount: nodeCount,
          junkBytes: junkBytes,
          cleanableCount: cleanableCount,
          inaccessible: inaccessible,
          coverageIssues: coverageIssues,
          oldLargeItems: oldLargeItems,
          scanMode: scanMode,
          changedDirectoryCount: changedDirectoryCount,
          journalCursor: journalCursor,
          incrementalFallbackReason: incrementalFallbackReason,
        ),
      );
      return;
    }

    final records = <_FinalTreeNodeRecord>[];
    while (pending.isNotEmpty && records.length < effectiveBatchSize) {
      final visit = pending.removeLast();
      records.add(
        _FinalTreeNodeRecord.fromNode(visit.node, depth: visit.depth),
      );
      final children = visit.node.children;
      for (var index = children.length - 1; index >= 0; index--) {
        pending.add(
          _FinalTreeVisit(node: children[index], depth: visit.depth + 1),
        );
      }
    }

    final batchIndex = nextBatchIndex++;
    awaitingBatchIndex = batchIndex;
    sendPort.send(
      _FinalTreeBatchMsg(
        index: batchIndex,
        records: records,
        ackPort: acknowledgements.sendPort,
      ),
    );
  }

  acknowledgements.listen((dynamic message) {
    if (message is! _FinalTreeBatchAck || message.index != awaitingBatchIndex) {
      return;
    }
    awaitingBatchIndex = -1;
    sendNextBatch();
  });
  sendNextBatch();
}

// ---------------------------------------------------------------------------
// Display compaction
// ---------------------------------------------------------------------------

/// Collapses the entries the UI can never usefully show into roll-up rows.
///
/// Two rules apply per directory: entries totalling less than [minEntryBytes]
/// are folded, and anything past [maxChildren] survivors is folded. Whatever is
/// folded becomes a single synthetic child carrying the exact summed bytes and
/// file count, which keeps every parent total — and any later recalculation
/// from children — correct.
///
/// Folded subtrees become garbage here in the scan isolate rather than being
/// copied into the UI isolate, which is the point: the copy is what used to
/// freeze the app and leave its heap permanently inflated.
void pruneTreeForDisplay(
  DiskTreeNode node, {
  required int minEntryBytes,
  required int maxChildren,
}) {
  foldDirectoryForDisplay(
    node,
    minEntryBytes: minEntryBytes,
    maxChildren: maxChildren,
  );
  for (final child in node.children) {
    pruneTreeForDisplay(
      child,
      minEntryBytes: minEntryBytes,
      maxChildren: maxChildren,
    );
  }
}

/// Sorts and folds one directory level, leaving descendants alone.
///
/// Folder rows are always retained. Only direct file rows below the display
/// threshold or beyond the per-directory file cap are folded, which preserves
/// a complete folder inventory without shipping every file leaf to the UI.
void foldDirectoryForDisplay(
  DiskTreeNode node, {
  required int minEntryBytes,
  required int maxChildren,
}) {
  final children = node.children;
  if (children.isEmpty) return;

  // Fold decisions depend on rank by size, so order first.
  node.sortBySize(recursive: false);

  final kept = <DiskTreeNode>[];
  var keptFileCount = 0;
  var foldedBytes = 0;
  var foldedFiles = 0;
  var foldedJunkBytes = 0;
  var foldedEntries = 0;

  for (final child in children) {
    final isFile = child.isFile;
    final tooSmall = isFile && child.sizeBytes < minEntryBytes;
    final beyondCap = isFile && keptFileCount >= maxChildren;
    if (tooSmall || beyondCap) {
      foldedBytes += child.sizeBytes;
      foldedFiles += child.fileCount;
      foldedJunkBytes += child.junkBytes;
      foldedEntries += child.isAggregate ? child.aggregatedItemCount : 1;
      continue;
    }
    kept.add(child);
    if (isFile) keptFileCount++;
  }

  if (foldedEntries == 0) return;

  // An empty fullPath is the established marker for "not a real target": every
  // selection, junk and deletion helper already skips such nodes, so a roll-up
  // row can never be checked for deletion.
  final aggregate = DiskTreeNode(
    name: '',
    fullPath: '',
    isFile: true,
    sizeBytes: foldedBytes,
    fileCount: foldedFiles,
    aggregatedItemCount: foldedEntries,
  );
  aggregate.cacheJunkMetadata(
    junkBytes: foldedJunkBytes,
    hasJunkChildren: foldedJunkBytes > 0,
  );
  kept.add(aggregate);
  node.replaceChildren(kept);

  // A roll-up can outweigh entries that were kept on their own merit, and the
  // percent-of-parent column and the pie's top-10 both read this order.
  node.sortBySize(recursive: false);
}

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

class _FullScanArgs {
  final SendPort sendPort;
  final String drivePath;
  final int maxDepth;
  final int minDisplayEntryBytes;
  final int maxChildrenPerDirectory;
  final int finalTreeBatchSize;
  final List<FullDiskJunkRule> junkRules;
  final DiskTreeNode? baseRoot;
  final DiskScanJournalCursor? journalCursor;
  final List<FullDiskScanInsight> baseOldLargeItems;
  final List<String> trackedDirtyDirectories;
  final bool hasTrackedChanges;
  const _FullScanArgs({
    required this.sendPort,
    required this.drivePath,
    this.maxDepth = 20,
    this.minDisplayEntryBytes = defaultMinDisplayEntryBytes,
    this.maxChildrenPerDirectory = defaultMaxChildrenPerDirectory,
    this.finalTreeBatchSize = defaultFinalTreeBatchSize,
    this.junkRules = const <FullDiskJunkRule>[],
    this.baseRoot,
    this.journalCursor,
    this.baseOldLargeItems = const <FullDiskScanInsight>[],
    this.trackedDirtyDirectories = const <String>[],
    this.hasTrackedChanges = false,
  });
}

class _WorkerWholeDirRule {
  final String path;
  final String prefix;
  final String categoryId;

  const _WorkerWholeDirRule({
    required this.path,
    required this.prefix,
    required this.categoryId,
  });
}

class _WorkerGlobRule {
  final String basePath;
  final String categoryId;
  final List<RegExp> globs;

  const _WorkerGlobRule({
    required this.basePath,
    required this.categoryId,
    required this.globs,
  });
}

class _ProgressMsg {
  final int dirs;
  final int files;
  final int bytes;
  final String currentPath;
  final bool isIncremental;
  const _ProgressMsg({
    required this.dirs,
    required this.files,
    required this.bytes,
    required this.currentPath,
    this.isIncremental = false,
  });
}

class _TreeMsg {
  final DiskTreeNode root;
  const _TreeMsg({required this.root});
}

class _FinalTreeVisit {
  final DiskTreeNode node;
  final int depth;

  const _FinalTreeVisit({required this.node, required this.depth});
}

/// Flat preorder representation of one [DiskTreeNode].
///
/// The depth links this record to its parent while preserving child order,
/// avoiding a large id-to-node map in the receiving isolate. Junk aggregates
/// are copied explicitly because they are otherwise private fields on
/// [DiskTreeNode].
class _FinalTreeNodeRecord {
  final int depth;
  final String name;
  final String fullPath;
  final bool isFile;
  final int sizeBytes;
  final int fileCount;
  final int? fileReferenceNumber;
  final String? junkCategoryId;
  final bool isSelectedForDeletion;
  final bool isExpanded;
  final int aggregatedItemCount;
  final int junkBytes;
  final bool hasJunkChildren;

  const _FinalTreeNodeRecord({
    required this.depth,
    required this.name,
    required this.fullPath,
    required this.isFile,
    required this.sizeBytes,
    required this.fileCount,
    required this.fileReferenceNumber,
    required this.junkCategoryId,
    required this.isSelectedForDeletion,
    required this.isExpanded,
    required this.aggregatedItemCount,
    required this.junkBytes,
    required this.hasJunkChildren,
  });

  factory _FinalTreeNodeRecord.fromNode(
    DiskTreeNode node, {
    required int depth,
  }) {
    return _FinalTreeNodeRecord(
      depth: depth,
      name: node.name,
      fullPath: node.fullPath,
      isFile: node.isFile,
      sizeBytes: node.sizeBytes,
      fileCount: node.fileCount,
      fileReferenceNumber: node.fileReferenceNumber,
      junkCategoryId: node.junkCategoryId,
      isSelectedForDeletion: node.isSelectedForDeletion,
      isExpanded: node.isExpanded,
      aggregatedItemCount: node.aggregatedItemCount,
      junkBytes: node.junkBytes,
      hasJunkChildren: node.hasJunkChildren,
    );
  }

  DiskTreeNode toNode() {
    final node = DiskTreeNode(
      name: name,
      fullPath: fullPath,
      isFile: isFile,
      sizeBytes: sizeBytes,
      fileCount: fileCount,
      fileReferenceNumber: fileReferenceNumber,
      junkCategoryId: junkCategoryId,
      isSelectedForDeletion: isSelectedForDeletion,
      isExpanded: isExpanded,
      aggregatedItemCount: aggregatedItemCount,
    );
    node.cacheJunkMetadata(
      junkBytes: junkBytes,
      hasJunkChildren: hasJunkChildren,
    );
    return node;
  }
}

class _FinalTreeBatchMsg {
  final int index;
  final List<_FinalTreeNodeRecord> records;
  final SendPort ackPort;

  const _FinalTreeBatchMsg({
    required this.index,
    required this.records,
    required this.ackPort,
  });
}

class _FinalTreeBatchAck {
  final int index;

  const _FinalTreeBatchAck(this.index);
}

class _FinalTreeAssembler {
  DiskTreeNode? _root;
  final _ancestors = <DiskTreeNode>[];
  int? _lastBatchIndex;
  int _nodeCount = 0;

  int get nodeCount => _nodeCount;

  DiskTreeNode get root =>
      _root ??
      (throw StateError(
        'The final disk scan tree was not reconstructed before completion.',
      ));

  void addBatch({
    required int index,
    required List<_FinalTreeNodeRecord> records,
  }) {
    final previousIndex = _lastBatchIndex;
    if (previousIndex != null && index <= previousIndex) {
      throw StateError(
        'The final disk scan batch index $index is not greater than '
        'the previous index $previousIndex.',
      );
    }
    if (records.isEmpty) {
      throw StateError('The final disk scan sent an empty batch.');
    }
    _lastBatchIndex = index;

    for (final record in records) {
      if (record.depth < 0) {
        throw StateError('The final disk scan sent a negative node depth.');
      }
      final node = record.toNode();
      if (record.depth == 0) {
        if (_root != null) {
          throw StateError('The final disk scan sent more than one root.');
        }
        _root = node;
        _ancestors
          ..clear()
          ..add(node);
        _nodeCount++;
        continue;
      }

      if (record.depth > _ancestors.length) {
        throw StateError('The final disk scan sent a node without its parent.');
      }
      if (_ancestors.length > record.depth) {
        _ancestors.length = record.depth;
      }
      final parent = _ancestors[record.depth - 1];
      parent.addChild(node);
      _ancestors.add(node);
      _nodeCount++;
    }
  }
}

class _DoneMsg {
  final int nodeCount;
  final int junkBytes;
  final int cleanableCount;
  final List<String> inaccessible;
  final List<FullDiskScanCoverageIssue> coverageIssues;
  final List<FullDiskScanInsight> oldLargeItems;
  final FullDiskScanMode scanMode;
  final int changedDirectoryCount;
  final DiskScanJournalCursor? journalCursor;
  final String? incrementalFallbackReason;
  const _DoneMsg({
    required this.nodeCount,
    required this.junkBytes,
    required this.cleanableCount,
    required this.inaccessible,
    required this.coverageIssues,
    required this.oldLargeItems,
    required this.scanMode,
    required this.changedDirectoryCount,
    required this.journalCursor,
    required this.incrementalFallbackReason,
  });
}

/// Total nodes in [root]'s subtree, including [root].
int countNodes(DiskTreeNode root) {
  var total = 0;
  final stack = <DiskTreeNode>[root];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    total++;
    stack.addAll(node.children);
  }
  return total;
}

int countNodesUpTo(DiskTreeNode root, int limit) {
  if (limit <= 0) return limit;
  var total = 0;
  final stack = <DiskTreeNode>[root];
  while (stack.isNotEmpty && total <= limit) {
    final node = stack.removeLast();
    total++;
    if (total > limit) return total;
    stack.addAll(node.children);
  }
  return total;
}

/// Keeps the final cross-isolate payload bounded even when a drive has many
/// large directories that survive the per-directory pruning threshold.
///
/// The largest branches are retained because the scan tree is already sorted
/// by size. Dropped branches become non-actionable roll-up rows, preserving
/// their byte/file totals and precomputed junk bytes.
void trimTreeToNodeBudget(DiskTreeNode node, {required int maxNodes}) {
  if (maxNodes < 1) return;

  int trim(DiskTreeNode current, int budget) {
    if (current.isFile || current.children.isEmpty) return 1;
    if (budget <= 1) {
      _collapseChildrenWithoutRow(current);
      return 1;
    }

    var used = 1;
    final kept = <DiskTreeNode>[];
    final folded = <DiskTreeNode>[];
    for (final child in current.children) {
      // Reserve one slot for a roll-up whenever this level overflows.
      final remaining = budget - used - 1;
      if (remaining <= 0) {
        folded.add(child);
        continue;
      }
      final childCount = countNodesUpTo(child, remaining);
      if (childCount <= remaining) {
        kept.add(child);
        used += childCount;
        continue;
      }

      if (child.isFile) {
        folded.add(child);
        continue;
      }
      final childUsed = trim(child, remaining);
      kept.add(child);
      used += childUsed;
    }

    if (folded.isNotEmpty) {
      _replaceWithAggregate(current, folded, kept: kept);
      used++;
    } else if (kept.length != current.children.length) {
      current.replaceChildren(kept);
    }
    return used;
  }

  trim(node, maxNodes);
}

void _collapseChildrenWithoutRow(DiskTreeNode node) {
  var junkBytes = 0;
  var hasJunkChildren = false;
  for (final child in node.children) {
    junkBytes += child.junkBytes;
    if (child.isJunk || child.hasJunkChildren) hasJunkChildren = true;
  }
  node.replaceChildren(const <DiskTreeNode>[]);
  node.cacheJunkMetadata(
    junkBytes: node.isJunk ? node.sizeBytes : junkBytes,
    hasJunkChildren: hasJunkChildren,
  );
}

void _replaceWithAggregate(
  DiskTreeNode node,
  Iterable<DiskTreeNode> folded, {
  List<DiskTreeNode>? kept,
}) {
  final foldedList = folded.toList(growable: false);
  if (foldedList.isEmpty) return;
  var foldedBytes = 0;
  var foldedFiles = 0;
  var foldedJunkBytes = 0;
  var foldedEntries = 0;
  for (final child in foldedList) {
    foldedBytes += child.sizeBytes;
    foldedFiles += child.fileCount;
    foldedJunkBytes += child.junkBytes;
    foldedEntries += child.isAggregate ? child.aggregatedItemCount : 1;
  }
  final aggregate = DiskTreeNode(
    name: '',
    fullPath: '',
    isFile: true,
    sizeBytes: foldedBytes,
    fileCount: foldedFiles,
    aggregatedItemCount: foldedEntries,
  );
  aggregate.cacheJunkMetadata(
    junkBytes: foldedJunkBytes,
    hasJunkChildren: foldedJunkBytes > 0,
  );
  final next = <DiskTreeNode>[...(kept ?? const <DiskTreeNode>[]), aggregate];
  node.replaceChildren(next);
  node.sortBySize(recursive: false);
}

RegExp _globToRegex(String glob) {
  final buffer = StringBuffer('^');
  for (final ch in glob.split('')) {
    switch (ch) {
      case '*':
        buffer.write('.*');
        break;
      case '?':
        buffer.write('.');
        break;
      case '.':
      case '(':
      case ')':
      case '[':
      case ']':
      case '{':
      case '}':
      case r'\':
      case '+':
      case '|':
      case '^':
      case r'$':
        buffer.write(r'\');
        buffer.write(ch);
        break;
      default:
        buffer.write(ch);
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString(), caseSensitive: false);
}
