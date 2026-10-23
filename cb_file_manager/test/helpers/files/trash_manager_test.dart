import 'dart:io';

import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final permanent in [false, true]) {
    test(
      'admin retry checks targets disappeared (permanent: $permanent)',
      () async {
        const channel = MethodChannel('cb_file_manager/file_operations');
        final directory = await Directory.systemTemp.createTemp(
          'cb_admin_retry_',
        );
        final file = await File(
          '${directory.path}/target.tmp',
        ).writeAsString('test');
        addTearDown(() async {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
          await directory.delete(recursive: true);
        });
        var removeTarget = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              final args = call.arguments as Map;
              expect(args['sources'], [file.path]);
              expect(args['permanent'], permanent);
              expect(args['requireElevation'], isTrue);
              if (removeTarget) await file.delete();
              return true;
            });
        expect(
          await TrashManager().retryDeleteAsAdministrator([
            file.path,
            file.path,
          ], permanent: permanent),
          isEmpty,
        );
        expect(await file.exists(), isTrue);
        removeTarget = true;
        expect(
          await TrashManager().retryDeleteAsAdministrator([
            file.path,
          ], permanent: permanent),
          {file.path},
        );
      },
      skip: !Platform.isWindows,
    );
  }

  for (final useNative in [true, false]) {
    group('TrashManager permanent deletion (native: $useNative)', () {
      late Directory tempDirectory;

      setUp(() async {
        tempDirectory = await Directory.systemTemp.createTemp(
          'cb_permanent_delete_test_',
        );
      });

      tearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      test(
        'deletes files and directories with bounded concurrent workers',
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
            '${tempDirectory.path}${Platform.pathSeparator}nested_directory',
          );
          await nestedDirectory.create();
          await File(
            '${nestedDirectory.path}${Platform.pathSeparator}nested.log',
          ).writeAsString('nested data');
          paths.add(nestedDirectory.path);

          final progress = <int>[];
          final succeeded = await TrashManager().deleteMultiplePermanently(
            paths,
            useNative: useNative,
            chunkSize: 3,
            onChunkDone: (done, total) {
              expect(total, paths.length);
              progress.add(done);
            },
          );

          expect(succeeded, paths.toSet());
          expect(
            progress,
            List<int>.generate(paths.length, (index) => index + 1),
          );
          for (final path in paths) {
            expect(
              await FileSystemEntity.type(path),
              FileSystemEntityType.notFound,
            );
          }
        },
      );

      test('treats an already missing path as successfully deleted', () async {
        final missingPath =
            '${tempDirectory.path}${Platform.pathSeparator}already_missing.tmp';

        final succeeded = await TrashManager().deleteMultiplePermanently([
          missingPath,
        ], useNative: useNative);

        expect(succeeded, {missingPath});
      });
    });
  }
}
