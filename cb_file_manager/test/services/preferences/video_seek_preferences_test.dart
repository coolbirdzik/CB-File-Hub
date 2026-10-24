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
    root = await Directory.systemTemp.createTemp('video-seek-prefs-');
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

  setUp(() async {
    await DatabaseManager.getInstance().deletePreference(
      'video_keyboard_seek_seconds',
    );
    await prefs.setVideoSeekSpeed(2);
  });

  test('defaults to one second independently of held-key speed', () async {
    expect(await prefs.getVideoKeyboardSeekSeconds(), 1);
  });

  test('persists the keyboard step without changing held-key speed', () async {
    expect(await prefs.setVideoKeyboardSeekSeconds(7), isTrue);
    expect(await prefs.getVideoKeyboardSeekSeconds(), 7);
    expect(
      await DatabaseManager.getInstance().getIntPreference(
        'video_keyboard_seek_seconds',
      ),
      7,
    );
    expect(await prefs.getVideoSeekSpeed(), 2);
  });

  test('held-seek acceleration is off until enabled', () async {
    await DatabaseManager.getInstance().deletePreference(
      'video_seek_acceleration',
    );
    expect(await prefs.getVideoSeekAcceleration(), isFalse);
    expect(await prefs.setVideoSeekAcceleration(true), isTrue);
    expect(await prefs.getVideoSeekAcceleration(), isTrue);
    await prefs.setVideoSeekAcceleration(false);
    expect(await prefs.getVideoSeekAcceleration(), isFalse);
  });

  test('keeps saved and legacy values within the selectable range', () async {
    await prefs.setVideoKeyboardSeekSeconds(0);
    expect(await prefs.getVideoKeyboardSeekSeconds(), 1);
    await prefs.setVideoKeyboardSeekSeconds(100);
    expect(await prefs.getVideoKeyboardSeekSeconds(), 30);
    await DatabaseManager.getInstance().saveIntPreference(
      'video_keyboard_seek_seconds',
      -5,
    );
    expect(await prefs.getVideoKeyboardSeekSeconds(), 1);
  });
}
