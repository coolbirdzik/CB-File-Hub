import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory testRoot;

  setUpAll(() async {
    testRoot = await Directory.systemTemp.createTemp('folder-sort-manager-');
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
    await testRoot.delete(recursive: true);
  });

  test(
    '03.01 migrates legacy display preferences without rewriting thumbnail data',
    () async {
      final folder = await Directory(
        path.join(testRoot.path, 'legacy-folder'),
      ).create(recursive: true);
      final legacyFile = File(path.join(folder.path, '.cbfile_config.json'));
      await legacyFile.writeAsString(
        json.encode(<String, Object>{
          'viewMode': ViewMode.grid.index,
          'sortOption': SortOption.nameDesc.index,
          'folderThumbnail': 'thumbnail.jpg',
        }),
      );

      final manager = FolderSortManager();
      expect(await manager.getFolderViewMode(folder.path), ViewMode.grid);
      expect(
        await manager.getFolderSortOption(folder.path),
        SortOption.nameDesc,
      );

      await manager.saveFolderViewMode(folder.path, ViewMode.details);
      final legacy = json.decode(await legacyFile.readAsString()) as Map;
      expect(legacy['folderThumbnail'], 'thumbnail.jpg');
      expect(legacy['viewMode'], ViewMode.grid.index);

      final database = await DatabaseManager.getInstance().getDatabase();
      final stored = await database.query(
        'folder_display_preferences',
        where: 'path = ?',
        whereArgs: <Object?>[
          Platform.isWindows ? folder.path.toLowerCase() : folder.path,
        ],
      );
      expect(stored.single['view_mode'], ViewMode.details.index);
      expect(stored.single['sort_option'], SortOption.nameDesc.index);
    },
  );

  test('03.02 persists virtual paths in SQLite', () async {
    const virtualPath = '#network/server/share';
    final manager = FolderSortManager();

    expect(
      await manager.saveFolderSortOption(virtualPath, SortOption.dateDesc),
      isTrue,
    );

    final database = await DatabaseManager.getInstance().getDatabase();
    final stored = await database.query(
      'folder_display_preferences',
      where: 'path = ?',
      whereArgs: <Object?>[virtualPath],
    );
    expect(stored.single['sort_option'], SortOption.dateDesc.index);
  });
}
