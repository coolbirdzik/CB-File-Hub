import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';

/// Shared menu tile: icon + title, dense, zero padding. Used by [VideoPlayerAdvancedMenu].
class _VideoPlayerMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? iconColor;
  final Color? titleColor;

  const _VideoPlayerMenuTile({
    required this.icon,
    required this.title,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final ic = iconColor ?? Colors.white;
    final tc = titleColor ?? Colors.white;
    return Row(
      children: [
        Icon(icon, color: ic, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(color: tc),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ],
    );
  }
}

/// Popup menu for video player: screenshot, audio tracks, subtitles, speed, PiP,
/// filters, sleep timer, settings. Callbacks are invoked on selection.
class VideoPlayerAdvancedMenu extends StatelessWidget {
  final VoidCallback? onScreenshot;
  final VoidCallback? onAudioTracks;
  final VoidCallback? onSubtitles;
  final VoidCallback? onSpeed;
  final VoidCallback? onPip;
  final VoidCallback? onFilters;
  final VoidCallback? onSleepTimer;
  final VoidCallback? onSettings;

  final bool hasSubtitles;
  final double playbackSpeed;
  final bool isPictureInPicture;
  final Duration? sleepDuration;

  const VideoPlayerAdvancedMenu({
    Key? key,
    this.onScreenshot,
    this.onAudioTracks,
    this.onSubtitles,
    this.onSpeed,
    this.onPip,
    this.onFilters,
    this.onSleepTimer,
    this.onSettings,
    this.hasSubtitles = false,
    this.playbackSpeed = 1.0,
    this.isPictureInPicture = false,
    this.sleepDuration,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(PhosphorIconsLight.dotsThreeVertical,
          color: Colors.white, size: 24),
      color: Colors.black.withValues(alpha: 0.9),
      tooltip: 'Advanced Controls',
      onSelected: (String value) {
        switch (value) {
          case 'screenshot':
            onScreenshot?.call();
            break;
          case 'audio_tracks':
            if (Platform.isWindows) onAudioTracks?.call();
            break;
          case 'subtitles':
            onSubtitles?.call();
            break;
          case 'speed':
            onSpeed?.call();
            break;
          case 'pip':
            onPip?.call();
            break;
          case 'filters':
            onFilters?.call();
            break;
          case 'sleep_timer':
            onSleepTimer?.call();
            break;
          case 'settings':
            onSettings?.call();
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'screenshot',
          child: _VideoPlayerMenuTile(
            icon: PhosphorIconsLight.camera,
            title: AppLocalizations.of(context)!.takeScreenshot,
          ),
        ),
        if (Platform.isWindows)
          const PopupMenuItem<String>(
            value: 'audio_tracks',
            child: _VideoPlayerMenuTile(
              icon: PhosphorIconsLight.musicNotes,
              title: 'Audio Tracks',
            ),
          ),
        PopupMenuItem<String>(
          value: 'subtitles',
          enabled: hasSubtitles,
          child: _VideoPlayerMenuTile(
            icon: PhosphorIconsLight.subtitles,
            title: 'Subtitles',
            iconColor: hasSubtitles ? Colors.white : Colors.grey,
            titleColor: hasSubtitles ? Colors.white : Colors.grey,
          ),
        ),
        PopupMenuItem<String>(
          value: 'speed',
          child: _VideoPlayerMenuTile(
            icon: PhosphorIconsLight.speedometer,
            title: 'Playback Speed (${playbackSpeed}x)',
          ),
        ),
        PopupMenuItem<String>(
          value: 'pip',
          child: _VideoPlayerMenuTile(
            icon: isPictureInPicture
                ? PhosphorIconsLight.pictureInpicture
                : PhosphorIconsLight.pictureInpicture,
            title: isPictureInPicture ? 'Exit PiP' : 'Picture in Picture',
          ),
        ),
        const PopupMenuItem<String>(
          value: 'filters',
          child: _VideoPlayerMenuTile(
            icon: PhosphorIconsLight.slidersHorizontal,
            title: 'Video Filters',
          ),
        ),
        PopupMenuItem<String>(
          value: 'sleep_timer',
          child: _VideoPlayerMenuTile(
            icon: PhosphorIconsLight.moon,
            title:
                sleepDuration != null ? 'Sleep Timer (Active)' : 'Sleep Timer',
            iconColor: sleepDuration != null ? Colors.orange : Colors.white,
            titleColor: sleepDuration != null ? Colors.orange : Colors.white,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'settings',
          child: _VideoPlayerMenuTile(
            icon: PhosphorIconsLight.gear,
            title: 'Video Settings',
          ),
        ),
      ],
    );
  }
}
