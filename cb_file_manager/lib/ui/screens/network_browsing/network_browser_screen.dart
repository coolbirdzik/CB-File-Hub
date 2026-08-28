import 'dart:io';
import 'dart:async'; // Add this import for Completer
// For math operations with drag selection and min/max functions

import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';
import '../../components/common/shared_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
// Import for keyboard keys
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/utils/app_busy_cursor.dart';
import 'package:cb_file_manager/ui/utils/fluent_background.dart'; // Import the Fluent Design background

// Import network browsing components
import 'package:cb_file_manager/bloc/network_browsing/network_browsing_bloc.dart';
import 'package:cb_file_manager/bloc/network_browsing/network_browsing_event.dart';
import 'package:cb_file_manager/bloc/network_browsing/network_browsing_state.dart';

// Import folder list state for models
import '../folder_list/folder_list_state.dart';
import '../folder_list/components/index.dart' as folder_list_components;

// Import selection bloc
import 'package:cb_file_manager/bloc/selection/selection.dart';

// Import tab manager components
import 'package:cb_file_manager/ui/tab_manager/components/index.dart'
    as tab_components;
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart'; // Import TabData explicitly

// Add imports for hardware acceleration
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/widgets/tree_view/tree_view.dart';

import 'package:path/path.dart' as p;
import 'package:cb_file_manager/helpers/network/network_thumbnail_helper.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/components/common/skeleton_helper.dart';
import 'package:cb_file_manager/helpers/network/streaming_helper.dart';
import 'package:cb_file_manager/ui/utils/platform_utils.dart';
import 'package:cb_file_manager/ui/widgets/value_listenable_builders.dart';
import 'package:cb_file_manager/ui/tab_manager/mobile/mobile_file_actions_controller.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/utils/view_mode_spectrum.dart';
import 'package:cb_file_manager/ui/widgets/selection_summary_tooltip.dart';
import 'package:cb_file_manager/ui/components/common/file_view_shell.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_collection_view.dart';

/// A screen for browsing network locations, with a UI consistent with TabbedFolderListScreen
class NetworkBrowserScreen extends StatefulWidget {
  final String path;
  final String tabId;
  final bool showAppBar;

  const NetworkBrowserScreen({
    Key? key,
    required this.path,
    required this.tabId,
    this.showAppBar = true,
  }) : super(key: key);

  @override
  State<NetworkBrowserScreen> createState() => _NetworkBrowserScreenState();
}

