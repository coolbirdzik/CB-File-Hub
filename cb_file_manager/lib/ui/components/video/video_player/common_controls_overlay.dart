import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'video_player_utils.dart';

class CommonVideoControlsOverlay extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek; // 0.0..1.0
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool hasPrev;
  final bool hasNext;
  final double? volume; // 0..100 (optional)
  final ValueChanged<double>? onVolumeChange; // 0..100 (optional)
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onScreenshot;

  const CommonVideoControlsOverlay({
    Key? key,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSeek,
    this.onPrev,
    this.onNext,
    this.hasPrev = false,
    this.hasNext = false,
    this.volume,
    this.onVolumeChange,
    this.onToggleFullscreen,
    this.onScreenshot,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final safeDuration =
        duration.inMilliseconds > 0 ? duration : const Duration(seconds: 1);
    final progress =
        (position.inMilliseconds / safeDuration.inMilliseconds).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.5),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(VideoPlayerUtils.formatDurationAlwaysHms(position),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: progress,
                  onChanged: onSeek,
                  activeColor: Colors.redAccent,
                  inactiveColor: Colors.white30,
                ),
              ),
              Text(VideoPlayerUtils.formatDurationAlwaysHms(duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                    hasPrev
                        ? PhosphorIconsLight.skipBack
                        : PhosphorIconsLight.skipBack,
                    color: hasPrev ? Colors.white : Colors.white24,
                    size: 26),
                onPressed: hasPrev ? onPrev : null,
              ),
              IconButton(
                icon: Icon(
                    isPlaying
                        ? PhosphorIconsLight.pause
                        : PhosphorIconsLight.play,
                    color: Colors.white,
                    size: 32),
                onPressed: onPlayPause,
              ),
              IconButton(
                icon: Icon(
                    hasNext
                        ? PhosphorIconsLight.skipForward
                        : PhosphorIconsLight.skipForward,
                    color: hasNext ? Colors.white : Colors.white24,
                    size: 26),
                onPressed: hasNext ? onNext : null,
              ),
              const Spacer(),
              if (onScreenshot != null)
                IconButton(
                  icon: const Icon(PhosphorIconsLight.camera,
                      color: Colors.white, size: 22),
                  onPressed: onScreenshot,
                ),
              if (onVolumeChange != null)
                Row(
                  children: [
                    const Icon(PhosphorIconsLight.speakerHigh,
                        color: Colors.white, size: 18),
                    SizedBox(
                      width: 100,
                      child: Slider(
                        value: (volume ?? 70).clamp(0, 100),
                        min: 0,
                        max: 100,
                        onChanged: onVolumeChange,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white30,
                      ),
                    ),
                  ],
                ),
              if (onToggleFullscreen != null)
                IconButton(
                  icon: const Icon(PhosphorIconsLight.cornersOut,
                      color: Colors.white, size: 22),
                  onPressed: onToggleFullscreen,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
