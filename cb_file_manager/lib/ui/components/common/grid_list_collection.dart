import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../screens/folder_list/folder_list_state.dart';
import '../../tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import '../../utils/grid_zoom_constraints.dart';
import '../../widgets/adaptive_file_list.dart';

/// Browser-like collections share view persistence and layout behavior.
class GridListViewController extends ChangeNotifier {
  GridListViewController({
    this.load,
    this.save,
    this.supportedModes = const {ViewMode.grid, ViewMode.list},
  });

  final Future<ViewMode> Function()? load;
  final Future<void> Function(ViewMode)? save;
  final Set<ViewMode> supportedModes;
  ViewMode _mode = ViewMode.grid;
  ViewMode get mode => _mode;
  bool _changed = false, _disposed = false, _initialized = false;
  Future<void> _writes = Future.value();

  static ViewMode normalize(
    ViewMode mode, {
    Set<ViewMode> supportedModes = const {ViewMode.grid, ViewMode.list},
  }) {
    if (supportedModes.contains(mode)) return mode;
    return supportedModes.contains(ViewMode.grid)
        ? ViewMode.grid
        : supportedModes.first;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final restored = await load?.call();
    if (_disposed || _changed || restored == null) return;
    _mode = normalize(restored, supportedModes: supportedModes);
    notifyListeners();
  }

