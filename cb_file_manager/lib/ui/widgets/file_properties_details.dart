import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

/// The same property values in the details screen and the selection panel.
class FilePropertiesDetails extends StatelessWidget {
  const FilePropertiesDetails({
    super.key,
    required this.filePath,
    required this.statFuture,
    this.dense = false,
  });

  final String filePath;
  final Future<FileStat> statFuture;

  /// Label beside value, one row each, for the compact properties pane.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<FileStat>(
      future: statFuture,
      builder: (context, snapshot) {
        // A new future keeps the previous stat until it resolves, so switching
        // files in the properties pane does not blink through "Loading".
        if (!snapshot.hasData &&
            snapshot.connectionState != ConnectionState.done) {
          return Text(l10n.loading);
        }
        final stat = snapshot.data;
        if (stat == null || stat.type == FileSystemEntityType.notFound) {
          return Text(l10n.operationFailed);
        }
        final isFolder = stat.type == FileSystemEntityType.directory;
        final extension = FileTypeUtils.getFileExtension(filePath);
        final type = isFolder
            ? l10n.folder
            : FileTypeUtils.getFileTypeLabel(context, extension);
        final values = <String, String>{
          l10n.fileName: path.basename(filePath),
          l10n.fileType:
              '$type${!isFolder && extension.isNotEmpty ? ' (${extension.substring(1).toUpperCase()})' : ''}',
          if (!isFolder)
            l10n.fileSize: FormatUtils.formatFileSizeExact(stat.size),
          l10n.fileLocation: filePath,
          l10n.fileCreated: stat.changed.toString().split('.')[0],
          l10n.fileModified: stat.modified.toString().split('.')[0],
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in values.entries)
              if (dense)
                FilePropertyRow(label: entry.key, value: entry.value)
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      SelectableText(
                        entry.value,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// One label/value line of the compact properties pane.
class FilePropertyRow extends StatelessWidget {
  const FilePropertyRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CbSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CbTypography.bodySm.copyWith(color: c.textSecondary),
            ),
          ),
          const SizedBox(width: CbSpacing.sm),
          Expanded(
            child: SelectableText(
              value,
              style: CbTypography.bodySm.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
