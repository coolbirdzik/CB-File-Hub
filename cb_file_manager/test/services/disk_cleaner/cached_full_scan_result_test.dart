import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'returns the completed cached result even when refresh tracking is unavailable',
    () async {
      if (!Platform.isWindows) return;

      final root =
          DiskTreeNode(
            name: r'Z:\',
            fullPath: r'Z:\',
            sizeBytes: 42,
            fileCount: 1,
            isExpanded: true,
          )..addChild(
            DiskTreeNode(
              name: 'cache.tmp',
              fullPath: r'Z:\cache.tmp',
              isFile: true,
              sizeBytes: 42,
              fileCount: 1,
              junkCategoryId: 'test-cache',
            ),
          );
      final oldLarge = FullDiskScanInsight(
        name: 'archive.zip',
        path: r'Z:\archive.zip',
        isFile: true,
        sizeBytes: 8 * 1024 * 1024 * 1024,
        lastModified: DateTime(2020),
      );
      const coverageIssue = FullDiskScanCoverageIssue(
        path: r'Z:\restricted',
        reason: FullDiskScanCoverageIssueReason.inaccessible,
        detail: 'Access denied',
      );
      final result = FullDiskScanResult(
        root: root,
        nodeCount: 2,
        junkBytes: 42,
        cleanableCount: 1,
        duration: const Duration(seconds: 3),
        inaccessible: const <String>[r'Z:\restricted'],
        coverageIssues: <FullDiskScanCoverageIssue>[coverageIssue],
        oldLargeItems: <FullDiskScanInsight>[oldLarge],
        journalCursor: const DiskScanJournalCursor(journalId: 7, nextUsn: 11),
        scanMode: FullDiskScanMode.full,
        changedDirectoryCount: 0,
        incrementalFallbackReason: 'The watcher was unavailable.',
      );

      var scanCalls = 0;
      final service = DiskCleanerService.forTesting(
        fullDiskScanSpawner:
            ({
              required drivePath,
              maxDepth = 20,
              minDisplayEntryBytes = defaultMinDisplayEntryBytes,
              maxChildrenPerDirectory = defaultMaxChildrenPerDirectory,
              junkRules = const <FullDiskJunkRule>[],
              baseRoot,
              journalCursor,
              baseOldLargeItems = const <FullDiskScanInsight>[],
              trackedDirtyDirectories = const <String>[],
              hasTrackedChanges = false,
              onCompleted,
            }) async {
              scanCalls++;
              onCompleted?.call(result);
              return FullDiskScanHandle.completed(
                drivePath: drivePath,
                result: result,
              );
            },
      );

      final handle = await service.scanFullDisk(drivePath: r'Z:\');
      await handle.future;

      final cached = service.cachedFullScanResult(r'z:/');
      expect(scanCalls, 1);
      expect(cached, isNotNull);
      expect(cached!.root, same(root));
      expect(cached.nodeCount, 2);
      expect(cached.junkBytes, 42);
      expect(cached.cleanableCount, 1);
      expect(cached.oldLargeItems.single, same(oldLarge));
      expect(cached.inaccessible, <String>[r'Z:\restricted']);
      expect(cached.coverageIssues.single, same(coverageIssue));
      expect(cached.journalCursor!.journalId, 7);
      expect(cached.journalCursor!.nextUsn, 11);
      expect(cached.incrementalFallbackReason, 'The watcher was unavailable.');
    },
  );
}
