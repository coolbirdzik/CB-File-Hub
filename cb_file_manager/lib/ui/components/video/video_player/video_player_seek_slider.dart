import 'package:flutter/material.dart';

/// Seek slider used in mobile controls. Parent wires StreamBuilder/ValueListenable
/// and provides value, min, max, and callbacks for seek start/change/end.
class VideoPlayerSeekSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onChangeEnd;

  const VideoPlayerSeekSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        ),
        child: Slider(
          value: value,
          min: min,
          max: max,
          activeColor: Colors.white,
          inactiveColor: Colors.white24,
          onChangeStart: (_) => onChangeStart?.call(),
          onChanged: onChanged,
          onChangeEnd: (_) => onChangeEnd?.call(),
        ),
      ),
    );
  }
}
