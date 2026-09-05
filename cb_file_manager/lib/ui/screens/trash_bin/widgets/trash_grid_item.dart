import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/ui/components/common/item_shell.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'trash_list_item.dart';

/// Grid item widget for trash bin - displays trash item in grid view
class TrashGridItem extends StatelessWidget {
  final TrashItem item;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isDesktop;
  final VoidCallback onToggleSelection;
  final VoidCallback onEnterSelectionMode;
  final void Function(Offset) onContextMenu;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const TrashGridItem({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isSelectionMode,
    required this.isDesktop,
    required this.onToggleSelection,
    required this.onEnterSelectionMode,
    required this.onContextMenu,
    this.onTap,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GridItemShell(
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      isDesktopMode: isDesktop,
      onTap: isDesktop ? onToggleSelection : onTap,
      onDoubleTap: isDesktop ? onDoubleTap : null,
      onToggleSelection: onToggleSelection,
      onEnterSelectionMode: onEnterSelectionMode,
      onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TrashItemIcon(
                    originalPath: item.originalPath,
                    actualFilePath: item.actualFilePath,
                    displayName: item.displayNameValue,
                    size: 48,
                    isFolder: item.isFolder,
                    fillAvailable: true,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: GridZoomConstraints.gridItemNameAreaHeight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4.0, left: 4.0, right: 4.0),
              child: Text(
                item.displayNameValue,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: GridZoomConstraints.gridItemFilenameFontSize,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
