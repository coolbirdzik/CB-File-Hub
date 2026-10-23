import 'dart:async';
import 'dart:isolate';

import 'disk_tree_node.dart';
import 'cleaner_categories.dart';
import 'cleaner_models.dart';
import 'cleaner_space_insights.dart';
import 'cleaner_paths.dart';

enum CleanerItemDecision { clean, review, keep }

class CleanerItemAnalysis {
  final CleanerItemDecision decision;
  final String reason;
  final bool selectForCleanup;
  final bool fromScan;

  const CleanerItemAnalysis({
    required this.decision,
    required this.reason,
    this.selectForCleanup = false,
    this.fromScan = false,
  });
}

class CleanerReviewedItem {
  final DiskTreeNode node;
  final CleanerItemAnalysis analysis;
  final int coveredItems;

  const CleanerReviewedItem({
    required this.node,
    required this.analysis,
    this.coveredItems = 1,
  });
}

class CleanerItemInteractionResult {
  final DiskTreeNode? node;
  final String? scanId;
  final String? error;

  /// The requested path when [node] was found by correcting a near miss.
  final String? correctedFrom;

  const CleanerItemInteractionResult({
    this.node,
    this.scanId,
    this.error,
    this.correctedFrom,
  });
}

typedef _ReviewEntry = ({
  String path,
  String name,
  bool isFile,
  bool hasChildren,
  String? categoryId,
  int parent,
  bool pending,
});

typedef _ReviewSnapshot = ({
  List<_ReviewEntry> entries,
  List<DiskTreeNode> nodes,
  Map<DiskTreeNode, DiskTreeNode> directoryParents,
});

class _ReviewGroupPlan {
  final String id;
  final String scope;
  final String? categoryId;
  final String? causeId;
  final String type;
  final List<int> members = [];

  _ReviewGroupPlan({
    required this.id,
    required this.scope,
    required this.categoryId,
    required this.causeId,
    required this.type,
  });
}

