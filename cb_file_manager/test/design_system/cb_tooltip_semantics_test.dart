import 'package:cb_file_manager/design_system/primitives/cb_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps sibling tooltip traversal anchors on separate nodes',
      (tester) async {
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

    final root = tester
        .binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
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
    expect(find.byTooltip('First action'), findsOneWidget);
    expect(find.byTooltip('Second action'), findsOneWidget);
    handle.dispose();
  });
}
