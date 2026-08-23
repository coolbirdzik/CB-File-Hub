import 'package:flutter/material.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/utils/view_mode_utils.dart';

/// Builder for folder app bar actions
class FolderAppBarActions {
  /// Build action widgets for the app bar
  static List<Widget> buildActions({
    required BuildContext context,
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
    required Function(String)? onGallerySelected,
    VoidCallback? onPreviewPaneToggled,
    required bool isPreviewPaneVisible,
    required bool showDesktopViewModes,
  }) {
    return SharedActionBar.buildCommonActions(
      context: context,
      onSearchPressed: onSearchPressed,
      isSearchActive: isSearchActive,
      onSortOptionSelected: onSortOptionSelected,
      currentSortOption: folderListState.sortOption,
      viewMode: folderListState.viewMode,
      onViewModeToggled: onViewModeToggled,
      onViewModeSelected: onViewModeSelected,
      onRefresh: onRefresh,
      currentGridZoomLevel: ViewModeUtils.isGridLike(folderListState.viewMode)
          ? folderListState.gridZoomLevel
          : null,
      onGridZoomChanged: onGridZoomChange,
      onColumnSettingsPressed: folderListState.viewMode == ViewMode.details
          ? onColumnSettingsPressed
          : null,
      onPreviewPaneToggled: onPreviewPaneToggled,
      isPreviewPaneVisible: isPreviewPaneVisible,
      showDesktopViewModes: showDesktopViewModes,
      onSelectionModeToggled: onSelectionModeToggled,
      onManageTagsPressed: onManageTagsPressed,
      allowFileExtensionRename: allowFileExtensionRename,
      onAllowFileExtensionRenameChanged: onAllowFileExtensionRenameChanged,
      onGallerySelected: isNetworkPath ? null : onGallerySelected,
      currentPath: currentPath,
    );
  }
}
