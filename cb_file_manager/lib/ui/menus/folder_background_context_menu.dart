import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/tab_manager/components/folder_context_menu.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';

/// Handles displaying context menu for folder background (empty areas)
class FolderBackgroundContextMenu {
  /// Show context menu at the specified position
  static void show({
    required BuildContext context,
    required Offset globalPosition,
    required FolderListBloc folderListBloc,
    required String currentPath,
    required ViewMode currentViewMode,
    required SortOption currentSortOption,
    required Function(ViewMode) onViewModeChanged,
    required VoidCallback onRefresh,
    required Function(String) onCreateFolder,
    required Future<void> Function(SortOption) onSortOptionSaved,
    InlineRenameController? inlineRenameController,
    ValueChanged<String>? onAfterFileCreated,
  }) {
    FolderContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      folderListBloc: folderListBloc,
      currentPath: currentPath,
      currentViewMode: currentViewMode,
      currentSortOption: currentSortOption,
      onViewModeChanged: onViewModeChanged,
      onRefresh: onRefresh,
      onCreateFolder: (String folderName) async {
        final String newFolderPath =
            '$currentPath${Platform.pathSeparator}$folderName';

        final directory = Directory(newFolderPath);
        try {
          await directory.create();
          folderListBloc.add(FolderListLoad(currentPath));
        } catch (error) {
          if (context.mounted) {
            AppToast.error(
              context,
              AppLocalizations.of(context)!.errorCreatingFolder('$error'),
            );
          }
        }
      },
      onSortOptionSaved: onSortOptionSaved,
      inlineRenameController: inlineRenameController,
      onAfterFileCreated: onAfterFileCreated,
    );
  }
}
