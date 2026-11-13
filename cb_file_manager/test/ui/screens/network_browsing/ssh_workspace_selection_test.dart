import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/components/common/file_view_shell.dart';
import 'package:cb_file_manager/services/ssh/local_ssh_discovery.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/ui/components/common/grid_list_collection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_host_list_item.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_host_sort.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_workspace_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_recovery_test.dart' show host;
import 'ssh_connection_dialog_test.dart' show FixtureSshDiscovery;

class _CountingSort extends SshHostSortController {
  int comparisons = 0;
  @override
  int compare(SshProfile a, SshProfile b) {
    comparisons++;
    return super.compare(a, b);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<SshProfileStore> pumpWorkspace(
    WidgetTester tester,
    ViewMode mode, {
    SshHostSortController? sort,
  }) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SshProfileStore();
    for (final name in ['Alpha', 'Beta', 'Gamma']) {
      await store.saveProfile(
        SshProfile(
          id: name,
          name: name,
          host: '$name.example.test',
          username: 'user',
          password: 'secret',
          port: 2222,
          group: 'Work',
        ),
      );
    }
    final tabs = TabManagerBloc();
    addTearDown(tabs.close);
    final added = tabs.stream.first;
    tabs.add(AddTab(path: '#ssh'));
    await added;
    final view = GridListViewController(
      supportedModes: SshWorkspaceScreen.viewModes,
    );
    await view.select(mode);
    addTearDown(view.dispose);
    await tester.pumpWidget(
      BlocProvider.value(
        value: tabs,
        child: host(
          SshWorkspaceScreen(
            tabId: tabs.state.activeTabId!,
            store: store,
            viewController: view,
            sortController: sort ?? SshHostSortController(),
            discovery: FixtureSshDiscovery(
              Future.value(const LocalSshSnapshot()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  Set<String> selected(WidgetTester tester) => tester
      .widgetList<SshHostListItem>(find.byType(SshHostListItem))
      .where((item) => item.isSelected)
      .map((item) => item.name)
      .toSet();

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('dragging selection does not re-sort the host collection', (
    tester,
  ) async {
    final sort = _CountingSort();
    await pumpWorkspace(tester, ViewMode.grid, sort: sort);
    final before = sort.comparisons;
    expect(before, greaterThan(0));
    final area = tester.getRect(
      find.byKey(const ValueKey('grid-list-collection-grid')),
    );
    final gesture = await tester.startGesture(
      area.bottomRight - const Offset(12, 12),
      kind: PointerDeviceKind.mouse,
    );
    for (final point in [area.center, area.topLeft + const Offset(1, 1)]) {
      await gesture.moveTo(point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected(tester), {'Alpha', 'Beta', 'Gamma'});
    expect(sort.comparisons, before);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ViewMode.list, ViewMode.details, ViewMode.grid]) {
    testWidgets(
      'SSH ${mode.name} context Delete keeps the complete selection',
      (tester) async {
        final store = await pumpWorkspace(tester, mode);
        await tester.tap(find.text('Alpha'));
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(find.text('Beta'));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(selected(tester), {'Alpha', 'Beta'});
        await tester.tap(find.text('Alpha'), buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        expect(selected(tester), {'Alpha', 'Beta'});
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(store.profiles.length, 3);
        await tester.tap(find.widgetWithText(CbButton, 'Delete'));
        await tester.pumpAndSettle();
        expect(store.profiles.map((p) => p.name), ['Gamma']);
      },
    );

    for (final keyboard in [false, true]) {
      testWidgets(
        'SSH ${mode.name} ${keyboard ? 'key after toolbar focus' : 'toolbar Delete'} removes both selected hosts',
        (tester) async {
          final store = await pumpWorkspace(tester, mode);
          await tester.tap(find.text('Alpha'));
          await tester.pumpAndSettle();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.tap(find.text('Beta'));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
          final toolbar = find.byKey(const ValueKey('ssh-delete-selection'));
          if (keyboard) {
            Focus.of(
              tester.element(
                find.descendant(of: toolbar, matching: find.byType(Icon)).first,
              ),
            ).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.delete);
          } else {
            await tester.tap(toolbar);
          }
          await tester.pumpAndSettle();
          expect(store.profiles.length, 3);
          await tester.tap(find.widgetWithText(CbButton, 'Delete'));
          await tester.pumpAndSettle();
          expect(store.profiles.map((p) => p.name), ['Gamma']);
        },
      );
    }
    testWidgets('SSH ${mode.name} supports Ctrl/Shift and select all', (
      tester,
    ) async {
      await pumpWorkspace(tester, mode);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('Beta'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(selected(tester), {'Alpha', 'Beta'});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Gamma'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(selected(tester), {'Beta', 'Gamma'});
      await chord(tester, LogicalKeyboardKey.keyA);
      expect(selected(tester), {'Alpha', 'Beta', 'Gamma'});
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(selected(tester), isEmpty);
    });

    testWidgets('SSH ${mode.name} rectangle selects multiple hosts', (
      tester,
    ) async {
      await pumpWorkspace(tester, mode);
      final area = tester.getRect(
        find.byKey(ValueKey('grid-list-collection-${mode.name}')),
      );
      final gesture = await tester.startGesture(
        area.bottomRight - const Offset(12, 12),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(area.topLeft + const Offset(1, 1));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected(tester), {'Alpha', 'Beta', 'Gamma'});
    });
  }

  testWidgets(
    'SSH view scale resizes cards, changes layout, and retains selection',
    (tester) async {
      await pumpWorkspace(tester, ViewMode.grid);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      final before = tester.getSize(find.byKey(const ValueKey('Alpha'))).width;
      FileViewShell shell() => tester
          .widgetList<FileViewShell>(find.byType(FileViewShell))
          .singleWhere((s) => s.onViewScaleDelta != null);
      shell().onViewScaleDelta!(1);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('Alpha'))).width,
        greaterThan(before),
      );
      expect(selected(tester), {'Alpha'});
      for (var i = 0; i < 30; i++) {
        shell().onViewScaleDelta!(-1);
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const ValueKey('grid-list-collection-details')),
        findsOneWidget,
      );
      expect(selected(tester), {'Alpha'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SSH copies profiles with credentials and confirms bulk deletion',
    (tester) async {
      final store = await pumpWorkspace(tester, ViewMode.list);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.keyA);
      await chord(tester, LogicalKeyboardKey.keyC);
      await chord(tester, LogicalKeyboardKey.keyV);
      expect(store.profiles.length, 6);
      final duplicate = store.profiles.singleWhere(
        (p) => p.name == 'Alpha (2)',
      );
      expect(duplicate.id, isNot('Alpha'));
      expect(duplicate.password, 'secret');
      expect(duplicate.port, 2222);
      expect(duplicate.group, 'Work');
      await chord(tester, LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(store.profiles.length, 6);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.profiles.length, 6);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CbButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(store.profiles, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('SSH cut keeps the original until paste and Escape cancels it', (
    tester,
  ) async {
    final store = await pumpWorkspace(tester, ViewMode.list);
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyX);
    expect(store.profiles.length, 3);
    await chord(tester, LogicalKeyboardKey.keyV);
    expect(store.profiles.map((p) => p.id), ['Alpha', 'Beta', 'Gamma']);
    await chord(tester, LogicalKeyboardKey.keyX);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyV);
    expect(store.profiles.length, 3);
  });
}
