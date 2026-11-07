import 'package:cb_file_manager/services/media/media_language_labels.dart';
import 'package:cb_file_manager/ui/components/video/video_player/audio_track_choices.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

void main() {
  test(
    'container language codes and native Japanese names display English',
    () {
      for (final value in [
        'ja',
        'jpn',
        'ja-JP',
        'ja_JP',
        'Japanese',
        '日本語',
        '日本語音声',
      ]) {
        expect(mediaLanguageEnglishName(value), 'Japanese', reason: value);
      }
      expect(mediaLanguageEnglishName('eng'), 'English');
      expect(mediaLanguageEnglishName('ger'), 'German');
      expect(mediaLanguageEnglishName('zho'), 'Chinese');
      expect(mediaLanguageEnglishName('chi'), 'Chinese');
      expect(mediaLanguageEnglishName('vie'), 'Vietnamese');
      expect(mediaLanguageEnglishName('und'), isNull);
      expect(
        audioTrackEnglishLabel(const mk.AudioTrack('1', '日本語', 'jpn')),
        'Japanese · Audio track 1',
      );
      expect(
        audioTrackEnglishLabel(const mk.AudioTrack('1', null, 'und')),
        'Audio track 1 · Unknown language',
      );
    },
  );

  testWidgets(
    'track languages are English A–Z while selecting preserves the actual stream ID',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioTrackChoices(
              tracks: [
                const mk.AudioTrack('1', '日本語', 'jpn'),
                const mk.AudioTrack('2', 'English', 'eng'),
                const mk.AudioTrack('3', 'Tiếng Việt', 'vie'),
                mk.AudioTrack.auto(),
                mk.AudioTrack.no(),
              ],
              selected: '2',
              onSelect: (track) => selected = track.id,
            ),
          ),
        ),
      );
      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();
      expect(labels, [
        'Automatic',
        'Off',
        'English · Audio track 2',
        'Japanese · Audio track 1',
        'Vietnamese · Audio track 3',
      ]);
      expect(find.text('日本語'), findsNothing);
      await tester.tap(find.text('Japanese · Audio track 1'));
      expect(selected, '1');
    },
  );
}
