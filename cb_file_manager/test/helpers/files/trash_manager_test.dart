import 'dart:io';

import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrashManager permanent deletion', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory =
          await Directory.systemTemp.createTemp('cb_permanent_delete_test_');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('deletes files and directories with bounded concurrent workers',
        () async {
      final paths = <String>[];
      for (var index = 0; index < 12; index++) {
        final file = File(
          '${tempDirectory.path}${Platform.pathSeparator}file_$index.tmp',
        );
        await file.writeAsString('temporary data');
        paths.add(file.path);
      }

      final nestedDirectory = Directory(
          '${tempDirectory.path}${Platform.pathSeparator}nested_directory');
      await nestedDirectory.create();
      await File('${nestedDirectory.path}${Platform.pathSeparator}nested.log')
          .writeAsString('nested data');
      paths.add(nestedDirectory.path);

      final progress = <int>[];
      final succeeded = await TrashManager().deleteMultiplePermanently(
        paths,
        chunkSize: 3,
        onChunkDone: (done, total) {
          expect(total, paths.length);
          progress.add(done);
        },
      );

      expect(succeeded, paths.toSet());
      expect(progress, List<int>.generate(paths.length, (index) => index + 1));
      for (final path in paths) {
        expect(
            await FileSystemEntity.type(path), FileSystemEntityType.notFound);
      }
    });

    test('treats an already missing path as successfully deleted', () async {
      final missingPath =
          '${tempDirectory.path}${Platform.pathSeparator}already_missing.tmp';

      final succeeded =
          await TrashManager().deleteMultiplePermanently([missingPath]);

      expect(succeeded, {missingPath});
    });
  });
}
