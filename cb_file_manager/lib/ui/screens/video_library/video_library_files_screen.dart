import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;
import 'package:cb_file_manager/ui/utils/route.dart';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_action_handlers.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/components/search_bar.dart'
    as tab_components;
import 'package:cb_file_manager/models/objectbox/video_library.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_file_surface.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/dialogs/delete_confirmation_dialog.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/dialogs/open_with_dialog.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/video_playback_launcher.dart';
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
import 'package:cb_file_manager/ui/utils/view_mode_spectrum.dart';
import 'package:cb_file_manager/ui/widgets/file_list_view_builder.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_keyboard_controller.dart';

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

class _VideoLibraryFilesScreenState extends State<VideoLibraryFilesScreen> {
  final VideoLibraryService _service = VideoLibraryService();
  final UserPreferences _preferences = UserPreferences.instance;
  late final VideoLibraryNavigationBloc _bloc;
  late final SelectionBloc _selectionBloc;
  late final FolderListBloc _dragFolderListBloc;
  late final TabbedFolderDragSelectionController _dragSelectionController;
  final ValueNotifier<double> _previewPaneWidthNotifier =
      ValueNotifier<double>(320);

  bool _isInitialized = false;
  String _searchQuery = '';
  List<String> _activeSearchTags = const [];
  Set<String>? _tagMatchedPaths;
  bool _showSearchBar = false;
  bool _useRegexSearch = false;
  bool _showFileTags = true;
  ColumnVisibility _columnVisibility = const ColumnVisibility();
  int _filterToken = 0;
  int _gridCrossAxisCount = 1;

