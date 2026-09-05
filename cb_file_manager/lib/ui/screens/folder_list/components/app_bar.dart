import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/dialogs/delete_confirmation_dialog.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/tab_manager/components/tag_dialogs.dart';
import 'package:cb_file_manager/helpers/files/file_icon_helper.dart';
import 'package:path/path.dart' as path;
import 'package:phosphor_flutter/phosphor_flutter.dart';

class FolderListAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String currentPath;
  final bool isSelectionMode;
  final bool isGridView;
  final List<String> selectedFiles;
  final List<String> allTags;
  final Function() toggleViewMode;
  final Function() toggleSelectionMode;
  final Function() clearSelection;
  final Function() showSearchScreen;
  final Function() refresh;
  final Function(int) setGridZoomLevel;
  final int currentGridZoomLevel;

  const FolderListAppBar({
    super.key,
    required this.currentPath,
    required this.isSelectionMode,
    required this.isGridView,
    required this.selectedFiles,
    required this.allTags,
    required this.toggleViewMode,
    required this.toggleSelectionMode,
    required this.clearSelection,
    required this.showSearchScreen,
    required this.refresh,
    required this.setGridZoomLevel,
    required this.currentGridZoomLevel,
  });

  @override
  Widget build(BuildContext context) {
    // Get the last part of the path for the title
    final String title = isSelectionMode
        ? '${selectedFiles.length} selected'
        : currentPath.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

    return AppBar(
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 18),
      ),
      centerTitle: false,
      elevation: 0,
      actions: _buildAppBarActions(context),
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (isSelectionMode) {
      return [
        // Grid size slider when in grid view and selection mode
        if (isGridView)
          Container(
            width: 150,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Semantics(
              container: true,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.0,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6.0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14.0,
                  ),
                  valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
                  valueIndicatorTextStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.0,
                  ),
                ),
                child: Slider(
                  // Invert: right = larger items (fewer columns).
                  // display = (2 + 5) - zoom; convert back on change.
                  value: (7 - currentGridZoomLevel).toDouble(),
                  min: 2,
                  max: 5,
                  divisions: 3,
                  onChanged: (value) => setGridZoomLevel(7 - value.toInt()),
                ),
              ),
            ),
          ),
        // Action buttons for selection mode
        TextButton.icon(
          icon: const Icon(PhosphorIconsLight.plusCircle, size: 18),
          label: const Text('Tag'),
          onPressed: () => showBatchAddTagDialog(context, selectedFiles),
        ),
        TextButton.icon(
          icon: const Icon(PhosphorIconsLight.trash, size: 18),
          label: const Text('Delete'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () async {
            final l10n = AppLocalizations.of(context);
            if (l10n == null) return;

            final totalCount = selectedFiles.length;
            final firstItemName = path.basename(selectedFiles.first);

            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => DeleteConfirmationDialog(
                title: l10n.deleteTitle,
                message: totalCount == 1
                    ? l10n.moveToTrashConfirmMessage(firstItemName)
                    : l10n.moveItemsToTrashConfirmation(totalCount, l10n.items),
                confirmText: l10n.deleteTitle,
                cancelText: l10n.cancel,
                previewPaths: selectedFiles.take(4).toList(),
              ),
            );

            if (confirmed == true && context.mounted) {
              BlocProvider.of<FolderListBloc>(
                context,
              ).add(FolderListDeleteFiles(selectedFiles));
              toggleSelectionMode();
            }
          },
        ),
        IconButton(
          icon: const Icon(PhosphorIconsLight.x, size: 24),
          tooltip: 'Cancel selection',
          onPressed: clearSelection,
        ),
        const SizedBox(width: 8),
      ];
    } else {
      return [
        // View toggle button
        IconButton(
          icon: Icon(
            isGridView
                ? PhosphorIconsLight.list
                : PhosphorIconsLight.squaresFour,
            size: 24,
          ),
          tooltip: isGridView ? 'Switch to list view' : 'Switch to grid view',
          onPressed: toggleViewMode,
        ),
        // Grid size slider when in grid view
        if (isGridView)
          Container(
            width: 120,
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Semantics(
              container: true,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.0,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6.0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14.0,
                  ),
                ),
                child: Slider(
                  // Invert: right = larger items (fewer columns).
                  value: (7 - currentGridZoomLevel).toDouble(),
                  min: 2,
                  max: 5,
                  divisions: 3,
                  onChanged: (value) => setGridZoomLevel(7 - value.toInt()),
                ),
              ),
            ),
          ),
        // Search button
        IconButton(
          icon: const Icon(PhosphorIconsLight.magnifyingGlass, size: 24),
          tooltip: 'Search',
          onPressed: showSearchScreen,
        ),
        // More actions menu
        PopupMenuButton<String>(
          icon: const Icon(PhosphorIconsLight.dotsThreeVertical, size: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onSelected: (value) async {
            switch (value) {
              case 'refresh':
                refresh();
                break;
              case 'select_all':
                toggleSelectionMode();
                break;
              case 'manage_tags':
                showManageTagsDialog(context, allTags, currentPath);
                break;
              case 'debug_apk':
                await FileIconHelper.debugApkIcons();
                if (context.mounted) {
                  AppToast.info(
                    context,
                    'APK icon cache cleared. Check console for debug info.',
                  );
                }
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'refresh',
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.arrowsClockwise,
                    size: 20,
                    color: theme.iconTheme.color,
                  ),
                  const SizedBox(width: 12),
                  const Text('Refresh'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'select_all',
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.checkSquare,
                    size: 20,
                    color: theme.iconTheme.color,
                  ),
                  const SizedBox(width: 12),
                  const Text('Select All'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'manage_tags',
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.tag,
                    size: 20,
                    color: theme.iconTheme.color,
                  ),
                  const SizedBox(width: 12),
                  const Text('Manage Tags'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'debug_apk',
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.gear,
                    size: 20,
                    color: theme.iconTheme.color,
                  ),
                  const SizedBox(width: 12),
                  const Text('Debug APK Icons'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ];
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
