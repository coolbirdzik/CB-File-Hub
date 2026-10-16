import 'dart:convert';

import 'package:cb_file_manager/services/ai/agent_tool_catalog.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/services/ai/cleaner_review_run.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_agent_review.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tabId = 'interactive-review-test';
  final cleaner = DiskCleanerService.instance;
  late DiskTreeNode junk;
  late DiskTreeNode personal;
  late DiskTreeNode root;
  var callbacks = 0;
  var accepted = true;

  void publish({bool cached = false, bool scanning = false}) {
    cleaner.publishCleanerScanContext(
      ownerTabId: tabId,
      root: root,
      isCached: cached,
      isScanning: scanning,
      reviewItem: (node, analysis) {
        if (!accepted) return false;
        callbacks++;
        if (analysis != null) {
          node.isSelectedForDeletion = analysis.selectForCleanup;
        }
        publish(); // The real UI republishes after each interaction too.
        return true;
      },
    );
  }

  String getId() => cleaner.getCleanerScanContext(ownerTabId: tabId)!.scanId;
  Future<ToolResult> inspect(
    DiskTreeNode node, {
    String? scanId,
    String? owner = tabId,
  }) => ToolExecutor(ownerTabId: owner).execute(
    ToolCall(
      name: 'inspect_cleaner_scan_item',
      arguments: {'scan_id': scanId ?? getId(), 'path': node.fullPath},
    ),
  );
  Future<ToolResult> assess(
    DiskTreeNode node, {
    String decision = 'CLEAN',
    bool select = true,
    String reason = 'Cache can be recreated.',
  }) => ToolExecutor(ownerTabId: tabId).execute(
    ToolCall(
      name: 'set_cleaner_scan_item_analysis',
      arguments: {
        'scan_id': getId(),
        'path': node.fullPath,
        'decision': decision,
        'reason': reason,
        'select': select,
      },
    ),
  );

  setUp(() {
    callbacks = 0;
    accepted = true;
    junk = DiskTreeNode(
      name: 'cache.bin',
      fullPath: r'C:\Cache\cache.bin',
      isFile: true,
      sizeBytes: 1024,
      junkCategoryId: 'browser_cache',
    );
    personal = DiskTreeNode(
      name: 'personal.iso',
      fullPath: r'C:\Downloads\personal.iso',
      isFile: true,
      sizeBytes: 4096,
    );
    root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      children: [junk, personal],
    );
    publish();
  });
  tearDown(() => cleaner.clearCleanerScanContext(tabId));

  test(
    'full review counts accepted verdicts, not inspection or rejected calls',
    () async {
      final run = CleanerReviewRun(tabId);
      await run.review.prepareGroups(checkActive: () {});
      expect(run.review.total, 2);
      expect(run.review.next, junk);
      await inspect(junk);
      expect(run.review.reviewed, 0);
      accepted = false;
      expect((await assess(junk)).success, isFalse);
      expect(run.review.reviewed, 0);
      accepted = true;
      await assess(junk);
      await assess(junk);
      expect(run.review.reviewed, 1);
      expect(run.review.next, personal);
      expect(run.requireActiveContext().root, same(root));
      publish(scanning: true);
      expect(run.requireActiveContext, throwsStateError);
    },
  );

  test('full review retains descendants and reports aggregates separately', () {
    final folder = DiskTreeNode(
      name: 'folder',
      fullPath: r'C:\folder',
      children: [
        personal,
        DiskTreeNode(name: 'Others', fullPath: '', aggregatedItemCount: 500),
      ],
    );
    final review = CleanerFullReview(
      DiskTreeNode(name: 'C:', fullPath: r'C:\', children: [folder, junk]),
    );
    expect(review.total, 3);
    expect(review.aggregatedItems, 500);
    review.markReviewed(folder);
    expect(review.remaining, 2);
    expect(review.next, personal);
    review.markReviewed(personal);
    review.markReviewed(junk);
    expect(review.isComplete, isTrue);
  });

  test('new roots and closed tabs invalidate full review runs', () {
    final run = CleanerReviewRun(tabId);
    root = DiskTreeNode(name: 'C:', fullPath: r'C:\', children: [junk]);
    publish();
    expect(run.requireActiveContext, throwsStateError);
    final nextRun = CleanerReviewRun(tabId);
    cleaner.clearCleanerScanContext(tabId);
    expect(nextRun.requireActiveContext, throwsStateError);
  });

  test(
    'inspection reports actual evidence and the fresh ID before visible assessment',
    () async {
      final oldId = getId();
      final result = await inspect(junk);
      expect(result.success, isTrue);
      final data = jsonDecode(result.output) as Map<String, dynamic>;
      expect(data['path'], junk.fullPath);
      expect(data['evidence'], contains('Browser caches'));
      expect(data['selected_for_cleanup'], isFalse);
      expect(data['scan_id'], getId());
      expect(data['scan_id'], isNot(oldId));
      final assessment = await assess(junk);
      expect(assessment.success, isTrue);
      expect(jsonDecode(assessment.output)['selected_for_cleanup'], isTrue);
      expect(callbacks, 2);
      expect(
        AgentToolCatalog.approvalTools,
        isNot(contains('set_cleaner_scan_item_analysis')),
      );
    },
  );

  test(
    'assessments require inspection of the exact item and a concrete reason',
    () async {
      expect((await assess(junk)).success, isFalse);
      expect((await inspect(junk)).success, isTrue);
      expect(
        (await assess(personal, decision: 'KEEP', select: false)).success,
        isFalse,
      );
      expect((await assess(junk, decision: 'unknown')).success, isFalse);
      expect((await assess(junk, reason: ' ')).success, isFalse);
      expect((await assess(junk, reason: 'x' * 2001)).success, isFalse);
      expect(callbacks, 1);
      expect(junk.isSelectedForDeletion, isFalse);
    },
  );

  test(
    'personal files cannot be labelled CLEAN or auto-checked as REVIEW/KEEP',
    () async {
      expect((await inspect(personal)).success, isTrue);
      expect((await assess(personal)).success, isFalse);
      expect((await assess(personal, decision: 'REVIEW')).success, isFalse);
      expect((await assess(personal, decision: 'KEEP')).success, isFalse);
      expect(
        (await assess(
          personal,
          decision: 'KEEP',
          select: false,
          reason: 'Personal data; size alone is not a reason to delete.',
        )).success,
        isTrue,
      );
      expect(personal.isSelectedForDeletion, isFalse);
    },
  );

  test(
    'stale, cached, scanning, cross-tab and rejected UI interactions fail without selection',
    () async {
      final stale = getId();
      publish();
      expect((await inspect(junk, scanId: stale)).success, isFalse);
      expect((await inspect(junk, owner: 'other-tab')).success, isFalse);
      expect((await inspect(junk, owner: null)).success, isFalse);
      publish(cached: true);
      expect((await inspect(junk)).success, isFalse);
      publish(scanning: true);
      expect((await inspect(junk)).success, isFalse);
      publish();
      accepted = false;
      expect((await inspect(junk)).success, isFalse);
      expect(callbacks, 0);
    },
  );

  test(
    'changing roots invalidates prior inspection even if the same path exists',
    () async {
      expect((await inspect(junk)).success, isTrue);
      root = DiskTreeNode(name: r'C:\', fullPath: r'C:\', children: [junk]);
      publish();
      expect((await assess(junk)).success, isFalse);
    },
  );

  test(
    'drive roots, invented paths and stopped turns never reach the UI',
    () async {
      expect((await inspect(root)).success, isFalse);
      expect(
        (await inspect(
          DiskTreeNode(name: 'missing', fullPath: r'C:\missing.bin'),
        )).success,
        isFalse,
      );
      final executor = ToolExecutor(ownerTabId: tabId)
        ..beginTurn(currentPath: '#cb-agent-cleaner', isCancelled: () => true);
      final result = await executor.execute(
        ToolCall(
          name: 'inspect_cleaner_scan_item',
          arguments: {'scan_id': getId(), 'path': junk.fullPath},
        ),
      );
      expect(result.success, isFalse);
      expect(callbacks, 0);
    },
  );
}