class _NetworkBrowserScreenState extends State<NetworkBrowserScreen>
    with SingleTickerProviderStateMixin {
  static const bool _enableVerboseLogs = false;
  late TextEditingController _searchController;
  late TextEditingController _pathController;

  late SelectionBloc _selectionBloc;
  bool _showSearchBar = false;
  String _currentPath = '';

  // View and sort preferences
  ViewMode _viewMode = ViewMode.list;
  SortOption _sortOption = SortOption.nameAsc;
  int _gridZoomLevel = 3;
  ColumnVisibility _columnVisibility = const ColumnVisibility();
  bool _arePreferencesLoading = true;

  // Network browsing BLoC
  late NetworkBrowsingBloc _networkBrowsingBloc;

  // Flag to track if we're handling a path update to avoid duplicate loads
  bool _isHandlingPathUpdate = false;

  // Flag to prevent multiple loads
  bool _isLoadingStarted = false;

  // Flag to track if there are background thumbnail tasks
  bool _hasPendingThumbnails = false;

  // Flag to force immediate UI transition when navigating to a new path.
  // This prevents the old directory contents from being displayed while the next
  // directory load is being queued/started (common with slow SMB listings).
  bool _isNavigationPending = false;

  bool _isNetworkLoadScheduled = false;

  // Subscription for thumbnail loading events
  StreamSubscription? _thumbnailLoadingSubscription;
  StreamSubscription? _networkBrowsingSubscription;

  // Variables for drag selection
  final Map<String, Rect> _itemPositions = {};
  final ValueNotifier<bool> _isDraggingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<Offset?> _dragStartPositionNotifier =
      ValueNotifier<Offset?>(null);
  final ValueNotifier<Offset?> _dragCurrentPositionNotifier =
      ValueNotifier<Offset?>(null);
  final GlobalKey _contentStackKey = GlobalKey();

  bool get _isDesktopMode => !Platform.isAndroid && !Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.path;
    _searchController = TextEditingController();
    _pathController = TextEditingController(text: _currentPath);
    _scrollController = ScrollController();

    // Add scroll listener for auto load more
    _scrollController.addListener(_onScroll);

    // Enable hardware acceleration for smoother animations
    // ignore: deprecated_member_use
    WidgetsBinding.instance.renderView.automaticSystemUiAdjustment = false;
    // Avoid forcing semantics to prevent potential render/semantics assertions

    // Initialize the blocs
    _networkBrowsingBloc = context.read<NetworkBrowsingBloc>();
    _selectionBloc = SelectionBloc();

    // Listen for thumbnail loading changes
    _thumbnailLoadingSubscription =
        ThumbnailLoader.onPendingTasksChanged.listen((count) {
      final hasBackgroundTasks = count > 0;
      if (_hasPendingThumbnails != hasBackgroundTasks) {
        setState(() {
          _hasPendingThumbnails = hasBackgroundTasks;
        });

        // Only show tab loading when there are actual thumbnail tasks
        final isLoading = _hasPendingThumbnails;
        if (mounted) {
          context
              .read<TabManagerBloc>()
              .add(UpdateTabLoading(widget.tabId, isLoading));
        }
      }
    });

    // Load preferences
    _loadPreferences();

    // Listen for network browsing state changes to initialize StreamingHelper
    _networkBrowsingSubscription = _networkBrowsingBloc.stream.listen((state) {
      if (state.currentService != null && mounted) {
        StreamingHelper.instance.initializeStreaming(state.currentService!);
        debugPrint(
            "NetworkBrowserScreen: StreamingHelper initialized with ${state.currentService!.serviceName}");
      }
    });

    // Load initial directory
    // Add a post-frame callback to ensure the BLoC provider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isLoadingStarted) {
        _loadNetworkDirectory();
      }
    });

    // Add listener to search controller to update UI when text changes
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          // Force UI update when search text changes
        });
      }
    });

    // Add listener to path controller to update current path when text changes
    _pathController.addListener(() {
      // Don't trigger path changes while user is editing
      if (_pathController.text != _currentPath && !_isHandlingPathUpdate) {
        // Removed debug print to reduce logging
      }
    });

    // Register mobile file actions controller for mobile UI
    // Defer registration until after first frame to ensure context is ready
    if (!isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _registerMobileActionsController();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Set up a listener for TabManagerBloc state changes
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    final activeTab = tabBloc.state.activeTab;
    if (activeTab != null &&
        activeTab.id == widget.tabId &&
        activeTab.path != _currentPath) {
      _updatePath(activeTab.path);
    }
  }

  @override
  void didUpdateWidget(NetworkBrowserScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.path != oldWidget.path && widget.path != _currentPath) {
      _updatePath(widget.path);
    }
  }

  @override
  void dispose() {
    // Clean up resources
    _searchController.dispose();
    _pathController.dispose();
    _scrollController.dispose();
    _selectionBloc.close();

    // Dispose of ValueNotifiers
    _isDraggingNotifier.dispose();
    _dragStartPositionNotifier.dispose();
    _dragCurrentPositionNotifier.dispose();
    _thumbnailLoadingSubscription?.cancel();
    _networkBrowsingSubscription?.cancel();

    // Remove mobile actions controller
    if (!isDesktopPlatform) {
      MobileFileActionsController.removeTab(widget.tabId);
    }

    // Restore default settings
    // ignore: deprecated_member_use
    WidgetsBinding.instance.renderView.automaticSystemUiAdjustment = true;

    super.dispose();
  }

  /// Register mobile actions controller to connect mobile action buttons with this screen
  void _registerMobileActionsController() {
    if (!mounted) return;

    final controller = MobileFileActionsController.forTab(widget.tabId);

    // Register callbacks (avoid capturing context directly)
    controller.onSearchPressed = () {
      if (mounted) _showSearchTip(context);
    };

    controller.onSortOptionSelected = (option) {
      if (!mounted) return;
      if (_sortOption == option) return; // No change needed

      setState(() {
        _sortOption = option;
      });
      _saveSortSetting(option);

      // Update mobile controller
      controller.currentSortOption = option;

      debugPrint('NetworkBrowserScreen: Sort option changed to $option');

      // Refresh to apply new sort order
      _refreshFileList();
    };

    controller.onViewModeToggled = (mode) {
      if (!mounted) return;
      _setViewMode(mode);
    };

    controller.onRefresh = () {
      if (mounted) _refreshFileList();
    };

    controller.onGridSizePressed = () {
      if (!mounted) return;
      SharedActionBar.showGridSizeDialog(
        context,
        currentGridSize: _gridZoomLevel,
        onApply: _handleGridZoomChange,
        sizeMode: GridSizeMode.columns,
      );
    };

    controller.onSelectionModeToggled = () {
      if (mounted) _toggleSelectionMode();
    };

    // Set initial state
    controller.currentSortOption = _sortOption;
    controller.currentViewMode = _viewMode;
    controller.currentGridSize = _gridZoomLevel;
    controller.currentPath = _currentPath;

    debugPrint(
        'NetworkBrowserScreen: Mobile actions controller registered for tab ${widget.tabId}');
  }

  // Helper methods
  Future<void> _loadPreferences() async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();

      final globalViewMode = await prefs.getViewMode();
      final viewMode = await prefs.getNetworkBrowserViewMode(
        fallback: globalViewMode,
      );
      final effectiveViewMode =
          viewMode == ViewMode.gridPreview ? ViewMode.grid : viewMode;
      final globalSortOption = await prefs.getSortOption();
      final sortOption = await prefs.getNetworkBrowserSortOption(
        fallback: globalSortOption,
      );
      final gridZoomLevel = await prefs.getGridZoomLevel();
      final columnVisibility = await prefs.getColumnVisibility();
      final maxZoom = GridZoomConstraints.maxGridSizeForContext(
        // ignore: use_build_context_synchronously
        context,
        mode: GridSizeMode.columns,
      );

      if (mounted) {
        setState(() {
          _viewMode = effectiveViewMode;
          _sortOption = sortOption;
          _gridZoomLevel = gridZoomLevel
              .clamp(UserPreferences.minGridZoomLevel, maxZoom)
              .toInt();
          _columnVisibility = columnVisibility;
          _arePreferencesLoading = false;
        });
      }
    } catch (e) {
      // Reduced debug logging
      if (mounted) {
        setState(() {
          _arePreferencesLoading = false;
        });
      }
    }
  }

  Future<void> _saveViewModeSetting(ViewMode mode) async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setNetworkBrowserViewMode(mode);
    } catch (e) {
      // Reduced debug logging
    }
  }

  Future<void> _saveSortSetting(SortOption option) async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setNetworkBrowserSortOption(option);
    } catch (e) {
      // Reduced debug logging
    }
  }

  Future<void> _saveGridZoomSetting(int zoomLevel) async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setGridZoomLevel(zoomLevel);
      setState(() {
        _gridZoomLevel = zoomLevel;
      });

      // Update mobile controller
      if (!isDesktopPlatform) {
        MobileFileActionsController.forTab(widget.tabId).currentGridSize =
            zoomLevel;
      }
    } catch (e) {
      // Reduced debug logging
    }
  }

  void _toggleSelectionMode({bool? forceValue}) {
    _selectionBloc.add(ToggleSelectionMode(forceValue: forceValue));
  }

  List<String> _visiblePathsForState(NetworkBrowsingState state) {
    final folders = (state.directories ?? const <FileSystemEntity>[])
        .map((entity) => entity.path);
    final files = (state.files ?? const <FileSystemEntity>[])
        .map((entity) => entity.path);
    return [...folders, ...files];
  }

  Set<String> _folderPathSetForState(NetworkBrowsingState state) {
    return (state.directories ?? const <FileSystemEntity>[])
        .map((entity) => entity.path)
        .toSet();
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

    final browsingState = _networkBrowsingBloc.state;
    final selectionState = _selectionBloc.state;
    if (selectionState.lastSelectedPath == null) {
      _selectionBloc.add(ToggleFileSelection(
        filePath,
        shiftSelect: false,
        ctrlSelect: ctrlSelect,
      ));
      return;
    }

    final visiblePaths = _visiblePathsForState(browsingState);
    final folderPaths = _folderPathSetForState(browsingState);
    final currentIndex = visiblePaths.indexOf(filePath);
    final lastIndex = visiblePaths.indexOf(selectionState.lastSelectedPath!);
    if (currentIndex == -1 || lastIndex == -1) return;

    final start = currentIndex < lastIndex ? currentIndex : lastIndex;
    final end = currentIndex < lastIndex ? lastIndex : currentIndex;
    final range = visiblePaths.sublist(start, end + 1);
    _selectionBloc.add(
      SelectItemsInRect(
        folderPaths: range.where(folderPaths.contains).toSet(),
        filePaths: range.where((path) => !folderPaths.contains(path)).toSet(),
        isCtrlPressed: ctrlSelect,
        isShiftPressed: true,
        lastSelectedPath: filePath,
      ),
    );
  }

  void _toggleFolderSelection(String folderPath,
      {bool shiftSelect = false, bool ctrlSelect = false}) {
    if (!shiftSelect) {
      _selectionBloc.add(ToggleFolderSelection(
        folderPath,
        shiftSelect: false,
        ctrlSelect: ctrlSelect,
      ));
      return;
    }

    final browsingState = _networkBrowsingBloc.state;
    final selectionState = _selectionBloc.state;
    if (selectionState.lastSelectedPath == null) {
      _selectionBloc.add(ToggleFolderSelection(
        folderPath,
        shiftSelect: false,
        ctrlSelect: ctrlSelect,
      ));
      return;
    }

    final visiblePaths = _visiblePathsForState(browsingState);
    final folderPaths = _folderPathSetForState(browsingState);
    final currentIndex = visiblePaths.indexOf(folderPath);
    final lastIndex = visiblePaths.indexOf(selectionState.lastSelectedPath!);
    if (currentIndex == -1 || lastIndex == -1) return;

    final start = currentIndex < lastIndex ? currentIndex : lastIndex;
    final end = currentIndex < lastIndex ? lastIndex : currentIndex;
    final range = visiblePaths.sublist(start, end + 1);
    _selectionBloc.add(
      SelectItemsInRect(
        folderPaths: range.where(folderPaths.contains).toSet(),
        filePaths: range.where((path) => !folderPaths.contains(path)).toSet(),
        isCtrlPressed: ctrlSelect,
        isShiftPressed: true,
        lastSelectedPath: folderPath,
      ),
    );
  }

  void _clearSelection() {
    _selectionBloc.add(ClearSelection());
  }

  void _selectAll(NetworkBrowsingState state) {
    _selectionBloc.add(SelectAll(
      allFilePaths: (state.files ?? const <FileSystemEntity>[])
          .whereType<File>()
          .map((file) => file.path)
          .toList(),
      allFolderPaths: (state.directories ?? const <FileSystemEntity>[])
          .whereType<Directory>()
          .map((directory) => directory.path)
          .toList(),
    ));
  }

  void _toggleViewMode() {
    setState(() {
      if (_viewMode == ViewMode.list) {
        _viewMode = ViewMode.grid;
      } else if (_viewMode == ViewMode.grid) {
        _viewMode = ViewMode.details;
      } else if (_viewMode == ViewMode.details) {
        _viewMode = ViewMode.tree;
      } else {
        _viewMode = ViewMode.list;
      }
    });
    _saveViewModeSetting(_viewMode);

    // Update mobile controller
    if (!isDesktopPlatform) {
      MobileFileActionsController.forTab(widget.tabId).currentViewMode =
          _viewMode;
    }
  }

  void _setViewMode(ViewMode mode) {
    if (_viewMode == mode) return; // No change needed

    setState(() {
      _viewMode = mode;
    });
    _saveViewModeSetting(_viewMode);

    // Update mobile controller
    if (!isDesktopPlatform) {
      MobileFileActionsController.forTab(widget.tabId).currentViewMode =
          _viewMode;
    }

    debugPrint('NetworkBrowserScreen: View mode changed to $_viewMode');
  }

  void _refreshFileList() {
    // Clear network thumbnail caches so that thumbnails are regenerated
    NetworkThumbnailHelper().clearCache();

    // Force reload even if same path by resetting flags
    setState(() {
      _isLoadingStarted = false;
    });

    _loadNetworkDirectory();
  }

  void _loadNetworkDirectory() {
    if (mounted && !_isLoadingStarted) {
      setState(() {
        _isLoadingStarted = true;
      });

      // Reset thumbnail loading state when loading a new directory
      ThumbnailLoader.resetPendingCount();
      _hasPendingThumbnails = false;

      // Don't set tab loading here - only set it when thumbnail loading starts
      // context.read<TabManagerBloc>().add(UpdateTabLoading(widget.tabId, true));
      _networkBrowsingBloc.add(NetworkDirectoryRequested(_currentPath));
    }
  }

  void _scheduleNetworkDirectoryLoad() {
    if (_isNetworkLoadScheduled) return;

    _isNetworkLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isNetworkLoadScheduled = false;
      if (!mounted) return;
      _loadNetworkDirectory();
    });
  }

  // Add a method to check if there are any video/image files in the current state
  bool _hasVideoOrImageFiles(NetworkBrowsingState state) {
    final files = state.files ?? [];
    return files.any((file) => FileTypeUtils.isMediaFile(file.path));
  }

  void _showSearchTip(BuildContext context) {
    setState(() {
      _showSearchBar = true;
    });
  }

  void _toggleSearchBar(BuildContext context) {
    if (_showSearchBar) {
      setState(() {
        _showSearchBar = false;
      });
      return;
    }

    _showSearchTip(context);
  }

  void _navigateToPath(String path) {
    // Cancel any SMB thumbnail work from the previous folder to avoid
    // background SMB operations interfering with the next directory listing.
    if (Platform.isAndroid || Platform.isIOS) {
      if (_currentPath.toLowerCase().startsWith('#network/smb/')) {
        NetworkThumbnailHelper().cancelAllRequests();
        ThumbnailLoader.resetPendingCount();
        _hasPendingThumbnails = false;
      }
    }

    setState(() {
      _currentPath = path;
      _pathController.text = path;
      _isLoadingStarted = false; // Reset loading flag for new path
      _isNavigationPending = true;
    });

    // Ensure path controller is updated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pathController.text != path) {
        _pathController.text = path;
      }
    });

    // Update the tab path (this will automatically handle navigation history)
    context.read<TabManagerBloc>().add(UpdateTabPath(widget.tabId, path));

    _scheduleNetworkDirectoryLoad();

    final pathParts = path.split('/');
    final lastPart = pathParts.lastWhere((part) => part.isNotEmpty,
        orElse: () => AppLocalizations.of(context)!.networkTab);
    final tabName =
        lastPart.isEmpty ? AppLocalizations.of(context)!.networkTab : lastPart;

    context.read<TabManagerBloc>().add(UpdateTabName(widget.tabId, tabName));
  }

  Future<bool> _handleBackButton() async {
    try {
      final tabManagerBloc = context.read<TabManagerBloc>();
      if (tabManagerBloc.canTabNavigateBack(widget.tabId)) {
        final previousPath = tabManagerBloc.getTabPreviousPath(widget.tabId);
        if (previousPath != null) {
          _navigateToPath(previousPath);
          return false; // Don't exit app, we navigated back
        }
      }

      // If we can't navigate back in tab, check if we can pop the navigator
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return false; // Don't exit app
      }

      // If we're at the root and can't navigate back, don't allow back
      return false; // Don't exit app, just prevent back navigation
    } catch (e) {
      debugPrint('Error in _handleBackButton: $e');
      return false; // Don't exit app on error
    }
  }

  void _updatePath(String newPath) {
    if (_isHandlingPathUpdate) return;

    _isHandlingPathUpdate = true;
    _navigateToPath(newPath);
    _isHandlingPathUpdate = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_arePreferencesLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BlocProvider.value(
      value: _selectionBloc,
      child: BlocListener<TabManagerBloc, TabManagerState>(
        listener: (context, tabManagerState) {
          final currentTab = tabManagerState.tabs.firstWhere(
            (tab) => tab.id == widget.tabId,
            orElse: () => TabData(id: '', name: '', path: ''),
          );

          if (currentTab.id.isNotEmpty && currentTab.path != _currentPath) {
            _updatePath(currentTab.path);
          }
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              await _handleBackButton();
            }
          },
          child: BlocConsumer<NetworkBrowsingBloc, NetworkBrowsingState>(
              listenWhen: (previous, current) {
            // Only trigger listener when state actually changes
            return previous.isLoading != current.isLoading ||
                previous.directories != current.directories ||
                previous.files != current.files ||
                previous.hasError != current.hasError;
          }, listener: (context, state) {
            // Check if there are any video/image files in the current directory
            final hasVideoOrImageFiles = _hasVideoOrImageFiles(state);

            // If no video/image files and we have pending thumbnails, reset the count
            if (!hasVideoOrImageFiles && _hasPendingThumbnails) {
              ThumbnailLoader.resetPendingCount();
              _hasPendingThumbnails = false;
            }

            // Only show tab loading when there are actual thumbnail tasks
            final isLoading = _hasPendingThumbnails;
            context
                .read<TabManagerBloc>()
                .add(UpdateTabLoading(widget.tabId, isLoading));

            if (!mounted) return;

            final bool shouldClearLoadingStarted =
                !state.isLoading && _isLoadingStarted;
            final bool shouldClearNavigationPending = _isNavigationPending &&
                (state.hasError ||
                    (state.currentPath != null &&
                        state.currentPath == _currentPath));

            if (shouldClearLoadingStarted || shouldClearNavigationPending) {
              setState(() {
                if (shouldClearLoadingStarted) {
                  _isLoadingStarted = false;
                }
                if (shouldClearNavigationPending) {
                  _isNavigationPending = false;
                }
              });
            }
          }, buildWhen: (previous, current) {
            // Only rebuild when state actually changes
            return previous.isLoading != current.isLoading ||
                previous.directories != current.directories ||
                previous.files != current.files ||
                previous.hasError != current.hasError;
          }, builder: (context, state) {
            return _buildWithSelectionState(context, state);
          }),
        ),
      ),
    );
  }

  Widget _buildWithSelectionState(
      BuildContext context, NetworkBrowsingState networkState) {
    return BlocBuilder<SelectionBloc, SelectionState>(
        builder: (context, selectionState) {
      final bool visualSelectionMode = isDesktopPlatform
          ? selectionState.selectedCount > 1
          : selectionState.isSelectionMode;
      List<Widget> actions = [];

      if (!visualSelectionMode) {
        actions.addAll(SharedActionBar.buildCommonActions(
          context: context,
          onSearchPressed: () => _toggleSearchBar(context),
          isSearchActive: _showSearchBar,
          onSortOptionSelected: (SortOption option) {
            setState(() {
              _sortOption = option;
            });
            _saveSortSetting(option);
            // Refresh the list with the new sort option
            _refreshFileList();
          },
          currentSortOption: _sortOption,
          viewMode: _viewMode,
          onViewModeToggled: _toggleViewMode,
          onViewModeSelected: _setViewMode,
          onRefresh: _refreshFileList,
          currentGridZoomLevel:
              _viewMode == ViewMode.grid ? _gridZoomLevel : null,
          onGridZoomChanged: _handleGridZoomChange,
          onColumnSettingsPressed: _viewMode == ViewMode.details
              ? () {
                  _showColumnVisibilityDialog(context);
                }
              : null,
          onSelectionModeToggled: _toggleSelectionMode,
        ));
      } else {
        // Selection mode actions
        actions.addAll([
          IconButton(
            icon: const Icon(PhosphorIconsLight.x),
            onPressed: _clearSelection,
          ),
          Text(AppLocalizations.of(context)!
              .itemsSelected(selectionState.selectedCount)),
          const Spacer(),
          IconButton(
            icon: const Icon(PhosphorIconsLight.checks),
            tooltip: AppLocalizations.of(context)!.selectAll,
            onPressed: () => _selectAll(networkState),
          ),
        ]);
      }

      return Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title: _buildAppBarTitle(context),
                actions: actions,
                elevation: 0,
                backgroundColor: Colors.transparent,
              )
            : null,
        body: FileViewShell(
          viewMode: _viewMode,
          onViewScaleDelta: _handleViewScaleDelta,
          onMouseBack: _handleBackButton,
          onMouseForward: _handleMouseForwardButton,
          onRefresh: _refreshFileList,
          onSelectAll: () => _selectAll(networkState),
          onSearch: () => _toggleSearchBar(context),
          onEscape: selectionState.selectedCount > 0
              ? _clearSelection
              : _showSearchBar
                  ? () => setState(() {
                        _showSearchBar = false;
                      })
                  : null,
          child: _buildBody(context, networkState, selectionState),
        ),
        floatingActionButton: _buildFloatingActionButton(selectionState),
      );
    });
  }

  Widget _buildAppBarTitle(BuildContext context) {
    if (_showSearchBar) {
      return SizedBox(
        height: 40,
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.searchHintText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.0),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor:
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            prefixIcon:
                const Icon(PhosphorIconsLight.magnifyingGlass, size: 20),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(PhosphorIconsLight.broom),
                    tooltip: AppLocalizations.of(context)!.clearSearch,
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                      });
                    },
                  ),
          ),
        ),
      );
    }

    return Row(
      children: [
        IconButton(
          icon: const Icon(PhosphorIconsLight.arrowLeft),
          onPressed: () async {
            await _handleBackButton();
          },
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              _showPathDialog(context);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Text(
                _currentPath,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, NetworkBrowsingState state,
      SelectionState selectionState) {
    FrameTimingOptimizer().optimizeBeforeHeavyOperation();

    if (_enableVerboseLogs) {
      debugPrint("NetworkBrowserScreen: _buildBody called with state:");
      debugPrint("  - isLoading: ${state.isLoading}");
      debugPrint("  - isLoadingMore: ${state.isLoadingMore}");
      debugPrint("  - hasError: ${state.hasError}");
      debugPrint("  - directories: ${state.directories?.length ?? 'null'}");
      debugPrint("  - files: ${state.files?.length ?? 'null'}");
      debugPrint("  - currentPath: ${state.currentPath}");
      if (state.hasError) {
        debugPrint("NetworkBrowserScreen: Error - ${state.errorMessage}");
      }
    }

    final bool isStatePathOutOfSync =
        state.currentPath != null && state.currentPath != _currentPath;

    final bool shouldShowSkeleton = !state.hasError &&
        (_isNavigationPending ||
            (state.isLoading && !state.hasContent) ||
            isStatePathOutOfSync);

    Widget content;

    if (shouldShowSkeleton) {
      final int crossAxis = _viewMode == ViewMode.grid ? _gridZoomLevel : 2;
      content = FluentBackground.container(
        context: context,
        child: _viewMode == ViewMode.grid
            ? SkeletonHelper.fileGrid(crossAxisCount: crossAxis, itemCount: 12)
            : SkeletonHelper.fileList(itemCount: 12),
      );
    } else if (state.hasError) {
      content = FluentBackground.container(
        context: context,
        padding: const EdgeInsets.all(24.0),
        blurAmount: 5.0,
        child: tab_components.ErrorView(
          errorMessage:
              state.errorMessage ?? AppLocalizations.of(context)!.unknownError,
          isNetworkPath: true,
          onRetry: () {
            _scheduleNetworkDirectoryLoad();
          },
          onGoBack: () {
            _handleBackButton();
          },
        ),
      );
    } else {
      final List<FileSystemEntity> folders = List.from(state.directories ?? []);
      final List<FileSystemEntity> files = List.from(state.files ?? []);

      if (folders.isEmpty && files.isEmpty && !state.isLoading) {
        // An empty folder simply shows nothing — no "empty folder" label.
        content = FluentBackground.container(
          context: context,
          child: const SizedBox.shrink(),
        );
      } else {
        final Widget contentView = _buildContentView(
          folders: folders,
          files: files,
          selectionState: selectionState,
        );

        content = Stack(
          clipBehavior: Clip.none,
          children: [
            FluentBackground(
              blurAmount: 8.0,
              opacity: 0.2,
              enableBlur: true,
              child: GestureDetector(
                onTap: () {
                  if (selectionState.selectedCount > 0) {
                    _clearSelection();
                  }
                },
                onSecondaryTapUp: (details) {
                  _showContextMenu(context, details.globalPosition, null);
                },
                onPanStart: isDesktopPlatform
                    ? (details) {
                        _startDragSelection(details.localPosition);
                      }
                    : null,
                onPanUpdate: isDesktopPlatform
                    ? (details) {
                        _updateDragSelection(details.localPosition);
                      }
                    : null,
                onPanEnd: isDesktopPlatform
                    ? (details) {
                        _endDragSelection();
                      }
                    : null,
                behavior: HitTestBehavior.translucent,
                child: Column(
                  children: [
                    Expanded(child: contentView),
                    if (state.isLoadingMore)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context)!.loading,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _buildDragSelectionOverlay(),
          ],
        );
      }
    }

    final bool showTopLoadingBar =
        _isNavigationPending || state.isLoading || state.isLoadingMore;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        content,
        if (showTopLoadingBar)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2.0),
          ),
        if (selectionState.selectedCount > 1 && isDesktopPlatform)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SelectionSummaryTooltip(
              selectedFileCount: selectionState.selectedFilePaths.length,
              selectedFolderCount: selectionState.selectedFolderPaths.length,
              selectedFilePaths: selectionState.selectedFilePaths.toList(),
              selectedFolderPaths: selectionState.selectedFolderPaths.toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildContentView({
    required List<FileSystemEntity> folders,
    required List<FileSystemEntity> files,
    required SelectionState selectionState,
  }) {
    final items = <FileSystemEntity>[...folders, ...files];
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.columns,
    );
    final crossAxisCount = _gridZoomLevel
        .clamp(
          UserPreferences.minGridZoomLevel,
          maxZoom,
        )
        .toInt();
    return BrowserLikeCollectionView<FileSystemEntity>(
      viewMode: _viewMode,
      items: items,
      isDesktop: isDesktopPlatform,
      stackKey: _contentStackKey,
      onRefresh: () async => _refreshFileList(),
      scrollController: _scrollController,
      padding: const EdgeInsets.all(8.0),
      physics: const ClampingScrollPhysics(),
      gridCacheExtent: 1500,
      detailsCacheExtent: 800,
      listCacheExtent: 1200,
      itemIdentity: (item) => item.path,
      registerItemPosition: _registerItemPosition,
      dragSelectionOverlay: const SizedBox.shrink(),
      gridCrossAxisCount: crossAxisCount,
      listItemBuilder: (itemContext, item) =>
          _buildListItem(itemContext, item, selectionState),
      gridItemBuilder: (itemContext, item) =>
          _buildGridItem(itemContext, item, selectionState),
      detailsItemBuilder: (itemContext, item) =>
          _buildDetailsItem(itemContext, item, selectionState),
      treeIsLeaf: (item) => item is File,
      treeChildrenLoader: _loadNetworkChildren,
      treeItemBuilder: (itemContext, node, depth) =>
          _buildNetworkTreeRow(itemContext, node, depth),
    );
  }

  // Scroll controller for auto load more
  late ScrollController _scrollController;
  bool _isLoadingMore = false;

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreItems();
    }
  }

  Future<void> _loadMoreItems() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    // Auto loading logic would go here

    setState(() {
      _isLoadingMore = false;
    });
  }

  void _handleGridZoomChange(int newZoomLevel) {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.columns,
    );
    final clamped =
        newZoomLevel.clamp(UserPreferences.minGridZoomLevel, maxZoom).toInt();
    _saveGridZoomSetting(clamped);
  }

  /// Unified Ctrl+scroll spectrum handler: walks tree↔detail↔list↔grid and
  /// adjusts grid item size. `+1` = more spacious, `-1` = denser.
  void _handleViewScaleDelta(int delta) {
    if (delta == 0) return;
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.columns,
    );
    final result = ViewModeSpectrum.step(
      currentMode: _viewMode,
      currentZoom: _gridZoomLevel,
      // Network browser supports tree/details/list (no columns mode).
      supported: const {ViewMode.tree, ViewMode.details, ViewMode.list},
      delta: delta,
      minZoom: UserPreferences.minGridZoomLevel,
      maxZoom: maxZoom,
    );

    if (result.mode != _viewMode) {
      _setViewMode(result.mode);
    }
    if (result.gridZoomLevel != _gridZoomLevel) {
      _saveGridZoomSetting(result.gridZoomLevel);
    }
  }

  void _showColumnVisibilityDialog(BuildContext context) {
    // Implementation for column visibility dialog
  }

  void _showPathDialog(BuildContext context) {
    // Implementation for path dialog
  }

  void _showContextMenu(BuildContext context, Offset position, String? path) {
    // Implementation for context menu
  }

  void _startDragSelection(Offset position) {
    // Implementation for drag selection start
  }

  void _updateDragSelection(Offset position) {
    // Implementation for drag selection update
  }

  void _endDragSelection() {
    // Implementation for drag selection end
  }

  void _registerItemPosition(String path, Rect position) {
    _itemPositions[path] = position;
  }

  Widget _buildDragSelectionOverlay() {
    return ValueListenableBuilder3<bool, Offset?, Offset?>(
      valueListenable1: _isDraggingNotifier,
      valueListenable2: _dragStartPositionNotifier,
      valueListenable3: _dragCurrentPositionNotifier,
      builder: (context, isDragging, startPosition, currentPosition, child) {
        if (!isDragging || startPosition == null || currentPosition == null) {
          return const SizedBox.shrink();
        }

        final rect = Rect.fromPoints(startPosition, currentPosition);
        return Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).primaryColor,
                width: 1,
              ),
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingActionButton(SelectionState selectionState) {
    return FloatingActionButton(
      heroTag: null, // Disable hero animation to avoid conflicts
      onPressed: _refreshFileList,
      child: const Icon(PhosphorIconsLight.arrowsClockwise),
    );
  }

  void _handleMouseForwardButton() {
    // Implementation for mouse forward button
  }

  void _handleFileOpen(BuildContext context, File file) {
    AppBusyCursor.pulse();
    final String filePath = file.path;
    final String extension = p.extension(filePath).toLowerCase();
    final String fileName = p.basename(filePath);

    debugPrint(
        "NetworkBrowserScreen: Opening file $filePath with extension $extension");

    // For all file types (including images), use StreamingHelper for network files
    // This ensures proper handling of SMB files on mobile
    StreamingHelper.instance.openFileWithStreaming(
      context,
      filePath,
      fileName,
    );
  }

  Widget _wrapNetworkItem(bool isSelected, Widget child) {
    return RepaintBoundary(
      child: FluentBackground.container(
        context: context,
        padding: EdgeInsets.zero,
        blurAmount: 5.0,
        opacity: isSelected ? 0.8 : 0.6,
        backgroundColor: isSelected
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.6)
            : Theme.of(context).cardColor.withValues(alpha: 0.4),
        child: child,
      ),
    );
  }

  Widget _buildGridItem(
    BuildContext itemContext,
    FileSystemEntity item,
    SelectionState selectionState,
  ) {
    final isSelected = selectionState.isPathSelected(item.path);
    if (item is Directory) {
      return KeyedSubtree(
        key: ValueKey('folder-grid-${item.path}'),
        child: _wrapNetworkItem(
          isSelected,
          folder_list_components.FolderGridItem(
            key: ValueKey('folder-grid-item-${item.path}'),
            folder: item,
            onNavigate: _navigateToPath,
            isSelected: isSelected,
            toggleFolderSelection: _toggleFolderSelection,
            isDesktopMode: _isDesktopMode,
            lastSelectedPath: selectionState.lastSelectedPath,
            clearSelectionMode: _clearSelection,
          ),
        ),
      );
    }

    final file = item as File;
    return KeyedSubtree(
      key: ValueKey('file-grid-${file.path}'),
      child: _wrapNetworkItem(
        isSelected,
        folder_list_components.FileGridItem(
          key: ValueKey('file-grid-item-${file.path}'),
          file: file,
          onFileTap: (openedFile, _) =>
              _handleFileOpen(itemContext, openedFile),
          isSelected: isSelected,
          isSelectionMode: isDesktopPlatform
              ? selectionState.selectedCount > 1
              : selectionState.isSelectionMode,
          toggleFileSelection: _toggleFileSelection,
          toggleSelectionMode: _toggleSelectionMode,
          isDesktopMode: _isDesktopMode,
          lastSelectedPath: selectionState.lastSelectedPath,
        ),
      ),
    );
  }

  Widget _buildDetailsItem(
    BuildContext itemContext,
    FileSystemEntity item,
    SelectionState selectionState,
  ) {
    final isSelected = selectionState.isPathSelected(item.path);
    if (item is Directory) {
      return KeyedSubtree(
        key: ValueKey('folder-details-${item.path}'),
        child: _wrapNetworkItem(
          isSelected,
          folder_list_components.FolderDetailsItem(
            key: ValueKey('folder-details-item-${item.path}'),
            folder: item,
            onTap: _navigateToPath,
            isSelected: isSelected,
            toggleFolderSelection: _toggleFolderSelection,
            isDesktopMode: _isDesktopMode,
            lastSelectedPath: selectionState.lastSelectedPath,
            clearSelectionMode: _clearSelection,
            columnVisibility: _columnVisibility,
          ),
        ),
      );
    }

    final file = item as File;
    return KeyedSubtree(
      key: ValueKey('file-details-${file.path}'),
      child: _wrapNetworkItem(
        isSelected,
        folder_list_components.FileDetailsItem(
          key: ValueKey('file-details-item-${file.path}'),
          file: file,
          onTap: (openedFile, _) => _handleFileOpen(itemContext, openedFile),
          isSelected: isSelected,
          toggleFileSelection: _toggleFileSelection,
          state: FolderListState(_currentPath),
          showDeleteTagDialog: (_, __, ___) {},
          showAddTagToFileDialog: (_, __) {},
          isDesktopMode: _isDesktopMode,
          lastSelectedPath: selectionState.lastSelectedPath,
          columnVisibility: _columnVisibility,
        ),
      ),
    );
  }

  Widget _buildListItem(
    BuildContext itemContext,
    FileSystemEntity item,
    SelectionState selectionState,
  ) {
    final isSelected = selectionState.isPathSelected(item.path);
    if (item is Directory) {
      return KeyedSubtree(
        key: ValueKey('folder-list-${item.path}'),
        child: _wrapNetworkItem(
          isSelected,
          folder_list_components.FolderItem(
            key: ValueKey('folder-list-item-${item.path}'),
            folder: item,
            onTap: _navigateToPath,
            isSelected: isSelected,
            toggleFolderSelection: _toggleFolderSelection,
            isDesktopMode: _isDesktopMode,
            lastSelectedPath: selectionState.lastSelectedPath,
            clearSelectionMode: _clearSelection,
          ),
        ),
      );
    }

    final file = item as File;
    return KeyedSubtree(
      key: ValueKey('file-list-${file.path}'),
      child: _wrapNetworkItem(
        isSelected,
        folder_list_components.FileItem(
          key: ValueKey('file-list-item-${file.path}'),
          file: file,
          state: FolderListState(_currentPath),
          isSelectionMode: isDesktopPlatform
              ? selectionState.selectedCount > 1
              : selectionState.isSelectionMode,
          isSelected: isSelected,
          toggleFileSelection: _toggleFileSelection,
          showDeleteTagDialog: (_, __, ___) {},
          showAddTagToFileDialog: (_, __) {},
          onFileTap: (openedFile, _) =>
              _handleFileOpen(itemContext, openedFile),
          isDesktopMode: _isDesktopMode,
          lastSelectedPath: selectionState.lastSelectedPath,
        ),
      ),
    );
  }

  /// Lazy children loader for the network tree view.
  ///
  /// Reuses the active connection's `NetworkServiceBase.listDirectory`
  /// (the same call the navigation flow uses), then maps results into
  /// `TreeNode<FileSystemEntity>` with folders first, then files.
  Future<List<TreeNode<FileSystemEntity>>> _loadNetworkChildren(
    TreeNode<FileSystemEntity> node,
  ) async {
    final entity = node.data;
    if (entity is! Directory) return const [];
    final service = _networkBrowsingBloc.state.currentService;
    if (service == null) return const [];

    try {
      final contents = await service.listDirectory(entity.path);
      final folders = contents.whereType<Directory>().toList()
        ..sort((a, b) => a.path
            .split('/')
            .last
            .toLowerCase()
            .compareTo(b.path.split('/').last.toLowerCase()));
      final files = contents.whereType<File>().toList()
        ..sort((a, b) => a.path
            .split('/')
            .last
            .toLowerCase()
            .compareTo(b.path.split('/').last.toLowerCase()));
      return [
        ...folders.map((d) => TreeNode<FileSystemEntity>(
              id: d.path,
              data: d,
              isLeaf: false,
            )),
        ...files.map((f) => TreeNode<FileSystemEntity>(
              id: f.path,
              data: f,
              isLeaf: true,
            )),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Compact row for the network tree.
  Widget _buildNetworkTreeRow(
    BuildContext itemContext,
    TreeNode<FileSystemEntity> node,
    int depth,
  ) {
    final entity = node.data;
    final isDir = entity is Directory;
    final segments = entity.path
        .split(RegExp(r'[\\/]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final name = segments.isEmpty ? entity.path : segments.last;
    final theme = Theme.of(itemContext);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isDir) {
          _navigateToPath(entity.path);
        }
      },
      onDoubleTap: () {
        if (isDir) {
          _navigateToPath(entity.path);
        } else if (entity is File) {
          _handleFileOpen(itemContext, entity);
        }
      },
      child: Row(
        children: [
          Icon(
            isDir ? PhosphorIconsLight.folder : PhosphorIconsLight.file,
            size: 14,
            color: isDir
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isDir ? FontWeight.w500 : FontWeight.normal,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
