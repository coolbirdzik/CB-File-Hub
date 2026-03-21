import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

class SelectionSummaryTooltip extends StatefulWidget {
  final int selectedFileCount;
  final int selectedFolderCount;
  final List<String> selectedFilePaths;
  final List<String> selectedFolderPaths;

  const SelectionSummaryTooltip({
    Key? key,
    required this.selectedFileCount,
    required this.selectedFolderCount,
    required this.selectedFilePaths,
    required this.selectedFolderPaths,
  }) : super(key: key);

  @override
  State<SelectionSummaryTooltip> createState() =>
      _SelectionSummaryTooltipState();
}

class _SelectionSummaryTooltipState extends State<SelectionSummaryTooltip> {
  int _totalSize = 0;

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
            oldWidget.selectedFolderPaths, widget.selectedFolderPaths)) {
      _calculateSize();
    }
  }

  Future<void> _calculateSize() async {
    if (widget.selectedFileCount == 0 && widget.selectedFolderCount == 0) {
      if (mounted) setState(() => _totalSize = 0);
      return;
    }

    int size = 0;

    // We copy the list to ensure we are working on a stable list even if widget updates
    final filesToCheck = List<String>.from(widget.selectedFilePaths);

    for (final path in filesToCheck) {
      // Check if widget was updated while we were calculating
      if (!mounted) return;

      try {
        final stat = await File(path).stat();
        size += stat.size;
      } catch (e) {
        // Ignore errors
      }
    }

    if (mounted) {
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

    if (widget.selectedFileCount > 0) {
      text += '   |   ${FormatUtils.formatFileSize(_totalSize)}';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202020) : const Color(0xFFF9F9F9),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
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
