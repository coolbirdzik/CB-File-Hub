import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path/path.dart' as pathlib;

import '../../../../models/ai/ai_search_result.dart';

/// Compact card showing an AI search result with file info and relevance.
///
/// Tap = open parent folder in a new tab (file highlighted).
/// Open-external button = open file with OS default app.
class FileResultCard extends StatelessWidget {
  final AiSearchResult result;

  /// Tap on card = open parent folder in new tab with file highlighted.
  final VoidCallback? onTap;

  /// Open the parent folder in a new tab (no file highlight).
  final VoidCallback? onOpenFolder;

  /// Open file with OS default application.
  final VoidCallback? onOpenExternal;

  const FileResultCard({
    Key? key,
    required this.result,
    this.onTap,
    this.onOpenFolder,
    this.onOpenExternal,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final parentPath = pathlib.dirname(result.path);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // File type icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _iconForExtension(pathlib.extension(result.path)),
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),

              // File info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.fileName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parentPath,
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (result.explanation.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        result.explanation,
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (!result.verified)
                      Text(
                        'File not found',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),

              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Open folder
                  if (onOpenFolder != null)
                    IconButton(
                      icon: Icon(
                        PhosphorIconsLight.folderOpen,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Open folder',
                      onPressed: onOpenFolder,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  // Open externally
                  if (onOpenExternal != null)
                    IconButton(
                      icon: Icon(
                        PhosphorIconsLight.arrowSquareOut,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Open file',
                      onPressed: onOpenExternal,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),

                  // Relevance badge
                  if (result.relevance > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: _relevanceColor(result.relevance)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${result.relevance}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _relevanceColor(result.relevance),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _relevanceColor(int relevance) {
    if (relevance >= 80) return Colors.green;
    if (relevance >= 50) return Colors.orange;
    return Colors.grey;
  }

  IconData _iconForExtension(String ext) {
    ext = ext.toLowerCase();
    const imageExts = {
      '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.heic'
    };
    const videoExts = {'.mp4', '.avi', '.mkv', '.mov', '.wmv', '.webm'};
    const audioExts = {'.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a'};
    const docExts = {'.doc', '.docx', '.pdf', '.txt', '.rtf'};
    const codeExts = {
      '.dart', '.js', '.ts', '.py', '.java', '.c', '.cpp', '.go', '.rs'
    };
    const archiveExts = {'.zip', '.rar', '.7z', '.tar', '.gz'};

    if (imageExts.contains(ext)) return PhosphorIconsLight.image;
    if (videoExts.contains(ext)) return PhosphorIconsLight.filmStrip;
    if (audioExts.contains(ext)) return PhosphorIconsLight.musicNote;
    if (docExts.contains(ext)) return PhosphorIconsLight.fileText;
    if (codeExts.contains(ext)) return PhosphorIconsLight.code;
    if (archiveExts.contains(ext)) return PhosphorIconsLight.fileZip;
    return PhosphorIconsLight.file;
  }
}
