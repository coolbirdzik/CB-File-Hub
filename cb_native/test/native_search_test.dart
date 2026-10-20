import 'dart:io';

import 'package:cb_native/cb_native.dart';
import 'package:test/test.dart';

void main() {
  final available = CbNative.isAvailable;
  final skip = available ? null : 'Rust library not built on this machine';

  group('NativeSearch', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('cb_native_test_');
      final nested = Directory('${root.path}/Bổ Não/deep');
      await nested.create(recursive: true);
      await File('${nested.path}/bo_nao.txt').writeAsString('');
      await File('${root.path}/other.txt').writeAsString('');
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('matches folded names in nested folders', () async {
      final search = NativeSearch.start(root: root.path, words: ['bo', 'nao'])!;
      final hits = await NativeSearch.collect(
        search,
        shouldContinue: () => true,
      );
      final byName = {
        for (final hit in hits!)
          hit.path.split(RegExp(r'[\\/]')).last: hit.kind,
      };
      expect(byName, {
        'Bổ Não': NativeEntryKind.directory,
        'bo_nao.txt': NativeEntryKind.file,
      });
    }, skip: skip);

    test('rejects a pattern Rust regex cannot compile', () {
      expect(NativeSearch.start(root: root.path, regex: r'(?<=a)b'), isNull);
    }, skip: skip);
  });

  test('searchKey folds Vietnamese', () {
    expect(CbNative.searchKey('Đường_đi (2).MP4'), 'duong di 2 mp4');
  }, skip: skip);
}
