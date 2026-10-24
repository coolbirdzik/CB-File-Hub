import 'package:cb_file_manager/services/directory_watcher_service.dart';
import 'dart:io';

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/models/objectbox/video_library.dart';
import 'package:cb_file_manager/ui/screens/system_screen_router.dart';
import 'package:cb_file_manager/ui/screens/video_library/video_hub_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_file_surface.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/video_library/video_library_files_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/components/search_bar.dart'
    as search;
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_window_transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import 'network_browsing/network_recovery_test.dart' show host;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb-library-search-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          // This widget test exercises metadata, not background debug-log IO.
          if (call.method == 'getTemporaryDirectory') return null;
          return root.path;
        });
    locator.registerSingleton(OperationProgressController());
    await TagManager.initialize();
  });
  tearDownAll(() async {
    await DirectoryWatcherService.instance.stopWatching();
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await locator.reset();
    await root.delete(recursive: true);
  });

  testWidgets(
    'moving a loaded gallery retains files, search, selection and scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final library = VideoLibrary(name: 'Transferred collection')..id = 94001;
      final files = List.generate(
        80,
        (i) => path.join(root.path, 'clip-$i.mp4'),
      );
      final tab = TabData(
        id: 'loaded-gallery-transfer',
        name: library.name,
        path: '#video-library/${library.id}',
      );
      addTearDown(() => TabWindowTransfer.forget(tab.id));
      TabWindowTransfer.restore(
        WindowTabPayload(
          path: tab.path,
          session: {
            'id': tab.id,
            'view': {
              'library': library.toDatabaseMap(),
              'loadedFiles': files,
              'viewMode': ViewMode.list.name,
              'sortOption': SortOption.nameAsc.name,
              'gridZoomLevel': 3,
              'showFileTags': false,
              'columns': const ColumnVisibility().toMap(),
              'query': 'clip',
              'searchBar': true,
              'selection': [files[5]],
              'lastSelected': files[5],
            },
          },
        ),
      );
      final tabs = TabManagerBloc();
      addTearDown(tabs.close);
      Widget destination() => host(
        BlocProvider.value(
          value: tabs,
          child: Material(
            child: Builder(
              builder: (context) => SystemScreenRouter.routeSystemPath(
                context,
                tab.path,
                tab.id,
              )!,
            ),
          ),
        ),
      );
      BrowserLikeFileSurface surface() =>
          tester.widget(find.byType(BrowserLikeFileSurface));
      await tester.pumpWidget(destination());
      await tester.pump();
      expect(surface().visiblePaths, files);
      expect(surface().selectionState.selectedFilePaths, {files[5]});
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      scrollable.position.jumpTo(350);
      await tester.pump();
      final moved = TabWindowTransfer.capture(tab);
      expect(moved.session!['view']['scroll'], 350);
      await tester.pumpWidget(const SizedBox.shrink());

      // This id has no database library or file cache. The new screen must draw
      // the snapshot, without a metadata spinner or a second filesystem scan.
      TabWindowTransfer.restore(moved);
      await tester.pumpWidget(destination());
      await tester.pump();
      expect(surface().visiblePaths, files);
      expect(surface().selectionState.selectedFilePaths, {files[5]});
      expect((surface().searchBar as search.SearchBar).initialQuery, 'clip');
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .pixels,
        350,
      );
      final state = tester.state(find.byType(VideoLibraryFilesScreen));
      tester.view.physicalSize = const Size(900, 500);
      await tester.pump();
      expect(tester.state(find.byType(VideoLibraryFilesScreen)), same(state));
      expect(surface().visiblePaths, files);
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'video hub transferred libraries appear without loading placeholders',
    (tester) async {
      const id = 'video-hub-transfer';
      final library = VideoLibrary(name: 'Already visible library')..id = 94002;
      TabWindowTransfer.restore(
        WindowTabPayload(
          path: '#video',
          session: {
            'id': id,
            'view': {
              'libraries': [library.toDatabaseMap()],
              'counts': {'94002': 25},
              'scroll': 0.0,
            },
          },
        ),
      );
      addTearDown(() => TabWindowTransfer.forget(id));
      final tabs = TabManagerBloc();
      addTearDown(tabs.close);
      await tester.pumpWidget(
        host(
          BlocProvider.value(
            value: tabs,
            child: const Material(child: VideoHubScreen(tabId: id)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(library.name), findsOneWidget);
      final captured = TabWindowTransfer.capture(
        TabData(id: id, name: 'Videos', path: '#video'),
      );
      expect(captured.session!['view']['counts'], {'94002': 25});
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh retains query and removes deleted video from search', (
    tester,
  ) async {
    final service = VideoLibraryService();
    final media = await tester.runAsync(() async {
      final directory = await Directory(path.join(root.path, 'media')).create();
      await File(path.join(directory.path, 'holiday.mp4')).writeAsBytes([0]);
      await File(path.join(directory.path, 'other.mp4')).writeAsBytes([0]);
      return directory;
    });
    final library = await tester.runAsync(
      () => service.createLibrary(
        name: 'Search refresh',
        directories: [media!.path],
      ),
    );
    await tester.pumpWidget(host(VideoLibraryFilesScreen(library: library!)));

    BrowserLikeFileSurface surface() => tester.widget<BrowserLikeFileSurface>(
      find.byType(BrowserLikeFileSurface),
    );
    Future<void> waitFor(bool Function() predicate) async {
      for (var i = 0; i < 150 && !predicate(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(predicate(), isTrue);
    }

    await waitFor(
      () =>
          find.byType(BrowserLikeFileSurface).evaluate().isNotEmpty &&
          surface().visiblePaths.length == 2,
    );
    final bar = surface().searchBar as search.SearchBar;
    bar.onSearchWithOptions!('holiday', false);
    await waitFor(() => surface().visiblePaths.length == 1);
    // Let the separate live search source finish before mutating the filesystem.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    final deleted = File(path.join(media!.path, 'holiday.mp4'));
    await tester.runAsync(deleted.delete);
    surface().onRefresh!();
    await waitFor(() => surface().visiblePaths.isEmpty);
    expect((surface().searchBar as search.SearchBar).initialQuery, 'holiday');
    await tester.pumpWidget(const SizedBox.shrink());
    // Drain real filesystem completions and their fake-async continuations.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a freshly opened library never shows the default view first', (
    tester,
  ) async {
    final service = VideoLibraryService();
    final media = await tester.runAsync(() async {
      final directory = await Directory(
        path.join(root.path, 'saved-view'),
      ).create();
      await File(path.join(directory.path, 'clip.mp4')).writeAsBytes([0]);
      return directory;
    });
    final library = await tester.runAsync(() async {
      final created = await service.createLibrary(
        name: 'Saved view',
        directories: [media!.path],
      );
      final prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setVideoLibraryViewMode(created!.id, ViewMode.details);
      return created;
    });

    // The details rows use ink, which the app's scaffold provides.
    await tester.pumpWidget(
      host(Material(child: VideoLibraryFilesScreen(library: library!))),
    );
    final shownModes = <ViewMode>{};
    for (var i = 0; i < 150; i++) {
      final surfaces = find.byType(BrowserLikeFileSurface).evaluate();
      if (surfaces.isNotEmpty) {
        final surface = surfaces.single.widget as BrowserLikeFileSurface;
        if (surface.visiblePaths.isNotEmpty) {
          shownModes.add(surface.viewMode);
          if (i > 20) break;
        }
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Files only ever appeared in the saved view.
    expect(shownModes, {ViewMode.details});

    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a library tab moved from another window draws its view at once',
    (tester) async {
      final service = VideoLibraryService();
      final library = await tester.runAsync(() async {
        final directory = await Directory(
          path.join(root.path, 'moved-view'),
        ).create();
        await File(path.join(directory.path, 'clip.mp4')).writeAsBytes([0]);
        return service.createLibrary(
          name: 'Moved view',
          directories: [directory.path],
        );
      });
      // What the source window's screen captured for its tab.
      TabWindowTransfer.restore(
        WindowTabPayload(
          path: '#video-library/${library!.id}',
          session: {
            'id': 'moved-library-tab',
            'view': {
              'viewMode': ViewMode.grid.name,
              'sortOption': SortOption.sizeDesc.name,
              'gridZoomLevel': 5,
              'showFileTags': false,
              'columns': const ColumnVisibility().toMap(),
            },
          },
        ),
      );

      await tester.pumpWidget(
        host(
          Material(
            child: VideoLibraryFilesScreen(
              library: library,
              tabId: 'moved-library-tab',
            ),
          ),
        ),
      );
      BrowserLikeFileSurface surface() => tester.widget<BrowserLikeFileSurface>(
        find.byType(BrowserLikeFileSurface),
      );
      // The localizations load first. From the screen's first frame on it uses
      // the moved view: no blank page while this window's preferences load
      // (nothing was saved here, which would mean the default list view).
      for (var i = 0; i < 50; i++) {
        if (find.byType(BrowserLikeFileSurface).evaluate().isNotEmpty) break;
        await tester.pump();
      }
      expect(surface().viewMode, ViewMode.grid);
      for (var i = 0; i < 150 && surface().visiblePaths.isEmpty; i++) {
        expect(surface().viewMode, ViewMode.grid);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(surface().visiblePaths, hasLength(1));
      expect(surface().viewMode, ViewMode.grid);

      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    },
  );
}
