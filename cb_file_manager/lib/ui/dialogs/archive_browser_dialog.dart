import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/services/archive/archive_entry_info.dart';
import 'package:cb_file_manager/services/archive/archive_service.dart';
import 'package:cb_file_manager/ui/controllers/archive_operations_handler.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Dialog to browse archive contents and extract files.
class ArchiveBrowserDialog extends StatefulWidget {
  final String archivePath;

  const ArchiveBrowserDialog({super.key, required this.archivePath});

  static Future<void> show(
    BuildContext context, {
    required String archivePath,
  }) {
    return RouteUtils.showAcrylicDialog<void>(
      context: context,
      builder: (_) => ArchiveBrowserDialog(archivePath: archivePath),
    );
  }

  @override
  State<ArchiveBrowserDialog> createState() => _ArchiveBrowserDialogState();
}

class _ArchiveBrowserDialogState extends State<ArchiveBrowserDialog> {
  final ArchiveService _service = locator<ArchiveService>();
  List<ArchiveEntryInfo> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _service.listEntries(widget.archivePath);
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
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

  Future<void> _extractAll() async {
    await ArchiveOperationsHandler.extractToDirectory(
      context: context,
      archiveFile: File(widget.archivePath),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  IconData _iconForEntry(ArchiveEntryInfo entry) {
    if (entry.isDirectory) return PhosphorIconsLight.folder;
    final ext = FileTypeUtils.getFileExtension(entry.name);
    return FileTypeRegistry.getIcon(ext);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileName = p.basename(widget.archivePath);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.archive,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.archiveBrowseTitle,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(PhosphorIconsLight.x),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    )
                  : _entries.isEmpty
                  ? Center(child: Text(l10n.archiveEmpty))
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(_iconForEntry(entry)),
                          title: Text(
                            entry.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            entry.isDirectory
                                ? l10n.folder
                                : _formatSize(entry.size),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.close),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _loading || _error != null ? null : _extractAll,
                    icon: const Icon(PhosphorIconsLight.package),
                    label: Text(l10n.archiveExtractAll),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
