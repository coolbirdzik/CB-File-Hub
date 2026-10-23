import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/primitives/cb_tooltip.dart';
import 'package:cb_file_manager/ui/components/common/file_details_columns.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/services/windows_shell_properties.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Horizontal padding of Details header and rows, on each side.
const double kDetailsRowPadding = 12.0;

extension DetailsColumnPresentation on DetailsColumn {
  String label(AppLocalizations l10n) => switch (this) {
    DetailsColumn.name => l10n.columnName,
    DetailsColumn.type => l10n.columnType,
    DetailsColumn.size => l10n.columnSize,
    DetailsColumn.dateModified => l10n.columnDateModified,
    DetailsColumn.dateCreated => l10n.columnDateCreated,
    DetailsColumn.attributes => l10n.columnAttributes,
    DetailsColumn.dateAccessed => l10n.columnDateAccessed,
    DetailsColumn.extension => l10n.columnExtension,
    DetailsColumn.path => l10n.columnPath,
    DetailsColumn.tags => l10n.columnTags,
    DetailsColumn.dimensions => l10n.columnDimensions,
    DetailsColumn.duration => l10n.columnDuration,
    DetailsColumn.itemCount => l10n.columnItemCount,
    DetailsColumn.parentFolder => l10n.columnParentFolder,
    DetailsColumn.permissions => l10n.columnPermissions,
    _ => l10n.shellColumn(name),
  };

  String description(AppLocalizations l10n) => switch (this) {
    DetailsColumn.name => l10n.columnName,
    DetailsColumn.type => l10n.columnTypeDescription,
    DetailsColumn.size => l10n.columnSizeDescription,
    DetailsColumn.dateModified => l10n.columnDateModifiedDescription,
    DetailsColumn.dateCreated => l10n.columnDateCreatedDescription,
    DetailsColumn.attributes => l10n.columnAttributesDescription,
    DetailsColumn.dateAccessed => l10n.columnDateAccessedDescription,
    DetailsColumn.extension => l10n.columnExtensionDescription,
    DetailsColumn.path => l10n.columnPathDescription,
    DetailsColumn.tags => l10n.columnTagsDescription,
    DetailsColumn.dimensions => l10n.columnDimensionsDescription,
    DetailsColumn.duration => l10n.columnDurationDescription,
    DetailsColumn.itemCount => l10n.columnItemCountDescription,
    DetailsColumn.parentFolder => l10n.columnParentFolderDescription,
    DetailsColumn.permissions => l10n.columnPermissionsDescription,
    _ => l10n.shellColumn('${name}Hint'),
  };

  IconData get icon => switch (this) {
    DetailsColumn.name => PhosphorIconsLight.textAa,
    DetailsColumn.type => PhosphorIconsLight.fileText,
    DetailsColumn.size => PhosphorIconsLight.hardDrives,
    DetailsColumn.dateModified => PhosphorIconsLight.arrowsClockwise,
    DetailsColumn.dateCreated => PhosphorIconsLight.calendar,
    DetailsColumn.attributes => PhosphorIconsLight.info,
    DetailsColumn.dateAccessed => PhosphorIconsLight.clock,
    DetailsColumn.extension => PhosphorIconsLight.fileText,
    DetailsColumn.path => PhosphorIconsLight.path,
    DetailsColumn.tags => PhosphorIconsLight.tag,
    DetailsColumn.dimensions => PhosphorIconsLight.frameCorners,
    DetailsColumn.duration => PhosphorIconsLight.timer,
    DetailsColumn.itemCount => PhosphorIconsLight.listNumbers,
    DetailsColumn.parentFolder => PhosphorIconsLight.folder,
    DetailsColumn.permissions => PhosphorIconsLight.lock,
    DetailsColumn.owner => PhosphorIconsLight.user,
    DetailsColumn.authors => PhosphorIconsLight.users,
    DetailsColumn.title => PhosphorIconsLight.textT,
    DetailsColumn.comments => PhosphorIconsLight.chatText,
    DetailsColumn.pageCount => PhosphorIconsLight.files,
    DetailsColumn.rating => PhosphorIconsLight.star,
    DetailsColumn.dateTaken => PhosphorIconsLight.calendarBlank,
    DetailsColumn.cameraModel => PhosphorIconsLight.camera,
    DetailsColumn.frameRate => PhosphorIconsLight.filmStrip,
    DetailsColumn.bitRate => PhosphorIconsLight.waveform,
    DetailsColumn.artist => PhosphorIconsLight.microphone,
    DetailsColumn.album => PhosphorIconsLight.vinylRecord,
    DetailsColumn.genre => PhosphorIconsLight.musicNotes,
    DetailsColumn.year => PhosphorIconsLight.calendar,
    DetailsColumn.company => PhosphorIconsLight.buildings,
    DetailsColumn.fileDescription => PhosphorIconsLight.info,
    DetailsColumn.fileVersion => PhosphorIconsLight.hash,
    DetailsColumn.productName => PhosphorIconsLight.package,
  };

