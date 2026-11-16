import 'dart:io';

import 'package:cb_file_manager/helpers/core/filesystem_sorter.dart';
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_native/cb_native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win;

/// Start with an open folder without starting thumbnail prefetch or a watcher.
/// Those readers can change last-access times between the two parity scans.
class _OpenFolderNavigation extends FileNavigationBloc {
  _OpenFolderNavigation(Directory folder, NativeListing listing) {
    emit(
      state.copyWith(
        currentPath: folder,
        isLoading: false,
        sortOption: SortOption.nameAsc,
        folders: [for (final entry in listing.folders) Directory(entry.path)],
        files: [for (final entry in listing.files) File(entry.path)],
      ),
    );
  }
}

/// The folder browser lists through Rust when package:cb_native is built and
/// through the Dart isolate otherwise; both must show the same order.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = CbNative.isAvailable ? null : 'Rust library not built';
  late Directory root;
  final fixtureLocks = <win.HANDLE>[];

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
      if (Platform.isWindows) {
        // Create before writing, so background indexers cannot open a content
        // reader and overwrite the deliberately distinct last-access times.
        // Attribute queries and writes remain shared, including Rust/Dart stat.
        final nativePath = file.path.toNativeUtf16();
        try {
          final opened = win.CreateFile(
            win.PCWSTR(nativePath),
            win.GENERIC_READ,
            win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE,
            null,
            win.CREATE_NEW,
            win.FILE_ATTRIBUTE_NORMAL,
            null,
          );
          expect(
            opened.value.isValid,
            isTrue,
            reason: '${file.path}: ${opened.error}',
          );
          fixtureLocks.add(opened.value);
        } finally {
          calloc.free(nativePath);
        }
      }
      await file.writeAsBytes(
        List<int>.filled((i * 7 + 3) % 23 + i, 0),
        mode: FileMode.writeOnly,
      );
      await file.setLastModified(base.add(Duration(hours: (i * 5) % 11 + i)));
      await file.setLastAccessed(base.add(Duration(hours: (i * 3) % 7 + i)));
    }
    if (Platform.isWindows) {
      // Distinct attribute letters for the attributes sorts.
      await Process.run('attrib', ['+R', p.join(root.path, 'b.txt')]);
      await Process.run('attrib', ['+H', p.join(root.path, 'Zed')]);
      await Process.run('attrib', ['+R', '+H', p.join(root.path, '9.png')]);
    }
    // Skipped by both listings.
    await File(p.join(root.path, 'x.tags')).writeAsString('');
    await File(p.join(root.path, '.cbfile_config.json')).writeAsString('');
    await Directory(p.join(root.path, 'Bravo', 'pics')).create();
    await File(p.join(root.path, 'Bravo', 'pics', 'a.JPG')).writeAsString('');
    await File(p.join(root.path, 'Bravo', '.hidden.png')).writeAsString('');
  });

  tearDownAll(() async {
    for (final handle in fixtureLocks) {
      win.CloseHandle(handle);
    }
    if (Platform.isWindows) {
      await Process.run('attrib', ['-R', '-H', p.join(root.path, '*')]);
    }
    await root.delete(recursive: true);
  });

  // Stat-based sorts run natively; content/Shell sorts use the async property reader.
  for (final sort in SortOption.values.where((s) => s.metadataColumn == null)) {
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
      if (const {
        SortOption.nameAsc,
        SortOption.nameDesc,
        SortOption.pathAsc,
        SortOption.pathDesc,
      }.contains(sort)) {
        expect(native.folders.map((e) => e.path), dart.folders);
      } else {
        expect(native.folders.map((e) => e.path).toSet(), dart.folders.toSet());
      }
    }, skip: skip);
  }

  test('changing the sort of an open folder re-lists it natively', () async {
    final listing = await NativeFs.listDirectory(
      root.path,
      sort: NativeListSort.nameAsc,
      skipSuffixes: const ['.tags'],
      skipNames: const ['.cbfile_config.json'],
    );
    final bloc = _OpenFolderNavigation(root, listing!);
    addTearDown(bloc.close);

    // A real re-list must observe changes after the folder was opened, rather
    // than merely sorting its previous in-memory sizes or dates.
    final changed = File(p.join(root.path, '_x.pdf'));
    await changed.writeAsBytes(
      List<int>.filled(4096, 0),
      mode: FileMode.writeOnly,
    );
    await changed.setLastAccessed(DateTime(2023, 1, 1));
    if (Platform.isWindows) {
      expect(changed.readAsBytesSync, throwsA(isA<FileSystemException>()));
    }

    for (final sort in [
      SortOption.sizeDesc,
      SortOption.dateAccessedAsc,
      SortOption.dateAccessedDesc,
      SortOption.typeDesc,
    ]) {
      final states = <FileNavigationState>[];
      final sub = bloc.stream.listen(states.add);
      final next = bloc.stream.firstWhere(
        (s) => s.sortOption == sort && !s.isLoading,
      );
      bloc.add(FileNavigationSetSortOption(sort, persist: false));
      final done = await next.timeout(const Duration(seconds: 10));
      await sub.cancel();
      final dart = await dartScanDirectoryForTesting(root.path, sort);
      if (sort == SortOption.sizeDesc || sort == SortOption.dateAccessedAsc) {
        expect(done.files.first.path, changed.path, reason: sort.name);
      }
      expect(done.files.map((f) => f.path), dart.files, reason: sort.name);
      expect(done.error, isNull);
      expect(done.folders.map((f) => f.path).toSet(), dart.folders.toSet());
      expect(
        states.any((s) => s.isLoading),
        isFalse,
        reason: 'a native re-sort swaps the order without a loading state',
      );
    }
  }, skip: skip);

  test('FileSystemSorter sorts loose paths natively like with stats', () async {
    final files = [
      for (final entity in root.listSync())
        if (entity is File && !entity.path.endsWith('.json')) entity,
    ]..shuffle();
    final stats = {for (final f in files) f.path: f.statSync()};
    for (final sort in [
      SortOption.sizeDesc,
      SortOption.dateAsc,
      SortOption.nameAsc,
    ]) {
      final native = await FileSystemSorter.sortFiles(files, sort);
      final dart = await FileSystemSorter.sortFiles(
        files,
        sort,
        fileStatsCache: stats,
      );
      expect(native.map((f) => f.path), dart.map((f) => f.path));
    }
  }, skip: skip);

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
