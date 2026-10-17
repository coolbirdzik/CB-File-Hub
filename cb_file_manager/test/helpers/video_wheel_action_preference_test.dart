import 'dart:io';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  group('UserPreferences video wheel action', () {
    setUpAll(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (methodCall) async {
            switch (methodCall.method) {
              case 'getApplicationDocumentsDirectory':
              case 'getApplicationSupportDirectory':
              case 'getTemporaryDirectory':
                return Directory.systemTemp.path;
              default:
                return null;
            }
          });

      SharedPreferences.setMockInitialValues(<String, Object>{});
      await UserPreferences.instance.init();
    });

    tearDownAll(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
    });

    test('defaults to volume and round-trips each action', () async {
      final prefs = UserPreferences.instance;
      expect(await prefs.getVideoWheelAction(), VideoWheelAction.volume);

      await prefs.setVideoWheelAction(VideoWheelAction.seek);
      expect(await prefs.getVideoWheelAction(), VideoWheelAction.seek);

      await prefs.setVideoWheelAction(VideoWheelAction.volume);
      expect(await prefs.getVideoWheelAction(), VideoWheelAction.volume);
    });
  });
}
