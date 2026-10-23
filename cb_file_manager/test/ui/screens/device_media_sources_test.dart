import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/device_media_sources.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cb_file_manager/ui/screens/system_screen_router.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:cb_file_manager/ui/tab_manager/components/navigation_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../services/device_media_library_test.dart'
    show FakeDeviceMediaAccess;

void main() {
  late TabManagerBloc tabs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => tabs.close());

  Future<void> settle(WidgetTester tester) async {
    // Bloc stream notifications can arrive after a frame has already settled.
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    FakeDeviceMediaAccess access, {
    RequestType type = RequestType.image,
    String? initialPath,
  }) async {
    tabs = TabManagerBloc();
    tabs.add(
      AddTab(
        path:
            initialPath ?? (type == RequestType.video ? '#video' : '#gallery'),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      BlocProvider.value(
        value: tabs,
        child: fluent.FluentApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Theme(
            data: ThemeData.light(),
            child: BlocBuilder<TabManagerBloc, TabManagerState>(
              builder: (context, state) {
                final tab = state.activeTab!;
                if (DeviceMediaPath.tryParse(tab.path) != null) {
                  // Use the real router, with a fake OS media backend in tests.
                  final screen =
                      SystemScreenRouter.routeSystemPath(
                            context,
                            tab.path,
                            tab.id,
                          )!
                          as DeviceMediaAlbumScreen;
                  return DeviceMediaAlbumScreen(
                    key: screen.key,
                    tabId: screen.tabId,
                    location: screen.location,
                    access: access,
                  );
                }
                return Scaffold(
                  key: ValueKey(tab.path),
                  body: DeviceMediaSources(
                    tabId: tab.id,
                    type: type,
                    access: access,
                    builder: (context, sources, loading, refresh) =>
                        RefreshIndicator(
                          onRefresh: refresh,
                          child: GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisExtent: 160,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: sources.length + 1,
                            itemBuilder: (context, index) => index == 0
                                ? const Center(child: Text('Custom sources'))
                                : sources[index - 1].buildTile(context),
                          ),
                        ),
                    child: const Center(child: Text('Custom sources')),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  for (final type in [RequestType.image, RequestType.video]) {
    testWidgets(
      '$type: automatic All and existing albums coexist with custom sources',
      (tester) async {
        final access = FakeDeviceMediaAccess()
          ..paths = [
            AssetPathEntity(id: 'all', name: 'Recent', isAll: true, type: type),
            AssetPathEntity(id: 'camera', name: 'Camera', type: type),
          ];
        await mount(tester, access, type: type);
        expect(
          find.text(type == RequestType.video ? 'All Videos' : 'All Images'),
          findsOneWidget,
        );
        expect(find.text('Camera'), findsOneWidget);
        expect(find.text('Custom sources'), findsOneWidget);
        expect(find.byType(GridView), findsOneWidget);
        expect(find.text('On this device'), findsNothing);
        final grid = find.byType(GridView);
        for (final title in ['Custom sources', 'Camera']) {
          expect(
            find.descendant(of: grid, matching: find.text(title)),
            findsOneWidget,
          );
        }
        await tester.tap(find.text('Camera'));
        await settle(tester);
        expect(find.byType(DeviceMediaAlbumScreen), findsOneWidget);
        final albumPath = DeviceMediaPath(
          isVideo: type == RequestType.video,
          albumId: 'camera',
        ).path;
        final tabId = tabs.state.activeTabId!;
        expect(tabs.state.tabs, hasLength(1));
        expect(tabs.state.activeTab!.path, albumPath);
        expect(tabs.state.activeTab!.name, 'Camera');
        expect(
          tester.state<NavigatorState>(find.byType(Navigator).first).canPop(),
          isFalse,
        );
        final navigation = tester.widget<PathNavigationBar>(
          find.byType(PathNavigationBar),
        );
        expect(navigation.currentPath, albumPath);
        expect(navigation.canNavigateToParent, isTrue);
        tabs.backNavigationToPath(tabId);
        await settle(tester);
        expect(tabs.state.activeTabId, tabId);
        expect(find.text('Custom sources'), findsOneWidget);
        expect(tabs.state.activeTab!.forwardHistory, [albumPath]);
        tabs.forwardNavigationToPath(tabId);
        await settle(tester);
        expect(tabs.state.activeTab!.path, albumPath);
        expect(tabs.state.activeTab!.name, 'Camera');
        expect(
          find.text(
            type == RequestType.video
                ? 'No videos found in this folder'
                : 'No images found in this folder',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty device still provides All', (tester) async {
    await mount(tester, FakeDeviceMediaAccess());
    expect(find.text('All Images'), findsOneWidget);
    await tester.tap(find.text('All Images'));
    await settle(tester);
    expect(find.byType(DeviceMediaAlbumScreen), findsOneWidget);
    expect(tabs.state.activeTab!.path, '#gallery/device');
    expect(tabs.state.tabs, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'denied access keeps custom sources usable and offers permission recovery',
    (tester) async {
      final access = FakeDeviceMediaAccess()..state = PermissionState.denied;
      await mount(tester, access);
      expect(find.text('Custom sources'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
      await tester.tap(find.text('All Images'));
      await settle(tester);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Camera'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop does not request mobile permissions', (tester) async {
    final access = FakeDeviceMediaAccess()..supported = false;
    await mount(tester, access);
    expect(access.requests, isEmpty);
    expect(find.text('On this device'), findsNothing);
    expect(find.text('Custom sources'), findsOneWidget);
  });

  testWidgets(
    'limited access shows recovery and clears an open album after revocation',
    (tester) async {
      final access = FakeDeviceMediaAccess()
        ..state = PermissionState.limited
        ..paths = [AssetPathEntity(id: 'all', name: 'Recent', isAll: true)];
      await mount(tester, access);
      expect(find.text('Choose more photos and videos'), findsNothing);
      await tester.tap(find.text('All Images'));
      await settle(tester);
      expect(find.text('Choose more photos and videos'), findsOneWidget);
      access.state = PermissionState.denied;
      await tester.pump();
      final screen = tester.widget<DeviceMediaAlbumScreen>(
        find.byType(DeviceMediaAlbumScreen),
      );
      final bar = tester.widget<PathNavigationBar>(
        find.byType(PathNavigationBar),
      );
      expect(bar.currentPath, screen.location.path);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await settle(tester);
      expect(find.text('No images found in this folder'), findsNothing);
      expect(find.text('Open Settings').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final isVideo in [false, true]) {
    testWidgets('restore a device album from its path (video: $isVideo)', (
      tester,
    ) async {
      const albumId = 'album/ảnh +%2F?東京';
      final type = isVideo ? RequestType.video : RequestType.image;
      final location = DeviceMediaPath(isVideo: isVideo, albumId: albumId);
      final access = FakeDeviceMediaAccess()
        ..paths = [
          AssetPathEntity(id: albumId, name: 'Existing album', type: type),
        ];
      await mount(tester, access, type: type, initialPath: location.path);
      expect(find.byType(DeviceMediaAlbumScreen), findsOneWidget);
      expect(tabs.state.activeTab!.path, location.path);
      expect(tabs.state.activeTab!.name, 'Existing album');
      expect(access.requests, contains((type, true)));
      final navigation = tester.widget<PathNavigationBar>(
        find.byType(PathNavigationBar),
      );
      navigation.onNavigateToParent!();
      await settle(tester);
      expect(tabs.state.activeTab!.path, location.parentPath);
      expect(tabs.state.tabs, hasLength(1));
      expect(find.text('Custom sources'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
