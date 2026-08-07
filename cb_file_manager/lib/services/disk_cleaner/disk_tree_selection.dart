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

    void walk(DiskTreeNode node) {
      if (node.fullPath.isNotEmpty) {
        node.isSelectedForDeletion = checked && node.isJunk;
      }
      if (node.isSelectedForDeletion && node.fullPath.isNotEmpty) {
        selectedPaths.add(node.fullPath);
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(root);
    root.invalidateSelectionCache();
    return selectedPaths;
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
