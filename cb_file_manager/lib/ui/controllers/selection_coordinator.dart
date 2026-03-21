import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/ui/tab_manager/components/index.dart'
    as tab_components;

/// Controller for coordinating selection operations in tabbed folder screens
class SelectionCoordinator {
  final SelectionBloc selectionBloc;
  final FolderListBloc folderListBloc;
  final Function() clearKeyboardFocus;

  SelectionCoordinator({
    required this.selectionBloc,
    required this.folderListBloc,
    required this.clearKeyboardFocus,
  });

  /// Toggle selection mode on/off
  void toggleSelectionMode({bool? forceValue}) {
    selectionBloc.add(ToggleSelectionMode(forceValue: forceValue));
  }

  /// Toggle file selection with support for shift and ctrl modifiers
  void toggleFileSelection(
    String filePath, {
    bool shiftSelect = false,
    bool ctrlSelect = false,
  }) {
    if (!shiftSelect) {
      // Simple selection, use the SelectionBloc directly
      selectionBloc.add(ToggleFileSelection(
        filePath,
        shiftSelect: shiftSelect,
        ctrlSelect: ctrlSelect,
      ));
    } else {
      // Range selection requires knowledge of all items in current view
      // Get the current selection state
      final selectionState = selectionBloc.state;

      // If no last selected path, treat as normal selection
      if (selectionState.lastSelectedPath == null) {
        selectionBloc.add(ToggleFileSelection(
          filePath,
          shiftSelect: false,
          ctrlSelect: ctrlSelect,
        ));
        return;
      }

      // Get lists of all paths for selection range
      final List<String> allFolderPaths =
          folderListBloc.state.folders.map((f) => f.path).toList();
      final List<String> allFilePaths =
          folderListBloc.state.files.map((f) => f.path).toList();
      final List<String> allPaths = [...allFolderPaths, ...allFilePaths];

      // Find indices
      final int currentIndex = allPaths.indexOf(filePath);
      final int lastIndex = allPaths.indexOf(selectionState.lastSelectedPath!);

      if (currentIndex != -1 && lastIndex != -1) {
        // Calculate the range
        final Set<String> filesToSelect = {};
        final Set<String> foldersToSelect = {};

        final int startIndex = min(currentIndex, lastIndex);
        final int endIndex = max(currentIndex, lastIndex);

        // Add all items in the range to appropriate sets
        for (int i = startIndex; i <= endIndex; i++) {
          final String pathInRange = allPaths[i];
          if (allFolderPaths.contains(pathInRange)) {
            foldersToSelect.add(pathInRange);
          } else {
            filesToSelect.add(pathInRange);
          }
        }

        // Send bulk selection event
        selectionBloc.add(SelectItemsInRect(
          folderPaths: foldersToSelect,
          filePaths: filesToSelect,
          isCtrlPressed: ctrlSelect,
          isShiftPressed: true,
        ));
      }
    }
  }

  /// Toggle folder selection with support for shift and ctrl modifiers
  void toggleFolderSelection(
    String folderPath, {
    bool shiftSelect = false,
    bool ctrlSelect = false,
  }) {
    if (!shiftSelect) {
      // Simple selection, use the SelectionBloc directly
      selectionBloc.add(ToggleFolderSelection(
        folderPath,
        shiftSelect: shiftSelect,
        ctrlSelect: ctrlSelect,
      ));
    } else {
      // Range selection requires knowledge of all items in current view
      // Get the current selection state
      final selectionState = selectionBloc.state;

      // If no last selected path, treat as normal selection
      if (selectionState.lastSelectedPath == null) {
        selectionBloc.add(ToggleFolderSelection(
          folderPath,
          shiftSelect: false,
          ctrlSelect: ctrlSelect,
        ));
        return;
      }

      // Get lists of all paths for selection range
      final List<String> allFolderPaths =
          folderListBloc.state.folders.map((f) => f.path).toList();
      final List<String> allFilePaths =
          folderListBloc.state.files.map((f) => f.path).toList();
      final List<String> allPaths = [...allFolderPaths, ...allFilePaths];

      // Find indices
      final int currentIndex = allPaths.indexOf(folderPath);
      final int lastIndex = allPaths.indexOf(selectionState.lastSelectedPath!);

      if (currentIndex != -1 && lastIndex != -1) {
        // Calculate the range
        final Set<String> filesToSelect = {};
        final Set<String> foldersToSelect = {};

        final int startIndex = min(currentIndex, lastIndex);
        final int endIndex = max(currentIndex, lastIndex);

        // Add all items in the range to appropriate sets
        for (int i = startIndex; i <= endIndex; i++) {
          final String pathInRange = allPaths[i];
          if (allFolderPaths.contains(pathInRange)) {
            foldersToSelect.add(pathInRange);
          } else {
            filesToSelect.add(pathInRange);
          }
        }

        // Send bulk selection event
        selectionBloc.add(SelectItemsInRect(
          folderPaths: foldersToSelect,
          filePaths: filesToSelect,
          isCtrlPressed: ctrlSelect,
          isShiftPressed: true,
        ));
      }
    }
  }

  /// Clear all selections
  void clearSelection() {
    selectionBloc.add(ClearSelection());
    clearKeyboardFocus();
  }

  /// Show dialog to remove tags from selected files
  void showRemoveTagsDialog(BuildContext context) {
    final selectionState = selectionBloc.state;
    tab_components.showRemoveTagsDialog(
        context, selectionState.selectedFilePaths.toList());
  }

  /// Show dialog to manage all tags for selected files or current folder
  void showManageAllTagsDialog(BuildContext context, String currentPath) {
    final selectionState = selectionBloc.state;

    if (selectionState.isSelectionMode &&
        selectionState.selectedFilePaths.isNotEmpty) {
      tab_components.showManageTagsDialog(
        context,
        folderListBloc.state.allTags.toList(),
        currentPath,
        selectedFiles: selectionState.selectedFilePaths.toList(),
      );
    } else {
      tab_components.showManageTagsDialog(
        context,
        folderListBloc.state.allTags.toList(),
        currentPath,
      );
    }
  }

  /// Show confirmation dialog before deleting selected items
  void showDeleteConfirmationDialog(
    BuildContext context,
    String currentPath,
    VoidCallback onRefresh,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final selectionState = selectionBloc.state;

    final int fileCount = selectionState.selectedFilePaths.length;
    final int folderCount = selectionState.selectedFolderPaths.length;
    final int totalCount = fileCount + folderCount;
    final String itemType = fileCount > 0 && folderCount > 0
        ? l10n.items
        : fileCount > 0
            ? (fileCount == 1 ? l10n.file : l10n.files)
            : (folderCount == 1 ? l10n.folder : l10n.folders);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.moveItemsToTrashConfirmation(totalCount, itemType)),
        content: Text(l10n.moveItemsToTrashDescription),
        actions: [
          TextButton(
            onPressed: () {
              RouteUtils.safePopDialog(context);
            },
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              folderListBloc.add(
                FolderListDeleteItems(
                  filePaths: selectionState.selectedFilePaths.toList(),
                  folderPaths: selectionState.selectedFolderPaths.toList(),
                  permanent: false,
                ),
              );

              RouteUtils.safePopDialog(context);
              clearSelection();
            },
            child: Text(
              l10n.moveToTrash,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
