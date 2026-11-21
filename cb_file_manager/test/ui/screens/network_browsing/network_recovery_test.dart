import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:cb_file_manager/design_system/primitives/cb_tooltip.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_content_overlay.dart';
import 'dart:async';
import 'dart:io';
import 'package:cb_file_manager/services/network_browsing/network_service_base.dart';
import 'package:cb_file_manager/services/network_browsing/network_service_registry.dart';
import 'package:cb_file_manager/bloc/network_browsing/network_browsing_bloc.dart';
import 'package:cb_file_manager/bloc/network_browsing/network_browsing_event.dart';
import 'package:cb_file_manager/bloc/network_browsing/network_browsing_state.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/primitives/cb_button.dart';
import 'package:cb_file_manager/ui/screens/network_browsing/components/network_recovery_view.dart';
import 'package:cb_file_manager/ui/screens/network_browsing/network_browser_screen.dart';
import 'package:cb_file_manager/ui/screens/network_browsing/network_connection_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const missingPath = '#network/SMB/192.0.2.1/missing/';

Widget host(Widget child, {bool vietnamese = false}) => fluent.FluentApp(
  theme: fluent.FluentThemeData(brightness: Brightness.light),
  locale: Locale(vietnamese ? 'vi' : 'en'),
  supportedLocales: const [Locale('en'), Locale('vi')],
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Theme(data: ThemeConfig.getLightTheme(), child: child),
);

class ListingService implements NetworkServiceBase {
  final pending = <String, Completer<List<FileSystemEntity>>>{};
  final started = StreamController<String>.broadcast();
  @override
  String get serviceName => 'SMB';
  @override
  bool isAvailable() => true;
  @override
  bool get isConnected => true;
  @override
  Future<ConnectionResult> connect({
    required String host,
    required String username,
    String? password,
    int? port,
    Map<String, dynamic>? additionalOptions,
  }) async =>
      ConnectionResult(success: true, connectedPath: 'smb://$host/share');
  @override
  Future<List<FileSystemEntity>> listDirectory(String path) {
    final result = Completer<List<FileSystemEntity>>();
    pending[path] = result;
    started.add(path);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'refreshing services clears a previous missing-connection error',
    () async {
      final bloc = NetworkBrowsingBloc(
        registry: NetworkServiceRegistry.withServices([]),
      );
      addTearDown(bloc.close);
      final failed = bloc.stream.firstWhere((s) => s.hasError);
      bloc.add(const NetworkDirectoryRequested(missingPath));
      await failed;
      final recovered = bloc.stream.firstWhere((s) => !s.hasError);
      bloc.add(const NetworkServicesListRequested());
      final state = await recovered;
      expect(state.services, isNotNull);
      expect(state.isLoading, isFalse);
    },
  );

  test(
    'parallel browser sessions keep their own listings and errors',
    () async {
      final service = ListingService();
      final registry = NetworkServiceRegistry.withServices([service]);
      await registry.connect(
        serviceName: 'SMB',
        host: '192.0.2.1',
        username: 'test',
      );
      final manager = NetworkBrowsingBloc(registry: registry);
      final first = manager.createBrowserSession();
      final second = manager.createBrowserSession();
      addTearDown(service.started.close);
      addTearDown(manager.close);
      addTearDown(first.close);
      addTearDown(second.close);
      const otherPath = '#network/SMB/192.0.2.1/other/';
      final firstStarted = service.started.stream.firstWhere(
        (p) => p == missingPath,
      );
      first.add(const NetworkDirectoryRequested(missingPath));
      await firstStarted;
      final secondStarted = service.started.stream.firstWhere(
        (p) => p == otherPath,
      );
      second.add(const NetworkDirectoryRequested(otherPath));
      await secondStarted;
      final secondLoaded = second.stream.firstWhere((s) => s.hasFiles);
      service.pending[otherPath]!.complete([File('$otherPath/example.txt')]);
      await secondLoaded;
      final firstFailed = first.stream.firstWhere((s) => s.hasError);
      service.pending[missingPath]!.completeError(
        StateError('Connection lost'),
      );
      await firstFailed;
      expect(second.state.currentPath, otherPath);
      expect(second.state.hasFiles, isTrue);
      expect(second.state.hasError, isFalse);
      expect(manager.state, const NetworkBrowsingState.initial());
    },
  );

