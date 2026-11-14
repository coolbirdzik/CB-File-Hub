import 'package:cb_file_manager/ui/components/video/video_player/video_cut_panel.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('source date mode is optional and can be switched back', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VideoCutPanel(
              source: 'sample.mp4',
              duration: const Duration(seconds: 20),
              position: () => Duration.zero,
              onSeek: (_) {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export options'));
    await tester.pumpAndSettle();
    expect(find.text('Export time'), findsOneWidget);
    await tester.ensureVisible(find.text('Export time'));
    await tester.tap(find.text('Export time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep source file dates'));
    await tester.pumpAndSettle();
    expect(find.text('Keep source file dates'), findsOneWidget);
    await tester.tap(find.text('Keep source file dates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export time'));
    await tester.pumpAndSettle();
    expect(find.text('Export time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'timecodes round-trip hours and milliseconds and reject malformed values',
    () {
      const time = Duration(
        hours: 27,
        minutes: 12,
        seconds: 4,
        milliseconds: 123,
      );
      expect(
        VideoCutPanelState.parseTimecode(VideoCutPanelState.timecode(time)),
        time,
      );
      expect(
        VideoCutPanelState.parseTimecode('00:01:02.1'),
        const Duration(seconds: 62, milliseconds: 100),
      );
      for (final invalid in [
        '1:60:00',
        '-1:00:00',
        '00:00:70',
        '2',
        '00:01:02.1234',
        '99999999999999999999999999:00:00',
      ]) {
        expect(VideoCutPanelState.parseTimecode(invalid), isNull);
      }
    },
  );

  testWidgets(
    'marks the current playhead, validates and keeps multiple segments',
    (tester) async {
      final key = GlobalKey<VideoCutPanelState>();
      var position = const Duration(seconds: 2);
      Duration? seek;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VideoCutPanel(
                key: key,
                source: 'sample.mkv',
                duration: const Duration(seconds: 12),
                position: () => position,
                onSeek: (value) => seek = value,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      key.currentState!.markIn();
      position = const Duration(seconds: 5);
      key.currentState!.markOut();
      await tester.pump();
      expect(find.text('00:00:02.000'), findsOneWidget);
      expect(find.text('00:00:05.000'), findsOneWidget);
      await tester.tap(find.text('Add segment'));
      await tester.pump();
      expect(find.text('Segments to export (2)'), findsOneWidget);
      await tester.tap(find.byTooltip('Go to start'));
      await tester.pump();
      expect(seek, const Duration(seconds: 5));
      final fields = find.byType(CbTextField);
      await tester.enterText(
        find.descendant(of: fields.first, matching: find.byType(TextField)),
        '00:00:20.000',
      );
      await tester.tap(find.text('Add segment'));
      await tester.pump();
      expect(find.textContaining('Enter a valid range'), findsOneWidget);
      expect(find.text('Segments to export (2)'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove segment').first);
      await tester.pump();
      expect(find.text('Segments to export (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dragging either cut boundary seeks during the drag and ends at that boundary',
    (tester) async {
      final previews = <Duration>[];
      final ends = <Duration>[];
      var starts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VideoCutPanel(
                source: 'sample.mp4',
                duration: const Duration(seconds: 100),
                position: () => Duration.zero,
                onSeek: (_) =>
                    fail('Range dragging must use the preview seek pipeline'),
                onRangeSeekStart: () => starts++,
                onRangeSeek: previews.add,
                onRangeSeekEnd: ends.add,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final slider = find.byType(RangeSlider);
      var rect = tester.getRect(slider);
      final startDrag = await tester.startGesture(
        Offset(rect.left + 24, rect.center.dy),
      );
      await startDrag.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(
        previews,
        isNotEmpty,
        reason: 'The player must seek before pointer release',
      );
      final startTarget = previews.last;
      expect(startTarget, greaterThan(Duration.zero));
      expect(ends, isEmpty);
      await startDrag.up();
      await tester.pump();
      expect(ends.single, startTarget);

      rect = tester.getRect(slider);
      final endDrag = await tester.startGesture(
        Offset(rect.right - 24, rect.center.dy),
      );
      await endDrag.moveBy(const Offset(-120, 0));
      await tester.pump();
      final endTarget = previews.last;
      expect(endTarget, greaterThan(startTarget));
      expect(endTarget, lessThan(const Duration(seconds: 100)));
      expect(ends, hasLength(1));
      await endDrag.up();
      await tester.pump();
      expect(
        ends.last,
        endTarget,
        reason: 'Releasing the end thumb must not jump to the start',
      );
      expect(starts, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rounded and repeated range values keep the same active thumb', (
    tester,
  ) async {
    final previews = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VideoCutPanel(
              source: 'sample.mp4',
              duration: const Duration(seconds: 1),
              position: () => Duration.zero,
              onSeek: previews.add,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    final slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
    slider.onChangeStart!(const RangeValues(0, 1000));
    slider.onChanged!(const RangeValues(0.1, 1000));
    slider.onChanged!(const RangeValues(0.2, 1000));
    slider.onChanged!(const RangeValues(0.2, 1000));
    slider.onChangeEnd!(const RangeValues(0.2, 1000));
    expect(previews, everyElement(Duration.zero));
    previews.clear();
    slider.onChangeStart!(const RangeValues(0, 1000));
    slider.onChanged!(const RangeValues(0, 999.9));
    slider.onChanged!(const RangeValues(0, 999.8));
    slider.onChanged!(const RangeValues(0, 999.8));
    slider.onChangeEnd!(const RangeValues(0, 999.8));
    expect(previews, everyElement(const Duration(seconds: 1)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'multiple ranges save automatically, stay editable and preview numbered filenames',
    (tester) async {
      final key = GlobalKey<VideoCutPanelState>();
      var playhead = const Duration(seconds: 2);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VideoCutPanel(
                key: key,
                source: 'sample.mkv',
                duration: const Duration(seconds: 12),
                position: () => playhead,
                onSeek: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      key.currentState!.markIn();
      playhead = const Duration(seconds: 5);
      key.currentState!.markOut();
      await tester.pump();
      expect(find.textContaining('sample_1.mkv'), findsOneWidget);
      await tester.tap(find.text('Add segment'));
      await tester.pump();
      expect(find.text('Segments to export (2)'), findsOneWidget);
      expect(find.text('Export 2 segments'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.first, '00:00:08.000');
      await tester.enterText(fields.last, '00:00:10.000');
      await tester.pump();
      expect(find.text('00:00:08.000 – 00:00:10.000'), findsOneWidget);
      await tester.tap(find.textContaining('sample_1.mkv'));
      await tester.pump();
      expect(
        tester.widget<TextField>(fields.first).controller!.text,
        '00:00:02.000',
      );
      expect(
        tester.widget<TextField>(fields.last).controller!.text,
        '00:00:05.000',
      );
      await tester.enterText(fields.last, '00:00:04.000');
      await tester.tap(find.textContaining('sample_2.mkv'));
      await tester.pump();
      expect(
        tester.widget<TextField>(fields.first).controller!.text,
        '00:00:08.000',
      );
      expect(
        tester.widget<TextField>(fields.last).controller!.text,
        '00:00:10.000',
      );
      expect(find.text('00:00:02.000 – 00:00:04.000'), findsOneWidget);
      expect(find.text('Segments to export (2)'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove segment').first);
      await tester.pump();
      expect(find.text('Segments to export (1)'), findsOneWidget);
      expect(find.text('00:00:08.000 – 00:00:10.000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small player panel scrolls without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VideoCutPanel(
              source: 'sample.mp4',
              duration: const Duration(seconds: 20),
              position: () => Duration.zero,
              onSeek: (_) {},
              onClose: () => closed = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    expect(closed, isTrue);
  });
}
