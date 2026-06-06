import 'dart:async';

import 'package:flutter/material.dart';

import 'tree_node.dart';
import 'tree_row.dart';

/// Builder signature for the user-supplied row content (everything except
/// the indent column and expand chevron, which the tree owns).
typedef TreeRowBuilder<T> = Widget Function(
  BuildContext context,
  TreeNode<T> node,
  int depth,
);

/// Async children loader. Called the first time a node expands when
/// `node.children == null`. The returned list is cached on the node.
typedef TreeChildrenLoader<T> = Future<List<TreeNode<T>>> Function(
  TreeNode<T> node,
);

/// A virtualised, generic tree view modelled after the disk-cleaner's
/// flat-list pattern.
///
/// The tree flattens its visible rows into a single `ListView.builder`
/// with a fixed `itemExtent`, which keeps scroll cheap even for tens of
/// thousands of nodes. Expansion state is owned by each [TreeNode]
/// (mutating `isExpanded`), and the parent screen is expected to call
/// `setState` after toggling a node Ã¢â‚¬â€ which the tree does automatically
/// for built-in interactions (chevron tap, lazy load completion).
class GenericTreeView<T> extends StatefulWidget {
  /// Top-level nodes to render. Order matters and is preserved.
  final List<TreeNode<T>> roots;

  /// Builder for the user-controlled portion of each row (icon, name,
  /// trailing widgets, etc.). The shell renders the indentation column
  /// and chevron itself.
  final TreeRowBuilder<T> itemBuilder;

  /// Optional async loader for nodes whose children haven't been
  /// resolved yet. If absent, every node must supply [TreeNode.children]
  /// up front (or be a leaf).
  final TreeChildrenLoader<T>? childrenLoader;

  /// Fixed row height (px). Must be constant for virtualisation.
  final double itemExtent;

  /// Pixels of indentation per depth level.
  final double indentPerDepth;

  /// Optional filter predicate applied during flatten. A node returning
  /// false is hidden, along with its subtree. The caller is responsible
  /// for keeping ancestors of matching nodes visible if that's the
  /// desired UX (compute a visible-set first and gate by membership).
  final bool Function(TreeNode<T> node)? nodeFilter;

  /// Tap on the row body (anywhere except the chevron).
  final void Function(TreeNode<T> node)? onTap;

  /// Double-tap on the row body.
  final void Function(TreeNode<T> node)? onDoubleTap;

  /// Right-click / long-press on the row.
  final void Function(TreeNode<T> node, Offset globalPosition)? onSecondary;

  /// Selected node ids Ã¢â‚¬â€ rows whose `id` is in this set are highlighted.
  final Set<String>? selectedIds;

  /// Currently focused node id (for keyboard navigation, lighter
  /// highlight). Independent from selection.
  final String? focusedId;

  /// Cap on the number of children rendered per node. Excess children
  /// are replaced by a `Ã¢â‚¬Â¦ and N more` row that, when tapped, raises the
  /// limit on that node. Default `2000`.
  final int maxChildrenPerNode;

  /// Optional [ScrollController] for the inner [ListView].
  final ScrollController? scrollController;

  /// Optional empty state widget shown when the (filtered) flat-list is
  /// empty. Defaults to a simple centered text.
  final Widget? emptyState;

  /// When true, tapping a row body also toggles expansion for nodes that
  /// have expandable children (in addition to firing [onTap]). The chevron
  /// always toggles regardless of this flag.
  final bool expandOnRowTap;

  const GenericTreeView({
    Key? key,
    required this.roots,
    required this.itemBuilder,
    this.childrenLoader,
    this.itemExtent = 32,
    this.indentPerDepth = 16,
    this.nodeFilter,
    this.onTap,
    this.onDoubleTap,
    this.onSecondary,
    this.selectedIds,
    this.focusedId,
    this.maxChildrenPerNode = 2000,
    this.scrollController,
    this.emptyState,
    this.expandOnRowTap = false,
  }) : super(key: key);

  @override
  State<GenericTreeView<T>> createState() => _GenericTreeViewState<T>();
}

class _GenericTreeViewState<T> extends State<GenericTreeView<T>> {
  /// Per-node soft limit on rendered children. Bumped when the user
  /// taps the truncated-tail row.
  final Map<String, int> _renderLimitOverrides = <String, int>{};

  /// Node ids that were just revealed by an expand and should play a
  /// one-shot entrance animation. Cleared shortly after, so scrolling
  /// virtualized rows in/out does not replay the animation.
  final Set<String> _animatingIn = <String>{};
  Timer? _animatingInTimer;

  /// Node ids whose parent is collapsing: kept rendered for one animation
  /// frame window so they can play a fade/slide-up exit before the parent
  /// actually collapses and drops them from the flattened list.
  final Set<String> _animatingOut = <String>{};

