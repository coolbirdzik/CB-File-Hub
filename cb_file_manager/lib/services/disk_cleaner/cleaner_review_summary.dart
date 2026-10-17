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
            CleanerItemDecision.clean => _t(
              'Consider cleaning',
              'Có thể cân nhắc dọn',
              'Temizlemeyi düşün',
              '可考虑清理',
            ),
            CleanerItemDecision.review => _t(
              'Review first',
              'Ưu tiên xem lại',
              'Önce gözden geçir',
              '优先查看',
            ),
            CleanerItemDecision.keep => _t('Keep', 'Nên giữ', 'Sakla', '建议保留'),
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
          title: _t(
            'Large folders to inspect',
            'Thư mục lớn cần chú ý',
            'İncelenecek büyük klasörler',
            '需要关注的大文件夹',
          ),
          groups: distinct,
          folderTotals: true,
        ),
      );
    }
  }

  bool get vi => languageCode == 'vi';

  /// Picks the text for the active language; unknown codes fall back to English.
  String _t(String en, String vi, String tr, String zh) =>
      switch (languageCode) {
        'vi' => vi,
        'tr' => tr,
        'zh' => zh,
        _ => en,
      };

  String get title => _t(
    'What needs attention',
    'Tóm tắt những phần cần chú ý',
    'Dikkat gerektirenler',
    '需要关注的内容',
  );
  String get scopeNote => _t(
    'Sizes use retained file rows; size-only entries are excluded from cleanup advice. Folder sizes are not added to file totals.',
    'Dung lượng theo các file có trong kết quả; mục chỉ có tổng dung lượng chưa được tính vào gợi ý dọn. Dung lượng thư mục không cộng vào tổng file.',
    'Boyutlar sonuçlarda tutulan dosya satırlarına dayanır; yalnızca boyut toplamı olan girdiler temizlik önerilerine dahil edilmez. Klasör boyutları dosya toplamlarına eklenmez.',
    '大小依据结果中保留的文件行；只有大小合计的条目不计入清理建议。文件夹大小不会加入文件总计。',
  );
  String get nextStep {
    if (sections.first.groups.isNotEmpty) {
      return _t(
        'Next: review the cleaning candidates, select only items you no longer need, then check the target list before confirming deletion.',
        'Bước tiếp theo: xem các nhóm có thể dọn, chọn đúng mục không còn cần rồi kiểm tra danh sách trước khi xác nhận xóa.',
        'Sonraki adım: temizleme adaylarını gözden geçirin, yalnızca artık gerekmeyen öğeleri seçin, ardından silmeyi onaylamadan önce hedef listesini kontrol edin.',
        '下一步：查看可清理的分组，只选择不再需要的项目，并在确认删除前检查目标列表。',
      );
    }
    if (sections[1].groups.isNotEmpty || sections.any((s) => s.folderTotals)) {
      return _t(
        'Next: inspect the review priorities or large folders to confirm their purpose; no file groups currently qualify as cleaning candidates.',
        'Bước tiếp theo: mở các mục ưu tiên xem lại hoặc thư mục lớn để xác nhận công dụng; chưa có nhóm file đủ điều kiện gợi ý dọn.',
        'Sonraki adım: amaçlarını doğrulamak için öncelikli incelemeleri veya büyük klasörleri açın; şu anda temizleme adayı olarak uygun dosya grubu yok.',
        '下一步：打开优先查看的项目或大文件夹以确认其用途；目前没有文件分组符合清理建议的条件。',
      );
    }
    return _t(
      'Next: keep the identified data; no file groups currently qualify as cleaning candidates.',
      'Bước tiếp theo: giữ các dữ liệu đã nhận diện; chưa có nhóm file đủ điều kiện gợi ý dọn.',
      'Sonraki adım: belirlenen verileri saklayın; şu anda temizleme adayı olarak uygun dosya grubu yok.',
      '下一步：保留已识别的数据；目前没有文件分组符合清理建议的条件。',
    );
  }

  String sectionHeading(CleanerReviewSummarySection section) {
    if (section.folderTotals) return section.title;
    return '${section.title}: ${section.groups.length} ${_t('groups', 'nhóm', 'grup', '个分组')} · ${formatBytes(section.fileBytes)}';
  }

  String highlightLabel(
    CleanerReviewSummarySection section,
    CleanerReviewGroup group,
  ) => section.folderTotals
      ? '${group.representative.fullPath} · ${formatBytes(group.largestFolderBytes)} (${_t('folder total', 'tổng thư mục', 'klasör toplamı', '文件夹合计')})'
      : '${group.scope} · ${formatBytes(group.fileBytes)} · ${group.nodes.length} ${_t('entries', 'mục', 'girdi', '个条目')}';

  String reasonFor(CleanerReviewGroup group) {
    final reason =
        group.analysis?.reason.trim() ??
        _t(
          'Check its purpose before cleanup.',
          'Cần kiểm tra công dụng trước khi dọn.',
          'Temizlemeden önce amacını kontrol edin.',
          '清理前请先确认其用途。',
        );
    final compact = reason.replaceAll(RegExp(r'\s+'), ' ');
    return compact.length > 280 ? '${compact.substring(0, 277)}…' : compact;
  }

  String toText() {
    final lines = <String>[title];
    for (final section in sections) {
      lines.add('\n${sectionHeading(section)}');
      if (section.groups.isEmpty) {
        lines.add(
          _t(
            'No file groups in this category.',
            'Không có nhóm file trong mục này.',
            'Bu kategoride dosya grubu yok.',
            '此类别中没有文件分组。',
          ),
        );
      }
      for (final group in section.highlights) {
        lines.add('- ${highlightLabel(section, group)}\n  ${reasonFor(group)}');
        if (!section.folderTotals) {
          lines.add(
            '  ${_t('Example', 'Ví dụ', 'Örnek', '示例')}: ${group.representative.fullPath}',
          );
        }
      }
      if (section.groups.length > section.highlights.length) {
        final count = section.groups.length - section.highlights.length;
        lines.add(
          _t(
            '$count more groups in the results.',
            'Còn $count nhóm trong bảng kết quả.',
            'Sonuçlarda $count grup daha var.',
            '结果中还有 $count 个分组。',
          ),
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
