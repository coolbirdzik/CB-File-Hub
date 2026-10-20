import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/core/sidebar_pins_repository.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/filesystem/macos_user_folders_service.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

class _UserFolders extends MacosUserFoldersService {
  final List<MacosUserFolder> folders;
  var calls = 0;
  _UserFolders(this.folders, {super.platform});
  @override
  Future<List<MacosUserFolder>> load() async {
    calls++;
    return folders;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late Database db;
  late SidebarPinsRepository pins;
  late List<MacosUserFolder> folders;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb-sidebar-favorites-');
    messenger.setMockMethodCallHandler(pathChannel, (_) async => root.path);
    SharedPreferences.setMockInitialValues({});
    await UserPreferences.instance.init();
    db = await DatabaseManager.getInstance().getDatabase();
    folders = [
      for (final kind in MacosUserFolderKind.values)
        MacosUserFolder(kind: kind, path: '${root.path}/${kind.name}'),
    ];
    for (final folder in folders) {
      await Directory(folder.path).create();
    }
  });

  setUp(() async {
    await db.delete('preferences');
    pins = SidebarPinsRepository(db);
  });

  tearDownAll(() async {
    await SqliteDatabaseProvider.closeSharedDatabase();
    messenger.setMockMethodCallHandler(pathChannel, null);
    await root.delete(recursive: true);
  });

  test(
    'native folder contract accepts redirected paths and rejects malformed rows',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(MacosUserFoldersService.channel, (
        call,
      ) async {
        calls.add(call.method);
        return [
          {'kind': 'applications', 'path': '/Applications'},
          {'kind': 'documents', 'path': '/Volumes/Work/My Documents'},
          {'kind': 'documents', 'path': '/ignored-duplicate-kind'},
          {'kind': 'downloads', 'path': '/Applications/'},
          {'kind': 'desktop', 'path': 'relative/Desktop'},
          {'kind': 'unknown', 'path': '/unknown'},
          {'kind': 'movies', 'path': 7},
          null,
        ];
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          MacosUserFoldersService.channel,
          null,
        ),
      );
      final resolved = await MacosUserFoldersService(
        platform: TargetPlatform.macOS,
      ).load();
      expect(resolved, const [
        MacosUserFolder(
          kind: MacosUserFolderKind.applications,
          path: '/Applications',
        ),
        MacosUserFolder(
          kind: MacosUserFolderKind.documents,
          path: '/Volumes/Work/My Documents',
        ),
      ]);
      expect(
        await MacosUserFoldersService(platform: TargetPlatform.windows).load(),
        isEmpty,
      );
      expect(calls, ['getSidebarUserFolders']);
    },
  );

  test(
    'seeds existing accounts once, deduplicates and preserves manual pin order',
    () async {
      final downloads = folders
          .firstWhere((folder) => folder.kind == MacosUserFolderKind.downloads)
          .path;
      await DatabaseManager.getInstance().saveStringPreference(
        SidebarPinsRepository.pathsKey,
        jsonEncode(['/custom/first', '$downloads/', '/custom/second']),
      );
      final defaults = folders.map((folder) => folder.path).toList();
      await pins.seedMacosDefaults(defaults);
      expect(await pins.read(validateDirectories: false), [
        ...defaults,
        '/custom/first',
        '/custom/second',
      ]);
      final before = await db.query('preferences', orderBy: 'key');
      await pins.seedMacosDefaults(defaults);
      expect(await db.query('preferences', orderBy: 'key'), before);
      await pins.setPinned(downloads, pinned: false);
      await SidebarPinsRepository(db).seedMacosDefaults(defaults);
      expect(await pins.contains(downloads), isFalse);
      for (final path in await pins.read(validateDirectories: false)) {
        await pins.setPinned(path, pinned: false);
      }
      await SidebarPinsRepository(db).seedMacosDefaults(defaults);
      expect(await pins.read(validateDirectories: false), isEmpty);
    },
  );

  test(
    'empty native results can retry and concurrent initialization preserves custom pins',
    () async {
      await pins.seedMacosDefaults([]);
      expect(await db.query('preferences'), isEmpty);
      final otherWindow = SidebarPinsRepository(db);
      await Future.wait([
        pins.seedMacosDefaults(folders.map((folder) => folder.path).toList()),
        otherWindow.seedMacosDefaults(
          folders.map((folder) => folder.path).toList(),
        ),
        otherWindow.setPinned('/custom/concurrent', pinned: true),
      ]);
      final paths = await pins.read(validateDirectories: false);
      expect(paths.toSet().length, folders.length + 1);
      expect(paths.length, folders.length + 1);
      expect(paths, contains('/custom/concurrent'));
    },
  );

  test(
    'a failed marker write rolls back pins and permits a complete retry',
    () async {
      await pins.setPinned('/custom/existing', pinned: true);
      await db.execute(
        "CREATE TEMP TRIGGER reject_sidebar_seed BEFORE INSERT ON preferences WHEN NEW.key = 'macos_sidebar_defaults_v1' BEGIN SELECT RAISE(ABORT, 'injected marker failure'); END",
      );
      await expectLater(
        pins.seedMacosDefaults([folders.first.path]),
        throwsA(isA<DatabaseException>()),
      );
      expect(await pins.read(validateDirectories: false), ['/custom/existing']);
      await db.execute('DROP TRIGGER reject_sidebar_seed');
      await pins.seedMacosDefaults([folders.first.path]);
      expect(await pins.read(validateDirectories: false), [
        folders.first.path,
        '/custom/existing',
      ]);
    },
  );

  test(
    'validation retains stored unavailable folders and accepts pinned files',
    () async {
      final file = await File('${root.path}/notes.txt').writeAsString('Notes');
      await pins.setPinned(file.path, pinned: true);
      await pins.setPinned('${root.path}/offline', pinned: true);
      expect(await pins.read(), [file.path]);
      expect(await pins.read(validateDirectories: false), [
        '${root.path}/offline',
        file.path,
      ]);
    },
  );

  test(
    'macOS drawer opens Favorites, remembers collapse and honors unpin after reload',
    () async {
      final loader = _UserFolders(folders, platform: TargetPlatform.macOS);
      final drawer = DrawerCubit(userFolders: loader);
      final reopened = DrawerCubit(userFolders: loader);
      addTearDown(drawer.close);
      addTearDown(reopened.close);
      await UserPreferences.instance.setDrawerSectionExpanded(
        tabId: 'first',
        sectionKey: 'pinned',
        isExpanded: false,
      );
      await UserPreferences.instance.setLastDrawerSectionExpanded(
        sectionKey: 'pinned',
        isExpanded: false,
      );
      await drawer.loadStorageLocations(activeTabId: 'first');
      expect(
        drawer.state.pinnedPaths,
        folders.map((folder) => folder.path).toList(),
      );
      expect(drawer.state.macosUserFolders, folders);
      expect(drawer.state.isPinnedExpanded, isTrue);
      await drawer.setPinnedExpanded(false);
      await drawer.togglePinnedPath(folders.first.path);
      await reopened.loadStorageLocations(activeTabId: 'reopened');
      expect(reopened.state.isPinnedExpanded, isFalse);
      expect(reopened.state.pinnedPaths, isNot(contains(folders.first.path)));
      expect(reopened.state.macosUserFolders, folders);
    },
  );

  test(
    'Windows drawer retains its manual pins and does not seed macOS defaults',
    () async {
      await pins.setPinned(root.path, pinned: true);
      final loader = _UserFolders(folders, platform: TargetPlatform.windows);
      final drawer = DrawerCubit(userFolders: loader);
      addTearDown(drawer.close);
      await drawer.loadStorageLocations(activeTabId: 'windows');
      expect(loader.calls, 0);
      expect(drawer.state.pinnedPaths, [root.path]);
      expect(drawer.state.macosUserFolders, isEmpty);
      expect(drawer.state.isPinnedExpanded, isFalse);
      expect(
        await db.query(
          'preferences',
          where: 'key = ?',
          whereArgs: ['macos_sidebar_defaults_v1'],
        ),
        isEmpty,
      );
    },
  );
}
