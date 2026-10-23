import 'package:cb_file_manager/services/torrent/torrent_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

class _CachedWindowsStore extends SharedPreferencesWindows {
  final Map<String, Object> values;
  _CachedWindowsStore(this.values);

  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => SharedPreferences.setMockInitialValues({}));

  test(
    'refreshes both Windows platform and legacy preference caches',
    () async {
      final oldStore = _CachedWindowsStore({
        'flutter.torrent.startImmediately': true,
      });
      SharedPreferencesStorePlatform.instance = oldStore;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getBool('torrent.startImmediately'), isTrue);
      final freshStore = _CachedWindowsStore({
        'flutter.torrent.startImmediately': false,
      });
      await reloadTorrentPreferences(
        prefs,
        createWindowsStore: () => freshStore,
      );
      expect(prefs.getBool('torrent.startImmediately'), isFalse);
      expect(SharedPreferencesStorePlatform.instance, same(freshStore));
      expect(oldStore.values['flutter.torrent.startImmediately'], isTrue);
    },
  );

  test('keeps other platform stores and reloads their saved values', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesStorePlatform.instance;
    await store.setValue('Bool', 'flutter.torrent.startImmediately', false);
    await reloadTorrentPreferences(
      prefs,
      createWindowsStore: () => throw StateError('Unexpected Windows store'),
    );
    expect(SharedPreferencesStorePlatform.instance, same(store));
    expect(prefs.getBool('torrent.startImmediately'), isFalse);
  });
}