List<_ReviewGroupPlan> _buildReviewPlans(List<_ReviewEntry> entries) {
  final byKey = <String, _ReviewGroupPlan>{};
  final causes = <CleanerSpaceCause?>[];
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final cause =
        CleanerSpaceInsights.causeForPath(entry.path, isFile: entry.isFile) ??
        (entry.parent < 0 ? null : causes[entry.parent]);
    causes.add(cause);
    if (!entry.pending) continue;
    final posix = CleanerPaths.isPosix(entry.path);
    final parts = posix
        ? CleanerPaths.key(entry.path).split('/')
        : entry.path.replaceAll('/', r'\').split(r'\');
    final depth = parts.length > 2 && parts[1].toUpperCase() == 'USERS' ? 4 : 3;
    final scope = parts
        .take(entry.isFile ? (parts.length - 1).clamp(1, depth) : depth)
        .join(posix ? '/' : r'\');
    final type = entry.isFile
        ? CleanerSpaceInsights.groupOfExtension(
                CleanerSpaceInsights.extensionOf(entry.name),
              ) ??
              'other_files'
        : entry.hasChildren
        ? 'folder'
        : 'empty_folder';
    final key =
        '${CleanerPaths.isPosix(entry.path) ? scope : scope.toUpperCase()}|${entry.categoryId}|${cause?.id}|$type';
    final group = byKey.putIfAbsent(
      key,
      () => _ReviewGroupPlan(
        id: 'group_${byKey.length}',
        scope: scope,
        categoryId: entry.categoryId,
        causeId: cause?.id,
        type: type,
      ),
    );
    group.members.add(index);
  }
  return byKey.values.toList();
}

void _reviewPlanWorker((SendPort, List<_ReviewEntry>) args) {
  Isolate.exit(args.$1, _buildReviewPlans(args.$2));
}

Future<List<_ReviewGroupPlan>> _reviewPlansInWorker(
  List<_ReviewEntry> entries,
  void Function() checkActive,
) async {
  checkActive();
  final port = ReceivePort();
  final done = Completer<List<_ReviewGroupPlan>>();
  final subscription = port.listen((message) {
    if (done.isCompleted) return;
    if (message is List<_ReviewGroupPlan>) {
      done.complete(message);
    } else {
      done.completeError(
        StateError('Cleaner grouping worker failed: $message'),
      );
    }
  });
  Isolate? worker;
  Timer? cancellation;
  try {
    worker = await Isolate.spawn(
      _reviewPlanWorker,
      (port.sendPort, entries),
      onError: port.sendPort,
      onExit: port.sendPort,
      debugName: 'Cleaner quick review',
    );
    cancellation = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (done.isCompleted) return;
      try {
        checkActive();
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return await done.future;
  } finally {
    cancellation?.cancel();
    worker?.kill(priority: Isolate.immediate);
    await subscription.cancel();
    port.close();
  }
}

/// Exhaustive work queue for one immutable, completed scan tree. A folder's
/// verdict never counts as a verdict for its descendants.
class CleanerFullReview {
  final DiskTreeNode root;
  Map<String, DiskTreeNode> _pending = {};
  int total = 0;
  bool _indexReady = true;
  int aggregatedItems = 0;
  final List<CleanerReviewGroup> groups = [];

  /// Started as a full AI review; only such a run resumes it as one.
  bool aiAllGroups = false;
  Map<String, CleanerReviewGroup> _groupsByPath = {};
  Map<DiskTreeNode, DiskTreeNode> _directoryParents = {};

  CleanerFullReview(this.root) {
    final stack = root.children.reversed.toList();
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node.isAggregate) {
        aggregatedItems += node.aggregatedItemCount;
      } else if (node.fullPath.isNotEmpty) {
        _pending[node.fullPath] = node;
      }
      stack.addAll(node.children.reversed);
    }
    total = _pending.length;
  }

  /// Start a UI-driven review without walking the disk tree in the click
  /// handler. [prepareGroups] builds the index in cancellable time slices.
  CleanerFullReview.deferred(this.root) : _indexReady = false;

  int get reviewed => total - _pending.length;
  int get remaining => _pending.length;
  int get unresolvedGroupCount => groups
      .where((group) => group.usedFallback && group.nodes.any(containsPending))
      .length;
  int get unresolvedItems => groups
      .where((group) => group.usedFallback)
      .fold(0, (sum, group) => sum + group.nodes.where(containsPending).length);
  bool get isComplete => _indexReady && _pending.isEmpty;
  DiskTreeNode? get next => _pending.values.firstOrNull;
  CleanerItemAnalysis? analysisForPath(String path) =>
      _groupsByPath[path]?.analysis;
  bool containsPending(DiskTreeNode node) =>
      identical(_pending[node.fullPath], node);
  bool ownsGroup(CleanerReviewGroup group) =>
      identical(_groupsByPath[group.representative.fullPath], group);
  DiskTreeNode? pendingNodeForPath(String path) => _pending[path];
  CleanerReviewGroup? groupForPath(String path) => _groupsByPath[path];

  Future<_ReviewSnapshot> _snapshot(void Function() checkActive) async {
    final pending = _indexReady ? _pending : <String, DiskTreeNode>{};
    final nodes = <DiskTreeNode>[];
    final entries = <_ReviewEntry>[];
    final directoryParents = <DiskTreeNode, DiskTreeNode>{};
    var aggregated = 0;
    final stack = [(root.children.iterator, root, -1)];
    final slice = Stopwatch()..start();
    var visited = 0;
    while (stack.isNotEmpty) {
      final (iterator, parent, parentIndex) = stack.last;
      if (!iterator.moveNext()) {
        stack.removeLast();
        continue;
      }
      final node = iterator.current;
      final index = nodes.length;
      nodes.add(node);
      if (!node.isFile) directoryParents[node] = parent;
      if (!_indexReady) {
        if (node.isAggregate) {
          aggregated += node.aggregatedItemCount;
        } else if (node.fullPath.isNotEmpty) {
          pending[node.fullPath] = node;
        }
      }
      entries.add((
        path: node.fullPath,
        name: node.name,
        isFile: node.isFile,
        hasChildren: node.children.isNotEmpty,
        categoryId: node.junkCategoryId,
        parent: parentIndex,
        pending: identical(pending[node.fullPath], node),
      ));
      if (node.children.isNotEmpty) {
        stack.add((node.children.iterator, node, index));
      }
      if (++visited % 128 == 0 && slice.elapsedMilliseconds >= 4) {
        await Future<void>.delayed(Duration.zero);
        checkActive();
        slice.reset();
      }
    }
    checkActive();
    if (!_indexReady) {
      _pending = pending;
      total = pending.length;
      aggregatedItems = aggregated;
      _indexReady = true;
    }
    return (entries: entries, nodes: nodes, directoryParents: directoryParents);
  }

  DiskTreeNode? parentOf(DiskTreeNode node) {
    final directoryParent = _directoryParents[node];
    if (directoryParent != null) return directoryParent;
    final group = _groupsByPath[node.fullPath];
    return group != null && identical(group.representative, node)
        ? group.representativeParent
        : null;
  }

  List<DiskTreeNode>? ancestorsOf(DiskTreeNode node) {
    if (identical(node, root)) return const [];
    var parent = parentOf(node);
    if (parent == null) return null;
    final result = <DiskTreeNode>[];
    while (parent != null) {
      result.add(parent);
      if (identical(parent, root)) return result;
      parent = _directoryParents[parent];
    }
    return null;
  }

  /// Snapshot and bind original rows in short slices. Path classification and
  /// grouping run off the UI isolate; copied worker rows never become targets.
  Future<void> prepareGroups({required void Function() checkActive}) async {
    checkActive();
    if (groups.isNotEmpty || isComplete) return;
    final snapshot = await _snapshot(checkActive);
    final plans = snapshot.entries.length <= 128
        ? _buildReviewPlans(snapshot.entries)
        : await _reviewPlansInWorker(snapshot.entries, checkActive);
    checkActive();
    final prepared = <CleanerReviewGroup>[];
    final groupsByPath = <String, CleanerReviewGroup>{};
    final causes = {
      for (final cause in CleanerSpaceInsights.causes) cause.id: cause,
    };
    final slice = Stopwatch()..start();
    var visited = 0;
    for (final plan in plans) {
      final group = CleanerReviewGroup(
        id: plan.id,
        scope: plan.scope,
        categoryId: plan.categoryId,
        cause: causes[plan.causeId],
        type: plan.type,
      );
      for (final index in plan.members) {
        final node = snapshot.nodes[index];
        if (!containsPending(node)) continue;
        final parentIndex = snapshot.entries[index].parent;
        final parent = parentIndex < 0 ? root : snapshot.nodes[parentIndex];
        group.add(node, parent: parent);
        groupsByPath[node.fullPath] = group;
        if (++visited % 128 == 0 && slice.elapsedMilliseconds >= 4) {
          await Future<void>.delayed(Duration.zero);
          checkActive();
          slice.reset();
        }
      }
      if (group.nodes.isNotEmpty) prepared.add(group);
    }
    checkActive();
    groups.addAll(prepared);
    _directoryParents = snapshot.directoryParents;
    _groupsByPath = groupsByPath;
  }

  void markGroupReviewed(
    CleanerReviewGroup group,
    CleanerItemAnalysis analysis, {
    bool fallback = false,
  }) {
    group.analysis = analysis;
    group.usedFallback = fallback;
    group.fallbackPendingReconciled = true;
    // A failed model response is a visible warning, not an accepted assessment.
    // Keep its exact members pending so Retry resumes only unresolved work.
    if (fallback) return;
    for (final node in group.nodes) {
      markReviewed(node);
    }
  }

  /// Upgrade a live session created by the earlier counter, which removed
  /// fallback members from its queue. Current failures are already pending.
  void reconcileFallbacks() {
    for (final group in groups) {
      if (!group.usedFallback || group.fallbackPendingReconciled) continue;
      for (final node in group.nodes) {
        _pending[node.fullPath] = node;
      }
      group.fallbackPendingReconciled = true;
    }
  }

  void markReviewed(DiskTreeNode node) {
    if (identical(_pending[node.fullPath], node)) {
      _pending.remove(node.fullPath);
    }
  }
}

