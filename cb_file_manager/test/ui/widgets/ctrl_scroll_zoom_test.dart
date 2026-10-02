import 'package:cb_file_manager/ui/widgets/ctrl_scroll_zoom.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart' as win32;

Future<void> scroll(WidgetTester tester, [double dy = 100]) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: const Offset(100, 100),
      scrollDelta: Offset(0, dy),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('released Ctrl after switching apps scrolls without zooming', (
    tester,
  ) async {
    var physicalCtrlDown = true;
    final deltas = <int>[];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CtrlScrollZoom(
          debugWindowsKeyState: (key) =>
              key == win32.VK_CONTROL && physicalCtrlDown ? 0x8000 : 0,
          onDelta: deltas.add,
          child: ListView(
            controller: controller,
            children: List.generate(100, (_) => const SizedBox(height: 50)),
          ),
        ),
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await scroll(tester);
    expect(deltas, [1]);
    // No key-up reaches Flutter while the user releases Ctrl in another app.
    physicalCtrlDown = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(HardwareKeyboard.instance.isControlPressed, isTrue);
    await scroll(tester);
    expect(deltas, [1]);
    expect(controller.offset, greaterThan(0));

    // A fresh Ctrl press must still enable zoom after returning to the app.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    physicalCtrlDown = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await scroll(tester, -100);
    expect(deltas, [1, -1]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
  });

  for (final virtualKey in [win32.VK_CONTROL, win32.VK_LWIN, win32.VK_RWIN]) {
    testWidgets(
      'physical modifier $virtualKey enables zoom without cached key',
      (tester) async {
        final deltas = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            home: CtrlScrollZoom(
              debugWindowsKeyState: (key) => key == virtualKey ? -32768 : 0,
              onDelta: deltas.add,
              child: const SizedBox.expand(),
            ),
          ),
        );
        expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
        await scroll(tester);
        await scroll(tester, -100);
        expect(deltas, [1, -1]);
      },
    );
  }

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  ]) {
    testWidgets(
      'cached ${modifier.keyLabel} cannot trigger zoom after release',
      (tester) async {
        final deltas = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            home: CtrlScrollZoom(
              debugWindowsKeyState: (_) => 1,
              onDelta: deltas.add,
              child: const SizedBox.expand(),
            ),
          ),
        );
        await tester.sendKeyDownEvent(modifier);
        await scroll(tester);
        expect(deltas, isEmpty);
        await tester.sendKeyUpEvent(modifier);
      },
    );
  }

  testWidgets('disabled zoom leaves wheel scrolling available with Ctrl held', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CtrlScrollZoom(
          debugWindowsKeyState: (_) => 0x8000,
          child: ListView(
            controller: controller,
            children: List.generate(100, (_) => const SizedBox(height: 50)),
          ),
        ),
      ),
    );
    await scroll(tester);
    expect(controller.offset, greaterThan(0));
  });
}
