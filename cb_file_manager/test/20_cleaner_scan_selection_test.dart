import 'dart:convert';

import 'package:cb_file_manager/services/ai/agent_tool_catalog.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tabId = 'cleaner-selection-test';
  final service = DiskCleanerService.instance;
  late DiskTreeNode root;
  late DiskTreeNode cache;
  late DiskTreeNode largeFile;
  late List<DiskTreeNode> selected;
  var callbacks = 0;

  void publish({
    bool cached = false,
    bool scanning = false,
    bool available = true,
  }) {
    service.publishCleanerScanContext(
      ownerTabId: tabId,
      root: root,
      isCached: cached,
      isScanning: scanning,
      selectTargets: available
          ? (nodes, replace) {
              callbacks++;
              selected = [if (!replace) ...selected, ...nodes];
              return selected;
            }
          : null,
    );
  }

  Future<ToolResult> select(
    List<String> paths, {
    String? owner = tabId,
    String? scanId,
    bool replace = true,
  }) {
    return ToolExecutor(ownerTabId: owner).execute(
      ToolCall(
        name: 'select_cleaner_scan_items',
        arguments: {
          'scan_id':
              scanId ??
              service.getCleanerScanContext(ownerTabId: tabId)!.scanId,
          'paths': paths,
          'replace': replace,
        },
      ),
    );
  }

  setUp(() {
    cache = DiskTreeNode(
      name: 'Cache',
      fullPath: r'C:\Cache',
      sizeBytes: 1024,
      junkCategoryId: 'browser_cache',
    );
    largeFile = DiskTreeNode(
      name: 'large.iso',
      fullPath: r'C:\Downloads\large.iso',
      isFile: true,
      sizeBytes: 4096,
    );
    root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      children: [cache, largeFile],
    );
    selected = [];
    callbacks = 0;
    publish();
  });

  tearDown(() => service.clearCleanerScanContext(tabId));

  test(
    'tool is discoverable and selection does not request deletion approval',
    () {
      expect(
        AgentToolCatalog.definitions,
        contains('select_cleaner_scan_items'),
      );
      expect(
        AgentToolCatalog.approvalTools,
        isNot(contains('select_cleaner_scan_items')),
      );
      expect(AgentToolCatalog.approvalTools, contains('clean_disk_junk'));
    },
  );

  test(
    'read exposes the selection token and select reports actual checked targets',
    () async {
      final read = await ToolExecutor(ownerTabId: tabId).execute(
        const ToolCall(name: 'get_current_cleaner_scan', arguments: {}),
      );
      expect(
        read.output,
        contains(
          'scan_id: ${service.getCleanerScanContext(ownerTabId: tabId)!.scanId}',
        ),
      );
      expect(read.output, contains('Selection available: true'));
      final result = await select([r'c:/cache/', cache.fullPath]);
      expect(result.success, isTrue);
      expect(selected, [cache]);
      final data = jsonDecode(result.output) as Map<String, dynamic>;
      expect(data['selected_paths'], [cache.fullPath]);
      expect(data['selected_bytes'], 1024);
      expect(data['message'], contains('No files deleted'));
    },
  );

  test(
    'replace defaults to exact recommendations and add preserves prior selection',
    () async {
      selected = [largeFile];
      expect((await select([cache.fullPath])).success, isTrue);
      expect(selected, [cache]);
      expect(
        (await select([largeFile.fullPath], replace: false)).success,
        isTrue,
      );
      expect(selected, [cache, largeFile]);
    },
  );

  test(
    'one invented path rejects the whole selection without changing checked items',
    () async {
      selected = [largeFile];
      final result = await select([cache.fullPath, r'C:\invented.tmp']);
      expect(result.success, isFalse);
      expect(result.output, contains('invented.tmp'));
      expect(callbacks, 0);
      expect(selected, [largeFile]);
    },
  );

  test(
    'selection never falls back to another tab or accepts an old scan token',
    () async {
      final oldId = service.getCleanerScanContext(ownerTabId: tabId)!.scanId;
      expect((await select([cache.fullPath], owner: null)).success, isFalse);
      expect(
        (await select([cache.fullPath], owner: 'other-tab')).success,
        isFalse,
      );
      publish();
      expect((await select([cache.fullPath], scanId: oldId)).success, isFalse);
      expect(callbacks, 0);
    },
  );

  test(
    'cached, scanning, unavailable and disposed results reject selection',
    () async {
      publish(cached: true);
      expect((await select([cache.fullPath])).success, isFalse);
      publish(scanning: true);
      expect((await select([cache.fullPath])).success, isFalse);
      publish(available: false);
      expect((await select([cache.fullPath])).success, isFalse);
      final scanId = service.getCleanerScanContext(ownerTabId: tabId)!.scanId;
      service.clearCleanerScanContext(tabId);
      expect((await select([cache.fullPath], scanId: scanId)).success, isFalse);
      expect(callbacks, 0);
    },
  );

  test(
    'drive roots, aggregate rows and malformed requests cannot be selected',
    () async {
      root.addChild(DiskTreeNode(name: 'Other drive', fullPath: r'D:\'));
      root.addChild(
        DiskTreeNode(
          name: 'Other files',
          fullPath: '',
          aggregatedItemCount: 20,
        ),
      );
      for (final paths in [
        [root.fullPath],
        [r'D:\'],
        [''],
        <String>[],
        List.filled(101, cache.fullPath),
      ]) {
        expect((await select(paths)).success, isFalse);
      }
      expect(callbacks, 0);
      final invalid = await ToolExecutor(ownerTabId: tabId).execute(
        const ToolCall(
          name: 'select_cleaner_scan_items',
          arguments: {'paths': 12},
        ),
      );
      expect(invalid.success, isFalse);
    },
  );
}
