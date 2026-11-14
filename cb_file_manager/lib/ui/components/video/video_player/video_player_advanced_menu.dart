import 'dart:io';

import 'package:cb_file_manager/design_system/primitives/cb_popover_transition.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/translation_helper.dart';

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
  final VoidCallback? onPlayPause;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;
  final VoidCallback? onMute;
  final VoidCallback? onFullscreen;
  final VoidCallback? onLosslessCut;
  final VoidCallback? onMenuOpened;
  final VoidCallback? onMenuClosed;
  final bool isPlaying;
  final bool isMuted;
  final bool isFullscreen;
  final bool losslessCutEnabled;
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
    super.key,
    this.onPlayPause,
    this.onRewind,
    this.onForward,
    this.onMute,
    this.onFullscreen,
    this.onLosslessCut,
    this.onMenuOpened,
    this.onMenuClosed,
    this.isPlaying = false,
    this.isMuted = false,
    this.isFullscreen = false,
    this.losslessCutEnabled = true,
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
  });

  void select(String value) {
    switch (value) {
      case 'play_pause':
        onPlayPause?.call();
        break;
      case 'rewind':
        onRewind?.call();
        break;
      case 'forward':
        onForward?.call();
        break;
      case 'mute':
        onMute?.call();
        break;
      case 'fullscreen':
        onFullscreen?.call();
        break;
      case 'lossless_cut':
        onLosslessCut?.call();
        break;
      case 'screenshot':
        onScreenshot?.call();
        break;
      case 'audio_tracks':
        onAudioTracks?.call();
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
  }

  Future<void> showAt(
    BuildContext context,
    Offset globalPosition, {
    bool Function()? isCurrent,
  }) async {
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) return;
    final position = overlay.globalToLocal(globalPosition);
    final value = await showMenu<String>(
      context: context,
      semanticLabel: context.tr.vpAdvancedControls,
      popUpAnimationStyle: CbPopoverTransition.menuStyleOf(context),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      color: Colors.black.withValues(alpha: 0.95),
      items: buildItems(context),
    );
    if (context.mounted && value != null && (isCurrent?.call() ?? true)) {
      select(value);
    }
  }

  List<PopupMenuEntry<String>> buildItems(
    BuildContext context,
  ) => <PopupMenuEntry<String>>[
    if (onPlayPause != null)
      PopupMenuItem<String>(
        value: 'play_pause',
        child: _VideoPlayerMenuTile(
          icon: isPlaying ? PhosphorIconsLight.pause : PhosphorIconsLight.play,
          title: isPlaying ? context.tr.pause : context.tr.play,
        ),
      ),
    if (onRewind != null)
      PopupMenuItem<String>(
        value: 'rewind',
        child: _VideoPlayerMenuTile(
          icon: PhosphorIconsLight.rewind,
          title: context.tr.vpRewind10,
        ),
      ),
    if (onForward != null)
      PopupMenuItem<String>(
        value: 'forward',
        child: _VideoPlayerMenuTile(
          icon: PhosphorIconsLight.fastForward,
          title: context.tr.vpForward10,
        ),
      ),
    if (onMute != null)
      PopupMenuItem<String>(
        value: 'mute',
        child: _VideoPlayerMenuTile(
          icon: isMuted
              ? PhosphorIconsLight.speakerSlash
              : PhosphorIconsLight.speakerHigh,
          title: isMuted ? context.tr.vpUnmute : context.tr.vpMute,
        ),
      ),
    if (onFullscreen != null)
      PopupMenuItem<String>(
        value: 'fullscreen',
        child: _VideoPlayerMenuTile(
          icon: isFullscreen
              ? PhosphorIconsLight.cornersIn
              : PhosphorIconsLight.cornersOut,
          title: isFullscreen
              ? context.tr.vpExitFullscreen
              : context.tr.vpEnterFullscreen,
        ),
      ),
    if (onLosslessCut != null)
      PopupMenuItem<String>(
        value: 'lossless_cut',
        enabled: losslessCutEnabled,
        child: _VideoPlayerMenuTile(
          icon: PhosphorIconsLight.scissors,
          title: context.tr.cutTitle,
          iconColor: losslessCutEnabled ? Colors.white : Colors.grey,
          titleColor: losslessCutEnabled ? Colors.white : Colors.grey,
        ),
      ),
    if (onPlayPause != null || onLosslessCut != null) const PopupMenuDivider(),
    PopupMenuItem<String>(
      value: 'screenshot',
      child: _VideoPlayerMenuTile(
        icon: PhosphorIconsLight.camera,
        title: context.tr.takeScreenshot,
      ),
    ),
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
      PopupMenuItem<String>(
        value: 'audio_tracks',
        child: _VideoPlayerMenuTile(
          icon: PhosphorIconsLight.musicNotes,
          title: context.tr.vpAudioTracks,
        ),
      ),
    PopupMenuItem<String>(
      value: 'subtitles',
      enabled: hasSubtitles,
      child: _VideoPlayerMenuTile(
        icon: PhosphorIconsLight.subtitles,
        title: context.tr.vpSubtitles,
        iconColor: hasSubtitles ? Colors.white : Colors.grey,
        titleColor: hasSubtitles ? Colors.white : Colors.grey,
      ),
    ),
    PopupMenuItem<String>(
      value: 'speed',
      child: _VideoPlayerMenuTile(
        icon: PhosphorIconsLight.speedometer,
        title: context.tr.vpPlaybackSpeedValue(playbackSpeed.toString()),
      ),
    ),
    PopupMenuItem<String>(
      value: 'pip',
      child: _VideoPlayerMenuTile(
        icon: isPictureInPicture
            ? PhosphorIconsLight.pictureInpicture
            : PhosphorIconsLight.pictureInpicture,
        title: isPictureInPicture
            ? context.tr.vpExitPip
            : context.tr.vpPictureInPicture,
      ),
    ),
    PopupMenuItem<String>(
      value: 'filters',
      child: _VideoPlayerMenuTile(
        icon: PhosphorIconsLight.slidersHorizontal,
        title: context.tr.vpVideoFilters,
      ),
    ),
    PopupMenuItem<String>(
      value: 'sleep_timer',
      child: _VideoPlayerMenuTile(
        icon: PhosphorIconsLight.moon,
        title: sleepDuration != null
            ? context.tr.vpSleepTimerActive
            : context.tr.vpSleepTimer,
        iconColor: sleepDuration != null ? Colors.orange : Colors.white,
        titleColor: sleepDuration != null ? Colors.orange : Colors.white,
      ),
    ),
    const PopupMenuDivider(),
    PopupMenuItem<String>(
      value: 'settings',
      child: _VideoPlayerMenuTile(
        icon: PhosphorIconsLight.gear,
        title: context.tr.vpVideoSettings,
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // PopupMenuButton creates its own Tooltip/OverlayPortal. Keep its
    // traversal anchor on a dedicated semantics node just like CbTooltip does
    // for the neighboring player buttons; otherwise Windows can reject rapid
    // AXTree updates while playback rebuilds the controls.
    return Semantics(
      container: true,
      child: PopupMenuButton<String>(
        popUpAnimationStyle: CbPopoverTransition.menuStyleOf(context),
        icon: const Icon(
          PhosphorIconsLight.dotsThreeVertical,
          color: Colors.white,
          size: 24,
        ),
        color: Colors.black.withValues(alpha: 0.9),
        tooltip: context.tr.vpAdvancedControls,
        onOpened: onMenuOpened,
        onCanceled: onMenuClosed,
        onSelected: (value) {
          onMenuClosed?.call();
          select(value);
        },
        itemBuilder: buildItems,
      ),
    );
  }
}
