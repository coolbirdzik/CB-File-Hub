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

  group('08 UserPreferences recent paths', () {
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
      await UserPreferences.instance.clearRecentPaths();
    });

    tearDownAll(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
    });

    setUp(() async {
      await UserPreferences.instance.clearRecentPaths();
    });

    test(
      '08.01 addRecentPath stores most recent first and deduplicates',
      () async {
        await UserPreferences.instance.addRecentPath('/tmp/a');
        await UserPreferences.instance.addRecentPath('/tmp/b');
        await UserPreferences.instance.addRecentPath('/tmp/a');

        final paths = await UserPreferences.instance.getRecentPaths(
          validateDirectories: false,
        );

        expect(paths, equals(<String>['/tmp/a', '/tmp/b']));
      },
    );

    test('08.02 addRecentPath ignores virtual paths', () async {
      final result = await UserPreferences.instance.addRecentPath(
        '#search?tag=cat',
      );
      expect(result, isFalse);

      final paths = await UserPreferences.instance.getRecentPaths(
        validateDirectories: false,
      );
      expect(paths, isEmpty);
    });
  });
}
