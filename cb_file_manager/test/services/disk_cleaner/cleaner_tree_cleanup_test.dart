import 'dart:async';

import 'package:cb_file_manager/services/disk_cleaner/cleaner_tree_cleanup.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'prunes descendants, preserves scan-only bytes and warms metadata',
    () async {
      final removed = DiskTreeNode(
        name: 'gone.tmp',
        fullPath: r'C:\Cache\gone.tmp',
        isFile: true,
        sizeBytes: 100,
        fileCount: 1,
        junkCategoryId: 'windows_temp',
        isSelectedForDeletion: true,
      );
      final kept = DiskTreeNode(
        name: 'kept.tmp',
        fullPath: r'C:\Cache\kept.tmp',
        isFile: true,
        sizeBytes: 50,
        fileCount: 1,
        junkCategoryId: 'windows_temp',
        isSelectedForDeletion: true,
      );
      final cache = DiskTreeNode(
        name: 'Cache',
        fullPath: r'C:\Cache',
        sizeBytes: 150,
        fileCount: 2,
        children: [removed, kept],
      );
      final root = DiskTreeNode(
        name: 'C:',
        fullPath: r'C:\',
        // 70 bytes and 4 files are measured but absent from displayed rows.
        sizeBytes: 220,
        fileCount: 6,
        children: [cache],
      );
      expect(root.junkBytes, 150);
      expect(root.hasSelectionInSubtree, isTrue);
      final totals = await pruneCleanedDiskTree(root, {
        removed.fullPath.toLowerCase(),
      });
      expect(root.sizeBytes, 120);
      expect(root.fileCount, 5);
      expect(cache.sizeBytes, 50);
      expect(cache.fileCount, 1);
      expect(cache.children, [same(kept)]);
      expect(totals, (junkBytes: 50, cleanableCount: 1));
      expect(root.junkBytes, 50);
      expect(root.hasJunkChildren, isTrue);
      expect(root.hasSelectionInSubtree, isFalse);
      expect(kept.isSelectedForDeletion, isFalse);
    },
  );

  test(
    'whole-directory removal does not double-count selected descendants',
    () async {
      final folder = DiskTreeNode(
        name: 'Cache',
        fullPath: r'C:\Cache',
        sizeBytes: 100,
        fileCount: 1,
        junkCategoryId: 'windows_temp',
        children: [
          DiskTreeNode(
            name: 'gone',
            fullPath: r'C:\Cache\gone',
            isFile: true,
            sizeBytes: 100,
            fileCount: 1,
          ),
        ],
      );
      final root = DiskTreeNode(
        name: 'C:',
        fullPath: r'C:\',
        sizeBytes: 100,
        fileCount: 1,
        children: [folder],
      );
      final totals = await pruneCleanedDiskTree(root, {
        folder.fullPath,
        folder.children.single.fullPath,
      });
      expect(root.children, isEmpty);
      expect(root.sizeBytes, 0);
      expect(root.fileCount, 0);
      expect(root.hasJunkChildren, isFalse);
      expect(totals, (junkBytes: 0, cleanableCount: 0));
    },
  );

  test('tree updates let the event loop run between work slices', () async {
    final root = DiskTreeNode(
      name: 'C:',
      fullPath: r'C:\',
      sizeBytes: 100,
      fileCount: 100,
      children: List.generate(
        100,
        (i) => DiskTreeNode(
          name: '$i',
          fullPath: 'C:\\$i',
          isFile: true,
          sizeBytes: 1,
          fileCount: 1,
        ),
      ),
    );
    var ticks = 0;
    final heartbeat = Timer.periodic(Duration.zero, (_) => ticks++);
    try {
      await pruneCleanedDiskTree(root, {r'C:\0'}, workSlice: Duration.zero);
    } finally {
      heartbeat.cancel();
    }
    expect(ticks, greaterThan(1));
    expect(root.sizeBytes, 99);
    expect(root.fileCount, 99);
  });
}