  test('closing a browser ignores its late directory completion', () async {
    final service = ListingService();
    final registry = NetworkServiceRegistry.withServices([service]);
    await registry.connect(
      serviceName: 'SMB',
      host: '192.0.2.1',
      username: 'test',
    );
    final browser = NetworkBrowsingBloc(registry: registry);
    addTearDown(service.started.close);
    final started = service.started.stream.first;
    browser.add(const NetworkDirectoryRequested(missingPath));
    await started;
    await browser.close();
    service.pending[missingPath]!.complete([File('$missingPath/example.txt')]);
    await Future<void>.delayed(Duration.zero);
    expect(browser.isClosed, isTrue);
    expect(browser.state.hasFiles, isFalse);
  });

  testWidgets('a failed browser does not poison other tabs and can go Home', (
    tester,
  ) async {
    final network = NetworkBrowsingBloc(
      registry: NetworkServiceRegistry.withServices([]),
    );
    final tabs = TabManagerBloc();
    addTearDown(network.close);
    addTearDown(tabs.close);
    final added = tabs.stream.first;
    tabs.add(AddTab(path: missingPath));
    await added;
    final firstId = tabs.state.activeTabId!;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: network),
          BlocProvider.value(value: tabs),
        ],
        child: host(
          BlocBuilder<TabManagerBloc, TabManagerState>(
            builder: (context, state) => IndexedStack(
              index: state.tabs.indexWhere((t) => t.id == state.activeTabId),
              children: state.tabs
                  .map(
                    (tab) => tab.path.startsWith('#network/')
                        ? NetworkBrowserScreen(
                            key: ValueKey(tab.id),
                            path: tab.path,
                            tabId: tab.id,
                          )
                        : Center(child: Text('Home: ${tab.id}')),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NetworkRecoveryView), findsOneWidget);
    expect(network.state, const NetworkBrowsingState.initial());

    tabs.add(AddTab(path: '#home'));
    await tester.pumpAndSettle();
    expect(tabs.state.activeTab!.path, '#home');
    expect(find.byType(NetworkRecoveryView), findsNothing);
    expect(find.text('Home: ${tabs.state.activeTabId}'), findsOneWidget);

    tabs.add(SwitchToTab(firstId));
    await tester.pumpAndSettle();
    final recovery = tester.widget<NetworkRecoveryView>(
      find.byType(NetworkRecoveryView),
    );
    expect(recovery.path, missingPath);
    recovery.onRetry();
    await tester.pumpAndSettle();
    expect(find.byType(NetworkRecoveryView), findsOneWidget);
    recovery.onHome();
    await tester.pumpAndSettle();
    expect(tabs.state.activeTab!.path, '#home');
    expect(network.state.hasError, isFalse);
    // Drain the existing skeleton's stagger timers after leaving its screen.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back traverses network history and exits to Home', (
    tester,
  ) async {
    final network = NetworkBrowsingBloc(
      registry: NetworkServiceRegistry.withServices([]),
    );
    final tabs = TabManagerBloc();
    addTearDown(network.close);
    addTearDown(tabs.close);
    final added = tabs.stream.first;
    tabs.add(AddTab(path: '#home'));
    await added;
    final id = tabs.state.activeTabId!;
    final navigated = tabs.stream.firstWhere(
      (s) => s.activeTab!.path == missingPath,
    );
    tabs.add(UpdateTabPath(id, missingPath));
    await navigated;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: network),
          BlocProvider.value(value: tabs),
        ],
        child: host(
          BlocBuilder<TabManagerBloc, TabManagerState>(
            builder: (context, state) => state.activeTab!.path == '#home'
                ? const Center(child: Text('Home destination'))
                : NetworkBrowserScreen(path: state.activeTab!.path, tabId: id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    const childPath = '$missingPath/child/';
    tabs.add(UpdateTabPath(id, childPath));
    await tester.pumpAndSettle();
    final back = find.byWidgetPredicate(
      (w) => w is CbFluentTooltip && w.message == 'Back',
    );
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(tabs.state.activeTab!.path, missingPath);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(tabs.state.activeTab!.path, '#home');
    expect(find.text('Home destination'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection controls and Home remain available after an error', (
    tester,
  ) async {
    final network = NetworkBrowsingBloc(
      registry: NetworkServiceRegistry.withServices([]),
    );
    final tabs = TabManagerBloc();
    addTearDown(network.close);
    addTearDown(tabs.close);
    final added = tabs.stream.first;
    tabs.add(AddTab(path: '#network'));
    await added;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: network),
          BlocProvider.value(value: tabs),
        ],
        child: host(NetworkConnectionScreen(tabId: tabs.state.activeTabId)),
      ),
    );
    await tester.pumpAndSettle();
    network.add(const NetworkDirectoryRequested(missingPath));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (w) => w is CbButton && w.tooltip == 'Add Connection',
      ),
      findsOneWidget,
    );
    final homeButton = find.byWidgetPredicate(
      (w) => w is CbFluentTooltip && w.message == 'Home',
    );
    await tester.tap(homeButton);
    await tester.pumpAndSettle();
    expect(tabs.state.activeTab!.path, '#home');
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1000.0]) {
    for (final vietnamese in [false, true]) {
      testWidgets(
        'network toolbar stays below tab bar at $width, Vietnamese=$vietnamese',
        (tester) async {
          tester.view.physicalSize = Size(width, 420);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final network = NetworkBrowsingBloc(
            registry: NetworkServiceRegistry.withServices([]),
          );
          final tabs = TabManagerBloc();
          addTearDown(network.close);
          addTearDown(tabs.close);
          final added = tabs.stream.first;
          tabs.add(AddTab(path: '#network'));
          await added;
          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider.value(value: network),
                BlocProvider.value(value: tabs),
              ],
              child: host(
                Scaffold(
                  appBar: const PreferredSize(
                    preferredSize: Size.fromHeight(48),
                    child: SizedBox(
                      key: ValueKey('global-tab-bar'),
                      height: 48,
                      child: Text('Tabs'),
                    ),
                  ),
                  body: TabContentOverlay(
                    child: NetworkConnectionScreen(
                      tabId: tabs.state.activeTabId,
                    ),
                  ),
                ),
                vietnamese: vietnamese,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final toolbar = find.byKey(const ValueKey('fluent-browser-toolbar'));
          final tabBar = tester.getRect(
            find.byKey(const ValueKey('global-tab-bar')),
          );
          final toolbarRect = tester.getRect(toolbar);
          expect(toolbarRect.top, greaterThanOrEqualTo(tabBar.bottom));
          expect(
            tester.getRect(find.byType(ListView).first).top,
            greaterThanOrEqualTo(toolbarRect.bottom),
          );
          for (final element
              in find
                  .descendant(of: toolbar, matching: find.byType(CbButton))
                  .evaluate()) {
            final button = tester.getRect(find.byWidget(element.widget));
            expect(button.left, greaterThanOrEqualTo(toolbarRect.left));
            expect(button.right, lessThanOrEqualTo(toolbarRect.right));
            expect(button.top, greaterThanOrEqualTo(toolbarRect.top));
            expect(button.bottom, lessThanOrEqualTo(toolbarRect.bottom));
          }
          await tester.drag(find.byType(ListView).first, const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(tester.getRect(toolbar), toolbarRect);
          final homeLabel = AppLocalizations.of(tester.element(toolbar))!.home;
          final homeButton = find.descendant(
            of: toolbar,
            matching: find.byWidgetPredicate(
              (w) =>
                  (w is CbButton && w.tooltip == homeLabel) ||
                  (w is CbFluentTooltip && w.message == homeLabel),
            ),
          );
          await tester.tap(homeButton);
          await tester.pumpAndSettle();
          expect(tabs.state.activeTab!.path, '#home');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final vietnamese in [false, true]) {
    testWidgets('recovery actions fit a small window, Vietnamese=$vietnamese', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var homeCount = 0;
      var connectionsCount = 0;
      var retryCount = 0;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: NetworkRecoveryView(
              path: missingPath,
              errorMessage: 'No connected service found for path: $missingPath',
              onHome: () => homeCount++,
              onConnections: () => connectionsCount++,
              onRetry: () => retryCount++,
            ),
          ),
          vietnamese: vietnamese,
        ),
      );
      await tester.pumpAndSettle();
      for (final button
          in find.byType(CbButton).evaluate().map((e) => e.widget).toList()) {
        final finder = find.byWidget(button);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }
      expect([connectionsCount, retryCount, homeCount], [1, 1, 1]);
      expect(tester.takeException(), isNull);
    });
  }
}
