import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/tab_manager/components/index.dart'
    as tab_components;

/// Manager for search and filter operations in folder list screens
///
/// This class provides static methods for:
/// - Showing search tips to users
/// - Building search results views
/// - Building filtered file views
class SearchFilterManager {
  /// Show search tip dialog to first-time users
  ///
  /// This displays a helpful dialog explaining how to use the search feature,
  /// and marks it as shown so it won't appear again.
  static Future<void> showSearchTip(BuildContext context) async {
    final prefs = UserPreferences.instance;
    await prefs.init();
    final shown = await prefs.getSearchTipShown();
    if (!shown && context.mounted) {
      await tab_components.showSearchTipsDialog(context);
      await prefs.setSearchTipShown(true);
    }
  }

  /// Build search results view
  ///
  /// Creates a widget displaying search results with proper selection handling
  /// and navigation capabilities.
  static Widget buildSearchResults({
    required BuildContext context,
    required FolderListState state,
    required SelectionState selectionState,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
    toggleFileSelection,
    required VoidCallback toggleSelectionMode,
    required Function(BuildContext, String, List<String>) showDeleteTagDialog,
    required Function(BuildContext, String) showAddTagToFileDialog,
    required Function(String) onFolderTap,
    required Function(File, bool) onFileTap,
    required VoidCallback onClearSearch,
    required VoidCallback onBackButtonPressed,
    required VoidCallback onForwardButtonPressed,
    required bool isGlobalSearch,
    required String currentPath,
    required String tabId,
  }) {
    return tab_components.SearchResultsView(
      state: state,
      isSelectionMode: selectionState.isSelectionMode,
      selectedFiles: selectionState.allSelectedPaths,
      lastSelectedPath: selectionState.lastSelectedPath,
      toggleFileSelection: toggleFileSelection,
      toggleSelectionMode: toggleSelectionMode,
      showDeleteTagDialog: showDeleteTagDialog,
      showAddTagToFileDialog: showAddTagToFileDialog,
      onClearSearch: onClearSearch,
      onFolderTap: onFolderTap,
      onFileTap: onFileTap,
      onBackButtonPressed: onBackButtonPressed,
      onForwardButtonPressed: onForwardButtonPressed,
      onLoadMore: () {
        context.read<FolderListBloc>().add(const LoadMoreSearchResults());
      },
    );
  }

  /// Build filtered view
  ///
  /// Creates a widget displaying filtered files based on current filter criteria.
  static Widget buildFilteredView({
    required BuildContext context,
    required FolderListState state,
    required SelectionState selectionState,
    required String currentFilter,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
    toggleFileSelection,
    required VoidCallback toggleSelectionMode,
    required Function(BuildContext, String, List<String>) showDeleteTagDialog,
    required Function(BuildContext, String) showAddTagToFileDialog,
    required bool showFileTags,
    required VoidCallback onClearFilter,
  }) {
    // This is a placeholder - the actual implementation would need to be
    // extracted from the main screen's filtered view logic
    return const SizedBox.shrink();
  }
}
