import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('UserPreferences recent paths', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await UserPreferences.instance.init();
      await UserPreferences.instance.clearRecentPaths();
    });

    setUp(() async {
      await UserPreferences.instance.clearRecentPaths();
    });

    test('addRecentPath stores most recent first and deduplicates', () async {
      await UserPreferences.instance.addRecentPath('/tmp/a');
      await UserPreferences.instance.addRecentPath('/tmp/b');
      await UserPreferences.instance.addRecentPath('/tmp/a');

      final paths = await UserPreferences.instance
          .getRecentPaths(validateDirectories: false);

      expect(paths, equals(<String>['/tmp/a', '/tmp/b']));
    });

    test('addRecentPath ignores virtual paths', () async {
      final result =
          await UserPreferences.instance.addRecentPath('#search?tag=cat');
      expect(result, isFalse);

      final paths = await UserPreferences.instance
          .getRecentPaths(validateDirectories: false);
      expect(paths, isEmpty);
    });
  });
}
