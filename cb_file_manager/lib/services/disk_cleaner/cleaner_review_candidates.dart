import 'cleaner_models.dart';
import 'cleaner_paths.dart';
import 'cleaner_categories.dart';

/// Read-only filesystem evidence. This type is deliberately not a JunkItem.
class CleanerFileReviewCandidate {
  final String path;
  final int sizeBytes;
  final DateTime lastModified;
  final String categoryId;
  final bool isDirectory;

  const CleanerFileReviewCandidate({
    required this.path,
    required this.sizeBytes,
    required this.lastModified,
    this.categoryId = CleanerReviewCandidates.categoryId,
    this.isDirectory = false,
  });
}

abstract final class CleanerReviewCandidates {
  static const categoryId = 'old_downloads_review';
  static const minAge = Duration(days: 90);
  static const limit = 200;

  static CleanerCategory category({required bool isMacOS}) => CleanerCategory(
    id: categoryId,
    displayName: 'Old downloads (review only)',
    description:
        'Up to 200 large files in the default Downloads folder unchanged for at least 90 days. Last modified is not last opened and does not prove a file is unused. Inspection only; these files are never selected for cleanup.',
    safety: CleanerSafety.careful,
    reviewOnly: true,
    rules: [
      CleanerPathRule(
        source: PathSource.env(isMacOS ? 'HOME' : 'USERPROFILE', 'Downloads'),
        minAge: minAge,
      ),
    ],
  );

  static List<CleanerFileReviewCandidate> select(
    ScanReport report,
    DateTime now,
  ) {
    final seen = <String>{};
    final items =
        (report.itemsByCategory[categoryId] ?? const <JunkItem>[])
            .where(
              (item) =>
                  !item.isContainerOnly &&
                  !item.isRecycleBinItem &&
                  !item.isUserSelected &&
                  item.lastModified != null &&
                  now.difference(item.lastModified!) >= minAge &&
                  seen.add(CleanerPaths.key(item.path)),
            )
            .toList()
          ..sort((a, b) {
            final bySize = b.sizeBytes.compareTo(a.sizeBytes);
            return bySize != 0 ? bySize : a.path.compareTo(b.path);
          });
    return [
      for (final item in items.take(limit))
        CleanerFileReviewCandidate(
          path: item.path,
          sizeBytes: item.sizeBytes,
          lastModified: item.lastModified!,
        ),
      for (final category in CleanerCategories.all())
        if (category.reviewOnly && category.id != categoryId)
          ..._selectCategory(report, category.id),
    ];
  }

  static List<CleanerFileReviewCandidate> _selectCategory(
    ScanReport report,
    String id,
  ) {
    final seen = <String>{};
    final items =
        (report.itemsByCategory[id] ?? const <JunkItem>[])
            .where(
              (item) =>
                  !item.isRecycleBinItem &&
                  !item.isUserSelected &&
                  seen.add(CleanerPaths.key(item.path)),
            )
            .toList()
          ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return [
      for (final item in items.take(limit))
        CleanerFileReviewCandidate(
          path: item.path,
          sizeBytes: item.sizeBytes,
          lastModified: item.lastModified ?? report.scannedAt,
          categoryId: id,
          isDirectory: item.isContainerOnly,
        ),
    ];
  }
}
