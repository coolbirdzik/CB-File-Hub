import 'package:cb_file_manager/design_system/primitives/cb_loading_text.dart';
import 'package:cb_file_manager/design_system/primitives/cb_popover_transition.dart';
import 'package:cb_file_manager/ui/widgets/file_properties_pane.dart';
import 'package:cb_file_manager/ui/widgets/file_pane_layout.dart';
import 'package:cb_file_manager/ui/widgets/file_preview_pane.dart';
import 'package:cb_file_manager/helpers/core/search_query.dart';
import 'package:cb_file_manager/services/drive/drive_browser_entries.dart';
import 'dart:async';
import 'package:cb_file_manager/ui/widgets/file_drag_drop_item.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/config/translation_helper.dart';
import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';
import 'package:cb_file_manager/services/desktop_integration/windows_folder_elevation.dart';
import 'package:cb_file_manager/services/file_drag_drop/file_drag_drop_move_service.dart';
import 'package:cb_file_manager/services/windowing/windows_explorer_drag_drop_service.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_action_handlers.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_display_state.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_keyboard_shortcuts.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/components/common/delete_failure_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/file_browser_options.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/tab_manager/shared/screen_menu_registry.dart';
import 'package:cb_file_manager/ui/components/common/skeleton_helper.dart';
import '../tab_manager.dart';
import '../tab_paths.dart';
import '../tab_focus_gate.dart';
import 'package:cb_file_manager/ui/utils/fluent_background.dart';
import 'package:path/path.dart' as path;

// Import folder list components with explicit alias
import '../../../screens/folder_list/folder_list_bloc.dart';
import '../../../screens/folder_list/folder_list_event.dart';
import '../../../screens/folder_list/folder_list_state.dart';
import '../../../screens/folder_list/folder_display_preferences.dart';

// Import selection bloc
import 'package:cb_file_manager/bloc/selection/selection.dart';

// Import our new components with a clear namespace
import '../../components/index.dart' as tab_components;
import '../tab_data.dart';
import '../tab_window_transfer.dart';
import 'tabbed_folder_drag_selection_controller.dart';
import 'tabbed_folder_keyboard_controller.dart';
import 'package:cb_file_manager/ui/screens/system_screen_router.dart';

import '../../../components/common/screen_scaffold.dart';
import '../../mobile/mobile_file_actions_controller.dart';
import 'package:cb_file_manager/ui/utils/platform_utils.dart';

// Import extracted foundation components
import 'package:cb_file_manager/ui/controllers/file_operations_handler.dart';
import 'package:cb_file_manager/ui/controllers/lazy_loading_manager.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:cb_file_manager/ui/menus/folder_background_context_menu.dart';
import 'package:cb_file_manager/ui/mixins/preferences_manager_mixin.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_pane_state.dart';
import 'package:cb_file_manager/ui/controllers/search_filter_manager.dart';
import 'package:cb_file_manager/ui/controllers/refresh_controller.dart';
import 'package:cb_file_manager/ui/controllers/navigation_controller.dart';
import 'package:cb_file_manager/ui/controllers/selection_coordinator.dart';
import 'package:cb_file_manager/ui/controllers/tab_lifecycle_manager.dart';
import 'package:cb_file_manager/ui/controllers/tag_search_initializer.dart';
import 'package:cb_file_manager/ui/controllers/app_bar_actions_builder.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/widgets/selection_summary_tooltip.dart';

// Import extracted view layer components
import 'package:cb_file_manager/ui/widgets/file_list_view_builder.dart';
import 'package:cb_file_manager/ui/widgets/ctrl_scroll_zoom.dart';
import 'package:cb_file_manager/ui/controllers/dialog_manager.dart';
import 'package:cb_file_manager/ui/widgets/folder_content_builder.dart';
import 'package:cb_file_manager/ui/widgets/refreshable_file_list_view.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/ui/widgets/slim_progress_bar.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/tab_activity/tab_activity_manager.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';

part 'tabbed_folder_list_screen.mobile_actions.dart';
part 'tabbed_folder_list_screen.refresh.dart';

/// Data class carrying the widgets needed to render the shared appbar in split-pane mode.
/// Scroll offset and focused item of a folder, remembered when the user
/// leaves it so that going back restores the same view.
class _FolderViewMemory {
  const _FolderViewMemory({required this.scrollOffset, this.focusedPath});

  final double scrollOffset;
  final String? focusedPath;
}

/// A restore that is waiting for the destination folder to finish loading.
class _PendingViewRestore {
  const _PendingViewRestore({
    required this.normalizedPath,
    this.scrollOffset,
    this.focusedPath,
  });

  final String normalizedPath;
  final double? scrollOffset;
  final String? focusedPath;
}

class SplitPaneAppBarData {
  final Widget titleWidget;
  final List<Widget> actions;
  final bool isSelectionMode;
  final Widget? selectionAppBar;
  final VoidCallback? onSearch;

  const SplitPaneAppBarData({
    required this.titleWidget,
    required this.actions,
    this.isSelectionMode = false,
    this.selectionAppBar,
    this.onSearch,
  });
}

/// A modified version of FolderListScreen that works with the tab system
class TabbedFolderListScreen extends StatefulWidget {
  final String path;
  final String tabId;
  final bool showAppBar; // Thêm tham số để kiểm soát việc hiển thị AppBar
  final String? searchTag; // Add parameter for tag search
  final bool globalTagSearch; // Add parameter to control global vs local search
  final String? highlightedFileName;

  /// When non-null, the screen will NOT render its own appbar. Instead it will
  /// push appbar data into this notifier so the parent (e.g. SplitPaneView)
  /// can render a shared bar.
  final ValueNotifier<SplitPaneAppBarData?>? appBarDataNotifier;

  const TabbedFolderListScreen({
    super.key,
    required this.path,
    required this.tabId,
    this.showAppBar = true, // Mặc định là hiển thị AppBar
    this.searchTag, // Optional tag to search for
    this.globalTagSearch = false, // Default to local search
    this.highlightedFileName,
    this.appBarDataNotifier,
  });

  @override
  State<TabbedFolderListScreen> createState() => _TabbedFolderListScreenState();
}

