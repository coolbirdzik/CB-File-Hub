import 'dart:io';

import 'package:cb_file_manager/helpers/files/lazy_path_size_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory testRoot;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('lazy-path-size-');
  });

  tearDown(() async {
    if (await testRoot.exists()) {
      await testRoot.delete(recursive: true);
    }
  });

  test('calculates files and nested folders without double counting', () async {
    final selectedFile = File(path.join(testRoot.path, 'selected.bin'));
    await selectedFile.writeAsBytes(List<int>.filled(7, 1));

    final folder = Directory(path.join(testRoot.path, 'folder'));
    final nested = Directory(path.join(folder.path, 'nested'));
    await nested.create(recursive: true);
    await File(
      path.join(folder.path, 'one.bin'),
    ).writeAsBytes(List<int>.filled(11, 1));
    await File(
      path.join(nested.path, 'two.bin'),
    ).writeAsBytes(List<int>.filled(13, 1));

    final size = await LazyPathSizeCalculator.calculate(
      filePaths: <String>[selectedFile.path],
      folderPaths: <String>[folder.path],
      initialDelay: Duration.zero,
    );

    expect(size, 31);
  });

  test('skips missing paths and stops when cancelled', () async {
    final file = File(path.join(testRoot.path, 'file.bin'));
    await file.writeAsBytes(List<int>.filled(5, 1));

    expect(
      await LazyPathSizeCalculator.calculate(
        filePaths: <String>[path.join(testRoot.path, 'missing'), file.path],
        initialDelay: Duration.zero,
      ),
      5,
    );
    expect(
      await LazyPathSizeCalculator.calculateDirectory(
        testRoot.path,
        isCancelled: () => true,
        initialDelay: Duration.zero,
      ),
      0,
    );
  });
}
