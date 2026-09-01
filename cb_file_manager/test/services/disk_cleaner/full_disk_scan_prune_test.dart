import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/services/disk_cleaner/usn_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

DiskTreeNode _file(String name, int bytes) => DiskTreeNode(
      name: name,
      fullPath: 'C:\\$name',
      isFile: true,
      sizeBytes: bytes,
      fileCount: 1,
    );

void main() {
  test('full-scan watcher path matching ignores case and separators', () {
    expect(
      fullScanPathsWithinRoot(r'C:\', r'c:\Temp\cache.bin'),
      isTrue,
    );
    expect(
      fullScanPathsWithinRoot(
          r'C:\Users\Cleaner', r'c:/users/cleaner/Temp/cache.bin'),
      isTrue,
    );
    expect(
      fullScanPathsWithinRoot(r'C:\Users\Cleaner', r'c:\users\cleaner-old'),
      isFalse,
    );
  });

  group('pruneTreeForDisplay', () {
    test('folds sub-threshold files into one roll-up row', () {
      final root = DiskTreeNode(
        name: r'C:\',
        fullPath: r'C:\',
        sizeBytes: 5000,
        fileCount: 4,
        children: [
          _file('big.iso', 4000),
          _file('a.txt', 500),
          _file('b.txt', 300),
          _file('c.txt', 200),
        ],
      );

      pruneTreeForDisplay(root, minEntryBytes: 1000, maxChildren: 100);

      expect(root.children.length, 2);
      expect(root.children.first.name, 'big.iso');

      final rollUp = root.children.last;
      expect(rollUp.isAggregate, isTrue);
      expect(rollUp.aggregatedItemCount, 3);
      expect(rollUp.sizeBytes, 1000);
      expect(rollUp.fileCount, 3);
    });

    test('roll-up rows can never become deletion targets', () {
      final root = DiskTreeNode(
        name: r'C:\',
        fullPath: r'C:\',
        children: [_file('a.txt', 10), _file('b.txt', 10)],
      );

      pruneTreeForDisplay(root, minEntryBytes: 1000, maxChildren: 100);

      final rollUp = root.children.single;
      expect(rollUp.isAggregate, isTrue);
      // Every selection and deletion helper skips empty paths.
      expect(rollUp.fullPath, isEmpty);
    });

    test('caps children per directory, keeping the largest', () {
      final root = DiskTreeNode(
        name: r'C:\',
        fullPath: r'C:\',
        children: [
          for (var i = 0; i < 10; i++) _file('f$i', (10 - i) * 1000),
        ],
      );

      pruneTreeForDisplay(root, minEntryBytes: 0, maxChildren: 3);

      expect(root.children.length, 4); // 3 kept + 1 roll-up
      expect(
        root.children.where((child) => !child.isAggregate).map((c) => c.name),
        ['f0', 'f1', 'f2'],
      );
      final rollUp = root.children.singleWhere((child) => child.isAggregate);
      expect(rollUp.aggregatedItemCount, 7);
    });

    test('preserves parent totals so recalculation stays exact', () {
      final documents = DiskTreeNode(
        name: 'Documents',
        fullPath: r'C:\Documents',
        sizeBytes: 3300,
        fileCount: 3,
        children: [
          _file('report.pdf', 3000),
          _file('note.txt', 200),
          _file('todo.txt', 100),
        ],
      );
      final root = DiskTreeNode(
        name: r'C:\',
        fullPath: r'C:\',
        sizeBytes: 3300,
        fileCount: 3,
        children: [documents],
      );

      pruneTreeForDisplay(root, minEntryBytes: 1000, maxChildren: 100);

      final totalBytes = documents.children
          .fold<int>(0, (sum, child) => sum + child.sizeBytes);
      final totalFiles = documents.children
          .fold<int>(0, (sum, child) => sum + child.fileCount);
      expect(totalBytes, 3300);
      expect(totalFiles, 3);
    });

    test('keeps whole folders whose subtree is under the threshold', () {
      final tiny = DiskTreeNode(
        name: 'Tiny',
        fullPath: r'C:\Tiny',
        sizeBytes: 400,
        fileCount: 2,
        children: [_file('a', 200), _file('b', 200)],
      );
      final root = DiskTreeNode(
        name: r'C:\',
        fullPath: r'C:\',
        children: [_file('big.iso', 9000), tiny],
      );

      pruneTreeForDisplay(root, minEntryBytes: 1000, maxChildren: 100);

      // Folder rows stay visible even when their total is small. Their own
      // small file leaves may still be represented by a roll-up row.
      expect(root.children.length, 2);
      final tinyRow =
          root.children.singleWhere((child) => child.name == 'Tiny');
      expect(tinyRow.isAggregate, isFalse);
      expect(tinyRow.children.single.isAggregate, isTrue);
      expect(tinyRow.children.single.sizeBytes, 400);
      expect(tinyRow.children.single.fileCount, 2);
    });

    test('orders the roll-up row by size like any other entry', () {
      final root = DiskTreeNode(
        name: r'C:\',
        fullPath: r'C:\',
        children: [
          _file('kept.iso', 2000),
          for (var i = 0; i < 50; i++) _file('small$i', 900),
        ],
      );

      pruneTreeForDisplay(root, minEntryBytes: 1000, maxChildren: 100);

      // 45,000 folded bytes outweigh the single kept 2,000-byte file.
      expect(root.children.first.isAggregate, isTrue);
      expect(root.children.first.sizeBytes, 45000);
      expect(root.children.last.name, 'kept.iso');
    });

    test('leaves a tree that needs no folding untouched', () {
      final root = DiskTreeNode(
        name: r'C:\',
        fullPath: r'C:\',
        children: [_file('big.iso', 4000), _file('bigger.iso', 9000)],
      );

      pruneTreeForDisplay(root, minEntryBytes: 1000, maxChildren: 100);

      expect(root.children.length, 2);
      expect(root.children.any((child) => child.isAggregate), isFalse);
    });

    test('keeps junk bytes when entries are folded', () {
      final root = DiskTreeNode(
        name: r'C:\',
        fullPath: r'C:\',
        sizeBytes: 3000,
        fileCount: 3,
        children: [
          DiskTreeNode(
            name: 'cache',
            fullPath: r'C:\cache',
            sizeBytes: 2000,
            fileCount: 2,
            children: [
              DiskTreeNode(
                name: 'junk.tmp',
                fullPath: r'C:\cache\junk.tmp',
                isFile: true,
                sizeBytes: 1500,
                fileCount: 1,
                junkCategoryId: 'windows_temp',
              ),
              _file('safe.txt', 500),
            ],
          ),
          _file('small.txt', 1000),
        ],
      );

      pruneTreeForDisplay(root, minEntryBytes: 2500, maxChildren: 100);

      final cache = root.children.singleWhere((child) => child.name == 'cache');
      expect(cache.isAggregate, isFalse);
      expect(cache.children.single.isAggregate, isTrue);
      expect(cache.junkBytes, 1500);
      expect(root.children.any((child) => child.isAggregate), isTrue);
      expect(root.junkBytes, 1500);
    });
  });

  group('trimTreeToNodeBudget', () {
    test('bounds the display tree without changing parent totals', () {
      final root = DiskTreeNode(
        name: r'C:\',
        fullPath: r'C:\',
        sizeBytes: 5000,
        fileCount: 5,
        children: [
          DiskTreeNode(
            name: 'large',
            fullPath: r'C:\large',
            sizeBytes: 3000,
            fileCount: 3,
            children: [
              _file('a', 1000),
              _file('b', 1000),
              _file('c', 1000),
            ],
          ),
          DiskTreeNode(
            name: 'other',
            fullPath: r'C:\other',
            sizeBytes: 2000,
            fileCount: 2,
            children: [_file('d', 1000), _file('e', 1000)],
          ),
        ],
      );

      trimTreeToNodeBudget(root, maxNodes: 4);

      expect(countNodes(root), lessThanOrEqualTo(4));
      expect(root.sizeBytes, 5000);
      expect(root.fileCount, 5);
      expect(root.children.any((child) => child.isAggregate), isTrue);
    });
  });

  test('preview clone obeys one global node budget across nested folders', () {
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      sizeBytes: 900,
      fileCount: 9,
      children: [
        for (var folder = 0; folder < 3; folder++)
          DiskTreeNode(
            name: 'folder$folder',
            fullPath: 'C:\\folder$folder',
            sizeBytes: 300,
            fileCount: 3,
            children: [
              for (var file = 0; file < 3; file++)
                _file('folder$folder-file$file', 100),
            ],
          ),
      ],
    );

    final preview = cloneDiskTreePreview(
      root,
      maxDepth: 10,
      maxChildrenPerNode: 40,
      maxNodes: 5,
    );

    expect(countNodes(preview), lessThanOrEqualTo(5));
    expect(preview.sizeBytes, root.sizeBytes);
    expect(preview.fileCount, root.fileCount);
  });

  group('DiskTreeNode children', () {
    test('childless nodes share one immutable list', () {
      final a = DiskTreeNode(name: 'a', fullPath: r'C:\a', isFile: true);
      final b = DiskTreeNode(name: 'b', fullPath: r'C:\b', isFile: true);
      expect(identical(a.children, b.children), isTrue);
      expect(a.children, isEmpty);
    });

    test('addChild allocates on first use and replaceChildren releases it', () {
      final dir = DiskTreeNode(name: 'dir', fullPath: r'C:\dir');
      dir.addChild(_file('x', 1));
      expect(dir.children.length, 1);

      dir.replaceChildren(const <DiskTreeNode>[]);
      expect(dir.children, isEmpty);
      expect(
        identical(
          dir.children,
          DiskTreeNode(name: 'other', fullPath: r'C:\other', isFile: true)
              .children,
        ),
        isTrue,
      );
    });

    test('sortBySize is safe on childless nodes', () {
      final leaf =
          DiskTreeNode(name: 'leaf', fullPath: r'C:\leaf', isFile: true);
      expect(leaf.sortBySize, returnsNormally);
    });
  });

  group('old large scan insights', () {
    final now = DateTime(2026, 8, 16);
    final oldActivity = DateTime(2025, 1, 1);

    test('requires both an old activity hint and the file size threshold', () {
      final insight = FullDiskScanInsight(
        name: 'archive.iso',
        path: r'C:\archive.iso',
        isFile: true,
        sizeBytes: defaultOldLargeFileBytes,
        lastModified: oldActivity,
      );

      expect(
        qualifiesAsOldLargeDiskInsight(insight, now: now),
        isTrue,
      );
      expect(
        qualifiesAsOldLargeDiskInsight(
          FullDiskScanInsight(
            name: 'small.zip',
            path: r'C:\small.zip',
            isFile: true,
            sizeBytes: defaultOldLargeFileBytes - 1,
            lastModified: oldActivity,
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('uses newest file timestamp and modified folder timestamp', () {
      expect(
        qualifiesAsOldLargeDiskInsight(
          FullDiskScanInsight(
            name: 'active.iso',
            path: r'C:\active.iso',
            isFile: true,
            sizeBytes: defaultOldLargeFileBytes,
            lastModified: oldActivity,
            lastAccessed: now.subtract(const Duration(days: 2)),
          ),
          now: now,
        ),
        isFalse,
      );
      expect(
        qualifiesAsOldLargeDiskInsight(
          FullDiskScanInsight(
            name: 'archive',
            path: r'C:\archive',
            isFile: false,
            sizeBytes: defaultOldLargeDirectoryBytes,
            lastModified: oldActivity,
            lastAccessed: now.subtract(const Duration(days: 2)),
          ),
          now: now,
        ),
        isTrue,
      );
      expect(
        qualifiesAsOldLargeDiskInsight(
          FullDiskScanInsight(
            name: 'small-archive',
            path: r'C:\small-archive',
            isFile: false,
            sizeBytes: defaultOldLargeDirectoryBytes - 1,
            lastModified: oldActivity,
            lastAccessed: now.subtract(const Duration(days: 2)),
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('retains independent 50-item folder and file caps within 100 total',
        () {
      final folders = <FullDiskScanInsight>[];
      final files = <FullDiskScanInsight>[];
      final oldActivity = DateTime(2025, 1, 1);

      for (var index = 0; index < 60; index++) {
        retainOldLargeDiskInsight(
          folders,
          FullDiskScanInsight(
            name: 'folder-$index',
            path: 'C:\\folder-$index',
            isFile: false,
            sizeBytes: defaultOldLargeDirectoryBytes + index,
            lastModified: oldActivity,
          ),
          now: now,
        );
        retainOldLargeDiskInsight(
          files,
          FullDiskScanInsight(
            name: 'file-$index',
            path: 'C:\\file-$index.bin',
            isFile: true,
            sizeBytes: defaultOldLargeFileBytes + index,
            lastModified: oldActivity,
          ),
          now: now,
        );
      }

      expect(folders, hasLength(defaultOldLargeItemsPerType));
      expect(files, hasLength(defaultOldLargeItemsPerType));
      final combined = buildBoundedOldLargeDiskEvidence(
        folders: folders,
        files: files,
      );
      expect(combined, hasLength(100));
      expect(combined.length, lessThanOrEqualTo(defaultMaxOldLargeItems));
      expect(folders.first.name, 'folder-59');
      expect(files.first.name, 'file-59');
    });

    test('retains the lexical winner at an equal-size cutoff', () {
      final paths = <String>[
        r'C:\zeta.bin',
        r'C:\middle.bin',
        r'C:\alpha.bin',
      ];

      List<String> retainedInOrder(Iterable<String> enumeration) {
        final retained = <FullDiskScanInsight>[];
        for (final path in enumeration) {
          retainOldLargeDiskInsight(
            retained,
            FullDiskScanInsight(
              name: p.basename(path),
              path: path,
              isFile: true,
              sizeBytes: defaultOldLargeFileBytes,
              lastModified: oldActivity,
            ),
            now: now,
            maxItems: 2,
          );
        }
        return retained.map((insight) => insight.path).toList();
      }

      final expected = <String>[r'C:\alpha.bin', r'C:\middle.bin'];
      expect(retainedInOrder(paths), expected);
      expect(retainedInOrder(paths.reversed), expected);
    });

    test('invalidates cached directory evidence for descendant changes', () {
      const directoryInsight = FullDiskScanInsight(
        name: 'archive',
        path: r'C:\Data\Archive',
        isFile: false,
        sizeBytes: defaultOldLargeDirectoryBytes,
      );
      const fileInsight = FullDiskScanInsight(
        name: 'archive.bin',
        path: r'C:\Data\Archive.bin',
        isFile: true,
        sizeBytes: defaultOldLargeFileBytes,
      );

      expect(
        isOldLargeInsightInvalidatedByDirtyDirectories(
          directoryInsight,
          <String>[r'c:/data/archive/new-folder'],
        ),
        isTrue,
      );
      expect(
        isOldLargeInsightInvalidatedByDirtyDirectories(
          fileInsight,
          <String>[r'C:\Data\Archive\new-folder'],
        ),
        isFalse,
      );
      expect(
        isOldLargeInsightInvalidatedByDirtyDirectories(
          fileInsight,
          <String>[r'C:\Data'],
        ),
        isTrue,
      );
    });

    test('dirty drive roots invalidate file and folder evidence', () {
      const directoryInsight = FullDiskScanInsight(
        name: 'archive',
        path: r'C:\Data\Archive',
        isFile: false,
        sizeBytes: defaultOldLargeDirectoryBytes,
      );
      const fileInsight = FullDiskScanInsight(
        name: 'archive.bin',
        path: r'C:\Data\Archive\archive.bin',
        isFile: true,
        sizeBytes: defaultOldLargeFileBytes,
      );

      for (final dirtyRoot in <String>[r'C:\', r'c:/']) {
        expect(
          isOldLargeInsightInvalidatedByDirtyDirectories(
            directoryInsight,
            <String>[dirtyRoot],
          ),
          isTrue,
          reason: 'Directory evidence should be invalidated by $dirtyRoot',
        );
        expect(
          isOldLargeInsightInvalidatedByDirtyDirectories(
            fileInsight,
            <String>[dirtyRoot],
          ),
          isTrue,
          reason: 'File evidence should be invalidated by $dirtyRoot',
        );
      }
    });

    test('directory invalidation respects ancestors and sibling boundaries',
        () {
      const directoryInsight = FullDiskScanInsight(
        name: 'archive',
        path: r'C:\Data\Archive',
        isFile: false,
        sizeBytes: defaultOldLargeDirectoryBytes,
      );

      expect(
        isOldLargeInsightInvalidatedByDirtyDirectories(
          directoryInsight,
          <String>[r'C:\Data'],
        ),
        isTrue,
      );
      expect(
        isOldLargeInsightInvalidatedByDirtyDirectories(
          directoryInsight,
          <String>[r'C:\Data\Archive2'],
        ),
        isFalse,
      );
    });
  });

  test('full scan keeps small directories while compacting file leaves',
      () async {
    if (!Platform.isWindows) return;

    final tempRoot = await Directory.systemTemp.createTemp('cb-full-scan-');
    try {
      final folder =
          await Directory(p.join(tempRoot.path, 'small-folder')).create();
      await File(p.join(folder.path, 'small.txt')).writeAsString('small');

      final handle = await spawnFullDiskScan(
        drivePath: tempRoot.path,
        minDisplayEntryBytes: 1024 * 1024,
        maxChildrenPerDirectory: 1,
      );
      final result = await handle.future;

      final folderNode = result.root.children
          .singleWhere((child) => child.name == 'small-folder');
      expect(folderNode.isAggregate, isFalse);
      expect(folderNode.children.single.isAggregate, isTrue);
      expect(folderNode.children.single.fileCount, 1);
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  test('full scan reconstructs the complete nested tree across final batches',
      () async {
    if (!Platform.isWindows) return;

    final tempRoot = await Directory.systemTemp.createTemp('cb-batched-scan-');
    try {
      final nested = await Directory(p.join(tempRoot.path, 'nested'))
          .create(recursive: true);
      final deep =
          await Directory(p.join(nested.path, 'deep')).create(recursive: true);
      await File(p.join(nested.path, 'child.txt')).writeAsString('child');
      await File(p.join(deep.path, 'junk.bin')).writeAsString('junk');
      await File(p.join(deep.path, 'kept.txt')).writeAsString('ok');

      final handle = await spawnFullDiskScan(
        drivePath: tempRoot.path,
        minDisplayEntryBytes: 0,
        maxChildrenPerDirectory: 10,
        finalTreeBatchSize: 1,
        junkRules: <FullDiskJunkRule>[
          FullDiskJunkRule(basePath: deep.path, categoryId: 'deep-junk'),
        ],
      );
      final result = await handle.future;

      expect(result.nodeCount, 6);
      expect(countNodes(result.root), result.nodeCount);
      final nestedNode = result.root.children.single;
      expect(nestedNode.name, 'nested');
      expect(nestedNode.children.map((child) => child.name).toList(),
          <String>['deep', 'child.txt']);

      final deepNode =
          nestedNode.children.singleWhere((child) => child.name == 'deep');
      expect(deepNode.children.map((child) => child.name).toList(),
          <String>['junk.bin', 'kept.txt']);
      expect(deepNode.junkCategoryId, 'deep-junk');
      expect(deepNode.hasJunkChildren, isTrue);
      expect(deepNode.junkBytes, 6);
      expect(result.root.junkBytes, 6);
      expect(result.cleanableCount, 3);
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  test('full scan preserves whole-directory and glob junk matching', () async {
    if (!Platform.isWindows) return;

    final tempRoot = await Directory.systemTemp.createTemp('cb-rule-scan-');
    try {
      final wholeDirectory =
          await Directory(p.join(tempRoot.path, 'whole')).create();
      final globDirectory =
          await Directory(p.join(tempRoot.path, 'glob', 'nested'))
              .create(recursive: true);
      await File(p.join(wholeDirectory.path, 'inside.bin'))
          .writeAsString('whole');
      await File(p.join(globDirectory.path, 'matched.tmp'))
          .writeAsString('matched');
      await File(p.join(globDirectory.path, 'kept.txt')).writeAsString('kept');

      final handle = await spawnFullDiskScan(
        drivePath: tempRoot.path,
        minDisplayEntryBytes: 0,
        maxChildrenPerDirectory: 10,
        junkRules: <FullDiskJunkRule>[
          FullDiskJunkRule(
            basePath: wholeDirectory.path,
            categoryId: 'whole',
          ),
          FullDiskJunkRule(
            basePath: p.join(tempRoot.path, 'glob'),
            categoryId: 'glob',
            includeGlobs: const <String>['*.tmp'],
          ),
        ],
      );
      final result = await handle.future;

      final wholeNode =
          result.root.children.singleWhere((child) => child.name == 'whole');
      final globNode =
          result.root.children.singleWhere((child) => child.name == 'glob');
      final nestedNode =
          globNode.children.singleWhere((child) => child.name == 'nested');
      expect(wholeNode.junkCategoryId, 'whole');
      expect(
        nestedNode.children
            .singleWhere((child) => child.name == 'matched.tmp')
            .junkCategoryId,
        'glob',
      );
      expect(
        nestedNode.children
            .singleWhere((child) => child.name == 'kept.txt')
            .junkCategoryId,
        isNull,
      );
      expect(result.junkBytes, 12);
      expect(result.cleanableCount, 3);
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  test('tracked refresh refreshes only changed directories', () async {
    if (!Platform.isWindows) return;

    final tempRoot = await Directory.systemTemp.createTemp('cb-usn-scan-');
    try {
      await File(p.join(tempRoot.path, 'before.txt')).writeAsString('before');
      final firstHandle = await spawnFullDiskScan(
        drivePath: tempRoot.path,
        minDisplayEntryBytes: 0,
        maxChildrenPerDirectory: 10,
      );
      final first = await firstHandle.future;

      await File(p.join(tempRoot.path, 'after.txt')).writeAsString('after');
      final secondHandle = await spawnFullDiskScan(
        drivePath: tempRoot.path,
        minDisplayEntryBytes: 0,
        maxChildrenPerDirectory: 10,
        baseRoot: first.root,
        baseOldLargeItems: first.oldLargeItems,
        trackedDirtyDirectories: <String>[tempRoot.path],
        hasTrackedChanges: true,
      );
      final second = await secondHandle.future;

      expect(
        second.scanMode,
        FullDiskScanMode.incremental,
        reason: second.incrementalFallbackReason,
      );
      expect(second.changedDirectoryCount, greaterThanOrEqualTo(1));
      expect(second.root.fileCount, 2);
      expect(second.root.children.any((child) => child.name == 'after.txt'),
          isTrue);
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  test('service reuses the cached scan for the same drive path', () async {
    if (!Platform.isWindows) return;

    final tempRoot = await Directory.systemTemp.createTemp('cb-usn-cache-');
    try {
      await File(p.join(tempRoot.path, 'before.txt')).writeAsString('before');
      final service = DiskCleanerService.instance;
      final firstHandle = await service.scanFullDisk(
        drivePath: tempRoot.path,
        minDisplayEntryBytes: 0,
        maxChildrenPerDirectory: 10,
      );
      final first = await firstHandle.future;

      expect(
        first.journalCursor != null,
        DiskUsnJournalReader.canReadChanges(tempRoot.path),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.canUseIncrementalScan(tempRoot.path), isFalse);
      expect(service.cachedFullScanRoot(tempRoot.path), isNull);

      final unchangedHandle = await service.scanFullDisk(
        drivePath: tempRoot.path,
        minDisplayEntryBytes: 0,
        maxChildrenPerDirectory: 10,
      );
      final unchanged = await unchangedHandle.future;
      expect(
        unchanged.scanMode,
        FullDiskScanMode.full,
        reason: unchanged.incrementalFallbackReason,
      );
      expect(unchanged.root.fileCount, 1);
      expect(identical(unchanged.root, first.root), isFalse);

      await File(p.join(tempRoot.path, 'after.txt')).writeAsString('after');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final changedHandle = await service.scanFullDisk(
        drivePath: tempRoot.path,
        minDisplayEntryBytes: 0,
        maxChildrenPerDirectory: 10,
      );
      final changed = await changedHandle.future;

      expect(
        changed.scanMode,
        FullDiskScanMode.full,
        reason: changed.incrementalFallbackReason,
      );
      expect(changed.root.fileCount, 2);
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  test('subtree scans are not retained as long-lived incremental caches',
      () async {
    if (!Platform.isWindows) return;

    final tempRoot = await Directory.systemTemp.createTemp('cb-subtree-scan-');
    try {
      await File(p.join(tempRoot.path, 'file.txt')).writeAsString('file');
      final service = DiskCleanerService.instance;
      final handle = await service.scanFullDisk(
        drivePath: tempRoot.path,
        minDisplayEntryBytes: 0,
        maxChildrenPerDirectory: 10,
      );
      await handle.future;

      expect(service.canUseIncrementalScan(tempRoot.path), isFalse);
      expect(service.cachedFullScanRoot(tempRoot.path), isNull);
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });
}
