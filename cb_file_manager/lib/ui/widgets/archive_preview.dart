import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/services/archive/archive_entry_info.dart';
import 'package:cb_file_manager/services/archive/archive_service.dart';
import 'package:cb_file_manager/ui/controllers/archive_navigation.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Compact archive contents preview for the right-hand preview pane.
class ArchivePreview extends StatefulWidget {
  final String archivePath;

  const ArchivePreview({
    Key? key,
    required this.archivePath,
  }) : super(key: key);

  @override
  State<ArchivePreview> createState() => _ArchivePreviewState();
}

class _ArchivePreviewState extends State<ArchivePreview> {
  final ArchiveService _service = locator<ArchiveService>();
  List<ArchiveEntryInfo> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ArchivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.archivePath != widget.archivePath) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _service.listEntries(widget.archivePath);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconForEntry(ArchiveEntryInfo entry) {
    if (entry.isDirectory) return PhosphorIconsLight.folder;
    return FileTypeRegistry.getIcon(FileTypeUtils.getFileExtension(entry.name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }

    final previewEntries = _entries.take(40).toList();
    final hasMore = _entries.length > previewEntries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Icon(
                PhosphorIconsLight.archive,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.archivePreviewSummary(_entries.length),
                  style: theme.textTheme.labelMedium,
                ),
              ),
              TextButton(
                onPressed: () => ArchiveNavigation.openBrowse(
                  context,
                  archiveFilePath: widget.archivePath,
                ),
                child: Text(l10n.archiveBrowseTitle),
              ),
            ],
          ),
        ),
        Expanded(
          child: _entries.isEmpty
              ? Center(child: Text(l10n.archiveEmpty))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: previewEntries.length + (hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: theme.dividerColor.withValues(alpha: 0.35),
                  ),
                  itemBuilder: (context, index) {
                    if (hasMore && index == previewEntries.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          l10n.archivePreviewMore(_entries.length -
                              previewEntries.length),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      );
                    }

                    final entry = previewEntries[index];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Icon(_iconForEntry(entry), size: 18),
                      title: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: entry.isDirectory
                          ? null
                          : Text(
                              _formatSize(entry.size),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
