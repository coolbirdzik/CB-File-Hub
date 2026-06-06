import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/ui/components/common/item_shell.dart';
import 'package:cb_file_manager/ui/components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:path/path.dart' as p;

/// File icon for trash items - generates thumbnails from the actual trash file path
/// Shows a folder icon when the item is a directory.
class TrashItemIcon extends StatelessWidget {
  final String originalPath;
  final String actualFilePath;
  final String displayName;
  final double size;
  final bool isFolder;
  final bool fillAvailable;

  const TrashItemIcon({
    Key? key,
    required this.originalPath,
    required this.actualFilePath,
    required this.displayName,
    this.size = 48,
    this.isFolder = false,
    this.fillAvailable = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isFolder) {
      return Icon(
        PhosphorIconsFill.folderSimple,
        size: size,
        color: const Color(0xFFFFB74D), // amber/orange folder color
      );
    }

    final String typePath =
        displayName.isNotEmpty ? displayName : p.basename(originalPath);
    final String extension = p.extension(typePath).toLowerCase();
    final FileCategory category = FileTypeRegistry.getCategory(extension);
    final IconData fallback = FileTypeRegistry.getIcon(extension);
    final Color fallbackColor = FileTypeRegistry.getColor(extension);
    final bool isVideo = category == FileCategory.video;
    final bool isImage = category == FileCategory.image;

    if (fillAvailable && (isVideo || isImage)) {
      return ThumbnailLoader(
        filePath: actualFilePath,
        isVideo: isVideo,
        isImage: isImage,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(0),
        fallbackBuilder: () => Center(
          child: Icon(
            fallback,
            size: size,
            color: fallbackColor,
          ),
        ),
      );
    }

    return OptimizedFileIcon(
      file: File(actualFilePath),
      isVideo: isVideo,
      isImage: isImage,
      size: size,
      fallbackIcon: fallback,
      fallbackColor: fallbackColor,
      borderRadius: BorderRadius.circular(size >= 32 ? 8.0 : 2.0),
    );
  }
}

/// List item widget for trash bin - displays trash item in list view
class TrashListItem extends StatelessWidget {
  final TrashItem item;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isDesktop;
  final VoidCallback onToggleSelection;
  final VoidCallback onEnterSelectionMode;
  final void Function(Offset) onContextMenu;
  final String Function(DateTime) formatDate;
  final String Function(int) formatSize;
  final AppLocalizations l10n;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const TrashListItem({
    Key? key,
    required this.item,
    required this.isSelected,
    required this.isSelectionMode,
    required this.isDesktop,
    required this.onToggleSelection,
    required this.onEnterSelectionMode,
    required this.onContextMenu,
    required this.formatDate,
    required this.formatSize,
    required this.l10n,
    this.onTap,
    this.onDoubleTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListItemShell(
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      isDesktopMode: isDesktop,
      onTap: isDesktop ? onToggleSelection : onTap,
      onDoubleTap: isDesktop ? onDoubleTap : null,
      onToggleSelection: onToggleSelection,
      onEnterSelectionMode: onEnterSelectionMode,
      onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      child: Row(
        children: [
          // File icon (48×48, matches FileItem thumbnail size)
          SizedBox(
            width: 48,
            height: 48,
            child: TrashItemIcon(
                originalPath: item.originalPath,
                actualFilePath: item.actualFilePath,
                displayName: item.displayNameValue,
                size: 48,
                isFolder: item.isFolder),
          ),
          const SizedBox(width: 16),
          // Text content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Text(
                  item.displayNameValue,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: item.isSystemTrashItem
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Original path
                Text(
                  l10n.originalLocation(item.originalPath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                // Date + size row
                Row(
                  children: [
                    Text(
                      formatSize(item.size),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                    Icon(PhosphorIconsLight.calendar,
                        size: 12, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      formatDate(item.trashedDate),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (item.isSystemTrashItem) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                        child: Text(
                          l10n.systemLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
