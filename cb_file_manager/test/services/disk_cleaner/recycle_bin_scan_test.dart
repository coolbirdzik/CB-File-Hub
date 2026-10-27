import 'dart:io';

import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records whether the slow Shell enumeration was asked for.
class _ShellTrash implements TrashManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  final List<SystemTrashItem> items;
  int calls = 0;

  _ShellTrash(this.items);

  @override
  Future<List<SystemTrashItem>> getWindowsRecycleBinItems({
    int? offset,
    int? limit,
  }) async {
    calls++;
    return items;
  }
}

SystemTrashItem _entry(String id, int size) => SystemTrashItem(
  name: '$id.txt',
  recycleBinPath: 'C:\\\$Recycle.Bin\\S-1\\\$R$id.txt',
  originalPath: 'C:\\Users\\me\\$id.txt',
  size: size,
  trashedDate: DateTime(2026, 10, 1),
  isSystemItem: true,
);

void main() {
  final skip = Platform.isWindows ? null : 'The Recycle Bin is Windows-only';

  test('reads the bin directly and leaves Shell alone', () async {
    final shell = _ShellTrash([_entry('shell', 1)]);
    final service = DiskCleanerService.forTesting(
      fullDiskScanSpawner: spawnFullDiskScan,
      trashManager: shell,
      recycleBinReader: () =>
          Stream.fromIterable([_entry('a', 10), _entry('b', 20)]),
    );
    final items = await service.scanRecycleBin();
    expect(shell.calls, 0);
    expect(items.map((i) => i.path), [
      'C:\\\$Recycle.Bin\\S-1\\\$Ra.txt',
      'C:\\\$Recycle.Bin\\S-1\\\$Rb.txt',
    ]);
    expect(items.every((i) => i.isRecycleBinItem), isTrue);
    expect(items.first.categoryId, 'recycle_bin');
    expect(items.first.originalPath, 'C:\\Users\\me\\a.txt');
    expect(items.last.sizeBytes, 20);
  }, skip: skip);

  test('falls back to Shell when the direct read finds nothing', () async {
    for (final reader in <Stream<SystemTrashItem> Function()>[
      () => const Stream.empty(),
      () => Stream.error(const FileSystemException('denied')),
    ]) {
      final shell = _ShellTrash([_entry('shell', 5)]);
      final service = DiskCleanerService.forTesting(
        fullDiskScanSpawner: spawnFullDiskScan,
        trashManager: shell,
        recycleBinReader: reader,
      );
      final items = await service.scanRecycleBin();
      expect(shell.calls, 1);
      expect(items.single.sizeBytes, 5);
    }
  }, skip: skip);
}