  /// The ascending and descending sort a header click toggles between, or
  /// Metadata columns are loaded in bounded batches before changing order.
  (SortOption, SortOption)? get sortOptions => switch (this) {
    DetailsColumn.name => (SortOption.nameAsc, SortOption.nameDesc),
    DetailsColumn.type => (SortOption.typeAsc, SortOption.typeDesc),
    DetailsColumn.size => (SortOption.sizeAsc, SortOption.sizeDesc),
    DetailsColumn.dateModified => (SortOption.dateAsc, SortOption.dateDesc),
    DetailsColumn.dateCreated => (
      SortOption.dateCreatedAsc,
      SortOption.dateCreatedDesc,
    ),
    DetailsColumn.attributes => (
      SortOption.attributesAsc,
      SortOption.attributesDesc,
    ),
    DetailsColumn.dateAccessed => (
      SortOption.dateAccessedAsc,
      SortOption.dateAccessedDesc,
    ),
    DetailsColumn.extension => (
      SortOption.extensionAsc,
      SortOption.extensionDesc,
    ),
    DetailsColumn.path ||
    DetailsColumn.parentFolder => (SortOption.pathAsc, SortOption.pathDesc),
    _ => (
      SortOption.values.byName('${name}Asc'),
      SortOption.values.byName('${name}Desc'),
    ),
  };
}

/// A Windows Shell property of [path], loaded in the background.
class ShellPropertyCell extends StatefulWidget {
  final String path;

  /// A [ShellProperty.byName] key; the [DetailsColumn] name.
  final String property;

  const ShellPropertyCell({
    super.key,
    required this.path,
    required this.property,
  });

  @override
  State<ShellPropertyCell> createState() => _ShellPropertyCellState();
}

