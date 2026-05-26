import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_action_handlers.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_display_state.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_keyboard_shortcuts.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/tab_manager/shared/screen_menu_registry.dart';
import 'package:cb_file_manager/ui/components/common/skeleton_helper.dart';
import '../tab_manager.dart';
import '../tab_paths.dart';
import 'package:cb_file_manager/ui/utils/fluent_background.dart';
import 'package:path/path.dart' as path;

// Import folder list components with explicit alias
import '../../../screens/folder_list/folder_list_bloc.dart';
import '../../../screens/folder_list/folder_list_event.dart';
import '../../../screens/folder_list/folder_list_state.dart';

// Import selection bloc
import 'package:cb_file_manager/bloc/selection/selection.dart';

// Import our new components with a clear namespace
import '../../components/index.dart' as tab_components;
import '../tab_data.dart';
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
import 'package:cb_file_manager/ui/controllers/dialog_manager.dart';
import 'package:cb_file_manager/ui/widgets/folder_content_builder.dart';
import 'package:cb_file_manager/ui/widgets/refreshable_file_list_view.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/ui/widgets/slim_progress_bar.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/tab_activity/tab_activity_manager.dart';

part 'tabbed_folder_list_screen.mobile_actions.dart';
part 'tabbed_folder_list_screen.refresh.dart';

/// Data class carrying the widgets needed to render the shared appbar in split-pane mode.
class SplitPaneAppBarData {
  final Widget titleWidget;
  final List<Widget> actions;
  final bool isSelectionMode;
  final Widget? selectionAppBar;

  const SplitPaneAppBarData({
    required this.titleWidget,
    required this.actions,
    this.isSelectionMode = false,
    this.selectionAppBar,
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
    Key? key,
    required this.path,
    required this.tabId,
    this.showAppBar = true, // Mặc định là hiển thị AppBar
    this.searchTag, // Optional tag to search for
    this.globalTagSearch = false, // Default to local search
    this.highlightedFileName,
    this.appBarDataNotifier,
  }) : super(key: key);

  @override
  State<TabbedFolderListScreen> createState() => _TabbedFolderListScreenState();
}

