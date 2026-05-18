import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/index.dart'
    as folder_list_components;
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/utils/platform_utils.dart';

/// Displays search results from tag and filename searches
class SearchResultsView extends StatefulWidget {
  final FolderListState state;
  final bool isSelectionMode;
  final List<String> selectedFiles;
  final String? lastSelectedPath;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;
  final Function(String, {bool shiftSelect, bool ctrlSelect})?
      toggleFolderSelection;
  final VoidCallback toggleSelectionMode;
  final Function(BuildContext, String, List<String>) showDeleteTagDialog;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final VoidCallback onClearSearch;
  final Function(String)? onFolderTap; // Callback for folder click
  final Function(File, bool)? onFileTap; // Callback for file click
  final VoidCallback? onBackButtonPressed; // Add callback for back button
  final VoidCallback? onForwardButtonPressed; // Add callback for forward button
  final VoidCallback? onLoadMore;
  final ValueChanged<int>? onZoomLevelChanged;

  const SearchResultsView({
    Key? key,
    required this.state,
    required this.isSelectionMode,
    required this.selectedFiles,
    this.lastSelectedPath,
    required this.toggleFileSelection,
    this.toggleFolderSelection,
    required this.toggleSelectionMode,
    required this.showDeleteTagDialog,
    required this.showAddTagToFileDialog,
    required this.onClearSearch,
    this.onFolderTap,
    this.onFileTap,
    this.onBackButtonPressed,
    this.onForwardButtonPressed,
    this.onLoadMore,
    this.onZoomLevelChanged,
  }) : super(key: key);

  @override
  State<SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends State<SearchResultsView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    if (widget.onLoadMore == null) return;
    final state = widget.state;
    if (!state.hasMoreSearchResults || state.isLoadingMoreSearchResults) return;
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > 600) return;
    widget.onLoadMore?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = isDesktopPlatform;
    // Wrap the entire widget with a Listener to detect mouse button events
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        // Mouse button 4 is usually the back button
        if (event.buttons == 8 && widget.onBackButtonPressed != null) {
          widget.onBackButtonPressed!();
        }
        // Mouse button 5 is usually the forward button
        else if (event.buttons == 16 && widget.onForwardButtonPressed != null) {
          widget.onForwardButtonPressed!();
        }
      },
      child: Column(
        children: [
          // Search results header with clear search button
          Container(
            padding:
                const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              children: [
                Icon(
                  _getSearchIcon(),
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(_getSearchTitle(context)),
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsLight.x),
                  onPressed: widget.onClearSearch,
                  tooltip: AppLocalizations.of(context)!.clearSearch,
                ),
              ],
            ),
          ),

          // Results list
          Expanded(child: _buildResultsView(isDesktop)),
        ],
      ),
    );
  }

  // Trả về biểu tượng phù hợp với loại tìm kiếm
  IconData _getSearchIcon() {
    final state = widget.state;
    if (state.currentSearchTag != null) {
      return PhosphorIconsLight.tag;
    } else if (state.currentSearchQuery != null) {
      return PhosphorIconsLight.magnifyingGlass;
    } else if (state.currentMediaSearch != null) {
      switch (state.currentMediaSearch!) {
        // Using non-null assertion since we checked it's not null
        case MediaType.image:
          return PhosphorIconsLight.image;
        case MediaType.video:
          return PhosphorIconsLight.filmStrip;
        case MediaType.audio:
          return PhosphorIconsLight.musicNote;
        case MediaType.document:
          return PhosphorIconsLight.fileText;
      }
    }
    return PhosphorIconsLight.magnifyingGlass; // Default icon
  }

  // Tạo tiêu đề dựa trên loại tìm kiếm
  String _getSearchTitle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = widget.state;
    // Đếm số lượng thư mục và tệp trong kết quả
    int folderCount = 0;
    int fileCount = 0;

    for (var entity in state.searchResults) {
      if (entity is Directory) {
        folderCount++;
      } else if (entity is File) {
        fileCount++;
      }
    }

    final String countText = _buildCountText(l10n, folderCount, fileCount);

    if (state.currentSearchTag != null) {
      if (state.isGlobalSearch) {
        return l10n.searchResultsTitleForTagGlobal(
            state.currentSearchTag!, countText);
      }
      return l10n.searchResultsTitleForTag(state.currentSearchTag!, countText);
    }
    if (state.currentSearchQuery != null) {
      return l10n.searchResultsTitleForQuery(
          state.currentSearchQuery!, countText);
    }
    if (state.currentFilter != null) {
      final int filteredCount = state.filteredFiles.length;
      final String filteredCountText =
          ' ($filteredCount ${filteredCount == 1 ? l10n.file : l10n.files})';
      return l10n.searchResultsTitleForFilter(
          state.currentFilter!, filteredCountText);
    } else if (state.currentMediaSearch != null) {
      String mediaType = '';
      switch (state.currentMediaSearch) {
        case MediaType.image:
          mediaType = l10n.image;
          break;
        case MediaType.video:
          mediaType = l10n.video;
          break;
        case MediaType.audio:
          mediaType = l10n.audio;
          break;
        case MediaType.document:
          mediaType = l10n.document;
          break;
        default:
          mediaType = '';
          break;
      }
      return l10n.searchResultsTitleForMedia(mediaType, countText);
    }
    return l10n.searchResultsTitle(countText);
  }

  String _buildCountText(
      AppLocalizations l10n, int folderCount, int fileCount) {
    if (folderCount == 0 && fileCount == 0) {
      return ' (0 ${l10n.results})';
    }

    final parts = <String>[];
    if (folderCount > 0) {
      parts
          .add('$folderCount ${folderCount == 1 ? l10n.folder : l10n.folders}');
    }
    if (fileCount > 0) {
      parts.add('$fileCount ${fileCount == 1 ? l10n.file : l10n.files}');
    }
    return ' (${parts.join(', ')})';
  }

  Widget _buildResultsView(bool isDesktop) {
    final state = widget.state;
    final files = state.searchResults.whereType<File>().toList();
    final folders = state.searchResults.whereType<Directory>().toList();
    final displayState = state.copyWith(
      files: files,
      folders: folders,
    );

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 600) {
              _onScroll();
            }
            return false;
          },
          child: folder_list_components.FileView(
            files: files,
            folders: folders,
            state: displayState,
            isSelectionMode: widget.isSelectionMode,
            isGridView: state.viewMode == ViewMode.grid ||
                state.viewMode == ViewMode.gridPreview,
            selectedFiles: widget.selectedFiles,
            toggleFileSelection: widget.toggleFileSelection,
            toggleFolderSelection:
                widget.toggleFolderSelection ?? widget.toggleFileSelection,
            toggleSelectionMode: widget.toggleSelectionMode,
            showDeleteTagDialog: widget.showDeleteTagDialog,
            showAddTagToFileDialog: widget.showAddTagToFileDialog,
            onFolderTap: widget.onFolderTap,
            onFileTap: widget.onFileTap,
            onZoomChanged: widget.onZoomLevelChanged,
            isDesktopMode: isDesktop,
            lastSelectedPath: widget.lastSelectedPath,
            scrollController: _scrollController,
          ),
        ),
        if (state.hasMoreSearchResults && !state.isLoadingMoreSearchResults)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: TextButton(
                onPressed: widget.onLoadMore,
                child: Text(AppLocalizations.of(context)!.nextPage),
              ),
            ),
          ),
      ],
    );
  }
}
