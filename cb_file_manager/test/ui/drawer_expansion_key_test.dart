import 'package:cb_file_manager/ui/drawer.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  test('drawer expansion keys change with tab and persisted section state', () {
    const tabA = DrawerState(
      activeTabId: 'tab-a',
      isPinnedExpanded: false,
      isStorageExpanded: true,
    );
    const tabB = DrawerState(
      activeTabId: 'tab-b',
      isPinnedExpanded: true,
      isStorageExpanded: true,
    );

    expect(
      fluentDrawerSectionExpansionKey(state: tabA, section: 'pinned'),
      'fluent-pinned-tab-a-false',
    );
    expect(
      fluentDrawerSectionExpansionKey(state: tabB, section: 'pinned'),
      'fluent-pinned-tab-b-true',
    );
    expect(
      fluentDrawerSectionExpansionKey(state: tabA, section: 'storage'),
      'fluent-storage-tab-a-true',
    );
  });

  testWidgets(
      'Fluent drawer section restores expansion per keyed tab and responds to keyboard',
      (tester) async {
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
                key: ValueKey<String>(
                  fluentDrawerSectionExpansionKey(
                    state: drawerState,
                    section: 'storage',
                  ),
                ),
                icon: fluent.FluentIcons.folder,
                title: 'Drives',
                selected: false,
                initiallyExpanded: drawerState.isStorageExpanded,
                onStateChanged: (expanded) => stateChanges.add(expanded),
                content: const Text('Storage item'),
              ),
            );
          },
        ),
      ),
    );

    bool isExpanded() => tester
        .state<fluent.ExpanderState>(find.byType(fluent.Expander))
        .isExpanded;

    expect(isExpanded(), isFalse);

    await tester.tap(find.text('Drives'));
    await tester.pumpAndSettle();
    expect(isExpanded(), isTrue);
    expect(find.text('Storage item'), findsOneWidget);
    expect(stateChanges, [true]);

    drawerState = const DrawerState(
      activeTabId: 'tab-a',
      isStorageExpanded: true,
    );
    update(() {});
    await tester.pump();
    expect(isExpanded(), isTrue);

    drawerState = const DrawerState(
      activeTabId: 'tab-b',
      isStorageExpanded: false,
    );
    update(() {});
    await tester.pump();
    expect(isExpanded(), isFalse);

    await tester.tap(find.text('Drives'));
    await tester.pumpAndSettle();
    expect(isExpanded(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(isExpanded(), isFalse);
    expect(stateChanges, [true, true, false]);
  });
}