/// One explicit assessment of a homogeneous evidence group. Member files were
/// classified from the scan, not individually read or sent to the model.
class CleanerReviewGroup {
  final String id;
  final String scope;
  final String? categoryId;
  final CleanerSpaceCause? cause;
  final String type;
  final List<DiskTreeNode> nodes = [];
  final List<DiskTreeNode> examples = [];
  int fileBytes = 0;
  int largestFolderBytes = 0;
  CleanerItemAnalysis? analysis;
  bool usedFallback = false;
  bool fallbackPendingReconciled = false;
  DiskTreeNode? representativeParent;

  CleanerReviewGroup({
    required this.id,
    required this.scope,
    required this.categoryId,
    required this.cause,
    required this.type,
  });

  bool get canClean =>
      type != 'folder' &&
      cause?.verdict != 'KEEP' &&
      CleanerCategories.byId(categoryId ?? '')?.safety == CleanerSafety.safe;
  DiskTreeNode get representative => examples.first;

  void add(DiskTreeNode node, {DiskTreeNode? parent}) {
    nodes.add(node);
    if (node.isFile) {
      fileBytes += node.sizeBytes;
    } else if (node.sizeBytes > largestFolderBytes) {
      largestFolderBytes = node.sizeBytes;
    }
    // Most leaves are smaller than the examples already retained. Avoid a
    // list allocation/sort for every file in a large homogeneous directory.
    if (examples.length == 4 && node.sizeBytes <= examples.last.sizeBytes) {
      return;
    }
    examples.add(node);
    examples.sort((a, b) {
      final bySize = b.sizeBytes.compareTo(a.sizeBytes);
      return bySize == 0 ? a.fullPath.compareTo(b.fullPath) : bySize;
    });
    if (identical(examples.first, node)) representativeParent = parent;
    if (examples.length > 4) examples.removeLast();
  }

  Map<String, Object?> get evidence => {
    'group_id': id,
    'scope': scope,
    'entry_count': nodes.length,
    'type': type,
    'file_bytes': fileBytes,
    'largest_folder_bytes_not_additive': largestFolderBytes,
    'scanner_category': categoryId,
    'scanner_category_description': CleanerCategories.byId(
      categoryId ?? '',
    )?.description,
    'can_clean': canClean,
    if (cause != null)
      'known_cause': {
        'label': cause!.label,
        'why': cause!.explanation,
        'safe_action': cause!.action,
        'starting_verdict': cause!.verdict,
      },
    'examples_not_all_members': [
      for (final node in examples)
        {'path': node.fullPath, 'size_bytes': node.sizeBytes},
    ],
  };
}
