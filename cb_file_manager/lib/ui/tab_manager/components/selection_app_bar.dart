import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'tag_dialogs.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';

/// AppBar component displayed when in selection mode
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final int selectedFileCount;
  final int selectedFolderCount;
  final VoidCallback onClearSelection;
  final List<String> selectedFilePaths;
  final List<String> selectedFolderPaths;
  final Function(BuildContext) showRemoveTagsDialog;
  final Function(BuildContext) showManageAllTagsDialog;
  final Function(BuildContext) showDeleteConfirmationDialog;
  final bool isNetworkPath;

  const SelectionAppBar({
    Key? key,
    required this.selectedCount,
    required this.selectedFileCount,
    required this.selectedFolderCount,
    required this.onClearSelection,
    required this.selectedFilePaths,
    required this.selectedFolderPaths,
    required this.showRemoveTagsDialog,
    required this.showManageAllTagsDialog,
    required this.showDeleteConfirmationDialog,
    this.isNetworkPath = false,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Calculate the actual count from the lists or use provided counts
    final int fileCount = selectedFileCount;
    final int folderCount = selectedFolderCount;
    final int actualCount = fileCount + folderCount;

    // Warn if our count doesn't match what was passed in
    if (selectedCount != actualCount) {
      debugPrint(
          "⚠️ SelectionAppBar - Count mismatch: passed=$selectedCount, actual=$actualCount (files=$fileCount, folders=$folderCount)");
    }

    return AppBar(
      title: Text(l10n.itemsSelected(selectedCount)),
      leading: IconButton(
        icon: const Icon(PhosphorIconsLight.x),
        onPressed: onClearSelection,
        tooltip: l10n.cancel,
      ),
      actions: [
        // Show tag management options if we have files selected
        if (fileCount > 0 &&
            !isNetworkPath) // Don't show tag options for network paths
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add_tags') {
                showBatchAddTagDialog(context, selectedFilePaths);
              } else if (value == 'remove_tags') {
                showRemoveTagsDialog(context);
              } else if (value == 'manage_all_tags') {
                showManageAllTagsDialog(context);
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'add_tags',
                child: ListTile(
                  leading: const Icon(PhosphorIconsLight.plusCircle),
                  title: Text(l10n.addTag),
                ),
              ),
              PopupMenuItem<String>(
                value: 'remove_tags',
                child: ListTile(
                  leading: const Icon(PhosphorIconsLight.xCircle),
                  title: Text(l10n.removeTag),
                ),
              ),
              PopupMenuItem<String>(
                value: 'manage_all_tags',
                child: ListTile(
                  leading: const Icon(PhosphorIconsLight.gear),
                  title: Text(l10n.manageTags),
                ),
              ),
            ],
            icon: const Icon(PhosphorIconsLight.shoppingBagOpen),
            tooltip: l10n.manageTags,
          ),

        // Delete button always shown
        IconButton(
          icon: const Icon(PhosphorIconsLight.trash),
          onPressed: () => showDeleteConfirmationDialog(context),
          tooltip: l10n.moveToTrash,
        ),
      ],
    );
  }
}
