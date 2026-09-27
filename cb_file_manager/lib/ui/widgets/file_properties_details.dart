import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

/// The same property values in the details screen and the selection panel.
class FilePropertiesDetails extends StatelessWidget {
  const FilePropertiesDetails({
    super.key,
    required this.filePath,
    required this.statFuture,
  });

  final String filePath;
  final Future<FileStat> statFuture;

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
