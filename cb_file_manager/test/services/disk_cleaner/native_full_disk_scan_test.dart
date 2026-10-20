import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The Disk Cleaner walks with package:cb_native when it is built. Its result
/// must be the one the Dart walker produces: same nodes, sizes, junk, folded
/// rows, coverage issues and old-large evidence.
void main() {
  final skip = !Platform.isWindows
      ? 'the full-disk scanner is Windows-only'
      : !CbNative.isAvailable
      ? 'Rust library not built'
      : null;

  late Directory root;

  setUpAll(() async {
    if (skip != null) return;
    root = await Directory.systemTemp.createTemp('cb_native_disk_scan_');
    Future<void> file(String relative, int size) async {
      final target = File(p.join(root.path, relative));
      await target.parent.create(recursive: true);
      final handle = await target.open(mode: FileMode.write);
      await handle.truncate(size);
      await handle.close();
    }

    for (var i = 0; i < 8; i++) {
      await file('media/clip_$i.mp4', 1000 + i * 100);
    }
    await file('media/tiny.txt', 3);
    await file('media/Bổ Não/nested.mkv', 4096);
    await file('media/huge.iso', 101 * 1024 * 1024);
    // Old-large evidence needs a file untouched for months.
    final huge = File(p.join(root.path, 'media', 'huge.iso'));
    await huge.setLastModified(DateTime(2020));
    await huge.setLastAccessed(DateTime(2020));
    await file('cache/a.bin', 2048);
    await file('cache/deep/b.bin', 512);
    await file('work/build.tmp', 700);
    await file('work/keep.doc', 900);
    await file('work/THUMBS1.DB', 50);
    await file('a/b/c/d/e/too_deep.txt', 10);
    await Directory(p.join(root.path, r'$RECYCLE.BIN')).create();
    await file(r'$RECYCLE.BIN/ignored.bin', 5000);
    final junction = await Process.run('cmd', [
      '/c',
      'mklink',
      '/J',
      p.join(root.path, 'link_to_media'),
      p.join(root.path, 'media'),
    ]);
    expect(junction.exitCode, 0, reason: '${junction.stderr}');
  });

  tearDownAll(() async {
    if (skip != null) return;
    await root.delete(recursive: true);
  });

  List<FullDiskJunkRule> rules() => [
    FullDiskJunkRule(basePath: p.join(root.path, 'cache'), categoryId: 'cache'),
    FullDiskJunkRule(
      basePath: p.join(root.path, 'work'),
      categoryId: 'temp',
      includeGlobs: const ['*.tmp', 'thumbs?.db'],
    ),
  ];

  Future<FullDiskScanResult> scan({
    required bool native,
    DiskTreeNode? baseRoot,
    List<String> dirty = const [],
  }) async {
    final handle = await spawnFullDiskScan(
      drivePath: root.path,
      maxDepth: 4,
      minDisplayEntryBytes: 600,
      maxChildrenPerDirectory: 3,
      junkRules: rules(),
      baseRoot: baseRoot,
      trackedDirtyDirectories: dirty,
      hasTrackedChanges: baseRoot != null,
      useNativeScanner: native,
    );
    handle.progress.listen((_) {});
    handle.treeSnapshots.listen((_) {});
    return handle.future;
  }

  test('full scan matches the Dart walker', () async {
    final dart = await scan(native: false);
    final native = await scan(native: true);
    _expectSameResult(native, dart);

    expect(dart.root.junkBytes, greaterThan(0));
    expect(
      dart.coverageIssues.map((issue) => issue.reason),
      containsAll([
        FullDiskScanCoverageIssueReason.reparsePoint,
        FullDiskScanCoverageIssueReason.maxDepthReached,
      ]),
    );
    expect(dart.oldLargeItems.map((item) => item.name), contains('huge.iso'));
  }, skip: skip);

  test('incremental refresh matches the Dart walker', () async {
    final base = await scan(native: false);
    final media = p.join(root.path, 'media');
    final added = File(p.join(media, 'added.mov'));
    await added.writeAsBytes(List.filled(1500, 1));
    try {
      final dart = await scan(
        native: false,
        baseRoot: base.root,
        dirty: [media],
      );
      final native = await scan(
        native: true,
        baseRoot: base.root,
        dirty: [media],
      );
      expect(dart.scanMode, FullDiskScanMode.incremental);
      _expectSameResult(native, dart);
    } finally {
      await added.delete();
    }
  }, skip: skip);
}

void _expectSameResult(FullDiskScanResult actual, FullDiskScanResult expected) {
  expect(_rows(actual.root), _rows(expected.root));
  expect(actual.nodeCount, expected.nodeCount);
  expect(actual.junkBytes, expected.junkBytes);
  expect(actual.cleanableCount, expected.cleanableCount);
  expect(actual.inaccessible.toSet(), expected.inaccessible.toSet());
  expect(_issues(actual), _issues(expected));
  expect(_insights(actual), _insights(expected));
}

/// Children of equal size may be ordered differently, so compare as a set of
/// rows keyed by path (roll-up rows by their parent).
Set<String> _rows(DiskTreeNode node, [String parent = '']) {
  final key = node.fullPath.isEmpty ? '$parent/<folded>' : node.fullPath;
  final rows = <String>{
    '$key|file=${node.isFile}|size=${node.sizeBytes}|files=${node.fileCount}'
        '|junk=${node.junkCategoryId}|junkBytes=${node.junkBytes}'
        '|hasJunk=${node.hasJunkChildren}|folded=${node.aggregatedItemCount}',
  };
  for (final child in node.children) {
    rows.addAll(_rows(child, node.fullPath));
  }
  return rows;
}

Set<String> _issues(FullDiskScanResult result) => {
  for (final issue in result.coverageIssues)
    '${issue.reason.name}|${issue.path}|${issue.detail}',
};

List<String> _insights(FullDiskScanResult result) => [
  for (final item in result.oldLargeItems)
    '${item.isFile}|${item.path}|${item.sizeBytes}|${item.lastModified}'
        '|${item.lastAccessed}',
];
