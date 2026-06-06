/// A generic tree node used by [GenericTreeView].
///
/// The tree is intentionally lightweight: each node carries a stable [id]
/// (used for identity, expansion state inspection, and selection
/// highlighting), an arbitrary [data] payload, and a mutable [isExpanded]
/// flag.
///
/// Children can be supplied eagerly via [children] or lazily fetched on
/// first expansion through `GenericTreeView.childrenLoader`. A node with
/// `isLeaf == true` never shows an expand chevron and is never asked for
/// children.
class TreeNode<T> {
  /// Stable identifier — should be unique within the tree at any given
  /// time (typically a file path or a normalized tag name).
  final String id;

  /// Caller payload. The row builder reads this to render the node.
  final T data;

  /// Marks this node as a leaf. Leaves never display an expand chevron
  /// and never trigger the children loader.
  final bool isLeaf;

  /// Children of this node.
  ///
  /// `null` means children are not loaded yet and will be fetched via the
  /// `GenericTreeView.childrenLoader` the first time the node is expanded.
  /// An empty list means children are loaded but the folder is empty.
  List<TreeNode<T>>? children;

  /// Whether the node is currently expanded. Owned by the node itself,
  /// matching the disk-cleaner pattern.
  bool isExpanded;

  /// Internal flag used by [GenericTreeView] to track an in-flight
  /// `childrenLoader` call. Not meant to be set by callers.
  bool isLoadingChildren;

  /// Internal error message stored when the loader throws. Cleared by a
  /// retry or by manually replacing the node.
  String? loadError;

  TreeNode({
    required this.id,
    required this.data,
    this.isLeaf = false,
    this.children,
    this.isExpanded = false,
    this.isLoadingChildren = false,
    this.loadError,
  });

  /// True when this node can request children via the async loader.
  bool get needsLoad => !isLeaf && children == null && loadError == null;

  /// Walks the subtree and runs [visit] on each node (including this one).
  void walk(void Function(TreeNode<T> node) visit) {
    visit(this);
    final kids = children;
    if (kids != null) {
      for (final c in kids) {
        c.walk(visit);
      }
    }
  }
}
