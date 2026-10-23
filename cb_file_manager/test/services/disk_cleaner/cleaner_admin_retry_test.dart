import 'dart:io';

import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

class _Trash implements TrashManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  int errorCode = 5;
  bool approveElevation = true;
  final attempts = <({List<String> paths, bool permanent, bool elevated})>[];

  Future<Set<String>> _delete(
    List<String> paths,
    bool permanent,
    void Function(String, Object)? onError,
  ) async {
    attempts.add((
      paths: List.of(paths),
      permanent: permanent,
      elevated: false,
    ));
    for (final path in paths.where((path) => path.contains('denied'))) {
      onError?.call(
        path,
        FileSystemException(
          'Delete failed',
          path,
          OSError('Denied', errorCode),
        ),
      );
    }
    return paths.where((path) => !path.contains('denied')).toSet();
  }

  @override
  Future<Set<String>> deleteMultiplePermanently(
    List<String> filePaths, {
    int chunkSize = 200,
    void Function(String, int, int)? onChunkStart,
    void Function(int, int)? onChunkDone,
    void Function(String, Object)? onError,
    Duration? timeoutOverride,
    bool useNative = true,
  }) => _delete(filePaths, true, onError);

  @override
  Future<Set<String>> moveMultipleToTrashBatched(
    List<String> filePaths, {
    int chunkSize = 200,
    void Function(String, int, int)? onChunkStart,
    void Function(int, int)? onChunkDone,
    Duration? timeoutOverride,
    void Function(String, Object)? onError,
  }) => _delete(filePaths, false, onError);

  @override
  Future<Set<String>> retryDeleteAsAdministrator(
    List<String> failedPaths, {
    required bool permanent,
  }) async {
    attempts.add((
      paths: List.of(failedPaths),
      permanent: permanent,
      elevated: true,
    ));
    return approveElevation ? failedPaths.toSet() : <String>{};
  }
}

JunkItem _item(String name) => JunkItem(
  path: 'C:\\cb_cleaner_admin_test\\$name.tmp',
  sizeBytes: 10,
  categoryId: 'manual',
  isUserSelected: true,
);

void main() {
  for (final permanent in [false, true]) {
    test(
      'asks before elevating only the failed target (permanent: $permanent)',
      () async {
        final trash = _Trash();
        final service = DiskCleanerService.forTesting(
          fullDiskScanSpawner: spawnFullDiskScan,
          trashManager: trash,
        );
        final denied = _item('denied');
        final healthy = _item('healthy');
        final result = await service.cleanJunk(
          items: [healthy, denied],
          permanent: permanent,
          onDeleteFailure: (details) async {
            expect(details.item.path, denied.path);
            expect(details.canRetryAsAdministrator, isTrue);
            expect(details.isInUse, isFalse);
            expect(
              trash.attempts.where((attempt) => attempt.elevated),
              isEmpty,
            );
            return CleanFailureAction.retryAsAdministrator;
          },
        );
        expect(result.succeeded, [healthy.path, denied.path]);
        expect(result.freedBytes, 20);
        expect(result.failed, isEmpty);
        expect(trash.attempts.last.paths, [denied.path]);
        expect(trash.attempts.last.permanent, permanent);
        expect(trash.attempts.last.elevated, isTrue);
      },
      skip: !Platform.isWindows,
    );
  }

  for (final action in [CleanFailureAction.skip, CleanFailureAction.skipAll]) {
    test('$action never requests elevation', () async {
      final trash = _Trash();
      final service = DiskCleanerService.forTesting(
        fullDiskScanSpawner: spawnFullDiskScan,
        trashManager: trash,
      );
      final denied = _item('denied');
      final result = await service.cleanJunk(
        items: [denied],
        permanent: true,
        onDeleteFailure: (_) async => action,
      );
      expect(result.skippedByUser, [denied.path]);
      expect(trash.attempts.where((attempt) => attempt.elevated), isEmpty);
    });
  }

  test(
    'cancelled UAC leaves the target and does not repeatedly offer elevation',
    () async {
      final trash = _Trash()..approveElevation = false;
      final service = DiskCleanerService.forTesting(
        fullDiskScanSpawner: spawnFullDiskScan,
        trashManager: trash,
      );
      var prompts = 0;
      final denied = _item('denied');
      final result = await service.cleanJunk(
        items: [denied],
        permanent: true,
        onDeleteFailure: (details) async {
          prompts++;
          expect(details.canRetryAsAdministrator, prompts == 1);
          return prompts == 1
              ? CleanFailureAction.retryAsAdministrator
              : CleanFailureAction.skip;
        },
      );
      expect(prompts, 2);
      expect(result.succeeded, isEmpty);
      expect(result.skippedByUser, [denied.path]);
      expect(trash.attempts.where((attempt) => attempt.elevated), hasLength(1));
    },
    skip: !Platform.isWindows,
  );

  test('other delete errors cannot trigger an elevated retry', () async {
    final trash = _Trash()..errorCode = 32;
    final service = DiskCleanerService.forTesting(
      fullDiskScanSpawner: spawnFullDiskScan,
      trashManager: trash,
    );
    final denied = _item('denied');
    final result = await service.cleanJunk(
      items: [denied],
      permanent: true,
      onDeleteFailure: (details) async {
        expect(details.canRetryAsAdministrator, isFalse);
        return CleanFailureAction.retryAsAdministrator;
      },
    );
    expect(result.failed.keys, [denied.path]);
    expect(trash.attempts.where((attempt) => attempt.elevated), isEmpty);
  });

  test(
    'ordinary retries retain permission errors for the next prompt',
    () async {
      final trash = _Trash();
      final service = DiskCleanerService.forTesting(
        fullDiskScanSpawner: spawnFullDiskScan,
        trashManager: trash,
      );
      var prompts = 0;
      final result = await service.cleanJunk(
        items: [_item('denied')],
        permanent: true,
        onDeleteFailure: (details) async {
          expect(details.canRetryAsAdministrator, isTrue);
          return ++prompts == 1
              ? CleanFailureAction.retry
              : CleanFailureAction.retryAsAdministrator;
        },
      );
      expect(prompts, 2);
      expect(result.successCount, 1);
    },
    skip: !Platform.isWindows,
  );
}
