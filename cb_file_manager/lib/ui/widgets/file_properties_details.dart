import 'dart:io';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

/// The same property values in the details screen and the selection panel.
class FilePropertiesDetails extends StatelessWidget {
  const FilePropertiesDetails({
    super.key,
    required this.filePath,
    required this.statFuture,
    this.dense = false,
    this.labelWidth = 88,
  });

  final String filePath;
  final Future<FileStat> statFuture;

  /// Label beside value, one row each, for the compact properties pane.
  final bool dense;
  final double labelWidth;

  Widget _copyPathButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CbButton.icon(
      key: const ValueKey('file-properties-copy-path'),
      icon: PhosphorIconsLight.copy,
      size: CbButtonSize.xs,
      tooltip: l10n.ivCopyPath,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: filePath));
        if (context.mounted) AppToast.info(context, l10n.copiedPathToClipboard);
      },
    );
  }

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
          return CbLoadingText(text: l10n.loading, textAlign: TextAlign.start);
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
          l10n.fileModified: stat.modified.toString().split('.')[0],
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in values.entries)
              if (dense)
                FilePropertyRow(
                  label: entry.key,
                  value: entry.value,
                  labelWidth: labelWidth,
                  trailing: entry.key == l10n.fileLocation
                      ? _copyPathButton(context)
                      : null,
                )
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
                      if (entry.key == l10n.fileLocation)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SelectableText(
                                entry.value,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            const SizedBox(width: CbSpacing.xs),
                            _copyPathButton(context),
                          ],
                        )
                      else
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
  const FilePropertyRow({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.labelWidth = 88,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CbSpacing.xxs),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: constraints.hasBoundedWidth
                  ? labelWidth.clamp(0, constraints.maxWidth * .42).toDouble()
                  : labelWidth,
              child: Text(
                label,
                maxLines: 2,
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
            if (trailing != null) ...[
              const SizedBox(width: CbSpacing.xs),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
