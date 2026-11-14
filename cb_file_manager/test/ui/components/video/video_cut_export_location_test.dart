import 'package:cb_file_manager/ui/components/video/video_player/video_cut_export_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  for (final location in VideoCutExportLocation.values) {
    testWidgets(
      'destination chooser returns $location and shows source folder',
      (tester) async {
        VideoCutExportLocation? selected;
        final source = p.join('videos', 'my-video.mp4');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => selected =
                      await chooseVideoCutExportLocation(context, source),
                  child: const Text('Export'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Export'));
        await tester.pumpAndSettle();
        expect(find.text(p.dirname(p.absolute(source))), findsOneWidget);
        await tester.tap(
          find.text(
            location == VideoCutExportLocation.besideSource
                ? 'Export here'
                : 'Choose another folder',
          ),
        );
        await tester.pumpAndSettle();
        expect(selected, location);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancelling the destination chooser does not select an export location',
    (tester) async {
      var completed = false;
      VideoCutExportLocation? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await chooseVideoCutExportLocation(
                    context,
                    'video.mp4',
                  );
                  completed = true;
                },
                child: const Text('Export'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(selected, isNull);
    },
  );
}
