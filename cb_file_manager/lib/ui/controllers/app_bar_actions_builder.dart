import 'package:flutter/material.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/widgets/folder_app_bar_actions.dart';

/// Builds complete app bar actions for tabbed folder screens
///
/// Handles:
/// - Selection mode vs normal mode actions
/// - Integration with FolderAppBarActions
/// - Conditional action visibility based on state
class AppBarActionsBuilder {
  /// Builds app bar actions based on current state
  ///
  /// Returns empty list in selection mode, full actions in normal mode
  static List<Widget> buildActions({
    required BuildContext context,
    required SelectionState selectionState,
    required FolderListState folderListState,
    required String currentPath,
    required bool isNetworkPath,
    required Function(SortOption) onSortOptionSelected,
    required VoidCallback onViewModeToggled,
    required Function(ViewMode) onViewModeSelected,
    required VoidCallback onRefresh,
    required VoidCallback onSearchPressed,
    bool isSearchActive = false,
    required VoidCallback onSelectionModeToggled,
    required VoidCallback onManageTagsPressed,
    bool allowFileExtensionRename = false,
    ValueChanged<bool>? onAllowFileExtensionRenameChanged,
    required Function(int) onGridZoomChange,
    required VoidCallback onColumnSettingsPressed,
    required Function(dynamic)? onGalleryResult,
    required VoidCallback onPreviewPaneToggled,
    required bool isPreviewPaneVisible,
    required bool showPreviewModeOption,
  }) {
    // Always keep the action bar visible; selection actions are handled elsewhere.
    return FolderAppBarActions.buildActions(
      context: context,
      folderListState: folderListState,
      currentPath: currentPath,
      isNetworkPath: isNetworkPath,
      onSortOptionSelected: onSortOptionSelected,
      onViewModeToggled: onViewModeToggled,
      onViewModeSelected: onViewModeSelected,
      onRefresh: onRefresh,
      onSearchPressed: onSearchPressed,
      isSearchActive: isSearchActive,
      onSelectionModeToggled: onSelectionModeToggled,
      onManageTagsPressed: onManageTagsPressed,
      allowFileExtensionRename: allowFileExtensionRename,
      onAllowFileExtensionRenameChanged: onAllowFileExtensionRenameChanged,
      onGridZoomChange: onGridZoomChange,
      onColumnSettingsPressed: onColumnSettingsPressed,
      onPreviewPaneToggled: onPreviewPaneToggled,
      isPreviewPaneVisible: isPreviewPaneVisible,
      showPreviewModeOption: showPreviewModeOption,
      onGallerySelected: isNetworkPath
          ? null
          : (value) {
              if (onGalleryResult != null) {
                onGalleryResult(value);
              }
            },
    );
  }
}
