import 'disk_tree_node.dart';

/// Selection helpers for the disk cleaner tree.
class DiskTreeSelection {
  const DiskTreeSelection._();

  /// Counts only nodes explicitly marked as junk by the scanner.
  ///
  /// Ancestor folders that merely contain junk remain visible in the filtered
  /// tree, but they are not cleanable targets themselves.
  static int countCleanableNodes(DiskTreeNode? root) {
    if (root == null) return 0;
    var count = 0;

    void walk(DiskTreeNode node) {
      if (node.fullPath.isNotEmpty && node.isJunk) count++;
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(root);
    return count;
  }

  /// Updates bulk selection and returns the complete selected path set.
  ///
  /// Checking makes the selection exactly the scanner-approved junk nodes,
  /// clearing any stale or manual safe-node selections. Unchecking clears the
  /// entire tree because the corresponding UI action is "Uncheck all".
  static Set<String> setAllCleanableChecked(
    DiskTreeNode? root,
    bool checked,
  ) {
    if (root == null) return <String>{};
    final selectedPaths = <String>{};

    void walk(DiskTreeNode node, {required bool ancestorSelected}) {
      if (node.fullPath.isNotEmpty) {
        node.isSelectedForDeletion =
            checked && node.isJunk && !ancestorSelected;
      }
      if (node.isSelectedForDeletion && node.fullPath.isNotEmpty) {
        selectedPaths.add(node.fullPath);
      }
      for (final child in node.children) {
        walk(
          child,
          ancestorSelected: ancestorSelected || node.isSelectedForDeletion,
        );
      }
    }

    walk(root, ancestorSelected: false);
    root.invalidateSelectionCache();
    return selectedPaths;
  }

  /// Toggles one exact cleanup target without materializing its descendants.
  ///
  /// The result remains canonical: selecting a target removes selected
  /// ancestors and descendants because either relationship would represent
  /// overlapping deletion work. Only nodes whose exact target state changes
  /// are mutated, so this costs O(selected targets), not O(tree size).
  static Set<DiskTreeNode> setExactTargetChecked(
    Iterable<DiskTreeNode> currentTargets,
    DiskTreeNode target,
    bool checked,
  ) {
    final result = <DiskTreeNode>{...currentTargets};
    final targetPath = _normalizePath(target.fullPath);
    if (targetPath.isEmpty) return result;

    if (!checked) {
      for (final existing in result.toList(growable: false)) {
        if (_normalizePath(existing.fullPath) != targetPath) continue;
        existing.isSelectedForDeletion = false;
        result.remove(existing);
      }
      target.isSelectedForDeletion = false;
      return result;
    }

    for (final existing in result.toList(growable: false)) {
      final existingPath = _normalizePath(existing.fullPath);
      if (_isSameOrDescendant(existingPath, targetPath) ||
          _isSameOrDescendant(targetPath, existingPath)) {
        existing.isSelectedForDeletion = false;
        result.remove(existing);
      }
    }
    target.isSelectedForDeletion = true;
    result.add(target);
    return result;
  }

  static String _normalizePath(String path) {
    var normalized = path.trim().replaceAll('/', r'\').toUpperCase();
    while (normalized.length > 3 && normalized.endsWith(r'\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool _isSameOrDescendant(String path, String root) {
    if (path == root) return true;
    final prefix = root.endsWith(r'\') ? root : '$root\\';
    return path.startsWith(prefix);
  }

  /// Returns the exact top-level nodes that will be sent to cleanup.
  ///
  /// When a selected directory contains selected descendants, only the
  /// directory is returned because deleting it already covers its subtree.
  static List<DiskTreeNode> collectDeletionTargets(DiskTreeNode? root) {
    if (root == null) return const <DiskTreeNode>[];
    final targets = <DiskTreeNode>[];

    void walk(DiskTreeNode node) {
      if (node.fullPath.isNotEmpty && node.isSelectedForDeletion) {
        targets.add(node);
        return;
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(root);
    return targets;
  }

  /// Expands only the ancestor chain needed to reveal deletion targets.
  ///
  /// A selected directory is itself a target, so its descendants do not need
  /// to be expanded in the review tree.
  static bool expandAncestorsOfSelection(DiskTreeNode node) {
    if (node.fullPath.isNotEmpty && node.isSelectedForDeletion) {
      node.isExpanded = false;
      return true;
    }

    var containsSelection = false;
    for (final child in node.children) {
      if (expandAncestorsOfSelection(child)) containsSelection = true;
    }
    if (containsSelection) node.isExpanded = true;
    return containsSelection;
  }
}
