import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/components/common/item_shell.dart';
import 'package:cb_file_manager/ui/components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';

/// File icon for trash items - based on the original file path extension
/// Shows a folder icon when the item is a directory.
class TrashItemIcon extends StatelessWidget {
  final String originalPath;
  final double size;
  final bool isFolder;

  const TrashItemIcon({
    Key? key,
    required this.originalPath,
    this.size = 48,
    this.isFolder = false,
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

    final String ext = originalPath.contains('.')
        ? originalPath.split('.').last.toLowerCase()
        : '';
    final IconData fallback = FileTypeRegistry.getIcon('.$ext');
    final Color fallbackColor = FileTypeRegistry.getColor('.$ext');
    final bool isVideo = FileTypeUtils.isVideoFile(originalPath);
    final bool isImage = FileTypeUtils.isImageFile(originalPath);

    return OptimizedFileIcon(
      file: File(originalPath),
      isVideo: isVideo,
      isImage: isImage,
      size: size,
      fallbackIcon: fallback,
      fallbackColor: fallbackColor,
      borderRadius: BorderRadius.circular(size >= 32 ? 12.0 : 4.0),
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
      onTap: onTap,
      onDoubleTap: onDoubleTap,
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
