import 'dart:io';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
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
}
