import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/home_content_service.dart';
import 'package:cb_file_manager/ui/components/common/library_hub_scaffold.dart';
import 'package:cb_file_manager/ui/screens/home/home_screen.dart';
import 'package:cb_file_manager/ui/screens/system_screen_router.dart';
import 'package:cb_file_manager/ui/tab_manager/components/navigation_bar.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyHomeContent extends HomeContentService {
  @override
  Future<List<String>> loadRecentPaths() async => [];

  @override
  Future<HomeMediaPreviews> loadMediaPreviews(List<String> recentPaths) async =>
      const HomeMediaPreviews();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late TabManagerBloc tabs;
  late DrawerCubit drawer;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb-home-navigation-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    SharedPreferences.setMockInitialValues({});
    await UserPreferences.instance.init();
    await SqliteDatabaseProvider().initialize();
  });

  tearDownAll(() async {
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  setUp(() {
    drawer = DrawerCubit();
  });

  tearDown(() async {
    await tabs.close();
    await drawer.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    bool keepToolbarMounted = false,
  }) async {
    tabs = TabManagerBloc();
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tabs.add(AddTab(path: '#settings'));
    await tester.pump();
    final tabId = tabs.state.activeTabId!;
    tabs.add(UpdateTabPath(tabId, '#home'));
    await tester.pump();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: tabs),
          BlocProvider.value(value: drawer),
        ],
        child: fluent.FluentApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => Theme(
            data: CbThemeBuilder.build(
              brightness: Brightness.light,
              accent: Colors.teal,
            ),
            child: child!,
          ),
          home: keepToolbarMounted
              ? LibraryHubScaffold(
                  tabId: tabId,
                  path: '#gallery',
                  title: 'Images',
                  icon: PhosphorIconsLight.image,
                  onRefresh: () {},
                  body: const SizedBox.expand(),
                )
              : BlocBuilder<TabManagerBloc, TabManagerState>(
                  builder: (context, state) {
                    final tab = state.activeTab!;
                    if (tab.path == '#home') {
                      return HomeScreen(
                        tabId: tab.id,
                        contentService: _EmptyHomeContent(),
                      );
                    }
                    return SystemScreenRouter.routeSystemPath(
                      context,
                      tab.path,
                      tab.id,
                    )!;
                  },
                ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> mouseButton(WidgetTester tester, int buttons) async {
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );
    await mouse.down(const Offset(1100, 850));
    await mouse.up();
    await mouse.removePointer();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
  }

  for (final entry in [
    ('home-photos', '#gallery'),
    ('home-videos', '#video'),
  ]) {
    testWidgets('${entry.$2}: toolbar and mouse history round trip from Home', (
      tester,
    ) async {
      await mount(tester);
      await tester.tap(find.byKey(ValueKey(entry.$1)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tabs.state.activeTab!.path, entry.$2);
      expect(find.byType(PathNavigationBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fluent-browser-toolbar')),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(PhosphorIconsLight.arrowLeft));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tabs.state.activeTab!.path, '#home');
      expect(tabs.state.activeTab!.forwardHistory, [entry.$2]);

      await mouseButton(tester, kForwardMouseButton);
      await tester.pump();
      expect(tabs.state.activeTab!.path, entry.$2);
      await mouseButton(tester, kBackMouseButton);
      await tester.pump();
      expect(tabs.state.activeTab!.path, '#home');
      expect(tabs.state.activeTab!.navigationHistory, ['#settings', '#home']);
      await mouseButton(tester, kForwardMouseButton);
      await tester.pump();
      expect(tabs.state.activeTab!.path, entry.$2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      // SQLite and filesystem completions run outside the widget fake clock;
      // alternate real I/O and frames to finish the disposed hubs' pending reads.
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() async {
          final db = await SqliteDatabaseProvider().getDatabase();
          await db.rawQuery('SELECT 1');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump(const Duration(milliseconds: 200));
      }
    });
  }

  testWidgets(
    'mounted navigation bar reacts to history changes without parent rebuilding',
    (tester) async {
      await mount(tester, keepToolbarMounted: true);
      final tabId = tabs.state.activeTabId!;
      tabs.add(UpdateTabPath(tabId, '#gallery'));
      await tester.pump();
      await tester.tap(find.byIcon(PhosphorIconsLight.arrowLeft));
      await tester.pump();
      await tester.pump();
      expect(tabs.state.activeTab!.path, '#home');
      final forward = find.ancestor(
        of: find.byIcon(PhosphorIconsLight.arrowRight),
        matching: find.byType(fluent.IconButton),
      );
      expect(tester.widget<fluent.IconButton>(forward).onPressed, isNotNull);
      await tester.tap(forward);
      await tester.pump();
      await tester.pump();
      expect(tabs.state.activeTab!.path, '#gallery');
      expect(tester.widget<fluent.IconButton>(forward).onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      // SQLite and filesystem completions run outside the widget fake clock;
      // alternate real I/O and frames to finish the disposed hubs' pending reads.
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() async {
          final db = await SqliteDatabaseProvider().getDatabase();
          await db.rawQuery('SELECT 1');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump(const Duration(milliseconds: 200));
      }
    },
  );
}