class _TabbedFolderListScreenState extends State<TabbedFolderListScreen>
    with PreferencesManagerMixin {
  late TextEditingController _searchController;
  late TextEditingController _tagController;
  late TextEditingController _pathController;
  String? _currentFilter;
  String? _currentSearchTag;

  // Add flag for lazy loading drives
  bool _isLazyLoadingDrives = false;
  String? _pendingHighlightedFileName;
  String? _highlightedScrollTargetPath;
  int _highlightedScrollAttempts = 0;
  bool _preferencesLoaded = false;
  double? _gridItemMainAxisExtent;

  // Replace ValueNotifier with SelectionBloc
  late SelectionBloc _selectionBloc;

  // Trạng thái hiển thị thanh tìm kiếm
  bool _showSearchBar = false;

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
  Set<String> _pendingDeletedFocusPaths = const {};
  String? _pendingNextFocusPathAfterDelete;
  bool _allowFileExtensionRename = false;
  bool _isMasonryLayout = false;

  /// Actual grid crossAxisCount from the file list (for arrow up/down in grid).
  int? _gridCrossAxisCount;

  // Flag to track if there are background thumbnail tasks
  bool _hasPendingThumbnails = false;
  StreamSubscription<int>? _pendingTasksSubscription;

  // Add a method to check if there are any video/image files in the current state
  bool _hasVideoOrImageFiles(FolderListState state) {
    return state.files.any((file) => FileTypeUtils.isMediaFile(file.path));
  }

  bool _isTextInputFocused() {
    final focused = FocusManager.instance.primaryFocus;
    final focusedContext = focused?.context;
    if (focusedContext == null) return false;
    if (focusedContext.widget is EditableText) return true;
    return focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _isPointerInsideFocusedEditableText(PointerDownEvent event) {
    final focused = FocusManager.instance.primaryFocus;
    final focusedContext = focused?.context;
    if (focusedContext == null) return false;

    RenderObject? renderObject = focusedContext.findRenderObject();
    if (renderObject is! RenderBox) return false;

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
      int index, int crossAxisCount, double itemMainAxisExtent) {
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
        final double target = (itemEnd - pos.viewportDimension)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
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
    return _isDrivesPathValue(path) ? '' : path;
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
    _inlineRenameController = InlineRenameController();
    FileBrowserHelper.setInlineRenameController(_inlineRenameController);
    FileBrowserHelper.setAfterFileCreatedCallback(_handleCreatedFile);

    // If this is a new tab with empty path (drive view), enable lazy loading
    if (_isDrivesPathValue(_currentPath)) {
      _isLazyLoadingDrives = true;
      // Schedule drive loading after UI is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startLazyLoadingDrives();
      });
    }

    // Listen for thumbnail loading changes
    _pendingTasksSubscription =
        ThumbnailLoader.onPendingTasksChanged.listen((count) {
      final hasBackgroundTasks = count > 0;
      if (_hasPendingThumbnails != hasBackgroundTasks) {
        setState(() {
          _hasPendingThumbnails = hasBackgroundTasks;
        });
      }
    });

    // Initialize the blocs
    _folderListBloc = FolderListBloc();

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
    _dragSelectionController = TabbedFolderDragSelectionController(
      folderListBloc: _folderListBloc,
      selectionBloc: _selectionBloc,
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
      onPathChanged: (String path) {
        setState(() {
          _currentPath = path;
          _pathController.text = _displayPathForInput(path);
        });
      },
      onSaveLastAccessedFolder: _saveLastAccessedFolder,
    );

    // Initialize SelectionCoordinator
    _selectionCoordinator = SelectionCoordinator(
      selectionBloc: _selectionBloc,
      folderListBloc: _folderListBloc,
      clearKeyboardFocus: () => _keyboardController.clearFocus(),
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
    // Clean up resources
    _searchController.dispose();
    _tagController.dispose();
    _pathController.dispose();
    _folderListBloc.close();
    _selectionBloc.close();

    _dragSelectionController.dispose();
    _keyboardController.dispose();
    _previewPaneWidthNotifier.dispose();
    _inlineRenameController.dispose();
    FileBrowserHelper.setInlineRenameController(null);
    FileBrowserHelper.setAfterFileCreatedCallback(null);
    _pendingTasksSubscription?.cancel();

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

  void _toggleFileSelection(String filePath,
      {bool shiftSelect = false, bool ctrlSelect = false}) {
    _selectionCoordinator.toggleFileSelection(
      filePath,
      shiftSelect: shiftSelect,
      ctrlSelect: ctrlSelect,
    );
  }

  void _toggleFolderSelection(String folderPath,
      {bool shiftSelect = false, bool ctrlSelect = false}) {
    _selectionCoordinator.toggleFolderSelection(
      folderPath,
      shiftSelect: shiftSelect,
      ctrlSelect: ctrlSelect,
    );
  }

  void _clearSelection() {
    _selectionCoordinator.clearSelection();
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

    final hasDeletedItemsStillVisible =
        _pendingDeletedFocusPaths.any((path) => currentPaths.contains(path));
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
      _toggleFolderSelection(nextFocusPath,
          shiftSelect: false, ctrlSelect: false);
    } else {
      _toggleFileSelection(nextFocusPath,
          shiftSelect: false, ctrlSelect: false);
    }
  }

  Future<void> _loadAllowFileExtensionRenamePreference() async {
    final prefs = UserPreferences.instance;
    await prefs.init();
    final allowFileExtensionRename = await prefs.getAllowFileExtensionRename();
    if (!mounted) {
      return;
    }

    setState(() {
      _allowFileExtensionRename = allowFileExtensionRename;
    });
    _inlineRenameController.allowFileExtensionRename = allowFileExtensionRename;
  }

  Future<void> _setAllowFileExtensionRename(bool value) async {
    final prefs = UserPreferences.instance;
    await prefs.init();
    await prefs.setAllowFileExtensionRename(value);
    if (!mounted) {
      return;
    }

    setState(() {
      _allowFileExtensionRename = value;
    });
    _inlineRenameController.allowFileExtensionRename = value;

    final controller = MobileFileActionsController.forTab(widget.tabId);
    controller.allowFileExtensionRename = value;
  }

  void _handleCreatedFile(String createdPath) {
    if (!mounted || !isDesktopPlatform) {
      return;
    }

    _pendingCreatedFilePath = createdPath;
    _maybeStartPendingCreatedFileRename(_folderListBloc.state);
  }

  void _maybeStartPendingCreatedFileRename(FolderListState folderState) {
    final pendingPath = _pendingCreatedFilePath;
    if (!mounted || !isDesktopPlatform || pendingPath == null) {
      return;
    }

    if (folderState.isLoading ||
        _normalizePath(folderState.currentPath.path) !=
            _normalizePath(_currentPath)) {
      return;
    }

    final normalizedPendingPath = _normalizePath(pendingPath);
    final matchedFilePath = folderState.files
        .map((entity) => entity.path)
        .cast<String?>()
        .firstWhere(
          (entityPath) =>
              entityPath != null &&
              _normalizePath(entityPath) == normalizedPendingPath,
          orElse: () => null,
        );
    if (matchedFilePath == null) {
      return;
    }

    _pendingCreatedFilePath = null;
    _toggleFileSelection(matchedFilePath);
    _keyboardController.focusedPath = matchedFilePath;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _inlineRenameController.startRename(
        matchedFilePath,
        onCancelled: () {
          _keyboardController.focusNode.requestFocus();
        },
        onCommitted: () {
          _keyboardController.focusNode.requestFocus();
        },
      );
    });
  }

  // View mode methods are now provided by PreferencesManagerMixin
  void _toggleViewMode() => toggleViewMode();

  void _toggleDrivesViewMode() {
    final currentMode = _folderListBloc.state.viewMode;
    final nextMode =
        (currentMode == ViewMode.grid || currentMode == ViewMode.gridPreview)
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
      locator<TabActivityManager>()
          .onTabInteraction(widget.tabId, path: _currentPath);
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
      setState(() {
        _showSearchBar = false;
      });
      return;
    }

    await _showSearchTip(context);
  }

  void _navigateToPath(String path) {
    _navigationController.navigateToPath(
      context,
      path,
      _pathController,
      (p) => _keyboardController.clearFocus(),
    );
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
        '  Selected files: ${_selectionBloc.state.selectedFilePaths.length}');
    debugPrint(
        '  Selected folders: ${_selectionBloc.state.selectedFolderPaths.length}');
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
    BrowserLikeActionHandlers.selectAll(
      selectionBloc: _selectionBloc,
      allFilePaths: _folderListBloc.state.files.map((f) => f.path),
      allFolderPaths: _folderListBloc.state.folders.map((f) => f.path),
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

    final isGridLayout = state.viewMode == ViewMode.grid ||
        state.viewMode == ViewMode.gridPreview;
    final crossAxisCount = isGridLayout
        ? (_gridCrossAxisCount ?? state.gridZoomLevel).clamp(1, 999).toInt()
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
    if (state.viewMode != ViewMode.grid &&
        state.viewMode != ViewMode.gridPreview) {
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
        56.0, (gridReferenceWidth - totalSpacing) / safeCrossAxisCount);
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
    unawaited(BrowserLikeActionHandlers.renameSelectionOrFocused(
      context: context,
      selectionState: _selectionBloc.state,
      focusedPath: _keyboardController.focusedPath,
      isDesktop: isDesktopPlatform,
      inlineRenameController: _inlineRenameController,
      folderListBloc: _folderListBloc,
      refocusNode: _keyboardController.focusNode,
      onInlineRenameStarted: () => setState(() {}),
    ));
  }

  void _updatePath(String newPath) {
    if (_isHandlingPathUpdate) return;
    _isHandlingPathUpdate = true;
    _pendingCreatedFilePath = null;
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
      unawaited(_applyFolderDisplayPreferences(newPath));
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
      final prefs = UserPreferences.instance;
      await prefs.init();
      final folderSortManager = FolderSortManager();
      final savedViewMode = await folderSortManager.getFolderViewMode(path) ??
          await prefs.getViewMode();
      final effectiveViewMode =
          !isDesktopPlatform && savedViewMode == ViewMode.gridPreview
              ? ViewMode.grid
              : savedViewMode;
      final savedSortOption =
          await folderSortManager.getFolderSortOption(path) ??
              await prefs.getSortOption();
      final savedGridZoomLevel =
          await folderSortManager.getFolderGridZoomLevel(path) ??
              await prefs.getGridZoomLevel();
      final savedColumnVisibility =
          await folderSortManager.getFolderColumnVisibility(path) ??
              await prefs.getColumnVisibility();
      final savedShowFileTags =
          await folderSortManager.getFolderShowFileTags(path) ??
              await prefs.getShowFileTags();
      final savedPreviewPaneVisible =
          await folderSortManager.getFolderPreviewPaneVisible(path) ??
              await prefs.getPreviewPaneVisible();
      final savedPreviewPaneWidth =
          await folderSortManager.getFolderPreviewPaneWidth(path) ??
              await prefs.getPreviewPaneWidth();
      if (!mounted || _currentPath != path) return;
      final maxZoom = GridZoomConstraints.maxGridSizeForContext(
        context,
        mode: GridSizeMode.referenceWidth,
      );
      final resolvedGridZoom = savedGridZoomLevel
          .clamp(UserPreferences.minGridZoomLevel, maxZoom)
          .toInt();

      setState(() {
        viewMode = effectiveViewMode;
        gridZoomLevel = resolvedGridZoom;
        columnVisibility = savedColumnVisibility;
        showFileTags = savedShowFileTags;
        isPreviewPaneVisible = savedPreviewPaneVisible;
        previewPaneWidth = savedPreviewPaneWidth;
      });
      _previewPaneWidthNotifier.value = savedPreviewPaneWidth;
      _folderListBloc.add(SetViewMode(effectiveViewMode));
      _folderListBloc.add(SetSortOption(
        savedSortOption,
        persist: false,
      ));
      _folderListBloc.add(SetGridZoom(resolvedGridZoom));
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
      normalized =
          normalized.substring(0, normalized.length - path.separator.length);
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
                'Tab path updated from $_currentPath to ${currentTab.path}');
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
        },
        child: _buildContentForCurrentPath(context),
      ),
    );
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
        !isDrivesPath(_currentPath)) {
      return;
    }

    AppLogger.perf(
      '[TabActivity] reloading tab=${widget.tabId} after refocus path=$_currentPath',
    );

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
        !isDrivesPath(_currentPath)) {
      final systemWidget = SystemScreenRouter.routeSystemPath(
          context, _currentPath, widget.tabId);
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
            'TabbedFolderListScreen PopScope onPopInvokedWithResult: didPop=$didPop, result=$result');
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
          return BrowserLikeKeyboardShortcuts.handle(
            isDesktop: isDesktopPlatform,
            keyboardController: _keyboardController,
            folderListState: _folderListBloc.state,
            selectionState: _selectionBloc.state,
            currentFilter: _currentFilter,
            gridCrossAxisCount: _gridCrossAxisCount,
            onBackInTabHistory: () {
              if (!mounted) return;
              final tabManagerBloc = context.read<TabManagerBloc>();
              if (tabManagerBloc.canTabNavigateBack(widget.tabId)) {
                tabManagerBloc.backNavigationToPath(widget.tabId);
              }
            },
            focusFolderPath: (path) => _toggleFolderSelection(path,
                shiftSelect: false, ctrlSelect: false),
            focusFilePath: (path) => _toggleFileSelection(path,
                shiftSelect: false, ctrlSelect: false),
            selectRange: ({
              required Set<String> folderPaths,
              required Set<String> filePaths,
              required String lastSelectedPath,
              required bool ctrlSelect,
            }) {
              _selectionBloc.add(SelectItemsInRect(
                folderPaths: folderPaths,
                filePaths: filePaths,
                isCtrlPressed: ctrlSelect,
                isShiftPressed: true,
                lastSelectedPath: lastSelectedPath,
              ));
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
            onScrollToIndex: _scrollToIndex,
            event: event,
          );
        },
        child: Listener(
          onPointerDown: (PointerDownEvent event) {
            if (isDesktopPlatform) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_isTextInputFocused()) {
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
                _maybeApplyFocusAfterDelete(folderState);
                _maybeStartPendingCreatedFileRename(folderState);
                _maybeScrollToHighlightedFile(folderState);

                // Check if there are any video/image files in the current directory
                final hasVideoOrImageFiles = _hasVideoOrImageFiles(folderState);

                // If no video/image files and we have pending thumbnails, reset the count
                if (!hasVideoOrImageFiles && _hasPendingThumbnails) {
                  debugPrint(
                      "TabbedFolderListScreen: No video/image files found, resetting pending thumbnail count");
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
                      context, state, isNetworkPath);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // New helper method that builds the UI with selection state from BLoC
  Widget _buildWithSelectionState(BuildContext context,
      FolderListState folderListState, bool isNetworkPath) {
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
            ? tab_components.SearchBar(
                currentPath: _currentPath,
                tabId: widget.tabId,
                folderListBloc: _folderListBloc,
                onCloseSearch: () {
                  setState(() {
                    _showSearchBar = false;
                  });
                },
              )
            : tab_components.PathNavigationBar(
                tabId: widget.tabId,
                pathController: _pathController,
                onPathSubmitted: _handlePathSubmit,
                currentPath: _displayPathForInput(_currentPath),
                tabPath: _currentPath,
                isNetworkPath: isNetworkPath,
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
              );
        final newData = SplitPaneAppBarData(
          titleWidget: titleWidget,
          actions: _getAppBarActions(),
          isSelectionMode: selectionState.isSelectionMode && !isDesktopPlatform,
        );
        // Schedule notifier update after build to avoid setState-in-build errors.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) notifier.value = newData;
        });
      }

      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          ScreenScaffold(
            selectionState: selectionState,
            body: _buildBody(
                context, folderListState, selectionState, isNetworkPath),
            isNetworkPath: isNetworkPath,
            onClearSelection: _clearSelection,
            showRemoveTagsDialog: _showRemoveTagsDialog,
            showManageAllTagsDialog: (context) =>
                _showManageAllTagsDialog(context),
            showDeleteConfirmationDialog: (context) =>
                _showDeleteConfirmationDialog(context),
            isDesktop: isDesktopPlatform,
            selectionModeFloatingActionButton: null,
            // When notifier is provided, suppress own appbar – parent renders it.
            showAppBar: notifier != null ? false : widget.showAppBar,
            // In split mode, search bar is shown in shared bar above; suppress it here.
            showSearchBar: notifier != null ? false : _showSearchBar,
            searchBar: tab_components.SearchBar(
              currentPath: _currentPath,
              tabId: widget.tabId,
              onCloseSearch: () {
                setState(() {
                  _showSearchBar = false;
                });
              },
            ),
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
          if (selectionState.isSelectionMode && isDesktopPlatform)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SelectionSummaryTooltip(
                selectedFileCount: selectionState.selectedFilePaths.length,
                selectedFolderCount: selectionState.selectedFolderPaths.length,
                selectedFilePaths: selectionState.selectedFilePaths.toList(),
                selectedFolderPaths:
                    selectionState.selectedFolderPaths.toList(),
              ),
            ),
        ],
      );
    });
  }

  Widget _buildBody(BuildContext context, FolderListState state,
      SelectionState selectionState, bool isNetworkPath) {
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
                    onPathChanged: (String path) {
                      setState(() {
                        _currentPath = path;
                        _pathController.text = _displayPathForInput(path);
                      });
                    },
                    onBackButtonPressed: _handleMouseBackButton,
                    onForwardButtonPressed: _handleMouseForwardButton,
                    isLazyLoading: _isLazyLoadingDrives,
                    viewMode: state.viewMode,
                    gridZoomLevel: state.gridZoomLevel,
                    onZoomChanged: handleZoomLevelChange,
                    isRefreshing: _isRefreshing,
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

    // Show content as soon as we have any files/folders (lazy loading)
    // Only show skeleton when truly empty and loading (initial navigation)
    final bool hasContent = state.folders.isNotEmpty || state.files.isNotEmpty;
    final bool isPathMismatch =
        !_currentPath.startsWith('#') && _isPathMismatch(state);
    // When search results are displayed, SearchResults widget owns the search
    // loading surface; suppress the top-level one to avoid duplicate loaders.
    final bool searchResultsActive = state.searchResults.isNotEmpty ||
        state.currentSearchQuery != null ||
        state.currentSearchTag != null;
    // Status bar: only for initial loads and path mismatches.
    // Refresh operations use `state.isRefreshing` and show at the bottom instead.
    final bool showStatusLoadingIndicator = !searchResultsActive &&
        !state.isRefreshing &&
        (state.isLoading || isPathMismatch);
    final bool shouldShowSkeleton = !hasContent &&
        (state.isLoading || isPathMismatch) &&
        state.error == null &&
        state.searchResults.isEmpty &&
        state.currentSearchTag == null &&
        state.currentSearchQuery == null;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: _buildAcrylicContentContainer(
                context: context,
                child: shouldShowSkeleton
                    ? _buildSkeletonLoader(state) // Show skeleton while loading
                    : _buildMainContent(
                        context, state, selectionState, isNetworkPath),
              ),
            ),
          ],
        ),
        // Bottom status bar indicator — shown during initial loading AND refresh
        // so the existing file list layout is never affected.
        if (showStatusLoadingIndicator || state.isRefreshing || _isRefreshing)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlimProgressBar(),
          ),
      ],
    );
  }

  /// Build skeleton loader while initial content loads
  /// Uses unified skeleton system with automatic mobile/desktop adaptation
  Widget _buildSkeletonLoader(FolderListState state) {
    final isGridView = state.viewMode == ViewMode.grid;
    return SkeletonHelper.responsive(
      isGridView: isGridView,
      isAlbum: false,
      crossAxisCount: state.gridZoomLevel,
      itemCount: 12,
      wrapInCardOnDesktop: true,
    );
  }

  Widget _buildMainContent(BuildContext context, FolderListState state,
      SelectionState selectionState, bool isNetworkPath) {
    final searchDisplayState =
        BrowserLikeDisplayState.resolveSearchOrFilterDisplayState(
      state: state,
      currentFilter: _currentFilter,
      currentSearchTagOverride: _currentSearchTag,
    );
    if (searchDisplayState != null) {
      return _buildFolderAndFileListContent(
          context, searchDisplayState, selectionState, isNetworkPath);
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
        onSecondaryTapUp: (details) =>
            _showContextMenu(context, details.globalPosition),
        behavior: HitTestBehavior.translucent,
        child: content,
      );
    }

    // Otherwise, show the normal file list with progressive loading
    return _buildFolderAndFileListContent(
        context, state, selectionState, isNetworkPath);
  }

  Widget _buildFolderAndFileListContent(
      BuildContext context,
      FolderListState state,
      SelectionState selectionState,
      bool isNetworkPath) {
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
                showContextMenu: _showContextMenu,
                isPreviewPaneVisible: isPreviewPaneVisible,
                previewPaneWidthListenable: _previewPaneWidthNotifier,
                onZoomLevelChanged: handleZoomLevelChange,
                onPreviewPaneWidthChanged: _updatePreviewPaneWidth,
                onPreviewPaneWidthCommitted: _commitPreviewPaneWidth,
                onPreviewPaneToggled: _togglePreviewPane,
                scrollController: _keyboardController.scrollController,
                itemKeyForPath: _keyboardController.itemKeyForPath,
                tabId: widget.tabId,
                isMasonryLayout: _isMasonryLayout,
                onGridCrossAxisCountChanged: (c) {
                  // Defer setState to after build — this callback runs from LayoutBuilder during build.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _gridCrossAxisCount != c) {
                      setState(() => _gridCrossAxisCount = c);
                    }
                  });
                },
                onGridItemMainAxisExtentChanged: (extent) {
                  if (extent == null || extent <= 0) {
                    return;
                  }
                  _gridItemMainAxisExtent = extent;
                  if (_pendingHighlightedFileName != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _maybeScrollToHighlightedFile(_folderListBloc.state);
                      }
                    });
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  // Helper methods for dialog calls - now using DialogManager
  void _showAddTagToFileDialog(BuildContext context, String filePath) {
    AppLogger.info('[ManageTags][TabbedFolder] _showAddTagToFileDialog',
        error: 'filePath=$filePath');
    DialogManager.showAddTagToFile(context, filePath);
  }

  void _showDeleteTagDialog(
      BuildContext context, String filePath, List<String> tags) {
    DialogManager.showDeleteTag(context, filePath, tags);
  }

  void _showRemoveTagsDialog(BuildContext context) {
    final selectionState = context.read<SelectionBloc>().state;
    DialogManager.showRemoveTags(
        context, selectionState.selectedFilePaths.toList());
  }

  void _showManageAllTagsDialog(BuildContext context) {
    final selectionState = context.read<SelectionBloc>().state;
    DialogManager.showManageAllTags(
      context,
      _folderListBloc.state.allTags.toList(),
      _currentPath,
      selectedFiles: selectionState.isSelectionMode &&
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
    );
  }

  // Method to handle mouse back button press
  void _handleMouseBackButton() {
    _navigationController.handleMouseBackButton(
        context, _currentPath, _pathController);
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
      onSortOptionSaved: (option) => saveSortSetting(option, _currentPath),
      inlineRenameController: _inlineRenameController,
      onAfterFileCreated: _handleCreatedFile,
    );
  }

  // Method to handle mouse forward button press
  void _handleMouseForwardButton() {
    _navigationController.handleMouseForwardButton(
        context, _currentPath, _pathController);
  }

  List<Widget> _getAppBarActions() {
    if (_isDrivesMode()) {
      final isGridView = _folderListBloc.state.viewMode == ViewMode.grid ||
          _folderListBloc.state.viewMode == ViewMode.gridPreview;

      return [
        if (isGridView)
          IconButton(
            icon: const Icon(PhosphorIconsLight.squaresFour),
            tooltip: 'Adjust grid size',
            onPressed: () => SharedActionBar.showGridSizeDialog(
              context,
              currentGridSize: _folderListBloc.state.gridZoomLevel,
              onApply: handleGridZoomChange,
              sizeMode: GridSizeMode.referenceWidth,
            ),
          ),
        IconButton(
          icon: const Icon(PhosphorIconsLight.eye),
          tooltip: 'Toggle view',
          onPressed: _toggleDrivesViewMode,
        ),
        IconButton(
          icon: const Icon(PhosphorIconsLight.arrowsClockwise),
          tooltip: 'Refresh',
          onPressed: _refreshFileList,
        ),
      ];
    }

    // Use AppBarActionsBuilder to build actions based on selection state
    final selectionState = _selectionBloc.state;
    final folderListState = _folderListBloc.state;

    return AppBarActionsBuilder.buildActions(
      context: context,
      selectionState: selectionState,
      folderListState: folderListState,
      currentPath: _currentPath,
      isNetworkPath: _currentPath.startsWith('#network/'),
      onSortOptionSelected: (SortOption option) {
        _folderListBloc.add(SetSortOption(
          option,
          folderPath: _currentPath,
        ));
        saveSortSetting(option, _currentPath);
      },
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
      onPreviewPaneToggled: _togglePreviewPane,
      isPreviewPaneVisible: isPreviewPaneVisible,
      showPreviewModeOption: isDesktopPlatform,
    );
  }
}

/// A slim, non-intrusive status bar shown at the bottom of the screen
/// while a directory refresh is in progress.
///
/// It overlays the file list via a [Positioned] widget inside a [Stack],
/// so the existing file list layout is never affected.
