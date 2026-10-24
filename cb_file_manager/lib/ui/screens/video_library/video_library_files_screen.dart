import 'package:cb_file_manager/helpers/core/search_query.dart';
import 'package:cb_file_manager/helpers/core/text_utils.dart';
import 'package:cb_file_manager/helpers/core/search_request_guard.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;
import 'package:cb_file_manager/ui/utils/route.dart';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_action_handlers.dart';
import 'package:cb_file_manager/ui/controllers/file_operations_handler.dart';
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
import 'package:cb_file_manager/helpers/core/filesystem_sorter.dart';
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
import 'package:cb_file_manager/ui/tab_manager/components/navigation_bar.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/utils/view_mode_spectrum.dart';
import 'package:cb_file_manager/ui/widgets/file_list_view_builder.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_keyboard_controller.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_window_transfer.dart';

/// How a library was last shown in this window, or in the window its tab came
/// from. A remounted or moved tab draws in that view at once instead of
/// waiting for its preferences, which showed an empty page meanwhile.
class _LibraryDisplay {
  const _LibraryDisplay({
    required this.viewMode,
    required this.sortOption,
    required this.gridZoomLevel,
    required this.showFileTags,
    required this.columnVisibility,
  });

  final ViewMode viewMode;
  final SortOption sortOption;
  final int gridZoomLevel;
  final bool showFileTags;
  final ColumnVisibility columnVisibility;

  Map<String, dynamic> toJson() => {
    'viewMode': viewMode.name,
    'sortOption': sortOption.name,
    'gridZoomLevel': gridZoomLevel,
    'showFileTags': showFileTags,
    'columns': columnVisibility.toMap(),
  };

