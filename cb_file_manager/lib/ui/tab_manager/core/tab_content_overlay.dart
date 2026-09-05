import 'package:flutter/widgets.dart';

/// Keeps a tab's portals and popovers in the same visibility/semantics subtree
/// as their anchors. In particular, Material Slider keeps an OverlayPortal
/// open even when its value indicator is not painted. If that portal targets
/// the app overlay, hiding a tab can serialize an orphan accessibility node.
class TabContentOverlay extends StatefulWidget {
  const TabContentOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<TabContentOverlay> createState() => _TabContentOverlayState();
}

class _TabContentOverlayState extends State<TabContentOverlay> {
  late final OverlayEntry _content = OverlayEntry(
    builder: (context) => widget.child,
  );

  @override
  void didUpdateWidget(TabContentOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) _content.markNeedsBuild();
  }

  @override
  void dispose() {
    _content.remove();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_content]);
}
