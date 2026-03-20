import 'package:flutter/material.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';

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
    required VoidCallback onSelectionModeToggled,
    required VoidCallback onManageTagsPressed,
    required Function(int) onGridZoomChange,
    required VoidCallback onColumnSettingsPressed,
    required Function(String)? onGallerySelected,
    required VoidCallback onPreviewPaneToggled,
    required bool isPreviewPaneVisible,
    required bool showPreviewModeOption,
  }) {
    return SharedActionBar.buildCommonActions(
      context: context,
      onSearchPressed: onSearchPressed,
      onSortOptionSelected: onSortOptionSelected,
      currentSortOption: folderListState.sortOption,
      viewMode: folderListState.viewMode,
      onViewModeToggled: onViewModeToggled,
      onViewModeSelected: onViewModeSelected,
      onRefresh: onRefresh,
      onGridSizePressed: folderListState.viewMode == ViewMode.grid ||
              folderListState.viewMode == ViewMode.gridPreview
          ? () => SharedActionBar.showGridSizeDialog(
                context,
                currentGridSize: folderListState.gridZoomLevel,
                onApply: onGridZoomChange,
                sizeMode: GridSizeMode.referenceWidth,
              )
          : null,
      onColumnSettingsPressed: folderListState.viewMode == ViewMode.details
          ? onColumnSettingsPressed
          : null,
      onPreviewPaneToggled: onPreviewPaneToggled,
      isPreviewPaneVisible: isPreviewPaneVisible,
      showPreviewModeOption: showPreviewModeOption,
      onSelectionModeToggled: onSelectionModeToggled,
      onManageTagsPressed: onManageTagsPressed,
      onGallerySelected: isNetworkPath ? null : onGallerySelected,
      currentPath: currentPath,
    );
  }
}
