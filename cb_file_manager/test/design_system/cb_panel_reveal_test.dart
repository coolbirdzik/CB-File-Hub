import 'package:cb_file_manager/design_system/primitives/cb_panel_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StateSetter update;
  var visible = false;
  var reduceMotion = false;
  var dismissed = 0;
  var pressed = 0;

  setUp(() {
    visible = false;
    reduceMotion = false;
    dismissed = 0;
    pressed = 0;
  });

  Widget host({bool reserveWidth = false}) => MaterialApp(
    home: StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: Align(
            alignment: Alignment.centerRight,
            child: CbPanelReveal(
              visible: visible,
              reserveWidth: reserveWidth,
              onDismissed: () => dismissed++,
              child: visible
                  ? SizedBox(
                      width: 320,
                      height: 200,
                      child: TextButton(
                        onPressed: () => pressed++,
                        child: const Text('Panel action'),
                      ),
                    )
                  : null,
            ),
          ),
        );
      },
    ),
  );

  testWidgets('docked panels reserve space gradually and retain their exit', (
    tester,
  ) async {
    await tester.pumpWidget(host(reserveWidth: true));
    update(() => visible = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final width = tester.getSize(find.byType(CbPanelReveal)).width;
    expect(width, greaterThan(0));
    expect(width, lessThan(320));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(CbPanelReveal)).width, 320);

    update(() => visible = false);
    await tester.pump();
    expect(find.text('Panel action'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getSize(find.byType(CbPanelReveal)).width, lessThan(320));
    await tester.pumpAndSettle();
    expect(find.text('Panel action'), findsNothing);
    expect(dismissed, 1);
  });

  testWidgets('closing panels cannot receive input', (tester) async {
    await tester.pumpWidget(host());
    update(() => visible = true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Panel action'));
    expect(pressed, 1);
    update(() => visible = false);
    await tester.pump();
    final ignored = tester.widget<IgnorePointer>(
      find
          .descendant(
            of: find.byType(CbPanelReveal),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(ignored.ignoring, isTrue);
    await tester.pumpAndSettle();
    expect(pressed, 1);
  });

  testWidgets('reopening during exit cancels disposal', (tester) async {
    await tester.pumpWidget(host());
    update(() => visible = true);
    await tester.pumpAndSettle();
    update(() => visible = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    update(() => visible = true);
    await tester.pumpAndSettle();
    expect(find.text('Panel action'), findsOneWidget);
    expect(dismissed, 0);
    await tester.tap(find.text('Panel action'));
    expect(pressed, 1);
  });

  testWidgets('reduced motion completes both directions immediately', (
    tester,
  ) async {
    reduceMotion = true;
    await tester.pumpWidget(host(reserveWidth: true));
    update(() => visible = true);
    await tester.pump();
    expect(tester.getSize(find.byType(CbPanelReveal)).width, 320);
    update(() => visible = false);
    await tester.pump();
    await tester.pump();
    expect(find.text('Panel action'), findsNothing);
    expect(dismissed, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
