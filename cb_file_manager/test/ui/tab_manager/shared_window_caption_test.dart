// The production adapter uses the window controller from the pinned Flutter SDK.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:io';

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/tab_activity/tab_activity_manager.dart';
import 'package:cb_file_manager/services/windowing/windows_shared_engine_windows.dart';
import 'package:cb_file_manager/ui/components/common/window_caption_buttons.dart';
import 'package:cb_file_manager/ui/tab_manager/components/tab_always_active_indicator.dart';
import 'package:cb_file_manager/ui/tab_manager/components/tab_inactive_indicator.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/desktop/scrollable_tab_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('tab bar controls target the shared window in its scope', (
    tester,
  ) async {
    final window = _TestWindowController();
    final tabs = TabController(length: 1, vsync: const TestVSync());
    addTearDown(window.dispose);
    addTearDown(tabs.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: WindowsSharedEngineScope(
            controller: window,
            child: ScrollableTabBar(
              controller: tabs,
              tabs: const [Text('Home')],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(PhosphorIconsLight.minus));
    expect(window.minimized, isTrue);

    await tester.tap(find.byIcon(PhosphorIconsLight.cornersOut));
    await tester.pump();
    expect(window.isMaximized, isTrue);

    await tester.tap(find.byIcon(PhosphorIconsLight.cornersIn));
    await tester.pump();
    expect(window.isMaximized, isFalse);

    await tester.tap(
      find.descendant(
        of: find.byType(WindowCaptionButtons),
        matching: find.byIcon(PhosphorIconsLight.x),
      ),
    );
    expect(window.isDestroyed, isTrue);
  }, skip: !Platform.isWindows);

  testWidgets('blank title bar areas move the shared window', (tester) async {
    final window = _TestWindowController();
    final tabs = TabController(length: 1, vsync: const TestVSync());
    addTearDown(window.dispose);
    addTearDown(tabs.dispose);
    var drags = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: WindowsSharedEngineScope(
            controller: window,
            startDragging: () => drags++,
            child: ScrollableTabBar(
              controller: tabs,
              tabs: const [Text('Home')],
            ),
          ),
        ),
      ),
    );
    final bar = tester.getRect(find.byType(ScrollableTabBar));
    final caption = tester.getRect(find.byType(WindowCaptionButtons));
    final blankStrip = bar.center;
    final dragAreas = [
      Offset(bar.left + 6, bar.center.dy),
      blankStrip,
      Offset(caption.left - 12, bar.center.dy),
    ];
    for (final point in dragAreas) {
      final gesture = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(35, 0));
      await gesture.up();
      await tester.pump();
    }
    expect(drags, dragAreas.length);

    await tester.tapAt(blankStrip, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(blankStrip, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(window.isMaximized, isTrue);
    expect(drags, dragAreas.length);
  }, skip: !Platform.isWindows);

  testWidgets('closing a shared window leaves surviving tab indicators safe', (
    tester,
  ) async {
    final window = _TestWindowController();
    final showWindow = ValueNotifier(true);
    late TabManagerBloc closingBloc;
    final activity = TabActivityManager()
      ..onTabInteraction('surviving-tab')
      ..setAlwaysActive('surviving-tab', true);
    final closedTabs = <String>[];
    activity.addClosedListener((id, _) => closedTabs.add(id));
    locator.registerSingleton(activity);
    addTearDown(() async {
      await locator.unregister<TabActivityManager>();
      activity.dispose();
      showWindow.dispose();
      window.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Column(
            children: [
              const Row(
                children: [
                  TabAlwaysActiveIndicator(tabId: 'surviving-tab'),
                  TabInactiveIndicator(tabId: 'surviving-tab'),
                ],
              ),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: showWindow,
                  child: WindowsSharedEngineScope(
                    controller: window,
                    child: Provider<TabManagerBloc>(
                      lazy: false,
                      create: (_) => closingBloc = TabManagerBloc()
                        ..add(
                          AddTab(path: '#home', name: 'Closing window tab'),
                        ),
                      dispose: (_, bloc) => bloc.closeWindow(),
                      child: const SizedBox.shrink(),
                    ),
                  ),
                  builder: (context, visible, child) =>
                      visible ? child! : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final closingTabId = closingBloc.state.tabs.single.id;
    expect(activity.stateOf(closingTabId), isNotNull);
    expect(find.byIcon(PhosphorIconsFill.pushPin), findsOneWidget);

    showWindow.value = false;
    await tester.pump();
    expect(closingBloc.isClosed, isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(activity.stateOf(closingTabId), isNull);
    expect(closedTabs, [closingTabId]);
    expect(find.byIcon(PhosphorIconsFill.pushPin), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Platform.isWindows);
}

class _TestWindowController extends WindowController {
  _TestWindowController() : super.empty();

  bool minimized = false;

  @override
  bool isMaximized = false;

  @override
  bool isDestroyed = false;

  @override
  void setMinimized(bool value) => minimized = value;

  @override
  void setMaximized(bool value) {
    isMaximized = value;
    notifyListeners();
  }

  @override
  void destroy() => isDestroyed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
