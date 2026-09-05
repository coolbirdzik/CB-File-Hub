// Guards CbFluentTooltip against the semantics remount that floods stderr with
// "Failed to update ui::AXTree, error: Nodes left pending by the update" on
// Windows.
//
// fluent_ui's Tooltip only wraps its child in a GestureDetector and MouseRegion
// once MouseTracker.mouseIsConnected is true. That flips from false to true the
// first time a pointer arrives after launch, changing the widget type at that
// slot and remounting the child subtree, so every semantics node underneath is
// destroyed and recreated in a single frame. The Windows accessibility bridge
// rejects such a batch and never resyncs, turning one bad frame into an endless
// error flood.
import 'package:cb_file_manager/design_system/primitives/cb_tooltip.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Map<int, SemanticsData> _snapshot(WidgetTester tester) {
  final root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  final out = <int, SemanticsData>{};
  if (root == null) return out;

  void walk(SemanticsNode node) {
    out[node.id] = node.getSemanticsData();
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return out;
}

void main() {
  testWidgets('keeps every semantics id when the mouse connects', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      fluent.FluentApp(
        home: Row(
          textDirection: TextDirection.ltr,
          children: <Widget>[
            CbFluentTooltip(
              message: 'CB Agent',
              child: fluent.Button(
                onPressed: () {},
                child: const Text('CB Agent'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = _snapshot(tester);
    expect(before, isNotEmpty);
    expect(
      before.values.any((data) => data.tooltip == 'CB Agent'),
      isTrue,
      reason: 'the tooltip message must still reach assistive technology',
    );

    // What happens on a real desktop the first time the user moves the mouse.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(500, 500));
    await tester.pumpAndSettle();

    final after = _snapshot(tester);
    await mouse.removePointer();
    handle.dispose();

    expect(
      after.keys.toList(),
      equals(before.keys.toList()),
      reason:
          'connecting a mouse renumbered the semantics tree; the Windows '
          'accessibility bridge drops an update that reclaims ids like that',
    );
    expect(
      after.values.any((data) => data.tooltip == 'CB Agent'),
      isTrue,
      reason: 'the tooltip message must survive the reshape',
    );
  });
}
