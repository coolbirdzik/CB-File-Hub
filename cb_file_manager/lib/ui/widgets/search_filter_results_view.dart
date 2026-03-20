import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/index.dart'
    as folder_list_components;
import 'package:cb_file_manager/ui/tab_manager/components/index.dart'
    as tab_components;
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/utils/fluent_background.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';

/// Widget to display search and filter results
class SearchFilterResultsView extends StatelessWidget {
  final FolderListState folderListState;
  final SelectionState selectionState;
  final String currentPath;
  final String tabId;
  final String? currentFilter;
  final String? currentSearchTag;
  final bool isGlobalSearch;
  final Function(String) onNavigateToPath;
  final Function(File, bool) onFileTap;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;
  final VoidCallback toggleSelectionMode;
  final Function(BuildContext, String, List<String>) showDeleteTagDialog;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final VoidCallback onClearSearch;
  final VoidCallback onBackButtonPressed;
  final VoidCallback onForwardButtonPressed;
  final bool showFileTags;
  final ValueChanged<int> onZoomLevelChanged;

  const SearchFilterResultsView({
    Key? key,
    required this.folderListState,
    required this.selectionState,
    required this.currentPath,
    required this.tabId,
    required this.currentFilter,
    required this.currentSearchTag,
    required this.isGlobalSearch,
    required this.onNavigateToPath,
    required this.onFileTap,
    required this.toggleFileSelection,
    required this.toggleSelectionMode,
    required this.showDeleteTagDialog,
    required this.showAddTagToFileDialog,
    required this.onClearSearch,
    required this.onBackButtonPressed,
    required this.onForwardButtonPressed,
    required this.showFileTags,
    required this.onZoomLevelChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Handle search results (tag or query search)
    if (currentSearchTag != null ||
        folderListState.currentSearchQuery != null) {
      return _buildSearchResults(context);
    }

    // Handle filter results
    if (currentFilter != null && currentFilter!.isNotEmpty) {
      return _buildFilterResults(context);
    }

    // Default: should not reach here
    return const SizedBox.shrink();
  }

  Widget _buildSearchResults(BuildContext context) {
    final bool shouldShowLoading = folderListState.isLoading ||
        (currentPath.startsWith('#search?tag=') &&
            currentSearchTag != null &&
            folderListState.searchResults.isEmpty &&
            folderListState.currentSearchTag == null &&
            folderListState.currentSearchQuery == null &&
            folderListState.error == null);

    if (shouldShowLoading && folderListState.searchResults.isEmpty) {
      // If we have an error, don't show loading
      if (folderListState.error != null) {
        return const SizedBox.shrink();
      }
      // User requested to hide the centered loading spinner and only show the top progress bar
      return const SizedBox.shrink();
    }

    if (folderListState.searchResults.isNotEmpty) {
      return tab_components.SearchResultsView(
        state: folderListState,
        isSelectionMode: selectionState.isSelectionMode,
        selectedFiles: selectionState.selectedFilePaths.toList(),
        toggleFileSelection: toggleFileSelection,
        toggleSelectionMode: toggleSelectionMode,
        showDeleteTagDialog: showDeleteTagDialog,
        showAddTagToFileDialog: showAddTagToFileDialog,
        onClearSearch: () {
          // If this is a search tag tab, close it instead of clearing search
          if (currentPath.startsWith('#search?tag=')) {
            final tabManagerBloc = BlocProvider.of<TabManagerBloc>(context);
            tabManagerBloc.add(CloseTab(tabId));
            return;
          }

          onClearSearch();
        },
        onFolderTap: onNavigateToPath,
        onFileTap: onFileTap,
        onBackButtonPressed: onBackButtonPressed,
        onForwardButtonPressed: onForwardButtonPressed,
        onLoadMore: () {
          context.read<FolderListBloc>().add(const LoadMoreSearchResults());
        },
      );
    } else {
      return _buildNoSearchResults(context);
    }
  }

  Widget _buildNoSearchResults(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final noResultsMessage = () {
      if (currentSearchTag != null) {
        final tag = currentSearchTag!;
        return isGlobalSearch
            ? l10n.noFilesFoundTagGlobal({'tag': tag})
            : l10n.noFilesFoundTag({'tag': tag});
      }
      return l10n.noFilesFoundQuery(
          {'query': folderListState.currentSearchQuery ?? ''});
    }();

    return Column(
      children: [
        FluentBackground(
          blurAmount: 8.0,
          opacity: 0.7,
          backgroundColor: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.7),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              children: [
                Icon(
                  currentSearchTag != null
                      ? PhosphorIconsLight.shoppingBagOpen
                      : PhosphorIconsLight.magnifyingGlass,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(noResultsMessage),
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsLight.x),
                  onPressed: () {
                    // If this is a search tag tab, close it instead of clearing search
                    if (currentPath.startsWith('#search?tag=')) {
                      final tabManagerBloc =
                          BlocProvider.of<TabManagerBloc>(context);
                      tabManagerBloc.add(CloseTab(tabId));
                      return;
                    }

                    onClearSearch();
                  },
                  tooltip: l10n.clearSearch,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(PhosphorIconsLight.magnifyingGlass,
                    size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  l10n.emptyFolder,
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterResults(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayFilter = _displayFilterLabel(context, currentFilter!);

    return Column(
      children: [
        // Filter indicator with clear button
        Container(
          padding: const EdgeInsets.all(8.0),
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3),
          child: Row(
            children: [
              const Icon(PhosphorIconsLight.funnelSimple, size: 16),
              const SizedBox(width: 8),
              Text(l10n.filteredBy(displayFilter)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  context
                      .read<FolderListBloc>()
                      .add(const ClearSearchAndFilters());
                },
                child: Text(l10n.clearFilter),
              ),
            ],
          ),
        ),
        // Show filtered files or empty message
        Expanded(
          child: folderListState.filteredFiles.isNotEmpty
              ? folder_list_components.FileView(
                  files:
                      folderListState.filteredFiles.whereType<File>().toList(),
                  folders: const [], // No folders in filtered view
                  state: folderListState,
                  isSelectionMode: selectionState.isSelectionMode,
                  isGridView: folderListState.viewMode == ViewMode.grid ||
                      folderListState.viewMode == ViewMode.gridPreview,
                  selectedFiles: selectionState.selectedFilePaths.toList(),
                  toggleFileSelection: toggleFileSelection,
                  toggleSelectionMode: toggleSelectionMode,
                  showDeleteTagDialog: showDeleteTagDialog,
                  showAddTagToFileDialog: showAddTagToFileDialog,
                  onZoomChanged: onZoomLevelChanged,
                  showFileTags: showFileTags,
                )
              : Center(
                  child: Text(l10n.noFilesMatchFilter(displayFilter)),
                ),
        ),
      ],
    );
  }

  String _displayFilterLabel(BuildContext context, String filter) {
    final l10n = AppLocalizations.of(context)!;
    switch (filter) {
      case 'image':
        return l10n.image;
      case 'video':
        return l10n.video;
      default:
        return filter;
    }
  }
}
