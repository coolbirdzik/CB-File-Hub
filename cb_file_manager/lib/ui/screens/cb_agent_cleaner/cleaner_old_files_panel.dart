import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/disk_cleaner/cleaner_review_candidates.dart';
import '../../utils/format_utils.dart';

/// Informational evidence only: no checkboxes and no cleanup callback.
class CleanerOldFilesPanel extends StatefulWidget {
  final List<CleanerFileReviewCandidate> candidates;
  final ValueChanged<String>? onOpenFile;
  final String? title;
  final String? description;
  final String categoryId;

  const CleanerOldFilesPanel({
    super.key,
    required this.candidates,
    this.onOpenFile,
    this.title,
    this.description,
    this.categoryId = CleanerReviewCandidates.categoryId,
  });

  @override
  State<CleanerOldFilesPanel> createState() => _CleanerOldFilesPanelState();
}

class _CleanerOldFilesPanelState extends State<CleanerOldFilesPanel> {
  int _visible = 20;

  @override
  void didUpdateWidget(CleanerOldFilesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.candidates, widget.candidates)) _visible = 20;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final c = context.cbColors;
    return CbSurface(
      key: ValueKey(
        widget.categoryId == CleanerReviewCandidates.categoryId
            ? 'cleaner-old-files-panel'
            : 'cleaner-review-panel-${widget.categoryId}',
      ),
      clip: true,
      child: CbExpander(
        key: ValueKey(
          widget.categoryId == CleanerReviewCandidates.categoryId
              ? 'cleaner-old-files-expand'
              : 'cleaner-review-expand-${widget.categoryId}',
        ),
        leading: const Icon(PhosphorIconsLight.clockCounterClockwise),
        title: Text(widget.title ?? l.cleanerOldFilesTitle),
        subtitle: Text(
          widget.categoryId == CleanerReviewCandidates.categoryId
              ? l.cleanerOldFilesCount(widget.candidates.length)
              : l.cleanerReviewSummary(
                  widget.candidates.length,
                  FormatUtils.formatFileSize(
                    widget.candidates.fold(
                      0,
                      (sum, item) => sum + item.sizeBytes,
                    ),
                  ),
                ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(widget.description ?? l.cleanerOldFilesDescription),
          ),
          const SizedBox(height: CbSpacing.xs),
          for (final item in widget.candidates.take(_visible))
            Padding(
              key: ValueKey('cleaner-old-file-${item.path}'),
              padding: const EdgeInsets.symmetric(
                horizontal: CbSpacing.lg,
                vertical: CbSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: CbSpacing.xs),
                    child: Icon(
                      item.isDirectory
                          ? PhosphorIconsLight.folder
                          : PhosphorIconsLight.file,
                      size: 20,
                      color: c.icon,
                    ),
                  ),
                  const SizedBox(width: CbSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.path.replaceAll(r'\', '/').split('/').last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CbTypography.label.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        CbTooltip(
                          message: item.path,
                          child: Text(
                            item.path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: CbTypography.bodySm.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                        if (!item.isDirectory)
                          Text(
                            l.cleanerOldFilesModified(
                              FormatUtils.formatDateLocalized(
                                item.lastModified,
                                context,
                              ),
                            ),
                            style: CbTypography.bodySm.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        Text(
                          FormatUtils.formatFileSize(item.sizeBytes),
                          style: CbTypography.monoSm.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onOpenFile != null)
                    CbButton.icon(
                      key: ValueKey('cleaner-old-file-open-${item.path}'),
                      tooltip: l.cleanerAppsOpenFolder,
                      onPressed: () => widget.onOpenFile!(item.path),
                      icon: PhosphorIconsLight.folderOpen,
                    ),
                ],
              ),
            ),
          if (widget.candidates.length > _visible)
            CbButton(
              variant: CbButtonVariant.ghost,
              onPressed: () => setState(() => _visible += 20),
              label: l.cleanerOldFilesShowMore,
            ),
        ],
      ),
    );
  }
}
