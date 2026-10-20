import 'package:cb_file_manager/design_system/fluent_surface_tokens.dart';
import 'package:cb_file_manager/design_system/fluent_chrome_surface.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/ui/tab_manager/desktop/desktop_tab_drag_data.dart';
import 'package:cb_file_manager/ui/tab_manager/desktop/scrollable_tab_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class _TabBarHarness extends StatefulWidget {
  final bool titleRow;
  const _TabBarHarness({super.key, this.titleRow = false});

  @override
  State<_TabBarHarness> createState() => _TabBarHarnessState();
}

class _TabBarHarnessState extends State<_TabBarHarness>
    with TickerProviderStateMixin {
  late TabController controller = TabController(length: 2, vsync: this);
  final tabIds = <String>['first', 'second'];
  final events = <String>[];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void closeTab(int index) {
    events.add('close:${tabIds[index]}');
    final oldController = controller;
    setState(() {
      tabIds.removeAt(index);
      controller = TabController(length: tabIds.length, vsync: this);
    });
    oldController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: widget.titleRow ? FluentSurfaceTokens.tabBarHeight : null,
            child: FluentChromeSurface(
              tint: Colors.white,
              tintAlpha: 0.7,
              blurSigma: 18,
              borderRadius: BorderRadius.circular(12),
              child: ScrollableTabBar(
                controller: controller,
                tabs: [for (final id in tabIds) Text(id)],
                draggableTabs: [
                  for (final id in tabIds)
                    DesktopTabDragData(
                      tabId: id,
                      tab: WindowTabPayload(path: '/$id'),
                    ),
                ],
                onAddTabPressed: () => events.add('add'),
                onTap: (index) => events.add('select:${tabIds[index]}'),
                onTabClose: closeTab,
                onTabDragStarted: (data) => events.add('drag:${data.tabId}'),
                onTabDragEnded: () => events.add('end'),
                onTabReorder: (from, to) => events.add('reorder:$from:$to'),
                onTabContextMenu: (index, _) =>
                    events.add('menu:${tabIds[index]}'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('macOS title row fits complete tabs and clickable controls', (
    tester,
  ) async {
    final key = GlobalKey<_TabBarHarnessState>();
    await tester.pumpWidget(_TabBarHarness(key: key, titleRow: true));
    final row = tester.getRect(find.byType(ScrollableTabBar));
    final tab = tester.getRect(find.byKey(const ValueKey('desktop_tab_first')));
    expect(row.height, 60);
    expect(tab.width, greaterThanOrEqualTo(240));
    expect(tab.top, greaterThanOrEqualTo(row.top));
    expect(tab.bottom, lessThanOrEqualTo(row.bottom));
    final close = tester.getRect(find.byIcon(PhosphorIconsLight.x).first);
    expect(row.contains(close.topLeft), isTrue);
    expect(row.contains(close.bottomRight), isTrue);
    await tester.tap(find.text('second'), kind: PointerDeviceKind.mouse);
    await tester.tap(
      find.byIcon(PhosphorIconsLight.x).first,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.events, ['select:second', 'close:first']);
    expect(find.byType(AppKitView), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('closing a tab never starts a window move', (tester) async {
    final key = GlobalKey<_TabBarHarnessState>();
    await tester.pumpWidget(_TabBarHarness(key: key));
    final close = find.byIcon(PhosphorIconsLight.x).first;
    final gesture = await tester.startGesture(
      tester.getCenter(close),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(key.currentState!.tabIds, ['first', 'second']);
    expect(
      key.currentState!.events.where((e) => e.startsWith('drag:')),
      isEmpty,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(key.currentState!.tabIds, ['second']);
    expect(
      key.currentState!.events.where((e) => e.startsWith('drag:')),
      isEmpty,
    );
    await tester.tap(
      find.byIcon(PhosphorIconsLight.x),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.tabIds, isEmpty);
    expect(
      key.currentState!.events.where((e) => e.startsWith('drag:')),
      isEmpty,
    );
  });

  testWidgets('clicking a tab selects without starting a drag', (tester) async {
    final key = GlobalKey<_TabBarHarnessState>();
    await tester.pumpWidget(_TabBarHarness(key: key));
    await tester.tap(find.text('second'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(key.currentState!.events, ['select:second']);
  });

  testWidgets('moving a pressed tab still starts and ends a drag', (
    tester,
  ) async {
    final key = GlobalKey<_TabBarHarnessState>();
    await tester.pumpWidget(_TabBarHarness(key: key));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('first')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(key.currentState!.events, isEmpty);
    await gesture.moveBy(const Offset(0, 45));
    await tester.pump();
    expect(key.currentState!.events, contains('drag:first'));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(key.currentState!.events.last, 'end');
  });

  testWidgets('dragging horizontally still reorders tabs', (tester) async {
    final key = GlobalKey<_TabBarHarnessState>();
    await tester.pumpWidget(_TabBarHarness(key: key));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('first')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(230, 0));
    await tester.pump();
    expect(key.currentState!.events, contains('reorder:0:1'));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(key.currentState!.events.last, 'end');
  });

  testWidgets('closing the dragged tab ends its window move', (tester) async {
    final key = GlobalKey<_TabBarHarnessState>();
    await tester.pumpWidget(_TabBarHarness(key: key));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('first')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 45));
    await tester.pump();
    key.currentState!.closeTab(0);
    await tester.pump();
    expect(key.currentState!.events.last, 'end');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(key.currentState!.events.where((e) => e == 'end'), hasLength(1));
  });

  for (final buttons in [kMiddleMouseButton, kSecondaryMouseButton]) {
    testWidgets('mouse button $buttons never starts a drag', (tester) async {
      final key = GlobalKey<_TabBarHarnessState>();
      await tester.pumpWidget(_TabBarHarness(key: key));
      await tester.tap(
        find.text('first'),
        kind: PointerDeviceKind.mouse,
        buttons: buttons,
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.events, [
        buttons == kMiddleMouseButton ? 'close:first' : 'menu:first',
      ]);
    });
  }
}
