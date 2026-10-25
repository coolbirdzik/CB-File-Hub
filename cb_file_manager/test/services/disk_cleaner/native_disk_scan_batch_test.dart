import 'package:cb_native/cb_native.dart';
import 'package:flutter_test/flutter_test.dart';

NativeDirRecord directory(int id, [List<int> children = const []]) =>
    NativeDirRecord(
      id: id,
      status: NativeDirStatus.scanned,
      subdirs: [
        for (final child in children)
          NativeSubdir(
            id: child,
            name: 'directory-$child',
            lastWriteFileTime: 0,
            lastAccessFileTime: 0,
            category: -1,
          ),
      ],
      retainedFiles: const [],
      oldLargeFiles: const [],
      foldedBytes: 0,
      foldedFiles: 0,
      foldedJunkBytes: 0,
      foldedEntries: 0,
      ownBytes: 0,
      ownFiles: 0,
      newestActivityFileTime: 0,
      reparseNames: const [],
    );

void main() {
  test('accepts parallel siblings and nested records across poll batches', () {
    final pending = <int>{0};
    NativeDiskScanBatch([
      directory(0, [1, 2]),
      directory(2, [3]),
    ], finished: false).validate(pending);
    expect(pending, {1, 3});

    const NativeDiskScanBatch([], finished: false).validate(pending);
    NativeDiskScanBatch([
      directory(3),
      directory(1),
    ], finished: true).validate(pending);
    expect(pending, isEmpty);
  });

  test('rejects an orphan after native abandonment discards its parent', () {
    final batch = NativeDiskScanBatch([directory(7)], finished: false);
    expect(
      () => batch.validate(<int>{0}),
      throwsA(isA<NativeDiskScanIncomplete>()),
    );
  });

  test('rejects a finished scan whose buffered root was discarded', () {
    expect(
      () => const NativeDiskScanBatch([], finished: true).validate(<int>{0}),
      throwsA(isA<NativeDiskScanIncomplete>()),
    );
  });

  test('rejects a finished scan with an unreported directory', () {
    final pending = <int>{0};
    NativeDiskScanBatch([
      directory(0, [1, 2]),
      directory(1),
    ], finished: false).validate(pending);
    expect(
      () => const NativeDiskScanBatch([], finished: true).validate(pending),
      throwsA(isA<NativeDiskScanIncomplete>()),
    );
  });

  test('accepts a scanned empty root', () {
    final pending = <int>{0};
    NativeDiskScanBatch([directory(0)], finished: true).validate(pending);
    expect(pending, isEmpty);
  });

  test('rejects duplicate records and duplicate child IDs', () {
    for (final records in [
      [directory(0), directory(0)],
      [
        directory(0, [1, 1]),
      ],
      [
        directory(0, [0]),
      ],
    ]) {
      expect(
        () => NativeDiskScanBatch(records, finished: false).validate(<int>{0}),
        throwsA(isA<NativeDiskScanIncomplete>()),
      );
    }
  });
}
