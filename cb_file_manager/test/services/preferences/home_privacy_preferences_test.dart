import 'dart:io';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  final prefs = UserPreferences.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('home-privacy-prefs-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => root.path);
    await prefs.init();
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    DatabaseManager.resetSingletonForE2ETest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await root.delete(recursive: true);
  });

  test('existing users keep recent folders visible by default', () async {
    await DatabaseManager.getInstance().deletePreference(
      'show_recent_folders_on_home',
    );
    expect(await prefs.getShowRecentFoldersOnHome(), isTrue);
  });

  test(
    'saved hidden setting reloads from SQLite without deleting history',
    () async {
      await prefs.addRecentPath(r'C:\Private');
      expect(await prefs.setShowRecentFoldersOnHome(false), isTrue);
      expect(prefs.showRecentFoldersOnHome.value, isFalse);
      expect(
        await DatabaseManager.getInstance().getBoolPreference(
          'show_recent_folders_on_home',
        ),
        isFalse,
      );
      // Discard the in-memory value to check the persisted preference is read.
      prefs.showRecentFoldersOnHome.value = true;
      expect(await prefs.getShowRecentFoldersOnHome(), isFalse);
      expect(prefs.showRecentFoldersOnHome.value, isFalse);
      expect(
        await prefs.getRecentPaths(validateDirectories: false),
        contains(r'C:\Private'),
      );
      expect(await prefs.setShowRecentFoldersOnHome(true), isTrue);
      expect(prefs.showRecentFoldersOnHome.value, isTrue);
    },
  );
}
