import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';

/// Shared background gesture and coordinate surface for desktop file layouts.
class DragSelectionRegion extends StatelessWidget {
  const DragSelectionRegion({
    super.key,
    required this.controller,
    required this.enabled,
    required this.child,
  });

  final TabbedFolderDragSelectionController controller;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    key: controller.stackKey,
    children: [
      GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: enabled
            ? (details) {
                final focused = FocusManager.instance.primaryFocus?.context;
                if (focused != null &&
                    (focused.widget is EditableText ||
                        focused.findAncestorWidgetOfExactType<EditableText>() !=
                            null)) {
                  return;
                }
                controller.start(details.localPosition);
              }
            : null,
        onPanUpdate: enabled
            ? (details) => controller.update(details.localPosition)
            : null,
        onPanEnd: enabled ? (_) => controller.end() : null,
        onPanCancel: enabled ? controller.end : null,
        child: child,
      ),
      controller.buildOverlay(),
    ],
  );
}
