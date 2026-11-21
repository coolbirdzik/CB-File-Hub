import 'dart:async';
import 'dart:io';

import 'package:cb_native/cb_native.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cb_file_manager/design_system/primitives/cb_decorations.dart';
import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/files/lazy_path_size_calculator.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

class SelectionSummaryTooltip extends StatefulWidget {
  /// Fixed bar height, so content drawn beneath the overlay (e.g. the preview
  /// pane) can reserve exactly this much space.
  static const double height = 30;

  /// Whether the bar renders anything for this selection.
  static bool isVisibleFor(SelectionState selectionState) =>
      selectionState.isSelectionMode &&
      (selectionState.selectedFilePaths.isNotEmpty ||
          selectionState.selectedFolderPaths.isNotEmpty);

  final int selectedFileCount;
  final int selectedFolderCount;
  final List<String> selectedFilePaths;
  final List<String> selectedFolderPaths;
  final bool showTotalSize;
  final bool allowWrap;

  /// Indexed collections can supply the same cached size their columns use.
  final int? totalSizeOverride;

  const SelectionSummaryTooltip({
    super.key,
    required this.selectedFileCount,
    required this.selectedFolderCount,
    required this.selectedFilePaths,
    required this.selectedFolderPaths,
    this.showTotalSize = true,
    this.totalSizeOverride,
    this.allowWrap = false,
  });

  SelectionSummaryTooltip.forSelection(
    SelectionState selection, {
    this.totalSizeOverride,
    this.allowWrap = false,
    super.key,
  }) : selectedFileCount = selection.selectedFilePaths.length,
       selectedFolderCount = selection.selectedFolderPaths.length,
       selectedFilePaths = selection.selectedFilePaths.toList(),
       selectedFolderPaths = selection.selectedFolderPaths.toList(),
       showTotalSize = true;

  @override
  State<SelectionSummaryTooltip> createState() =>
      _SelectionSummaryTooltipState();
}

class _SelectionSummaryTooltipState extends State<SelectionSummaryTooltip> {
  int? _totalSize;
  DateTime? _dateCreated;
  int _calculationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _refreshSummary();
  }

  @override
  void didUpdateWidget(SelectionSummaryTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showTotalSize != widget.showTotalSize ||
        oldWidget.totalSizeOverride != widget.totalSizeOverride ||
        !listEquals(oldWidget.selectedFilePaths, widget.selectedFilePaths) ||
        !listEquals(
          oldWidget.selectedFolderPaths,
          widget.selectedFolderPaths,
        )) {
      _refreshSummary();
    }
  }

  Future<void> _refreshSummary() async {
    final generation = ++_calculationGeneration;
    _dateCreated = null;
    _totalSize = widget.totalSizeOverride;

    if (widget.selectedFilePaths.length == 1 &&
        widget.selectedFolderPaths.isEmpty) {
      unawaited(_readCreationDate(widget.selectedFilePaths.single, generation));
    }

    if (_totalSize != null ||
        !widget.showTotalSize ||
        (widget.selectedFileCount == 0 && widget.selectedFolderCount == 0)) {
      return;
    }

    final size = await LazyPathSizeCalculator.calculate(
      filePaths: List<String>.of(widget.selectedFilePaths),
      folderPaths: List<String>.of(widget.selectedFolderPaths),
      isCancelled: () => !mounted || generation != _calculationGeneration,
    );

    if (mounted && generation == _calculationGeneration) {
      setState(() {
        _totalSize = size;
      });
    }
  }

  Future<void> _readCreationDate(String path, int generation) async {
    DateTime? created;
    if (Platform.isWindows) {
      // On Windows, FileStat.changed is the file's creation time.
      final stat = await FileStat.stat(path);
      if (stat.type == FileSystemEntityType.file) created = stat.changed;
    } else {
      created = await NativeFs.fileCreated(path);
    }
    if (mounted && generation == _calculationGeneration && created != null) {
      setState(() => _dateCreated = created);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show if there is a selection
    if (widget.selectedFileCount == 0 && widget.selectedFolderCount == 0) {
      return const SizedBox.shrink();
    }

    String text = '';
    if (widget.selectedFolderCount > 0 && widget.selectedFileCount > 0) {
      text =
          '${widget.selectedFileCount} files, ${widget.selectedFolderCount} folders selected';
    } else if (widget.selectedFileCount > 0) {
      text = '${widget.selectedFileCount} items selected';
    } else {
      text = '${widget.selectedFolderCount} items selected';
    }

    if (widget.showTotalSize) {
      final totalSize = _totalSize;
      text += totalSize == null
          ? '   |   Calculating size...'
          : '   |   ${FormatUtils.formatFileSize(totalSize)}';
    }

    final dateCreated = _dateCreated;
    if (dateCreated != null) {
      final label = AppLocalizations.of(context)?.fileCreated ?? 'Created';
      text += '   |   $label: ${dateCreated.toString().split('.').first}';
    }

    return Container(
      width: double.infinity,
      height: widget.allowWrap ? null : SelectionSummaryTooltip.height,
      constraints: const BoxConstraints(
        minHeight: SelectionSummaryTooltip.height,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: widget.allowWrap ? 6 : 0,
      ),
      margin: EdgeInsets.zero,
      decoration: CbDecorations.bar(context),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        heightFactor: 1,
        child: Text(
          text,
          maxLines: widget.allowWrap ? null : 1,
          overflow: widget.allowWrap
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }
}
