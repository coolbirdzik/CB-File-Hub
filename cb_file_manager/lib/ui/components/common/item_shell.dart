import 'package:flutter/material.dart';
import 'package:cb_file_manager/ui/components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/ui/utils/item_interaction_style.dart';

/// A reusable shell widget that provides common hover, selection, and gesture handling
/// for list/grid items. This encapsulates the pattern used across file items,
/// folder items, and trash items.
///
/// Usage:
/// ```dart
/// ItemShell(
/// isSelected: isSelected,
/// isSelectionMode: isSelectionMode,
/// isDesktopMode: isDesktopMode,
/// onTap: onTap,
/// onDoubleTap: onDoubleTap,
/// onSecondaryTapUp: (details) => showContextMenu(details.globalPosition),
/// onToggleSelection: onToggleSelection,
/// onEnterSelectionMode: onEnterSelectionMode,
/// child: MyItemContent(),
/// )
/// ```
class ItemShell extends StatefulWidget {
  final Widget child;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isDesktopMode;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapUpDetails)? onSecondaryTapUp;
  final VoidCallback? onToggleSelection;
  final VoidCallback? onEnterSelectionMode;
  final bool enableSelectionHighlight;

  const ItemShell({
    super.key,
    required this.child,
    required this.isSelected,
    required this.isSelectionMode,
    this.isDesktopMode = false,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapUp,
    this.onToggleSelection,
    this.onEnterSelectionMode,
    this.enableSelectionHighlight = true,
  });

  @override
  State<ItemShell> createState() => _ItemShellState();
}

class _ItemShellState extends State<ItemShell> {
  bool _isHovering = false;

  void _handleTap() {
    if (widget.isSelectionMode) {
      widget.onToggleSelection?.call();
    } else {
      widget.onTap?.call();
    }
  }

  void _handleDoubleTap() {
    if (!widget.isSelectionMode) {
      widget.onDoubleTap?.call();
    }
  }

  void _handleLongPress() {
    if (!widget.isSelectionMode) {
      widget.onEnterSelectionMode?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool showHighlight =
        widget.enableSelectionHighlight &&
        (widget.isSelected || (_isHovering && widget.isSelectionMode));

    final Color backgroundColor = ItemInteractionStyle.backgroundColor(
      theme: theme,
      isDesktopMode: widget.isDesktopMode,
      isSelected: widget.isSelected,
      isHovering: _isHovering,
    );

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovering = true);
      },
      onExit: (_) {
        setState(() => _isHovering = false);
      },
      cursor: SystemMouseCursors.click,
      child: OptimizedInteractionLayer(
        onTap: _handleTap,
        onDoubleTap: widget.onDoubleTap == null ? null : _handleDoubleTap,
        onLongPress: _handleLongPress,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: Container(
          color: showHighlight ? backgroundColor : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Shell specifically for list items (e.g., file list rows)
/// Provides list-specific styling and behavior
class ListItemShell extends StatefulWidget {
  final Widget child;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isDesktopMode;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapUpDetails)? onSecondaryTapUp;
  final VoidCallback? onToggleSelection;
  final VoidCallback? onEnterSelectionMode;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;

  const ListItemShell({
    super.key,
    required this.child,
    required this.isSelected,
    required this.isSelectionMode,
    this.isDesktopMode = false,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapUp,
    this.onToggleSelection,
    this.onEnterSelectionMode,
    this.padding = const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
    this.borderRadius,
  });

  @override
  State<ListItemShell> createState() => _ListItemShellState();
}

class _ListItemShellState extends State<ListItemShell> {
  bool _isHovering = false;

  void _handleTap() {
    if (widget.isSelectionMode) {
      widget.onToggleSelection?.call();
    } else {
      widget.onTap?.call();
    }
  }

  void _handleDoubleTap() {
    if (!widget.isSelectionMode) {
      widget.onDoubleTap?.call();
    }
  }

  void _handleLongPress() {
    if (!widget.isSelectionMode) {
      widget.onEnterSelectionMode?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color backgroundColor = ItemInteractionStyle.backgroundColor(
      theme: theme,
      isDesktopMode: widget.isDesktopMode,
      isSelected: widget.isSelected,
      isHovering: _isHovering,
    );

    final decoration = widget.borderRadius != null
        ? BoxDecoration(
            color: backgroundColor,
            borderRadius: widget.borderRadius,
          )
        : BoxDecoration(color: backgroundColor);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: OptimizedInteractionLayer(
        onTap: _handleTap,
        onDoubleTap: widget.onDoubleTap == null ? null : _handleDoubleTap,
        onLongPress: _handleLongPress,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: Container(
          decoration: decoration,
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Shell specifically for grid items (e.g., file grid cells)
/// Provides grid-specific styling and overlay behavior
class GridItemShell extends StatefulWidget {
  final Widget child;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isDesktopMode;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapUpDetails)? onSecondaryTapUp;
  final VoidCallback? onToggleSelection;
  final VoidCallback? onEnterSelectionMode;

  const GridItemShell({
    super.key,
    required this.child,
    required this.isSelected,
    required this.isSelectionMode,
    this.isDesktopMode = false,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapUp,
    this.onToggleSelection,
    this.onEnterSelectionMode,
  });

  @override
  State<GridItemShell> createState() => _GridItemShellState();
}

class _GridItemShellState extends State<GridItemShell> {
  bool _isHovering = false;

  void _handleTap() {
    if (widget.isSelectionMode) {
      widget.onToggleSelection?.call();
    } else {
      widget.onTap?.call();
    }
  }

  void _handleDoubleTap() {
    if (!widget.isSelectionMode) {
      widget.onDoubleTap?.call();
    }
  }

  void _handleLongPress() {
    if (!widget.isSelectionMode) {
      widget.onEnterSelectionMode?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Whole-cell selection fill + border, matching the folder/file grid items so
    // selection reads consistently without painting an overlay over the
    // thumbnail itself.
    final Color cellBackgroundColor = ItemInteractionStyle.backgroundColor(
      theme: theme,
      isDesktopMode: widget.isDesktopMode,
      isSelected: widget.isSelected,
      isHovering: _isHovering,
    );
    final Color primary = theme.colorScheme.primary;
    final Color cellBorderColor = widget.isSelected
        ? primary
        : (_isHovering && widget.isDesktopMode
              ? primary.withValues(alpha: 0.4)
              : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: OptimizedInteractionLayer(
        onTap: _handleTap,
        onDoubleTap: widget.onDoubleTap == null ? null : _handleDoubleTap,
        onLongPress: _handleLongPress,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: Container(
          decoration: BoxDecoration(
            color: cellBackgroundColor,
            border: cellBorderColor != Colors.transparent
                ? Border.all(color: cellBorderColor, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
