import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/material.dart';

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
    if (viewMode == ViewMode.grid || viewMode == ViewMode.gridPreview) {
      return GridView.builder(
        controller: scrollController,
        padding: padding,
        physics: physics,
        cacheExtent: gridCacheExtent,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridCrossAxisCount,
          crossAxisSpacing: gridSpacing,
          mainAxisSpacing: gridSpacing,
          childAspectRatio: gridChildAspectRatio,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _MeasuredCollectionItem(
            identity: itemIdentity(item),
            registerItemPosition: registerItemPosition,
            child: Builder(
              builder: (itemContext) => gridItemBuilder(itemContext, item),
            ),
          );
        },
      );
    }

    if (viewMode == ViewMode.details) {
      final Widget listView = detailsSeparatorBuilder != null
          ? ListView.separated(
              controller: scrollController,
              padding: padding,
              physics: physics,
              cacheExtent: detailsCacheExtent,
              itemCount: items.length,
              separatorBuilder: detailsSeparatorBuilder!,
              itemBuilder: (context, index) {
                final item = items[index];
                return _MeasuredCollectionItem(
                  identity: itemIdentity(item),
                  registerItemPosition: registerItemPosition,
                  child: Builder(
                    builder: (itemContext) =>
                        detailsItemBuilder(itemContext, item),
                  ),
                );
              },
            )
          : ListView.builder(
              controller: scrollController,
              padding: padding,
              physics: physics,
              cacheExtent: detailsCacheExtent,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _MeasuredCollectionItem(
                  identity: itemIdentity(item),
                  registerItemPosition: registerItemPosition,
                  child: Builder(
                    builder: (itemContext) =>
                        detailsItemBuilder(itemContext, item),
                  ),
                );
              },
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

    return ListView.builder(
      controller: scrollController,
      padding: padding,
      physics: physics,
      cacheExtent: listCacheExtent,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _MeasuredCollectionItem(
          identity: itemIdentity(item),
          registerItemPosition: registerItemPosition,
          child: Builder(
            builder: (itemContext) => listItemBuilder(itemContext, item),
          ),
        );
      },
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
