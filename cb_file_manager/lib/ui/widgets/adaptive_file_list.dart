import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// Explorer-style List fills each column from top to bottom, then moves right.
/// Mobile keeps the existing, variable-height single-column list.
class AdaptiveFileList extends StatefulWidget {
  const AdaptiveFileList({
    super.key,
    required this.isDesktop,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.onCrossAxisCountChanged,
    this.onItemMainAxisExtentChanged,
  });

  final bool isDesktop;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final ValueChanged<int?>? onCrossAxisCountChanged;
  final ValueChanged<double?>? onItemMainAxisExtentChanged;

  @override
  State<AdaptiveFileList> createState() => _AdaptiveFileListState();
}

class _AdaptiveFileListState extends State<AdaptiveFileList> {
  final ScrollController _ownedController = ScrollController();
  ScrollController get _controller => widget.controller ?? _ownedController;

  @override
  void dispose() {
    _ownedController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    final position = _controller.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (mounted && _controller.hasClients) {
        _controller.position.pointerScroll(delta);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isDesktop) {
      return ListView.builder(
        controller: _controller,
        physics: const ClampingScrollPhysics(),
        scrollCacheExtent: const ScrollCacheExtent.pixels(800),
        padding: const EdgeInsets.only(bottom: 200),
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.max(
          1.0,
          MediaQuery.textScalerOf(context).scale(14) / 14,
        );
        const spacing = 8.0;
        // Leave room below the rows for the horizontal scrollbar.
        final rows = math.max(
          1,
          ((constraints.maxHeight - 16) / (40 * scale)).floor(),
        );
        final availableWidth = math.max(1.0, constraints.maxWidth - 16);
        final visibleColumns = math.max(
          1,
          ((availableWidth + spacing) / (260 * scale + spacing)).floor(),
        );
        final columnWidth =
            (availableWidth - spacing * (visibleColumns - 1)) / visibleColumns;
        widget.onCrossAxisCountChanged?.call(rows);
        widget.onItemMainAxisExtentChanged?.call(columnWidth + spacing);
        return Listener(
          onPointerSignal: _handlePointerSignal,
          child: GridView.builder(
            key: const ValueKey('desktop-list-columns'),
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            scrollCacheExtent: const ScrollCacheExtent.pixels(800),
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: rows,
              mainAxisSpacing: spacing,
              mainAxisExtent: columnWidth,
            ),
            itemCount: widget.itemCount,
            itemBuilder: widget.itemBuilder,
          ),
        );
      },
    );
  }
}
