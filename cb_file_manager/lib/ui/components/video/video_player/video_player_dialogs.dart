import 'package:flutter/material.dart';

import '../../../utils/route.dart';
import 'video_player_models.dart';

/// One option for [VideoPlayerRadioListContent].
class VideoPlayerRadioOption<T> {
  final T? value;
  final String label;
  const VideoPlayerRadioOption(this.value, this.label);
}

/// Shared Radio list content: options (value + label), selected, onSelect.
/// Each Radio onChanged calls onSelect and pops the dialog.
class VideoPlayerRadioListContent<T> extends StatelessWidget {
  final List<VideoPlayerRadioOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onSelect;

  const VideoPlayerRadioListContent({
    Key? key,
    required this.options,
    required this.selected,
    required this.onSelect,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: options
          .map((opt) => ListTile(
                title: Text(opt.label),
                leading: Radio<T?>(
                  // ignore: deprecated_member_use
                  value: opt.value,
                  // ignore: deprecated_member_use
                  groupValue: selected,
                  // ignore: deprecated_member_use
                  onChanged: (v) {
                    onSelect(v);
                    RouteUtils.safePopDialog(context);
                  },
                ),
              ))
          .toList(),
    );
  }
}

/// Label + Slider for settings (Buffer Size, Network Timeout, etc.). [label] is the full text.
class VideoPlayerLabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const VideoPlayerLabeledSlider({
    Key? key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Shared row: label (e.g. "Brightness: 100%") + Slider for filter dialogs.
class VideoPlayerFilterSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const VideoPlayerFilterSlider({
    Key? key,
    required this.label,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${(value * 100).round()}%'),
        Slider(
          value: value,
          min: 0.0,
          max: 2.0,
          divisions: 20,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

String _formatDurationOption(Duration d) {
  if (d.inHours > 0) {
    return '${d.inHours} hour${d.inHours > 1 ? 's' : ''}';
  }
  return '${d.inMinutes} minutes';
}

/// Content for the subtitles selection dialog.
class SubtitleDialogContent extends StatelessWidget {
  final List<SubtitleTrack> tracks;
  final int? selected;
  final ValueChanged<int?> onSelect;

  const SubtitleDialogContent({
    Key? key,
    required this.tracks,
    required this.selected,
    required this.onSelect,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final options = <VideoPlayerRadioOption<int>>[
      const VideoPlayerRadioOption<int>(null, 'Off'),
      ...tracks
          .asMap()
          .entries
          .map((e) => VideoPlayerRadioOption<int>(e.key, e.value.language)),
    ];
    return VideoPlayerRadioListContent<int>(
      options: options,
      selected: selected,
      onSelect: onSelect,
    );
  }
}

/// Content for the playback speed selection dialog.
class PlaybackSpeedDialogContent extends StatelessWidget {
  final List<double> speeds;
  final double current;
  final ValueChanged<double> onSelect;

  const PlaybackSpeedDialogContent({
    Key? key,
    this.speeds = const [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
    required this.current,
    required this.onSelect,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final options =
        speeds.map((s) => VideoPlayerRadioOption<double>(s, '${s}x')).toList();
    return VideoPlayerRadioListContent<double>(
      options: options,
      selected: current,
      onSelect: (v) {
        if (v != null) onSelect(v);
      },
    );
  }
}

/// Content for the video filters (brightness, contrast, saturation) dialog.
class VideoFiltersDialogContent extends StatelessWidget {
  final double brightness;
  final double contrast;
  final double saturation;
  final ValueChanged<double> onBrightnessChanged;
  final ValueChanged<double> onContrastChanged;
  final ValueChanged<double> onSaturationChanged;

  const VideoFiltersDialogContent({
    Key? key,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.onBrightnessChanged,
    required this.onContrastChanged,
    required this.onSaturationChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        VideoPlayerFilterSlider(
          label: 'Brightness',
          value: brightness,
          onChanged: onBrightnessChanged,
        ),
        VideoPlayerFilterSlider(
          label: 'Contrast',
          value: contrast,
          onChanged: onContrastChanged,
        ),
        VideoPlayerFilterSlider(
          label: 'Saturation',
          value: saturation,
          onChanged: onSaturationChanged,
        ),
      ],
    );
  }
}

/// Content for the sleep timer dialog.
class SleepTimerDialogContent extends StatelessWidget {
  final List<Duration> durations;
  final Duration? selected;
  final ValueChanged<Duration?> onSelect;

  const SleepTimerDialogContent({
    Key? key,
    this.durations = const [
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(hours: 1),
      Duration(hours: 2),
    ],
    required this.selected,
    required this.onSelect,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final options = <VideoPlayerRadioOption<Duration>>[
      const VideoPlayerRadioOption<Duration>(null, 'Off'),
      ...durations.map(
          (d) => VideoPlayerRadioOption<Duration>(d, _formatDurationOption(d))),
    ];
    return VideoPlayerRadioListContent<Duration>(
      options: options,
      selected: selected,
      onSelect: onSelect,
    );
  }
}
