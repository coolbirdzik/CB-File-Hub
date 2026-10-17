import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/disk_cleaner/cleaner_agent_review.dart';
import '../../../services/disk_cleaner/cleaner_review_summary.dart';
import '../../../services/disk_cleaner/disk_tree_node.dart';

/// Visual review of one completed scan. Navigation never selects for deletion.
class CleanerReviewOverview extends StatefulWidget {
  final CleanerFullReview review;
  final ValueChanged<DiskTreeNode> onReveal;
  final int coverageIssueCount;

  const CleanerReviewOverview({
    super.key,
    required this.review,
    required this.onReveal,
    this.coverageIssueCount = 0,
  });

  @override
  State<CleanerReviewOverview> createState() => _CleanerReviewOverviewState();
}

class _CleanerReviewOverviewState extends State<CleanerReviewOverview> {
  int? _selected;

  @override
  void didUpdateWidget(CleanerReviewOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.review, widget.review)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final l = AppLocalizations.of(context)!;
    String t(String en, String vi, String tr, String zh) =>
        switch (languageCode) {
          'vi' => vi,
          'tr' => tr,
          'zh' => zh,
          _ => en,
        };
    final summary = CleanerReviewSummary(
      widget.review,
      languageCode: const ['vi', 'tr', 'zh'].contains(languageCode)
          ? languageCode
          : 'en',
    );
    final index =
        _selected ??
        summary.sections
            .indexWhere((s) => s.groups.isNotEmpty)
            .clamp(0, summary.sections.length - 1);
    final section = summary.sections[index];
    final colors = [
      theme.brightness == Brightness.dark
          ? Colors.green.shade300
          : Colors.green.shade800,
      theme.brightness == Brightness.dark
          ? Colors.amber.shade300
          : Colors.orange.shade900,
      theme.colorScheme.onSurfaceVariant,
    ];
    final total = summary.sections
        .take(3)
        .fold<int>(0, (sum, s) => sum + s.fileBytes);
    return Material(
      key: const ValueKey('cleaner-review-overview'),
      color: theme.colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 240;
          return SingleChildScrollView(
            key: const ValueKey('cleaner-overview-scroll'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        PhosphorIconsLight.chartBar,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          summary.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (summary.sections.length > 3)
                        Tooltip(
                          message: summary.sections[3].title,
                          child: IconButton(
                            key: const ValueKey('cleaner-overview-folders'),
                            visualDensity: VisualDensity.compact,
                            isSelected: index == 3,
                            onPressed: () => setState(() => _selected = 3),
                            icon: const Icon(
                              PhosphorIconsLight.folder,
                              size: 18,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
                            child: TextButton(
                              key: ValueKey('cleaner-overview-category-$i'),
                              onPressed: () => setState(() => _selected = i),
                              style: TextButton.styleFrom(
                                // Overview tiles have several lines; the app's
                                // shared 32px button height does not apply here.
                                fixedSize: Size.infinite,
                                maximumSize: Size.infinite,
                                minimumSize: Size.zero,
                                foregroundColor: colors[i],
                                backgroundColor: index == i
                                    ? colors[i].withValues(alpha: 0.09)
                                    : theme.colorScheme.surfaceContainerLow,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  side: BorderSide(
                                    color: index == i
                                        ? colors[i].withValues(alpha: 0.5)
                                        : Colors.transparent,
                                  ),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    summary.sections[i].title,
                                    maxLines: 2,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors[i],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      CleanerReviewSummary.formatBytes(
                                        summary.sections[i].fileBytes,
                                      ),
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            color: colors[i],
                                            fontWeight: FontWeight.w600,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ),
                                  Text(
                                    '${summary.sections[i].groups.length} ${t('groups', 'nhóm', 'grup', '个分组')}',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Tooltip(
                    message: summary.scopeNote,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 5,
                        child: total == 0
                            ? ColoredBox(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < 3; i++)
                                    if (summary.sections[i].fileBytes > 0)
                                      Expanded(
                                        flex: summary.sections[i].fileBytes,
                                        child: ColoredBox(
                                          key: ValueKey(
                                            'cleaner-overview-share-$i',
                                          ),
                                          color: colors[i],
                                        ),
                                      ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  ...[
                    const SizedBox(height: 8),
                    Text(
                      '${section.title} · ${section.folderTotals ? t('Folder totals', 'Tổng thư mục', 'Klasör toplamları', '文件夹合计') : t('Largest groups', 'Các nhóm lớn nhất', 'En büyük gruplar', '最大的分组')}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    section.groups.isEmpty
                        ? Center(
                            child: Text(
                              t(
                                'No file groups in this category.',
                                'Chưa có nhóm file trong mục này.',
                                'Bu kategoride dosya grubu yok.',
                                '此类别中没有文件分组。',
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            primary: false,
                            physics: const NeverScrollableScrollPhysics(),
                            key: ValueKey('cleaner-overview-priorities-$index'),
                            itemCount: section.highlights.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, position) {
                              final group = section.highlights[position];
                              final bytes = section.folderTotals
                                  ? group.largestFolderBytes
                                  : group.fileBytes;
                              final fraction = section.fileBytes == 0
                                  ? 0.0
                                  : bytes / section.fileBytes;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 22,
                                      child: Text(
                                        '${position + 1}',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Tooltip(
                                                  message: group
                                                      .representative
                                                      .fullPath,
                                                  child: Text(
                                                    '${_groupTitle(group, l)} · ${section.folderTotals ? group.representative.fullPath : group.scope}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                CleanerReviewSummary.formatBytes(
                                                  bytes,
                                                ),
                                                style: theme
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                              ),
                                            ],
                                          ),
                                          if (!section.folderTotals)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: LinearProgressIndicator(
                                                key: ValueKey(
                                                  'cleaner-overview-group-share-${group.id}',
                                                ),
                                                value: fraction,
                                                minHeight: 3,
                                                color: colors[index],
                                                backgroundColor: colors[index]
                                                    .withValues(alpha: 0.08),
                                                semanticsLabel:
                                                    '${group.scope}: ${(fraction * 100).round()}% ${t('of this category', 'dung lượng trong mục này', 'bu kategorinin', '占此类别的比例')}',
                                              ),
                                            ),
                                          const SizedBox(height: 4),
                                          Tooltip(
                                            message:
                                                group.analysis?.reason ??
                                                summary.reasonFor(group),
                                            child: Text(
                                              summary.reasonFor(group),
                                              maxLines: compact ? 1 : 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                          TextButton(
                                            key: ValueKey(
                                              'cleaner-summary-${group.id}',
                                            ),
                                            style: TextButton.styleFrom(
                                              fixedSize: Size.infinite,
                                              maximumSize: Size.infinite,
                                              alignment: Alignment.centerLeft,
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(0, 28),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            onPressed: () => widget.onReveal(
                                              group.representative,
                                            ),
                                            child: Text(
                                              t(
                                                'Show in results',
                                                'Xem trong kết quả',
                                                'Sonuçlarda göster',
                                                '在结果中显示',
                                              ),
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ],
                  ...[
                    const SizedBox(height: 4),
                    Tooltip(
                      message: summary.scopeNote,
                      child: Text(
                        '${t('Scan metadata · Select items in the result tree to clean', 'Theo dữ liệu quét · Chọn mục trong cây kết quả để dọn', 'Tarama meta verileri · Temizlemek için sonuç ağacından öğe seçin', '扫描元数据 · 在结果树中选择要清理的项目')}'
                        '${widget.review.aggregatedItems > 0 ? ' · ${widget.review.aggregatedItems} ${t('size-only entries', 'mục chỉ có tổng dung lượng', 'yalnızca boyut toplamı olan girdi', '只有大小合计的条目')}' : ''}'
                        '${widget.coverageIssueCount > 0 ? ' · ${widget.coverageIssueCount} ${t('paths with scan limits', 'đường dẫn chưa quét đầy đủ', 'tarama sınırlı yol', '扫描受限的路径')}' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _groupTitle(CleanerReviewGroup group, AppLocalizations l) =>
      switch (group.categoryId) {
        'windows_temp' => l.diskCleanerCategoryWindowsTemp,
        'browser_cache' => l.diskCleanerCategoryBrowserCache,
        'recycle_bin' => l.diskCleanerCategoryRecycleBin,
        'thumbnail_cache' => l.diskCleanerCategoryThumbnailCache,
        'app_cache' => l.diskCleanerCategoryAppCache,
        'crash_dumps_logs' => l.diskCleanerCategoryCrashLogs,
        'windows_update_cache' => l.diskCleanerCategoryWindowsUpdate,
        'prefetch' => l.diskCleanerCategoryPrefetch,
        'delivery_optimization' => l.diskCleanerCategoryDeliveryOptimization,
        'dev_cache' => l.diskCleanerCategoryDevCache,
        _ => group.representative.name,
      };
}
