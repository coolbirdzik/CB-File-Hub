import 'package:flutter/material.dart';

/// A single action row at every width, so breakpoint changes cannot drop or
/// duplicate the cut/menu actions. Only the secondary controls collapse.
class VideoPlayerDesktopToolbar extends StatelessWidget {
  const VideoPlayerDesktopToolbar({
    super.key,
    required this.playPause,
    required this.seekControl,
    required this.position,
    required this.duration,
    required this.menu,
    this.cut,
    this.playlist,
    this.volume,
    this.subtitles,
    this.fullscreen,
  });

  final Widget playPause, seekControl, position, duration, menu;
  final Widget? cut, playlist, volume, subtitles, fullscreen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final showTimes = constraints.maxWidth >= 520;
      final showSecondary = constraints.maxWidth >= 760;
      return Row(
        children: [
          playPause,
          const SizedBox(width: 8),
          if (showTimes) ...[position, const SizedBox(width: 8)],
          Expanded(child: seekControl),
          if (showTimes) ...[
            const SizedBox(width: 8),
            duration,
            const SizedBox(width: 8),
          ],
          ?cut,
          if (constraints.maxWidth >= 400) ...[?playlist, ?subtitles],
          if (showSecondary) ?volume,
          menu,
          ?fullscreen,
        ],
      );
    },
  );
}
