import 'dart:ui' show Offset, Rect;

import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';

class DesktopTabDragData {
  final String tabId;
  final WindowTabPayload tab;

  const DesktopTabDragData({required this.tabId, required this.tab});
}

/// Where a tab being pulled out of the strip is, for the drag preview and the
/// window it moves to. Logical pixels, relative to this window's content.
class TabDetachGeometry {
  /// Where the pointer sits in the new window, so the tab stays under it.
  final Offset windowAnchor;

  /// The dragged tab as drawn now.
  final Rect tabRect;

  /// Where the first tab sits in a window whose strip is not scrolled.
  final Offset firstTabOrigin;

  /// Bottom edge of the tab strip.
  final double stripBottom;

  const TabDetachGeometry({
    required this.windowAnchor,
    required this.tabRect,
    required this.firstTabOrigin,
    required this.stripBottom,
  });
}
