import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/services/windowing/windows_native_tab_drag_drop_service.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/desktop/desktop_tab_drag_data.dart';
import 'package:cb_file_manager/ui/tab_manager/desktop/external_tab_drop_controller.dart';
import 'package:cb_file_manager/ui/tab_manager/desktop/scrollable_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('cb_file_manager/window_utils');

Future<void> _sendFromPlatform(String method, Object? arguments) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _channel.name,
        _channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AddTab.insertIndex', () {
    late TabManagerBloc tabs;
    setUp(() => tabs = TabManagerBloc());
    tearDown(() => tabs.close());

    Future<void> dispatch(TabEvent event) async {
      final changed = tabs.stream.first;
      tabs.add(event);
      await changed;
    }

    test('inserts at the index and clamps past the end', () async {
      await dispatch(AddTab(path: '/a'));
      await dispatch(AddTab(path: '/b'));
      await dispatch(AddTab(path: '/c', insertIndex: 1));
      await dispatch(AddTab(path: '/d', insertIndex: 99));
      await dispatch(AddTab(path: '/e', insertIndex: -3));
      expect(tabs.state.tabs.map((t) => t.path), [
        '/e',
        '/a',
        '/c',
        '/b',
        '/d',
      ]);
      expect(tabs.state.activeTab!.path, '/e');
    });
  });

  group('tab payloads', () {
    test('round-trip through the merge payload', () {
      const tabs = [
        WindowTabPayload(path: r'C:\Users', name: 'Users'),
        WindowTabPayload(path: '/tmp', highlightedFileName: 'a.txt'),
      ];
      final decoded = WindowsNativeTabDragDropService.decodeTabsPayload(
        WindowsNativeTabDragDropService.encodeTabsPayload(tabs),
      );
      expect(decoded.map((t) => t.toJson()), tabs.map((t) => t.toJson()));
    });

    test('label names the first tab and counts the rest', () {
      expect(
        WindowsNativeTabDragDropService.tabDragLabel(const [
          WindowTabPayload(path: r'D:\Media\Movies\'),
          WindowTabPayload(path: '/b'),
          WindowTabPayload(path: '/c'),
        ]),
        'Movies +2',
      );
      expect(
        WindowsNativeTabDragDropService.tabDragLabel(const [
          WindowTabPayload(path: '/x', name: ' Docs '),
        ]),
        'Docs',
      );
    });
  });

  test('ExternalTabDropController reports only changed bounds', () {
    final reported = <Rect?>[];
    final controller = ExternalTabDropController(
      onStripBoundsChanged: reported.add,
    );
    int resolver(Offset _) => 2;
    controller.attach(resolver);
    controller.reportStripBounds(const Rect.fromLTWH(0, 0, 100, 50));
    controller.reportStripBounds(const Rect.fromLTWH(0, 0, 100, 50));
    expect(controller.insertIndexAt(Offset.zero), 2);
    controller.detach((Offset _) => 7);
    expect(controller.insertIndexAt(Offset.zero), 2);
    controller.detach(resolver);
    expect(controller.insertIndexAt(Offset.zero), isNull);
    expect(reported, [const Rect.fromLTWH(0, 0, 100, 50), null]);
  });

  test(
    'a tab merged in from another window lands at the hovered gap',
    () async {
      final tabs = TabManagerBloc();
      addTearDown(tabs.close);
      WindowsNativeTabDragDropService.initialize(tabs);
      final drop = WindowsNativeTabDragDropService.externalTabDrop;
      int resolver(Offset position) => position.dx > 100 ? 1 : 0;
      drop.attach(resolver);
      addTearDown(() => drop.detach(resolver));

      for (final path in ['/a', '/b']) {
        final changed = tabs.stream.first;
        tabs.add(AddTab(path: path));
        await changed;
      }

      await _sendFromPlatform('onTabMergeHover', {
        'x': 150.0,
        'y': 20.0,
        'label': 'Movies',
      });
      expect(
        drop.hover.value,
        const ExternalTabDropHover(position: Offset(150, 20), label: 'Movies'),
      );

      final merged = tabs.stream.firstWhere((s) => s.tabs.length == 3);
      await _sendFromPlatform('onTabMergeDrop', {
        'payload': WindowsNativeTabDragDropService.encodeTabsPayload(const [
          WindowTabPayload(path: '/movies', name: 'Movies'),
        ]),
        'x': 150.0,
        'y': 20.0,
      });
      // The gap stays open until the tab that fills it is in the state.
      expect(drop.hover.value, isNotNull);
      final state = await merged;
      expect(state.tabs.map((t) => t.path), ['/a', '/movies', '/b']);
      expect(state.activeTab!.path, '/movies');
      await Future<void>.delayed(Duration.zero);
      expect(drop.hover.value, isNull);

      var mergedAway = false;
      WindowsNativeTabDragDropService.onTabWindowMerged = () =>
          mergedAway = true;
      addTearDown(
        () => WindowsNativeTabDragDropService.onTabWindowMerged = null,
      );
      await _sendFromPlatform('onTabWindowMerged', null);
      expect(mergedAway, isTrue);
    },
  );

  testWidgets('tab bar reports its strip and shows the incoming tab', (
    tester,
  ) async {
    final reported = <Rect?>[];
    final controller = ExternalTabDropController(
      onStripBoundsChanged: reported.add,
    );
    final tabController = TabController(length: 2, vsync: const TestVSync());
    addTearDown(tabController.dispose);

    Widget bar() => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: ScrollableTabBar(
            controller: tabController,
            tabs: const [Text('first'), Text('second')],
            draggableTabs: const [
              DesktopTabDragData(
                tabId: 'first',
                tab: WindowTabPayload(path: '/first'),
              ),
              DesktopTabDragData(
                tabId: 'second',
                tab: WindowTabPayload(path: '/second'),
              ),
            ],
            externalTabDrop: controller,
          ),
        ),
      ),
    );

    await tester.pumpWidget(bar());
    await tester.pump();
    expect(reported, hasLength(1));
    expect(reported.single, isNotNull);
    expect(reported.single!.width, greaterThan(0));

    final second = tester.getRect(
      find.byKey(const ValueKey('desktop_tab_second')),
    );
    expect(controller.insertIndexAt(second.centerLeft + const Offset(4, 0)), 1);
    expect(controller.insertIndexAt(second.centerRight), 2);

    final slot = second.width;
    final secondTextX = tester.getTopLeft(find.text('second')).dx;
    controller.hover.value = ExternalTabDropHover(
      position: second.centerLeft + const Offset(4, 0),
      label: 'Incoming',
    );
    await tester.pump();
    expect(find.text('Incoming'), findsOneWidget);
    // The neighbour slides aside to open the gap instead of jumping.
    await tester.pump(const Duration(milliseconds: 60));
    final midX = tester.getTopLeft(find.text('second')).dx;
    expect(midX, greaterThan(secondTextX));
    expect(midX, lessThan(secondTextX + slot));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('second')).dx,
      moreOrLessEquals(secondTextX + slot),
    );

    // Over the ghost tab the gap holds still.
    final ghost = tester.getRect(
      find.byKey(const ValueKey('desktop_tab_external_drop')),
    );
    controller.hover.value = ExternalTabDropHover(
      position: ghost.center + Offset(slot * 0.4, 0),
      label: 'Incoming',
    );
    await tester.pumpAndSettle();
    expect(controller.insertIndexAt(ghost.center + Offset(slot * 0.4, 0)), 1);

    controller.hover.value = null;
    await tester.pumpAndSettle();
    expect(find.text('Incoming'), findsNothing);
    expect(
      tester.getTopLeft(find.text('second')).dx,
      moreOrLessEquals(secondTextX),
    );

    await tester.pumpWidget(const SizedBox());
    expect(reported.last, isNull);
    expect(controller.insertIndexAt(Offset.zero), isNull);
  });

  testWidgets('closing a tab slides its neighbours into place', (tester) async {
    final ids = ['a', 'b', 'c'];
    late StateSetter setBarState;
    TabController? tabController;
    addTearDown(() => tabController?.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) {
                setBarState = setState;
                tabController?.dispose();
                tabController = TabController(
                  length: ids.length,
                  vsync: const TestVSync(),
                );
                return ScrollableTabBar(
                  controller: tabController!,
                  tabs: [for (final id in ids) Text('tab-$id')],
                  draggableTabs: [
                    for (final id in ids)
                      DesktopTabDragData(
                        tabId: id,
                        tab: WindowTabPayload(path: '/$id'),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    final bX = tester.getTopLeft(find.text('tab-b')).dx;
    final cX = tester.getTopLeft(find.text('tab-c')).dx;

    setBarState(() => ids.remove('b'));
    await tester.pump();
    // Still drawn where it was, then slides left into b's old slot.
    expect(tester.getTopLeft(find.text('tab-c')).dx, moreOrLessEquals(cX));
    await tester.pump(const Duration(milliseconds: 60));
    final midX = tester.getTopLeft(find.text('tab-c')).dx;
    expect(midX, lessThan(cX));
    expect(midX, greaterThan(bX));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('tab-c')).dx, moreOrLessEquals(bX));
  });

  testWidgets('tabs appear without re-rendering where nothing changed', (
    tester,
  ) async {
    final ids = <String>[];
    final controller = ExternalTabDropController();
    late StateSetter setBarState;
    TabController? tabController;
    addTearDown(() => tabController?.dispose());

    double opacityOf(String text) => tester
        .widgetList<Opacity>(
          find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
        )
        .fold(1.0, (value, o) => value * o.opacity);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) {
                setBarState = setState;
                tabController?.dispose();
                tabController = TabController(
                  length: ids.length,
                  vsync: const TestVSync(),
                );
                return ScrollableTabBar(
                  controller: tabController!,
                  activeTabIndex: ids.isEmpty ? null : ids.length - 1,
                  tabs: [for (final id in ids) Text(id)],
                  draggableTabs: [
                    for (final id in ids)
                      DesktopTabDragData(
                        tabId: id,
                        tab: WindowTabPayload(path: '/$id'),
                      ),
                  ],
                  externalTabDrop: controller,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // A fresh window's first tabs are simply there.
    setBarState(() => ids.addAll(['a', 'b']));
    await tester.pump();
    expect(opacityOf('a'), 1);
    expect(opacityOf('b'), 1);

    // A tab dropped into the open gap takes the ghost's place.
    final b = tester.getRect(find.byKey(const ValueKey('desktop_tab_b')));
    controller.hover.value = ExternalTabDropHover(
      position: b.centerLeft + const Offset(4, 0),
      label: 'merged',
    );
    await tester.pumpAndSettle();
    final ghost = tester.getRect(
      find.byKey(const ValueKey('desktop_tab_external_drop')),
    );
    setBarState(() => ids.insert(1, 'merged'));
    controller.hover.value = null;
    await tester.pump();
    expect(
      find.byKey(const ValueKey('desktop_tab_external_drop')),
      findsNothing,
    );
    expect(opacityOf('merged'), 1);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('desktop_tab_merged'))),
      ghost.topLeft,
    );
    final bAfter = tester.getTopLeft(find.text('b')).dx;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('b')).dx, moreOrLessEquals(bAfter));

    // An ordinary new tab still eases in.
    setBarState(() => ids.add('c'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(opacityOf('c'), lessThan(1));
    await tester.pumpAndSettle();
    expect(opacityOf('c'), 1);
  });
}
