import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

import '../../../../services/media/media_language_labels.dart';

String audioTrackEnglishLabel(mk.AudioTrack track) {
  if (track.id == 'auto') return 'Automatic';
  if (track.id == 'no') return 'Off';
  final language =
      mediaLanguageEnglishName(track.language) ??
      mediaLanguageEnglishName(track.title);
  return language == null
      ? 'Audio track ${track.id} · Unknown language'
      : '$language · Audio track ${track.id}';
}

class AudioTrackChoices extends StatelessWidget {
  final List<mk.AudioTrack> tracks;
  final String selected;
  final ValueChanged<mk.AudioTrack> onSelect;
  const AudioTrackChoices({
    super.key,
    required this.tracks,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final ordered = [...tracks]
      ..sort((a, b) {
        int special(mk.AudioTrack track) => track.id == 'auto'
            ? 0
            : track.id == 'no'
            ? 1
            : 2;
        final rank = special(a).compareTo(special(b));
        return rank != 0
            ? rank
            : audioTrackEnglishLabel(a).compareTo(audioTrackEnglishLabel(b));
      });
    return RadioGroup<String>(
      groupValue: selected,
      onChanged: (id) {
        if (id != null) onSelect(tracks.firstWhere((track) => track.id == id));
      },
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final track in ordered)
            RadioListTile<String>(
              value: track.id,
              title: Text(audioTrackEnglishLabel(track)),
            ),
        ],
      ),
    );
  }
}
