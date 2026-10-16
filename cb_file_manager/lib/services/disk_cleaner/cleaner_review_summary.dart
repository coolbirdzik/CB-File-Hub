import 'cleaner_agent_review.dart';

/// A bounded, actionable report derived from the accepted scan assessments.
/// File-group totals never include folder sizes or unnamed aggregate rows.
class CleanerReviewSummary {
  final CleanerFullReview review;
  final String languageCode;
  final List<CleanerReviewSummarySection> sections;

  CleanerReviewSummary(this.review, {this.languageCode = 'en'})
    : sections = [] {
    for (final decision in CleanerItemDecision.values) {
      final groups =
          review.groups
              .where(
                (group) => group.fileBytes > 0 && _decision(group) == decision,
              )
              .toList()
            ..sort(_largestFirst);
      sections.add(
        CleanerReviewSummarySection(
          title: switch (decision) {
            CleanerItemDecision.clean =>
              vi ? 'Có thể cân nhắc dọn' : 'Consider cleaning',
            CleanerItemDecision.review =>
              vi ? 'Ưu tiên xem lại' : 'Review first',
            CleanerItemDecision.keep => vi ? 'Nên giữ' : 'Keep',
          },
          groups: groups,
        ),
      );
    }
    // Folder totals also reveal space hidden in aggregate rows. Report exact
    // examples separately; never add them to file totals or deletion estimates.
    final folders =
        review.groups.where((group) => group.largestFolderBytes > 0).toList()
          ..sort(
            (a, b) => b.largestFolderBytes.compareTo(a.largestFolderBytes),
          );
    final distinct = <CleanerReviewGroup>[];
    for (final group in folders) {
      final path = _path(group);
      if (distinct.any((other) => _overlaps(path, _path(other)))) continue;
      distinct.add(group);
      if (distinct.length == 2) break;
    }
    if (distinct.isNotEmpty) {
      sections.add(
        CleanerReviewSummarySection(
          title: vi ? 'Thư mục lớn cần chú ý' : 'Large folders to inspect',
          groups: distinct,
          folderTotals: true,
        ),
      );
    }
  }

  bool get vi => languageCode == 'vi';
  String get title =>
      vi ? 'Tóm tắt những phần cần chú ý' : 'What needs attention';
  String get scopeNote => vi
      ? 'Dung lượng theo các file có trong kết quả; mục chỉ có tổng dung lượng chưa được tính vào gợi ý dọn. Dung lượng thư mục không cộng vào tổng file.'
      : 'Sizes use retained file rows; size-only entries are excluded from cleanup advice. Folder sizes are not added to file totals.';
  String get nextStep {
    if (sections.first.groups.isNotEmpty) {
      return vi
          ? 'Bước tiếp theo: xem các nhóm có thể dọn, chọn đúng mục không còn cần rồi kiểm tra danh sách trước khi xác nhận xóa.'
          : 'Next: review the cleaning candidates, select only items you no longer need, then check the target list before confirming deletion.';
    }
    if (sections[1].groups.isNotEmpty || sections.any((s) => s.folderTotals)) {
      return vi
          ? 'Bước tiếp theo: mở các mục ưu tiên xem lại hoặc thư mục lớn để xác nhận công dụng; chưa có nhóm file đủ điều kiện gợi ý dọn.'
          : 'Next: inspect the review priorities or large folders to confirm their purpose; no file groups currently qualify as cleaning candidates.';
    }
    return vi
        ? 'Bước tiếp theo: giữ các dữ liệu đã nhận diện; chưa có nhóm file đủ điều kiện gợi ý dọn.'
        : 'Next: keep the identified data; no file groups currently qualify as cleaning candidates.';
  }

  String sectionHeading(CleanerReviewSummarySection section) {
    if (section.folderTotals) return section.title;
    return '${section.title}: ${section.groups.length} ${vi ? 'nhóm' : 'groups'} · ${formatBytes(section.fileBytes)}';
  }

  String highlightLabel(
    CleanerReviewSummarySection section,
    CleanerReviewGroup group,
  ) => section.folderTotals
      ? '${group.representative.fullPath} · ${formatBytes(group.largestFolderBytes)} (${vi ? 'tổng thư mục' : 'folder total'})'
      : '${group.scope} · ${formatBytes(group.fileBytes)} · ${group.nodes.length} ${vi ? 'mục' : 'entries'}';

  String reasonFor(CleanerReviewGroup group) {
    final reason =
        group.analysis?.reason.trim() ??
        (vi
            ? 'Cần kiểm tra công dụng trước khi dọn.'
            : 'Check its purpose before cleanup.');
    final compact = reason.replaceAll(RegExp(r'\s+'), ' ');
    return compact.length > 280 ? '${compact.substring(0, 277)}…' : compact;
  }

  String toText() {
    final lines = <String>[title];
    for (final section in sections) {
      lines.add('\n${sectionHeading(section)}');
      if (section.groups.isEmpty) {
        lines.add(
          vi
              ? 'Không có nhóm file trong mục này.'
              : 'No file groups in this category.',
        );
      }
      for (final group in section.highlights) {
        lines.add('- ${highlightLabel(section, group)}\n  ${reasonFor(group)}');
        if (!section.folderTotals) {
          lines.add(
            '  ${vi ? 'Ví dụ' : 'Example'}: ${group.representative.fullPath}',
          );
        }
      }
      if (section.groups.length > section.highlights.length) {
        final count = section.groups.length - section.highlights.length;
        lines.add(
          vi
              ? 'Còn $count nhóm trong bảng kết quả.'
              : '$count more groups in the results.',
        );
      }
    }
    lines.add('\n$nextStep');
    lines.add(scopeNote);
    return lines.join('\n');
  }

  static CleanerItemDecision _decision(CleanerReviewGroup group) {
    final decision = group.analysis?.decision;
    if (group.usedFallback ||
        decision == null ||
        (decision == CleanerItemDecision.clean && !group.canClean)) {
      return CleanerItemDecision.review;
    }
    return decision;
  }

  static int _largestFirst(CleanerReviewGroup a, CleanerReviewGroup b) {
    final size = b.fileBytes.compareTo(a.fileBytes);
    return size == 0 ? a.id.compareTo(b.id) : size;
  }

  static String _path(CleanerReviewGroup group) => group.representative.fullPath
      .replaceAll('/', r'\')
      .toUpperCase()
      .replaceFirst(RegExp(r'\\+$'), '');
  static bool _overlaps(String a, String b) =>
      a == b || a.startsWith('$b\\') || b.startsWith('$a\\');

  static String formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

class CleanerReviewSummarySection {
  final String title;
  final List<CleanerReviewGroup> groups;
  final bool folderTotals;
  const CleanerReviewSummarySection({
    required this.title,
    required this.groups,
    this.folderTotals = false,
  });

  int get fileBytes => groups.fold(0, (sum, group) => sum + group.fileBytes);
  List<CleanerReviewGroup> get highlights => groups.take(3).toList();
}