  static _LibraryDisplay? fromJson(Map<String, dynamic> json) {
    try {
      return _LibraryDisplay(
        viewMode: ViewMode.values.byName(json['viewMode'] as String),
        sortOption: SortOption.values.byName(json['sortOption'] as String),
        gridZoomLevel: json['gridZoomLevel'] as int,
        showFileTags: json['showFileTags'] as bool,
        columnVisibility: ColumnVisibility.fromMap(
          Map<String, dynamic>.from(json['columns'] as Map),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

class VideoLibraryFilesScreen extends StatefulWidget {
  final VideoLibrary library;
  final String? tabId;

  const VideoLibraryFilesScreen({super.key, required this.library, this.tabId});

  @override
  State<VideoLibraryFilesScreen> createState() =>
      _VideoLibraryFilesScreenState();
}

class _VideoLibraryFilesScreenState extends State<VideoLibraryFilesScreen> {
  final VideoLibraryService _service = VideoLibraryService();
  final UserPreferences _preferences = UserPreferences.instance;
  late VideoLibraryNavigationBloc _bloc;
  late final SelectionBloc _selectionBloc;
  late final FolderListBloc _dragFolderListBloc;
  late final TabbedFolderDragSelectionController _dragSelectionController;
  final ValueNotifier<double> _previewPaneWidthNotifier = ValueNotifier<double>(
    320,
  );
  final TextEditingController _addressController = TextEditingController();

  // Display preferences are applied before the files load (see
  // _loadPreferencesThenLibrary); until then the body stays empty.
  bool _preferencesReady = false;
  String _searchQuery = '';
  List<String> _activeSearchTags = const [];
  Set<String>? _tagMatchedPaths;
  bool _showSearchBar = false;
  final _searchFocusNode = FocusNode(debugLabel: 'video library search');
  bool _useRegexSearch = false;
  bool _isSearchLoading = false;
  List<FileSystemEntity>? _liveSearchSource;
  Set<String> _removedPaths = {};
  bool _showFileTags = true;
  ColumnVisibility _columnVisibility = const ColumnVisibility();
  final _searchRequests = SearchRequestGuard();
  StreamSubscription<String>? _tagChanges;
  Timer? _tagRefreshDebounce;
  int _gridCrossAxisCount = 1;
  ScrollController? _transferScrollController;
  double _initialTransferScroll = 0;

  static final Map<int, _LibraryDisplay> _displays = {};

  @override
  void initState() {
    super.initState();
    final tabId = widget.tabId;
    final initial = tabId == null
        ? <String, dynamic>{}
        : TabWindowTransfer.takeInitial(tabId);
    final transferred = _LibraryDisplay.fromJson(initial);
    _startLibrary(
      transferred ?? _displays[widget.library.id],
      initial: initial,
    );
    if (tabId != null) TabWindowTransfer.register(tabId, _readTransfer);
    final selected =
        (initial['selection'] as List?)?.whereType<String>().toSet() ??
        <String>{};
    _selectionBloc = SelectionBloc(
      initialState: SelectionState(
        selectedFilePaths: selected,
        isSelectionMode: selected.isNotEmpty,
        lastSelectedPath: initial['lastSelected'] as String?,
      ),
    );
    _dragFolderListBloc = FolderListBloc();
    _dragSelectionController = TabbedFolderDragSelectionController(
      folderListBloc: _dragFolderListBloc,
      selectionBloc: _selectionBloc,
    );
    _restoreTransfer(initial);
    _tagChanges = TagManager.onTagChanged.listen((_) {
      if (!mounted || _activeSearchTags.isEmpty) return;
      _tagRefreshDebounce?.cancel();
      _tagRefreshDebounce = Timer(const Duration(milliseconds: 100), () {
        if (mounted && _activeSearchTags.isNotEmpty) {
          unawaited(_applyTagSearch(List.of(_activeSearchTags), false));
        }
      });
    });
  }

  @override
  void didUpdateWidget(VideoLibraryFilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library.id != widget.library.id) {
      _searchRequests.invalidate();
      _tagRefreshDebounce?.cancel();
      _displays[oldWidget.library.id] = _currentDisplay();
      _bloc.close();
      _searchQuery = '';
      _removedPaths = {};
      _activeSearchTags = const [];
      _tagMatchedPaths = null;
      _liveSearchSource = null;
      _isSearchLoading = false;
      _useRegexSearch = false;
      _clearSelection();
      _startLibrary(_displays[widget.library.id]);
    }
  }

  /// Creates the bloc for this library. With a known display it is shown at
  /// once; otherwise the saved preferences are read first.
  void _startLibrary(
    _LibraryDisplay? display, {
    Map<String, dynamic> initial = const {},
  }) {
    if (display == null) {
      _bloc = VideoLibraryNavigationBloc(libraryId: widget.library.id);
      _preferencesReady = false;
      unawaited(_loadPreferencesThenLibrary());
      return;
    }
    _bloc = VideoLibraryNavigationBloc(
      libraryId: widget.library.id,
      initialState:
          FileNavigationState.initial(
            '#video-library/${widget.library.id}',
          ).copyWith(
            viewMode: display.viewMode,
            sortOption: display.sortOption,
            gridZoomLevel: display.gridZoomLevel,
            files: (initial['loadedFiles'] as List?)
                ?.whereType<String>()
                .map(File.new)
                .toList(),
            isLoading: initial['loadedFiles'] is! List,
          ),
    );
    _showFileTags = display.showFileTags;
    _columnVisibility = display.columnVisibility;
    _preferencesReady = true;
    if (initial['loadedFiles'] is! List) _bloc.loadLibrary();
  }

  Map<String, dynamic> _readTransfer() {
    final scroll = _transferScrollController;
    final selection = _selectionBloc.state;
    return {
      ..._currentDisplay().toJson(),
      'library': widget.library.toDatabaseMap(),
      if (!_bloc.state.isLoading)
        'loadedFiles': _bloc.state.files.map((file) => file.path).toList(),
      'query': _searchQuery,
      'regex': _useRegexSearch,
      'searchBar': _showSearchBar,
      'searchLoading': _isSearchLoading,
      'searchTags': _activeSearchTags,
      'tagMatches': _tagMatchedPaths?.toList(),
      'searchSource': _liveSearchSource?.map((file) => file.path).toList(),
      'removed': _removedPaths.toList(),
      'selection': selection.selectedFilePaths.toList(),
      'lastSelected': selection.lastSelectedPath,
      'scroll': scroll != null && scroll.hasClients ? scroll.offset : 0.0,
    };
  }

  void _restoreTransfer(Map<String, dynamic> initial) {
    if (initial.isEmpty) return;
    List<String> strings(String key) =>
        (initial[key] as List?)?.whereType<String>().toList() ?? [];
    _searchQuery = initial['query'] as String? ?? '';
    _useRegexSearch = initial['regex'] == true;
    _showSearchBar = initial['searchBar'] == true;
    _activeSearchTags = strings('searchTags');
    _tagMatchedPaths = initial['tagMatches'] is List
        ? strings('tagMatches').toSet()
        : null;
    _liveSearchSource = initial['searchSource'] is List
        ? strings('searchSource').map(File.new).toList()
        : null;
    _removedPaths = strings('removed').toSet();
    final scroll = initial['scroll'];
    if (scroll is num && scroll.isFinite) {
      _initialTransferScroll = scroll.toDouble().clamp(0.0, double.infinity);
    }
    // An in-flight source search has no completed result to transfer.
    if (initial['searchLoading'] == true) {
      if (_activeSearchTags.isNotEmpty) {
        unawaited(_applyTagSearch(List.of(_activeSearchTags), false));
      } else if (_searchQuery.isNotEmpty) {
        unawaited(_applySearchWithOptions(_searchQuery, _useRegexSearch));
      }
    }
  }

  _LibraryDisplay _currentDisplay() => _LibraryDisplay(
    viewMode: _bloc.state.viewMode,
    sortOption: _bloc.state.sortOption,
    gridZoomLevel: _bloc.state.gridZoomLevel,
    showFileTags: _showFileTags,
    columnVisibility: _columnVisibility,
  );

  @override
  void dispose() {
    if (_preferencesReady) _displays[widget.library.id] = _currentDisplay();
    if (widget.tabId != null) {
      TabWindowTransfer.unregister(widget.tabId!, _readTransfer);
    }
    _searchFocusNode.dispose();
    _tagRefreshDebounce?.cancel();
    _tagChanges?.cancel();
    _searchRequests.dispose();
    _dragSelectionController.dispose();
    _dragFolderListBloc.close();
    _selectionBloc.close();
    _previewPaneWidthNotifier.dispose();
    _addressController.dispose();
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
      final effectiveViewMode = viewMode == ViewMode.gridPreview
          ? ViewMode.grid
          : viewMode;
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
      _bloc.add(FileNavigationSetSortOption(sortOption, persist: false));
      _bloc.add(FileNavigationSetGridZoom(gridZoomLevel));

      setState(() {
        _showFileTags = showFileTags;
        _columnVisibility = columnVisibility;
      });
    } catch (e) {
      // Keep defaults if preferences cannot be loaded.
    }
  }

  /// Applies view mode, sort and zoom, then loads the files. Reading them
  /// after the first file list showed every freshly opened library (a new tab,
  /// or a tab moved to another window) in the default view and order, then
  /// switched.
  Future<void> _loadPreferencesThenLibrary() async {
    final bloc = _bloc;
    await _loadPreferences();
    if (!mounted || !identical(bloc, _bloc)) return;
    setState(() => _preferencesReady = true);
    bloc.loadLibrary();
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
    setState(() {
      _removedPaths = <String>{};
      _searchRequests.invalidate();
      _liveSearchSource = null;
      _isSearchLoading = false;
    });
    // Clear both memory and disk cache before re-scanning
    await VideoLibraryNavigationBloc.invalidateCache(widget.library.id);
    if (!mounted) return;
    _bloc.refreshLibrary();
    if (_activeSearchTags.isNotEmpty) {
      await _applyTagSearch(List.of(_activeSearchTags), false);
    } else if (_searchQuery.isNotEmpty) {
      await _applySearchWithOptions(_searchQuery, _useRegexSearch);
    }
  }

  Future<void> _applyFilters() async {
    final int token = _searchRequests.begin();
    if (!mounted || !_searchRequests.isCurrent(token)) return;
    // Trigger rebuild to re-apply local search filter
    _bloc.add(const FileNavigationClearSearchAndFilters());
  }

  Future<List<FileSystemEntity>> _loadLiveLibraryFiles() async {
    final paths = await _service.getLibraryFiles(widget.library.id);
    final uniquePaths = <String>{};
    final files = <File>[
      for (final filePath in paths)
        if (uniquePaths.add(filePath)) File(filePath),
    ];
    return FileSystemSorter.sortFiles(files, _bloc.state.sortOption);
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
    final nextLevel = level
        .clamp(UserPreferences.minGridZoomLevel, maxZoom)
        .toInt();
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
      onApply: _applyColumnVisibility,
    );
  }

  void _applyColumnVisibility(ColumnVisibility visibility) {
    setState(() {
      _columnVisibility = visibility;
    });
    _saveColumnVisibility(visibility);
  }

  Future<void> _applySearchWithOptions(String value, bool useRegex) async {
    final trimmed = value.trim();
    final int token = _searchRequests.begin();
    setState(() {
      _searchQuery = trimmed;
      _useRegexSearch = useRegex;
      _activeSearchTags = const [];
      _tagMatchedPaths = null;
      _liveSearchSource = null;
      _isSearchLoading = trimmed.isNotEmpty;
    });

    _bloc.add(const FileNavigationClearSearchAndFilters());
    if (trimmed.isEmpty) return;

    try {
      // The navigation state may have come from an older disk cache or may
      // still be receiving a progressive scan. Search the configured library
      // sources directly so a submitted query is evaluated against the full,
      // current collection rather than only the files loaded so far.
      final files = await _loadLiveLibraryFiles();
      if (!mounted || !_searchRequests.isCurrent(token)) return;
      setState(() {
        _liveSearchSource = files;
        _removedPaths = {};
        _isSearchLoading = false;
      });
    } catch (error) {
      if (!mounted || !_searchRequests.isCurrent(token)) return;
      AppLogger.warning(
        'Failed to refresh video library search source',
        error: error,
      );
      setState(() {
        _isSearchLoading = false;
      });
    }
  }

  Future<void> _applyTagSearch(List<String> tags, bool _) async {
    final normalizedTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedTags.isEmpty) return;

    final int token = _searchRequests.begin();
    setState(() {
      _activeSearchTags = normalizedTags;
      _searchQuery = normalizedTags.map((tag) => '#$tag').join(' ');
      _useRegexSearch = false;
      _tagMatchedPaths = null;
      _liveSearchSource = null;
      _isSearchLoading = true;
    });
    try {
      final files = await _loadLiveLibraryFiles();
      if (!mounted || !_searchRequests.isCurrent(token)) return;
      final fileTags = await TagManager.getTagsForFiles(
        files.map((entity) => entity.path).toList(),
      );
      if (!mounted || !_searchRequests.isCurrent(token)) {
        return;
      }

      final matchedPaths = files
          .where((entity) {
            final tagsForFile = fileTags[entity.path] ?? const <String>[];
            return normalizedTags.every(
              (queryTag) => tagsForFile.any(
                (tag) => TextUtils.matchesSearch(tag, queryTag),
              ),
            );
          })
          .map((entity) => entity.path)
          .toSet();

      setState(() {
        _activeSearchTags = normalizedTags;
        _tagMatchedPaths = matchedPaths;
        _searchQuery = normalizedTags.map((tag) => '#$tag').join(' ');
        _useRegexSearch = false;
        _liveSearchSource = files;
        _removedPaths = {};
        _isSearchLoading = false;
      });
      _bloc.add(const FileNavigationClearSearchAndFilters());
    } catch (error) {
      if (!mounted || !_searchRequests.isCurrent(token)) return;
      AppLogger.warning('Failed to search video library tags', error: error);
      setState(() {
        _isSearchLoading = false;
      });
    }
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty &&
        !_useRegexSearch &&
        _activeSearchTags.isEmpty &&
        !_isSearchLoading &&
        _liveSearchSource == null) {
      return;
    }
    setState(() {
      _searchRequests.invalidate();
      _searchQuery = '';
      _useRegexSearch = false;
      _activeSearchTags = const [];
      _tagMatchedPaths = null;
      _liveSearchSource = null;
      _isSearchLoading = false;
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

  void _openOrFocusSearch() {
    if (!_showSearchBar) setState(() => _showSearchBar = true);
    _searchFocusNode.requestFocus();
  }

  void _toggleSelectionMode() {
    _selectionBloc.add(const ToggleSelectionMode());
  }

  void _openVideoGallery() {
    final tabId = widget.tabId;
    if (tabId == null) return;

    TabNavigator.updateTabPath(context, tabId, '#video');
    context.read<TabManagerBloc>().add(
      UpdateTabName(tabId, AppLocalizations.of(context)!.videoHubTitle),
    );
  }

  Widget _buildPathNavigationBar(AppLocalizations l10n) {
    final segments = [
      BreadcrumbSegment(
        label: l10n.videoGallery,
        icon: PhosphorIconsLight.filmStrip,
        onTap: _openVideoGallery,
      ),
      BreadcrumbSegment(label: widget.library.name),
    ];
    final tabId = widget.tabId;

    if (tabId == null) {
      return BreadcrumbAddressBar(segments: segments);
    }

    return PathNavigationBar(
      tabId: tabId,
      pathController: _addressController,
      onPathSubmitted: (_) {},
      currentPath: '#video-library/${widget.library.id}',
      tabPath: '#video-library/${widget.library.id}',
      enablePathEditing: false,
      canNavigateToParent: true,
      onNavigateToParent: _openVideoGallery,
      breadcrumbSegments: segments,
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n) => tab_components.SearchBar(
    focusNode: _searchFocusNode,
    currentPath: '#video-library/${widget.library.id}',
    tabId: widget.tabId ?? '#video-library/${widget.library.id}',
    initialQuery: _searchQuery,
    hintText: l10n.searchByFilename,
    onSearchWithOptions: _applySearchWithOptions,
    onTagSearch: _applyTagSearch,
    onClearSearch: _clearSearch,
    onCloseSearch: _closeSearchBar,
    showClearButton: true,
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
    List<String> selectedFiles, {
    bool permanent = false,
  }) async {
    await _deleteSelectedFiles(selectedFiles, permanent: permanent);
  }

  Future<void> _deleteSelectedFiles(
    List<String> filePaths, {
    bool permanent = false,
  }) async {
    await BrowserLikeActionHandlers.confirmAndMoveFilesToTrash(
      context: context,
      filePaths: filePaths,
      permanent: permanent,
      onMoved: (filePath) =>
          _service.removeFileFromLibrary(widget.library.id, filePath),
      onAfterSuccess: (deletedPaths) async {
        if (!mounted) return;
        _clearSelection();
        // Hide the deleted items in place; a rescan would rebuild the whole
        // list and rerun the search. Only the cache has to forget them.
        setState(() => _removedPaths = {..._removedPaths, ...deletedPaths});
        await VideoLibraryNavigationBloc.invalidateCache(widget.library.id);
      },
      onMoveError: (filePath, _) {
        AppLogger.warning(
          permanent
              ? 'Failed to permanently delete video library file: $filePath'
              : 'Failed to move video library file to trash: $filePath',
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
    final sourceFiles = (_liveSearchSource ?? state.files)
        .where(
          (entity) => !SearchQuery.isRemovedPath(entity.path, _removedPaths),
        )
        .toList();
    if (_activeSearchTags.isNotEmpty) {
      final matchedPaths = _tagMatchedPaths ?? const <String>{};
      return sourceFiles
          .where((entity) => matchedPaths.contains(entity.path))
          .toList();
    }
    return trimmedQuery.isEmpty
        ? sourceFiles
        : _filterFilesBySearch(sourceFiles, trimmedQuery);
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
      currentSearchTag: _activeSearchTags.isEmpty
          ? null
          : _activeSearchTags.join(', '),
      currentSearchQuery: trimmedQuery.isEmpty || _activeSearchTags.isNotEmpty
          ? null
          : trimmedQuery,
    );
  }

  /// Selected videos still on screen; keyboard focus here always selects, so
  /// the selection covers the focused item too.
  List<FileSystemEntity> _selectedVisibleFiles(FileNavigationState state) {
    final selected = _selectionBloc.state.selectedFilePaths;
    return _visibleFilesForState(
      state,
    ).where((entity) => selected.contains(entity.path)).toList();
  }

  void _handleCopy(FileNavigationState state) {
    FileOperationsHandler.copyFilesToClipboard(
      context: context,
      entities: _selectedVisibleFiles(state),
    );
  }

  void _handleCut(FileNavigationState state) {
    FileOperationsHandler.cutFilesToClipboard(
      context: context,
      entities: _selectedVisibleFiles(state),
    );
  }

  Future<void> _handleDelete(
    TabbedFolderKeyboardController keyboardController,
    bool permanent,
  ) async {
    final selectedFiles = _selectionBloc.state.selectedFilePaths.toList();
    if (selectedFiles.isNotEmpty) {
      await _showDeleteFilesConfirmation(
        context,
        selectedFiles,
        permanent: permanent,
      );
      return;
    }

    final focusedPath = keyboardController.focusedPath;
    if (focusedPath == null || focusedPath.isEmpty) return;

    final visiblePaths = _visibleFilesForState(
      _bloc.state,
    ).map((entity) => entity.path).toSet();
    if (!visiblePaths.contains(focusedPath)) return;

    await _showDeleteFilesConfirmation(context, <String>[
      focusedPath,
    ], permanent: permanent);
  }

  void _openVideo(File file) {
    ExternalAppHelper.openWithPreferredVideoApp(file.path).then((
      openedPreferred,
    ) {
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
            return BlocBuilder<VideoLibraryNavigationBloc, FileNavigationState>(
              builder: (context, state) {
                final folderListState = _folderListStateFor(state);
                return BrowserLikeFileSurface(
                  selectionState: selectionState,
                  viewMode: state.viewMode,
                  initialScrollOffset: _initialTransferScroll,
                  isDesktop: isDesktop,
                  visiblePaths: _visibleFilesForState(
                    state,
                  ).map((entity) => entity.path),
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
                  selectRange:
                      ({
                        required Set<String> folderPaths,
                        required Set<String> filePaths,
                        required String lastSelectedPath,
                        required bool ctrlSelect,
                      }) {
                        _selectionBloc.add(
                          SelectItemsInRect(
                            folderPaths: const <String>{},
                            filePaths: filePaths,
                            isCtrlPressed: ctrlSelect,
                            isShiftPressed: true,
                            lastSelectedPath: lastSelectedPath,
                          ),
                        );
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
                    allowMetadataSorting: true,
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
                  onSearch: _openOrFocusSearch,
                  onSelectAll: () => _selectAllVisible(state),
                  onCopy: () => _handleCopy(state),
                  onCut: () => _handleCut(state),
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
    _transferScrollController = keyboardController.scrollController;
    // Neither a skeleton nor files in a view mode that is about to change.
    if (!_preferencesReady) return const SizedBox.shrink();

    final isGridView =
        state.viewMode == ViewMode.grid ||
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
        child: state.isLoading || _isSearchLoading
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
      onColumnVisibilityChanged: _applyColumnVisibility,
      showContextMenu: (_, _) {},
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
          .where(
            (file) => TextUtils.matchesVietnamese(
              path.basename(file.path),
              normalizedQuery,
            ),
          )
          .toList();
    }

    RegExp pattern;
    try {
      pattern = RegExp(query, caseSensitive: false, unicode: true);
    } catch (_) {
      return const [];
    }

    return files
        .where((file) => pattern.hasMatch(path.basename(file.path)))
        .toList();
  }

  void _toggleFileSelection(
    String filePath, {
    bool shiftSelect = false,
    bool ctrlSelect = false,
  }) {
    if (!shiftSelect) {
      _selectionBloc.add(
        ToggleFileSelection(
          filePath,
          shiftSelect: false,
          ctrlSelect: ctrlSelect,
        ),
      );
      return;
    }

    final selectionState = _selectionBloc.state;
    if (selectionState.lastSelectedPath == null) {
      _selectionBloc.add(
        ToggleFileSelection(
          filePath,
          shiftSelect: false,
          ctrlSelect: ctrlSelect,
        ),
      );
      return;
    }

    final allPaths = _visibleFilesForState(
      _bloc.state,
    ).map((entity) => entity.path).toList();
    final currentIndex = allPaths.indexOf(filePath);
    final lastIndex = allPaths.indexOf(selectionState.lastSelectedPath!);
    if (currentIndex == -1 || lastIndex == -1) return;

    final start = currentIndex < lastIndex ? currentIndex : lastIndex;
    final end = currentIndex < lastIndex ? lastIndex : currentIndex;
    _selectionBloc.add(
      SelectItemsInRect(
        folderPaths: const <String>{},
        filePaths: allPaths.sublist(start, end + 1).toSet(),
        isCtrlPressed: ctrlSelect,
        isShiftPressed: true,
        lastSelectedPath: filePath,
      ),
    );
  }

  void _showAddTagToFileDialog(BuildContext context, String filePath) {
    AppLogger.info(
      '[ManageTags][VideoLibrary] _showAddTagToFileDialog',
      error: 'filePath=$filePath',
    );
    tag_dialogs.showAddTagToFileDialog(context, filePath);
  }

  void _showDeleteTagDialog(
    BuildContext context,
    String filePath,
    List<String> tags,
  ) {
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
