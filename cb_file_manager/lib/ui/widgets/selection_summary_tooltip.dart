import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/primitives/cb_decorations.dart';
import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'package:cb_file_manager/helpers/files/lazy_path_size_calculator.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

class SelectionSummaryTooltip extends StatefulWidget {
  /// Fixed bar height, so content drawn beneath the overlay (e.g. the preview
  /// pane) can reserve exactly this much space.
  static const double height = 30;

  /// Whether the bar renders anything for this selection. Hosts only mount it
  /// on desktop while in selection mode; an empty selection renders nothing.
  static bool isVisibleFor(SelectionState selectionState) =>
      selectionState.isSelectionMode &&
      (selectionState.selectedFilePaths.isNotEmpty ||
          selectionState.selectedFolderPaths.isNotEmpty);

  final int selectedFileCount;
  final int selectedFolderCount;
  final List<String> selectedFilePaths;
  final List<String> selectedFolderPaths;

  const SelectionSummaryTooltip({
    super.key,
    required this.selectedFileCount,
    required this.selectedFolderCount,
    required this.selectedFilePaths,
    required this.selectedFolderPaths,
  });

  @override
  State<SelectionSummaryTooltip> createState() =>
      _SelectionSummaryTooltipState();
}

class _SelectionSummaryTooltipState extends State<SelectionSummaryTooltip> {
  int? _totalSize;
  int _calculationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _calculateSize();
  }

  @override
  void didUpdateWidget(SelectionSummaryTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.selectedFilePaths, widget.selectedFilePaths) ||
        !listEquals(
          oldWidget.selectedFolderPaths,
          widget.selectedFolderPaths,
        )) {
      _calculateSize();
    }
  }

  Future<void> _calculateSize() async {
    final generation = ++_calculationGeneration;
    if (widget.selectedFileCount == 0 && widget.selectedFolderCount == 0) {
      if (mounted) setState(() => _totalSize = null);
      return;
    }

    final filesToCheck = List<String>.from(widget.selectedFilePaths);
    final foldersToCheck = List<String>.from(widget.selectedFolderPaths);
    setState(() => _totalSize = null);

    final size = await LazyPathSizeCalculator.calculate(
      filePaths: filesToCheck,
      folderPaths: foldersToCheck,
      isCancelled: () => !mounted || generation != _calculationGeneration,
    );

    if (mounted && generation == _calculationGeneration) {
      setState(() {
        _totalSize = size;
      });
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

    final totalSize = _totalSize;
    text += totalSize == null
        ? '   |   Calculating size...'
        : '   |   ${FormatUtils.formatFileSize(totalSize)}';

    return Container(
      width: double.infinity,
      height: SelectionSummaryTooltip.height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      margin: EdgeInsets.zero,
      decoration: CbDecorations.bar(context),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }
}
