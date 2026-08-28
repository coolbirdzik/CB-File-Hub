import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/widgets/tree_view/tree_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class BrowserLikeCollectionView<T> extends StatelessWidget {
  final ViewMode viewMode;
  final List<T> items;
  final bool isDesktop;
  final GlobalKey stackKey;
  final Future<void> Function() onRefresh;
  final ScrollController? scrollController;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics physics;
  final void Function(Offset localPosition)? onDragStart;
  final void Function(Offset localPosition)? onDragUpdate;
  final void Function()? onDragEnd;
  final String Function(T item) itemIdentity;
  final void Function(String key, Rect rect) registerItemPosition;
  final Widget Function(BuildContext itemContext, T item) listItemBuilder;
  final Widget Function(BuildContext itemContext, T item) gridItemBuilder;
  final Widget Function(BuildContext itemContext, T item) detailsItemBuilder;

  /// Optional row builder used for [ViewMode.tree]. Receives the tree
  /// node so callers can render whatever depth-aware UI they want
  /// (icon, name, badge, etc.). The shell handles the indent column +
  /// expand chevron itself.
  final Widget Function(
    BuildContext itemContext,
    TreeNode<T> node,
    int depth,
  )? treeItemBuilder;

  /// Async loader called the first time a folder node is expanded.
  /// Result is cached on the node.
  final Future<List<TreeNode<T>>> Function(TreeNode<T> node)?
      treeChildrenLoader;

  /// Per-item flag indicating whether the item itself is a leaf
  /// (e.g. a file). Used to decide whether the chevron is shown and
  /// whether the children loader should be called. Defaults to `false`
  /// (everything expandable) when omitted.
  final bool Function(T item)? treeIsLeaf;
  final Widget? detailsHeader;
  final Widget Function(BuildContext context, int index)?
      detailsSeparatorBuilder;
  final Widget dragSelectionOverlay;
  final int gridCrossAxisCount;
  final double gridSpacing;
  final double gridChildAspectRatio;
  final double? listCacheExtent;
  final double? gridCacheExtent;
  final double? detailsCacheExtent;

  /// When false the per-item position registration (used for lasso/drag
  /// selection) is skipped — every visible item then avoids a per-frame
  /// `LayoutBuilder` + `addPostFrameCallback` + `localToGlobal` round-trip.
  /// Trash bin / recycle bin enables this only while a drag is in progress.
  final bool measurePositions;

  const BrowserLikeCollectionView({
    Key? key,
    required this.viewMode,
    required this.items,
    required this.isDesktop,
    required this.stackKey,
    required this.onRefresh,
    this.scrollController,
    this.padding = EdgeInsets.zero,
    this.physics = const ClampingScrollPhysics(),
    required this.itemIdentity,
    required this.registerItemPosition,
    required this.listItemBuilder,
    required this.gridItemBuilder,
    required this.detailsItemBuilder,
    this.treeItemBuilder,
    this.treeChildrenLoader,
    this.treeIsLeaf,
    required this.dragSelectionOverlay,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.detailsHeader,
    this.detailsSeparatorBuilder,
    this.gridCrossAxisCount = 1,
    this.gridSpacing = 8.0,
    this.gridChildAspectRatio = 0.8,
    this.listCacheExtent,
    this.gridCacheExtent,
    this.detailsCacheExtent,
    this.measurePositions = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: stackKey,
      children: [
        GestureDetector(
          onPanStart: isDesktop && onDragStart != null
              ? (details) => onDragStart!(details.localPosition)
              : null,
          onPanUpdate: isDesktop && onDragUpdate != null
              ? (details) => onDragUpdate!(details.localPosition)
              : null,
          onPanEnd: isDesktop && onDragEnd != null ? (_) => onDragEnd!() : null,
          behavior: HitTestBehavior.translucent,
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: _buildContent(),
          ),
        ),
        dragSelectionOverlay,
      ],
    );
  }

  Widget _buildContent() {
    // Reverse-lookup map for `findChildIndexCallback`. With this, when the
    // underlying list is sorted/filtered Flutter reuses element slots
    // instead of rebuilding every visible item from scratch.
    final indexByIdentity = <String, int>{
      for (var i = 0; i < items.length; i++) itemIdentity(items[i]): i,
    };
    int? findIndex(Key key) {
      if (key is ValueKey<String>) {
        return indexByIdentity[key.value];
      }
      return null;
    }

    Widget buildItem(BuildContext context, int index,
        Widget Function(BuildContext, T) builder) {
      final item = items[index];
      final id = itemIdentity(item);
      final child =
          Builder(builder: (itemContext) => builder(itemContext, item));
      final wrapped = RepaintBoundary(
        child: measurePositions
            ? _MeasuredCollectionItem(
                identity: id,
                registerItemPosition: registerItemPosition,
                child: child,
              )
            : child,
      );
      return KeyedSubtree(
        key: ValueKey<String>(id),
        child: wrapped,
      );
    }

    if (viewMode == ViewMode.grid || viewMode == ViewMode.gridPreview) {
      return GridView.builder(
        controller: scrollController,
        padding: padding,
        physics: physics,
        scrollCacheExtent: gridCacheExtent == null
            ? null
            : ScrollCacheExtent.pixels(gridCacheExtent!),
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true,
        addSemanticIndexes: false,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridCrossAxisCount,
          crossAxisSpacing: gridSpacing,
          mainAxisSpacing: gridSpacing,
          childAspectRatio: gridChildAspectRatio,
        ),
        itemCount: items.length,
        findChildIndexCallback: findIndex,
        itemBuilder: (context, index) =>
            buildItem(context, index, gridItemBuilder),
      );
    }

    if (viewMode == ViewMode.details) {
      final Widget listView = detailsSeparatorBuilder != null
          ? ListView.separated(
              controller: scrollController,
              padding: padding,
              physics: physics,
              scrollCacheExtent: detailsCacheExtent == null
                  ? null
                  : ScrollCacheExtent.pixels(detailsCacheExtent!),
              addAutomaticKeepAlives: true,
              addRepaintBoundaries: true,
              addSemanticIndexes: false,
              itemCount: items.length,
              separatorBuilder: detailsSeparatorBuilder!,
              findItemIndexCallback: findIndex,
              itemBuilder: (context, index) =>
                  buildItem(context, index, detailsItemBuilder),
            )
          : ListView.builder(
              controller: scrollController,
              padding: padding,
              physics: physics,
              scrollCacheExtent: detailsCacheExtent == null
                  ? null
                  : ScrollCacheExtent.pixels(detailsCacheExtent!),
              addAutomaticKeepAlives: true,
              addRepaintBoundaries: true,
              addSemanticIndexes: false,
              itemCount: items.length,
              findChildIndexCallback: findIndex,
              itemBuilder: (context, index) =>
                  buildItem(context, index, detailsItemBuilder),
            );
      return Column(
        children: [
          if (detailsHeader != null) detailsHeader!,
          Expanded(
            child: listView,
          ),
        ],
      );
    }

    if (viewMode == ViewMode.tree && treeItemBuilder != null) {
      return _BrowserTreeView<T>(
        items: items,
        itemIdentity: itemIdentity,
        treeIsLeaf: treeIsLeaf,
        treeChildrenLoader: treeChildrenLoader,
        treeItemBuilder: treeItemBuilder!,
        scrollController: scrollController,
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: padding,
      physics: physics,
      scrollCacheExtent: listCacheExtent == null
          ? null
          : ScrollCacheExtent.pixels(listCacheExtent!),
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
      itemCount: items.length,
      findChildIndexCallback: findIndex,
      itemBuilder: (context, index) =>
          buildItem(context, index, listItemBuilder),
    );
  }
}

