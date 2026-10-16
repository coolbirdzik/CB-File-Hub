import 'package:cb_file_manager/services/disk_cleaner/cleaner_agent_review.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_review_summary.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mb = 1024 * 1024;

  test(
    'file totals exclude overlapping folders and size-only entries',
    () async {
      final cache = DiskTreeNode(
        name: 'cache.tmp',
        fullPath: r'C:\Temp\cache.tmp',
        isFile: true,
        sizeBytes: 20 * mb,
        junkCategoryId: 'windows_temp',
      );
      final personal = DiskTreeNode(
        name: 'family.mp4',
        fullPath: r'C:\Data\family.mp4',
        isFile: true,
        sizeBytes: 100 * mb,
      );
      final kept = DiskTreeNode(
        name: 'pagefile.sys',
        fullPath: r'C:\pagefile.sys',
        isFile: true,
        sizeBytes: 50 * mb,
      );
      final review = CleanerFullReview(
        DiskTreeNode(
          name: 'C:',
          fullPath: r'C:\',
          sizeBytes: 500 * mb,
          children: [
            DiskTreeNode(
              name: 'Temp',
              fullPath: r'C:\Temp',
              sizeBytes: 320 * mb,
              children: [
                cache,
                DiskTreeNode(
                  name: 'roll-up',
                  fullPath: '',
                  isFile: true,
                  sizeBytes: 300 * mb,
                  aggregatedItemCount: 2000,
                ),
              ],
            ),
            DiskTreeNode(
              name: 'Data',
              fullPath: r'C:\Data',
              sizeBytes: 100 * mb,
              children: [personal],
            ),
            kept,
          ],
        ),
      );
      await review.prepareGroups(checkActive: () {});
      for (final group in review.groups) {
        review.markGroupReviewed(
          group,
          CleanerItemAnalysis(
            decision: group.canClean
                ? CleanerItemDecision.clean
                : group.cause?.verdict == 'KEEP'
                ? CleanerItemDecision.keep
                : CleanerItemDecision.review,
            reason: group.canClean
                ? 'Temporary cache; check before removing.'
                : 'Confirm ownership before making changes.',
            fromScan: true,
          ),
        );
      }
      final report = CleanerReviewSummary(review);
      expect(report.sections.take(3).map((s) => s.fileBytes), [
        20 * mb,
        100 * mb,
        50 * mb,
      ]);
      expect(report.sections.last.folderTotals, isTrue);
      expect(
        report.toText(),
        contains('Consider cleaning: 1 groups · 20.0 MB'),
      );
      expect(report.toText(), contains('C:\\Temp · 320.0 MB (folder total)'));
      expect(report.toText(), contains(personal.fullPath));
      expect(report.toText(), contains('Next: review the cleaning candidates'));
      expect(review.aggregatedItems, 2000);
      expect(
        [cache, personal, kept].every((n) => !n.isSelectedForDeletion),
        isTrue,
      );
    },
  );

  test(
    'largest priorities are bounded and unsafe or failed CLEAN is review',
    () {
      final review = CleanerFullReview(
        DiskTreeNode(name: 'C:', fullPath: r'C:\'),
      );
      for (var i = 0; i < 8; i++) {
        final group =
            CleanerReviewGroup(
                id: 'g$i',
                scope: r'C:\Data',
                categoryId: null,
                cause: null,
                type: 'other_files',
              )
              ..add(
                DiskTreeNode(
                  name: '$i.bin',
                  fullPath: 'C:\\Data\\$i.bin',
                  isFile: true,
                  sizeBytes: (i + 1) * mb,
                ),
              )
              ..analysis = const CleanerItemAnalysis(
                decision: CleanerItemDecision.clean,
                reason: 'Unsupported CLEAN.',
              );
        review.groups.add(group);
      }
      final failed =
          CleanerReviewGroup(
              id: 'failed',
              scope: r'C:\Temp',
              categoryId: 'windows_temp',
              cause: null,
              type: 'other_files',
            )
            ..add(
              DiskTreeNode(
                name: 'failed.tmp',
                fullPath: r'C:\Temp\failed.tmp',
                isFile: true,
                sizeBytes: 10 * mb,
              ),
            )
            ..analysis = const CleanerItemAnalysis(
              decision: CleanerItemDecision.clean,
              reason: 'Failed assessment.',
            )
            ..usedFallback = true;
      review.groups.add(failed);
      final report = CleanerReviewSummary(review, languageCode: 'vi');
      expect(report.sections.first.fileBytes, 0);
      expect(report.sections[1].groups.length, 9);
      expect(report.sections[1].highlights.map((g) => g.id), [
        'failed',
        'g7',
        'g6',
      ]);
      expect(report.toText(), contains('Tóm tắt những phần cần chú ý'));
      expect(report.toText(), contains('Còn 6 nhóm trong bảng kết quả.'));
      expect(report.toText(), contains('chưa có nhóm file đủ điều kiện'));
      expect(report.toText(), isNot(contains('C:\\Data\\0.bin')));
    },
  );

  test('folder examples do not repeat ancestor and descendant paths', () {
    final review = CleanerFullReview(
      DiskTreeNode(name: 'C:', fullPath: r'C:\'),
    );
    for (final path in [r'C:\Data', r'C:\Data\Child', r'C:\Other']) {
      review.groups.add(
        CleanerReviewGroup(
          id: path,
          scope: path,
          categoryId: null,
          cause: null,
          type: 'folder',
        )..add(
          DiskTreeNode(
            name: path,
            fullPath: path,
            sizeBytes: path == r'C:\Data' ? 100 * mb : 50 * mb,
          ),
        ),
      );
    }
    final folders = CleanerReviewSummary(review).sections.last;
    expect(folders.groups.map((g) => g.scope), [r'C:\Data', r'C:\Other']);
    expect(folders.fileBytes, 0);
  });
}
