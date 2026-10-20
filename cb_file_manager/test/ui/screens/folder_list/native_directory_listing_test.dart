import 'dart:io';

import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The folder browser lists through Rust when package:cb_native is built and
/// through the Dart isolate otherwise; both must show the same order.
void main() {
  final skip = CbNative.isAvailable ? null : 'Rust library not built';
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_native_listing_');
    for (final name in ['Bravo', 'alpha', 'Ünder', '_tmp']) {
      await Directory(p.join(root.path, name)).create();
    }
    // Distinct sizes, dates and extensions so every sort is a total order.
    final files = <String>[
      'b.txt',
      'A.MP4',
      'ä.doc',
      'Zed',
      '_x.pdf',
      '10.jpeg',
      '9.png',
      'Ωmega.gif',
    ];
    final base = DateTime(2024, 1, 1);
    for (final (i, name) in files.indexed) {
      final file = File(p.join(root.path, name));
      await file.writeAsBytes(List<int>.filled((i * 7 + 3) % 23 + i, 0));
      await file.setLastModified(base.add(Duration(hours: (i * 5) % 11 + i)));
    }
    // Skipped by both listings.
    await File(p.join(root.path, 'x.tags')).writeAsString('');
    await File(p.join(root.path, '.cbfile_config.json')).writeAsString('');
    await Directory(p.join(root.path, 'Bravo', 'pics')).create();
    await File(p.join(root.path, 'Bravo', 'pics', 'a.JPG')).writeAsString('');
    await File(p.join(root.path, 'Bravo', '.hidden.png')).writeAsString('');
  });

  tearDownAll(() => root.delete(recursive: true));

  for (final sort in [
    SortOption.nameAsc,
    SortOption.nameDesc,
    SortOption.dateAsc,
    SortOption.dateDesc,
    SortOption.sizeAsc,
    SortOption.sizeDesc,
    SortOption.extensionAsc,
    SortOption.extensionDesc,
  ]) {
    test('${sort.name} matches the Dart listing', () async {
      final dart = await dartScanDirectoryForTesting(root.path, sort);
      final native = await NativeFs.listDirectory(
        root.path,
        sort: NativeListSort.values.byName(sort.name),
        skipSuffixes: const ['.tags'],
        skipNames: const ['.cbfile_config.json'],
      );
      expect(native!.files.map((e) => e.path), dart.files);
      // Folder dates, sizes and extensions tie, so only names order them.
      if (sort == SortOption.nameAsc || sort == SortOption.nameDesc) {
        expect(native.folders.map((e) => e.path), dart.folders);
      } else {
        expect(native.folders.map((e) => e.path).toSet(), dart.folders.toSet());
      }
    }, skip: skip);
  }

  test('getAllImages finds the same files natively', () async {
    final images = await getAllImages(root.path);
    expect(images.map((f) => p.basename(f.path)).toSet(), {
      '10.jpeg',
      '9.png',
      'Ωmega.gif',
      'a.JPG',
    });
  });
}
