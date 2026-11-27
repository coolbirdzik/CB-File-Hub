import 'dart:io';

import 'package:cb_file_manager/ui/screens/folder_list/components/subtitle_thumbnail_badge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  testWidgets(
    'SRT badges follow matching sidecars, including new queue exports',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('subtitle-grid-');
      addTearDown(() => folder.deleteSync(recursive: true));
      String media(String name) {
        final file = File(p.join(folder.path, name))..createSync();
        return file.path;
      }

      final plain = media('movie.mp4');
      final sibling = media('movie.en.mkv');
      final translated = media('translated.mkv');
      final direct = media('direct.mp4');
      media('movie.en.srt');
      media('direct.SRT');

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (final path in [plain, sibling, translated, direct])
                SubtitleThumbnailBadge(key: ValueKey(path), videoPath: path),
            ],
          ),
        ),
      );

      Finder badge(String path) => find.descendant(
        of: find.byKey(ValueKey(path)),
        matching: find.byIcon(PhosphorIconsBold.subtitles),
      );

      Future<void> waitFor(Finder finder, {required bool present}) async {
        for (var i = 0; i < 50; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (finder.evaluate().isNotEmpty == present) return;
        }
        expect(finder, present ? findsOneWidget : findsNothing);
      }

      await waitFor(badge(sibling), present: true);
      expect(badge(direct), findsOneWidget);
      expect(badge(plain), findsNothing);
      expect(badge(translated), findsNothing);

      final sidecar = File(p.join(folder.path, 'Subs', 'translated.vi.ai.srt'))
        ..createSync(recursive: true);
      await tester.pump(const Duration(seconds: 5));
      await waitFor(badge(translated), present: true);

      sidecar.deleteSync();
      await tester.pump(const Duration(seconds: 5));
      await waitFor(badge(translated), present: false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
