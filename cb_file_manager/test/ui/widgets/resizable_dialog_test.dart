import 'package:cb_file_manager/ui/widgets/resizable_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Margin the dialog keeps between itself and the viewport edges.
const double _margin = 16;

void main() {
  /// Size of the dialog surface currently rendered on screen.
  Size dialogSize(WidgetTester tester) {
    final surface = find
        .descendant(
          of: find.byType(ResizableDialog),
          matching: find.byType(Material),
        )
        .first;
    return tester.getSize(surface);
  }

  Offset dialogTopLeft(WidgetTester tester) {
    final surface = find
        .descendant(
          of: find.byType(ResizableDialog),
          matching: find.byType(Material),
        )
        .first;
    return tester.getTopLeft(surface);
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    Size initialSizeFactor = const Size(0.5, 0.6),
    Size minSize = const Size(380, 320),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResizableDialog(
          initialSizeFactor: initialSizeFactor,
          minSize: minSize,
          title: const Text('Manage tags'),
          contentBuilder: (context, size) => const SizedBox.expand(),
          actions: const <Widget>[Text('SAVE')],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sizes itself from the viewport factor and centers',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(tester);

    expect(dialogSize(tester), const Size(500, 480));
    expect(dialogTopLeft(tester), const Offset(250, 160));
  });

  testWidgets('maximize fills the viewport, restore returns the old rect',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(tester);
    final restored = dialogSize(tester);

    await tester.tap(find.byIcon(PhosphorIconsLight.cornersOut));
    await tester.pumpAndSettle();

    expect(
      dialogSize(tester),
      const Size(1000 - _margin * 2, 800 - _margin * 2),
    );
    expect(dialogTopLeft(tester), const Offset(_margin, _margin));

    await tester.tap(find.byIcon(PhosphorIconsLight.cornersIn));
    await tester.pumpAndSettle();

    expect(dialogSize(tester), restored);
  });

  testWidgets('dragging the bottom-right corner resizes the dialog',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(tester);
    final before = dialogSize(tester);

    await tester.drag(
      find.byIcon(PhosphorIconsLight.dotsSixVertical),
      const Offset(60, 40),
    );
    await tester.pumpAndSettle();

    final after = dialogSize(tester);
    expect(after.width, closeTo(before.width + 60, 0.5));
    expect(after.height, closeTo(before.height + 40, 0.5));
  });

  testWidgets('resizing cannot shrink the dialog below its minimum size',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(tester, minSize: const Size(400, 300));

    await tester.drag(
      find.byIcon(PhosphorIconsLight.dotsSixVertical),
      const Offset(-900, -900),
    );
    await tester.pumpAndSettle();

    expect(dialogSize(tester), const Size(400, 300));
  });

  testWidgets('dragging the header moves the dialog', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(tester);
    final before = dialogTopLeft(tester);
    final beforeSize = dialogSize(tester);

    await tester.drag(find.text('Manage tags'), const Offset(-80, 50));
    await tester.pumpAndSettle();

    expect(dialogTopLeft(tester), before + const Offset(-80, 50));
    expect(dialogSize(tester), beforeSize);
  });

  testWidgets('the dialog is clamped inside the viewport when dragged out',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(tester);

    await tester.drag(find.text('Manage tags'), const Offset(-2000, -2000));
    await tester.pumpAndSettle();

    expect(dialogTopLeft(tester), const Offset(_margin, _margin));
  });
}
