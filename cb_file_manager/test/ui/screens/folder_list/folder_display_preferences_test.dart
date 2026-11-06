import 'dart:io';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/directory_listing_cache_service.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_display_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory testRoot;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    testRoot = await Directory.systemTemp.createTemp('folder-display-prefs-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (methodCall) async {
          switch (methodCall.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
              return testRoot.path;
            default:
              return null;
          }
        });
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    DatabaseManager.resetSingletonForE2ETest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      await testRoot.delete(recursive: true);
    } on FileSystemException {
      // The directory watcher may still hold the folder; it is a temp dir.
    }
  });

  String key(String folder) =>
      Platform.isWindows ? path.normalize(folder).toLowerCase() : folder;

  test('warm-up answers saved folders and defaults without waiting', () async {
    final prefs = UserPreferences.instance;
    await prefs.init();
    await prefs.setViewMode(ViewMode.grid);
    await prefs.setSortOption(SortOption.dateDesc);

    // Stored by an earlier session: only on disk, not in memory yet.
    final saved = path.join(testRoot.path, 'photos');
    final database = await DatabaseManager.getInstance().getDatabase();
    await database.insert('folder_display_preferences', {
      'path': key(saved),
      'view_mode': ViewMode.details.index,
      'sort_option': SortOption.sizeDesc.index,
      'column_visibility_json': '{"tags":true,"order":["tags"]}',
      'updated_at': 0,
    });

    final displays = FolderDisplayPreferences.instance;
    expect(displays.cached(saved), isNull, reason: 'nothing loaded yet');
    await displays.warmUp();

    final photos = displays.cached(saved)!;
    expect(photos.viewMode, ViewMode.details);
    expect(photos.sortOption, SortOption.sizeDesc);
    expect(photos.columnVisibility.visibleColumns.take(2), [
      DetailsColumn.name,
      DetailsColumn.tags,
    ]);

    // A folder without settings follows the defaults, also synchronously.
    final plain = displays.cached(path.join(testRoot.path, 'plain'))!;
    expect(plain.viewMode, ViewMode.grid);
    expect(plain.sortOption, SortOption.dateDesc);
  });

  test('saving a folder or a default updates what cached() returns', () async {
    final displays = FolderDisplayPreferences.instance;
    await displays.warmUp();
    final folder = path.join(testRoot.path, 'music');

    await FolderSortManager().saveFolderViewMode(folder, ViewMode.tiles);
    expect(displays.cached(folder)!.viewMode, ViewMode.tiles);

    await UserPreferences.instance.setSortOption(SortOption.nameDesc);
    expect(
      displays.cached(folder),
      isNull,
      reason: 'defaults changed; they must be read again',
    );
    final resolved = await displays.resolve(folder);
    expect(resolved.sortOption, SortOption.nameDesc);
    expect(resolved.viewMode, ViewMode.tiles);
    expect(displays.cached(folder)!.sortOption, SortOption.nameDesc);
  });

  test(
    'a load shows the folder in its saved layout from the first emit',
    () async {
      final folder = await Directory(
        path.join(testRoot.path, 'docs'),
      ).create(recursive: true);
      for (final name in ['a.txt', 'bb.txt', 'ccc.txt']) {
        await File(path.join(folder.path, name)).writeAsString(name * 50);
      }
      await FolderSortManager().saveFolderViewMode(
        folder.path,
        ViewMode.details,
      );
      await FolderSortManager().saveFolderSortOption(
        folder.path,
        SortOption.sizeDesc,
      );
      await FolderDisplayPreferences.instance.warmUp();

      final bloc = FileNavigationBloc(applyFolderDisplay: true);
      addTearDown(bloc.close);
      final states = <FileNavigationState>[];
      final sub = bloc.stream.listen(states.add);
      addTearDown(sub.cancel);
      bloc.add(FileNavigationLoad(folder.path));
      await bloc.stream.firstWhere((s) => !s.isLoading && s.files.length == 3);

      final forFolder = states.where((s) => s.currentPath.path == folder.path);
      expect(forFolder.map((s) => (s.viewMode, s.sortOption)).toSet(), {
        (ViewMode.details, SortOption.sizeDesc),
      }, reason: 'no emit for the folder may carry another layout');
      expect(states.last.files.map((f) => path.basename(f.path)), [
        'ccc.txt',
        'bb.txt',
        'a.txt',
      ]);
    },
  );

  group('view mode fallback policy', () {
    final prefs = UserPreferences.instance;
    final displays = FolderDisplayPreferences.instance;
    late Directory fixture;

    setUp(() async {
      fixture = await testRoot.createTemp('view-policy-');
      await prefs.setViewMode(ViewMode.list);
      await prefs.setSortOption(SortOption.nameAsc);
      await prefs.setFolderViewModePreference(
        FolderViewModePreference.mediaGrid,
      );
    });

    test(
      'unknown media layouts wait for classification, saved layouts do not',
      () async {
        await displays.warmUp();
        expect(displays.needsListingForViewMode(fixture.path), isTrue);
        await displays.resolve(
          fixture.path,
          files: [File(path.join(fixture.path, 'photo.jpg'))],
          folders: [],
        );
        expect(displays.needsListingForViewMode(fixture.path), isFalse);
        final saved = path.join(fixture.path, 'saved');
        await FolderSortManager().saveFolderViewMode(saved, ViewMode.details);
        expect(displays.needsListingForViewMode(saved), isFalse);
        await prefs.setFolderViewModePreference(
          FolderViewModePreference.inheritParent,
        );
        await displays.warmUp();
        expect(
          displays.needsListingForViewMode(path.join(fixture.path, 'new')),
          isFalse,
        );
      },
    );

    test(
      'policy persists and invalid values fall back to media Grid',
      () async {
        await prefs.setFolderViewModePreference(
          FolderViewModePreference.inheritParent,
        );
        expect(
          await prefs.getFolderViewModePreference(),
          FolderViewModePreference.inheritParent,
        );
        await displays.warmUp();
        await prefs.setFolderViewModePreference(
          FolderViewModePreference.mediaGrid,
        );
        expect(displays.cached(fixture.path), isNull);
        await DatabaseManager.getInstance().saveStringPreference(
          'folder_view_mode_preference',
          'unknown',
        );
        expect(
          await prefs.getFolderViewModePreference(),
          FolderViewModePreference.mediaGrid,
        );
      },
    );

    test('only nonempty photo/video-only folders default to Grid', () async {
      for (final (names, folders, expected)
          in <(List<String>, List<Directory>, ViewMode)>[
            (['photo.JPG'], [], ViewMode.grid),
            (['clip.mp4'], [], ViewMode.grid),
            (['photo.webp', 'clip.MKV'], [], ViewMode.grid),
            (['photo.jpg', 'notes.txt'], [], ViewMode.list),
            (['photo.jpg', 'song.mp3'], [], ViewMode.list),
            ([], [], ViewMode.list),
            (
              ['photo.jpg'],
              [Directory(path.join(fixture.path, 'nested'))],
              ViewMode.list,
            ),
          ]) {
        final settings = await displays.resolve(
          fixture.path,
          files: names
              .map((name) => File(path.join(fixture.path, name)))
              .toList(),
          folders: folders,
        );
        expect(settings.viewMode, expected, reason: '$names / $folders');
        expect(displays.cached(fixture.path)!.viewMode, expected);
        expect(
          await FolderSortManager().getFolderViewMode(fixture.path),
          isNull,
          reason: 'automatic layouts must not become explicit preferences',
        );
      }
    });

    test(
      'saved view wins over media Grid while other overrides stay intact',
      () async {
        await FolderSortManager().saveFolderSortOption(
          fixture.path,
          SortOption.sizeDesc,
        );
        final automatic = await displays.resolve(
          fixture.path,
          files: [File(path.join(fixture.path, 'photo.jpg'))],
          folders: [],
        );
        expect(automatic.viewMode, ViewMode.grid);
        expect(automatic.sortOption, SortOption.sizeDesc);
        await FolderSortManager().saveFolderViewMode(
          fixture.path,
          ViewMode.details,
        );
        expect(
          (await displays.resolve(fixture.path)).viewMode,
          ViewMode.details,
        );
        expect(displays.cached(fixture.path)!.viewMode, ViewMode.details);
      },
    );

    test(
      'inheritance uses nearest saved ancestor and only its view mode',
      () async {
        await prefs.setFolderViewModePreference(
          FolderViewModePreference.inheritParent,
        );
        final parent = path.join(fixture.path, 'parent');
        final child = path.join(parent, 'child');
        await FolderSortManager().saveFolderViewMode(
          fixture.path,
          ViewMode.details,
        );
        await FolderSortManager().saveFolderSortOption(
          fixture.path,
          SortOption.sizeDesc,
        );
        await FolderSortManager().saveFolderGridZoomLevel(fixture.path, 7);
        await FolderSortManager().saveFolderSortOption(
          parent,
          SortOption.dateAsc,
        );
        await displays.warmUp();

        final inherited = await displays.resolve(child);
        expect(inherited.viewMode, ViewMode.details);
        expect(inherited.sortOption, SortOption.nameAsc);
        expect(inherited.gridZoomLevel, await prefs.getGridZoomLevel());
        expect(displays.cached(child)!.viewMode, ViewMode.details);

        await FolderSortManager().saveFolderViewMode(parent, ViewMode.tiles);
        expect(displays.cached(child)!.viewMode, ViewMode.tiles);
        await FolderSortManager().saveFolderViewMode(child, ViewMode.tree);
        expect((await displays.resolve(child)).viewMode, ViewMode.tree);
        expect(displays.cached(child)!.viewMode, ViewMode.tree);
      },
    );

    test('inheritance without a saved ancestor uses global default', () async {
      await prefs.setFolderViewModePreference(
        FolderViewModePreference.inheritParent,
      );
      await prefs.setViewMode(ViewMode.tiles);
      expect((await displays.resolve(fixture.path)).viewMode, ViewMode.tiles);
      expect((await displays.resolve('#drives')).viewMode, ViewMode.tiles);
      expect(
        (await displays.resolve('smb://server/share')).viewMode,
        ViewMode.tiles,
      );
    });

    for (final policy in FolderViewModePreference.values) {
      test('$policy applies on cold load, cached load and refresh', () async {
        await prefs.setFolderViewModePreference(policy);
        await FolderSortManager().saveFolderViewMode(
          fixture.path,
          ViewMode.details,
        );
        final folder = await Directory(
          path.join(fixture.path, 'photos'),
        ).create();
        await File(
          path.join(folder.path, 'photo.jpg'),
        ).writeAsString('photo fixture');
        await displays.warmUp();
        final bloc = FileNavigationBloc(applyFolderDisplay: true);
        addTearDown(bloc.close);
        final expected = policy == FolderViewModePreference.mediaGrid
            ? ViewMode.grid
            : ViewMode.details;
        Future<FileNavigationState> loaded(int count) => bloc.stream
            .firstWhere(
              (s) =>
                  !s.isLoading &&
                  !s.isRefreshing &&
                  s.currentPath.path == folder.path &&
                  s.files.length == count,
            )
            .timeout(const Duration(seconds: 10));

        var done = loaded(1);
        bloc.add(FileNavigationLoad(folder.path));
        expect((await done).viewMode, expected);
        // Let the load finish storing its listing and starting the watcher.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          DirectoryListingCacheService.instance.getListing(folder.path),
          isNotNull,
        );
        done = loaded(1);
        bloc.add(FileNavigationLoad(folder.path));
        expect((await done).viewMode, expected);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // A mixed folder ceases to be media-only after refresh.
        await File(path.join(folder.path, 'notes.txt')).writeAsString('notes');
        done = loaded(2);
        bloc.add(FileNavigationRefresh(folder.path));
        expect(
          (await done).viewMode,
          policy == FolderViewModePreference.mediaGrid
              ? ViewMode.list
              : ViewMode.details,
        );

        // A later explicit choice takes precedence in either policy.
        await FolderSortManager().saveFolderViewMode(
          folder.path,
          ViewMode.tiles,
        );
        done = loaded(2);
        bloc.add(FileNavigationRefresh(folder.path));
        expect((await done).viewMode, ViewMode.tiles);
      });
    }
  });
}
