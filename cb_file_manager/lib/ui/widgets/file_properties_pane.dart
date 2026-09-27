import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
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

  @override
  State<FilePropertiesPane> createState() => _FilePropertiesPaneState();
}

class _FilePropertiesPaneState extends State<FilePropertiesPane> {
  late final SelectionTagsController _tags;
  double? _dragHeight;
  List<String> _paths = [];
  Future<FileStat>? _stat;
  int? _size;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _tags = widget.controller ?? SelectionTagsController();
    _tags.addListener(_changed);
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

  void _changed() {
    if (mounted) setState(() {});
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

  Widget _properties(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.properties, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_paths.length == 1)
          FilePropertiesDetails(filePath: _paths.single, statFuture: _stat!),
        if (_paths.length > 1)
          Text(
            '${widget.filePaths.length} ${l10n.files}, ${widget.folderPaths.length} ${l10n.folders}',
          ),
        if (_paths.length > 1 || widget.folderPaths.isNotEmpty)
          Text(
            '${l10n.fileSize}: ${_size == null ? l10n.loading : FormatUtils.formatFileSizeExact(_size!)}',
          ),
      ],
    );
  }

  Widget _editor(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final failure in _tags.failures)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l10n.propertiesFilesOnly),
          ),
        if (widget.filePaths.isNotEmpty) SelectionTagEditor(controller: _tags),
      ],
    );
  }

  Widget _contents(BuildContext context) {
    if (_paths.isEmpty && _tags.failures.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)!.propertiesSelectFile),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _properties(context),
                const SizedBox(height: 16),
                _editor(context),
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: math.min(340, constraints.maxWidth * .34),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: _properties(context),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: _editor(context),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
