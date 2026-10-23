import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../screens/folder_list/folder_list_state.dart';

/// Additional metadata columns for an indexed collection, rendered by the
/// normal file Details header and rows. Cell data stays bounded to the page.
class FileDetailsColumn {
  final String id;
  final String label;
  final String? description;
  final double width;
  final bool visible;
  final String Function(String path) valueOf;
  final VoidCallback? onSort;
  final bool? sortAscending;

  const FileDetailsColumn({
    required this.id,
    required this.label,
    required this.valueOf,
    this.description,
    this.width = 110,
    this.visible = true,
    this.onSort,
    this.sortAscending,
  });

  Widget cell(BuildContext context, String path) {
    final value = valueOf(path);
    return SizedBox(
      key: ValueKey('details-cell-$id-$path'),
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Tooltip(
          message: value,
          child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class FileDetailsColumns extends InheritedWidget {
  final List<FileDetailsColumn> columns;
  final ValueChanged<String> onToggle;
  final bool hasCustomSort;
  final Set<SortOption>? allowedBaseSortOptions;

  const FileDetailsColumns({
    super.key,
    required this.columns,
    required this.onToggle,
    this.hasCustomSort = false,
    this.allowedBaseSortOptions,
    required super.child,
  });

  static FileDetailsColumns? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FileDetailsColumns>();

  Iterable<FileDetailsColumn> get visible => columns.where((c) => c.visible);

  @override
  bool updateShouldNotify(FileDetailsColumns oldWidget) =>
      columns != oldWidget.columns ||
      onToggle != oldWidget.onToggle ||
      hasCustomSort != oldWidget.hasCustomSort ||
      allowedBaseSortOptions != oldWidget.allowedBaseSortOptions;
}

/// Header and lazy vertical list share one horizontal viewport, keeping every
/// column aligned without squeezing file names when extra metadata is enabled.
class FileDetailsViewport extends StatefulWidget {
  final double minimumWidth;
  final Widget child;

  const FileDetailsViewport({
    super.key,
    required this.minimumWidth,
    required this.child,
  });

  @override
  State<FileDetailsViewport> createState() => _FileDetailsViewportState();
}

class _FileDetailsViewportState extends State<FileDetailsViewport> {
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        interactive: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        notificationPredicate: (event) => event.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(constraints.maxWidth, widget.minimumWidth),
            height: constraints.maxHeight,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}
