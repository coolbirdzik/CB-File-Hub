import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_isolate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('overlapping rules scan physical files once per category', () async {
    final root = await Directory.systemTemp.createTemp('cb-cleaner-worker-');
    try {
      final nested = await Directory(p.join(root.path, 'nested')).create();
      final rootFile = File(p.join(root.path, 'root.tmp'));
      final nestedFile = File(p.join(nested.path, 'nested.tmp'));
      await rootFile.writeAsBytes(List<int>.filled(7, 1));
      await nestedFile.writeAsBytes(List<int>.filled(11, 1));

      final handle = await spawnScanWithResolvedRules(
        drivesScanned: <String>[root.path],
        rules: <ResolvedRule>[
          ResolvedRule(
            categoryId: 'cache',
            basePath: root.path,
            includeGlobs: const <String>['*.tmp'],
          ),
          ResolvedRule(
            categoryId: 'cache',
            basePath: nested.path,
            includeGlobs: const <String>['nested.*'],
          ),
          ResolvedRule(
            categoryId: 'review',
            basePath: nested.path,
            includeGlobs: const <String>['nested.tmp'],
          ),
        ],
      );
      final report = await handle.future;

      final cacheItems = report.itemsByCategory['cache']!;
      expect(cacheItems.map((item) => p.basename(item.path)).toSet(),
          <String>{'root.tmp', 'nested.tmp'});
      expect(cacheItems.fold<int>(0, (sum, item) => sum + item.sizeBytes), 18);

      final reviewItems = report.itemsByCategory['review']!;
      expect(reviewItems, hasLength(1));
      expect(reviewItems.single.path, nestedFile.path);
      expect(reviewItems.single.sizeBytes, 11);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('preserves glob, age, and non-recursive rule semantics', () async {
    final root = await Directory.systemTemp.createTemp('cb-cleaner-worker-');
    try {
      final nested = await Directory(p.join(root.path, 'nested')).create();
      final old = DateTime.now().subtract(const Duration(days: 30));
      final recent = DateTime.now().subtract(const Duration(days: 1));
      final oldLog = File(p.join(root.path, 'old.log'));
      final recentLog = File(p.join(root.path, 'recent.log'));
      final excludedLog = File(p.join(root.path, 'excluded.log'));
      final nestedLog = File(p.join(nested.path, 'nested.log'));
      await oldLog.writeAsString('old');
      await recentLog.writeAsString('recent');
      await excludedLog.writeAsString('excluded');
      await nestedLog.writeAsString('nested');
      await oldLog.setLastModified(old);
      await recentLog.setLastModified(recent);
      await excludedLog.setLastModified(old);
      await nestedLog.setLastModified(old);

      final handle = await spawnScanWithResolvedRules(
        drivesScanned: <String>[root.path],
        rules: <ResolvedRule>[
          ResolvedRule(
            categoryId: 'old_logs',
            basePath: root.path,
            includeGlobs: const <String>['*.log'],
            excludeGlobs: const <String>['excluded*'],
            minAge: const Duration(days: 7),
          ),
          ResolvedRule(
            categoryId: 'root_only',
            basePath: root.path,
            includeGlobs: const <String>['*.log'],
            recursive: false,
          ),
        ],
      );
      final report = await handle.future;

      expect(
        report.itemsByCategory['old_logs']!
            .map((item) => p.basename(item.path))
            .toSet(),
        <String>{'old.log', 'nested.log'},
      );
      expect(
        report.itemsByCategory['root_only']!
            .map((item) => p.basename(item.path))
            .toSet(),
        <String>{'old.log', 'recent.log', 'excluded.log'},
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('ignores empty and missing rule roots without permission warnings',
      () async {
    final root = await Directory.systemTemp.createTemp('cb-cleaner-worker-');
    try {
      final empty = await Directory(p.join(root.path, 'empty')).create();
      final missing = p.join(root.path, 'missing');
      final handle = await spawnScanWithResolvedRules(
        drivesScanned: <String>[root.path],
        rules: <ResolvedRule>[
          ResolvedRule(categoryId: 'empty', basePath: empty.path),
          ResolvedRule(categoryId: 'missing', basePath: missing),
        ],
      );
      final report = await handle.future;

      expect(report.itemsByCategory, isEmpty);
      expect(report.warnings, isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('times out root opening with a per-category actionable warning',
      () async {
    final root = await Directory.systemTemp.createTemp('cb-cleaner-worker-');
    try {
      final handle = await spawnScanWithResolvedRules(
        drivesScanned: <String>[root.path],
        // Duration.zero is the documented deterministic seam for the
        // first-entry timeout; the directory itself still exists.
        rootOpenTimeout: Duration.zero,
        rules: <ResolvedRule>[
          ResolvedRule(categoryId: 'blocked_provider', basePath: root.path),
        ],
      );
      final report = await handle.future.timeout(const Duration(seconds: 2));

      expect(report.itemsByCategory, isEmpty);
      expect(
        report.warnings,
        contains(
          startsWith('blocked_provider: Permission probe timed out'),
        ),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
