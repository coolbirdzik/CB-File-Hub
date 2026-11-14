import 'package:flutter/material.dart';

/// Gesture target for the video surface. Controls and timecode fields sit
/// above it and keep their own gestures and text-editing context menus.
class VideoPlayerContextMenuRegion extends StatelessWidget {
  const VideoPlayerContextMenuRegion({
    super.key,
    required this.onRequested,
    required this.child,
  });

  final ValueChanged<Offset> onRequested;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onSecondaryTapUp: (details) => onRequested(details.globalPosition),
    onLongPressStart: (details) => onRequested(details.globalPosition),
    child: child,
  );
}