  /// Nodes whose `isExpanded` should be flipped to false once the current
  /// collapse animation window ends.
  final List<TreeNode<T>> _pendingCollapse = <TreeNode<T>>[];
  Timer? _animatingOutTimer;

  static const Duration _expandAnimDuration = Duration(milliseconds: 200);

  @override
  void dispose() {
    _animatingInTimer?.cancel();
    _animatingOutTimer?.cancel();
    super.dispose();
  }

  /// Collects the ids of rows that become visible when [node] expands
  /// (its currently-expanded, filtered, capped descendant subtree).
  void _collectRevealedIds(TreeNode<T> node, Set<String> out) {
    if (node.isLeaf || !node.isExpanded) return;
    final children = node.children;
    if (children == null || children.isEmpty) return;
    final cap = _renderLimitOverrides[node.id] ?? widget.maxChildrenPerNode;
    final renderCount = children.length <= cap ? children.length : cap;
    for (var i = 0; i < renderCount; i++) {
      final child = children[i];
      if (widget.nodeFilter != null && !widget.nodeFilter!(child)) continue;
      out.add(child.id);
      _collectRevealedIds(child, out);
    }
  }

  void _markRevealed(TreeNode<T> node) {
    final revealed = <String>{};
    _collectRevealedIds(node, revealed);
    if (revealed.isEmpty) return;
    _animatingIn.addAll(revealed);
    _animatingInTimer?.cancel();
    _animatingInTimer = Timer(_expandAnimDuration, () {
      if (!mounted) return;
      setState(_animatingIn.clear);
    });
  }

  /// Toggles a node's expansion. If children haven't been loaded yet,
  /// the loader is dispatched.
  void _toggleExpansion(TreeNode<T> node) {
    if (node.isLeaf) return;
    if (!node.isExpanded) {
      // Cancelling a pending collapse of the same node re-expands instantly.
      _pendingCollapse.remove(node);
      node.isExpanded = true;
      if (node.needsLoad && widget.childrenLoader != null) {
        _loadChildren(node);
      } else {
        _markRevealed(node);
      }
      if (mounted) setState(() {});
    } else {
      _markCollapsing(node);
    }
  }

  /// Begins a collapse: the visible descendant rows are flagged to play an
  /// exit animation while the node stays expanded for one animation window,
  /// then `isExpanded` is flipped to false and the rows drop out.
  void _markCollapsing(TreeNode<T> node) {
    final leaving = <String>{};
    _collectRevealedIds(node, leaving);
    if (leaving.isEmpty) {
      node.isExpanded = false;
      if (mounted) setState(() {});
      return;
    }
    _animatingOut.addAll(leaving);
    _pendingCollapse.add(node);
    _animatingOutTimer?.cancel();
    _animatingOutTimer = Timer(_expandAnimDuration, () {
      if (!mounted) {
        for (final n in _pendingCollapse) {
          n.isExpanded = false;
        }
        _pendingCollapse.clear();
        _animatingOut.clear();
        return;
      }
      setState(() {
        for (final n in _pendingCollapse) {
          n.isExpanded = false;
        }
        _pendingCollapse.clear();
        _animatingOut.clear();
      });
    });
    if (mounted) setState(() {});
  }

  Future<void> _loadChildren(TreeNode<T> node) async {
    final loader = widget.childrenLoader;
    if (loader == null) return;
    node.isLoadingChildren = true;
    node.loadError = null;
    if (mounted) setState(() {});
    try {
      final result = await loader(node);
      node.children = result;
      _markRevealed(node);
    } catch (e) {
      node.loadError = e.toString();
    } finally {
      node.isLoadingChildren = false;
      if (mounted) setState(() {});
    }
  }

  void _retryLoad(TreeNode<T> node) {
    node.loadError = null;
    node.children = null;
    _loadChildren(node);
  }

  void _bumpChildLimit(TreeNode<T> node) {
    final children = node.children;
    if (children == null) return;
    setState(() {
      final current =
          _renderLimitOverrides[node.id] ?? widget.maxChildrenPerNode;
      _renderLimitOverrides[node.id] = current + widget.maxChildrenPerNode;
    });
  }

