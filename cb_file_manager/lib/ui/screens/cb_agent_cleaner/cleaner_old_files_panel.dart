import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
    return Container(
      key: ValueKey(
        widget.categoryId == CleanerReviewCandidates.categoryId
            ? 'cleaner-old-files-panel'
            : 'cleaner-review-panel-${widget.categoryId}',
      ),
      decoration: CbDecorations.card(context, radius: 12),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          key: ValueKey(
            widget.categoryId == CleanerReviewCandidates.categoryId
                ? 'cleaner-old-files-expand'
                : 'cleaner-review-expand-${widget.categoryId}',
          ),
          leading: const Icon(Icons.history_rounded),
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
            const Divider(height: 1),
            for (final item in widget.candidates.take(_visible))
              ListTile(
                key: ValueKey('cleaner-old-file-${item.path}'),
                leading: Icon(
                  item.isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 20,
                ),
                title: Text(
                  item.path.replaceAll(r'\', '/').split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: item.path,
                      child: Text(
                        item.path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(FormatUtils.formatFileSize(item.sizeBytes)),
                    if (widget.onOpenFile != null)
                      IconButton(
                        key: ValueKey('cleaner-old-file-open-${item.path}'),
                        tooltip: l.cleanerAppsOpenFolder,
                        onPressed: () => widget.onOpenFile!(item.path),
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                      ),
                  ],
                ),
              ),
            if (widget.candidates.length > _visible)
              TextButton(
                onPressed: () => setState(() => _visible += 20),
                child: Text(l.cleanerOldFilesShowMore),
              ),
          ],
        ),
      ),
    );
  }
}
