import 'package:cb_file_manager/services/ai/disk_cleaner_skill.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tabId = 'cleaner-scan-advice-test-tab';
  final service = DiskCleanerService.instance;

  tearDown(() {
    service.clearCleanerScanContext(tabId);
  });

  test('junk scan output ranks evidence and does not invite immediate cleanup',
      () {
    final report = ScanReport(
      drivesScanned: const [r'C:\'],
      itemsByCategory: {
        'browser_cache': [
          const JunkItem(
            path:
                r'C:\Users\Tester\AppData\Local\Google\Chrome\User Data\Default\Cache',
            sizeBytes: 900 * 1024 * 1024,
            categoryId: 'browser_cache',
            isContainerOnly: true,
          ),
          const JunkItem(
            path:
                r'C:\Users\Tester\AppData\Local\Microsoft\Edge\User Data\Default\Cache',
            sizeBytes: 300 * 1024 * 1024,
            categoryId: 'browser_cache',
            isContainerOnly: true,
          ),
        ],
      },
      warnings: const [],
      scannedAt: DateTime.utc(2026, 8, 12),
    );

    final output = ToolExecutor().formatJunkScanReport(report, 'sc_test');

    expect(output, contains('JUNK SCAN ANALYSIS'));
    expect(output, contains('Browser caches'));
    expect(output, contains('safety=safe'));
    expect(output, contains('owner=Google Chrome'));
    expect(output, contains('CLEAN:'));
    expect(output, contains('analysis-only'));
    expect(output, isNot(contains('To clean: call clean_disk_junk')));
  });

  test('current scan reports large files separately from cleanup candidates',
      () async {
    final installer = DiskTreeNode(
      name: 'installer.iso',
      fullPath: r'C:\Users\Tester\Downloads\installer.iso',
      isFile: true,
      sizeBytes: 3 * 1024 * 1024 * 1024,
      fileCount: 1,
    );
    final downloads = DiskTreeNode(
      name: 'Downloads',
      fullPath: r'C:\Users\Tester\Downloads',
      sizeBytes: installer.sizeBytes,
      fileCount: 1,
      children: [installer],
    );
    final cacheFile = DiskTreeNode(
      name: 'data.bin',
      fullPath:
          r'C:\Users\Tester\AppData\Local\Google\Chrome\User Data\Default\Cache\data.bin',
      isFile: true,
      sizeBytes: 700 * 1024 * 1024,
      fileCount: 1,
      junkCategoryId: 'browser_cache',
    );
    final cache = DiskTreeNode(
      name: 'Cache',
      fullPath:
          r'C:\Users\Tester\AppData\Local\Google\Chrome\User Data\Default\Cache',
      sizeBytes: cacheFile.sizeBytes,
      fileCount: 1,
      children: [cacheFile],
      junkCategoryId: 'browser_cache',
    );
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      sizeBytes: downloads.sizeBytes + cache.sizeBytes,
      fileCount: 2,
      children: [downloads, cache],
    );
    service.publishCleanerScanContext(ownerTabId: tabId, root: root);
    expect(
      service.getCleanerScanContext(ownerTabId: tabId)?.isCached,
      isFalse,
    );

    final result = await ToolExecutor(ownerTabId: tabId).execute(
      const ToolCall(
        name: 'get_current_cleaner_scan',
        arguments: {'max_items': 5},
      ),
    );

    expect(result.output, contains('Largest folders'));
    expect(result.output, contains('Largest files'));
    expect(result.output, contains(r'installer.iso'));
    expect(result.output, contains('owner=User Downloads'));
    expect(result.output, contains('REVIEW: Large size alone'));
    expect(result.output, contains('Rule-backed cleanup candidates'));
    expect(result.output, contains('category=Browser caches (browser_cache)'));
    expect(result.output, contains('owner=Google Chrome'));
    expect(result.output, contains('CLEAN:'));
    expect(result.output, contains('not JSON'));
  });

  test('cached scan advice identifies stale data and asks for a refresh',
      () async {
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      sizeBytes: 1024,
      fileCount: 1,
    );
    service.publishCleanerScanContext(
      ownerTabId: tabId,
      root: root,
      isCached: true,
    );

    final result = await ToolExecutor(ownerTabId: tabId).execute(
      const ToolCall(
        name: 'get_current_cleaner_scan',
        arguments: <String, dynamic>{},
      ),
    );

    expect(result.output, contains('PREVIOUS CACHED CLEANER SCAN'));
    expect(result.output, contains('previous cached result'));
    expect(result.output, contains('this is not a current scan'));
    expect(result.output, contains('Use Scan again to refresh'));
    expect(result.output, isNot(contains('CURRENT CLEANER SCAN')));
  });

  test('cleaner skill keeps recommendation requests read-only', () {
    expect(
      DiskCleanerSkill.skillBlock,
      contains('NEVER call clean_disk_junk for those requests'),
    );
    expect(DiskCleanerSkill.skillBlock, contains('Do not echo tool JSON'));
    expect(
      DiskCleanerSkill.skillBlock,
      contains('Being large alone is never evidence that deletion is safe'),
    );
  });
}