  @override
  void initState() {
    super.initState();
    _bloc = VideoLibraryNavigationBloc(libraryId: widget.library.id);
    _selectionBloc = SelectionBloc();
    _dragFolderListBloc = FolderListBloc();
    _dragSelectionController = TabbedFolderDragSelectionController(
      folderListBloc: _dragFolderListBloc,
      selectionBloc: _selectionBloc,
    );
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
    _dragSelectionController.dispose();
    _dragFolderListBloc.close();
    _selectionBloc.close();
    _previewPaneWidthNotifier.dispose();
    _bloc.close();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      await _preferences.init();
      final globalViewMode = await _preferences.getViewMode();
      final viewMode = await _preferences.getVideoLibraryViewMode(
        widget.library.id,
        fallback: globalViewMode,
      );
      final effectiveViewMode =
          viewMode == ViewMode.gridPreview ? ViewMode.grid : viewMode;
      final globalSortOption = await _preferences.getSortOption();
      final sortOption = await _preferences.getVideoLibrarySortOption(
        widget.library.id,
        fallback: globalSortOption,
      );
      final showFileTags = await _preferences.getShowFileTags();
      final gridZoomLevel = await _preferences.getGridZoomLevel();
      final columnVisibility = await _preferences.getColumnVisibility();

      if (!mounted) return;

      // Apply to bloc first
      _bloc.add(FileNavigationSetViewMode(effectiveViewMode));
      _bloc.add(FileNavigationSetSortOption(
        sortOption,
        persist: false,
      ));
      _bloc.add(FileNavigationSetGridZoom(gridZoomLevel));

      setState(() {
        _showFileTags = showFileTags;
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
      await _preferences.setVideoLibraryViewMode(widget.library.id, mode);
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
      await _preferences.setVideoLibrarySortOption(widget.library.id, option);
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

  /// Unified Ctrl+scroll spectrum handler: walks detail↔list↔grid and adjusts
  /// grid item size. `+1` = more spacious, `-1` = denser.
  void _handleViewScaleDelta(int delta) {
    if (delta == 0) return;
    final state = _bloc.state;
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final result = ViewModeSpectrum.step(
      currentMode: state.viewMode,
      currentZoom: state.gridZoomLevel,
      supported: const {ViewMode.details, ViewMode.list},
      delta: delta,
      minZoom: UserPreferences.minGridZoomLevel,
      maxZoom: maxZoom,
    );

    if (result.mode != state.viewMode) {
      _setViewMode(result.mode);
    }
    if (result.gridZoomLevel != state.gridZoomLevel) {
      _bloc.add(FileNavigationSetGridZoom(result.gridZoomLevel));
      _saveGridZoomLevel(result.gridZoomLevel);
    }
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
    if (_searchQuery == trimmed &&
        _useRegexSearch == useRegex &&
        _activeSearchTags.isEmpty) {
      return;
    }
    setState(() {
      _searchQuery = trimmed;
      _useRegexSearch = useRegex;
      _activeSearchTags = const [];
      _tagMatchedPaths = null;
    });
    unawaited(_applyFilters());
  }

  Future<void> _applyTagSearch(List<String> tags, bool _) async {
    final normalizedTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedTags.isEmpty) return;

    final int token = ++_filterToken;
    try {
      final files = List<FileSystemEntity>.from(_bloc.state.files);
      final fileTags = await TagManager.getTagsForFiles(
        files.map((entity) => entity.path).toList(),
      );
      if (!mounted || token != _filterToken) {
        return;
      }

      final normalizedSearchTags =
          normalizedTags.map((tag) => tag.toLowerCase()).toSet();
      final matchedPaths = files
          .where((entity) {
            final tagsForFile = fileTags[entity.path] ?? const <String>[];
            final normalizedFileTags =
                tagsForFile.map((tag) => tag.toLowerCase()).toSet();
            return normalizedSearchTags.every(normalizedFileTags.contains);
          })
          .map((entity) => entity.path)
          .toSet();

      setState(() {
        _activeSearchTags = normalizedTags;
        _tagMatchedPaths = matchedPaths;
        _searchQuery = normalizedTags.map((tag) => '#$tag').join(' ');
        _useRegexSearch = false;
      });
      _bloc.add(const FileNavigationClearSearchAndFilters());
    } catch (_) {}
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && !_useRegexSearch && _activeSearchTags.isEmpty) {
      return;
    }
    setState(() {
      _searchQuery = '';
      _useRegexSearch = false;
      _activeSearchTags = const [];
      _tagMatchedPaths = null;
    });
    unawaited(_applyFilters());
  }

  void _closeSearchBar() {
    setState(() {
      _showSearchBar = false;
    });
  }

  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
    });
  }

  void _toggleSelectionMode() {
    _selectionBloc.add(const ToggleSelectionMode());
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
        onTagSearch: _applyTagSearch,
        onClearSearch: _clearSearch,
        onCloseSearch: _closeSearchBar,
        showClearButton:
            _searchQuery.isNotEmpty || _activeSearchTags.isNotEmpty,
        showTipsButton: true,
        showTagSearch: true,
        showGlobalSearchToggle: false,
        showRegexToggle: true,
      );

  void _clearSelection() {
    _selectionBloc.add(ClearSelection());
  }

  void _showRemoveTagsDialog(BuildContext context) {
    final selectedPaths = _selectionBloc.state.selectedFilePaths;
    if (selectedPaths.isEmpty) return;
    tag_dialogs.showRemoveTagsDialog(context, selectedPaths.toList());
  }

  void _showManageAllTagsDialog(BuildContext context) {
    final selectedPaths = _selectionBloc.state.selectedFilePaths;
    tag_dialogs.showManageTagsDialog(
      context,
      const [],
      '#video-library/${widget.library.id}',
      selectedFiles: selectedPaths.toList(),
    );
  }

  Future<void> _showDeleteConfirmationDialog(BuildContext context) async {
    final selectedPaths = _selectionBloc.state.selectedFilePaths;
    if (selectedPaths.isEmpty) return;
    await _showDeleteFilesConfirmation(context, selectedPaths.toList());
  }

  Future<void> _showDeleteFilesConfirmation(
    BuildContext context,
    List<String> selectedFiles,
  ) async {
    await _deleteSelectedFiles(selectedFiles);
  }

  Future<void> _deleteSelectedFiles(List<String> filePaths) async {
    await BrowserLikeActionHandlers.confirmAndMoveFilesToTrash(
      context: context,
      filePaths: filePaths,
      onMoved: (filePath) =>
          _service.removeFileFromLibrary(widget.library.id, filePath),
      onAfterSuccess: (_) async {
        await VideoLibraryNavigationBloc.invalidateCache(widget.library.id);
        _bloc.refreshLibrary();
        _clearSelection();
      },
      onMoveError: (filePath, _) {
        AppLogger.warning(
          'Failed to move video library file to trash: $filePath',
        );
      },
    );
  }

  void _selectAllVisible(FileNavigationState state) {
    BrowserLikeActionHandlers.selectAll(
      selectionBloc: _selectionBloc,
      allFilePaths: _visibleFilesForState(state).map((entity) => entity.path),
      allFolderPaths: const <String>[],
    );
  }

  List<FileSystemEntity> _visibleFilesForState(FileNavigationState state) {
    final trimmedQuery = _searchQuery.trim();
    if (_activeSearchTags.isNotEmpty) {
      final matchedPaths = _tagMatchedPaths ?? const <String>{};
      return state.files
          .where((entity) => matchedPaths.contains(entity.path))
          .toList();
    }
    return trimmedQuery.isEmpty
        ? state.files
        : _filterFilesBySearch(state.files, trimmedQuery);
  }

  FolderListState _folderListStateFor(FileNavigationState state) {
    final trimmedQuery = _searchQuery.trim();
    final visibleFiles = _visibleFilesForState(state);
    return FolderListState(
      '#video-library/${widget.library.id}',
      files: visibleFiles,
      folders: const [],
      searchResults: trimmedQuery.isEmpty && _activeSearchTags.isEmpty
          ? const []
          : visibleFiles,
      viewMode: state.viewMode,
      sortOption: state.sortOption,
      gridZoomLevel: state.gridZoomLevel,
      currentSearchTag:
          _activeSearchTags.isEmpty ? null : _activeSearchTags.join(', '),
      currentSearchQuery: trimmedQuery.isEmpty || _activeSearchTags.isNotEmpty
          ? null
          : trimmedQuery,
    );
  }

  Future<void> _handleDelete(
    TabbedFolderKeyboardController keyboardController,
    bool permanent,
  ) async {
    final selectedFiles = _selectionBloc.state.selectedFilePaths.toList();
    if (selectedFiles.isNotEmpty) {
      await _showDeleteFilesConfirmation(context, selectedFiles);
      return;
    }

    final focusedPath = keyboardController.focusedPath;
    if (focusedPath == null || focusedPath.isEmpty) return;

    final visiblePaths =
        _visibleFilesForState(_bloc.state).map((entity) => entity.path).toSet();
    if (!visiblePaths.contains(focusedPath)) return;

    await _showDeleteFilesConfirmation(context, <String>[focusedPath]);
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
            unawaited(VideoPlaybackLauncher.open(context, file: file));
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _handleBackButton();
        }
      },
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _bloc),
          BlocProvider.value(value: _selectionBloc),
        ],
        child: BlocBuilder<SelectionBloc, SelectionState>(
          builder: (context, selectionState) {
            return BlocConsumer<VideoLibraryNavigationBloc,
                FileNavigationState>(
              listener: (context, state) => _onBlocStateChange(_bloc),
              builder: (context, state) {
                final folderListState = _folderListStateFor(state);
                return BrowserLikeFileSurface(
                  selectionState: selectionState,
                  viewMode: state.viewMode,
                  isDesktop: isDesktop,
                  visiblePaths:
                      _visibleFilesForState(state).map((entity) => entity.path),
                  bodyBuilder: (context, keyboardController) =>
                      _buildBody(l10n, state, keyboardController),
                  keyboardFolderListState: folderListState,
                  currentFilter: null,
                  gridCrossAxisCount: _gridCrossAxisCount,
                  onBackInTabHistory: () => unawaited(_handleBackButton()),
                  focusFolderPath: (_) {},
                  focusFilePath: (filePath) => _toggleFileSelection(
                    filePath,
                    shiftSelect: false,
                    ctrlSelect: false,
                  ),
                  selectRange: ({
                    required Set<String> folderPaths,
                    required Set<String> filePaths,
                    required String lastSelectedPath,
                    required bool ctrlSelect,
                  }) {
                    _selectionBloc.add(SelectItemsInRect(
                      folderPaths: const <String>{},
                      filePaths: filePaths,
                      isCtrlPressed: ctrlSelect,
                      isShiftPressed: true,
                      lastSelectedPath: lastSelectedPath,
                    ));
                  },
                  activateEntity: (entity) {
                    if (entity is File) {
                      _openVideo(entity);
                    }
                  },
                  onClearSelection: _clearSelection,
                  showRemoveTagsDialog: _showRemoveTagsDialog,
                  showManageAllTagsDialog: _showManageAllTagsDialog,
                  showDeleteConfirmationDialog: _showDeleteConfirmationDialog,
                  showAppBar: true,
                  showSearchBar: _showSearchBar,
                  searchBar: _buildSearchBar(l10n),
                  pathNavigationBar: _buildPathNavigationBar(l10n),
                  actions: SharedActionBar.buildCommonActions(
                    context: context,
                    onSearchPressed: _toggleSearchBar,
                    isSearchActive: _showSearchBar,
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
                    onSelectionModeToggled: _toggleSelectionMode,
                  ),
                  floatingActionButton: FloatingActionButton(
                    heroTag: null,
                    onPressed: _toggleSelectionMode,
                    child: const Icon(PhosphorIconsLight.checkSquare),
                  ),
                  onGridZoomDelta: _handleGridZoomDelta,
                  onViewScaleDelta: _handleViewScaleDelta,
                  onMouseBack: _handleBackButton,
                  onRefresh: _refresh,
                  onEscape: selectionState.isSelectionMode
                      ? _clearSelection
                      : _showSearchBar
                          ? _closeSearchBar
                          : null,
                  onSearch: _toggleSearchBar,
                  onSelectAll: () => _selectAllVisible(state),
                  onDelete: (keyboardController, permanent) =>
                      _handleDelete(keyboardController, permanent),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    FileNavigationState state,
    TabbedFolderKeyboardController keyboardController,
  ) {
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
    final visibleFiles = _visibleFilesForState(state);

    if (state.files.isEmpty) {
      return Center(
        child: Text(
          l10n.noVideosInLibrary,
          style: const TextStyle(fontSize: 16),
        ),
      );
    }

    if (visibleFiles.isEmpty) {
      return Center(
        child: state.isLoading
            ? SkeletonHelper.responsive(
                isGridView: isGridView,
                crossAxisCount: isGridView ? state.gridZoomLevel : null,
                itemCount: 8,
              )
            : Text(
                trimmedQuery.isNotEmpty
                    ? l10n.noFilesFoundQuery({'query': _searchQuery})
                    : l10n.noVideosInLibrary,
                style: const TextStyle(fontSize: 16),
              ),
      );
    }

    return _buildFileView(state, keyboardController);
  }

  Widget _buildFileView(
    FileNavigationState state,
    TabbedFolderKeyboardController keyboardController,
  ) {
    final folderListState = _folderListStateFor(state);

    return FileListViewBuilder.build(
      state: folderListState,
      selectionState: _selectionBloc.state,
      isDesktopPlatform:
          Platform.isWindows || Platform.isMacOS || Platform.isLinux,
      onNavigateToPath: (_) {},
      onFileTap: (file, _) => _openVideo(file),
      toggleFileSelection: _toggleFileSelection,
      toggleFolderSelection: (_, {shiftSelect = false, ctrlSelect = false}) {},
      clearSelection: _clearSelection,
      dragSelectionController: _dragSelectionController,
      showFileTags: _showFileTags,
      showDeleteTagDialog: _showDeleteTagDialog,
      showAddTagToFileDialog: _showAddTagToFileDialog,
      onDeleteFile: _showDeleteSingleFileConfirmation,
      onDeleteFiles: _showDeleteFilesConfirmation,
      toggleSelectionMode: _toggleSelectionMode,
      columnVisibility: _columnVisibility,
      showContextMenu: (_, __) {},
      isPreviewPaneVisible: false,
      previewPaneWidthListenable: _previewPaneWidthNotifier,
      onZoomLevelChanged: _handleGridZoomDelta,
      onPreviewPaneWidthChanged: (_) {},
      onPreviewPaneWidthCommitted: (_) {},
      onPreviewPaneToggled: () {},
      scrollController: keyboardController.scrollController,
      itemKeyForPath: keyboardController.itemKeyForPath,
      tabId: widget.tabId,
      onGridCrossAxisCountChanged: (count) {
        if (count != null) {
          _gridCrossAxisCount = count;
        }
      },
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
    if (!shiftSelect) {
      _selectionBloc.add(ToggleFileSelection(
        filePath,
        shiftSelect: false,
        ctrlSelect: ctrlSelect,
      ));
      return;
    }

    final selectionState = _selectionBloc.state;
    if (selectionState.lastSelectedPath == null) {
      _selectionBloc.add(ToggleFileSelection(
        filePath,
        shiftSelect: false,
        ctrlSelect: ctrlSelect,
      ));
      return;
    }

    final allPaths = _visibleFilesForState(_bloc.state)
        .map((entity) => entity.path)
        .toList();
    final currentIndex = allPaths.indexOf(filePath);
    final lastIndex = allPaths.indexOf(selectionState.lastSelectedPath!);
    if (currentIndex == -1 || lastIndex == -1) return;

    final start = currentIndex < lastIndex ? currentIndex : lastIndex;
    final end = currentIndex < lastIndex ? lastIndex : currentIndex;
    _selectionBloc.add(SelectItemsInRect(
      folderPaths: const <String>{},
      filePaths: allPaths.sublist(start, end + 1).toSet(),
      isCtrlPressed: ctrlSelect,
      isShiftPressed: true,
      lastSelectedPath: filePath,
    ));
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

  Future<void> _showDeleteSingleFileConfirmation(
    BuildContext context,
    File file,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DeleteConfirmationDialog(
        title: l10n.moveToTrash,
        message: l10n.moveToTrashConfirmMessage(path.basename(file.path)),
        confirmText: l10n.moveToTrash,
        cancelText: l10n.cancel,
        previewPaths: <String>[file.path],
      ),
    );

    if (confirmed == true) {
      await _deleteSelectedFiles(<String>[file.path]);
    }
  }
}
