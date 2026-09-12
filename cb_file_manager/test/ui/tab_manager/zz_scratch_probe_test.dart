import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Probe 2: does the traversal policy pick the tab's outer shortcut [Focus]
/// when a tab is re-activated with no remembered focus?
void main() {
  testWidgets('findFirstFocus picks the outer shortcut Focus', (
    WidgetTester tester,
  ) async {
    final scope = FocusScopeNode(debugLabel: 'tab');
    final outer = FocusNode(debugLabel: 'outer-shortcuts');
    final button = FocusNode(debugLabel: 'toolbar-button');
    final item = FocusNode(debugLabel: 'list-item');
    addTearDown(() {
      scope.dispose();
      outer.dispose();
      button.dispose();
      item.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FocusScope(
          node: scope,
          child: Focus(
            focusNode: outer,
            onKeyEvent: (_, _) => KeyEventResult.ignored,
            child: Column(
              children: <Widget>[
                AppBar(
                  title: const Text('t'),
                  actions: <Widget>[
                    IconButton(
                      focusNode: button,
                      onPressed: () {},
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                Expanded(
                  child: Focus(focusNode: item, child: const SizedBox.expand()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final BuildContext ctx = tester.element(find.byType(AppBar));
    final FocusTraversalPolicy policy =
        FocusTraversalGroup.maybeOf(ctx) ?? ReadingOrderTraversalPolicy();
    final FocusNode? first = policy.findFirstFocus(
      scope,
      ignoreCurrentFocus: true,
    );
    debugPrint(
      'PROBE2 policy=${policy.runtimeType} first=${first?.debugLabel}',
    );

    scope.unfocus();
    await tester.pumpAndSettle();
    debugPrint(
      'PROBE2 after unfocus, focusedChild=${scope.focusedChild?.debugLabel}',
    );
  });
}
