import 'package:cb_file_manager/ui/widgets/smooth_wheel_scroll_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<SmoothWheelScrollController> mount(
    WidgetTester tester, {
    bool enabled = true,
    bool reducedMotion = false,
  }) async {
    final controller = SmoothWheelScrollController(enabled: enabled);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: ListView.builder(
            controller: controller,
            itemExtent: 50,
            itemCount: 100,
            itemBuilder: (_, index) => Text('$index'),
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('a wheel notch moves over multiple frames instead of jumping', (
    tester,
  ) async {
    final controller = await mount(tester);
    controller.position.pointerScroll(160);
    expect(controller.offset, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(controller.offset, inExclusiveRange(0, 160));
    await tester.pumpAndSettle();
    expect(controller.offset, 160);
  });

  testWidgets('consecutive notches accumulate their complete distance', (
    tester,
  ) async {
    final controller = await mount(tester);
    controller.position.pointerScroll(160);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    controller.position.pointerScroll(160);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    controller.position.pointerScroll(160);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(480, .001));
  });

  testWidgets('another wheel tick does not freeze the next display frame', (
    tester,
  ) async {
    final controller = await mount(tester);
    controller.position.pointerScroll(160);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 6));
    for (var i = 0; i < 20; i++) {
      final before = controller.offset;
      controller.position.pointerScroll(160);
      await tester.pump(const Duration(milliseconds: 6));
      expect(
        controller.offset,
        greaterThan(before),
        reason: 'A new wheel packet must not restart the ticker at time zero',
      );
    }
    await tester.pumpAndSettle();
  });

  testWidgets('reversing cancels the pending forward movement', (tester) async {
    final controller = await mount(tester);
    controller.position.pointerScroll(160);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final reversal = controller.offset;
    controller.position.pointerScroll(-160);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(controller.offset, lessThan(reversal));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('reversing also moves on the very next display frame', (
    tester,
  ) async {
    final controller = await mount(tester);
    controller.position.pointerScroll(160);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final before = controller.offset;
    controller.position.pointerScroll(-160);
    await tester.pump(const Duration(milliseconds: 6));
    expect(controller.offset, lessThan(before));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('unmounting the view stops its wheel ticker', (tester) async {
    final controller = await mount(tester);
    controller.position.pointerScroll(160);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scrollbar or keyboard jump discards the old wheel target', (
    tester,
  ) async {
    final controller = await mount(tester);
    controller.position.pointerScroll(160);
    await tester.pump();
    controller.jumpTo(500);
    controller.position.pointerScroll(160);
    await tester.pumpAndSettle();
    expect(controller.offset, 660);
  });

  testWidgets('precise small deltas remain immediate', (tester) async {
    final controller = await mount(tester);
    controller.position.pointerScroll(8);
    expect(controller.offset, 8);
  });

  testWidgets('wheel targets stay within the scroll bounds', (tester) async {
    final controller = await mount(tester);
    controller.jumpTo(controller.position.maxScrollExtent - 20);
    controller.position.pointerScroll(160);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
      reducedMotion
          ? 'respects reduced motion'
          : 'supports disabling smoothing',
      (tester) async {
        final controller = await mount(
          tester,
          enabled: reducedMotion,
          reducedMotion: reducedMotion,
        );
        controller.position.pointerScroll(160);
        expect(controller.offset, 160);
      },
    );
  }

  testWidgets('touch dragging keeps its normal direct response', (
    tester,
  ) async {
    final controller = await mount(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    expect(controller.offset, greaterThan(100));
    await tester.pumpAndSettle();
  });
}
