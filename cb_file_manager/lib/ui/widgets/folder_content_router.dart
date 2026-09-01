import 'dart:io';

import 'package:flutter/material.dart';

import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/tab_manager/components/index.dart'
    as tab_components;
import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';
import 'package:cb_file_manager/ui/screens/system_screen_router.dart';
import 'package:cb_file_manager/ui/utils/fluent_background.dart';
import 'package:cb_file_manager/ui/widgets/app_progress_indicator.dart';
import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';

/// Router for folder content that handles different path types
class FolderContentRouter {
  /// Build content for the current path, routing to appropriate views
  static Widget buildForPath({
    required BuildContext context,
    required String currentPath,
    required String tabId,
    required FolderListBloc folderListBloc,
    required SelectionState selectionState,
    required FolderListState folderListState,
    required bool isNetworkPath,
    required TextEditingController pathController,
    required Function(String) onPathChanged,
    required VoidCallback onBackButtonPressed,
    required VoidCallback onForwardButtonPressed,
    required bool isLazyLoadingDrives,
    required Widget Function(FolderListState, SelectionState, bool)
        contentBuilder,
  }) {
    // Drive view (Windows only)
    if (currentPath.isEmpty && Platform.isWindows) {
      return _buildDriveView(
        tabId: tabId,
        folderListBloc: folderListBloc,
        onPathChanged: onPathChanged,
        onBackButtonPressed: onBackButtonPressed,
        onForwardButtonPressed: onForwardButtonPressed,
        isLazyLoading: isLazyLoadingDrives,
      );
    }

    // Route system paths except the special inline tag-search variant
    if (currentPath.startsWith('#') &&
        !currentPath.startsWith('#search?tag=') &&
        !ArchivePathUtils.isArchiveBrowsePath(currentPath)) {
      final systemWidget = _buildSystemScreen(
        context: context,
        currentPath: currentPath,
        tabId: tabId,
      );
      if (systemWidget != null) {
        return systemWidget;
      }
    }

    // Folder/browser UI (default and for #search?tag=...)
    return contentBuilder(folderListState, selectionState, isNetworkPath);
  }

  /// Build drive view for Windows
  static Widget _buildDriveView({
    required String tabId,
    required FolderListBloc folderListBloc,
    required Function(String) onPathChanged,
    required VoidCallback onBackButtonPressed,
    required VoidCallback onForwardButtonPressed,
    required bool isLazyLoading,
  }) {
    return tab_components.DriveView(
      tabId: tabId,
      folderListBloc: folderListBloc,
      onPathChanged: onPathChanged,
      onBackButtonPressed: onBackButtonPressed,
      onForwardButtonPressed: onForwardButtonPressed,
      isLazyLoading: isLazyLoading,
    );
  }

  /// Build system screen for special paths like #tags
  static Widget? _buildSystemScreen({
    required BuildContext context,
    required String currentPath,
    required String tabId,
  }) {
    return SystemScreenRouter.routeSystemPath(
      context,
      currentPath,
      tabId,
    );
  }

  /// Build the body content with loading states
  static Widget buildBody({
    required BuildContext context,
    required FolderListState state,
    required SelectionState selectionState,
    required bool isNetworkPath,
    required bool isDesktopPlatform,
    required bool isRefreshing,
    required Widget Function(
            BuildContext, FolderListState, SelectionState, bool)
        mainContentBuilder,
  }) {
    // Apply frame timing optimization before heavy UI operations
    FrameTimingOptimizer().optimizeBeforeHeavyOperation();

    // Show content as soon as we have any files/folders (lazy loading)
    // Only show skeleton when truly empty and loading
    final bool hasContent = state.folders.isNotEmpty || state.files.isNotEmpty;
    // Top bar: only for initial loads (no existing content yet).
    // Refresh operations show at the bottom and don't affect content layout.
    final bool shouldShowSkeleton = !hasContent &&
        state.isLoading &&
        !state.isRefreshing &&
        state.error == null &&
        state.searchResults.isEmpty &&
        state.currentSearchTag == null &&
        state.currentSearchQuery == null;

    return Column(
      children: [
        // Top progress bar only when loading with no content yet (initial load)
        if (state.isLoading && !state.isRefreshing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4.0),
            child: AppProgressIndicatorBeautiful(),
          ),
        Expanded(
          child: FluentBackground.container(
            context: context,
            enableBlur: isDesktopPlatform,
            child: shouldShowSkeleton
                ? const SizedBox.shrink() // Show an empty space while loading
                : mainContentBuilder(
                    context, state, selectionState, isNetworkPath),
          ),
        ),
      ],
    );
  }

  /// Build main content with error handling
  static Widget buildMainContent({
    required BuildContext context,
    required FolderListState state,
    required SelectionState selectionState,
    required bool isNetworkPath,
    required bool isDesktopPlatform,
    required String currentPath,
    required FolderListBloc folderListBloc,
    required Function(String) onNavigateToPath,
    required Widget Function(
            BuildContext, FolderListState, SelectionState, bool)
        folderAndFileListContentBuilder,
  }) {
    if (state.error != null) {
      return _buildErrorView(
        context: context,
        error: state.error!,
        isNetworkPath: isNetworkPath,
        isDesktopPlatform: isDesktopPlatform,
        currentPath: currentPath,
        folderListBloc: folderListBloc,
        onNavigateToPath: onNavigateToPath,
      );
    }

    // Show files/folders even while loading (progressive loading)
    return folderAndFileListContentBuilder(
        context, state, selectionState, isNetworkPath);
  }

  /// Build error view with retry and go back options
  static Widget _buildErrorView({
    required BuildContext context,
    required String error,
    required bool isNetworkPath,
    required bool isDesktopPlatform,
    required String currentPath,
    required FolderListBloc folderListBloc,
    required Function(String) onNavigateToPath,
  }) {
    return FluentBackground.container(
      context: context,
      enableBlur: isDesktopPlatform,
      padding: const EdgeInsets.all(24.0),
      blurAmount: 5.0,
      child: tab_components.ErrorView(
        errorMessage: error,
        isNetworkPath: isNetworkPath,
        onRetry: () {
          folderListBloc.add(FolderListLoad(currentPath));
        },
        onGoBack: () {
          if (isNetworkPath) {
            final parts = currentPath.split('/');
            if (parts.length > 3) {
              final parentPath = parts.sublist(0, parts.length - 1).join('/');
              onNavigateToPath(parentPath);
            } else {
              // Note: This requires TabManagerBloc to be available in context
              // The calling code should handle tab closing
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
        },
      ),
    );
  }
}
