import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import '../../../../models/ai/referenced_file.dart';

/// A card displayed in the chat showing a file referenced (dropped) by the user.
/// For text files, shows a content preview. For other files, shows file info.
class ReferencedFileCard extends StatelessWidget {
  final List<ReferencedFile> files;

  const ReferencedFileCard({super.key, required this.files});

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.paperclip,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  files.length == 1
                      ? l10n.referencedFile
                      : l10n.referencedFiles(files.length),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    final paths = files.map((f) => f.path).join('\n');
                    Clipboard.setData(ClipboardData(text: paths));
                    AppToast.info(context, l10n.pathsCopied(files.length));
                  },
                  child: Icon(
                    PhosphorIconsLight.copy,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 0, endIndent: 0),
          // File items
          ...files.map((f) => _buildFileItem(context, f, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildFileItem(
    BuildContext context,
    ReferencedFile file,
    ThemeData theme,
    bool isDark,
  ) {
    final icon = _iconForExt(file.extension);
    final accentColor = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File header row
          Row(
            children: [
              Icon(icon, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.9)
                            : Colors.black.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      file.path,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.black.withValues(alpha: 0.4),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (file.isTextFile)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'text',
                    style: TextStyle(
                      fontSize: 9,
                      color: accentColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          // Content preview for text files
          if (file.isTextFile) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: _buildContentPreview(file, theme, isDark),
            ),
          ],
          // Error state
          if (file.error != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  PhosphorIconsLight.warningCircle,
                  size: 11,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    file.error!,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.error,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContentPreview(
    ReferencedFile file,
    ThemeData theme,
    bool isDark,
  ) {
    if (!file.contentLoaded || file.content == null) {
      return Row(
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Loading content...',
            style: TextStyle(
              fontSize: 10,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.4),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    final lines = file.content!.split('\n');
    final previewLines = lines.take(12).join('\n');
    final truncated = lines.length > 12;
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.75)
        : Colors.black.withValues(alpha: 0.7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          previewLines,
          style: TextStyle(
            fontSize: 10,
            fontFamily: 'monospace',
            color: textColor,
            height: 1.4,
          ),
        ),
        if (truncated)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '... (${lines.length - 12} more lines)',
              style: TextStyle(
                fontSize: 9,
                fontStyle: FontStyle.italic,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.3),
              ),
            ),
          ),
      ],
    );
  }

  IconData _iconForExt(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'svg':
        return PhosphorIconsLight.image;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'webm':
        return PhosphorIconsLight.filmStrip;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'm4a':
      case 'aac':
      case 'ogg':
        return PhosphorIconsLight.musicNote;
      case 'pdf':
        return PhosphorIconsLight.filePdf;
      case 'txt':
      case 'md':
      case 'markdown':
      case 'log':
        return PhosphorIconsLight.fileText;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return PhosphorIconsLight.fileZip;
      case 'dart':
      case 'js':
      case 'ts':
      case 'tsx':
      case 'jsx':
      case 'py':
      case 'java':
      case 'kt':
      case 'scala':
      case 'cpp':
      case 'c':
      case 'cs':
      case 'h':
      case 'hpp':
      case 'go':
      case 'rs':
      case 'rb':
      case 'php':
      case 'sh':
      case 'bash':
      case 'ps1':
      case 'bat':
      case 'cmd':
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'toml':
      case 'html':
      case 'htm':
      case 'css':
      case 'scss':
      case 'sql':
      case 'swift':
      case 'm':
      case 'lua':
      case 'vim':
        return PhosphorIconsLight.fileCode;
      default:
        return PhosphorIconsLight.file;
    }
  }
}
