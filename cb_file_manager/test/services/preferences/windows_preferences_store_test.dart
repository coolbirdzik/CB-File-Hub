import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/preferences/windows_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late File file;

  WindowsPreferencesStore store() =>
      WindowsPreferencesStore(file: () async => file);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cb_prefs_');
    file = File(p.join(root.path, 'shared_preferences.json'));
  });

  tearDown(() => root.delete(recursive: true));

  test('a stale process keeps values another process saved later', () async {
    await file.writeAsString(jsonEncode({'flutter.app_theme': 'dark'}));
    // Both "processes" have loaded the file before either writes.
    final main = store();
    final optionsWindow = store();
    expect(await main.getAll(), {'flutter.app_theme': 'dark'});
    expect(await optionsWindow.getAll(), {'flutter.app_theme': 'dark'});

    expect(await main.setValue('Int', 'flutter.torrent.pageSize', 500), true);
    expect(
      await optionsWindow.setValue(
        'String',
        'flutter.torrent.lastDownloadDirectory',
        r'D:\Downloads',
      ),
      true,
    );

    expect(jsonDecode(await file.readAsString()), {
      'flutter.app_theme': 'dark',
      'flutter.torrent.pageSize': 500,
      'flutter.torrent.lastDownloadDirectory': r'D:\Downloads',
    });
    expect(
      (await main.getAll())['flutter.torrent.lastDownloadDirectory'],
      r'D:\Downloads',
    );
  });

  test('remove and clear only drop their own keys', () async {
    final a = store();
    final b = store();
    await a.setValue('Bool', 'flutter.keep', true);
    await a.setValue('Bool', 'flutter.drop', true);
    await b.setValue('String', 'other.value', 'x');
    expect(await a.remove('flutter.drop'), isTrue);
    expect(await b.getAllWithPrefix(''), {
      'flutter.keep': true,
      'other.value': 'x',
    });
    expect(await b.clear(), isTrue);
    expect(await a.getAllWithPrefix(''), {'other.value': 'x'});
  });

  test('missing file reads as empty and is created on first write', () async {
    final s = store();
    expect(await s.getAll(), isEmpty);
    expect(await s.setValue('Int', 'flutter.n', 1), isTrue);
    expect(jsonDecode(await file.readAsString()), {'flutter.n': 1});
  });
}
