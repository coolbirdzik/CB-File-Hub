import 'dart:async';
import 'dart:io';

import 'package:cb_native/cb_native.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'cleaner worker reports monotonic progress for native permanent deletion',
    () async {
      final root = await Directory.systemTemp.createTemp('cb_clean_worker_');
      final items = <JunkItem>[];
      try {
        for (var i = 0; i < 64; i++) {
          final file = await File(
            p.join(root.path, '$i.tmp'),
          ).writeAsString('delete');
          items.add(
            JunkItem(
              path: file.path,
              sizeBytes: 6,
              categoryId: 'selected_item',
              isUserSelected: true,
            ),
          );
        }
        final progress = <int>[];
        final report = await DiskCleanerService.instance.cleanJunk(
          items: items,
          permanent: true,
          onProgress: (done, total, _) {
            if (total > 0) progress.add(done);
          },
        );
        expect(
          report.succeeded,
          unorderedEquals(items.map((item) => item.path)),
        );
        expect(report.failed, isEmpty);
        expect(report.freedBytes, 64 * 6);
        expect(progress, isNotEmpty);
        expect(progress.last, 64);
        expect(progress, orderedEquals([...progress]..sort()));
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: CbNative.isAvailable ? null : 'Rust library not built',
  );

  test(
    'native deletion streams per-target outcomes and keeps unrelated files',
    () async {
      final root = await Directory.systemTemp.createTemp('cb_native_delete_');
      try {
        final selected = await Directory(
          p.join(root.path, 'selected'),
        ).create();
        for (var i = 0; i < 100; i++) {
          await File(p.join(selected.path, '$i.tmp')).writeAsString('delete');
        }
        final kept = await File(
          p.join(root.path, 'keep.txt'),
        ).writeAsString('keep');
        final paths = [selected.path, p.join(root.path, 'missing'), ''];
        final streamed = <NativeDeleteResult>[];
        var heartbeat = false;
        final timer = Timer(Duration.zero, () => heartbeat = true);
        final results = await NativeDelete.permanently(
          paths,
          concurrency: 2,
          onResult: streamed.add,
        );
        timer.cancel();
        expect(results, isNotNull, reason: 'New native job must actually run');
        expect(heartbeat, isTrue);
        expect(streamed, hasLength(paths.length));
        final byPath = {for (final result in results!) result.path: result};
        expect(byPath[selected.path]!.succeeded, isTrue);
        expect(byPath[paths[1]]!.succeeded, isTrue);
        expect(byPath['']!.succeeded, isFalse);
        expect(byPath['']!.error, isNotEmpty);
        expect(await selected.exists(), isFalse);
        expect(await kept.readAsString(), 'keep');
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: CbNative.isAvailable ? null : 'Rust library not built',
  );
}
