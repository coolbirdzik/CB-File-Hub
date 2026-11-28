import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/file_browser_options.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('browser-options-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async => root.path,
        );
    await UserPreferences.instance.init();
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    DatabaseManager.resetSingletonForE2ETest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await root.delete(recursive: true);
  });

  test('extension display preserves dotfiles and real file identity', () {
    const options = FileBrowserOptions(showExtensions: false);
    expect(options.fileLabel('photo.jpg'), 'photo');
    expect(options.fileLabel('archive.tar.gz'), 'archive.tar');
    expect(options.fileLabel('.gitignore'), '.gitignore');
    expect(options.fileLabel('README'), 'README');
    expect(options.fileLabel('.env.local'), '.env');
    expect(const FileBrowserOptions().fileLabel('a.exe'), 'a.exe');
    expect(FileBrowserOptions.fromJson(options.toJson()), options);
    expect(
      FileBrowserOptions.fromJson({'extensions': null}),
      const FileBrowserOptions(),
    );
  });

  test('settings persist in the shared preference database', () async {
    final prefs = UserPreferences.instance;
    final initial = prefs.fileBrowserOptions.value;
    addTearDown(() => prefs.setFileBrowserOptions(initial));
    const options = FileBrowserOptions(
      showExtensions: false,
      selectionCheckboxes: true,
      singleClickToOpen: true,
    );
    expect(await prefs.setFileBrowserOptions(options), isTrue);
    expect(prefs.fileBrowserOptions.value, options);
    final raw = await DatabaseManager.getInstance().getStringPreference(
      'file_browser_options_v1',
    );
    expect(
      FileBrowserOptions.fromJson(jsonDecode(raw!) as Map<String, dynamic>),
      options,
    );
  });

  test(
    'hidden and system filters act on real filesystem attributes and refresh an open folder',
    () async {
      final prefs = UserPreferences.instance;
      final initial = prefs.fileBrowserOptions.value;
      await prefs.setFileBrowserOptions(const FileBrowserOptions());
      final folder = await root.createTemp('listing-');
      final normal = await File(p.join(folder.path, 'normal.txt')).create();
      final hidden = await File(
        p.join(folder.path, Platform.isWindows ? 'hidden.txt' : '.hidden.txt'),
      ).create();
      final system = await File(p.join(folder.path, 'system.txt')).create();
      if (Platform.isWindows) {
        expect((await Process.run('attrib', ['+H', hidden.path])).exitCode, 0);
        expect((await Process.run('attrib', ['+S', system.path])).exitCode, 0);
      }
      final bloc = FileNavigationBloc();
      addTearDown(() async {
        await bloc.close();
        await prefs.setFileBrowserOptions(initial);
        if (Platform.isWindows) {
          await Process.run('attrib', ['-H', hidden.path]);
          await Process.run('attrib', ['-S', system.path]);
        }
        await folder.delete(recursive: true);
      });
      final all = [normal, hidden, system];
      final withoutHidden = await visibleBrowserEntries(
        all,
        const FileBrowserOptions(showHidden: false),
      );
      expect(
        withoutHidden.map((f) => f.path),
        unorderedEquals([normal.path, system.path]),
      );
      final withoutSystem = await visibleBrowserEntries(
        all,
        const FileBrowserOptions(showSystem: false),
      );
      expect(
        withoutSystem.map((f) => f.path),
        unorderedEquals(
          Platform.isWindows
              ? [normal.path, hidden.path]
              : all.map((f) => f.path),
        ),
      );

      final loaded = bloc.stream.firstWhere(
        (state) => !state.isLoading && state.files.length == 3,
      );
      bloc.add(FileNavigationLoad(folder.path));
      await loaded.timeout(const Duration(seconds: 15));
      final searched = bloc.stream.firstWhere(
        (state) => !state.isLoading && state.searchResults.length == 3,
      );
      bloc.add(const FileNavigationSearchByFileName(r'\.txt$', useRegex: true));
      await searched.timeout(const Duration(seconds: 15));
      final hiddenRefresh = bloc.stream.firstWhere(
        (state) =>
            !state.isLoading &&
            !state.isRefreshing &&
            state.files.length == 2 &&
            state.searchResults.length == 2,
      );
      await prefs.setFileBrowserOptions(
        const FileBrowserOptions(showHidden: false),
      );
      final filtered = await hiddenRefresh.timeout(const Duration(seconds: 15));
      expect(
        filtered.files.map((e) => e.path),
        unorderedEquals([normal.path, system.path]),
      );
      expect(
        filtered.searchResults.map((e) => e.path),
        unorderedEquals([normal.path, system.path]),
      );
      final shownRefresh = bloc.stream.firstWhere(
        (state) =>
            !state.isLoading &&
            !state.isRefreshing &&
            state.files.length == 3 &&
            state.searchResults.length == 3,
      );
      await prefs.setFileBrowserOptions(const FileBrowserOptions());
      final restored = await shownRefresh.timeout(const Duration(seconds: 15));
      expect(
        restored.files.map((e) => e.path),
        unorderedEquals(all.map((e) => e.path)),
      );
    },
  );

  test(
    'recursive search excludes hidden ancestors but direct navigation still works',
    () async {
      final folder = await root.createTemp('recursive-');
      final hiddenFolder = await Directory(
        p.join(folder.path, Platform.isWindows ? 'hidden' : '.hidden'),
      ).create();
      final child = await File(
        p.join(hiddenFolder.path, 'visible.txt'),
      ).create();
      if (Platform.isWindows) {
        expect(
          (await Process.run('attrib', ['+H', hiddenFolder.path])).exitCode,
          0,
        );
      }
      addTearDown(() async {
        if (Platform.isWindows) {
          await Process.run('attrib', ['-H', hiddenFolder.path]);
        }
        await folder.delete(recursive: true);
      });
      const options = FileBrowserOptions(showHidden: false);
      expect(
        await visibleBrowserEntries([child], options, rootPath: folder.path),
        isEmpty,
      );
      expect(
        await visibleBrowserEntries(
          [child],
          options,
          rootPath: hiddenFolder.path,
        ),
        [child],
      );
    },
  );
}