class _ShellPropertyCellState extends State<ShellPropertyCell> {
  String? _text;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ShellPropertyCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.property != widget.property) {
      _load();
    }
  }

  void _load() {
    final properties = WindowsShellProperties.instance;
    _text = properties.peek(widget.path, widget.property);
    if (_text != null) return;
    final path = widget.path;
    final property = widget.property;
    properties.get(path, property).then((text) {
      if (mounted && path == widget.path && property == widget.property) {
        setState(() => _text = text);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      Text(_text ?? '...', maxLines: 1, overflow: TextOverflow.ellipsis);
}

/// Date text of the Details view.
String formatDetailsDate(DateTime time) => time.toString().split('.').first;

/// The live column layout of a Details table. Rows read it, so they follow
/// the header while a column is resized or moved, before it is saved.
class DetailsColumnsScope extends InheritedWidget {
  final ColumnVisibility columns;

  /// Shows [columns] without saving them (during a resize drag).
  final ValueChanged<ColumnVisibility> preview;

  /// Shows and saves [columns].
  final ValueChanged<ColumnVisibility> commit;

  const DetailsColumnsScope({
    super.key,
    required this.columns,
    required this.preview,
    required this.commit,
    required super.child,
  });

  static DetailsColumnsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailsColumnsScope>();

  @override
  bool updateShouldNotify(DetailsColumnsScope oldWidget) =>
      columns != oldWidget.columns;
}

/// Hosts a Details table: holds the live column layout for
/// [DetailsColumnsScope] and scrolls header and rows horizontally together
/// once the columns are wider than the view.
class DetailsLayoutHost extends StatefulWidget {
  final ColumnVisibility columns;

  /// Persists a changed layout. Without it changes last until [columns]
  /// changes.
  final ValueChanged<ColumnVisibility>? onChanged;
  final Widget child;

  const DetailsLayoutHost({
    super.key,
    required this.columns,
    this.onChanged,
    required this.child,
  });

  @override
  State<DetailsLayoutHost> createState() => _DetailsLayoutHostState();
}

class _DetailsLayoutHostState extends State<DetailsLayoutHost> {
  ColumnVisibility? _live;

  @override
  void didUpdateWidget(DetailsLayoutHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.columns != oldWidget.columns) _live = null;
  }

  void _preview(ColumnVisibility columns) => setState(() => _live = columns);

  void _commit(ColumnVisibility columns) {
    setState(() => _live = columns);
    widget.onChanged?.call(columns);
  }

  @override
  Widget build(BuildContext context) {
    final columns = _live ?? widget.columns;
    final extras = FileDetailsColumns.maybeOf(context)?.visible ?? const [];
    final minimumWidth =
        kDetailsRowPadding * 2 +
        columns.visibleColumns.fold<double>(
          0,
          (sum, column) => sum + columns.widthOf(column),
        ) +
        extras.fold<double>(0, (sum, column) => sum + column.width);
    return FileDetailsViewport(
      minimumWidth: minimumWidth,
      child: DetailsColumnsScope(
        columns: columns,
        preview: _preview,
        commit: _commit,
        child: widget.child,
      ),
    );
  }
}

/// One Details row, header or item: Name fills the free width, extra
/// collection columns follow it, then every other visible column at its own
/// width.
class DetailsRowLayout extends StatelessWidget {
  final ColumnVisibility columns;
  final Widget Function(DetailsColumn column) cellBuilder;
  final Widget Function(FileDetailsColumn column) extraCellBuilder;

  const DetailsRowLayout({
    super.key,
    required this.columns,
    required this.cellBuilder,
    required this.extraCellBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final extras = FileDetailsColumns.maybeOf(context)?.visible ?? const [];
    return Row(
      children: [
        for (final column in columns.visibleColumns)
          if (column == DetailsColumn.name) ...[
            Expanded(child: cellBuilder(column)),
            for (final extra in extras) extraCellBuilder(extra),
          ] else
            SizedBox(
              width: columns.widthOf(column),
              child: cellBuilder(column),
            ),
      ],
    );
  }
}

/// A padded Details cell.
class DetailsCell extends StatelessWidget {
  final Widget child;

  const DetailsCell({super.key, required this.child});

  DetailsCell.text(String text, {Key? key, TextStyle? style})
    : this(
        key: key,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
    child: child,
  );
}

/// The Details header: click a column to sort by it, drag it onto another
/// column to move it, drag its right edge to resize it (double-click the edge
/// for the default width), right-click to choose columns.
class DetailsColumnsHeader extends StatefulWidget {
  final bool supportsMetadataSort;
  final SortOption? sortOption;
  final ValueChanged<SortOption>? onSortOptionSelected;

  /// Must match the horizontal padding of the rows below.
  final double horizontalPadding;

  const DetailsColumnsHeader({
    super.key,
    required this.sortOption,
    this.supportsMetadataSort = true,
    this.onSortOptionSelected,
    this.horizontalPadding = kDetailsRowPadding,
  });

  @override
  State<DetailsColumnsHeader> createState() => _DetailsColumnsHeaderState();
}

class _DetailsColumnsHeaderState extends State<DetailsColumnsHeader> {
  static final bool _touch = Platform.isAndroid || Platform.isIOS;

  DetailsColumn? _resizing;
  double _resizeStartWidth = 0;
  double _resizeOriginX = 0;

  /// The layout the resize last previewed. The scope may not have rebuilt
  /// with it yet when the pointer is released.
  ColumnVisibility? _resized;

  DetailsColumnsScope? get _scope => DetailsColumnsScope.maybeOf(context);

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final columns = scope?.columns ?? const ColumnVisibility();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final style = TextStyle(
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onSurface,
    );
    return GestureDetector(
      onSecondaryTapUp: scope == null
          ? null
          : (details) => _showMenu(details.globalPosition, l10n),
      child: Container(
        key: const ValueKey('details-columns-header'),
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
        color: theme.colorScheme.surfaceContainerHighest,
        child: DetailsRowLayout(
          columns: columns,
          cellBuilder: (column) =>
              _buildCell(context, column, columns, style, l10n),
          extraCellBuilder: (column) => SizedBox(
            width: column.width,
            child: CbTooltip(
              message: column.description ?? column.label,
              child: Semantics(
                button: column.onSort != null,
                selected: column.sortAscending != null,
                child: InkWell(
                  key: ValueKey('details-header-${column.id}'),
                  onTap: column.onSort,
                  child: DetailsCell(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            column.label,
                            style: style,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (column.onSort != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            column.sortAscending == false
                                ? PhosphorIconsLight.arrowDown
                                : PhosphorIconsLight.arrowUp,
                            size: 16,
                            color: column.sortAscending == null
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCell(
    BuildContext context,
    DetailsColumn column,
    ColumnVisibility columns,
    TextStyle style,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final options = column.sortOptions;
    final allowed = FileDetailsColumns.maybeOf(context)?.allowedBaseSortOptions;
    final sort = allowed != null && !allowed.contains(options?.$1)
        ? null
        : !widget.supportsMetadataSort && options?.$1.metadataColumn != null
        ? null
        : options;
    final customSort =
        FileDetailsColumns.maybeOf(context)?.hasCustomSort ?? false;
    final ascending =
        !customSort && sort != null && widget.sortOption == sort.$1;
    final descending =
        !customSort && sort != null && widget.sortOption == sort.$2;
    final label = Row(
      children: [
        Flexible(
          child: Text(
            column.label(l10n),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (sort != null) ...[
          const SizedBox(width: 4),
          Icon(
            descending
                ? PhosphorIconsLight.arrowDown
                : PhosphorIconsLight.arrowUp,
            size: 16,
            color: ascending || descending
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ],
    );
    Widget content = InkWell(
      key: ValueKey('details-header-${column.name}'),
      onTap: sort == null || widget.onSortOptionSelected == null
          ? null
          : () => widget.onSortOptionSelected!(ascending ? sort.$2 : sort.$1),
      child: DetailsCell(child: label),
    );

    if (column != DetailsColumn.name && _scope != null) {
      content = _buildDraggable(column, columns, content, style, l10n);
    }
    return DragTarget<DetailsColumn>(
      onWillAcceptWithDetails: (details) =>
          details.data != column && _scope != null,
      onAcceptWithDetails: (details) =>
          _scope?.commit(columns.moveColumn(details.data, column)),
      builder: (context, candidates, _) {
        final dragged = candidates.isEmpty ? null : candidates.first;
        final order = columns.orderedColumns;
        final dropAfter =
            dragged != null &&
            (column == DetailsColumn.name ||
                order.indexOf(dragged) < order.indexOf(column));
        return Stack(
          children: [
            content,
            if (dragged != null)
              Positioned(
                top: 4,
                bottom: 4,
                left: dropAfter ? null : 0,
                right: dropAfter ? 0 : null,
                width: 2,
                child: ColoredBox(color: theme.colorScheme.primary),
              ),
            if (_scope != null)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: _touch ? 16 : 8,
                child: _buildResizeHandle(column, columns),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDraggable(
    DetailsColumn column,
    ColumnVisibility columns,
    Widget child,
    TextStyle style,
    AppLocalizations l10n,
  ) {
    final feedback = Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: columns.widthOf(column),
        child: DetailsCell.text(column.label(l10n), style: style),
      ),
    );
    final dimmed = Opacity(opacity: 0.4, child: child);
    return _touch
        ? LongPressDraggable<DetailsColumn>(
            data: column,
            axis: Axis.horizontal,
            feedback: feedback,
            childWhenDragging: dimmed,
            child: child,
          )
        : Draggable<DetailsColumn>(
            data: column,
            axis: Axis.horizontal,
            feedback: feedback,
            childWhenDragging: dimmed,
            child: child,
          );
  }

  Widget _buildResizeHandle(DetailsColumn column, ColumnVisibility columns) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: ValueKey('details-resize-${column.name}'),
        behavior: HitTestBehavior.opaque,
        // Measure from the press, so the edge stays under the pointer.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (details) {
          final box = context.findRenderObject() as RenderBox?;
          _resizing = column;
          _resizeOriginX = details.globalPosition.dx;
          // Name is drawn wider than its saved width when it fills the view,
          // so resize from what is on screen.
          _resizeStartWidth = column == DetailsColumn.name && box != null
              ? _renderedNameWidth(box, columns)
              : columns.widthOf(column);
        },
        onHorizontalDragUpdate: (details) {
          final scope = _scope;
          if (_resizing != column || scope == null) return;
          final delta = details.globalPosition.dx - _resizeOriginX;
          final resized = (_resized ?? scope.columns).withWidth(
            column,
            _resizeStartWidth + delta,
          );
          _resized = resized;
          scope.preview(resized);
        },
        onHorizontalDragEnd: (_) => _endResize(),
        onHorizontalDragCancel: _endResize,
        onDoubleTap: () {
          final scope = _scope;
          scope?.commit(scope.columns.withWidth(column, null));
        },
        child: Center(
          child: Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: 8),
            color: _resizing == column
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }

  double _renderedNameWidth(RenderBox header, ColumnVisibility columns) {
    final extras = FileDetailsColumns.maybeOf(context)?.visible ?? const [];
    final others = columns.visibleColumns
        .where((column) => column != DetailsColumn.name)
        .fold<double>(0, (sum, column) => sum + columns.widthOf(column));
    final extraWidth = extras.fold<double>(0, (sum, c) => sum + c.width);
    final free =
        header.size.width - widget.horizontalPadding * 2 - others - extraWidth;
    final saved = columns.widthOf(DetailsColumn.name);
    return free > saved ? free : saved;
  }

  void _endResize() {
    final resized = _resized;
    if (_resizing == null) return;
    setState(() {
      _resizing = null;
      _resized = null;
    });
    if (resized != null) _scope?.commit(resized);
  }

  Future<void> _showMenu(Offset position, AppLocalizations l10n) async {
    final scope = _scope;
    if (scope == null) return;
    final columns = scope.columns;
    final extras = FileDetailsColumns.maybeOf(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    PopupMenuItem<String> toggle(String value, String label, bool checked) =>
        PopupMenuItem<String>(
          value: value,
          height: 36,
          child: Row(
            children: [
              Icon(
                checked
                    ? PhosphorIconsLight.checkSquare
                    : PhosphorIconsLight.square,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          ),
        );

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        for (final column in extras?.columns ?? const <FileDetailsColumn>[])
          toggle('extra:${column.id}', column.label, column.visible),
        if (extras != null) const PopupMenuDivider(),
        // Shell property columns are many; the menu lists the shown ones and
        // the dialog lists them all.
        for (final column in columns.orderedColumns)
          if (column != DetailsColumn.name &&
              column.isAvailable &&
              (!column.shell || columns.isVisible(column)))
            toggle(column.name, column.label(l10n), columns.isVisible(column)),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: ':customize',
          height: 36,
          child: Row(
            children: [
              const Icon(PhosphorIconsLight.columns, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.columnVisibilityTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: ':reset',
          height: 36,
          child: Row(
            children: [
              const Icon(PhosphorIconsLight.arrowCounterClockwise, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.columnResetLayout,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (value == null || !mounted) return;
    final current = _scope;
    if (current == null) return;
    if (value.startsWith('extra:')) {
      extras?.onToggle(value.substring(6));
    } else if (value == ':customize') {
      SharedActionBar.showColumnVisibilityDialog(
        context,
        currentVisibility: current.columns,
        onApply: current.commit,
      );
    } else if (value == ':reset') {
      current.commit(current.columns.resetLayout());
    } else if (DetailsColumn.values.asNameMap()[value] case final column?) {
      current.commit(
        current.columns.withColumn(column, !current.columns.isVisible(column)),
      );
    }
  }
}
