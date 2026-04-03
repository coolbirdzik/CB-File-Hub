import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/tab_manager/components/index.dart'
    as tab_components;
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

/// Manages all dialog operations for file/folder management
class DialogManager {
  /// Show dialog to add a tag to a specific file
  static void showAddTagToFile(BuildContext context, String filePath) {
    AppLogger.info('[ManageTags][DialogManager] showAddTagToFile',
        error: 'filePath=$filePath');
    tab_components.showAddTagToFileDialog(context, filePath);
  }

  /// Show dialog to delete a tag from a specific file
  static void showDeleteTag(
    BuildContext context,
    String filePath,
    List<String> tags,
  ) {
    tab_components.showDeleteTagDialog(context, filePath, tags);
  }

  /// Show dialog to remove tags from multiple selected files
  static void showRemoveTags(
    BuildContext context,
    List<String> selectedFilePaths,
  ) {
    tab_components.showRemoveTagsDialog(context, selectedFilePaths);
  }

  /// Show dialog to manage all tags in the current directory
  static void showManageAllTags(
    BuildContext context,
    List<String> allTags,
    String currentPath, {
    List<String>? selectedFiles,
  }) {
    if (selectedFiles != null && selectedFiles.isNotEmpty) {
      tab_components.showManageTagsDialog(
        context,
        allTags,
        currentPath,
        selectedFiles: selectedFiles,
      );
    } else {
      tab_components.showManageTagsDialog(
        context,
        allTags,
        currentPath,
      );
    }
  }

  /// Show confirmation dialog before deleting files/folders
  static Future<void> showDeleteConfirmation(
    BuildContext context, {
    required List<String> selectedFilePaths,
    required List<String> selectedFolderPaths,
    required FolderListBloc folderListBloc,
    required String currentPath,
    required VoidCallback onClearSelection,
  }) async {
    final l10n = AppLocalizations.of(context)!;

    final int fileCount = selectedFilePaths.length;
    final int folderCount = selectedFolderPaths.length;
    final int totalCount = fileCount + folderCount;
    final String itemType = fileCount > 0 && folderCount > 0
        ? l10n.items
        : fileCount > 0
            ? (fileCount == 1 ? l10n.file : l10n.files)
            : (folderCount == 1 ? l10n.folder : l10n.folders);

    return showDialog(
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
              // Delete files
              if (fileCount > 0) {
                BlocProvider.of<FolderListBloc>(context)
                    .add(FolderListDeleteFiles(selectedFilePaths));
              }

              // Delete folders
              if (folderCount > 0) {
                for (final folderPath in selectedFolderPaths) {
                  final folder = Directory(folderPath);
                  try {
                    // Check if folder exists and move to trash
                    if (folder.existsSync()) {
                      final trashManager = TrashManager();
                      trashManager.moveToTrash(folderPath);
                    }
                  } catch (e) {
                    debugPrint('Error moving folder to trash: $e');
                  }
                }

                // Refresh the folder list after deletion
                folderListBloc.add(FolderListLoad(currentPath));
              }

              RouteUtils.safePopDialog(context);
              onClearSelection();
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
