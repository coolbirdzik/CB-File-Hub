import 'package:flutter/widgets.dart';

/// Converts a drag-selection rectangle from its local interaction surface to
/// the global coordinate space used by item bounds registered with
/// [RenderBox.localToGlobal].
Rect dragSelectionRectToGlobal(Rect localRect, RenderBox? interactionSurface) {
  if (interactionSurface == null || !interactionSurface.attached) {
    return localRect;
  }

  return localRect.shift(interactionSurface.localToGlobal(Offset.zero));
}
