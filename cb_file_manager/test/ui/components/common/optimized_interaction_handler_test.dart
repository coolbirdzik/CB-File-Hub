import 'package:cb_file_manager/ui/components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/ui/widgets/file_drag_drop_item.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int taps = 0;
  int doubleTaps = 0;

  setUp(() {
    taps = 0;
    doubleTaps = 0;
  });

  Future<void> pumpItem(WidgetTester tester, {required bool selected}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: FileDragDropItem(
              path: 'a.mp4',
              isFolder: false,
              selectedPaths: selected ? const {'a.mp4'} : const {},
              child: OptimizedInteractionLayer(
                onTap: () => taps++,
                onDoubleTap: () => doubleTaps++,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset center(WidgetTester tester) =>
      tester.getCenter(find.byType(OptimizedInteractionLayer));

  testWidgets('a mouse press selects an unselected item before release', (
    tester,
  ) async {
    await pumpItem(tester, selected: false);

    final mouse = await tester.startGesture(
      center(tester),
      kind: PointerDeviceKind.mouse,
    );
    expect(taps, 1);

    await mouse.up();
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a press on a selected item waits for release', (tester) async {
    await pumpItem(tester, selected: true);

    final mouse = await tester.startGesture(
      center(tester),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 0, reason: 'the press may still become a drag');

    await mouse.up();
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a double-click with a held second press still opens', (
    tester,
  ) async {
    await pumpItem(tester, selected: false);
    final first = await tester.startGesture(
      center(tester),
      kind: PointerDeviceKind.mouse,
    );
    await first.up();
    await tester.pump(const Duration(milliseconds: 50));

    // The first click selected the item, so the second press is deferred.
    await pumpItem(tester, selected: true);
    final second = await tester.startGesture(
      center(tester),
      kind: PointerDeviceKind.mouse,
    );
    // The double-click window is wall-clock based; hold past it.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 350)),
    );
    await second.up();
    await tester.pump();

    expect(doubleTaps, 1);
  });
}