  Future<void> select(ViewMode mode) {
    _changed = true;
    _mode = normalize(mode, supportedModes: supportedModes);
    notifyListeners();
    final selected = _mode;
    // Keep quick consecutive switches in order, including a failed prior save.
    _writes = _writes.then(
      (_) => save?.call(selected),
      onError: (Object _, StackTrace _) => save?.call(selected),
    );
    return _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class GridListViewToggle extends StatelessWidget {
  const GridListViewToggle({
    super.key,
    required this.mode,
    required this.onChanged,
    this.supportedModes = const {ViewMode.grid, ViewMode.list},
  });
  final ViewMode mode;
  final ValueChanged<ViewMode> onChanged;
  final Set<ViewMode> supportedModes;

  static const _orderedModes = [
    ViewMode.list,
    ViewMode.tiles,
    ViewMode.grid,
    ViewMode.details,
    ViewMode.tree,
    ViewMode.columns,
  ];

  IconData _icon(ViewMode mode) => switch (mode) {
    ViewMode.list => PhosphorIconsLight.list,
    ViewMode.tiles => PhosphorIconsLight.gridNine,
    ViewMode.details => PhosphorIconsLight.listBullets,
    ViewMode.tree => PhosphorIconsLight.treeView,
    ViewMode.columns => PhosphorIconsLight.columns,
    _ => PhosphorIconsLight.squaresFour,
  };

  String _label(BuildContext context, ViewMode mode) => switch (mode) {
    ViewMode.list => context.tr.viewModeList,
    ViewMode.tiles => context.tr.viewModeTiles,
    ViewMode.details => context.tr.viewModeDetails,
    ViewMode.tree => context.tr.viewModeTree,
    ViewMode.columns => context.tr.viewModeColumns,
    _ => context.tr.viewModeGrid,
  };

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final option in _orderedModes)
        if (supportedModes.contains(option)) option,
    ];
    if (options.length <= 2) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            Semantics(
              selected: option == mode,
              child: CbButton.icon(
                key: ValueKey('collection-view-${option.name}'),
                icon: _icon(option),
                tooltip: _label(context, option),
                variant: option == mode
                    ? CbButtonVariant.subtle
                    : CbButtonVariant.ghost,
                onPressed: () => onChanged(option),
              ),
            ),
        ],
      );
    }
    return PopupMenuButton<ViewMode>(
      key: const ValueKey('collection-view-menu'),
      tooltip: context.tr.viewModeTooltip,
      initialValue: mode,
      icon: Icon(_icon(mode)),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<ViewMode>(
            key: ValueKey('collection-view-${option.name}'),
            value: option,
            child: Row(
              children: [
                Icon(_icon(option), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(_label(context, option))),
                if (option == mode)
                  const Icon(PhosphorIconsLight.check, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

class GridListCollection<T> extends StatefulWidget {
  const GridListCollection({
    super.key,
    required this.mode,
    required this.items,
    required this.isDesktop,
    required this.identity,
    required this.itemBuilder,
    required this.onRefresh,
    this.dragSelectionController,
    this.onBackgroundTap,
    this.supportedModes = const {ViewMode.grid, ViewMode.list},
    this.detailsHeader,
    this.gridZoomLevel,
    this.gridAspectRatio = 1.9,
    this.gridMinExtent = 128,
    this.gridMaxExtent = 156,
  });
  final ViewMode mode;
  final List<T> items;
  final bool isDesktop;
  final String Function(T) identity;
  final Widget Function(BuildContext, T, ViewMode) itemBuilder;
  final Future<void> Function() onRefresh;
  final TabbedFolderDragSelectionController? dragSelectionController;
  final VoidCallback? onBackgroundTap;
  final Set<ViewMode> supportedModes;
  final Widget? detailsHeader;
  final int? gridZoomLevel;
  final double gridAspectRatio;
  final double gridMinExtent;
  final double gridMaxExtent;

  @override
  State<GridListCollection<T>> createState() => _GridListCollectionState<T>();
}

class _GridListCollectionState<T> extends State<GridListCollection<T>> {
  void _registerItem(BuildContext context, String identity) {
    final controller = widget.dragSelectionController;
    if (!widget.isDesktop || controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero);
      controller.registerItemPosition(
        identity,
        Rect.fromLTWH(origin.dx, origin.dy, box.size.width, box.size.height),
      );
    });
  }

  Widget _buildItem(BuildContext context, T item, ViewMode mode) {
    final identity = widget.identity(item);
    return LayoutBuilder(
      builder: (context, _) {
        _registerItem(context, identity);
        return KeyedSubtree(
          key: ValueKey('${mode.name}-$identity'),
          child: widget.itemBuilder(context, item, mode),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = math.max(
        1.0,
        MediaQuery.textScalerOf(context).scale(14) / 14,
      );
      final automaticColumns = math.max(
        1,
        ((constraints.maxWidth - 16 + 8) / (280 * scale + 8)).floor(),
      );
      final columns = widget.gridZoomLevel == null
          ? automaticColumns
          : GridZoomConstraints.columnCountForZoom(
              widget.gridZoomLevel!,
              constraints.maxWidth,
            );
      final width = (constraints.maxWidth - 16 - 8 * (columns - 1)) / columns;
      final gridHeight = (width / widget.gridAspectRatio).clamp(
        widget.gridMinExtent * scale,
        widget.gridMaxExtent * scale,
      );
      final mode = GridListViewController.normalize(
        widget.mode,
        supportedModes: widget.supportedModes,
      );
      final collection = AnimatedSwitcher(
        duration: CbDurations.fast,
        child: switch (mode) {
          ViewMode.grid => RefreshIndicator(
            key: const ValueKey('grid-list-collection-grid'),
            onRefresh: widget.onRefresh,
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              physics: const ClampingScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent: gridHeight,
              ),
              itemCount: widget.items.length,
              itemBuilder: (context, index) =>
                  _buildItem(context, widget.items[index], ViewMode.grid),
            ),
          ),
          ViewMode.tiles => RefreshIndicator(
            key: const ValueKey('grid-list-collection-tiles'),
            onRefresh: widget.onRefresh,
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              physics: const ClampingScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 440 * scale,
                mainAxisExtent: 78 * scale,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: widget.items.length,
              itemBuilder: (context, index) =>
                  _buildItem(context, widget.items[index], ViewMode.tiles),
            ),
          ),
          ViewMode.details => Column(
            key: const ValueKey('grid-list-collection-details'),
            children: [
              ?widget.detailsHeader,
              Expanded(
                child: RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    physics: const ClampingScrollPhysics(),
                    itemExtent: 44 * scale,
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) => _buildItem(
                      context,
                      widget.items[index],
                      ViewMode.details,
                    ),
                  ),
                ),
              ),
            ],
          ),
          ViewMode.tree => RefreshIndicator(
            key: const ValueKey('grid-list-collection-tree'),
            onRefresh: widget.onRefresh,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              physics: const ClampingScrollPhysics(),
              itemCount: widget.items.length,
              itemBuilder: (context, index) =>
                  _buildItem(context, widget.items[index], ViewMode.tree),
            ),
          ),
          _ => RefreshIndicator(
            key: const ValueKey('grid-list-collection-list'),
            onRefresh: widget.onRefresh,
            child: AdaptiveFileList(
              isDesktop: widget.isDesktop,
              itemCount: widget.items.length,
              itemBuilder: (context, index) =>
                  _buildItem(context, widget.items[index], ViewMode.list),
            ),
          ),
        },
      );

      final drag = widget.dragSelectionController;
      if (!widget.isDesktop || drag == null) return collection;
      return Stack(
        key: drag.stackKey,
        children: [
          Listener(
            onPointerDown: (event) {
              if (event.kind != PointerDeviceKind.mouse ||
                  event.buttons != kPrimaryMouseButton) {
                return;
              }
              drag.start(event.localPosition);
              setState(() {});
            },
            onPointerMove: (event) {
              if (event.kind == PointerDeviceKind.mouse &&
                  event.buttons == kPrimaryMouseButton) {
                drag.update(event.localPosition);
              }
            },
            onPointerUp: (_) => drag.end(),
            onPointerCancel: (_) => drag.end(),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onBackgroundTap,
              child: collection,
            ),
          ),
          drag.buildOverlay(),
        ],
      );
    },
  );
}
