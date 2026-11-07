import 'package:cb_file_manager/design_system/primitives/cb_tooltip.dart';
import 'e2e_wait.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  group('Tooltip Semantics', () {
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();

    testWidgets('sibling list tooltips keep a valid Windows AX tree', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 100,
            child: ListView(
              children: const <Widget>[
                Row(
                  children: <Widget>[
                    CbTooltip(message: 'First action', child: Text('First')),
                    CbTooltip(message: 'Second action', child: Text('Second')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await settleE2EUi(tester);

      final root = tester
          .binding
          .renderViews
          .first
          .owner
          ?.semanticsOwner
          ?.rootSemanticsNode;
      expect(root, isNotNull);

      final traversalParents = <Object>{};
      void collect(SemanticsNode node) {
        final identifier = node.getSemanticsData().traversalParentIdentifier;
        if (identifier != null) traversalParents.add(identifier);
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      collect(root!);
      expect(traversalParents, hasLength(2));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('First')));
      await tester.pump(const Duration(seconds: 1));
      await mouse.moveTo(tester.getCenter(find.text('Second')));
      await tester.pump(const Duration(seconds: 1));
      await mouse.moveTo(Offset.zero);
      await settleE2EUi(tester);
      await mouse.removePointer();

      handle.dispose();
    });
  });
}
