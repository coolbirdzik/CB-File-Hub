import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;
import 'package:cb_file_manager/ui/utils/route.dart';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/components/search_bar.dart'
    as tab_components;
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/models/objectbox/video_library.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/components/common/screen_scaffold.dart';
import 'package:cb_file_manager/ui/components/common/file_view_shell.dart';
import 'package:cb_file_manager/ui/dialogs/delete_confirmation_dialog.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';
import 'package:cb_file_manager/ui/dialogs/open_with_dialog.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/file_view.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/video_player_full_screen.dart';
import 'package:cb_file_manager/ui/screens/mixins/selection_mixin.dart';
import 'package:cb_file_manager/ui/screens/video_library/video_library_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_state.dart';
import 'package:cb_file_manager/ui/tab_manager/components/tag_dialogs.dart'
    as tag_dialogs;
import 'package:cb_file_manager/ui/components/common/skeleton_helper.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';

class VideoLibraryFilesScreen extends StatefulWidget {
  final VideoLibrary library;
  final String? tabId;

  const VideoLibraryFilesScreen({
    Key? key,
    required this.library,
    this.tabId,
  }) : super(key: key);

  @override
  State<VideoLibraryFilesScreen> createState() =>
      _VideoLibraryFilesScreenState();
}

class _VideoLibraryFilesScreenState extends State<VideoLibraryFilesScreen>
    with SelectionMixin {
  final VideoLibraryService _service = VideoLibraryService();
  final UserPreferences _preferences = UserPreferences.instance;
  late final VideoLibraryNavigationBloc _bloc;

  bool _isInitialized = false;
  String _searchQuery = '';
  bool _showSearchBar = false;
  bool _useRegexSearch = false;
  ColumnVisibility _columnVisibility = const ColumnVisibility();
  int _filterToken = 0;

  @override
  void initState() {
    super.initState();
    _bloc = VideoLibraryNavigationBloc(libraryId: widget.library.id);
    _bloc.loadLibrary(); // Kick off initial load
  }

  @override
  void didUpdateWidget(VideoLibraryFilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library.id != widget.library.id) {
      _bloc.close();
      // ignore: invalid_use_of_visible_for_testing_member
      _bloc.add(FileNavigationLoad('#video-library/${widget.library.id}',
          isVirtualPath: true));
    }
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      await _preferences.init();
      final viewMode = await _preferences.getViewMode();
      final effectiveViewMode =
          viewMode == ViewMode.gridPreview ? ViewMode.grid : viewMode;
      final sortOption = await _preferences.getSortOption();
      final gridZoomLevel = await _preferences.getGridZoomLevel();
      final columnVisibility = await _preferences.getColumnVisibility();

      if (!mounted) return;

      // Apply to bloc first
      _bloc.add(FileNavigationSetViewMode(effectiveViewMode));
      _bloc.add(FileNavigationSetSortOption(sortOption));
      _bloc.add(FileNavigationSetGridZoom(gridZoomLevel));

      setState(() {
        _columnVisibility = columnVisibility;
      });
    } catch (e) {
      // Keep defaults if preferences cannot be loaded.
    }
  }

  void _onBlocStateChange(VideoLibraryNavigationBloc bloc) {
    if (!_isInitialized) {
      _isInitialized = true;
      _loadPreferences();
    }
  }

  Future<void> _handleBackButton() async {
    if (widget.tabId == null) return;
    try {
      final tabManagerBloc = context.read<TabManagerBloc>();
      if (tabManagerBloc.canTabNavigateBack(widget.tabId!)) {
        tabManagerBloc.backNavigationToPath(widget.tabId!);
      }
    } catch (_) {
      // Ignore if TabManagerBloc is not available
    }
  }

  Future<void> _refresh() async {
    // Clear both memory and disk cache before re-scanning
    await VideoLibraryNavigationBloc.invalidateCache(widget.library.id);
    _bloc.refreshLibrary();
  }

  Future<void> _applyFilters() async {
    final int token = ++_filterToken;
    if (!mounted || token != _filterToken) return;
    // Trigger rebuild to re-apply local search filter
    _bloc.add(const FileNavigationClearSearchAndFilters());
  }

  Future<void> _saveColumnVisibility(ColumnVisibility visibility) async {
    try {
      await _preferences.init();
      await _preferences.setColumnVisibility(visibility);
    } catch (e) {
      // Ignore preference errors for now.
    }
  }

  void _toggleViewMode(ViewMode current) {
    ViewMode next;
    if (current == ViewMode.list) {
      next = ViewMode.grid;
    } else if (current == ViewMode.grid) {
      next = ViewMode.details;
    } else {
      next = ViewMode.list;
    }
    _bloc.add(FileNavigationSetViewMode(next));
    _saveViewMode(next);
  }

  void _setViewMode(ViewMode mode) {
    final resolved = mode == ViewMode.gridPreview ? ViewMode.grid : mode;
    _bloc.add(FileNavigationSetViewMode(resolved));
    _saveViewMode(resolved);
  }

  Future<void> _saveViewMode(ViewMode mode) async {
    try {
      await _preferences.init();
      await _preferences.setViewMode(mode);
    } catch (e) {
      // Ignore preference errors for now.
    }
  }

  void _setSortOption(SortOption option) {
    _bloc.add(FileNavigationSetSortOption(option));
    _saveSortOption(option);
  }

  Future<void> _saveSortOption(SortOption option) async {
    try {
      await _preferences.init();
      await _preferences.setSortOption(option);
    } catch (e) {
      // Ignore preference errors for now.
    }
  }

  void _handleGridZoomDelta(int delta) {
    final current = _bloc.state.gridZoomLevel;
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final nextLevel = (current + delta)
        .clamp(UserPreferences.minGridZoomLevel, maxZoom)
        .toInt();
    if (nextLevel == current) return;
    _bloc.add(FileNavigationSetGridZoom(nextLevel));
    _saveGridZoomLevel(nextLevel);
  }

  void _setGridZoomLevel(int level) {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final nextLevel =
        level.clamp(UserPreferences.minGridZoomLevel, maxZoom).toInt();
    _bloc.add(FileNavigationSetGridZoom(nextLevel));
    _saveGridZoomLevel(nextLevel);
  }

  Future<void> _saveGridZoomLevel(int level) async {
    try {
      await _preferences.init();
      await _preferences.setGridZoomLevel(level);
    } catch (e) {
      // Ignore preference errors for now.
    }
  }

  void _showColumnSettings() {
    SharedActionBar.showColumnVisibilityDialog(
      context,
      currentVisibility: _columnVisibility,
      onApply: (visibility) {
        setState(() {
          _columnVisibility = visibility;
        });
        _saveColumnVisibility(visibility);
      },
    );
  }

  void _applySearchWithOptions(String value, bool useRegex) {
    final trimmed = value.trim();
    if (_searchQuery == trimmed && _useRegexSearch == useRegex) return;
    setState(() {
      _searchQuery = trimmed;
      _useRegexSearch = useRegex;
    });
    _applyFilters();
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && !_useRegexSearch) return;
    setState(() {
      _searchQuery = '';
      _useRegexSearch = false;
    });
    _applyFilters();
  }

  void _openSearchBar() {
    setState(() {
      _showSearchBar = true;
    });
  }

  void _closeSearchBar() {
    setState(() {
      _showSearchBar = false;
    });
  }

  SelectionState _buildSelectionState() {
    return SelectionState(
      selectedFilePaths: selectedPaths.toSet(),
      selectedFolderPaths: const {},
      isSelectionMode: isSelectionMode,
    );
  }

  Widget _buildPathNavigationBar(AppLocalizations l10n) {
    return BreadcrumbAddressBar(
      segments: [
        BreadcrumbSegment(
          label: l10n.videoLibrary,
          icon: PhosphorIconsLight.filmStrip,
        ),
        BreadcrumbSegment(
          label: widget.library.name,
        ),
      ],
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n) => tab_components.SearchBar(
        currentPath: '#video-library/${widget.library.id}',
        tabId: widget.tabId ?? '#video-library/${widget.library.id}',
        initialQuery: _searchQuery,
        hintText: l10n.searchByFilename,
        onSearchWithOptions: _applySearchWithOptions,
        onClearSearch: _clearSearch,
        onCloseSearch: _closeSearchBar,
        showClearButton: _searchQuery.isNotEmpty,
        showTipsButton: true,
        showTagSearch: false,
        showGlobalSearchToggle: false,
        showRegexToggle: true,
      );

  void _clearSelection() {
    exitSelectionMode();
  }

  void _showRemoveTagsDialog(BuildContext context) {
    if (selectedPaths.isEmpty) return;
    tag_dialogs.showRemoveTagsDialog(context, selectedPaths.toList());
  }

  void _showManageAllTagsDialog(BuildContext context) {
    tag_dialogs.showManageTagsDialog(
      context,
      const [],
      '#video-library/${widget.library.id}',
      selectedFiles: selectedPaths.toList(),
    );
  }

  Future<void> _showDeleteConfirmationDialog(BuildContext context) async {
    if (selectedPaths.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final selectedFiles = selectedPaths.toList();
    final totalCount = selectedFiles.length;
    final firstName = path.basename(selectedFiles.first);
    final message = totalCount == 1
        ? l10n.moveToTrashConfirmMessage(firstName)
        : l10n.moveItemsToTrashConfirmation(totalCount, l10n.items);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DeleteConfirmationDialog(
        title: l10n.moveToTrash,
        message: message,
        confirmText: l10n.moveToTrash,
        cancelText: l10n.cancel,
      ),
    );

    if (confirmed == true) {
      await _deleteSelectedFiles(selectedFiles);
    }
  }

  Future<void> _deleteSelectedFiles(List<String> filePaths) async {
    final trashManager = TrashManager();
    final deletedPaths = <String>{};

    for (final filePath in filePaths) {
      try {
        final success = await trashManager.moveToTrash(filePath);
        if (success) {
          deletedPaths.add(filePath);
          await _service.removeFileFromLibrary(widget.library.id, filePath);
        }
      } catch (_) {
        // Ignore failures to keep the UI responsive.
      }
    }

    if (!mounted || deletedPaths.isEmpty) return;

    // Invalidate cache so refresh re-scans from disk
    VideoLibraryNavigationBloc.invalidateCache(widget.library.id);
    _bloc.refreshLibrary();
    exitSelectionMode();
  }

  void _openVideo(File file) {
    ExternalAppHelper.openWithPreferredVideoApp(file.path)
        .then((openedPreferred) {
      if (openedPreferred) return;

      _preferences.getUseSystemDefaultForVideo().then((useSystem) {
        if (useSystem) {
          ExternalAppHelper.openWithSystemDefault(file.path).then((success) {
            if (!success && mounted) {
              RouteUtils.showAcrylicDialog(
                context: context,
                builder: (context) => OpenWithDialog(filePath: file.path),
              );
            }
          });
        } else {
          if (mounted) {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => VideoPlayerFullScreen(file: file),
              ),
            );
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final selectionState = _buildSelectionState();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _handleBackButton();
        }
      },
      child: BlocProvider.value(
        value: _bloc,
        child: BlocConsumer<VideoLibraryNavigationBloc, FileNavigationState>(
          listener: (context, state) => _onBlocStateChange(_bloc),
          builder: (context, state) {
            return ScreenScaffold(
              selectionState: selectionState,
              body: FileViewShell(
                viewMode: state.viewMode,
                onGridZoomDelta: _handleGridZoomDelta,
                onMouseBack: _handleBackButton,
                onRefresh: _refresh,
                onEscape: isSelectionMode
                    ? exitSelectionMode
                    : _showSearchBar
                        ? _closeSearchBar
                        : null,
                onDelete: ({required bool permanent}) {
                  if (isSelectionMode && selectedPaths.isNotEmpty) {
                    _showDeleteConfirmationDialog(context);
                  }
                },
                child: _buildBody(l10n, state),
              ),
              isNetworkPath: false,
              onClearSelection: _clearSelection,
              showRemoveTagsDialog: _showRemoveTagsDialog,
              showManageAllTagsDialog: _showManageAllTagsDialog,
              showDeleteConfirmationDialog: _showDeleteConfirmationDialog,
              isDesktop: isDesktop,
              selectionModeFloatingActionButton: null,
              showAppBar: true,
              showSearchBar: _showSearchBar,
              searchBar: _buildSearchBar(l10n),
              pathNavigationBar: _buildPathNavigationBar(l10n),
              actions: SharedActionBar.buildCommonActions(
                context: context,
                onSearchPressed: _openSearchBar,
                onSortOptionSelected: _setSortOption,
                currentSortOption: state.sortOption,
                viewMode: state.viewMode,
                onViewModeToggled: () => _toggleViewMode(state.viewMode),
                onViewModeSelected: _setViewMode,
                onRefresh: _refresh,
                currentGridZoomLevel: state.viewMode == ViewMode.grid
                    ? state.gridZoomLevel
                    : null,
                onGridZoomChanged: _setGridZoomLevel,
                onColumnSettingsPressed: state.viewMode == ViewMode.details
                    ? _showColumnSettings
                    : null,
                onSelectionModeToggled: toggleSelectionMode,
              ),
              floatingActionButton: FloatingActionButton(
                heroTag: null,
                onPressed: toggleSelectionMode,
                child: const Icon(PhosphorIconsLight.checkSquare),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, FileNavigationState state) {
    final isGridView = state.viewMode == ViewMode.grid ||
        state.viewMode == ViewMode.gridPreview;

    if (state.isLoading && state.files.isEmpty) {
      return SkeletonHelper.responsive(
        isGridView: isGridView,
        crossAxisCount: isGridView ? state.gridZoomLevel : null,
        itemCount: 12,
      );
    }

    // Apply local search filter
    final trimmedQuery = _searchQuery.trim();
    final visibleFiles = trimmedQuery.isEmpty
        ? state.files
        : _filterFilesBySearch(state.files, trimmedQuery);

    if (state.files.isEmpty) {
      return Center(
        child: Text(
          l10n.noVideosInLibrary,
          style: const TextStyle(fontSize: 16),
        ),
      );
    }

    final hasSearch = _searchQuery.trim().isNotEmpty;
    final content = visibleFiles.isEmpty
        ? Center(
            child: state.isLoading
                ? SkeletonHelper.responsive(
                    isGridView: isGridView,
                    crossAxisCount: isGridView ? state.gridZoomLevel : null,
                    itemCount: 8,
                  )
                : Text(
                    hasSearch
                        ? l10n.noFilesFoundQuery({'query': _searchQuery})
                        : l10n.noVideosInLibrary,
                    style: const TextStyle(fontSize: 16),
                  ),
          )
        : _buildFileView(visibleFiles, state);

    return Column(
      children: [
        if (hasSearch)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3),
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.magnifyingGlass, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.searchingFor(_searchQuery))),
                IconButton(
                  icon: const Icon(PhosphorIconsLight.x),
                  tooltip: l10n.clearSearch,
                  onPressed: _clearSearch,
                ),
              ],
            ),
          ),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildFileView(
      List<FileSystemEntity> visibleFiles, FileNavigationState state) {
    final folderListState = FolderListState(
      '#video-library/${widget.library.id}',
      files: visibleFiles,
      folders: const [],
      viewMode: state.viewMode,
      sortOption: state.sortOption,
      gridZoomLevel: state.gridZoomLevel,
    );

    final isGridView = state.viewMode == ViewMode.grid ||
        state.viewMode == ViewMode.gridPreview;

    return FileView(
      files: visibleFiles.cast<File>(),
      folders: const [],
      state: folderListState,
      isSelectionMode: isSelectionMode,
      isGridView: isGridView,
      selectedFiles: selectedPaths.toList(),
      toggleFileSelection: _toggleFileSelection,
      toggleSelectionMode: toggleSelectionMode,
      showDeleteTagDialog: _showDeleteTagDialog,
      showAddTagToFileDialog: _showAddTagToFileDialog,
      onFileTap: (file, _) => _openVideo(file),
      onZoomChanged: _handleGridZoomDelta,
      isDesktopMode: Platform.isWindows || Platform.isMacOS || Platform.isLinux,
      columnVisibility: _columnVisibility,
      showFileTags: false,
    );
  }

  List<FileSystemEntity> _filterFilesBySearch(
    List<FileSystemEntity> files,
    String query,
  ) {
    if (!_useRegexSearch) {
      final normalizedQuery = query.toLowerCase();
      return files
          .where((file) =>
              path.basename(file.path).toLowerCase().contains(normalizedQuery))
          .toList();
    }

    RegExp pattern;
    try {
      pattern = RegExp(query, caseSensitive: false);
    } catch (_) {
      return files;
    }

    return files
        .where((file) => pattern.hasMatch(path.basename(file.path)))
        .toList();
  }

  void _toggleFileSelection(String filePath,
      {bool shiftSelect = false, bool ctrlSelect = false}) {
    final shouldEnterSelection = !isSelectionMode || shiftSelect || ctrlSelect;
    if (shouldEnterSelection && !isSelectionMode) {
      enterSelectionMode();
    }
    toggleSelection(filePath);
    if (selectedPaths.isEmpty) {
      exitSelectionMode();
    }
  }

  void _showAddTagToFileDialog(BuildContext context, String filePath) {
    AppLogger.info('[ManageTags][VideoLibrary] _showAddTagToFileDialog',
        error: 'filePath=$filePath');
    tag_dialogs.showAddTagToFileDialog(context, filePath);
  }

  void _showDeleteTagDialog(
      BuildContext context, String filePath, List<String> tags) {
    tag_dialogs.showDeleteTagDialog(context, filePath, tags);
  }
}
