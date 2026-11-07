import 'dart:ui';

/// A label and local rectangle are not an identity: sibling tabs, toolbar
/// buttons and file rows routinely share both. Only compare replacements
/// occupying the same slot under a surviving semantic parent.
bool isSameSemanticsSlot({
  required String oldLabel,
  required String newLabel,
  required Rect oldRect,
  required Rect newRect,
  required int? oldParent,
  required int? newParent,
}) =>
    oldParent != null &&
    oldParent == newParent &&
    oldLabel == newLabel &&
    oldRect == newRect;