class _BrowserTreeView<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T item) itemIdentity;
  final bool Function(T item)? treeIsLeaf;
  final Future<List<TreeNode<T>>> Function(TreeNode<T> node)?
      treeChildrenLoader;
  final Widget Function(
    BuildContext itemContext,
    TreeNode<T> node,
    int depth,
  ) treeItemBuilder;
  final ScrollController? scrollController;

  const _BrowserTreeView({
    Key? key,
    required this.items,
    required this.itemIdentity,
    required this.treeIsLeaf,
    required this.treeChildrenLoader,
    required this.treeItemBuilder,
    required this.scrollController,
  }) : super(key: key);

  @override
  State<_BrowserTreeView<T>> createState() => _BrowserTreeViewState<T>();
}

class _BrowserTreeViewState<T> extends State<_BrowserTreeView<T>> {
  List<TreeNode<T>> _roots = const [];
  String? _signature;

  @override
  void didUpdateWidget(covariant _BrowserTreeView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRebuildRoots();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeRebuildRoots();
  }

  /// Rebuild root nodes only when the input list actually changes
  /// (cheap signature: count + last id). This preserves expansion
  /// state across rebuilds caused by selection changes etc.
  void _maybeRebuildRoots() {
    final items = widget.items;
    final last = items.isEmpty ? '' : widget.itemIdentity(items.last);
    final sig = '${items.length}|$last';
    if (sig == _signature && _roots.isNotEmpty) return;
    _signature = sig;
    _roots = items
        .map(
          (item) => TreeNode<T>(
            id: widget.itemIdentity(item),
            data: item,
            isLeaf: widget.treeIsLeaf?.call(item) ?? false,
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return GenericTreeView<T>(
      roots: _roots,
      itemExtent: 30,
      childrenLoader: widget.treeChildrenLoader,
      itemBuilder: widget.treeItemBuilder,
      scrollController: widget.scrollController,
    );
  }
}

class _MeasuredCollectionItem extends StatelessWidget {
  final String identity;
  final void Function(String key, Rect rect) registerItemPosition;
  final Widget child;

  const _MeasuredCollectionItem({
    required this.identity,
    required this.registerItemPosition,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (layoutContext, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!layoutContext.mounted) {
            return;
          }
          final renderBox = layoutContext.findRenderObject() as RenderBox?;
          if (renderBox == null || !renderBox.hasSize) {
            return;
          }
          final position = renderBox.localToGlobal(Offset.zero);
          registerItemPosition(
            identity,
            Rect.fromLTWH(
              position.dx,
              position.dy,
              renderBox.size.width,
              renderBox.size.height,
            ),
          );
        });
        return child;
      },
    );
  }
}
