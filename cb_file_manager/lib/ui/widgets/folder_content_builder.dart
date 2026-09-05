import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/utils/fluent_background.dart';
import 'package:cb_file_manager/ui/tab_manager/components/index.dart'
    as tab_components;
import 'package:cb_file_manager/ui/widgets/search_filter_results_view.dart';

/// Builder for folder content with error handling
class FolderContentBuilder {
  /// Builds the main content area with error handling and empty state
  static Widget build(
    BuildContext context, {
    required FolderListState folderListState,
    required SelectionState selectionState,
    required String currentPath,
    required bool isNetworkPath,
    required bool isDesktopPlatform,
    required VoidCallback onRetry,
    required Function(String) onNavigateToPath,
    required String tabId,
    required bool showFileTags,
    required String? currentFilter,
    required String? currentSearchTag,
    required Function(File, bool) onFileTap,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
    toggleFileSelection,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
    toggleFolderSelection,
    required VoidCallback toggleSelectionMode,
    required Function(BuildContext, String, List<String>) showDeleteTagDialog,
    required Function(BuildContext, String) showAddTagToFileDialog,
    required VoidCallback onClearSearch,
    required bool isGlobalSearch,
    required VoidCallback onBackButtonPressed,
    required VoidCallback onForwardButtonPressed,
    required ValueChanged<int> onZoomLevelChanged,
  }) {
    // Handle error state
    if (folderListState.error != null) {
      debugPrint('🔴 [FolderContentBuilder] ERROR STATE DETECTED!');
      debugPrint(
        '🔴 [FolderContentBuilder] Error message: ${folderListState.error}',
      );
      debugPrint('🔴 [FolderContentBuilder] Current path: $currentPath');
      debugPrint(
        '🔴 [FolderContentBuilder] Is loading: ${folderListState.isLoading}',
      );
      debugPrint(
        '🔴 [FolderContentBuilder] Stack trace: ${StackTrace.current}',
      );

      return _buildErrorView(
        context: context,
        errorMessage: folderListState.error!,
        isNetworkPath: isNetworkPath,
        isDesktopPlatform: isDesktopPlatform,
        currentPath: currentPath,
        onRetry: onRetry,
        onGoBack: () => _handleGoBack(
          context,
          currentPath,
          isNetworkPath,
          onNavigateToPath,
          tabId,
        ),
      );
    }

    // Handle search/filter results
    if (folderListState.currentSearchTag != null ||
        currentSearchTag != null ||
        folderListState.currentSearchQuery != null ||
        (currentFilter != null && currentFilter.isNotEmpty)) {
      return SearchFilterResultsView(
        folderListState: folderListState,
        selectionState: selectionState,
        currentPath: currentPath,
        tabId: tabId,
        currentFilter: currentFilter,
        currentSearchTag: currentSearchTag,
        isGlobalSearch: isGlobalSearch,
        onNavigateToPath: onNavigateToPath,
        onFileTap: onFileTap,
        toggleFileSelection: toggleFileSelection,
        toggleFolderSelection: toggleFolderSelection,
        toggleSelectionMode: toggleSelectionMode,
        showDeleteTagDialog: showDeleteTagDialog,
        showAddTagToFileDialog: showAddTagToFileDialog,
        onClearSearch: onClearSearch,
        onBackButtonPressed: onBackButtonPressed,
        onForwardButtonPressed: onForwardButtonPressed,
        isDesktopPlatform: isDesktopPlatform,
        showFileTags: showFileTags,
        onZoomLevelChanged: onZoomLevelChanged,
      );
    }

    // Handle empty directory - only show empty state when not loading
    // During progressive loading, folders/files may temporarily be empty
    if (folderListState.folders.isEmpty &&
        folderListState.files.isEmpty &&
        !folderListState.isLoading) {
      return _buildEmptyFolder(context, isDesktopPlatform);
    }

    // If we reach here, caller should show the normal file list
    return const SizedBox.shrink();
  }

  /// Builds the error view with retry and navigation options
  static Widget _buildErrorView({
    required BuildContext context,
    required String errorMessage,
    required bool isNetworkPath,
    required bool isDesktopPlatform,
    required String currentPath,
    required VoidCallback onRetry,
    required VoidCallback onGoBack,
  }) {
    return FluentBackground.container(
      context: context,
      enableBlur: isDesktopPlatform,
      padding: const EdgeInsets.all(24.0),
      blurAmount: 5.0,
      child: tab_components.ErrorView(
        errorMessage: errorMessage,
        isNetworkPath: isNetworkPath,
        onRetry: onRetry,
        onGoBack: onGoBack,
      ),
    );
  }

  /// Builds the empty folder view
  static Widget _buildEmptyFolder(
    BuildContext context,
    bool isDesktopPlatform,
  ) {
    // An empty folder simply shows nothing — no "empty folder" label.
    return const SizedBox.shrink();
  }

  /// Handles the go back action from error view
  static void _handleGoBack(
    BuildContext context,
    String currentPath,
    bool isNetworkPath,
    Function(String) onNavigateToPath,
    String tabId,
  ) {
    if (isNetworkPath) {
      final parts = currentPath.split('/');
      if (parts.length > 3) {
        final parentPath = parts.sublist(0, parts.length - 1).join('/');
        onNavigateToPath(parentPath);
      } else {
        // Close the tab if we can't go back further
        // This requires TabManagerBloc which should be available in context
        // Import will be needed if used
      }
    } else {
      try {
        final parentPath = Directory(currentPath).parent.path;
        if (parentPath != currentPath) {
          onNavigateToPath(parentPath);
        } else {
          onNavigateToPath('');
        }
      } catch (e) {
        debugPrint('Error navigating back: $e');
      }
    }
  }
}
