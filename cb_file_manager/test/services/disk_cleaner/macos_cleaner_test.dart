import 'dart:io';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_categories.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_paths.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_safety.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_tree_cleanup.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_selection.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/services/disk_cleaner/macos_cleaner_platform.dart';
import 'package:cb_file_manager/services/disk_cleaner/scan_target_resolver.dart';
import 'package:cb_file_manager/services/disk_cleaner/windows_known_folders.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('macOS rules resolve inside HOME without Windows categories', () {
    expect(CleanerPaths.supports('macos'), isTrue);
    expect(CleanerPaths.supports('windows'), isTrue);
    expect(CleanerPaths.supports('android'), isFalse);
    final categories = CleanerCategories.all(operatingSystem: 'macos');
    expect(categories.map((category) => category.id), [
      'browser_cache',
      'app_cache',
      'crash_dumps_logs',
      'dev_cache',
      'package_download_cache',
      'electron_cache',
      'xcode_build_cache',
      'old_downloads_review',
    ]);
    const env = {'HOME': '/Users/test'};
    for (final category in categories) {
      for (final rule in category.rules) {
        final base = WindowsKnownFolders.resolvePosix(rule.source, env)!;
        expect(base, startsWith('/Users/test/'));
        expect(
          CleanerPathSafety.isMacosPathSafeToDelete('$base/item', env),
          category.reviewOnly ? isFalse : isTrue,
        );
      }
    }
    for (final path in [
      '/Users/test/Documents/a',
      '/Users/test/Library/Application Support/a',
      '/Users/test/Library/Caches-other/a',
      '/Users/test/Library/Caches/../Documents/a',
      '/Users/other/Library/Caches/a',
      '/System/Library/Caches/a',
      'Library/Caches/a',
    ]) {
      expect(
        CleanerPathSafety.isMacosPathSafeToDelete(path, env),
        isFalse,
        reason: path,
      );
    }
    expect(
      CleanerPathSafety.isMacosPathSafeToDelete(
        '/System/Volumes/Data/Users/test/Library/Caches/a',
        env,
      ),
      isTrue,
    );
  });

  test(
    'POSIX selection, target resolution and pruning preserve case',
    () async {
      DiskTreeNode file(String name) => DiskTreeNode(
        name: name,
        fullPath: '/Users/test/$name',
        isFile: true,
        sizeBytes: 10,
        fileCount: 1,
      );
      final upper = file('File');
      final lower = file('file');
      final root = DiskTreeNode(
        name: 'test',
        fullPath: '/System/Volumes/Data/Users/test',
        sizeBytes: 20,
        fileCount: 2,
        children: [upper, lower],
      );
      expect(resolveScanTarget(root, lower.fullPath).node, same(lower));
      final targets = DiskTreeSelection.setExactTargetChecked([], upper, true);
      expect(
        DiskTreeSelection.setExactTargetChecked(targets, lower, true),
        hasLength(2),
      );
      await pruneCleanedDiskTree(root, {upper.fullPath});
      expect(root.children, [same(lower)]);
      expect(root.sizeBytes, 10);
      expect(
        CleanerPaths.contains('/Users/test', '/Users/test-other/a'),
        isFalse,
      );
      expect(CleanerPaths.ancestors('/Users/test/file'), [
        '/Users/test/file',
        '/Users/test',
        '/Users',
        '/',
      ]);
    },
  );

  test(
    'macOS channel preserves exact paths and per-item Trash failures',
    () async {
      final calls = <MethodCall>[];
      const first = '/Users/test/a"\nfile';
      const second = '/Users/test/locked';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MacosCleanerPlatform.channel, (call) async {
            calls.add(call);
            if (call.method == 'getCleanerVolumes') {
              return [
                {
                  'path': '/System/Volumes/Data',
                  'label': 'Macintosh HD',
                  'totalBytes': 1000,
                  'freeBytes': 400,
                },
                {
                  'path': '/Volumes/External',
                  'label': 'External',
                  'totalBytes': 2000,
                  'freeBytes': 1000,
                },
              ];
            }
            return [
              {'path': first},
              {'path': second, 'error': 'Permission denied'},
            ];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MacosCleanerPlatform.channel, null),
      );
      final volumes = await MacosCleanerPlatform.volumes();
      expect(volumes.map((drive) => drive.path), [
        '/System/Volumes/Data',
        '/Volumes/External',
      ]);
      expect(volumes.first.freeBytes, 400);
      expect(await MacosCleanerPlatform.trash([first, second]), {
        first: null,
        second: 'Permission denied',
      });
      expect(calls.last.arguments, {
        'paths': [first, second],
      });
    },
  );

  test(
    'portable scanner counts nested files and folds the small-file tail',
    () async {
      final root = await Directory.systemTemp.createTemp('cb_portable_scan_');
      try {
        final nested = await Directory(p.join(root.path, 'nested')).create();
        await File(
          p.join(nested.path, 'small.tmp'),
        ).writeAsBytes(List.filled(3, 1));
        await File(
          p.join(nested.path, 'big.tmp'),
        ).writeAsBytes(List.filled(20, 1));
        await File(
          p.join(root.path, 'keep.bin'),
        ).writeAsBytes(List.filled(7, 1));
        final handle = await spawnFullDiskScan(
          drivePath: root.path,
          usePortableScanner: true,
          useNativeScanner: false,
          minDisplayEntryBytes: 10,
          maxChildrenPerDirectory: 1,
          junkRules: [
            FullDiskJunkRule(basePath: nested.path, categoryId: 'app_cache'),
          ],
        );
        final result = await handle.future;
        expect(result.root.sizeBytes, 30);
        expect(result.root.fileCount, 3);
        expect(result.root.junkBytes, 23);
        final folder = result.root.children.singleWhere((node) => !node.isFile);
        expect(
          folder.children.where((node) => !node.isAggregate).single.name,
          'big.tmp',
        );
        expect(
          folder.children.singleWhere((node) => node.isAggregate).sizeBytes,
          3,
        );
        expect(result.coverageIssues, isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
