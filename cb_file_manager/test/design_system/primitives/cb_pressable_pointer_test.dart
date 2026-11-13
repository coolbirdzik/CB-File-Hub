import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mouse selection and feedback paint before tap arbitration', (
    tester,
  ) async {
    var selections = 0;
    var opens = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    CbInteractionState? painted;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CbPressable(
            pressOnPointerDown: true,
            focusNode: focus,
            onPressed: () {
              selections++;
              focus.requestFocus();
            },
            onDoubleTap: () => opens++,
            builder: (_, state) {
              painted = state;
              return const SizedBox(width: 180, height: 50);
            },
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final position = tester.getCenter(find.byType(CbPressable));
    await mouse.down(position);
    await tester.pump(); // No 100 ms press / 300 ms double-tap wait.
    expect(selections, 1);
    expect(painted!.pressed, isTrue);
    expect(painted!.focused, isTrue);
    expect(opens, 0);
    await mouse.up();
    await tester.pump();
    expect(painted!.pressed, isFalse);
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      painted!.pressed,
      isFalse,
      reason: 'late onTapDown must not re-press the row',
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      selections,
      1,
      reason: 'deferred onTap must not toggle selection twice',
    );
    final second = await tester.startGesture(
      position,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await second.up();
    await tester.pump(const Duration(milliseconds: 50));
    final third = await tester.startGesture(
      position,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await third.up();
    await tester.pump();
    expect(opens, 1);
    expect(selections, 3);
    await tester.pump(const Duration(milliseconds: 400));
    expect(selections, 3);
    expect(opens, 1);
    await mouse.removePointer();
  });

  testWidgets(
    'touch scrolling cancels selection while a touch tap commits once',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                CbPressable(
                  pressOnPointerDown: true,
                  onPressed: () => selected++,
                  onDoubleTap: () {},
                  builder: (_, _) =>
                      const SizedBox(height: 80, width: double.infinity),
                ),
                const SizedBox(height: 1600),
              ],
            ),
          ),
        ),
      );
      final position = tester.getCenter(find.byType(CbPressable));
      final touch = await tester.startGesture(
        position,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(selected, 0);
      await touch.moveBy(const Offset(0, -80));
      await touch.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, 0);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(0);
      await tester.pump();
      await tester.tap(find.byType(CbPressable));
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, 1);
    },
  );

  testWidgets(
    'cancel and secondary mouse buttons do not activate a row twice',
    (tester) async {
      var selected = 0;
      var menus = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: CbPressable(
              pressOnPointerDown: true,
              onPressed: () => selected++,
              onDoubleTap: () {},
              onSecondaryTap: () => menus++,
              builder: (_, _) => const SizedBox(width: 180, height: 50),
            ),
          ),
        ),
      );
      final position = tester.getCenter(find.byType(CbPressable));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.down(position);
      await mouse.cancel();
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, 1);
      final secondary = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await secondary.down(position);
      await secondary.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, 1);
      expect(menus, 1);
      await tester.tap(find.byType(CbPressable));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        selected,
        2,
        reason: 'a subsequent touch tap must not be suppressed',
      );
    },
  );
}
