import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/helpers/files/lazy_path_size_calculator.dart';
import 'package:cb_file_manager/ui/controllers/selection_tags_controller.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';
import 'package:cb_file_manager/ui/widgets/file_properties_details.dart';
import 'package:cb_file_manager/ui/widgets/selection_tag_editor.dart';

/// Each folder pane owns its selection and controller. The controller remains
/// mounted when collapsed so an in-flight write and its retry result survive.
class FilePropertiesPane extends StatefulWidget {
  const FilePropertiesPane({
    super.key,
    required this.child,
    required this.filePaths,
    required this.folderPaths,
    required this.visible,
    required this.height,
    required this.onHeightChanged,
    required this.onClose,
    this.bottomInset = 0,
    this.controller,
    this.panelFocusNode,
    this.paneLayoutBuilder,
    this.headerLeading,
  });

  final Widget child;
  final List<String> filePaths;
  final List<String> folderPaths;
  final bool visible;
  final double height;
  final ValueChanged<double> onHeightChanged;
  final VoidCallback onClose;
  final double bottomInset;
  final SelectionTagsController? controller;
  final FocusNode? panelFocusNode;
  final Widget Function(BuildContext context, Widget panel)? paneLayoutBuilder;
  final Widget? headerLeading;

  @override
  State<FilePropertiesPane> createState() => _FilePropertiesPaneState();
}

class _FilePropertiesPaneState extends State<FilePropertiesPane> {
  final _editorKey = GlobalKey();
  late final SelectionTagsController _tags;
  double? _dragHeight;
  List<String> _paths = [];
  Future<FileStat>? _stat;
  int? _size;
  int _generation = 0;
  bool _propertiesExpanded = false;

  @override
  void initState() {
    super.initState();
    _tags = widget.controller ?? SelectionTagsController();
    if (widget.visible) _select();
  }

  @override
  void didUpdateWidget(FilePropertiesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible &&
        (!oldWidget.visible ||
            !listEquals(oldWidget.filePaths, widget.filePaths) ||
            !listEquals(oldWidget.folderPaths, widget.folderPaths))) {
      _select();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _tags.removeListener(_changed);
  }

  // Older mounted panes registered this tear-off before tag updates moved to
  // ListenableBuilder. Hot reload preserves those listeners, so keep the
  // callback callable and detach it without rebuilding the surrounding panes.
  void _changed() {
    _tags.removeListener(_changed);
  }

