import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_quick_clean.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_review_candidates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 26);
  JunkItem old(int index, {Duration age = const Duration(days: 100)}) =>
      JunkItem(
        path: '/Users/test/Downloads/file-$index.zip',
        sizeBytes: index,
        categoryId: CleanerReviewCandidates.categoryId,
        lastModified: now.subtract(age),
      );

  test('old downloads are bounded read-only evidence, not junk selection', () {
    final report = ScanReport(
      drivesScanned: const [],
      itemsByCategory: {
        CleanerReviewCandidates.categoryId: [
          for (var i = 0; i < 250; i++) old(i),
          old(249),
          old(999, age: const Duration(days: 30)),
          const JunkItem(
            path: '/Users/test/Downloads/unknown.zip',
            sizeBytes: 1000,
            categoryId: CleanerReviewCandidates.categoryId,
          ),
        ],
      },
      warnings: const [],
      scannedAt: now,
    );
    final candidates = CleanerReviewCandidates.select(report, now);
    expect(candidates, hasLength(200));
    expect(candidates.first.sizeBytes, 249);
    expect(candidates.last.sizeBytes, 50);
    expect(CleanerQuickClean.select(report, now: now).totalCount, 0);
    for (final isMacOS in [true, false]) {
      final category = CleanerReviewCandidates.category(isMacOS: isMacOS);
      expect(category.reviewOnly, isTrue);
      expect(category.defaultEnabled, isFalse);
    }
  });
}
