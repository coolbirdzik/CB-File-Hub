import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/disk_cleaner/cleaner_agent_review.dart';
import '../../../services/disk_cleaner/cleaner_review_summary.dart';
import '../../../services/disk_cleaner/disk_tree_node.dart';

String cleanerDecisionLabel(AppLocalizations l, CleanerItemDecision decision) =>
    switch (decision) {
      CleanerItemDecision.clean => l.diskCleanerAgentCanClean,
      CleanerItemDecision.review => l.diskCleanerAgentNeedsReview,
      CleanerItemDecision.keep => l.diskCleanerAgentKeep,
    };

class CleanerDecisionBadge extends StatelessWidget {
  final CleanerItemAnalysis analysis;
  const CleanerDecisionBadge({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = switch (analysis.decision) {
      CleanerItemDecision.clean =>
        dark ? Colors.green.shade300 : Colors.green.shade800,
      CleanerItemDecision.review =>
        dark ? Colors.amber.shade300 : Colors.orange.shade900,
      CleanerItemDecision.keep => theme.colorScheme.onSurfaceVariant,
    };
    return Tooltip(
      message: analysis.reason,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          cleanerDecisionLabel(
            AppLocalizations.of(context)!,
            analysis.decision,
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
        ),
      ),
    );
  }
}

/// A live companion to the scanned tree, populated by completed agent tools.
class CleanerAgentAnalysisPanel extends StatelessWidget {
  final DiskTreeNode? inspectingNode;
  final String? focusedPath;
  final List<CleanerReviewedItem> items;
  final CleanerFullReview? review;
  final bool showSummary;
  final ValueChanged<DiskTreeNode> onReveal;

  const CleanerAgentAnalysisPanel({
    super.key,
    required this.inspectingNode,
    required this.focusedPath,
    required this.items,
    this.review,
    this.showSummary = true,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final summary =
        showSummary &&
            review != null &&
            review!.isComplete &&
            review!.groups.isNotEmpty
        ? CleanerReviewSummary(
            review!,
            languageCode: Localizations.localeOf(context).languageCode,
          )
        : null;
    final ordered = [
      ...items.where((item) => item.node.fullPath == focusedPath),
      ...items.where((item) => item.node.fullPath != focusedPath),
    ];
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.sparkle,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.diskCleanerAgentAnalysisTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (review != null)
                  Text(
                    '${review!.reviewed} / ${review!.total}',
                    style: theme.textTheme.labelSmall,
                  )
                else if (items.isNotEmpty)
                  Text('${items.length}', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          if (review != null && review!.total > 0)
            LinearProgressIndicator(value: review!.reviewed / review!.total),
          Expanded(
            child: ListView.builder(
              key: const ValueKey('cleaner-agent-analysis-list'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              itemCount:
                  ordered.length +
                  (inspectingNode == null ? 0 : 1) +
                  (summary == null ? 0 : 1),
              itemBuilder: (context, index) {
                if (summary != null && index == 0) {
                  return _buildSummary(context, summary);
                }
                final contentIndex = index - (summary == null ? 0 : 1);
                if (inspectingNode case final node? when contentIndex == 0) {
                  return Semantics(
                    liveRegion: true,
                    child: Padding(
                      key: ValueKey(
                        'cleaner-agent-inspecting-${node.fullPath}',
                      ),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.diskCleanerAgentInspecting,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            node.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SelectableText(
                            node.fullPath,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final item =
                    ordered[contentIndex - (inspectingNode == null ? 0 : 1)];
                return InkWell(
                  key: ValueKey('cleaner-agent-analysis-${item.node.fullPath}'),
                  onTap: () => onReveal(item.node),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.node.name,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            CleanerDecisionBadge(analysis: item.analysis),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.analysis.fromScan
                              ? l.diskCleanerAdviceFromScan
                              : l.diskCleanerAdviceFromAi,
                          style: theme.textTheme.labelSmall,
                        ),
                        if (item.coveredItems > 1)
                          Text(
                            l.diskCleanerAgentGroupCount(item.coveredItems),
                            style: theme.textTheme.labelSmall,
                          ),
                        Tooltip(
                          message: item.node.fullPath,
                          child: Text(
                            item.node.fullPath,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.analysis.reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, CleanerReviewSummary summary) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('cleaner-review-summary'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(summary.title, style: theme.textTheme.titleSmall),
          ),
          for (final section in summary.sections) ...[
            const SizedBox(height: 12),
            Text(
              summary.sectionHeading(section),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final group in section.highlights)
              InkWell(
                key: ValueKey('cleaner-summary-${group.id}'),
                onTap: () => onReveal(group.representative),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        summary.highlightLabel(section, group),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summary.reasonFor(group),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (!section.folderTotals)
                        Text(
                          group.representative.fullPath,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(summary.nextStep, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(summary.scopeNote, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
