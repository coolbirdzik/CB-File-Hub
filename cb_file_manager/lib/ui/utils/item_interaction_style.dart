import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';

class ItemInteractionStyle {
  /// Check if a file/folder is in the cut clipboard (should appear dimmed)
  static bool isBeingCut(String path) {
    final ops = FileOperations();
    if (!ops.isCutOperation) return false;
    return ops.clipboardItems.any((item) => item.path == path);
  }

  /// The opacity to apply when an item is being cut
  static const double cutOpacity = 0.5;

  static Color backgroundColor({
    required ThemeData theme,
    required bool isDesktopMode,
    required bool isSelected,
    required bool isHovering,
  }) {
    if (isSelected) {
      return theme.colorScheme.primaryContainer.withValues(alpha: 0.7);
    }

    if (isHovering && isDesktopMode) {
      final bool isDarkMode = theme.brightness == Brightness.dark;
      return isDarkMode ? Colors.grey[800]! : Colors.grey[100]!;
    }

    return Colors.transparent;
  }
}