  void _select() {
    _paths = [...widget.filePaths, ...widget.folderPaths]..sort();
    _stat = _paths.length == 1 ? FileStat.stat(_paths.single) : null;
    _size = null;
    unawaited(_tags.select(widget.filePaths));
    final generation = ++_generation;
    if (_paths.isNotEmpty &&
        (_paths.length > 1 || widget.folderPaths.isNotEmpty)) {
      unawaited(
        LazyPathSizeCalculator.calculate(
          filePaths: List.of(widget.filePaths),
          folderPaths: List.of(widget.folderPaths),
          isCancelled: () => !mounted || generation != _generation,
        ).then((value) {
          if (mounted && generation == _generation) {
            setState(() => _size = value);
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _generation++;
    _tags.removeListener(_changed);
    if (widget.controller == null) _tags.dispose();
    super.dispose();
  }

  /// Collapsed by default so the tag editor gets the room; the choice sticks
  /// across selections while the pane stays mounted.
  Widget _properties(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showSize = _paths.length > 1 || widget.folderPaths.isNotEmpty;
    return CbExpander(
      expanded: _propertiesExpanded,
      onExpansionChanged: (value) =>
          setState(() => _propertiesExpanded = value),
      headerPadding: const EdgeInsets.symmetric(
        horizontal: CbSpacing.sm,
        vertical: CbSpacing.xs + CbSpacing.xxs,
      ),
      contentPadding: const EdgeInsets.all(CbSpacing.sm),
      title: Text(l10n.properties),
      // What the selection is, readable without expanding.
      subtitle: Text(
        _paths.length == 1
            ? p.basename(_paths.single)
            : '${widget.filePaths.length} ${l10n.files}, ${widget.folderPaths.length} ${l10n.folders}',
      ),
      children: [
        if (_paths.length == 1)
          FilePropertiesDetails(
            filePath: _paths.single,
            statFuture: _stat!,
            dense: true,
          ),
        if (showSize)
          FilePropertyRow(
            label: l10n.fileSize,
            value: _size == null
                ? l10n.loading
                : FormatUtils.formatFileSizeExact(_size!),
          ),
      ],
    );
  }

  Widget _editor(BuildContext context, double browseMaxHeight) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final failure in _tags.failures)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CbSpacing.sm,
              0,
              CbSpacing.sm,
              CbSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.propertiesTagFailure}: ${failure.paths.length}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                Text(
                  failure.tags.join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Tooltip(
                  message: failure.paths.join('\n'),
                  child: TextButton(
                    onPressed: _tags.saving ? null : () => _tags.retry(failure),
                    child: Text(l10n.retry),
                  ),
                ),
              ],
            ),
          ),
        if (widget.folderPaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CbSpacing.sm,
              0,
              CbSpacing.sm,
              CbSpacing.sm,
            ),
            child: Text(
              l10n.propertiesFilesOnly,
              style: CbTypography.bodySm.copyWith(
                color: context.cbColors.textSecondary,
              ),
            ),
          ),
        if (widget.filePaths.isNotEmpty)
          SelectionTagEditor(
            key: _editorKey,
            controller: _tags,
            browseMaxHeight: browseMaxHeight,
          ),
      ],
    );
  }

  // A tag write only updates the panel contents, preserving the surrounding
  // dock layout and file/preview panes throughout saving and reloading.
  Widget _contents(BuildContext context) => ListenableBuilder(
    listenable: _tags,
    builder: (context, _) => _buildContents(context),
  );

  Widget _buildContents(BuildContext context) {
    if (_paths.isEmpty && _tags.failures.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)!.propertiesSelectFile),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // A narrow gutter so expander headers can show their hover fill;
        // everything else is inset to line up with their titles.
        padding: const EdgeInsets.fromLTRB(
          CbSpacing.xs,
          0,
          CbSpacing.xs,
          CbSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_paths.isNotEmpty) _properties(context),
            const SizedBox(height: CbSpacing.xs),
            // Once scrolled to, the browser fills most of the pane.
            _editor(context, math.max(320, constraints.maxHeight - 48)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.paneLayoutBuilder != null) {
      return widget.paneLayoutBuilder!(
        context,
        Focus(
          focusNode: widget.panelFocusNode,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      if (widget.headerLeading != null) widget.headerLeading!,
                      Expanded(
                        child: Text(
                          l10n.propertiesAndTags,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: l10n.hidePropertiesPane,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: widget.bottomInset),
                    child: _contents(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight / 2;
        final height = (_dragHeight ?? widget.height)
            .clamp(math.min(100.0, maxHeight), maxHeight)
            .toDouble();
        // Extremely short windows retain the list rather than overflowing chrome.
        final showPanel = widget.visible && height >= 60;
        return Column(
          children: [
            Expanded(child: widget.child),
            if (showPanel)
              SizedBox(
                height: height,
                child: Focus(
                  focusNode: widget.panelFocusNode,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(
                      children: [
                        Semantics(
                          label: l10n.propertiesResize,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeUpDown,
                            child: GestureDetector(
                              key: const ValueKey('properties-pane-resize'),
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragUpdate: (details) => setState(() {
                                _dragHeight =
                                    ((_dragHeight ?? height) - details.delta.dy)
                                        .clamp(
                                          math.min(100.0, maxHeight),
                                          maxHeight,
                                        )
                                        .toDouble();
                              }),
                              onVerticalDragEnd: (_) {
                                widget.onHeightChanged(_dragHeight ?? height);
                                setState(() => _dragHeight = null);
                              },
                              onVerticalDragCancel: () =>
                                  setState(() => _dragHeight = null),
                              child: SizedBox(
                                height: 6,
                                child: Center(
                                  child: Container(
                                    width: 40,
                                    height: 2,
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 32,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.propertiesAndTags,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  tooltip: l10n.hidePropertiesPane,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 20,
                                  ),
                                  onPressed: widget.onClose,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(child: _contents(context)),
                      ],
                    ),
                  ),
                ),
              ),
            if (showPanel) SizedBox(height: widget.bottomInset),
          ],
        );
      },
    );
  }
}