  /// Walks the tree and produces the visible flat-row list.
  List<FlatTreeRow<T>> _flatten() {
    final out = <FlatTreeRow<T>>[];

    void visit(TreeNode<T> node, int depth) {
      if (widget.nodeFilter != null && !widget.nodeFilter!(node)) {
        return;
      }
      out.add(FlatTreeRow<T>(
        depth: depth,
        kind: FlatRowKind.node,
        node: node,
      ));
      if (!node.isExpanded || node.isLeaf) return;

      // Children may be in one of three states: loading, error, or
      // available (possibly empty).
      if (node.isLoadingChildren) {
        out.add(FlatTreeRow<T>(
          depth: depth + 1,
          kind: FlatRowKind.loading,
          parent: node,
        ));
        return;
      }
      if (node.loadError != null) {
        out.add(FlatTreeRow<T>(
          depth: depth + 1,
          kind: FlatRowKind.error,
          parent: node,
        ));
        return;
      }
      final children = node.children;
      if (children == null || children.isEmpty) return;

      final cap = _renderLimitOverrides[node.id] ?? widget.maxChildrenPerNode;
      final renderCount = children.length <= cap ? children.length : cap;
      for (var i = 0; i < renderCount; i++) {
        visit(children[i], depth + 1);
      }
      if (children.length > renderCount) {
        out.add(FlatTreeRow<T>(
          depth: depth + 1,
          kind: FlatRowKind.truncated,
          parent: node,
          extraCount: children.length - renderCount,
        ));
      }
    }

    for (final root in widget.roots) {
      visit(root, 0);
    }
    return out;
  }

  bool _nodeHasExpandableChildren(TreeNode<T> node) {
    if (node.isLeaf) return false;
    // If we have a loader and haven't loaded yet, treat it as
    // expandable (the loader will populate on first expand).
    if (widget.childrenLoader != null && node.children == null) return true;
    final kids = node.children;
    return kids != null && kids.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _flatten();
    if (rows.isEmpty) {
      return widget.emptyState ??
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nothing to show'),
            ),
          );
    }
    return ListView.builder(
      controller: widget.scrollController,
      itemCount: rows.length,
      itemExtent: widget.itemExtent,
      itemBuilder: (context, index) {
        final row = rows[index];
        switch (row.kind) {
          case FlatRowKind.loading:
            return TreePlaceholderRow(
              kind: row.kind,
              depth: row.depth,
              indentPerDepth: widget.indentPerDepth,
            );
          case FlatRowKind.error:
            return TreePlaceholderRow(
              kind: row.kind,
              depth: row.depth,
              indentPerDepth: widget.indentPerDepth,
              onTap: row.parent == null ? null : () => _retryLoad(row.parent!),
            );
          case FlatRowKind.truncated:
            return TreePlaceholderRow(
              kind: row.kind,
              depth: row.depth,
              indentPerDepth: widget.indentPerDepth,
              extraCount: row.extraCount,
              onTap: row.parent == null
                  ? null
                  : () => _bumpChildLimit(row.parent!),
            );
          case FlatRowKind.node:
            final node = row.node!;
            final selected = widget.selectedIds?.contains(node.id) ?? false;
            final focused = widget.focusedId == node.id;
            final shell = TreeRowShell<T>(
              node: node,
              depth: row.depth,
              indentPerDepth: widget.indentPerDepth,
              hasExpandableChildren: _nodeHasExpandableChildren(node),
              isSelected: selected,
              isFocused: focused,
              onToggleExpansion: () => _toggleExpansion(node),
              onTap: () {
                if (widget.expandOnRowTap && _nodeHasExpandableChildren(node)) {
                  _toggleExpansion(node);
                }
                widget.onTap?.call(node);
              },
              onDoubleTap: widget.onDoubleTap == null
                  ? null
                  : () => widget.onDoubleTap!(node),
              onSecondary: widget.onSecondary == null
                  ? null
                  : (pos) => widget.onSecondary!(node, pos),
              child: widget.itemBuilder(context, node, row.depth),
            );
            if (_animatingOut.contains(node.id)) {
              // Playing an exit animation while the parent collapses.
              return _TreeRowEntrance(
                key: ValueKey('exit-${node.id}'),
                duration: _expandAnimDuration,
                reverse: true,
                child: shell,
              );
            }
            if (_animatingIn.contains(node.id)) {
              // One-shot entrance for rows just revealed by an expand.
              return _TreeRowEntrance(
                key: ValueKey('enter-${node.id}'),
                duration: _expandAnimDuration,
                child: shell,
              );
            }
            return shell;
        }
      },
    );
  }
}

/// Plays a single fade + slide-down entrance when first built. Used for
/// rows revealed by an expand. Because it animates only on initial build,
/// virtualized rows scrolling back into view do not replay it (the id is
/// cleared from the animating set after the animation window).
class _TreeRowEntrance extends StatefulWidget {
  final Widget child;
  final Duration duration;

  /// When true, plays the animation backwards: the row fades out and slides
  /// up (used while a parent collapses, just before the row is dropped).
  final bool reverse;

  const _TreeRowEntrance({
    Key? key,
    required this.child,
    required this.duration,
    this.reverse = false,
  }) : super(key: key);

  @override
  State<_TreeRowEntrance> createState() => _TreeRowEntranceState();
}

class _TreeRowEntranceState extends State<_TreeRowEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.reverse ? 1.0 : 0.0,
  );
  late final Animation<double> _curved =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.reverse) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.18),
          end: Offset.zero,
        ).animate(_curved),
        child: widget.child,
      ),
    );
  }
}
