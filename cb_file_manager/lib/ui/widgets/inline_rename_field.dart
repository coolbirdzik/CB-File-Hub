import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/inline_rename_controller.dart';

/// Inline text field for renaming files/folders on desktop.
class InlineRenameField extends StatefulWidget {
  final InlineRenameController controller;
  final Future<void> Function() onCommit;
  final VoidCallback onCancel;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final int maxLines;

  const InlineRenameField({
    Key? key,
    required this.controller,
    required this.onCommit,
    required this.onCancel,
    this.textStyle,
    this.textAlign = TextAlign.center,
    this.maxLines = 1,
  }) : super(key: key);

  @override
  State<InlineRenameField> createState() => _InlineRenameFieldState();
}

class _InlineRenameFieldState extends State<InlineRenameField> {
  @override
  void initState() {
    super.initState();
    widget.controller.focusNode?.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.controller.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.controller.focusNode != null &&
        !widget.controller.focusNode!.hasFocus) {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surface = theme.colorScheme.surface;
    final focusedSurface = theme.colorScheme.surfaceContainer;
    final outline = theme.colorScheme.outline;
    final outlineVariant = theme.colorScheme.outlineVariant;
    final onSurface = theme.colorScheme.onSurface;

    final effectiveStyle = widget.textStyle ??
        theme.textTheme.bodySmall?.copyWith(fontSize: 13, color: onSurface);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Width: bounded → use it; infinite → expand (infinity is ok for width).
        // Height: bounded → use it; infinite → clamp to 60px (2-line field).
        final BoxConstraints ec = BoxConstraints(
          minWidth: 40,
          maxWidth: constraints.hasBoundedWidth
              ? constraints.maxWidth
              : double.infinity,
          minHeight: 24,
          maxHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 60,
        );

        return ConstrainedBox(
          constraints: ec,
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  widget.onCancel();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.enter) {
                  widget.onCommit();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: widget.controller.textController!,
              focusNode: widget.controller.focusNode!,
              style: effectiveStyle,
              textAlign: widget.textAlign,
              maxLines: widget.maxLines,
              autofocus: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                filled: true,
                fillColor: WidgetStateColor.resolveWith((states) {
                  return states.contains(WidgetState.focused)
                      ? focusedSurface
                      : surface;
                }),
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: outlineVariant,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: outlineVariant,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: outline, width: 1),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              cursorColor: primary,
              cursorWidth: 2,
              onSubmitted: (_) => widget.onCommit(),
            ),
          ),
        );
      },
    );
  }
}
