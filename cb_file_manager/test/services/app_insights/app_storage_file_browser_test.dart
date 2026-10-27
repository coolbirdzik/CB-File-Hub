import 'dart:io';

import 'package:cb_file_manager/services/app_insights/app_storage_file_browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cb-app-files-');
    Directory(p.join(root.path, 'nested')).createSync();
    File(p.join(root.path, 'data.bin')).writeAsBytesSync([1, 2, 3]);
    File(p.join(root.path, '.settings')).writeAsStringSync('setting');
    File(p.join(root.path, 'nested', 'child.txt')).writeAsStringSync('child');
  });

  tearDown(() => root.deleteSync(recursive: true));

  for (final useNative in [false, true]) {
    test(
      'lists direct files with sizes and hidden data (native: $useNative)',
      () async {
        final entries = await AppStorageFileBrowser.listDirectory(
          root.path,
          useNative: useNative,
        );

        expect(entries.map((entry) => entry.name), [
          'nested',
          '.settings',
          'data.bin',
        ]);
        expect(entries.first.isDirectory, isTrue);
        expect(entries.first.sizeBytes, isNull);
        expect(entries[1].sizeBytes, 7);
        expect(entries.last.sizeBytes, 3);
        expect(
          entries.map((entry) => entry.name),
          isNot(contains('child.txt')),
        );
        expect(File(p.join(root.path, 'data.bin')).readAsBytesSync(), [
          1,
          2,
          3,
        ]);
      },
    );

    test('missing folders report an error (native: $useNative)', () async {
      await expectLater(
        AppStorageFileBrowser.listDirectory(
          p.join(root.path, 'missing'),
          useNative: useNative,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  }
}
