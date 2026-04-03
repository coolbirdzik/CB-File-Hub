import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/filesystem_sorter.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/models/objectbox/video_library.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/components/common/screen_scaffold.dart';
import 'package:cb_file_manager/ui/dialogs/delete_confirmation_dialog.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';
import 'package:cb_file_manager/ui/dialogs/open_with_dialog.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/file_view.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/video_player_full_screen.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/screens/mixins/selection_mixin.dart';
import 'package:cb_file_manager/ui/tab_manager/components/index.dart'
    as tab_components;
import 'package:cb_file_manager/ui/tab_manager/components/tag_dialogs.dart'
    as tag_dialogs;
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
  static final Map<int, List<File>> _libraryCache = {};
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final TextEditingController _pathController;

  List<File> _allVideos = [];
  List<File> _visibleVideos = [];
  bool _isLoading = true;
  bool _isSorting = false;
  String _searchQuery = '';
  bool _showSearchBar = false;
  ViewMode _viewMode = ViewMode.list;
  SortOption _sortOption = SortOption.dateDesc;
  int _gridZoomLevel = 3;
  ColumnVisibility _columnVisibility = const ColumnVisibility();
  int _filterToken = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: _searchQuery);
    _searchFocusNode = FocusNode();
    _pathController = TextEditingController();
    _loadPreferences();
    final cached = _libraryCache[widget.library.id];
    if (cached != null && cached.isNotEmpty) {
      _allVideos = cached;
      _isLoading = false;
      _isSorting = cached.isNotEmpty;
      _applyFilters();
    }
    _loadVideos(showLoading: _allVideos.isEmpty);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pathController.dispose();
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
      final maxZoom = GridZoomConstraints.maxGridSizeForContext(
        // ignore: use_build_context_synchronously
        context,
        mode: GridSizeMode.referenceWidth,
      );

      if (!mounted) return;
      setState(() {
        _viewMode = effectiveViewMode;
        _sortOption = sortOption;
        _gridZoomLevel = gridZoomLevel
            .clamp(UserPreferences.minGridZoomLevel, maxZoom)
            .toInt();
        _columnVisibility = columnVisibility;
      });
      await _applyFilters();
    } catch (e) {
      // Keep defaults if preferences cannot be loaded.
    }
  }

  Future<void> _loadVideos({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    final paths = await _service.getLibraryFiles(widget.library.id);
    final files = paths.map((path) => File(path)).toList();

    if (!mounted) return;
    setState(() {
      _allVideos = files;
      _libraryCache[widget.library.id] = files;
      _isLoading = false;
      _isSorting = files.isNotEmpty;
    });
    await _applyFilters();
    
    // Start proactive thumbnail generation after loading videos
    if (files.isNotEmpty) {
      _startProactiveThumbnailGeneration();
    }
  }

  Future<void> _applyFilters() async {
    final int token = ++_filterToken;
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _allVideos
        : _allVideos
            .where((file) =>
                path.basename(file.path).toLowerCase().contains(query))
            .toList();

    if (!mounted) return;
    setState(() {
      _visibleVideos = filtered;
      _isSorting = filtered.isNotEmpty;
    });

    if (filtered.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isSorting = false;
      });
      return;
    }

    final sorted = await FileSystemSorter.sortFiles(filtered, _sortOption);
    if (!mounted || token != _filterToken) return;
    setState(() {
      _visibleVideos = sorted;
      _isSorting = false;
    });
  }

  /// Start proactive thumbnail generation for all videos in the library
  void _startProactiveThumbnailGeneration() {
    // Only generate for video files
    if (_allVideos.isEmpty) return;
    
    final paths = _allVideos.map((f) => f.path).toList();
    final libraryPath = '#video-library/${widget.library.id}';
    VideoThumbnailHelper.setCurrentDirectory(libraryPath);
    VideoThumbnailHelper.proactiveGenerateAll(paths, directoryPath: libraryPath);
  }

  Future<void> _saveViewMode(ViewMode mode) async {
    try {
      await _preferences.init();
      await _preferences.setViewMode(mode);
    } catch (e) {
      // Ignore preference errors for now.
    }
  }

  Future<void> _saveSortOption(SortOption option) async {
    try {
      await _preferences.init();
      await _preferences.setSortOption(option);
    } catch (e) {
      // Ignore preference errors for now.
    }
  }

  Future<void> _saveGridZoomLevel(int level) async {
    try {
      await _preferences.init();
      await _preferences.setGridZoomLevel(level);
    } catch (e) {
      // Ignore preference errors for now.
    }
  }

  Future<void> _saveColumnVisibility(ColumnVisibility visibility) async {
    try {
      await _preferences.init();
      await _preferences.setColumnVisibility(visibility);
    } catch (e) {
      // Ignore preference errors for now.
    }
  }

  void _toggleViewMode() {
    if (_viewMode == ViewMode.list) {
      _setViewMode(ViewMode.grid);
    } else if (_viewMode == ViewMode.grid) {
      _setViewMode(ViewMode.details);
    } else {
      _setViewMode(ViewMode.list);
    }
  }

  void _setViewMode(ViewMode mode) {
    final resolved = mode == ViewMode.gridPreview ? ViewMode.grid : mode;
    setState(() {
      _viewMode = resolved;
    });
    _saveViewMode(resolved);
  }

  void _setSortOption(SortOption option) {
    if (_sortOption == option) return;
    setState(() {
      _sortOption = option;
    });
    _saveSortOption(option);
    _applyFilters();
  }

  void _handleGridZoomDelta(int delta) {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final nextLevel = (_gridZoomLevel + delta)
        .clamp(UserPreferences.minGridZoomLevel, maxZoom)
        .toInt();
    if (nextLevel == _gridZoomLevel) return;
    setState(() {
      _gridZoomLevel = nextLevel;
    });
    _saveGridZoomLevel(nextLevel);
  }

  void _setGridZoomLevel(int level) {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final nextLevel =
        level.clamp(UserPreferences.minGridZoomLevel, maxZoom).toInt();
    setState(() {
      _gridZoomLevel = nextLevel;
    });
    _saveGridZoomLevel(nextLevel);
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

  void _applySearch(String value) {
    final trimmed = value.trim();
    if (_searchQuery == trimmed) return;
    setState(() {
      _searchQuery = trimmed;
    });
    _applyFilters();
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty) return;
    setState(() {
      _searchQuery = '';
    });
    _searchController.clear();
    _applyFilters();
  }

  void _openSearchBar() {
    setState(() {
      _showSearchBar = true;
    });
    _searchController.text = _searchQuery;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: _searchController.text.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  void _closeSearchBar() {
    setState(() {
      _showSearchBar = false;
    });
    _searchFocusNode.unfocus();
  }

  SelectionState _buildSelectionState() {
    return SelectionState(
      selectedFilePaths: selectedPaths.toSet(),
      selectedFolderPaths: const {},
      isSelectionMode: isSelectionMode,
    );
  }

  String _buildPathLabel(AppLocalizations l10n) {
    final separator = Platform.pathSeparator;
    return '${l10n.videoLibrary}$separator${widget.library.name}';
  }

  void _syncPathField(String value) {
    if (_pathController.text == value) return;
    _pathController.text = value;
    _pathController.selection =
        TextSelection.collapsed(offset: _pathController.text.length);
  }

  Widget _buildPathNavigationBar(String currentPath) {
    _syncPathField(currentPath);
    return tab_components.PathNavigationBar(
      tabId: widget.tabId ?? '',
      pathController: _pathController,
      onPathSubmitted: (_) => _syncPathField(currentPath),
      currentPath: currentPath,
      tabPath: currentPath,
      isNetworkPath: false,
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Icon(
            PhosphorIconsLight.magnifyingGlass,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: l10n.searchByFilename,
                hintStyle: TextStyle(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                isDense: true,
              ),
              onSubmitted: _applySearch,
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(PhosphorIconsLight.x, size: 18),
              tooltip: l10n.clearSearch,
              onPressed: _clearSearch,
            ),
          IconButton(
            icon: const Icon(PhosphorIconsLight.magnifyingGlass, size: 18),
            tooltip: l10n.search,
            onPressed: () => _applySearch(_searchController.text),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsLight.x, size: 18),
            tooltip: l10n.close,
            onPressed: _closeSearchBar,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

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

    setState(() {
      _allVideos = _allVideos
          .where((file) => !deletedPaths.contains(file.path))
          .toList();
      _libraryCache[widget.library.id] = _allVideos;
    });
    exitSelectionMode();
    _applyFilters();
  }

  void _openVideo(File file) {
    ExternalAppHelper.openWithPreferredVideoApp(file.path)
        .then((openedPreferred) {
      if (openedPreferred) return;

      // Default: in-app player. Only system default when user enabled in Settings.
      _preferences.getUseSystemDefaultForVideo().then((useSystem) {
        if (useSystem) {
          ExternalAppHelper.openWithSystemDefault(file.path).then((success) {
            if (!success && mounted) {
              showDialog(
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
    final currentPath = _buildPathLabel(l10n);

    return ScreenScaffold(
      selectionState: selectionState,
      body: _buildBody(l10n),
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
      pathNavigationBar: _buildPathNavigationBar(currentPath),
      actions: SharedActionBar.buildCommonActions(
        context: context,
        onSearchPressed: _openSearchBar,
        onSortOptionSelected: _setSortOption,
        currentSortOption: _sortOption,
        viewMode: _viewMode,
        onViewModeToggled: _toggleViewMode,
        onViewModeSelected: _setViewMode,
        onRefresh: _loadVideos,
        onGridSizePressed: _viewMode == ViewMode.grid
            ? () => SharedActionBar.showGridSizeDialog(
                  context,
                  currentGridSize: _gridZoomLevel,
                  onApply: _setGridZoomLevel,
                  sizeMode: GridSizeMode.referenceWidth,
                )
            : null,
        onColumnSettingsPressed:
            _viewMode == ViewMode.details ? _showColumnSettings : null,
        onSelectionModeToggled: toggleSelectionMode,
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // Disable hero animation to avoid conflicts
        onPressed: toggleSelectionMode,
        child: const Icon(PhosphorIconsLight.checkSquare),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allVideos.isEmpty) {
      return Center(
        child: Text(
          l10n.noVideosInLibrary,
          style: const TextStyle(fontSize: 16),
        ),
      );
    }

    final hasSearch = _searchQuery.trim().isNotEmpty;
    final content = _visibleVideos.isEmpty
        ? Center(
            child: _isSorting
                ? const CircularProgressIndicator()
                : Text(
                    hasSearch
                        ? l10n.noFilesFoundQuery({'query': _searchQuery})
                        : l10n.noVideosInLibrary,
                    style: const TextStyle(fontSize: 16),
                  ),
          )
        : _buildFileView();

    return Column(
      children: [
        // Show search banner if searching
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

  Widget _buildFileView() {
    final state = FolderListState(
      '#video-library/${widget.library.id}',
      files: _visibleVideos,
      folders: const [],
      viewMode: _viewMode,
      sortOption: _sortOption,
      gridZoomLevel: _gridZoomLevel,
    );

    final isGridView =
        _viewMode == ViewMode.grid || _viewMode == ViewMode.gridPreview;

    return FileView(
      files: _visibleVideos,
      folders: const [],
      state: state,
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

  void _toggleFileSelection(String path,
      {bool shiftSelect = false, bool ctrlSelect = false}) {
    final shouldEnterSelection = !isSelectionMode || shiftSelect || ctrlSelect;
    if (shouldEnterSelection && !isSelectionMode) {
      enterSelectionMode();
    }
    toggleSelection(path);
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
