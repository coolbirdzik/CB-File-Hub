import 'dart:async';
import 'dart:convert';
import 'package:cb_file_manager/services/ai/cleaner_review_run.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_agent_review.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = 'group-review-test';
  final service = DiskCleanerService.instance;
  late DiskTreeNode safe;
  late DiskTreeNode personal;
  late DiskTreeNode root;
  var accepted = true;
  var focusCalls = 0;
  void publish() => service.publishCleanerScanContext(
    ownerTabId: owner,
    root: root,
    reviewItem: (_, _) {
      focusCalls++;
      publish();
      return true;
    },
    reviewGroup: (group, analysis) {
      if (!accepted) return false;
      for (final node in group.nodes) {
        node.isSelectedForDeletion = analysis.selectForCleanup;
      }
      publish();
      return true;
    },
  );
  setUp(() {
    accepted = true;
    focusCalls = 0;
    safe = DiskTreeNode(
      name: 'cache.tmp',
      fullPath: r'C:\Temp\cache.tmp',
      isFile: true,
      sizeBytes: 100,
      junkCategoryId: 'windows_temp',
    );
    personal = DiskTreeNode(
      name: 'photo.jpg',
      fullPath: r'C:\Data\photo.jpg',
      isFile: true,
      sizeBytes: 1000,
    );
    root = DiskTreeNode(
      name: 'C:',
      fullPath: r'C:\',
      children: [safe, personal],
    );
    publish();
  });
  tearDown(() => service.clearCleanerScanContext(owner));

  test(
    'batch verification focuses once and authorizes only its exact queued groups',
    () async {
      final run = CleanerReviewRun(owner);
      await run.review.prepareGroups(checkActive: () {});
      final groups = run.review.groups;
      expect(
        () => service.inspectFullReviewGroups(
          ownerTabId: 'other',
          review: run.review,
          groups: groups,
        ),
        throwsStateError,
      );
      final invented = CleanerReviewGroup(
        id: groups.first.id,
        scope: 'C:',
        categoryId: 'windows_temp',
        cause: null,
        type: 'other_files',
      )..add(safe);
      expect(
        () => service.inspectFullReviewGroups(
          ownerTabId: owner,
          review: run.review,
          groups: [invented],
        ),
        throwsStateError,
      );
      expect(focusCalls, 0);
      service.inspectFullReviewGroups(
        ownerTabId: owner,
        review: run.review,
        groups: groups,
      );
      expect(focusCalls, 1);
      for (final group in groups) {
        service.applyFullReviewGroup(
          ownerTabId: owner,
          review: run.review,
          group: group,
          analysis: const CleanerItemAnalysis(
            decision: CleanerItemDecision.keep,
            reason: 'Keep these files.',
          ),
        );
      }
      expect(run.review.isComplete, isTrue);
      service.clearCleanerScanContext(owner);
      expect(
        () => service.applyFullReviewGroup(
          ownerTabId: owner,
          review: run.review,
          group: groups.first,
          analysis: const CleanerItemAnalysis(
            decision: CleanerItemDecision.clean,
            reason: 'Cache',
            selectForCleanup: true,
          ),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'batch parser keeps valid partial answers but rejects duplicate or unsafe verdicts',
    () async {
      final run = CleanerReviewRun(owner);
      await run.review.prepareGroups(checkActive: () {});
      final groups = run.review.groups;
      final response = jsonEncode({
        'assessments': [
          {
            'group_id': groups.first.id,
            'decision': 'CLEAN',
            'reason': 'Scanner-confirmed junk.',
          },
          {
            'group_id': groups.first.id,
            'decision': 'KEEP',
            'reason': 'Duplicate conflict.',
          },
          {
            'group_id': groups.last.id,
            'decision': 'CLEAN',
            'reason': 'Large photo.',
          },
          {
            'group_id': 'invented',
            'decision': 'CLEAN',
            'reason': 'Not in request.',
          },
        ],
      });
      expect(run.parseBatchAssessments(response, groups), isEmpty);
      final partial = run.parseBatchAssessments(
        jsonEncode({
          'assessments': [
            {
              'group_id': groups.last.id,
              'decision': 'KEEP',
              'reason': 'Personal image.',
            },
          ],
        }),
        groups,
      );
      expect(partial.keys, [groups.last.id]);
      expect(partial.values.single.selectForCleanup, isFalse);
    },
  );

  test(
    'group verdicts require inspected evidence and an accepted UI callback',
    () async {
      final run = CleanerReviewRun(owner);
      await run.review.prepareGroups(checkActive: () {});
      final group = run.review.groups.first;
      const analysis = CleanerItemAnalysis(
        decision: CleanerItemDecision.clean,
        reason: 'Scanner-confirmed temporary files.',
        selectForCleanup: true,
      );
      void apply() => service.applyFullReviewGroup(
        ownerTabId: owner,
        review: run.review,
        group: group,
        analysis: analysis,
      );
      expect(apply, throwsStateError);
      final inspection = await ToolExecutor(ownerTabId: owner).execute(
        ToolCall(
          name: 'inspect_cleaner_scan_item',
          arguments: {
            'scan_id': run.requireActiveContext().scanId,
            'path': group.representative.fullPath,
          },
        ),
      );
      expect(inspection.success, isTrue);
      accepted = false;
      expect(apply, throwsStateError);
      expect(group.analysis, isNull);
      expect(run.review.reviewed, 0);
      accepted = true;
      apply();
      expect(run.review.reviewed, 1);
      expect(run.review.analysisForPath(safe.fullPath), same(analysis));
      expect(safe.isSelectedForDeletion, isTrue);
      expect(personal.isSelectedForDeletion, isFalse);
    },
  );

  test(
    'parser recovers arrays and completed entries in truncated JSON',
    () async {
      final run = CleanerReviewRun(owner);
      await run.review.prepareGroups(checkActive: () {});
      final groups = run.review.groups;
      final entries = [
        for (final group in groups)
          {
            'group_id': group.id,
            'decision': 'KEEP',
            'reason': 'Keep "{user}" data.',
          },
      ];
      expect(run.parseBatchAssessments(jsonEncode(entries), groups).length, 2);
      final truncated =
          '{"assessments":[${jsonEncode(entries.first)}, {"group_id":';
      final recovered = run.parseBatchAssessments(truncated, groups);
      expect(recovered.keys, [groups.first.id]);
      expect(recovered.values.single.reason, 'Keep "{user}" data.');
      final echoed =
          '${jsonEncode(groups.map((g) => g.evidence).toList())}\n'
          '${jsonEncode({'assessments': entries})}';
      expect(run.parseBatchAssessments(echoed, groups).length, 2);
    },
  );

  test(
    'failed groups stay pending and Retry retains successful assessments',
    () async {
      final run = CleanerReviewRun(owner);
      await run.review.prepareGroups(checkActive: () {});
      final groups = run.review.groups;
      service.inspectFullReviewGroups(
        ownerTabId: owner,
        review: run.review,
        groups: groups,
      );
      const kept = CleanerItemAnalysis(
        decision: CleanerItemDecision.keep,
        reason: 'User data.',
      );
      service.applyFullReviewGroup(
        ownerTabId: owner,
        review: run.review,
        group: groups.first,
        analysis: kept,
      );
      service.applyFullReviewGroup(
        ownerTabId: owner,
        review: run.review,
        group: groups.last,
        analysis: run.fallbackFor(groups.last),
        fallback: true,
      );
      expect(run.review.reviewed, 1);
      expect(run.review.unresolvedItems, 1);
      expect(run.review.isComplete, isFalse);
      expect(run.summary(), contains('Quick overview incomplete'));
      final retry = CleanerReviewRun(owner);
      expect(retry.review, same(run.review));
      expect(retry.batches().single, [groups.last]);
      service.applyFullReviewGroup(
        ownerTabId: owner,
        review: run.review,
        group: groups.last,
        analysis: kept,
      );
      expect(run.review.isComplete, isTrue);
      expect(run.review.unresolvedItems, 0);
      expect(groups.last.usedFallback, isFalse);
    },
  );

  test('legacy fallback counters reopen only failed groups', () async {
    final run = CleanerReviewRun(owner);
    await run.review.prepareGroups(checkActive: () {});
    final groups = run.review.groups;
    run.review.markGroupReviewed(
      groups.first,
      const CleanerItemAnalysis(
        decision: CleanerItemDecision.keep,
        reason: 'User data.',
      ),
    );
    for (final node in groups.last.nodes) {
      run.review.markReviewed(node);
    }
    groups.last.analysis = run.fallbackFor(groups.last);
    groups.last.usedFallback = true;
    expect(run.review.isComplete, isTrue);
    expect(service.beginFullCleanerReview(owner), same(run.review));
    expect(run.review.reviewed, 1);
    expect(run.review.pendingNodeForPath(personal.fullPath), same(personal));
    expect(groups.first.analysis, isNotNull);
    // Individually accepted work must not be reopened on subsequent retries.
    run.review.markReviewed(personal);
    run.review.reconcileFallbacks();
    expect(run.review.isComplete, isTrue);
  });

  test(
    'summary distinguishes retained entries, roll-ups and coverage reasons',
    () async {
      root.addChild(
        DiskTreeNode(
          name: 'roll-up',
          fullPath: '',
          aggregatedItemCount: 2361514,
        ),
      );
      service.publishCleanerScanContext(
        ownerTabId: owner,
        root: root,
        reviewItem: (_, _) => true,
        reviewGroup: (_, _) => true,
        coverageIssues: [
          for (final reason in FullDiskScanCoverageIssueReason.values)
            FullDiskScanCoverageIssue(
              path: 'C:\\unassessed\\${reason.name}',
              reason: reason,
            ),
        ],
      );
      final run = CleanerReviewRun(owner);
      await run.review.prepareGroups(checkActive: () {});
      for (final group in run.review.groups) {
        run.review.markGroupReviewed(
          group,
          const CleanerItemAnalysis(
            decision: CleanerItemDecision.keep,
            reason: 'User data.',
          ),
        );
      }
      final summary = run.summary();
      expect(summary, contains('Quick overview ready'));
      expect(summary, contains('2 with AI recommendations'));
      expect(summary, contains('What needs attention'));
      expect(summary, contains('Keep: 2 groups'));
      expect(summary, contains(personal.fullPath));
      expect(summary, contains('User data.'));
      expect(summary, contains('Next: keep the identified data'));
      expect(summary, contains('2361514 entries have size totals only'));
      expect(summary, contains('1 unreadable paths'));
      expect(summary, contains('1 paths at the scan depth limit'));
      expect(summary, contains('1 reparse points intentionally skipped'));
      expect(summary, contains('Preliminary advice based on scan metadata'));
      expect(
        CleanerReviewRun(owner, languageCode: 'vi').summary(),
        contains('đường dẫn không đọc được'),
      );
    },
  );

  test(
    'invalid, mismatched and unsafe model assessments cannot select personal data',
    () async {
      final run = CleanerReviewRun(owner, languageCode: 'vi');
      await run.review.prepareGroups(checkActive: () {});
      final group = run.review.groups.last;
      String reply(String decision, {String? id, Object reason = 'Evidence'}) =>
          jsonEncode({
            'group_id': id ?? group.id,
            'decision': decision,
            'reason': reason,
          });
      expect(run.parseAssessment(reply('CLEAN'), group), isNull);
      expect(run.parseAssessment(reply('KEEP', id: 'invented'), group), isNull);
      expect(run.parseAssessment(reply('KEEP', reason: 12), group), isNull);
      expect(
        run.parseAssessment(reply('KEEP', reason: 'x' * 2001), group),
        isNull,
      );
      expect(run.parseAssessment('I will inspect this next.', group), isNull);
      final kept = run.parseAssessment(
        '<think>reasoning</think>```json\n${reply('keep')}\n```',
        group,
      )!;
      expect(kept.decision, CleanerItemDecision.keep);
      expect(kept.selectForCleanup, isFalse);
      expect(run.fallbackFor(group).reason, contains('AI không trả được'));
      expect(run.fallbackFor(group).selectForCleanup, isFalse);
    },
  );

  test(
    'quick recommendations identify safe data without selecting it',
    () async {
      final run = CleanerReviewRun(owner);
      await run.review.prepareGroups(checkActive: () {});
      final group = run.review.groups.first;
      final local = run.scanAssessmentFor(group);
      expect(local.decision, CleanerItemDecision.clean);
      expect(local.fromScan, isTrue);
      expect(local.selectForCleanup, isFalse);
      expect(local.reason, contains('Windows temporary files'));
      final model = run.parseAssessment(
        jsonEncode({
          'group_id': group.id,
          'decision': 'CLEAN',
          'reason': 'Temporary files.',
        }),
        group,
      )!;
      expect(model.decision, CleanerItemDecision.clean);
      expect(model.selectForCleanup, isFalse);
      expect(model.fromScan, isFalse);
    },
  );

  test(
    'all descendants are grouped while owners, categories and types stay separate',
    () async {
      final mixedFolder = DiskTreeNode(
        name: 'mixed',
        fullPath: r'C:\mixed',
        junkCategoryId: 'windows_temp',
        sizeBytes: 1100,
        children: [safe, personal],
      );
      final cloudFile = DiskTreeNode(
        name: 'cloud.tmp',
        fullPath: r'C:\Users\Tester\OneDrive\cloud.tmp',
        isFile: true,
        junkCategoryId: 'windows_temp',
      );
      final cloud = DiskTreeNode(
        name: 'OneDrive',
        fullPath: r'C:\Users\Tester\OneDrive',
        children: [cloudFile],
      );
      final review = CleanerFullReview(
        DiskTreeNode(
          name: 'C:',
          fullPath: r'C:\',
          children: [
            mixedFolder,
            cloud,
            DiskTreeNode(
              name: 'filler',
              fullPath: r'C:\filler',
              children: List.generate(
                256,
                (i) => DiskTreeNode(
                  name: '$i.bin',
                  fullPath: 'C:\\filler\\$i.bin',
                  isFile: true,
                ),
              ),
            ),
          ],
        ),
      );
      await review.prepareGroups(checkActive: () {});
      // Exceed the inline limit: worker results must still use the exact
      // original nodes and preserve inherited owners and cleanup safety.
      expect(review.groups.fold(0, (sum, g) => sum + g.nodes.length), 262);
      expect(review.groups.fold(0, (sum, g) => sum + g.fileBytes), 1100);
      expect(review.parentOf(safe), same(mixedFolder));
      expect(review.ancestorsOf(safe), [mixedFolder, review.root]);
      expect(
        review.groups.firstWhere((g) => g.nodes.contains(mixedFolder)).canClean,
        isFalse,
      );
      expect(
        review.groups.firstWhere((g) => g.nodes.contains(safe)).canClean,
        isTrue,
      );
      expect(
        review.groups.firstWhere((g) => g.nodes.contains(personal)).canClean,
        isFalse,
      );
      expect(
        review.groups.firstWhere((g) => g.nodes.contains(cloudFile)).canClean,
        isFalse,
      );
    },
  );

  test(
    'deferred review yields to Stop and can restart without partial indexes',
    () async {
      final nodes = List.generate(
        50000,
        (i) => DiskTreeNode(
          name: '$i.bin',
          fullPath: 'C:\\Data\\$i.bin',
          isFile: true,
        ),
      );
      final review = CleanerFullReview.deferred(
        DiskTreeNode(name: 'C:', fullPath: r'C:\', children: nodes),
      );
      expect(review.total, 0);
      expect(review.isComplete, isFalse);
      var stopped = false;
      final preparing = review.prepareGroups(
        checkActive: () {
          if (stopped) throw StateError('Stopped');
        },
      );
      Timer.run(() => stopped = true);
      await expectLater(preparing, throwsStateError);
      expect(review.groups, isEmpty);
      expect(review.isComplete, isFalse);
      expect(review.total, anyOf(0, nodes.length));
      expect(review.remaining, review.total);

      var ticks = 0;
      final heartbeat = Timer.periodic(Duration.zero, (_) => ticks++);
      try {
        await review.prepareGroups(checkActive: () {});
      } finally {
        heartbeat.cancel();
      }
      expect(ticks, greaterThan(1));
      expect(review.total, nodes.length);
      expect(review.remaining, nodes.length);
      expect(review.groups.single.nodes, nodes);
      expect(review.pendingNodeForPath(nodes.last.fullPath), same(nodes.last));
      expect(review.groupForPath(nodes.last.fullPath), review.groups.single);
      expect(review.ancestorsOf(review.groups.single.representative), [
        review.root,
      ]);
    },
  );

  test(
    'group preparation yields to cancellation without persisting partial groups',
    () async {
      final review = CleanerFullReview(
        DiskTreeNode(
          name: 'C:',
          fullPath: r'C:\',
          children: List.generate(
            10000,
            (i) => DiskTreeNode(
              name: '$i',
              fullPath: 'C:\\Data\\$i',
              isFile: true,
            ),
          ),
        ),
      );
      await expectLater(
        review.prepareGroups(checkActive: () => throw StateError('Stopped')),
        throwsStateError,
      );
      expect(review.groups, isEmpty);
      expect(review.remaining, 10000);
    },
  );
}
