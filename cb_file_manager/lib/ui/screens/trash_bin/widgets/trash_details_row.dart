import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/ui/components/common/item_shell.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'trash_list_item.dart';

/// Shared helpers for details-view columns
Widget detailsCell({required int flex, required Widget child}) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: child,
      ),
    );

/// Details row widget for trash bin - displays trash item in details view
class TrashDetailsRow extends StatelessWidget {
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

  const TrashDetailsRow({
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
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          // Name column (flex 3): icon + name
          detailsCell(
            flex: 3,
            child: Row(
              children: [
                TrashItemIcon(
                    originalPath: item.originalPath,
                    size: 24,
                    isFolder: item.isFolder),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.displayNameValue,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: item.isSystemTrashItem
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: item.isSystemTrashItem
                          ? theme.colorScheme.primary
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Original path column (flex 3)
          detailsCell(
            flex: 3,
            child: Text(
              item.originalPath,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          // Date deleted column (flex 2)
          detailsCell(
            flex: 2,
            child: Text(
              formatDate(item.trashedDate),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Size column (flex 1)
          detailsCell(
            flex: 1,
            child: Text(
              formatSize(item.size),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
