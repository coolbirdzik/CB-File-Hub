import 'package:flutter/material.dart';

import 'package:cb_file_manager/design_system/primitives/cb_inline_rename.dart';

import '../controllers/inline_rename_controller.dart';

/// The in-place rename field for a file or folder row.
///
/// Thin adapter over [CbInlineRenameField]: it binds the controller and focus
/// node owned by [InlineRenameController]. New items commit on blur, while
/// ordinary renames retain the existing cancel-on-blur behavior.
class InlineRenameField extends StatelessWidget {
  final InlineRenameController controller;
  final Future<void> Function() onCommit;
  final VoidCallback onCancel;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final int maxLines;

  const InlineRenameField({
    super.key,
    required this.controller,
    required this.onCommit,
    required this.onCancel,
    this.textStyle,
    this.textAlign = TextAlign.center,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final textController = controller.textController;
    final focusNode = controller.focusNode;

    // The controller tears these down a frame after a rename ends, so a stale
    // build can still reach here with nothing to edit.
    if (textController == null || focusNode == null) {
      return const SizedBox.shrink();
    }
    // The previous item's focus can leave while the next editor is mounting.
    // Its callbacks must never commit or cancel the new session.
    void commit() {
      if (identical(controller.textController, textController)) onCommit();
    }

    void cancel() {
      if (identical(controller.textController, textController)) onCancel();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Width: bounded → use it; infinite → expand (infinity is ok for
        // width). Height is deliberately left alone: `maxLines` already caps
        // how tall the field can get, and an arbitrary pixel clamp on top of
        // that would cut off the very name the user is editing.
        return ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 40,
            maxWidth: constraints.hasBoundedWidth
                ? constraints.maxWidth
                : double.infinity,
            minHeight: 24,
          ),
          child: CbInlineRenameField(
            controller: textController,
            focusNode: focusNode,
            onCommit: commit,
            onCancel: cancel,
            onBlur: controller.commitOnBlur ? commit : cancel,
            lockedSuffix: controller.lockedSuffix,
            textStyle: textStyle,
            textAlign: textAlign,
            maxLines: maxLines,
            // Always dense. Grid tiles give the name a fixed-height band
            // (40px, 58px with tags) sized for the plain label, so the editor
            // that replaces it has that much room and no more.
            dense: true,
          ),
        );
      },
    );
  }
}
