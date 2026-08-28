import 'package:cb_file_manager/ui/drawer.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  testWidgets(
      'Fluent drawer section follows drawer state, responds to keyboard, and '
      'is never remounted', (tester) async {
    var drawerState = const DrawerState(
      activeTabId: 'tab-a',
      isStorageExpanded: false,
    );
    late StateSetter update;
    final stateChanges = <bool>[];

    await tester.pumpWidget(
      fluent.FluentApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SizedBox(
              width: 320,
              child: FluentDrawerSection(
                // Deliberately stable: a key that encodes the drawer state
                // would remount this subtree on every tab switch, which is what
                // floods the Windows AccessibilityBridge.
                key: const ValueKey<String>('fluent-storage'),
                icon: fluent.FluentIcons.folder,
                title: 'Drives',
                selected: false,
                expanded: drawerState.isStorageExpanded,
                onStateChanged: (expanded) => stateChanges.add(expanded),
                content: const Text('Storage item'),
              ),
            );
          },
        ),
      ),
    );

    fluent.ExpanderState expanderState() =>
        tester.state<fluent.ExpanderState>(find.byType(fluent.Expander));
    bool isExpanded() => expanderState().isExpanded;

    final fluent.ExpanderState mountedOnce = expanderState();
    expect(isExpanded(), isFalse);

    await tester.tap(find.text('Drives'));
    await tester.pumpAndSettle();
    expect(isExpanded(), isTrue);
    expect(find.text('Storage item'), findsOneWidget);
    expect(stateChanges, [true]);

    // State catches up with what the user already did: nothing to animate, and
    // nothing to echo back to the cubit.
    drawerState = const DrawerState(
      activeTabId: 'tab-a',
      isStorageExpanded: true,
    );
    update(() {});
    await tester.pumpAndSettle();
    expect(isExpanded(), isTrue);
    expect(stateChanges, [true]);
    expect(expanderState(), same(mountedOnce));

    // Switching tabs restores that tab's expansion without a remount.
    drawerState = const DrawerState(
      activeTabId: 'tab-b',
      isStorageExpanded: false,
    );
    update(() {});
    await tester.pumpAndSettle();
    expect(isExpanded(), isFalse);
    expect(stateChanges, [true], reason: 'a state-driven sync must not echo');
    expect(expanderState(), same(mountedOnce));

    await tester.tap(find.text('Drives'));
    await tester.pumpAndSettle();
    expect(isExpanded(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(isExpanded(), isFalse);
    expect(stateChanges, [true, true, false]);
    expect(expanderState(), same(mountedOnce));
  });
}
