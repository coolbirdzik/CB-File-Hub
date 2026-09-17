import 'package:cb_file_manager/ui/components/video/video_player/video_player_seek_preview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const inset = VideoSeekHoverPreview.trackInset;
  const barKey = ValueKey('seek-bar');

  Future<Rect> pumpSeekBar(
    WidgetTester tester, {
    required ValueChanged<bool> onHoverChanged,
    bool show = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: barKey,
              // Leaves a 200px track: every 50px is 30s of a 2 minute video.
              width: 200 + 2 * inset,
              child: show
                  ? VideoSeekHoverPreview(
                      duration: const Duration(minutes: 2),
                      onHoverChanged: onHoverChanged,
                      child: Slider(value: 0, max: 120000, onChanged: (_) {}),
                    )
                  : const SizedBox(height: 48),
            ),
          ),
        ),
      ),
    );
    return tester.getRect(find.byKey(barKey));
  }

  testWidgets('hovering shows the time under the pointer, pressing hides it', (
    tester,
  ) async {
    final hoverChanges = <bool>[];
    final bar = await pumpSeekBar(tester, onHoverChanged: hoverChanges.add);
    Offset at(double trackX) =>
        Offset(bar.left + inset + trackX, bar.center.dy);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(bar.left - 20, bar.center.dy));
    await mouse.moveTo(at(150));
    await tester.pump();
    expect(find.text('01:30'), findsOneWidget);
    expect(hoverChanges, [true]);

    await mouse.down(at(150));
    await tester.pump();
    expect(find.text('01:30'), findsNothing);
    expect(hoverChanges, [true, false]);

    // Dragging is not hovering: the main video previews the drag instead.
    await mouse.moveTo(at(100));
    await tester.pump();
    expect(find.text('01:00'), findsNothing);

    await mouse.up();
    await mouse.moveTo(at(50));
    await tester.pump();
    expect(find.text('00:30'), findsOneWidget);
    expect(hoverChanges, [true, false, true]);

    await mouse.moveTo(Offset(bar.left - 20, bar.center.dy));
    await tester.pump();
    expect(find.text('00:30'), findsNothing);
    expect(hoverChanges, [true, false, true, false]);
  });

  testWidgets('hover position clamps to the ends of the track', (tester) async {
    final bar = await pumpSeekBar(tester, onHoverChanged: (_) {});

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(bar.left, bar.top - 40));
    await mouse.moveTo(Offset(bar.left + 2, bar.center.dy));
    await tester.pump();
    expect(find.text('00:00'), findsOneWidget);

    await mouse.moveTo(Offset(bar.right - 2, bar.center.dy));
    await tester.pump();
    expect(find.text('02:00'), findsOneWidget);
  });

  testWidgets('unmounting mid-hover reports the hover end after the frame', (
    tester,
  ) async {
    final hoverChanges = <bool>[];
    final bar = await pumpSeekBar(tester, onHoverChanged: hoverChanges.add);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(bar.left - 20, bar.center.dy));
    await mouse.moveTo(bar.center);
    await tester.pump();
    expect(hoverChanges, [true]);

    await pumpSeekBar(tester, onHoverChanged: hoverChanges.add, show: false);
    expect(hoverChanges, [true, false]);
    expect(tester.takeException(), isNull);
  });
}
