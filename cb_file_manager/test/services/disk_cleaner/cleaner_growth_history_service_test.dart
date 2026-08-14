import 'dart:async';

import 'package:cb_file_manager/services/disk_cleaner/cleaner_growth_history_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FullDiskScanResult _scan({
  required int usersBytes,
  int cacheBytes = 0,
  List<FullDiskScanCoverageIssue> coverageIssues = const [],
}) {
  return FullDiskScanResult(
    root: DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      sizeBytes: usersBytes,
      children: <DiskTreeNode>[
        DiskTreeNode(
          name: 'Users',
          fullPath: r'C:\Users',
          sizeBytes: usersBytes,
          children: <DiskTreeNode>[
            DiskTreeNode(
              name: 'Cache',
              fullPath: r'C:\Users\me\Cache',
              sizeBytes: cacheBytes,
            ),
          ],
        ),
      ],
    ),
    duration: const Duration(seconds: 1),
    coverageIssues: coverageIssues,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('first completed scan creates a baseline without reporting growth',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final service = CleanerGrowthHistoryService(preferences);

    final comparison = await service.compareAndStore(
      _scan(usersBytes: 1024 * 1024 * 1024),
      scannedAt: DateTime(2026, 8, 10),
    );

    expect(comparison.hasBaseline, isFalse);
    expect(comparison.folders, isEmpty);
  });

  test('large snapshot traversal yields instead of monopolizing the caller',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final service = CleanerGrowthHistoryService(preferences);
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      children: <DiskTreeNode>[
        for (var i = 0; i < 3000; i++)
          DiskTreeNode(
            name: 'folder-$i',
            fullPath: 'C:\\folder-$i',
            sizeBytes: i,
          ),
      ],
    );
    var eventLoopWasReached = false;
    Timer.run(() => eventLoopWasReached = true);

    await service.compareAndStore(
      FullDiskScanResult(root: root, duration: Duration.zero),
      scannedAt: DateTime(2026, 8, 12),
    );

    expect(eventLoopWasReached, isTrue);
  });

  test('reports largest meaningful directory increases on the same drive',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final service = CleanerGrowthHistoryService(preferences);
    final baselineAt = DateTime(2026, 8, 10, 9);
    await service.compareAndStore(
      _scan(
        usersBytes: 1024 * 1024 * 1024,
        cacheBytes: 100 * 1024 * 1024,
      ),
      scannedAt: baselineAt,
    );

    final comparison = await service.compareAndStore(
      _scan(
        usersBytes: 1400 * 1024 * 1024,
        cacheBytes: 300 * 1024 * 1024,
      ),
      scannedAt: DateTime(2026, 8, 12, 9),
    );

    expect(comparison.baselineAt, baselineAt);
    expect(comparison.folders, hasLength(2));
    expect(comparison.folders.first.path, r'C:\Users');
    expect(
      comparison.folders.first.increasedBytes,
      376 * 1024 * 1024,
    );
    expect(comparison.folders.last.path, r'C:\Users\me\Cache');
  });

  test('does not compare folders overlapping incomplete coverage', () async {
    final preferences = await SharedPreferences.getInstance();
    final service = CleanerGrowthHistoryService(preferences);
    await service.compareAndStore(
      _scan(
        usersBytes: 1024 * 1024 * 1024,
        cacheBytes: 100 * 1024 * 1024,
        coverageIssues: const <FullDiskScanCoverageIssue>[
          FullDiskScanCoverageIssue(
            path: r'C:\Users\me\Cache',
            reason: FullDiskScanCoverageIssueReason.inaccessible,
          ),
        ],
      ),
      scannedAt: DateTime(2026, 8, 10),
    );

    final comparison = await service.compareAndStore(
      _scan(
        usersBytes: 1400 * 1024 * 1024,
        cacheBytes: 500 * 1024 * 1024,
      ),
      scannedAt: DateTime(2026, 8, 12),
    );

    expect(comparison.hasBaseline, isTrue);
    expect(comparison.folders, isEmpty);
  });

  test('suppresses an ancestor when a descendant explains the same growth',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final service = CleanerGrowthHistoryService(preferences);
    await service.compareAndStore(
      _scan(
        usersBytes: 1024 * 1024 * 1024,
        cacheBytes: 100 * 1024 * 1024,
      ),
      scannedAt: DateTime(2026, 8, 10),
    );

    final comparison = await service.compareAndStore(
      _scan(
        usersBytes: 1224 * 1024 * 1024,
        cacheBytes: 300 * 1024 * 1024,
      ),
      scannedAt: DateTime(2026, 8, 12),
    );

    expect(comparison.folders, hasLength(1));
    expect(comparison.folders.single.path, r'C:\Users\me\Cache');
  });

  test('keeps independent baselines for different drives', () async {
    final preferences = await SharedPreferences.getInstance();
    final service = CleanerGrowthHistoryService(preferences);
    await service.compareAndStore(
      _scan(usersBytes: 1024 * 1024 * 1024),
      scannedAt: DateTime(2026, 8, 10),
    );
    final dScan = _scan(usersBytes: 2 * 1024 * 1024 * 1024);
    final dRoot = DiskTreeNode(
      name: r'D:\',
      fullPath: r'D:\',
      sizeBytes: dScan.root.sizeBytes,
      children: <DiskTreeNode>[
        DiskTreeNode(
          name: 'Data',
          fullPath: r'D:\Data',
          sizeBytes: dScan.root.sizeBytes,
        ),
      ],
    );

    final comparison = await service.compareAndStore(
      FullDiskScanResult(root: dRoot, duration: Duration.zero),
      scannedAt: DateTime(2026, 8, 12),
    );

    expect(comparison.hasBaseline, isFalse);
    expect(comparison.folders, isEmpty);
  });
}
