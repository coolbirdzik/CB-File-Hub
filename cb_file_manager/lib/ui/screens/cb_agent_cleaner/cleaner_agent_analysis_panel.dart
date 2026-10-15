import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/disk_cleaner/cleaner_agent_review.dart';
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
  final ValueChanged<DiskTreeNode> onReveal;

  const CleanerAgentAnalysisPanel({
    super.key,
    required this.inspectingNode,
    required this.focusedPath,
    required this.items,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
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
                if (items.isNotEmpty)
                  Text('${items.length}', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('cleaner-agent-analysis-list'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                if (inspectingNode case final node?)
                  Semantics(
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
                  ),
                for (final item in ordered)
                  InkWell(
                    key: ValueKey(
                      'cleaner-agent-analysis-${item.node.fullPath}',
                    ),
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
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
