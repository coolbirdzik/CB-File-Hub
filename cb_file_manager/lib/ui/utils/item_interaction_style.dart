import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_tokens.dart';
import 'package:cb_file_manager/design_system/primitives/cb_decorations.dart';
import 'package:cb_file_manager/design_system/tokens/cb_geometry_tokens.dart';
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

  /// Background of a file/folder row or tile.
  ///
  /// Flat: selection and hover are carried entirely by the fill — no item
  /// draws an outline. Hover is a neutral wash; selection is the accent
  /// [CbDecorations.selectionFill], a clearly stronger step than hover so it
  /// stays unmistakable in a dense listing.
  static Color backgroundColor({
    required ThemeData theme,
    required bool isDesktopMode,
    required bool isSelected,
    required bool isHovering,
  }) {
    final tokens = theme.cb;
    final bool hovered = isHovering && isDesktopMode;
    if (isSelected) {
      return CbDecorations.selectionFill(tokens, hovered: hovered);
    }
    if (hovered) return tokens.colors.fillHover;
    return Colors.transparent;
  }

  /// Background of a grid tile: the neutral hover fill only. Selection is
  /// painted on top by [gridForeground].
  static Color gridBackgroundColor({
    required ThemeData theme,
    required bool isDesktopMode,
    required bool isSelected,
    required bool isHovering,
  }) {
    return backgroundColor(
      theme: theme,
      isDesktopMode: isDesktopMode,
      isSelected: false,
      isHovering: isHovering && !isSelected,
    );
  }

  /// Foreground of a grid tile: the selection wash painted *over* the whole
  /// cell. A photo or video thumbnail fills the cell edge to edge and would
  /// hide a background fill, leaving only the name band tinted.
  ///
  /// Never null: [Container] only adds its foreground [DecoratedBox] when a
  /// decoration is given, so toggling null on selection changed the tile's
  /// depth and remounted everything below it. A video thumbnail then
  /// re-read its cache asynchronously and blinked for a frame.
  static BoxDecoration gridForeground(
    BuildContext context, {
    required bool isDesktopMode,
    required bool isSelected,
    required bool isHovering,
    double radius = CbRadii.md,
  }) {
    if (!isSelected) return const BoxDecoration();
    return CbDecorations.selectedOverlay(
      context,
      radius: radius,
      hovered: isHovering && isDesktopMode,
    );
  }
}
