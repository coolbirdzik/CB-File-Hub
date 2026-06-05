import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'tree_node.dart';

/// Internal flat-row record used by [GenericTreeView].
///
/// Special node ids ([_loadingId], [_errorId], [_truncatedId]) are
/// rendered as inline placeholder rows that do not represent a real
/// caller node.
class FlatTreeRow<T> {
  final TreeNode<T>? node;
  final int depth;
  final FlatRowKind kind;

  /// Used for the truncated-tail row (`… and N more`).
  final int? extraCount;

  /// Parent of a placeholder row, so the tree can implement retry / load
  /// more on the right node.
  final TreeNode<T>? parent;

  const FlatTreeRow({
    required this.depth,
    required this.kind,
    this.node,
    this.extraCount,
    this.parent,
  });
}

enum FlatRowKind { node, loading, error, truncated }

/// Internal row widget shared by all tree rows.
///
/// Renders the indentation and expand chevron column, then defers to
/// [child] for the user-supplied content. Hover, tap, double-tap and
/// secondary tap are all dispatched here.
class TreeRowShell<T> extends StatefulWidget {
  final TreeNode<T> node;
  final int depth;
  final double indentPerDepth;
  final bool hasExpandableChildren;
  final bool isSelected;
  final bool isFocused;
  final Widget child;
  final VoidCallback onToggleExpansion;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset globalPosition)? onSecondary;

  const TreeRowShell({
    Key? key,
    required this.node,
    required this.depth,
    required this.indentPerDepth,
    required this.hasExpandableChildren,
    required this.isSelected,
    required this.isFocused,
    required this.child,
    required this.onToggleExpansion,
    this.onTap,
    this.onDoubleTap,
    this.onSecondary,
  }) : super(key: key);

  @override
  State<TreeRowShell<T>> createState() => _TreeRowShellState<T>();
}

class _TreeRowShellState<T> extends State<TreeRowShell<T>> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = widget.indentPerDepth * widget.depth;

    Color? background;
    if (widget.isSelected) {
      background = theme.colorScheme.primary.withValues(alpha: 0.16);
    } else if (widget.isFocused) {
      background = theme.colorScheme.primary.withValues(alpha: 0.10);
    } else if (_hovering) {
      background = theme.colorScheme.primary.withValues(alpha: 0.06);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapUp: widget.onSecondary == null
            ? null
            : (details) => widget.onSecondary!(details.globalPosition),
        onLongPressStart: widget.onSecondary == null
            ? null
            : (details) => widget.onSecondary!(details.globalPosition),
        child: Container(
          color: background ?? Colors.transparent,
          padding: EdgeInsets.only(left: 12 + indent, right: 8),
          child: Row(
            children: [
              // Expand chevron column — fixed width, separately tappable.
              SizedBox(
                width: 20,
                child: widget.hasExpandableChildren
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onToggleExpansion,
                        child: Icon(
                          widget.node.isExpanded
                              ? PhosphorIconsLight.caretDown
                              : PhosphorIconsLight.caretRight,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline placeholder row (loading / error / truncated tail).
class TreePlaceholderRow extends StatelessWidget {
  final FlatRowKind kind;
  final int depth;
  final double indentPerDepth;
  final int? extraCount;
  final VoidCallback? onTap;

  const TreePlaceholderRow({
    Key? key,
    required this.kind,
    required this.depth,
    required this.indentPerDepth,
    this.extraCount,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = indentPerDepth * depth;

    Widget content;
    switch (kind) {
      case FlatRowKind.loading:
        content = Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.4),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading…',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
        break;
      case FlatRowKind.error:
        content = Row(
          children: [
            Icon(
              PhosphorIconsLight.warning,
              size: 14,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Failed to load. Tap to retry.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.error,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
        break;
      case FlatRowKind.truncated:
        content = Text(
          '… and ${extraCount ?? 0} more, click to load',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.primary,
          ),
        );
        break;
      case FlatRowKind.node:
        content = const SizedBox.shrink();
        break;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(left: 12 + indent + 20, right: 8),
        alignment: Alignment.centerLeft,
        child: content,
      ),
    );
  }
}
