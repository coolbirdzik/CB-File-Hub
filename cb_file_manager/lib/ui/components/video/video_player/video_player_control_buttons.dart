import 'package:cb_file_manager/design_system/primitives/cb_tooltip.dart';
import 'package:flutter/material.dart';

/// Compact volume slider (0–100) for video player. Reuses SliderTheme across player backends.
class VideoPlayerVolumeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const VideoPlayerVolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Slider uses an OverlayPortal for its value indicator even without a
    // label. Isolate that traversal anchor from the neighboring player
    // tooltip and menu portals.
    return Semantics(
      container: true,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
        ),
        child: Slider(
          value: value.clamp(0.0, 100.0),
          min: 0.0,
          max: 100.0,
          onChanged: onChanged,
          activeColor: Colors.white,
          inactiveColor: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

/// Reusable icon button for video player controls (play, pause, volume, etc.).
class VideoPlayerControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final double size;
  final double padding;
  final String? tooltip;

  const VideoPlayerControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.size = 24,
    this.padding = 8,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: Icon(icon, size: size, color: enabled ? Colors.white : Colors.grey),
      onPressed: enabled ? onPressed : null,
      padding: EdgeInsets.all(padding),
      constraints: const BoxConstraints(),
      splashRadius: size + 4,
    );

    return tooltip != null
        ? CbTooltip(message: tooltip!, child: button)
        : button;
  }
}
