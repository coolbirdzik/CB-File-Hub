import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
// Add this import for mouse buttons
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
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;
  final VoidCallback toggleSelectionMode;
  final Function(BuildContext, String, List<String>) showDeleteTagDialog;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final VoidCallback onClearSearch;
  final Function(String)? onFolderTap; // Callback for folder click
  final Function(File, bool)? onFileTap; // Callback for file click
  final VoidCallback? onBackButtonPressed; // Add callback for back button
  final VoidCallback? onForwardButtonPressed; // Add callback for forward button
  final VoidCallback? onLoadMore;

  const SearchResultsView({
    Key? key,
    required this.state,
    required this.isSelectionMode,
    required this.selectedFiles,
    required this.toggleFileSelection,
    required this.toggleSelectionMode,
    required this.showDeleteTagDialog,
    required this.showAddTagToFileDialog,
    required this.onClearSearch,
    this.onFolderTap,
    this.onFileTap,
    this.onBackButtonPressed,
    this.onForwardButtonPressed,
    this.onLoadMore,
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
          // Top progress bar when searching
          if (widget.state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: LinearProgressIndicator(),
            ),
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
          Expanded(
            child: (widget.state.viewMode == ViewMode.grid ||
                    widget.state.viewMode == ViewMode.gridPreview)
                ? _buildGridView(isDesktop)
                : _buildListView(isDesktop),
          ),
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

  Widget _buildListView(bool isDesktop) {
    final state = widget.state;
    return ListView.builder(
      controller: _scrollController,
      itemCount:
          state.searchResults.length + (state.hasMoreSearchResults ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.searchResults.length) {
          if (state.isLoadingMoreSearchResults) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Center(
              child: TextButton(
                onPressed: widget.onLoadMore,
                child: Text(AppLocalizations.of(context)!.nextPage),
              ),
            ),
          );
        }

        final entity = state.searchResults[index];
        if (entity is File) {
          return folder_list_components.FileItem(
            file: entity,
            state: state,
            isSelectionMode: widget.isSelectionMode,
            isSelected: widget.selectedFiles.contains(entity.path),
            toggleFileSelection: widget.toggleFileSelection,
            showDeleteTagDialog: widget.showDeleteTagDialog,
            showAddTagToFileDialog: widget.showAddTagToFileDialog,
            onFileTap: widget.onFileTap,
            isDesktopMode: isDesktop,
          );
        } else if (entity is Directory) {
          // Hiển thị thư mục trong kết quả tìm kiếm
          return ListTile(
            leading: const Icon(PhosphorIconsLight.folder, color: Colors.amber),
            // Show only folder name instead of full path
            title: Text(entity.path.split(Platform.pathSeparator).last),
            // Keep subtitle as full path for reference
            subtitle: Text(entity.path),
            onTap: () {
              if (widget.onFolderTap != null) {
                // Sử dụng callback để chuyển đường dẫn trong tab hiện tại
                widget.onFolderTap!(entity.path);
              }
            },
          );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _buildGridView(bool isDesktop) {
    final state = widget.state;
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8.0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: state.gridZoomLevel,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount:
          state.searchResults.length + (state.hasMoreSearchResults ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.searchResults.length) {
          if (state.isLoadingMoreSearchResults) {
            return const Center(child: CircularProgressIndicator());
          }

          return Center(
            child: TextButton(
              onPressed: widget.onLoadMore,
              child: Text(AppLocalizations.of(context)!.nextPage),
            ),
          );
        }

        final entity = state.searchResults[index];
        if (entity is File) {
          return folder_list_components.FileGridItem(
            file: entity,
            state: state,
            isSelectionMode: widget.isSelectionMode,
            isSelected: widget.selectedFiles.contains(entity.path),
            toggleFileSelection: widget.toggleFileSelection,
            toggleSelectionMode: widget.toggleSelectionMode,
            onFileTap: widget.onFileTap,
            isDesktopMode: isDesktop,
          );
        } else if (entity is Directory) {
          // Xử lý thư mục trong chế độ xem lưới
          return InkWell(
            onTap: () {
              if (widget.onFolderTap != null) {
                // Sử dụng callback để chuyển đường dẫn trong tab hiện tại
                widget.onFolderTap!(entity.path);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(PhosphorIconsLight.folder,
                      size: 48, color: Colors.amber),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text(
                      entity.path.split(Platform.pathSeparator).last,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }
}