class _TabbedFolderListScreenState extends State<TabbedFolderListScreen>
    with PreferencesManagerMixin {
  late TextEditingController _searchController;
  final _searchFocusNode = FocusNode(debugLabel: 'folder search');
  late TextEditingController _tagController;
  late TextEditingController _pathController;
  String? _currentFilter;
  String? _currentSearchTag;

  // Add flag for lazy loading drives
  bool _isLazyLoadingDrives = false;
  String? _pendingHighlightedFileName;

  // Per-tab memory of each visited folder's scroll offset and focused item,
  // keyed by normalized path. Static so it survives the screen being rebuilt
  // when the tab switches between folder / drives / other screens.
  static const int _maxViewMemoryTabs = 30;
  static const int _maxViewMemoryFolders = 50;
  static final Map<String, Map<String, _FolderViewMemory>> _viewMemoryByTab =
      <String, Map<String, _FolderViewMemory>>{};
  _PendingViewRestore? _pendingViewRestore;
  int _viewRestoreGeneration = 0;
  bool _freshNavigation = false;
  String? _viewStateCapturedFor;
  String? _highlightedScrollTargetPath;
  int _highlightedScrollAttempts = 0;
  final _propertiesPaneFocusNode = FocusNode(debugLabel: 'properties pane');
  bool _propertiesPaneVisible = false;
  double _propertiesPaneHeight = 260;
  bool _propertiesPaneTouched = false;
  bool _preferencesLoaded = false;
  double? _gridItemMainAxisExtent;

  // Replace ValueNotifier with SelectionBloc
  late SelectionBloc _selectionBloc;

  // Trạng thái hiển thị thanh tìm kiếm
  bool _showSearchBar = false;
  String _driveSearchQuery = '';
  bool _drivePropertiesVisible = false;
  final Set<tab_components.DriveDetailsColumn> _driveColumns = tab_components
      .DriveDetailsColumn
      .values
      .toSet();

  // Current path displayed in this tab
  String _currentPath = '';
  // Flag to indicate whether we're in path editing mode

  // View and sort preferences are now managed by PreferencesManagerMixin
  // late ViewMode _viewMode;
  // late int _gridZoomLevel;
  // late ColumnVisibility _columnVisibility;
  // late bool _showFileTags;

  // Refresh state
  bool _isRefreshing = false;
  String? _lastShownFolderError;

  /// Set true while a refocus-from-inactive reload is in flight. Drives the
  /// dedicated "restoring tab" UI (skeleton + slim progress bar + status
  /// hint) so the user sees an explicit loading state rather than a stale
  /// or empty screen while caches are warmed back up.
  bool _isRestoringFromInactive = false;

  // Create the bloc instance at the class level
  late FolderListBloc _folderListBloc;

  // RefreshController instance
  late RefreshController _refreshController;

  // Navigation and Selection controllers
  late NavigationController _navigationController;
  late SelectionCoordinator _selectionCoordinator;

  // Override the getter required by PreferencesManagerMixin
  @override
  FolderListBloc get folderListBloc => _folderListBloc;

  @override
  String get preferencePath => _currentPath;

  // Preview pane visibility follows the tab, not the folder.
  @override
  bool? get sessionPreviewPaneVisible =>
      TabPaneState.previewVisible(widget.tabId);

  @override
  void onPreviewPaneVisibilityChanged(bool visible) =>
      TabPaneState.setPreviewVisible(widget.tabId, visible);

  // Global search toggle for tag search
  bool isGlobalSearch = false;

  // Flag to track if we're handling a path update to avoid duplicate loads
  bool _isHandlingPathUpdate = false;

  late final TabbedFolderDragSelectionController _dragSelectionController;
  late final TabbedFolderKeyboardController _keyboardController;
  late final ValueNotifier<double> _previewPaneWidthNotifier;

  // Controller for inline rename on desktop
  late final InlineRenameController _inlineRenameController;
  String? _pendingCreatedFilePath;
  int _createdItemRenameGeneration = 0;
  Set<String> _pendingDeletedFocusPaths = const {};
  String? _pendingNextFocusPathAfterDelete;
  bool _allowFileExtensionRename = false;
  late FileBrowserOptions _lastBrowserOptions;
  bool _isMasonryLayout = false;

  /// Actual grid crossAxisCount from the file list (for arrow up/down in grid).
  int? _gridCrossAxisCount;

  // Flag to track if there are background thumbnail tasks
  bool _hasPendingThumbnails = false;
  StreamSubscription<int>? _pendingTasksSubscription;
  StreamSubscription<WindowsExplorerFileDropEvent>? _fileDropSubscription;
  StreamSubscription<FolderListState>? _transferRestoreSubscription;

  Map<String, dynamic> _captureWindowState() {
    final folder = _folderListBloc.state;
    final selection = _selectionBloc.state;
    final scroll = _keyboardController.scrollController;
    return {
      'scroll': scroll.hasClients ? scroll.offset : 0.0,
      'files': selection.selectedFilePaths.toList(),
      'folders': selection.selectedFolderPaths.toList(),
      'lastSelected': selection.lastSelectedPath,
      'focused': _keyboardController.focusedPath,
      'searchBar': _showSearchBar,
      'query': folder.currentSearchQuery,
      'recursive': folder.searchRecursive,
      'filter': folder.currentFilter,
      'viewMode': folder.viewMode.name,
      'sort': folder.sortOption.name,
      'zoom': folder.gridZoomLevel,
    };
  }

  void _restoreWindowState(Map<String, dynamic> initial) {
    if (initial.isEmpty) return;
    _showSearchBar = initial['searchBar'] == true;
    _searchController.text = initial['query'] as String? ?? '';
    var searchStarted = false;
    var restored = false;
    _transferRestoreSubscription = _folderListBloc.stream.listen((state) {
      if (restored ||
          state.isLoading ||
          state.isRefreshing ||
          state.currentPath.path != _currentPath) {
        return;
      }
      if (!searchStarted) {
        searchStarted = true;
        final query = initial['query'] as String?;
        if (query != null && query.isNotEmpty) {
          _folderListBloc.add(
            SearchByFileName(query, recursive: initial['recursive'] == true),
          );
          return;
        }
      }
      restored = true;
      _transferRestoreSubscription?.cancel();
      final view = ViewMode.values
          .where((v) => v.name == initial['viewMode'])
          .firstOrNull;
      final sort = SortOption.values
          .where((v) => v.name == initial['sort'])
          .firstOrNull;
      if (view != null) _folderListBloc.add(SetViewMode(view));
      if (sort != null) {
        _folderListBloc.add(
          SetSortOption(sort, persist: false, folderPath: _currentPath),
        );
      }
      if (initial['zoom'] is int) {
        _folderListBloc.add(SetGridZoom(initial['zoom'] as int));
      }
      if (initial['filter'] is String) {
        _folderListBloc.add(FolderListFilter(initial['filter'] as String));
      }
      _selectionBloc.add(
        SelectItemsInRect(
          filePaths: (initial['files'] as List? ?? [])
              .whereType<String>()
              .toSet(),
          folderPaths: (initial['folders'] as List? ?? [])
              .whereType<String>()
              .toSet(),
          lastSelectedPath: initial['lastSelected'] as String?,
        ),
      );
      _keyboardController.focusedPath = initial['focused'] as String?;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scroll = _keyboardController.scrollController;
        final offset = initial['scroll'];
        if (scroll.hasClients && offset is num && offset.isFinite) {
          scroll.jumpTo(
            offset.toDouble().clamp(0, scroll.position.maxScrollExtent),
          );
        }
      });
    });
  }

  // Add a method to check if there are any video/image files in the current state
  bool _hasVideoOrImageFiles(FolderListState state) {
    return state.files.any((file) => FileTypeUtils.isMediaFile(file.path));
  }

  bool _isPointerInsideFocusedEditableText(PointerDownEvent event) =>
      _isPointerInside(FocusManager.instance.primaryFocus?.context, event);

  bool _isPointerInside(BuildContext? context, PointerDownEvent event) {
    if (context == null || !context.mounted) return false;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    return rect.contains(event.position);
  }

  bool _isDrivesPathValue(String path) {
    return isDrivesPath(path) || path.isEmpty;
  }

  bool _isDrivesMode() => _isDrivesPathValue(_currentPath);

  /// Scrolls the list/grid when the focused item is outside the viewport.
  void _scrollToIndex(
    int index,
    int crossAxisCount,
    double itemMainAxisExtent,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sc = _keyboardController.scrollController;
      if (!sc.hasClients || !sc.position.hasContentDimensions) return;

      final pos = sc.position;
      final int rowIndex = (index / crossAxisCount).floor();
      final double itemStart = rowIndex * itemMainAxisExtent;
      final double itemEnd = itemStart + itemMainAxisExtent;
      final double viewStart = pos.pixels;
      final double viewEnd = viewStart + pos.viewportDimension;

      if (itemEnd > viewEnd) {
        final double target = (itemEnd - pos.viewportDimension).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        sc.jumpTo(target);
      } else if (itemStart < viewStart) {
        sc.jumpTo(itemStart.clamp(pos.minScrollExtent, pos.maxScrollExtent));
      }
    });
  }

  void _setMasonryLayout(bool enabled) {
    setState(() {
      _isMasonryLayout = enabled;
    });
  }

  Widget _buildAcrylicContentContainer({
    required BuildContext context,
    required Widget child,
  }) {
    if (isDesktopPlatform) {
      return child;
    }

    return FluentBackground.container(
      context: context,
      enableBlur: true,
      blurAmount: 10.0,
      opacity: 0.70,
      backgroundColor: null,
      padding: EdgeInsets.zero,
      child: child,
    );
  }

  String _displayPathForInput(String path) {
    if (_isDrivesPathValue(path)) return '';
    if (ArchivePathUtils.isArchiveBrowsePath(path)) {
      return ArchivePathUtils.displayPath(path);
    }
    return path;
  }

  @override
  void initState() {
    super.initState();
    _currentPath = widget.path;
    _pendingHighlightedFileName = widget.highlightedFileName;
    _searchController = TextEditingController();
    _tagController = TextEditingController();
    _pathController = TextEditingController(
      text: _displayPathForInput(_currentPath),
    );
    _keyboardController = TabbedFolderKeyboardController();
    _previewPaneWidthNotifier = ValueNotifier<double>(previewPaneWidth);
    // Restore this tab's pane toggles right away so a rebuilt screen (e.g.
    // back from a system path) doesn't flash the defaults first.
    isPreviewPaneVisible =
        TabPaneState.previewVisible(widget.tabId) ?? isPreviewPaneVisible;
    _propertiesPaneVisible =
        TabPaneState.propertiesVisible(widget.tabId) ?? _propertiesPaneVisible;
    _inlineRenameController = InlineRenameController();
    FileBrowserHelper.setInlineRenameController(
      _inlineRenameController,
      tabId: widget.tabId,
    );
    FileBrowserHelper.setAfterFileCreatedCallback(
      _handleCreatedFile,
      tabId: widget.tabId,
    );
    FileBrowserHelper.setCreateFolderCallback(
      _showCreateFolderDialog,
      tabId: widget.tabId,
    );

    // If this is a new tab with empty path (drive view), enable lazy loading
    if (_isDrivesPathValue(_currentPath)) {
      _isLazyLoadingDrives = true;
      // Schedule drive loading after UI is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startLazyLoadingDrives();
      });
    }

    // Listen for thumbnail loading changes
    _pendingTasksSubscription = ThumbnailLoader.onPendingTasksChanged.listen((
      count,
    ) {
      final hasBackgroundTasks = count > 0;
      if (_hasPendingThumbnails != hasBackgroundTasks) {
        setState(() {
          _hasPendingThumbnails = hasBackgroundTasks;
        });
      }
    });

    // Initialize the blocs. The bloc applies each folder's saved view mode
    // and sort in the same emit as the new path.
    _folderListBloc = FolderListBloc(applyFolderDisplayPreferences: true);
    // Saved settings are usually in memory already: start with them instead
    // of the defaults, so the first frame does not jump once they load.
    final cachedDisplay = FolderDisplayPreferences.instance.cached(
      _currentPath,
    );
    if (cachedDisplay != null) {
      applyDisplaySettings(cachedDisplay, inInitState: true);
    }

    // Initialize tag search using TagSearchInitializer
    final tagSearchConfig = TagSearchInitializer.initialize(
      searchTag: widget.searchTag,
      globalTagSearch: widget.globalTagSearch,
      path: widget.path,
      folderListBloc: _folderListBloc,
      tagController: _tagController,
      isMounted: mounted,
    );

    _currentSearchTag = tagSearchConfig.currentSearchTag;
    isGlobalSearch = tagSearchConfig.isGlobalSearch;

    // Initialize selection bloc
    _selectionBloc = SelectionBloc();
    TabWindowTransfer.register(widget.tabId, _captureWindowState);
    _restoreWindowState(TabWindowTransfer.takeInitial(widget.tabId));
    _dragSelectionController = TabbedFolderDragSelectionController(
      folderListBloc: _folderListBloc,
      selectionBloc: _selectionBloc,
    );
    _fileDropSubscription = WindowsExplorerDragDropService.fileDrops.listen(
      _handleNativeFileDrop,
    );

    _saveLastAccessedFolder();

    // Load preferences using mixin
    loadPreferences().then((_) {
      if (!mounted) return;
      _preferencesLoaded = true;
      _previewPaneWidthNotifier.value = previewPaneWidth;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _maybeScrollToHighlightedFile(_folderListBloc.state);
        }
      });
    });
    _loadAllowFileExtensionRenamePreference();
    _loadPropertiesPanePreferences();

    // Initialize RefreshController
    _refreshController = RefreshController(
      folderListBloc: _folderListBloc,
      tabManagerBloc: context.read<TabManagerBloc>(),
      tabId: widget.tabId,
    );

    // Initialize NavigationController
    _navigationController = NavigationController(
      tabId: widget.tabId,
      tabManagerBloc: context.read<TabManagerBloc>(),
      folderListBloc: _folderListBloc,
      onPathChanged: _handleCurrentPathChanged,
      onSaveLastAccessedFolder: _saveLastAccessedFolder,
    );

    // Initialize SelectionCoordinator
    _selectionCoordinator = SelectionCoordinator(
      selectionBloc: _selectionBloc,
      folderListBloc: _folderListBloc,
      clearKeyboardFocus: () => _keyboardController.clearFocus(),
    );
    _lastBrowserOptions = UserPreferences.instance.fileBrowserOptions.value;
    UserPreferences.instance.fileBrowserOptions.addListener(
      _onBrowserOptionsChanged,
    );
    UserPreferences.instance.allowFileExtensionRename.addListener(
      _onRenameExtensionPreferenceChanged,
    );

    // Register mobile file actions controller for mobile UI
    if (Platform.isAndroid || Platform.isIOS) {
      _registerMobileActionsController();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Use TabLifecycleManager to handle tab lifecycle
    TabLifecycleManager.handleDidChangeDependencies(
      context: context,
      tabId: widget.tabId,
      currentPath: _currentPath,
      folderListBloc: _folderListBloc,
      isMounted: mounted,
      onPathUpdate: _updatePath,
    );
  }

  @override
  void didUpdateWidget(TabbedFolderListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Use TabLifecycleManager to handle widget updates
    TabLifecycleManager.handleDidUpdateWidget(
      oldPath: oldWidget.path,
      newPath: widget.path,
      currentPath: _currentPath,
      onPathUpdate: _updatePath,
    );

    if (oldWidget.highlightedFileName != widget.highlightedFileName) {
      _pendingHighlightedFileName = widget.highlightedFileName;
      _highlightedScrollTargetPath = null;
      _highlightedScrollAttempts = 0;
    }
  }

  @override
  void dispose() {
    UserPreferences.instance.fileBrowserOptions.removeListener(
      _onBrowserOptionsChanged,
    );
    UserPreferences.instance.allowFileExtensionRename.removeListener(
      _onRenameExtensionPreferenceChanged,
    );
    VideoThumbnailHelper.clearFocusedFolderFill(widget.tabId);
    TabWindowTransfer.unregister(widget.tabId, _captureWindowState);
    _transferRestoreSubscription?.cancel();
    // Clean up resources
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tagController.dispose();
    _pathController.dispose();
    _folderListBloc.close();
    _selectionBloc.close();

    _dragSelectionController.dispose();
    _keyboardController.dispose();
    _previewPaneWidthNotifier.dispose();
    _propertiesPaneFocusNode.dispose();
    _inlineRenameController.dispose();
    FileBrowserHelper.setInlineRenameController(null, tabId: widget.tabId);
    FileBrowserHelper.setAfterFileCreatedCallback(null, tabId: widget.tabId);
    FileBrowserHelper.setCreateFolderCallback(null, tabId: widget.tabId);
    _pendingTasksSubscription?.cancel();
    _fileDropSubscription?.cancel();

    // Remove mobile actions controller
    if (Platform.isAndroid || Platform.isIOS) {
      MobileFileActionsController.removeTab(widget.tabId);
    }

    super.dispose();
  }

  // Register mobile actions controller to connect mobile action buttons with this screen
  void _registerMobileActionsController() =>
      _registerMobileActionsControllerImpl();

  // Helper methods
  Future<void> _saveLastAccessedFolder() async {
    try {
      final directory = Directory(_currentPath);
      if (await directory.exists()) {
        final UserPreferences prefs = UserPreferences.instance;
        await prefs.init();
        await prefs.setLastAccessedFolder(_currentPath);
      }
    } catch (e) {
      debugPrint('Error saving last accessed folder: $e');
    }
  }

  // Preferences methods are now provided by PreferencesManagerMixin

  void _toggleSelectionMode({bool? forceValue}) {
    _selectionCoordinator.toggleSelectionMode(forceValue: forceValue);
  }

  Future<void> _loadPropertiesPanePreferences() async {
    // Visibility follows the tab and a new tab starts with the pane closed.
    // The height stays a global preference.
    final height = await UserPreferences.instance.getPropertiesPaneHeight();
    if (!mounted || _propertiesPaneTouched) return;
    setState(() {
      _propertiesPaneVisible =
          TabPaneState.propertiesVisible(widget.tabId) ?? false;
      _propertiesPaneHeight = height;
    });
  }

  void _togglePropertiesPane() {
    _propertiesPaneTouched = true;
    setState(() => _propertiesPaneVisible = !_propertiesPaneVisible);
    TabPaneState.setPropertiesVisible(widget.tabId, _propertiesPaneVisible);
  }

  Widget _buildBodyWithProperties(
    BuildContext context,
    FolderListState state,
    SelectionState selection,
    bool isNetworkPath,
  ) {
    final body = _buildBody(context, state, selection, isNetworkPath);
    if (!isDesktopPlatform || _isDrivesMode()) return body;
    return FilePropertiesPane(
      headerLeading: const FilePaneDragHandle(pane: FilePane.properties),
      paneLayoutBuilder: (context, panel) => ValueListenableBuilder<double>(
        valueListenable: _previewPaneWidthNotifier,
        builder: (context, width, _) => FilePaneLayout(
          files: body,
          preview: FilePreviewPane(
            state: state,
            selectionState: selection,
            onOpenFile: _onFileTap,
            onClosePreview: _togglePreviewPane,
            headerLeading: const FilePaneDragHandle(pane: FilePane.preview),
          ),
          properties: panel,
          previewVisible: isPreviewPaneVisible,
          propertiesVisible: _propertiesPaneVisible,
          previewWidth: width,
          propertiesHeight: _propertiesPaneHeight,
          listFocusNode: _keyboardController.focusNode,
          previewFocusNode: _keyboardController.previewFocusNode,
        ),
      ),
      panelFocusNode: _propertiesPaneFocusNode,
      filePaths: selection.selectedFilePaths.toList(),
      folderPaths: selection.selectedFolderPaths.toList(),
      visible: _propertiesPaneVisible,
      height: _propertiesPaneHeight,
      onClose: _togglePropertiesPane,
      onHeightChanged: (height) {
        _propertiesPaneTouched = true;
        setState(() => _propertiesPaneHeight = height);
        unawaited(UserPreferences.instance.setPropertiesPaneHeight(height));
      },
      bottomInset: SelectionSummaryTooltip.isVisibleFor(selection)
          ? SelectionSummaryTooltip.height
          : 0,
      child: body,
    );
  }

  void _togglePreviewPane() {
    togglePreviewPaneVisibility();
  }

  void _updatePreviewPaneWidth(double width) {
    previewPaneWidth = width;
    _previewPaneWidthNotifier.value = width;
  }

  void _commitPreviewPaneWidth(double width) {
    previewPaneWidth = width;
    _previewPaneWidthNotifier.value = width;
    savePreviewPaneWidthSetting(width);
  }

  void _toggleFileSelection(
    String filePath, {
    bool shiftSelect = false,
    bool ctrlSelect = false,
  }) {
    _keyboardController.focusPickedPath(
      filePath,
      shiftSelect: shiftSelect,
      previousSelectedPath: _selectionBloc.state.lastSelectedPath,
    );
    _showImmediateSelectionForToggle(
      filePath,
      shiftSelect: shiftSelect,
      ctrlSelect: ctrlSelect,
    );
    _selectionCoordinator.toggleFileSelection(
      filePath,
      shiftSelect: shiftSelect,
      ctrlSelect: ctrlSelect,
    );
  }

  void _toggleFolderSelection(
    String folderPath, {
    bool shiftSelect = false,
    bool ctrlSelect = false,
  }) {
    _keyboardController.focusPickedPath(
      folderPath,
      shiftSelect: shiftSelect,
      previousSelectedPath: _selectionBloc.state.lastSelectedPath,
    );
    _showImmediateSelectionForToggle(
      folderPath,
      shiftSelect: shiftSelect,
      ctrlSelect: ctrlSelect,
    );
    _selectionCoordinator.toggleFolderSelection(
      folderPath,
      shiftSelect: shiftSelect,
      ctrlSelect: ctrlSelect,
    );
  }

  void _showImmediateSelectionForToggle(
    String path, {
    required bool shiftSelect,
    required bool ctrlSelect,
  }) {
    if (!isDesktopPlatform || shiftSelect) {
      _keyboardController.clearImmediateSelection();
      return;
    }

    final currentPaths = _selectionBloc.state.allSelectedPaths.toSet();
    final nextPaths = ctrlSelect ? Set<String>.of(currentPaths) : <String>{};
    if (ctrlSelect && nextPaths.contains(path)) {
      nextPaths.remove(path);
    } else {
      nextPaths.add(path);
    }
    _keyboardController.showImmediateSelection(
      nextPaths,
      currentSelectedPaths: currentPaths,
    );
  }

  void _clearSelection() {
    _selectionCoordinator.clearSelection();
  }

  void _onBrowserOptionsChanged() {
    final next = UserPreferences.instance.fileBrowserOptions.value;
    // Never leave selected items hidden from view after turning visibility off.
    if ((_lastBrowserOptions.showHidden && !next.showHidden) ||
        (_lastBrowserOptions.showSystem && !next.showSystem)) {
      _clearSelection();
    }
    _lastBrowserOptions = next;
  }

  void _startFileDrag(List<String> paths) {
    if (!Platform.isWindows || paths.isEmpty) return;
    WindowsExplorerDragDropService.startFileDrag(paths).then((result) {
      if (!mounted) return;
      if (result == WindowsExplorerDragResult.moved && !_isDrivesMode()) {
        final movedPaths = paths
            .where(
              (path) =>
                  FileSystemEntity.typeSync(path, followLinks: false) ==
                  FileSystemEntityType.notFound,
            )
            .toSet();
        if (movedPaths.isNotEmpty) {
          _folderListBloc.add(FolderListRemovePaths(movedPaths));
        }
        _folderListBloc.add(FolderListRefresh(_currentPath));
        _selectionBloc.add(ClearSelection());
      }
    });
  }

  Future<void> _handleNativeFileDrop(WindowsExplorerFileDropEvent event) async {
    if (!mounted || !Platform.isWindows) return;
    if (context.read<TabManagerBloc>().state.activeTabId != widget.tabId) {
      return;
    }
    final hitFolder = FileDragDropItem.folderAt(context, event.globalPosition);
    // Search results can expose real destination folders even though the tab
    // itself has a virtual path. Only a background drop needs a real cwd.
    if (hitFolder == null &&
        (_currentPath.startsWith('#') || _isDrivesMode())) {
      return;
    }
    await _moveDroppedItemsToFolder(event.paths, hitFolder ?? _currentPath);
  }

  Future<void> _moveDroppedItemsToFolder(
    List<String> sources,
    String destinationFolder,
  ) async {
    final rejection = await FileDragDropMoveService.move(
      sources: sources,
      destination: destinationFolder,
    );
    if (!mounted) return;

    switch (rejection) {
      case FileDragDropMoveRejection.none:
        _selectionBloc.add(ClearSelection());
        _folderListBloc.add(FolderListRemovePaths(sources.toSet()));
        _folderListBloc.add(FolderListRefresh(_currentPath));
        AppToast.success(context, context.tr.dndMoved(sources.length));
        return;
      case FileDragDropMoveRejection.sameParent:
        return;
      case FileDragDropMoveRejection.selfDrop:
      case FileDragDropMoveRejection.descendantDrop:
        AppToast.warning(context, context.tr.dndFolderIntoItself);
        return;
      case FileDragDropMoveRejection.nonLocalPath:
        AppToast.warning(context, context.tr.dndLocalOnly);
        return;
      case FileDragDropMoveRejection.destinationMissing:
        AppToast.warning(context, context.tr.dndDestinationMissing);
        return;
      case FileDragDropMoveRejection.empty:
      case FileDragDropMoveRejection.moveFailed:
        AppToast.error(context, context.tr.dndMoveFailed);
        return;
    }
  }

  void _queueFocusAfterDelete(Set<String> deletedPaths, String? nextFocusPath) {
    final focusedPath = _keyboardController.focusedPath;
    if (focusedPath == null || !deletedPaths.contains(focusedPath)) {
      _pendingDeletedFocusPaths = const {};
      _pendingNextFocusPathAfterDelete = null;
      _selectionBloc.add(ClearSelection());
      return;
    }

    _pendingDeletedFocusPaths = deletedPaths;
    _pendingNextFocusPathAfterDelete = nextFocusPath;
  }

  void _maybeApplyFocusAfterDelete(FolderListState state) {
    if (_pendingDeletedFocusPaths.isEmpty) return;

    final currentPaths = <String>{
      ...state.folders.map((entity) => entity.path),
      ...state.files.map((entity) => entity.path),
      ...state.searchResults.map((entity) => entity.path),
      ...state.filteredFiles.map((entity) => entity.path),
    };

    final currentFocusedPath = _keyboardController.focusedPath;
    if (currentFocusedPath != null &&
        currentPaths.contains(currentFocusedPath) &&
        !_pendingDeletedFocusPaths.contains(currentFocusedPath)) {
      _pendingDeletedFocusPaths = const {};
      _pendingNextFocusPathAfterDelete = null;
      return;
    }

    final hasDeletedItemsStillVisible = _pendingDeletedFocusPaths.any(
      (path) => currentPaths.contains(path),
    );
    if (hasDeletedItemsStillVisible) {
      return;
    }

    final nextFocusPath = _pendingNextFocusPathAfterDelete;
    _pendingDeletedFocusPaths = const {};
    _pendingNextFocusPathAfterDelete = null;

    _clearSelection();

    if (nextFocusPath == null || !currentPaths.contains(nextFocusPath)) {
      _keyboardController.clearFocus();
      return;
    }

    _keyboardController.focusedPath = nextFocusPath;
    if (state.folders.any((entity) => entity.path == nextFocusPath)) {
      _toggleFolderSelection(
        nextFocusPath,
        shiftSelect: false,
        ctrlSelect: false,
      );
    } else {
      _toggleFileSelection(
        nextFocusPath,
        shiftSelect: false,
        ctrlSelect: false,
      );
    }
  }

  Future<void> _loadAllowFileExtensionRenamePreference() async {
    final prefs = UserPreferences.instance;
    await prefs.init();
    _onRenameExtensionPreferenceChanged();
  }

  Future<void> _setAllowFileExtensionRename(bool value) async {
    final prefs = UserPreferences.instance;
    await prefs.init();
    await prefs.setAllowFileExtensionRename(value);
  }

  void _onRenameExtensionPreferenceChanged() {
    if (!mounted) return;
    final value = UserPreferences.instance.allowFileExtensionRename.value;
    setState(() {
      _allowFileExtensionRename = value;
    });
    _inlineRenameController.allowFileExtensionRename = value;

    if (Platform.isAndroid || Platform.isIOS) {
      MobileFileActionsController.forTab(
        widget.tabId,
      ).allowFileExtensionRename = value;
    }
  }

  void _handleCreatedFile(String createdPath) {
    if (!mounted ||
        !isDesktopPlatform ||
        _normalizePath(path.dirname(createdPath)) !=
            _normalizePath(_currentPath)) {
      return;
    }

    _createdItemRenameGeneration++;
    _pendingCreatedFilePath = createdPath;
    final state = _folderListBloc.state;
    if (state.currentFilter != null ||
        state.currentSearchQuery != null ||
        state.currentSearchTag != null) {
      _searchController.clear();
      _folderListBloc.add(const ClearSearchAndFilters());
    }
    _folderListBloc.add(FolderListRefresh(_currentPath));
  }

  void _maybeStartPendingCreatedFileRename(FolderListState folderState) {
    final pendingPath = _pendingCreatedFilePath;
    if (!mounted || !isDesktopPlatform || pendingPath == null) {
      return;
    }

    if (folderState.isLoading ||
        folderState.isRefreshing ||
        _normalizePath(folderState.currentPath.path) !=
            _normalizePath(_currentPath)) {
      return;
    }

    final normalizedPendingPath = _normalizePath(pendingPath);
    final items = <FileSystemEntity>[
      ...folderState.folders,
      ...folderState.files,
    ];
    final targetIndex = items.indexWhere(
      (entity) => _normalizePath(entity.path) == normalizedPendingPath,
    );
    if (targetIndex == -1) return;

    final entity = items[targetIndex];
    final generation = _createdItemRenameGeneration;
    _pendingCreatedFilePath = null;
    if (entity is Directory) {
      _toggleFolderSelection(entity.path);
    } else {
      _toggleFileSelection(entity.path);
    }
    _keyboardController.focusedPath = entity.path;

    final crossAxisCount = (_gridCrossAxisCount ?? 1).clamp(1, 999).toInt();
    _keyboardController.ensurePathVisible(
      entity.path,
      index: targetIndex,
      crossAxisCount: crossAxisCount,
      itemMainAxisExtent: _resolvedItemMainAxisExtent(
        folderState,
        crossAxisCount,
      ),
    );
    // Let the refresh and scroll build the item before focusing its editor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _createdItemRenameGeneration ||
            _normalizePath(path.dirname(entity.path)) !=
                _normalizePath(_currentPath)) {
          return;
        }
        _inlineRenameController.startRename(
          entity.path,
          commitOnBlur: true,
          onCancelled: () => _keyboardController.focusNode.requestFocus(),
          onCommitted: () => _keyboardController.focusNode.requestFocus(),
        );
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  // View mode methods are now provided by PreferencesManagerMixin
  void _toggleViewMode() => toggleViewMode();

  void _toggleDrivesViewMode() {
    final currentMode = _folderListBloc.state.viewMode;
    final nextMode = (currentMode == ViewMode.grid)
        ? ViewMode.list
        : ViewMode.grid;
    _setViewMode(nextMode);
  }

  void _setViewMode(ViewMode mode) {
    setViewMode(mode, tabId: widget.tabId);
    // Update mobile controller state
    final controller = MobileFileActionsController.forTab(widget.tabId);
    controller.currentViewMode = mode;
  }

  void _refreshFileList() {
    setState(() {
      _isRefreshing = true;
    });

    // Pull-to-refresh / explicit refresh counts as user interaction.
    if (locator.isRegistered<TabActivityManager>()) {
      locator<TabActivityManager>().onTabInteraction(
        widget.tabId,
        path: _currentPath,
      );
    }

    _refreshController.refreshFileList(
      currentPath: _currentPath,
      isMounted: () => mounted,
      onRefreshComplete: () {
        if (!mounted) return;
        setState(() {
          _isRefreshing = false;
        });
      },
    );
  }

  // Handle mobile inline search
  void _handleMobileSearch(String? query) => _handleMobileSearchImpl(query);

  // Show search tip using SearchFilterManager
  Future<void> _showSearchTip(BuildContext context) async {
    await SearchFilterManager.showSearchTip(context);
    if (mounted) {
      setState(() {
        _showSearchBar = true;
      });
    }
  }

  Future<void> _toggleSearchBar(BuildContext context) async {
    if (_showSearchBar) {
      _closeSearchBar();
      return;
    }

    if (_isDrivesMode()) {
      _openOrFocusSearch();
      return;
    }
    await _showSearchTip(context);
  }

  void _setDriveSearchQuery(String query) {
    if (!mounted || query == _driveSearchQuery) return;
    setState(() => _driveSearchQuery = query);
    MobileFileActionsController.forTab(widget.tabId).currentSearchQuery = query;
  }

  void _closeSearchBar() {
    setState(() {
      _showSearchBar = false;
      if (_isDrivesMode()) _driveSearchQuery = '';
    });
    if (_isDrivesMode()) {
      MobileFileActionsController.forTab(widget.tabId).currentSearchQuery =
          null;
    }
  }

  /// Back on a search that found nothing leaves the search: the query is
  /// cleared, the folder listing comes back and the search bar closes.
  /// Returns whether it consumed the back action.
  bool _exitEmptySearch() {
    final state = _folderListBloc.state;
    if (!state.isSearchActive ||
        state.searchResults.isNotEmpty ||
        _currentPath.startsWith('#search?tag=')) {
      return false;
    }
    _folderListBloc.add(const ClearSearchAndFilters());
    _folderListBloc.add(FolderListLoad(_currentPath));
    // The mobile search dialog keeps its own copy of the query.
    MobileFileActionsController.forTab(widget.tabId).currentSearchQuery = null;
    if (_showSearchBar) _closeSearchBar();
    return true;
  }

  Widget _buildSearchBar() {
    final drives = _isDrivesMode();
    return tab_components.SearchBar(
      focusNode: _searchFocusNode,
      currentPath: _currentPath,
      tabId: widget.tabId,
      folderListBloc: _folderListBloc,
      initialQuery: drives ? _driveSearchQuery : null,
      onQueryChanged: drives ? _setDriveSearchQuery : null,
      onSearch: drives ? _setDriveSearchQuery : null,
      onClearSearch: drives ? () => _setDriveSearchQuery('') : null,
      showTipsButton: !drives,
      showTagSearch: !drives,
      showGlobalSearchToggle: !drives,
      showRegexToggle: !drives,
      hintText: drives ? context.tr.searchStorageLocations : null,
      onCloseSearch: _closeSearchBar,
    );
  }

  void _openOrFocusSearch() {
    if (!_showSearchBar) setState(() => _showSearchBar = true);
    _searchFocusNode.requestFocus();
  }

  void _navigateToPath(String path) {
    // Capture before NavigationController clears the keyboard focus, and flag
    // this as a fresh drill-in (opens at the top) rather than a history move.
    _rememberViewState();
    _viewStateCapturedFor = _normalizePath(_currentPath);
    _freshNavigation = true;
    try {
      _navigationController.navigateToPath(
        context,
        path,
        _pathController,
        (p) => _keyboardController.clearFocus(),
      );
    } finally {
      _freshNavigation = false;
      _viewStateCapturedFor = null;
    }
  }

  Map<String, _FolderViewMemory> get _viewMemory {
    if (!_viewMemoryByTab.containsKey(widget.tabId) &&
        _viewMemoryByTab.length >= _maxViewMemoryTabs) {
      _viewMemoryByTab.remove(_viewMemoryByTab.keys.first);
    }
    return _viewMemoryByTab.putIfAbsent(
      widget.tabId,
      () => <String, _FolderViewMemory>{},
    );
  }

  bool _isRestorableViewPath(String value) =>
      value.isNotEmpty && !value.startsWith('#') && !_isDrivesPathValue(value);

  /// Saves the scroll offset and focused item of the folder being left.
  void _rememberViewState() {
    if (!_isRestorableViewPath(_currentPath)) return;
    final key = _normalizePath(_currentPath);
    final memory = _viewMemory;
    final previous = memory.remove(key);
    final scroll = _keyboardController.scrollController;
    memory[key] = _FolderViewMemory(
      scrollOffset: scroll.hasClients
          ? scroll.offset
          : (previous?.scrollOffset ?? 0.0),
      focusedPath: _keyboardController.focusedPath,
    );
    while (memory.length > _maxViewMemoryFolders) {
      memory.remove(memory.keys.first);
    }
  }

  /// Runs when the visible folder is about to change: stores the old folder's
  /// view and, when returning to a remembered folder (or to the parent of the
  /// one just left), schedules restoring its scroll position and focus.
  void _prepareViewRestore(String newPath) {
    final oldPath = _currentPath;
    final oldKey = _normalizePath(oldPath);
    final newKey = _normalizePath(newPath);
    if (oldKey == newKey) return;

    if (_viewStateCapturedFor != oldKey) _rememberViewState();
    _viewStateCapturedFor = null;
    final fresh = _freshNavigation;
    _freshNavigation = false;

    // Never let the previous folder's focused item leak into the next one.
    _keyboardController.clearFocus();
    _viewRestoreGeneration++;
    _pendingViewRestore = null;

    if (!_isRestorableViewPath(newPath)) return;
    final highlight = _pendingHighlightedFileName;
    if (highlight != null && highlight.isNotEmpty) return;

    final memory = fresh ? null : _viewMemory[newKey];
    var focusTarget = memory?.focusedPath;
    // Going up (or back) to the parent: focus the folder we just came from.
    if (focusTarget == null &&
        _isRestorableViewPath(oldPath) &&
        _normalizePath(path.dirname(oldPath)) == newKey) {
      focusTarget = oldPath;
    }
    if (memory == null && focusTarget == null) return;

    _pendingViewRestore = _PendingViewRestore(
      normalizedPath: newKey,
      scrollOffset: memory?.scrollOffset,
      focusedPath: focusTarget,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeApplyPendingViewRestore(_folderListBloc.state);
    });
  }

  void _maybeApplyPendingViewRestore(FolderListState state) {
    final pending = _pendingViewRestore;
    if (pending == null) return;
    if (state.isLoading || state.isRefreshing) return;
    if (_normalizePath(state.currentPath.path) != pending.normalizedPath) {
      return;
    }
    _pendingViewRestore = null;

    final items = <FileSystemEntity>[
      ...state.folders.whereType<FileSystemEntity>(),
      ...state.files.whereType<FileSystemEntity>(),
    ];
    final focusKey = pending.focusedPath == null
        ? null
        : _normalizePath(pending.focusedPath!);
    final focusIndex = focusKey == null
        ? -1
        : items.indexWhere((e) => _normalizePath(e.path) == focusKey);
    final generation = _viewRestoreGeneration;

    if (focusIndex != -1) {
      // The list shows focus as a selection, so do what a plain click does.
      final target = items[focusIndex];
      if (target is Directory) {
        _toggleFolderSelection(target.path);
      } else {
        _toggleFileSelection(target.path);
      }
    }

    final offset = pending.scrollOffset;
    if (offset != null && offset.isFinite) {
      _restoreScrollOffset(offset, generation, 0);
    } else if (focusIndex != -1) {
      final isGridLayout =
          state.viewMode == ViewMode.grid ||
          state.viewMode == ViewMode.tiles ||
          (state.viewMode == ViewMode.list && isDesktopPlatform);
      final crossAxisCount = isGridLayout
          ? (_gridCrossAxisCount ??
                    (state.viewMode == ViewMode.list ? 1 : state.gridZoomLevel))
                .clamp(1, 999)
                .toInt()
          : 1;
      _keyboardController.ensurePathVisible(
        items[focusIndex].path,
        index: focusIndex,
        crossAxisCount: crossAxisCount,
        itemMainAxisExtent: _resolvedItemMainAxisExtent(state, crossAxisCount),
      );
    }
  }

  /// Jumps to [offset] once the list has laid out enough content; retries for
  /// a few frames because lazy grids settle their extent after the first one.
  void _restoreScrollOffset(double offset, int generation, int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _viewRestoreGeneration) return;
      final scroll = _keyboardController.scrollController;
      final laidOut = scroll.hasClients && scroll.position.hasContentDimensions;
      if ((!laidOut || scroll.position.maxScrollExtent < offset - 0.5) &&
          attempt < 8) {
        Future<void>.delayed(const Duration(milliseconds: 60), () {
          if (mounted && generation == _viewRestoreGeneration) {
            _restoreScrollOffset(offset, generation, attempt + 1);
          }
        });
        return;
      }
      if (!laidOut) return;
      scroll.jumpTo(
        offset
            .clamp(
              scroll.position.minScrollExtent,
              scroll.position.maxScrollExtent,
            )
            .toDouble(),
      );
    });
  }

  void _handlePathSubmit(String path) {
    _navigationController.handlePathSubmit(
      context,
      path,
      _currentPath,
      _pathController,
    );
  }

  Future<bool> _handleBackButton() async {
    if (_exitEmptySearch()) return false;
    return await _navigationController.handleBackButton(
      context,
      _currentPath,
      _pathController,
    );
  }

  Future<void> _handleDelete(bool permanent) async {
    if (!mounted) {
      debugPrint('_handleDelete called but widget not mounted');
      return;
    }

    debugPrint('_handleDelete called - permanent: $permanent');
    debugPrint(
      '  Selected files: ${_selectionBloc.state.selectedFilePaths.length}',
    );
    debugPrint(
      '  Selected folders: ${_selectionBloc.state.selectedFolderPaths.length}',
    );
    debugPrint('  Focused path: ${_keyboardController.focusedPath}');

    await BrowserLikeActionHandlers.handleDelete(
      context: context,
      folderListBloc: _folderListBloc,
      selectionBloc: _selectionBloc,
      focusedPath: _keyboardController.focusedPath,
      permanent: permanent,
      onClearSelection: () => _selectionBloc.add(ClearSelection()),
      onDeleteConfirmed: _queueFocusAfterDelete,
    );
  }

  void _handleSelectAll() {
    debugPrint('Select all triggered');
    BrowserLikeActionHandlers.selectAllVisibleFolderItems(
      selectionBloc: _selectionBloc,
      state: _folderListBloc.state,
      currentFilter: _currentFilter,
      currentSearchTagOverride: _currentSearchTag,
      ensureSelectionMode: () => _toggleSelectionMode(forceValue: true),
    );
  }

  void _maybeScrollToHighlightedFile(FolderListState state) {
    final highlightedFileName = _pendingHighlightedFileName;
    if (highlightedFileName == null || highlightedFileName.isEmpty) {
      return;
    }
    if (!_preferencesLoaded || state.isLoading || state.isRefreshing) {
      return;
    }

    final items = <FileSystemEntity>[
      ...state.folders.whereType<FileSystemEntity>(),
      ...state.files.whereType<FileSystemEntity>(),
    ];
    final targetIndex = items.indexWhere(
      (entity) => path.basename(entity.path) == highlightedFileName,
    );
    if (targetIndex == -1) {
      return;
    }

    final target = items[targetIndex];
    final targetPath = target.path;
    if (_highlightedScrollTargetPath != targetPath) {
      _highlightedScrollTargetPath = targetPath;
      _highlightedScrollAttempts = 0;
      _keyboardController.focusedPath = targetPath;
      if (target is File) {
        _selectionBloc.add(ToggleFileSelection(targetPath));
      } else if (target is Directory) {
        _selectionBloc.add(ToggleFolderSelection(targetPath));
      }
    }

    final isGridLayout =
        state.viewMode == ViewMode.grid ||
        state.viewMode == ViewMode.tiles ||
        (state.viewMode == ViewMode.list && isDesktopPlatform);
    final crossAxisCount = isGridLayout
        ? (_gridCrossAxisCount ??
                  (state.viewMode == ViewMode.list ? 1 : state.gridZoomLevel))
              .clamp(1, 999)
              .toInt()
        : 1;

    _scrollToHighlightedTarget(
      targetPath: targetPath,
      index: targetIndex,
      crossAxisCount: crossAxisCount,
      itemMainAxisExtent: _resolvedItemMainAxisExtent(state, crossAxisCount),
    );
  }

  void _scrollToHighlightedTarget({
    required String targetPath,
    required int index,
    required int crossAxisCount,
    required double itemMainAxisExtent,
  }) {
    if (!mounted || _pendingHighlightedFileName == null) return;

    _keyboardController.ensurePathVisible(
      targetPath,
      index: index,
      crossAxisCount: crossAxisCount,
      itemMainAxisExtent: itemMainAxisExtent,
      forward: true,
    );

    if (_keyboardController.hasRenderedItem(targetPath) ||
        _highlightedScrollAttempts >= 8) {
      _pendingHighlightedFileName = null;
      return;
    }

    _highlightedScrollAttempts += 1;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || _pendingHighlightedFileName == null) return;
      _scrollToHighlightedTarget(
        targetPath: targetPath,
        index: index,
        crossAxisCount: crossAxisCount,
        itemMainAxisExtent: itemMainAxisExtent,
      );
    });
  }

  double _resolvedItemMainAxisExtent(
    FolderListState state,
    int crossAxisCount,
  ) {
    if (state.viewMode == ViewMode.list && isDesktopPlatform) {
      return _gridItemMainAxisExtent ?? 40.0;
    }
    if (state.viewMode != ViewMode.grid) {
      if (state.viewMode == ViewMode.tiles) {
        return 84.0;
      }
      return state.viewMode == ViewMode.details ? 48.0 : 88.0;
    }

    final measuredExtent = _gridItemMainAxisExtent;
    if (measuredExtent != null && measuredExtent > 0) {
      return measuredExtent;
    }

    const gridSpacing = 8.0;
    const gridAspectRatio = 0.8;
    const gridReferenceWidth = 960.0;
    final safeCrossAxisCount = math.max(1, crossAxisCount);
    final totalSpacing = gridSpacing * (safeCrossAxisCount - 1);
    final itemWidth = math.max(
      56.0,
      (gridReferenceWidth - totalSpacing) / safeCrossAxisCount,
    );
    return (itemWidth / gridAspectRatio) + gridSpacing;
  }

  void _handleCopy() {
    BrowserLikeActionHandlers.copySelectionOrFocused(
      context: context,
      selectionState: _selectionBloc.state,
      focusedPath: _keyboardController.focusedPath,
      folderListBloc: _folderListBloc,
    );
  }

  void _handleCut() {
    BrowserLikeActionHandlers.cutSelectionOrFocused(
      context: context,
      selectionState: _selectionBloc.state,
      focusedPath: _keyboardController.focusedPath,
      folderListBloc: _folderListBloc,
    );
  }

  void _handlePaste() {
    BrowserLikeActionHandlers.pasteInto(
      context: context,
      destinationPath: _currentPath,
      folderListBloc: _folderListBloc,
    );
  }

  void _handleRename() {
    unawaited(
      BrowserLikeActionHandlers.renameSelectionOrFocused(
        context: context,
        selectionState: _selectionBloc.state,
        focusedPath: _keyboardController.focusedPath,
        isDesktop: isDesktopPlatform,
        inlineRenameController: _inlineRenameController,
        folderListBloc: _folderListBloc,
        refocusNode: _keyboardController.focusNode,
        onInlineRenameStarted: () => setState(() {}),
      ),
    );
  }

  void _handleCurrentPathChanged(String path) {
    if (!mounted) return;
    _prepareViewRestore(path);
    setState(() {
      if (_isDrivesMode() != _isDrivesPathValue(path)) {
        _driveSearchQuery = '';
        _showSearchBar = false;
        MobileFileActionsController.forTab(widget.tabId).currentSearchQuery =
            null;
      }
      _currentPath = path;
      _pathController.text = _displayPathForInput(path);
    });
    // Apply the folder's settings in this frame when they are in memory;
    // otherwise as soon as they are read.
    final cached = FolderDisplayPreferences.instance.cached(path);
    if (cached != null) {
      applyDisplaySettings(cached);
    } else {
      unawaited(_applyFolderDisplayPreferences(path));
    }
  }

  void _updatePath(String newPath) {
    if (_isHandlingPathUpdate) return;
    _isHandlingPathUpdate = true;
    _pendingCreatedFilePath = null;
    _createdItemRenameGeneration++;
    // Defer the actual update to avoid setState-during-build when this is
    // triggered synchronously from didUpdateWidget (e.g. split-pane path change).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isHandlingPathUpdate = false;
        return;
      }
      _navigationController.updatePath(
        newPath,
        _pathController,
        _currentFilter,
        _currentSearchTag,
      );
      if (Platform.isAndroid || Platform.isIOS) {
        final controller = MobileFileActionsController.forTab(widget.tabId);
        controller.currentPath = newPath;
        controller.actionBarProfile = _isDrivesPathValue(newPath)
            ? MobileActionBarProfile.drivesMinimal
            : MobileActionBarProfile.full;
      }
      _isHandlingPathUpdate = false;
    });
  }

  Future<void> _applyFolderDisplayPreferences(String path) async {
    try {
      final settings = await FolderDisplayPreferences.instance.resolve(path);
      // Preview/properties panes are deliberately left alone here: they
      // follow the tab, not the folder.
      if (!mounted || _currentPath != path) return;
      applyDisplaySettings(settings);
    } catch (e) {
      debugPrint('Error applying folder display preferences: $e');
    }
  }

  // New method to handle lazy loading of drives
  void _startLazyLoadingDrives() {
    LazyLoadingManager.startLazyLoadingDrives(
      folderListBloc: _folderListBloc,
      isMounted: () => mounted,
      onComplete: () {
        if (!mounted) return;
        setState(() {
          _isLazyLoadingDrives = false;
        });
      },
    );
  }

  String _normalizePath(String value) {
    if (value.isEmpty) {
      return '';
    }
    var normalized = path.normalize(value);
    final root = path.rootPrefix(normalized);
    if (normalized.length > root.length &&
        normalized.endsWith(path.separator)) {
      normalized = normalized.substring(
        0,
        normalized.length - path.separator.length,
      );
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  bool _isPathMismatch(FolderListState state) {
    if (_isDrivesMode()) {
      return false;
    }
    return _normalizePath(state.currentPath.path) !=
        _normalizePath(_currentPath);
  }

  @override
  Widget build(BuildContext context) {
    // Always listen for tab path changes so we can switch between system and folder screens
    return BlocProvider.value(
      value: _selectionBloc,
      child: BlocListener<TabManagerBloc, TabManagerState>(
        listener: (context, tabManagerState) {
          final currentTab = tabManagerState.tabs.firstWhere(
            (tab) => tab.id == widget.tabId,
            orElse: () => TabData(id: '', name: '', path: ''),
          );

          if (currentTab.id.isNotEmpty && currentTab.path != _currentPath) {
            debugPrint(
              'Tab path updated from $_currentPath to ${currentTab.path}',
            );
            _updatePath(currentTab.path);
          }

          // If this tab just became the active one, ask the activity manager
          // whether a reload is required (i.e. it was previously inactive and
          // had its caches released). When required, kick a fresh load so the
          // user sees up-to-date content immediately on refocus.
          if (currentTab.id.isNotEmpty &&
              tabManagerState.activeTabId == widget.tabId) {
            _maybeReloadIfRefocused();
          }
          // Path changes reach the fill through the FolderListBloc listener
          // once the new listing is loaded; here only focus changes matter.
          final isActive = tabManagerState.activeTabId == widget.tabId;
          if (isActive != _fillActive) {
            _syncFocusedFolderFill(_folderListBloc.state, isActive: isActive);
          }
        },
        child: _buildContentForCurrentPath(context),
      ),
    );
  }

  List<FileSystemEntity>? _fillFiles;
  String? _fillPath;
  bool _fillActive = false;

  /// Keeps the whole-folder thumbnail fill on the focused tab's folder: while
  /// this tab is the active one, every video in its listing gets a thumbnail
  /// without waiting for the user to scroll to it. Losing focus hands the
  /// fill to whichever tab gains it (or stops it).
  void _syncFocusedFolderFill(FolderListState state, {bool? isActive}) {
    if (!mounted || !isDesktopPlatform) return;
    final active =
        isActive ??
        context.read<TabManagerBloc>().state.activeTabId == widget.tabId;
    if (!active) {
      if (_fillActive) {
        VideoThumbnailHelper.clearFocusedFolderFill(widget.tabId);
        _fillActive = false;
        _fillFiles = null;
        _fillPath = null;
      }
      return;
    }
    // A listing that is still loading keeps the running fill; a virtual one
    // (home, search, tags, network, archives) stops it.
    if (state.isLoading) return;
    final folderPath = state.currentPath.path;
    if (_currentPath.startsWith('#') ||
        folderPath.startsWith('#') ||
        ArchivePathUtils.isArchiveBrowsePath(folderPath)) {
      if (_fillActive) {
        VideoThumbnailHelper.clearFocusedFolderFill(widget.tabId);
        _fillActive = false;
        _fillFiles = null;
        _fillPath = null;
      }
      return;
    }
    if (_fillActive &&
        identical(state.files, _fillFiles) &&
        _fillPath == folderPath) {
      return;
    }
    _fillActive = true;
    _fillFiles = state.files;
    _fillPath = folderPath;
    VideoThumbnailHelper.setFocusedFolderFill(widget.tabId, [
      for (final file in state.files)
        if (file is File && FileTypeUtils.isVideoFile(file.path)) file.path,
    ]);
  }

  /// Triggers a fresh folder load if the tab activity manager flagged this
  /// tab as needing a reload after its caches were aggressively released
  /// during the inactive transition.
  void _maybeReloadIfRefocused() {
    if (!mounted) return;
    if (!locator.isRegistered<TabActivityManager>()) return;
    final activity = locator<TabActivityManager>();
    if (!activity.consumeReloadFlag(widget.tabId)) return;

    // System tabs that are not folder/network views do their own routing and
    // do not need an explicit reload here.
    if (_currentPath.startsWith('#') &&
        !_currentPath.startsWith('#search?tag=') &&
        !_currentPath.startsWith('#network/') &&
        !ArchivePathUtils.isArchiveBrowsePath(_currentPath) &&
        !isDrivesPath(_currentPath)) {
      return;
    }

    AppLogger.perf(
      '[TabActivity] reloading tab=${widget.tabId} after refocus path=$_currentPath',
    );

    // Resume background work suspended during the inactive transition.
    // ThumbnailLoader.resumeTab unblocks visibility-driven enqueues; the
    // FolderListBloc resumes its directory watcher subscription so future
    // filesystem events repopulate the listing.
    ThumbnailLoader.resumeTab(widget.tabId);
    _folderListBloc.resumeDirectoryWatching();

    // Drive the section 12 restore UX: enter "restoring" state immediately
    // so the user sees a skeleton + slim progress bar within the same
    // frame the tab becomes active. The flag is cleared by the
    // BlocListener<FolderListBloc> when loading completes.
    setState(() {
      _isRestoringFromInactive = true;
    });

    if (isDrivesPath(_currentPath)) {
      _folderListBloc.add(const FolderListLoadDrives());
    } else {
      _folderListBloc.add(FolderListRefresh(_currentPath));
    }
  }

  // Build appropriate content depending on current path. This keeps the tab listening
  // active even when showing system screens like #tags.
  Widget _buildContentForCurrentPath(BuildContext context) {
    // Route system paths except the special inline tag-search variant
    if (_currentPath.startsWith('#') &&
        !_currentPath.startsWith('#search?tag=') &&
        !ArchivePathUtils.isArchiveBrowsePath(_currentPath) &&
        !isDrivesPath(_currentPath)) {
      final systemWidget = SystemScreenRouter.routeSystemPath(
        context,
        _currentPath,
        widget.tabId,
      );
      if (systemWidget != null) {
        return systemWidget;
      }
    }

    // Folder/browser UI (default and for #search?tag=...)
    final bool isNetworkPath = _currentPath.startsWith('#network/');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        debugPrint(
          'TabbedFolderListScreen PopScope onPopInvokedWithResult: didPop=$didPop, result=$result',
        );
        if (!didPop) {
          debugPrint('Gesture navigation detected - calling _handleBackButton');
          await _handleBackButton();
        }
      },
      // Wrap with Listener to detect mouse button events
      child: Focus(
        autofocus: isDesktopPlatform,
        focusNode: _keyboardController.focusNode,
        onKeyEvent: (node, event) {
          // Shortcuts belong to the tab in front of the user. Hidden tabs stay
          // mounted in the shell's IndexedStack, so without this guard a stale
          // focus would let Delete / Shift+Delete hit an invisible folder.
          if (!TabFocusGate.isActiveTab(context)) {
            return KeyEventResult.ignored;
          }
          final searchResult = BrowserLikeKeyboardShortcuts.handleSearch(
            isDesktop: isDesktopPlatform,
            event: event,
            onSearch: _openOrFocusSearch,
          );
          if (searchResult != KeyEventResult.ignored) return searchResult;
          if (_isDrivesMode()) {
            return BrowserLikeKeyboardShortcuts.handleBasic(
              isDesktop: isDesktopPlatform,
              event: event,
              onRefresh: _refreshFileList,
              onBack: _handleMouseBackButton,
              onForward: _handleMouseForwardButton,
            );
          }
          // Keys the focused preview pane didn't use (it only claims the
          // video player's) must not drive the list behind it.
          if (_keyboardController.previewFocusNode.hasFocus ||
              _propertiesPaneFocusNode.hasFocus) {
            return KeyEventResult.ignored;
          }
          return BrowserLikeKeyboardShortcuts.handle(
            isDesktop: isDesktopPlatform,
            keyboardController: _keyboardController,
            folderListState: _folderListBloc.state,
            selectionState: _selectionBloc.state,
            currentFilter: _currentFilter,
            gridCrossAxisCount: _gridCrossAxisCount,
            onBackInTabHistory: () {
              if (!mounted || _exitEmptySearch()) return;
              final tabManagerBloc = context.read<TabManagerBloc>();
              if (tabManagerBloc.canTabNavigateBack(widget.tabId)) {
                tabManagerBloc.backNavigationToPath(widget.tabId);
              }
            },
            onForwardInTabHistory: _handleMouseForwardButton,
            onNavigateToParent: () =>
                _navigationController.navigateToParentFolder(
                  context,
                  _currentPath,
                  _pathController,
                  (_) => _keyboardController.clearFocus(),
                ),
            onCreateFolder:
                path.isAbsolute(_currentPath) &&
                    !ArchivePathUtils.isArchiveBrowsePath(_currentPath)
                ? _showCreateFolderDialog
                : null,
            focusFolderPath: (path) => _toggleFolderSelection(
              path,
              shiftSelect: false,
              ctrlSelect: false,
            ),
            focusFilePath: (path) => _toggleFileSelection(
              path,
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
                  final currentPaths = _selectionBloc.state.allSelectedPaths;
                  _keyboardController.showImmediateSelection(<String>{
                    if (ctrlSelect) ...currentPaths,
                    ...folderPaths,
                    ...filePaths,
                  }, currentSelectedPaths: currentPaths);
                  _selectionBloc.add(
                    SelectItemsInRect(
                      folderPaths: folderPaths,
                      filePaths: filePaths,
                      isCtrlPressed: ctrlSelect,
                      isShiftPressed: true,
                      lastSelectedPath: lastSelectedPath,
                    ),
                  );
                },
            activateEntity: (entity) {
              if (entity is Directory) {
                _navigateToPath(entity.path);
              } else if (entity is File) {
                _onFileTap(entity, false);
              }
            },
            onDelete: _handleDelete,
            onSelectAll: _handleSelectAll,
            onCopy: _handleCopy,
            onCut: _handleCut,
            onPaste: _handlePaste,
            onRename: _handleRename,
            onRefresh: _refreshFileList,
            onSearch: _openOrFocusSearch,
            onScrollToIndex: _scrollToIndex,
            event: event,
          );
        },
        child: Listener(
          onPointerDown: (PointerDownEvent event) {
            // The preview pane takes focus itself when clicked.
            if (isDesktopPlatform &&
                !_isDrivesMode() &&
                !_isPointerInside(_propertiesPaneFocusNode.context, event) &&
                !_isPointerInside(
                  _keyboardController.previewFocusNode.context,
                  event,
                )) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (BrowserLikeKeyboardShortcuts.isTextInputFocused()) {
                  if (_isPointerInsideFocusedEditableText(event)) {
                    return;
                  }
                  FocusManager.instance.primaryFocus?.unfocus();
                }
                _keyboardController.focusNode.requestFocus();
              });
            }
            // Mouse button 4 is usually the back button (button value is 8)
            if (event.buttons == 8) {
              _handleMouseBackButton();
            }
            // Mouse button 5 is usually the forward button (button value is 16)
            else if (event.buttons == 16) {
              _handleMouseForwardButton();
            }
          },
          child: BlocProvider<FolderListBloc>.value(
            value: _folderListBloc,
            child: BlocListener<FolderListBloc, FolderListState>(
              listener: (context, folderState) {
                _syncFocusedFolderFill(folderState);
                final error = folderState.error;
                if (error == null) {
                  _lastShownFolderError = null;
                } else if (error != _lastShownFolderError) {
                  _lastShownFolderError = error;
                  DeleteFailureToast.show(
                    context,
                    error,
                    retryPaths: folderState.retryableElevatedDeletePaths,
                    onRetryAsAdministrator: (paths) => _folderListBloc.add(
                      FolderListRetryDeleteAsAdministrator(paths),
                    ),
                  );
                }

                _maybeApplyFocusAfterDelete(folderState);
                _maybeStartPendingCreatedFileRename(folderState);
                _maybeScrollToHighlightedFile(folderState);
                _maybeApplyPendingViewRestore(folderState);

                // Clear the refocus restore flag once the folder list bloc
                // has finished loading. We watch both isLoading and
                // isRefreshing so the flag is dropped as soon as either
                // completion path settles. The check is cheap enough to
                // run on every state change.
                if (_isRestoringFromInactive &&
                    !folderState.isLoading &&
                    !folderState.isRefreshing) {
                  // Defer to next frame so the skeleton cross-fades cleanly
                  // with real content rather than disappearing mid-build.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _isRestoringFromInactive = false;
                    });
                  });
                }

                // Check if there are any video/image files in the current directory
                final hasVideoOrImageFiles = _hasVideoOrImageFiles(folderState);

                // If no video/image files and we have pending thumbnails, reset the count
                if (!hasVideoOrImageFiles && _hasPendingThumbnails) {
                  debugPrint(
                    "TabbedFolderListScreen: No video/image files found, resetting pending thumbnail count",
                  );
                  ThumbnailLoader.resetPendingCount();
                  _hasPendingThumbnails = false;
                }

                // Only show tab loading when there are actual thumbnail tasks
                // Folder loading should not show in tab loading indicator
                final isLoading = _hasPendingThumbnails;

                context.read<TabManagerBloc>().add(
                  UpdateTabLoading(widget.tabId, isLoading),
                );
              },
              child: BlocBuilder<FolderListBloc, FolderListState>(
                builder: (context, state) {
                  // Only update from state if not in a pending tag search state
                  // or if state has caught up
                  if (!_currentPath.startsWith('#search?tag=') ||
                      state.currentSearchTag != null) {
                    _currentSearchTag = state.currentSearchTag;
                  }
                  _currentFilter = state.currentFilter;
                  if (_pendingHighlightedFileName != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _maybeScrollToHighlightedFile(state);
                      }
                    });
                  }

                  return _buildWithSelectionState(
                    context,
                    state,
                    isNetworkPath,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // New helper method that builds the UI with selection state from BLoC
  Widget _buildWithSelectionState(
    BuildContext context,
    FolderListState folderListState,
    bool isNetworkPath,
  ) {
    return BlocBuilder<SelectionBloc, SelectionState>(
      builder: (context, selectionState) {
        // When a parent (e.g. SplitPaneView) owns the bar, push bar data into
        // the notifier instead of rendering our own appbar.
        final notifier = widget.appBarDataNotifier;
        if (notifier != null) {
          // In split mode the SearchBar is rendered in the shared top bar
          // (outside the pane's BlocProvider subtree), so we pass the pane's
          // FolderListBloc directly to avoid a context lookup failure.
          final titleWidget = _showSearchBar
              ? _buildSearchBar()
              : tab_components.PathNavigationBar(
                  tabId: widget.tabId,
                  pathController: _pathController,
                  onPathSubmitted: _handlePathSubmit,
                  currentPath: _displayPathForInput(_currentPath),
                  tabPath: _currentPath,
                  isNetworkPath: isNetworkPath,
                  canNavigateToParent:
                      _navigationController.parentPathForUpButton(
                        _currentPath,
                      ) !=
                      null,
                  onNavigateToParent: () {
                    _navigationController.navigateToParentFolder(
                      context,
                      _currentPath,
                      _pathController,
                      (p) => _keyboardController.clearFocus(),
                    );
                  },
                );
          final newData = SplitPaneAppBarData(
            titleWidget: titleWidget,
            onSearch: _openOrFocusSearch,
            actions: _getAppBarActions(),
            isSelectionMode:
                selectionState.isSelectionMode && !isDesktopPlatform,
          );
          // Schedule notifier update after build to avoid setState-in-build errors.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) notifier.value = newData;
          });
        }

        final summary = SelectionSummaryTooltip.isVisibleFor(selectionState)
            ? SelectionSummaryTooltip.forSelection(
                selectionState,
                allowWrap: !isDesktopPlatform,
              )
            : null;
        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            ScreenScaffold(
              selectionState: selectionState,
              body: _buildBodyWithProperties(
                context,
                folderListState,
                selectionState,
                isNetworkPath,
              ),
              isNetworkPath: isNetworkPath,
              onClearSelection: _clearSelection,
              showRemoveTagsDialog: _showRemoveTagsDialog,
              showManageAllTagsDialog: (context) =>
                  _showManageAllTagsDialog(context),
              showDeleteConfirmationDialog: (context) =>
                  _showDeleteConfirmationDialog(context),
              isDesktop: isDesktopPlatform,
              selectionModeFloatingActionButton: null,
              mobileSelectionSummary: isDesktopPlatform ? null : summary,
              // When notifier is provided, suppress own appbar – parent renders it.
              showAppBar: notifier != null ? false : widget.showAppBar,
              // In split mode, search bar is shown in shared bar above; suppress it here.
              showSearchBar: notifier != null ? false : _showSearchBar,
              searchBar: _buildSearchBar(),
              pathNavigationBar: tab_components.PathNavigationBar(
                tabId: widget.tabId,
                pathController: _pathController,
                onPathSubmitted: _handlePathSubmit,
                currentPath: _displayPathForInput(_currentPath),
                tabPath: _currentPath,
                isNetworkPath: isNetworkPath, // Pass network flag
                canNavigateToParent:
                    _navigationController.parentPathForUpButton(_currentPath) !=
                    null,
                onNavigateToParent: () {
                  _navigationController.navigateToParentFolder(
                    context,
                    _currentPath,
                    _pathController,
                    (p) => _keyboardController.clearFocus(),
                  );
                },
              ),
              actions: _getAppBarActions(),
            ),
            if (isDesktopPlatform && summary != null)
              Positioned(bottom: 0, left: 0, right: 0, child: summary),
          ],
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    FolderListState state,
    SelectionState selectionState,
    bool isNetworkPath,
  ) {
    // Apply frame timing optimization before heavy UI operations
    FrameTimingOptimizer().optimizeBeforeHeavyOperation();

    if (isDesktopPlatform) {
      _keyboardController.syncFromSelection(selectionState);
    }

    if (_isDrivesMode()) {
      return Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _buildAcrylicContentContainer(
                  context: context,
                  child: tab_components.DriveView(
                    tabId: widget.tabId,
                    folderListBloc: _folderListBloc,
                    onPathChanged: _handleCurrentPathChanged,
                    onBackButtonPressed: _handleMouseBackButton,
                    onForwardButtonPressed: _handleMouseForwardButton,
                    isLazyLoading: _isLazyLoadingDrives,
                    viewMode: state.viewMode,
                    gridZoomLevel: state.gridZoomLevel,
                    onZoomChanged: handleViewScaleChange,
                    isRefreshing: _isRefreshing,
                    searchQuery: _driveSearchQuery,
                    sortOption: state.sortOption,
                    showProperties: _drivePropertiesVisible,
                    visibleColumns: _driveColumns,
                    onSort: (option) => _folderListBloc.add(
                      SetSortOption(option, folderPath: _currentPath),
                    ),
                    onClearSearch: () => _setDriveSearchQuery(''),
                  ),
                ),
              ),
            ],
          ),
          // Refresh indicator at the bottom for drives mode
          if (_isRefreshing)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SlimProgressBar(),
            ),
        ],
      );
    }

    // Show content as soon as we have any files/folders (lazy loading).
    // A path mismatch means that content belongs to the previous navigation,
    // so it must never suppress the loading surface for the requested path.
    final bool hasContent = state.folders.isNotEmpty || state.files.isNotEmpty;
    final bool isPathMismatch =
        !_currentPath.startsWith('#') && _isPathMismatch(state);
    // When search results are displayed, SearchResults widget owns the search
    // loading surface; suppress the top-level one to avoid duplicate loaders.
    final bool searchResultsActive =
        state.searchResults.isNotEmpty ||
        state.currentSearchQuery != null ||
        state.currentSearchTag != null;
    // Status bar: only for initial loads and path mismatches.
    // Refresh operations use `state.isRefreshing` and show at the bottom instead.
    final bool showStatusLoadingIndicator =
        !searchResultsActive &&
        !state.isRefreshing &&
        (state.isLoading || isPathMismatch);
    final bool shouldShowSkeleton =
        !searchResultsActive &&
        state.error == null &&
        ((_isRestoringFromInactive && !hasContent) ||
            isPathMismatch ||
            (!hasContent && state.isLoading));

    return Stack(
      children: [
        Column(
          children: [
            if (_isRestoringFromInactive) _buildRestoringTabHint(context),
            Expanded(
              child: _buildAcrylicContentContainer(
                context: context,
                child: shouldShowSkeleton
                    ? _buildSkeletonLoader(state) // Show skeleton while loading
                    : _buildMainContent(
                        context,
                        state,
                        selectionState,
                        isNetworkPath,
                      ),
              ),
            ),
          ],
        ),
        // Bottom status bar indicator — shown during initial loading AND refresh
        // so the existing file list layout is never affected.
        if (showStatusLoadingIndicator ||
            state.isRefreshing ||
            _isRefreshing ||
            _isRestoringFromInactive)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlimProgressBar(),
          ),
      ],
    );
  }

  /// Subtle inline status hint that appears at the top of the tab content
  /// while a refocus-from-inactive reload is in flight (section 12). The
  /// hint sits above the file list so the breadcrumb / appbar are still
  /// readable, and disappears as soon as the reload completes.
  Widget _buildRestoringTabHint(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: CbLoadingText(
        text: context.tr.restoringTab,
        style: theme.textTheme.bodySmall,
        baseColor: color,
      ),
    );
  }

  /// Build skeleton loader while initial content loads
  /// Uses unified skeleton system with automatic mobile/desktop adaptation
  Widget _buildSkeletonLoader(FolderListState state) {
    return SkeletonHelper.files(
      viewMode: state.viewMode,
      gridZoomLevel: state.gridZoomLevel,
      layoutKnown: !FolderDisplayPreferences.instance.needsListingForViewMode(
        _currentPath,
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    FolderListState state,
    SelectionState selectionState,
    bool isNetworkPath,
  ) {
    final searchDisplayState =
        BrowserLikeDisplayState.resolveSearchOrFilterDisplayState(
          state: state,
          currentFilter: _currentFilter,
          currentSearchTagOverride: _currentSearchTag,
        );
    if (searchDisplayState != null &&
        (searchDisplayState.folders.isNotEmpty ||
            searchDisplayState.files.isNotEmpty)) {
      return _buildFolderAndFileListContent(
        context,
        searchDisplayState,
        selectionState,
        isNetworkPath,
      );
    }

    // Use FolderContentBuilder for error handling and content routing
    final content = FolderContentBuilder.build(
      context,
      folderListState: state,
      selectionState: selectionState,
      currentPath: _currentPath,
      isNetworkPath: isNetworkPath,
      isDesktopPlatform: isDesktopPlatform,
      onRetry: () {
        _folderListBloc.add(FolderListLoad(_currentPath));
      },
      onOpenAsAdministrator:
          state.directoryAccessDenied &&
              state.currentPath.path == _currentPath &&
              !isNetworkPath &&
              Platform.isWindows &&
              !WindowsFolderElevation.isElevated
          ? () async {
              final path = state.currentPath.path;
              try {
                await WindowsFolderElevation.open(path);
              } catch (error) {
                if (context.mounted) {
                  AppToast.error(
                    context,
                    '${context.tr.folderOpenFailed}\n$path\n$error',
                  );
                }
              }
            }
          : null,
      onNavigateToPath: _navigateToPath,
      tabId: widget.tabId,
      showFileTags: showFileTags,
      currentFilter: _currentFilter,
      currentSearchTag: _currentSearchTag,
      onFileTap: _onFileTap,
      toggleFileSelection: _toggleFileSelection,
      toggleFolderSelection: _toggleFolderSelection,
      toggleSelectionMode: _toggleSelectionMode,
      showDeleteTagDialog: _showDeleteTagDialog,
      showAddTagToFileDialog: _showAddTagToFileDialog,
      onClearSearch: () {
        _folderListBloc.add(const ClearSearchAndFilters());
        _folderListBloc.add(FolderListLoad(_currentPath));
      },
      isGlobalSearch: isGlobalSearch,
      onBackButtonPressed: _handleMouseBackButton,
      onForwardButtonPressed: _handleMouseForwardButton,
      onZoomLevelChanged: handleZoomLevelChange,
    );

    // If content builder returns a widget (error, empty, or search results), show it
    if (content is! SizedBox) {
      // For error views, show as-is (context menu is not useful on an error screen).
      if (state.error != null) return content;
      // For empty folders and search/filter results the file-list GestureDetector
      // is not rendered, so right-clicking the background would do nothing.
      // Wrap with the same background right-click handler so "Paste Here",
      // "New Folder", etc. remain accessible even in an empty directory.
      return GestureDetector(
        key: const ValueKey<String>('file-browser-background-context-target'),
        onSecondaryTapUp: (details) =>
            _showContextMenu(context, details.globalPosition),
        behavior: HitTestBehavior.translucent,
        child: content,
      );
    }

    // Otherwise, show the normal file list with progressive loading
    return _buildFolderAndFileListContent(
      context,
      state,
      selectionState,
      isNetworkPath,
    );
  }

  Widget _buildFolderAndFileListContent(
    BuildContext context,
    FolderListState state,
    SelectionState selectionState,
    bool isNetworkPath,
  ) {
    // Use RefreshableFileListView for pull-to-refresh functionality
    return RefreshableFileListView(
      folderListState: state,
      currentPath: _currentPath,
      tabId: widget.tabId,
      folderListBloc: _folderListBloc,
      tabManagerBloc: context.read<TabManagerBloc>(),
      isMounted: () => mounted,
      onRefreshStateChanged: (isRefreshing) {
        setState(() {
          _isRefreshing = isRefreshing;
        });
      },
      child: _buildFolderAndFileList(state),
    );
  }

  Widget _buildFolderAndFileList(FolderListState state) {
    return BlocBuilder<SelectionBloc, SelectionState>(
      builder: (context, selectionState) {
        // Wrap with InlineRenameScope to provide rename controller to child items
        return ListenableBuilder(
          listenable: _inlineRenameController,
          builder: (context, _) {
            return InlineRenameScope(
              controller: _inlineRenameController,
              // Ctrl+scroll walks the full view spectrum (tree↔column↔
              // detail↔list↔tiles↔grid) in every mode. CtrlScrollZoom emits +1 on
              // scroll-down; spectrum convention is +1 = more spacious
              // (scroll-up), so invert the raw sign here.
              child: CtrlScrollZoom(
                onDelta: (raw) => handleViewScaleChange(-raw),
                child: FileListViewBuilder.build(
                  state: state,
                  selectionState: selectionState,
                  isDesktopPlatform: isDesktopPlatform,
                  onNavigateToPath: _navigateToPath,
                  onFileTap: _onFileTap,
                  toggleFileSelection: _toggleFileSelection,
                  toggleFolderSelection: _toggleFolderSelection,
                  clearSelection: _clearSelection,
                  dragSelectionController: _dragSelectionController,
                  showFileTags: showFileTags,
                  showDeleteTagDialog: _showDeleteTagDialog,
                  showAddTagToFileDialog: _showAddTagToFileDialog,
                  toggleSelectionMode: _toggleSelectionMode,
                  columnVisibility: columnVisibility,
                  onColumnVisibilityChanged: saveColumnVisibility,
                  onSortOptionSelected: _setSortOption,
                  showContextMenu: _showContextMenu,
                  isPreviewPaneVisible: false,
                  previewPaneWidthListenable: _previewPaneWidthNotifier,
                  onZoomLevelChanged: handleZoomLevelChange,
                  onPreviewPaneWidthChanged: _updatePreviewPaneWidth,
                  onPreviewPaneWidthCommitted: _commitPreviewPaneWidth,
                  onPreviewPaneToggled: _togglePreviewPane,
                  listFocusNode: _keyboardController.focusNode,
                  previewFocusNode: _keyboardController.previewFocusNode,
                  scrollController: _keyboardController.scrollController,
                  itemKeyForPath: _keyboardController.itemKeyForPath,
                  immediateSelectionForPath:
                      _keyboardController.immediateSelectionForPath,
                  tabId: widget.tabId,
                  isMasonryLayout: _isMasonryLayout,
                  onGridCrossAxisCountChanged: (c) {
                    // Read by keyboard navigation and scroll-to-item handlers,
                    // not by the visible UI. Rebuilding the whole tab here
                    // recreated every thumbnail when a resize changed columns.
                    _gridCrossAxisCount = c;
                  },
                  onGridItemMainAxisExtentChanged: (extent) {
                    if (extent == null || extent <= 0) {
                      return;
                    }
                    _gridItemMainAxisExtent = extent;
                    _keyboardController.itemMainAxisExtent = extent;
                    if (_pendingHighlightedFileName != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _maybeScrollToHighlightedFile(_folderListBloc.state);
                        }
                      });
                    }
                  },
                  onStartFileDrag: _startFileDrag,
                  onMoveItemsToFolder: _moveDroppedItemsToFolder,
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _setSortOption(SortOption option) {
    _folderListBloc.add(SetSortOption(option, folderPath: _currentPath));
  }

  // Helper methods for dialog calls - now using DialogManager
  void _showAddTagToFileDialog(BuildContext context, String filePath) {
    AppLogger.info(
      '[ManageTags][TabbedFolder] _showAddTagToFileDialog',
      error: 'filePath=$filePath',
    );
    DialogManager.showAddTagToFile(context, filePath);
  }

  void _showDeleteTagDialog(
    BuildContext context,
    String filePath,
    List<String> tags,
  ) {
    DialogManager.showDeleteTag(context, filePath, tags);
  }

  void _showRemoveTagsDialog(BuildContext context) {
    final selectionState = context.read<SelectionBloc>().state;
    DialogManager.showRemoveTags(
      context,
      selectionState.selectedFilePaths.toList(),
    );
  }

  void _showManageAllTagsDialog(BuildContext context) {
    final selectionState = context.read<SelectionBloc>().state;
    DialogManager.showManageAllTags(
      context,
      _folderListBloc.state.allTags.toList(),
      _currentPath,
      selectedFiles:
          selectionState.isSelectionMode &&
              selectionState.selectedFilePaths.isNotEmpty
          ? selectionState.selectedFilePaths.toList()
          : null,
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context) {
    final selectionState = context.read<SelectionBloc>().state;
    DialogManager.showDeleteConfirmation(
      context,
      selectedFilePaths: selectionState.selectedFilePaths.toList(),
      selectedFolderPaths: selectionState.selectedFolderPaths.toList(),
      folderListBloc: _folderListBloc,
      currentPath: _currentPath,
      onClearSelection: _clearSelection,
    );
  }

  // Grid zoom change is now handled by mixin

  // Tag search dialog and handling

  // Xử lý khi người dùng click vào một file trong kết quả tìm kiếm
  void _onFileTap(File file, bool isVideo) {
    FileOperationsHandler.onFileTap(
      context: context,
      file: file,
      folderListBloc: _folderListBloc,
      selectionBloc: _selectionBloc,
      currentFilter: _currentFilter,
      currentSearchTag: _currentSearchTag,
      onNavigateToPath: (path) => _navigationController.navigateToPath(
        context,
        path,
        _pathController,
        (_) => _keyboardController.clearFocus(),
      ),
    );
  }

  // Method to handle mouse back button press
  void _handleMouseBackButton() {
    if (_exitEmptySearch()) return;
    _navigationController.handleMouseBackButton(
      context,
      _currentPath,
      _pathController,
    );
  }

  // Show context menu for the folder
  void _showContextMenu(BuildContext context, Offset position) {
    FolderBackgroundContextMenu.show(
      context: context,
      globalPosition: position,
      folderListBloc: _folderListBloc,
      currentPath: _currentPath,
      currentViewMode: _folderListBloc.state.viewMode,
      currentSortOption: _folderListBloc.state.sortOption,
      onViewModeChanged: _setViewMode,
      onRefresh: _refreshFileList,
      onCreateFolder: (String folderName) {
        // This callback is now handled inside FolderBackgroundContextMenu
      },
      inlineRenameController: _inlineRenameController,
      onAfterFileCreated: _handleCreatedFile,
    );
  }

  // Method to handle mouse forward button press
  void _handleMouseForwardButton() {
    _navigationController.handleMouseForwardButton(
      context,
      _currentPath,
      _pathController,
    );
  }

  List<Widget> _getAppBarActions() {
    if (_isDrivesMode()) {
      final state = _folderListBloc.state;
      final actions = SharedActionBar.buildCommonActions(
        context: context,
        onSearchPressed: () => _toggleSearchBar(context),
        isSearchActive: _showSearchBar,
        onSortOptionSelected: (option) => _folderListBloc.add(
          SetSortOption(option, folderPath: _currentPath),
        ),
        currentSortOption: DriveBrowserEntries.effectiveSort(state.sortOption),
        allowedSortOptions: DriveBrowserEntries.sortOptions,
        viewMode: state.viewMode,
        showDesktopViewModes: isDesktopPlatform,
        onViewModeToggled: _toggleDrivesViewMode,
        onViewModeSelected: _setViewMode,
        onRefresh: _refreshFileList,
        currentGridZoomLevel: state.gridZoomLevel,
        onGridZoomChanged: handleGridZoomChange,
        onSelectionModeToggled: () {},
        showMoreOptions: false,
      );
      if (isDesktopPlatform) {
        actions.insert(
          1,
          IconButton(
            key: const ValueKey('drive-properties-toggle'),
            tooltip: _drivePropertiesVisible
                ? context.tr.hidePropertiesPane
                : context.tr.showPropertiesPane,
            isSelected: _drivePropertiesVisible,
            icon: const Icon(PhosphorIconsLight.sidebar),
            onPressed: () => setState(
              () => _drivePropertiesVisible = !_drivePropertiesVisible,
            ),
          ),
        );
      }
      if (state.viewMode == ViewMode.details) {
        actions.insert(
          2,
          PopupMenuButton<tab_components.DriveDetailsColumn>(
            popUpAnimationStyle: CbPopoverTransition.menuStyleOf(context),
            key: const ValueKey('drive-columns-menu'),
            tooltip: context.tr.columnSettingsTooltip,
            icon: const Icon(PhosphorIconsLight.layout),
            itemBuilder: (context) => [
              for (final column in tab_components.DriveDetailsColumn.values)
                if (column != tab_components.DriveDetailsColumn.name)
                  CheckedPopupMenuItem(
                    value: column,
                    checked: _driveColumns.contains(column),
                    child: Text(
                      tab_components.driveColumnLabel(context, column),
                    ),
                  ),
            ],
            onSelected: (column) => setState(() {
              if (!_driveColumns.remove(column)) _driveColumns.add(column);
            }),
          ),
        );
      }
      return actions;
    }

    // Use AppBarActionsBuilder to build actions based on selection state
    final selectionState = _selectionBloc.state;
    final folderListState = _folderListBloc.state;

    final actions = AppBarActionsBuilder.buildActions(
      context: context,
      selectionState: selectionState,
      folderListState: folderListState,
      currentPath: _currentPath,
      isNetworkPath: _currentPath.startsWith('#network/'),
      onSortOptionSelected: _setSortOption,
      onViewModeToggled: _toggleViewMode,
      onViewModeSelected: _setViewMode,
      onRefresh: _refreshFileList,
      onSearchPressed: () => _toggleSearchBar(context),
      isSearchActive: _showSearchBar,
      onSelectionModeToggled: _toggleSelectionMode,
      onManageTagsPressed: () {
        tab_components.showManageTagsDialog(
          context,
          folderListState.allTags.toList(),
          folderListState.currentPath.path,
        );
      },
      allowFileExtensionRename: _allowFileExtensionRename,
      onAllowFileExtensionRenameChanged: _setAllowFileExtensionRename,
      onGridZoomChange: handleGridZoomChange,
      onColumnSettingsPressed: () {
        showColumnVisibilityDialog(context);
      },
      onGalleryResult: null,
      onPreviewPaneToggled: isDesktopPlatform ? _togglePreviewPane : null,
      isPreviewPaneVisible: isPreviewPaneVisible,
      showDesktopViewModes: isDesktopPlatform,
    );
    if (isDesktopPlatform) {
      final l10n = AppLocalizations.of(context)!;
      // Keep the search button on the left of the properties (tag) toggle.
      final searchIndex = actions.indexWhere(
        (w) => w.key == const ValueKey('shared-search-action'),
      );
      actions.insert(
        searchIndex + 1,
        IconButton(
          key: const ValueKey('toggle-properties-pane'),
          tooltip: _propertiesPaneVisible
              ? l10n.hidePropertiesPane
              : l10n.showPropertiesPane,
          isSelected: _propertiesPaneVisible,
          icon: Icon(
            _propertiesPaneVisible
                ? PhosphorIconsFill.tag
                : PhosphorIconsLight.tag,
            size: 20,
          ),
          onPressed: _togglePropertiesPane,
        ),
      );
    }
    return actions;
  }
}

/// A slim, non-intrusive status bar shown at the bottom of the screen
/// while a directory refresh is in progress.
///
/// It overlays the file list via a [Positioned] widget inside a [Stack],
/// so the existing file list layout is never affected.
