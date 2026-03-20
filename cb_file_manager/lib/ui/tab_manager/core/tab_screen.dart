import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'; // Import for keyboard shortcuts
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';
import 'tab_manager.dart';
import 'tab_data.dart';
import 'tab_paths.dart';
import '../../drawer.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'tabbed_folder/tabbed_folder_list_screen.dart';
import 'package:flutter/gestures.dart'; // Import for mouse scrolling
import '../desktop/scrollable_tab_bar.dart'; // Import our custom ScrollableTabBar
import '../desktop/desktop_tab_drag_data.dart';
import '../mobile/mobile_tab_view.dart'; // Import giao diện mobile kiểu Chrome
import 'package:cb_file_manager/config/languages/app_localizations.dart'; // Import AppLocalizations
import 'package:cb_file_manager/config/translation_helper.dart'; // Import translation helper
import 'package:cb_file_manager/ui/screens/system_screen_router.dart'; // Import system screen router
// import 'package:cb_file_manager/widgets/test_native_streaming.dart'; // Test widget removed
import '../../utils/route.dart';
import '../../screens/home/home_screen.dart'; // Import home screen
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/windowing/desktop_windowing_service.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/services/windowing/windows_native_tab_drag_drop_service.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'split_pane_view.dart'; // Split-pane view

// Create a custom scroll behavior that supports mouse wheel scrolling
class TabBarMouseScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        ...super.dragDevices,
      };
}

/// A screen that manages and displays tabbed content
class TabScreen extends StatefulWidget {
  const TabScreen({Key? key}) : super(key: key);

  @override
  State<TabScreen> createState() => _TabScreenState();
}

// Create a new tab action for keyboard shortcuts
class CreateNewTabIntent extends Intent {
  const CreateNewTabIntent();
}

// Create a close tab action for keyboard shortcuts
class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

// Create a new window action for keyboard shortcuts
class CreateNewWindowIntent extends Intent {
  const CreateNewWindowIntent();
}

// Create actions for switching to specific tabs
class SwitchToTabIntent extends Intent {
  final int tabIndex;
  const SwitchToTabIntent(this.tabIndex);
}

/// Intent to toggle split-pane view for the active tab.
class ToggleSplitViewIntent extends Intent {
  const ToggleSplitViewIntent();
}

class _TabScreenState extends State<TabScreen> with TickerProviderStateMixin {
  // Drawer state variables
  bool _isDrawerPinned = false;
  String? _lastPersistedTabPath;

  // Key for the scaffold to control drawer programmatically
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _tabStripAreaKey = GlobalKey();

  // Controller cho TabBar tích hợp
  late TabController _tabController;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool get _isSecondaryDesktopWindow =>
      _isDesktop &&
      Platform.environment[WindowStartupPayload.envSecondaryWindowKey] == '1';

  OverlayEntry? _windowDropOverlayEntry;
  final Map<String, _CachedTabContent> _tabContentCache =
      <String, _CachedTabContent>{};
  StreamSubscription<TabManagerState>? _tabStateSubscription;

  @override
  void initState() {
    super.initState();
    // Initialize with a temporary controller. It will be properly set in postFrameCallback.
    _tabController = TabController(length: 0, vsync: this);
    _tabStateSubscription = context.read<TabManagerBloc>().stream.listen(
      (state) {
        unawaited(_persistLastOpenedTabPath(state));
      },
    );
    unawaited(
      _persistLastOpenedTabPath(context.read<TabManagerBloc>().state),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadDrawerPreferences();
      await _restoreLastOpenedTabIfNeeded();
      if (mounted) {
        final initialState = context.read<TabManagerBloc>().state;
        // _updateTabController will create the controller with the correct length
        // and set its initialIndex based on the initialState from BLoC.
        _updateTabController(initialState.tabs.length);
      }
    });
  }

  @override
  void didUpdateWidget(TabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Content removed: BlocBuilder now handles all TabController updates
    // based on TabManagerBloc state.
  }

  @override
  void dispose() {
    _removeWindowDropOverlay();
    _tabContentCache.clear();
    _tabStateSubscription?.cancel();
    _tabStateSubscription = null;
    _tabController.dispose();
    super.dispose();
  }

  void _updateTabController(int tabCount) {
    final oldController = _tabController;

    // Determine the initialIndex for the new TabController based on current BLoC state.
    int newInitialIndex = 0;
    if (mounted) {
      // Ensure context is valid for reading BLoC
      final currentState = context.read<TabManagerBloc>().state;
      if (currentState.activeTabId != null && tabCount > 0) {
        final activeIndexFromBloc = currentState.tabs
            .indexWhere((tab) => tab.id == currentState.activeTabId);
        if (activeIndexFromBloc >= 0 && activeIndexFromBloc < tabCount) {
          newInitialIndex = activeIndexFromBloc;
        } else if (tabCount > 0) {
          // Fallback if activeId is somehow invalid
          newInitialIndex =
              (oldController.index < tabCount && oldController.index >= 0)
                  ? oldController.index
                  : tabCount - 1;
        }
      } else if (tabCount > 0) {
        // No activeTabId, but tabs exist
        newInitialIndex =
            (oldController.index < tabCount && oldController.index >= 0)
                ? oldController.index
                : 0;
      }
    } else if (tabCount > 0) {
      // Fallback if not mounted (less ideal)
      newInitialIndex =
          (oldController.index < tabCount && oldController.index >= 0)
              ? oldController.index
              : 0;
    }

    _tabController = TabController(
      length: tabCount,
      vsync: this,
      initialIndex: newInitialIndex, // Set based on BLoC's active tab
    );
    oldController.dispose();

    if (mounted) {
      // This setState is crucial for the UI to pick up the new _tabController instance
      setState(() {});
    }
  }

  void _clearTabSelectionWhenClickOutsideStrip(PointerDownEvent event) {
    if (!_isDesktop) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event.buttons != kPrimaryMouseButton) return;

    final bloc = context.read<TabManagerBloc>();
    if (bloc.state.selectedTabIds.isEmpty) return;

    final stripContext = _tabStripAreaKey.currentContext;
    final stripBox = stripContext?.findRenderObject() as RenderBox?;
    if (stripBox == null || !stripBox.hasSize) return;

    final stripOrigin = stripBox.localToGlobal(Offset.zero);
    final stripRect = stripOrigin & stripBox.size;
    if (!stripRect.contains(event.position)) {
      bloc.add(ClearTabSelection());
    }
  }

  // Load drawer preferences from storage
  Future<void> _loadDrawerPreferences() async {
    try {
      // Get the UserPreferences singleton instance without reinitializing
      final UserPreferences prefs = UserPreferences.instance;
      final drawerPinned = await prefs.getDrawerPinned();

      if (mounted) {
        setState(() {
          // Only set drawer to pinned if not on a small screen
          final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
          _isDrawerPinned = isSmallScreen ? false : drawerPinned;
        });
      }
    } catch (e) {
      debugPrint('Error loading drawer preferences: $e');
    }
  }

  Future<void> _restoreLastOpenedTabIfNeeded() async {
    try {
      if (_isSecondaryDesktopWindow) return;

      final tabBloc = context.read<TabManagerBloc>();
      if (tabBloc.state.tabs.isNotEmpty) return;

      final prefs = UserPreferences.instance;
      await prefs.init();
      final rememberWorkspace = await prefs.getRememberTabWorkspaceEnabled();
      if (!rememberWorkspace) return;

      // Restore all open tabs
      final lastOpenedTabs = await prefs.getLastOpenedTabsList();
      final lastActivePath = await prefs.getLastOpenedTabPath();

      if (!mounted) return;
      if (tabBloc.state.tabs.isNotEmpty) return;

      if (lastOpenedTabs.isNotEmpty) {
        for (final path in lastOpenedTabs) {
          final isLastActive = path == lastActivePath;
          tabBloc.add(AddTab(
            path: path,
            name: _tabNameForRestoredPath(path),
            switchToTab: isLastActive,
          ));
        }
      } else if (lastActivePath != null && lastActivePath.trim().isNotEmpty) {
        // Fallback for backward compatibility
        tabBloc.add(AddTab(
          path: lastActivePath,
          name: _tabNameForRestoredPath(lastActivePath),
          switchToTab: true,
        ));
      }
    } catch (e) {
      debugPrint('Error restoring last opened tab: $e');
    }
  }

  String _tabNameForRestoredPath(String path) {
    if (path == '#home') return context.tr.homeTab;
    if (path == '#gallery') return context.tr.imageGallery;
    if (path == '#video') return context.tr.videoGallery;
    if (path == '#tags') return context.tr.tags;
    if (path == '#network') return context.tr.networkTab;
    if (path == '#trash') return context.tr.trashBin;
    if (isDrivesPath(path)) return context.tr.drivesTab;
    return _getStorageDisplayName(path);
  }

  Future<void> _persistLastOpenedTabPath(TabManagerState state) async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();
      final rememberWorkspace = await prefs.getRememberTabWorkspaceEnabled();
      if (!rememberWorkspace) {
        if (_lastPersistedTabPath != null) {
          await prefs.clearLastOpenedTabPath();
          await prefs.setLastOpenedTabsList([]);
          _lastPersistedTabPath = null;
        }
        return;
      }

      final activeTab = state.activeTab;
      if (activeTab == null) return;

      final path = activeTab.path.trim();

      // Save all open tabs
      final allPaths = state.tabs
          .map((t) => t.path.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      await prefs.setLastOpenedTabsList(allPaths);

      // Save active tab path
      if (path.isEmpty) return;

      final saved = await prefs.setLastOpenedTabPath(path);
      if (saved) {
        _lastPersistedTabPath = path;
      }
    } catch (e) {
      debugPrint('Error persisting last opened tab: $e');
    }
  }

  // Save drawer pinned state
  Future<void> _saveDrawerPinned(bool isPinned) async {
    try {
      // Get the UserPreferences singleton instance without reinitializing
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.setDrawerPinned(isPinned);
    } catch (e) {
      debugPrint('Error saving drawer pinned state: $e');
    }
  }

  // Toggle drawer pin state
  void _toggleDrawerPin() {
    // Check if we're on a small screen
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;

    setState(() {
      // Only allow pinning on larger screens
      if (!isSmallScreen) {
        _isDrawerPinned = !_isDrawerPinned;
        _saveDrawerPinned(_isDrawerPinned);
      } else {
        // Force unpinned on small screens and show a message
        _isDrawerPinned = false;
        _saveDrawerPinned(false);

        // Show a message explaining why pinning isn't available
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.menuPinningOnlyLargeScreens),
              duration: const Duration(seconds: 2),
            ),
          );
        });
      }
    });
  }

  // Xác định thiết bị là tablet hay điện thoại dựa trên kích thước màn hình
  bool _isTablet(BuildContext context) {
    // Coi rộng > 600dp là tablet, theo Material Design guidelines
    return MediaQuery.of(context).size.shortestSide >= 600;
  }

  // Method to close the current active tab
  void _handleCloseCurrentTab() {
    final state = context.read<TabManagerBloc>().state;
    final activeTab = state.activeTab;
    if (activeTab != null) {
      context.read<TabManagerBloc>().add(CloseTab(activeTab.id));
    }
  }

  // Method to switch to a specific tab by index
  void _handleSwitchToTab(int tabIndex) {
    final state = context.read<TabManagerBloc>().state;
    // Check if the tab index is valid
    if (tabIndex >= 0 && tabIndex < state.tabs.length) {
      // Switch to the tab
      context.read<TabManagerBloc>().add(SwitchToTab(state.tabs[tabIndex].id));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apply frame timing optimization before building the tabbed interface
    // This helps prevent the "Reported frame time is older than the last one" error
    FrameTimingOptimizer().optimizeBeforeHeavyOperation();

    // Xác định xem thiết bị có phải là tablet hay không
    final isTablet = _isTablet(context);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final desktopUnifiedChromeColor = _isDesktop
        ? (isDarkMode
            ? theme.colorScheme.surface.withValues(alpha: 0.32)
            : const Color(0xFFFFFFFF).withValues(alpha: 0.22))
        : theme.scaffoldBackgroundColor;
    final desktopBodyTintColor = _isDesktop ? desktopUnifiedChromeColor : null;
    final desktopTopBarColor = _isDesktop ? Colors.transparent : null;
    final desktopActiveTabColor = _isDesktop ? Colors.transparent : null;

    return BlocProvider(
      create: (context) => DrawerCubit()
        ..loadStorageLocations(
            activeTabId: context.read<TabManagerBloc>().state.activeTabId),
      child: BlocListener<TabManagerBloc, TabManagerState>(
        listener: (context, state) {
          context.read<DrawerCubit>().setActiveTab(state.activeTabId);
        },
        child: BlocBuilder<TabManagerBloc, TabManagerState>(
          builder: (context, state) {
            // 1. Handle TabController LENGTH update (if needed)
            if (isTablet && _tabController.length != state.tabs.length) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  // Re-read latest state to ensure consistency for the update.
                  final latestStateForLengthUpdate =
                      context.read<TabManagerBloc>().state;
                  if (_tabController.length !=
                      latestStateForLengthUpdate.tabs.length) {
                    // _updateTabController now sets the correct initialIndex from BLoC state
                    _updateTabController(
                        latestStateForLengthUpdate.tabs.length);
                  }
                }
              });
            }
            // 2. Handle TabController INDEX synchronization if length is already correct.
            // This covers cases where the active tab changes without a change in tab count.
            // If _updateTabController was just called, the new controller it created
            // should already have the correct initialIndex, making this animation redundant for that specific frame.
            // However, this handles clicks on tabs that don't change the tab count.
            else if (isTablet &&
                state.activeTabId != null &&
                state.tabs.isNotEmpty) {
              final activeIndexFromBloc =
                  state.tabs.indexWhere((tab) => tab.id == state.activeTabId);
              if (activeIndexFromBloc >= 0 &&
                  activeIndexFromBloc < _tabController.length) {
                if (_tabController.index != activeIndexFromBloc) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      // Re-read state to ensure we're acting on the most current information.
                      final latestStateForSync =
                          context.read<TabManagerBloc>().state;
                      if (latestStateForSync.activeTabId != null &&
                          latestStateForSync.tabs.isNotEmpty &&
                          _tabController.length ==
                              latestStateForSync.tabs.length) {
                        // Check length again

                        final latestActiveIndex = latestStateForSync.tabs
                            .indexWhere((tab) =>
                                tab.id == latestStateForSync.activeTabId);
                        if (latestActiveIndex >= 0 &&
                            latestActiveIndex < _tabController.length) {
                          if (_tabController.index != latestActiveIndex) {
                            _tabController.animateTo(latestActiveIndex);
                          }
                        }
                      }
                    }
                  });
                }
              }
            }

            // Define keyboard shortcuts and actions
            final Map<ShortcutActivator, Intent> shortcuts = {
              // Create new tab with Ctrl+T
              const SingleActivator(LogicalKeyboardKey.keyT, control: true):
                  const CreateNewTabIntent(),
              // Create new tab with Ctrl+N
              const SingleActivator(LogicalKeyboardKey.keyN, control: true):
                  const CreateNewTabIntent(),
              // Create new window with Ctrl+Shift+N
              const SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
                shift: true,
              ): const CreateNewWindowIntent(),
              // macOS equivalents
              const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
                  const CreateNewTabIntent(),
              const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
                shift: true,
              ): const CreateNewWindowIntent(),
              // Close current tab with Ctrl+W
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.keyW):
                  const CloseTabIntent(),
              // Toggle split-pane view with Ctrl+\
              const SingleActivator(
                LogicalKeyboardKey.backslash,
                control: true,
              ): const ToggleSplitViewIntent(),
              // Switch to tabs 1-9 with Ctrl+1, Ctrl+2, etc.
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.digit1):
                  const SwitchToTabIntent(0),
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.digit2):
                  const SwitchToTabIntent(1),
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.digit3):
                  const SwitchToTabIntent(2),
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.digit4):
                  const SwitchToTabIntent(3),
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.digit5):
                  const SwitchToTabIntent(4),
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.digit6):
                  const SwitchToTabIntent(5),
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.digit7):
                  const SwitchToTabIntent(6),
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.digit8):
                  const SwitchToTabIntent(7),
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.digit9):
                  const SwitchToTabIntent(8),
            };

            final Map<Type, Action<Intent>> actions = {
              CreateNewTabIntent: CallbackAction<CreateNewTabIntent>(
                onInvoke: (CreateNewTabIntent intent) {
                  _handleAddNewTab();
                  return null;
                },
              ),
              CreateNewWindowIntent: CallbackAction<CreateNewWindowIntent>(
                onInvoke: (CreateNewWindowIntent intent) {
                  if (!_isDesktop) return null;
                  HapticFeedback.mediumImpact();
                  SchedulerBinding.instance.addPostFrameCallback((_) async {
                    await locator<DesktopWindowingService>().openNewWindow(
                      tabs: [
                        WindowTabPayload(
                            path: '#home', name: context.tr.homeTab),
                      ],
                    );
                  });
                  return null;
                },
              ),
              CloseTabIntent: CallbackAction<CloseTabIntent>(
                onInvoke: (CloseTabIntent intent) => _handleCloseCurrentTab(),
              ),
              SwitchToTabIntent: CallbackAction<SwitchToTabIntent>(
                onInvoke: (SwitchToTabIntent intent) =>
                    _handleSwitchToTab(intent.tabIndex),
              ),
              ToggleSplitViewIntent: CallbackAction<ToggleSplitViewIntent>(
                onInvoke: (ToggleSplitViewIntent intent) {
                  _handleToggleSplitView();
                  return null;
                },
              ),
            };

            return Shortcuts(
              shortcuts: shortcuts,
              child: Actions(
                actions: actions,
                child: FocusScope(
                  autofocus: true,
                  child: Builder(
                    builder: (popContext) {
                      return PopScope(
                        canPop: false, // Always intercept back button
                        onPopInvokedWithResult: (didPop, result) async {
                          if (!didPop) {
                            try {
                              // First, check if there are any screens pushed on the active tab's navigator
                              // (like video player, image viewer, etc.)
                              final activeTab = state.activeTab;

                              if (activeTab != null) {
                                final tabNavigatorState =
                                    activeTab.navigatorKey.currentState;
                                if (tabNavigatorState != null &&
                                    tabNavigatorState.canPop()) {
                                  tabNavigatorState.pop();
                                  return;
                                }
                              }

                              // Then check main navigator
                              final mainNavigator = Navigator.of(popContext);
                              if (mainNavigator.canPop()) {
                                mainNavigator.pop();
                                return;
                              }

                              // Handle tab navigation history
                              if (activeTab != null) {
                                // Check if the active tab can navigate back
                                if (activeTab.navigationHistory.length > 1) {
                                  // Use the proper backNavigationToPath method
                                  final tabManagerBloc =
                                      context.read<TabManagerBloc>();
                                  tabManagerBloc
                                      .backNavigationToPath(activeTab.id);
                                  return;
                                }
                              }

                              // If we're at the root (no history), exit app
                              SystemNavigator.pop();
                            } catch (e) {
                              debugPrint('Error in TabScreen PopScope: $e');
                            }
                          }
                        },
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown:
                              _clearTabSelectionWhenClickOutsideStrip,
                          child: Scaffold(
                            key: _scaffoldKey,
                            backgroundColor: desktopBodyTintColor,
                            // Modern AppBar, always present on tablet/desktop for custom title bar
                            appBar: isTablet
                                ? AppBar(
                                    automaticallyImplyLeading: false,
                                    elevation: 0,
                                    backgroundColor: desktopTopBarColor,
                                    surfaceTintColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    leading: !_isDrawerPinned
                                        ? IconButton(
                                            icon: Icon(
                                              PhosphorIconsLight.list,
                                              color: isDarkMode
                                                  ? Colors.white
                                                      .withValues(alpha: 0.9)
                                                  : theme.colorScheme.onSurface,
                                              size: 22,
                                            ),
                                            tooltip: MaterialLocalizations.of(
                                                    context)
                                                .openAppDrawerTooltip,
                                            style: IconButton.styleFrom(
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12.0),
                                              ),
                                              backgroundColor: isDarkMode
                                                  ? Colors.white
                                                      .withValues(alpha: 0.04)
                                                  : theme
                                                      .colorScheme.onSurface
                                                      .withValues(alpha: 0.05),
                                            ),
                                            onPressed: () => _scaffoldKey
                                                .currentState
                                                ?.openDrawer(),
                                          )
                                        : null,
                                    // Always show ScrollableTabBar in the title for Windows (isTablet)
                                    // It handles its own content (tabs or add button) and window controls.
                                    title: KeyedSubtree(
                                      key: _tabStripAreaKey,
                                      child: ScrollConfiguration(
                                        behavior: TabBarMouseScrollBehavior(),
                                        child: ScrollableTabBar(
                                          controller:
                                              _tabController, // Ensure this controller has the correct length
                                          barBackgroundColor:
                                              desktopTopBarColor,
                                          activeTabBackgroundColor:
                                              desktopActiveTabColor,
                                          onTabPrimaryClick:
                                              (index, shiftPressed) {
                                            if (index >= state.tabs.length)
                                              return;

                                            final tabId = state.tabs[index].id;
                                            final bloc =
                                                context.read<TabManagerBloc>();
                                            final selectedIds =
                                                state.selectedTabIds;
                                            final keepMultiSelection =
                                                _isDesktop &&
                                                    !shiftPressed &&
                                                    selectedIds.length > 1 &&
                                                    selectedIds.contains(tabId);

                                            if (_isDesktop && shiftPressed) {
                                              // Shift+click is additive:
                                              // - First Shift selection includes current active tab.
                                              // - Next Shift selections only add (do not toggle off).
                                              if (selectedIds.isEmpty) {
                                                final activeId =
                                                    state.activeTabId;
                                                if (activeId != null &&
                                                    activeId != tabId &&
                                                    state.tabs.any((tab) =>
                                                        tab.id == activeId)) {
                                                  bloc.add(ToggleTabSelection(
                                                      activeId));
                                                }
                                                bloc.add(
                                                    ToggleTabSelection(tabId));
                                              } else if (!selectedIds
                                                  .contains(tabId)) {
                                                bloc.add(
                                                    ToggleTabSelection(tabId));
                                              }
                                            } else if (_isDesktop &&
                                                !keepMultiSelection) {
                                              bloc.add(ClearTabSelection());
                                            }

                                            bloc.add(SwitchToTab(tabId));
                                          },
                                          draggableTabs: _isDesktop
                                              ? state.tabs
                                                  .map(
                                                    (t) => DesktopTabDragData(
                                                      tabId: t.id,
                                                      tab: _toWindowTabPayload(
                                                          t),
                                                    ),
                                                  )
                                                  .toList(growable: false)
                                              : null,
                                          selectedTabIds: _isDesktop
                                              ? state.selectedTabIds
                                              : const <String>{},
                                          onTabReorder: _isDesktop
                                              ? (fromIndex, toIndex) {
                                                  context
                                                      .read<TabManagerBloc>()
                                                      .add(
                                                        ReorderTab(
                                                          fromIndex: fromIndex,
                                                          toIndex: toIndex,
                                                        ),
                                                      );
                                                }
                                              : null,
                                          onNativeTabDragRequested:
                                              Platform.isWindows
                                                  ? _handleNativeTabDrag
                                                  : null,
                                          onTabDragStarted: (_isDesktop &&
                                                  !Platform.isWindows)
                                              ? (d) => unawaited(
                                                    _showWindowDropOverlay(
                                                        context, d),
                                                  )
                                              : null,
                                          onTabDragEnded: (!Platform.isWindows)
                                              ? _removeWindowDropOverlay
                                              : null,
                                          onTabContextMenu: (index, pos) {
                                            if (index < state.tabs.length) {
                                              unawaited(
                                                  _showDesktopTabContextMenu(
                                                context: context,
                                                tab: state.tabs[index],
                                                globalPosition: pos,
                                              ));
                                            }
                                          },
                                          // Add tab close callback
                                          onTabClose: (index) {
                                            if (index < state.tabs.length) {
                                              context
                                                  .read<TabManagerBloc>()
                                                  .add(CloseTab(
                                                      state.tabs[index].id));
                                            }
                                          },
                                          // Keep the add tab button functionality
                                          onAddTabPressed: _handleAddNewTab,
                                          tabs: [
                                            // Generate modern-style tabs from state.tabs
                                            ...state.tabs.map((tab) {
                                              return Tab(
                                                height: 38,
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(horizontal: 4),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (tab.isLoading) ...[
                                                        const SizedBox(
                                                          width: 14,
                                                          height: 14,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 6),
                                                      ],
                                                      Icon(
                                                        tab.isPinned
                                                            ? PhosphorIconsLight
                                                                .pushPin
                                                            : tab.icon ??
                                                                PhosphorIconsLight
                                                                    .folder,
                                                        size: 16,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Flexible(
                                                        child: Text(
                                                          tab.name,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ],
                                        ),
                                      ),
                                    ),
                                    actions: [
                                      // Modern menu button
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8.0),
                                        child: IconButton(
                                          icon: Icon(
                                            PhosphorIconsLight.dotsThree,
                                            color: theme.colorScheme.primary,
                                            size: 22,
                                          ),
                                          style: IconButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16.0),
                                            ),
                                            backgroundColor: isDarkMode
                                                ? theme.colorScheme.primary
                                                    .withValues(alpha: 0.06)
                                                : theme.colorScheme.primary
                                                    .withValues(alpha: 0.07),
                                          ),
                                          onPressed: () =>
                                              _showTabOptions(context),
                                        ),
                                      ),
                                    ],
                                  )
                                : null, // No AppBar for mobile interface
                            drawer: !_isDrawerPinned
                                ? CBDrawer(
                                    context,
                                    activeTabId: state.activeTabId,
                                    isPinned: _isDrawerPinned,
                                    onPinStateChanged: (isPinned) {
                                      _toggleDrawerPin();
                                    },
                                  )
                                : null,
                            body: Row(
                              key: const ValueKey<String>(
                                  'tab-screen-content-block'),
                              children: [
                                // Pinned drawer (if enabled)
                                if (_isDrawerPinned)
                                  SizedBox(
                                    width: 280,
                                    child: CBDrawer(
                                      context,
                                      activeTabId: state.activeTabId,
                                      isPinned: _isDrawerPinned,
                                      onPinStateChanged: (isPinned) {
                                        _toggleDrawerPin();
                                      },
                                    ),
                                  ),
                                // Main content area with subtle container styling
                                Expanded(
                                  child:
                                      _buildContent(context, state, isTablet),
                                ),
                              ],
                            ),
                            floatingActionButton: state.tabs.isEmpty
                                ? FloatingActionButton(
                                    heroTag:
                                        null, // Disable hero animation to avoid conflicts
                                    onPressed: _handleAddNewTab,
                                    tooltip: context.tr.newFolder,
                                    elevation: 0,
                                    backgroundColor: theme.colorScheme.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      PhosphorIconsLight.plus,
                                      size: 24,
                                    ),
                                  )
                                : null,
                          ), // Scaffold
                        ), // Listener
                      ); // PopScope
                    }, // builder function
                  ), // Builder
                ), // FocusScope
              ), // Actions
            ); // Shortcuts
          }, // BlocBuilder builder function
        ), // BlocBuilder
      ), // BlocListener
    ); // BlocProvider
  }

  // Phương thức mới để xây dựng nội dung dựa trên loại thiết bị
  Widget _buildContent(
      BuildContext context, TabManagerState state, bool isTablet) {
    // Giao diện cho tablet sử dụng UI hiện tại
    if (isTablet) {
      if (state.tabs.isEmpty) {
        return const HomeScreen(
          tabId: 'home', // Use a special ID for home screen
        );
      }
      return _buildTabContent(state);
    }
    // Giao diện cho mobile luôn sử dụng kiểu Chrome, ngay cả khi không có tab
    else {
      // On mobile, ensure we always have a home tab for navigation history
      if (state.tabs.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final tabBloc = context.read<TabManagerBloc>();
            if (tabBloc.state.tabs.isEmpty) {
              tabBloc.add(AddTab(
                path: '#home',
                name: 'Home',
                switchToTab: true,
              ));
            }
          }
        });
      }
      return MobileTabView(
        onAddNewTab: _handleAddNewTab,
      );
    }
  }

  // ...existing code...

  void _syncTabContentCache(List<TabData> tabs) {
    final currentIds = tabs.map((tab) => tab.id).toSet();
    _tabContentCache.removeWhere((id, _) => !currentIds.contains(id));
  }

  Widget _buildOrGetTabContent(TabData tab) {
    final cached = _tabContentCache[tab.id];
    if (cached != null &&
        cached.path == tab.path &&
        cached.splitPanePath == tab.splitPanePath) {
      return cached.widget;
    }

    final widget = _createTabContent(tab);
    _tabContentCache[tab.id] = _CachedTabContent(
        path: tab.path, splitPanePath: tab.splitPanePath, widget: widget);
    return widget;
  }

  Widget _createTabContent(TabData tab) {
    final Widget content;
    if (tab.path.startsWith('#') && !isDrivesPath(tab.path)) {
      content = SystemScreenRouter.routeSystemPath(context, tab.path, tab.id) ??
          Container();
    } else if (tab.splitPanePath != null) {
      // Split-pane mode: render two panes side-by-side.
      content = SplitPaneView(
        key: ValueKey('${tab.id}_split'),
        tabId: tab.id,
        leftPath: tab.path,
        rightPath: tab.splitPanePath!,
      );
    } else {
      content = TabbedFolderListScreen(
        key: ValueKey(tab.id),
        path: tab.path,
        tabId: tab.id,
      );
    }

    return KeyedSubtree(
      key: ValueKey(tab.id),
      child: RepaintBoundary(
        key: tab.repaintBoundaryKey,
        child: content,
      ),
    );
  }

  Widget _buildTabContent(TabManagerState state) {
    if (state.tabs.isEmpty) return Container();

    final activeTabId = state.activeTabId;
    final activeIndex = activeTabId == null
        ? 0
        : state.tabs.indexWhere((tab) => tab.id == activeTabId);

    final safeActiveIndex =
        activeIndex >= 0 && activeIndex < state.tabs.length ? activeIndex : 0;

    _syncTabContentCache(state.tabs);
    final children = state.tabs.map(_buildOrGetTabContent).toList();

    return IndexedStack(
      index: safeActiveIndex,
      children: children,
    );
  }

  void _handleAddNewTab() {
    // Always create new tab with home page
    if (mounted) {
      context
          .read<TabManagerBloc>()
          .add(AddTab(path: '#home', name: context.tr.homeTab));
    }
  }

  /// Toggles split-pane view for the currently active tab.
  /// If the tab is already split, closes the split. Otherwise opens the right
  /// pane with the same path as the left pane.
  void _handleToggleSplitView() {
    if (!_isDesktop || !mounted) return;
    final bloc = context.read<TabManagerBloc>();
    final activeTab = bloc.state.activeTab;
    if (activeTab == null) return;

    if (activeTab.splitPanePath != null) {
      bloc.add(CloseSplitPane(tabId: activeTab.id));
    } else {
      bloc.add(OpenSplitPane(tabId: activeTab.id, path: activeTab.path));
    }
  }

  WindowTabPayload _toWindowTabPayload(TabData tab) {
    return WindowTabPayload(
      path: tab.path,
      name: tab.name,
      highlightedFileName: tab.highlightedFileName,
    );
  }

  _ResolvedTabMoveSelection _resolveTabMoveSelection(String triggerTabId) {
    final bloc = context.read<TabManagerBloc>();
    final state = bloc.state;
    final selected = state.selectedTabIds;
    final useSelection = selected.isNotEmpty && selected.contains(triggerTabId);
    final requestedIds = useSelection ? selected : <String>{triggerTabId};

    final tabs = state.tabs
        .where((tab) => requestedIds.contains(tab.id))
        .toList(growable: false);

    if (tabs.isEmpty) {
      return _ResolvedTabMoveSelection(
        tabIds: <String>[triggerTabId],
        payloads: <WindowTabPayload>[],
      );
    }

    return _ResolvedTabMoveSelection(
      tabIds: tabs.map((tab) => tab.id).toList(growable: false),
      payloads: tabs.map(_toWindowTabPayload).toList(growable: false),
    );
  }

  void _removeWindowDropOverlay() {
    _windowDropOverlayEntry?.remove();
    _windowDropOverlayEntry = null;
  }

  Future<void> _showWindowDropOverlay(
    BuildContext context,
    DesktopTabDragData dragged,
  ) async {
    if (!_isDesktop) return;

    _removeWindowDropOverlay();

    final svc = locator<DesktopWindowingService>();
    final others = await svc.listOtherWindows();
    if (!mounted) return;
    final moveSelection = _resolveTabMoveSelection(dragged.tabId);
    final moveCount = moveSelection.tabIds.length;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _windowDropOverlayEntry = OverlayEntry(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDarkMode = theme.brightness == Brightness.dark;
        final bg = isDarkMode
            ? Colors.black.withAlpha((0.72 * 255).round())
            : Colors.white.withAlpha((0.94 * 255).round());

        Widget buildTarget({
          required Widget child,
          required Future<void> Function(DesktopTabDragData) onAccept,
        }) {
          return DragTarget<DesktopTabDragData>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) async {
              _removeWindowDropOverlay();
              await onAccept(details.data);
            },
            builder: (context, candidateData, rejectedData) {
              final hovered = candidateData.isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: hovered
                      ? theme.colorScheme.primary
                          .withAlpha((0.12 * 255).round())
                      : (isDarkMode
                          ? Colors.white.withAlpha((0.06 * 255).round())
                          : Colors.black.withAlpha((0.04 * 255).round())),
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: child,
              );
            },
          );
        }

        return Positioned.fill(
          child: Material(
            color: Colors.black.withAlpha((0.05 * 255).round()),
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 56),
                width: 520,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      ctx.tr.moveTabToWindow,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (dragged.tab.name ?? dragged.tab.path).trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 10),
                    buildTarget(
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsLight.arrowSquareOut,
                              size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              moveCount > 1
                                  ? '${ctx.tr.moveTabToNewWindow} ($moveCount)'
                                  : ctx.tr.moveTabToNewWindow,
                            ),
                          ),
                        ],
                      ),
                      onAccept: (d) async {
                        final tabs = moveSelection.payloads.isNotEmpty
                            ? moveSelection.payloads
                            : <WindowTabPayload>[d.tab];
                        final ok = await svc.openNewWindow(tabs: tabs);
                        if (!mounted) return;
                        if (ok) {
                          final bloc = context.read<TabManagerBloc>();
                          for (final id in moveSelection.tabIds) {
                            bloc.add(CloseTab(id));
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    if (others.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          ctx.tr.noOtherWindows,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.75),
                          ),
                        ),
                      )
                    else
                      ...others.map((w) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: buildTarget(
                            child: Row(
                              children: [
                                const Icon(PhosphorIconsLight.appWindow,
                                    size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    w.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${w.tabCount}',
                                  style: theme.textTheme.labelMedium,
                                ),
                              ],
                            ),
                            onAccept: (d) async {
                              final tabs = moveSelection.payloads.isNotEmpty
                                  ? moveSelection.payloads
                                  : <WindowTabPayload>[d.tab];
                              final ok = await svc.sendTabsToWindow(w, tabs);
                              if (!mounted) return;
                              if (ok) {
                                final bloc = context.read<TabManagerBloc>();
                                for (final id in moveSelection.tabIds) {
                                  bloc.add(CloseTab(id));
                                }
                              }
                            },
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _removeWindowDropOverlay,
                      child: Text(ctx.tr.cancel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_windowDropOverlayEntry!);
  }

  Future<void> _handleNativeTabDrag(DesktopTabDragData data) async {
    if (!Platform.isWindows) return;

    final moveSelection = _resolveTabMoveSelection(data.tabId);
    final payloads = moveSelection.payloads;

    final result = await WindowsNativeTabDragDropService.startDrag(
      tabs: payloads.isNotEmpty ? payloads : <WindowTabPayload>[data.tab],
    );
    if (!mounted) return;

    if (result == WindowsNativeTabDragResult.moved) {
      final bloc = context.read<TabManagerBloc>();
      for (final id in moveSelection.tabIds) {
        bloc.add(CloseTab(id));
      }
    }
  }

  Future<DesktopWindowInfo?> _pickTargetWindow(BuildContext context) async {
    final svc = locator<DesktopWindowingService>();
    final others = await svc.listOtherWindows();
    if (!mounted) return null;

    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr.noOtherWindows)),
      );
      return null;
    }

    return showDialog<DesktopWindowInfo>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.tr.selectWindow),
          content: SizedBox(
            width: 420,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: others.length,
              itemBuilder: (context, index) {
                final w = others[index];
                final subtitle =
                    '${context.tr.openTabs}: ${w.tabCount} • ${w.windowId.substring(0, 8)}';
                return ListTile(
                  title: Text(w.title),
                  subtitle: Text(subtitle),
                  onTap: () => Navigator.of(ctx).pop(w),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(context.tr.cancel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _mergeWindowIntoThis(BuildContext context) async {
    final svc = locator<DesktopWindowingService>();
    final target = await _pickTargetWindow(context);
    if (target == null || !mounted) return;

    final incomingTabs = await svc.requestTabsFromWindow(target);
    if (!mounted) return;

    if (incomingTabs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr.noTabsOpen)),
      );
      return;
    }

    final bloc = context.read<TabManagerBloc>();
    for (int i = 0; i < incomingTabs.length; i++) {
      final t = incomingTabs[i];
      bloc.add(AddTab(
        path: t.path,
        name: t.name,
        switchToTab: i == incomingTabs.length - 1,
        highlightedFileName: t.highlightedFileName,
      ));
    }

    await svc.requestCloseWindow(target);
  }

  Future<void> _showDesktopTabContextMenu({
    required BuildContext context,
    required TabData tab,
    required Offset globalPosition,
  }) async {
    if (!_isDesktop) return;

    final moveSelection = _resolveTabMoveSelection(tab.id);
    final selectionCount = moveSelection.tabIds.length;

    final moveToNewWindowLabel = selectionCount > 1
        ? '${context.tr.moveTabToNewWindow} ($selectionCount)'
        : context.tr.moveTabToNewWindow;
    final moveToWindowLabel = selectionCount > 1
        ? '${context.tr.moveTabToWindow} ($selectionCount)'
        : context.tr.moveTabToWindow;
    final closeTabLabel = selectionCount > 1
        ? '${context.tr.closeTab} ($selectionCount)'
        : context.tr.closeTab;

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final size = overlay?.size ?? const Size(1, 1);
    final pos = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      size.width - globalPosition.dx,
      size.height - globalPosition.dy,
    );

    final action = await showMenu<_DesktopTabAction>(
      context: context,
      position: pos,
      items: [
        PopupMenuItem(
          value: _DesktopTabAction.moveToNewWindow,
          child: Text(moveToNewWindowLabel),
        ),
        PopupMenuItem(
          value: _DesktopTabAction.moveToWindow,
          child: Text(moveToWindowLabel),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _DesktopTabAction.closeTab,
          child: Text(closeTabLabel),
        ),
      ],
    );

    if (action == null || !mounted) return;

    final bloc = context.read<TabManagerBloc>();
    final svc = locator<DesktopWindowingService>();
    final payloads = moveSelection.payloads.isNotEmpty
        ? moveSelection.payloads
        : <WindowTabPayload>[_toWindowTabPayload(tab)];
    final tabIdsToMove = moveSelection.tabIds.isNotEmpty
        ? moveSelection.tabIds
        : <String>[tab.id];

    switch (action) {
      case _DesktopTabAction.moveToNewWindow:
        {
          final ok = await svc.openNewWindow(tabs: payloads);
          if (!mounted) return;
          if (ok) {
            for (final id in tabIdsToMove) {
              bloc.add(CloseTab(id));
            }
          }
          return;
        }
      case _DesktopTabAction.moveToWindow:
        {
          final target = await _pickTargetWindow(context);
          if (target == null || !mounted) return;

          final ok = await svc.sendTabsToWindow(target, payloads);
          if (!mounted) return;
          if (ok) {
            for (final id in tabIdsToMove) {
              bloc.add(CloseTab(id));
            }
          }
          return;
        }
      case _DesktopTabAction.closeTab:
        for (final id in tabIdsToMove) {
          bloc.add(CloseTab(id));
        }
        return;
    }
  }

  /// Helper method to create fallback tab
  void _createFallbackTab() {
    if (mounted) {
      try {
        context
            .read<TabManagerBloc>()
            .add(AddTab(path: '#home', name: context.tr.homeTab));
      } catch (e) {
        debugPrint("Failed to create fallback tab: $e");
      }
    }
  }

  /// Helper method to get display name for storage path
  String _getStorageDisplayName(String path) {
    if (path.isEmpty || isDrivesPath(path)) return 'Drives';

    // For Android, try to extract meaningful name
    if (Platform.isAndroid) {
      if (path.contains('/storage/emulated/0')) {
        return 'Internal Storage';
      } else if (path.contains('/storage/')) {
        // Extract UUID or storage identifier
        final parts = path.split('/');
        if (parts.length >= 3) {
          final storageId = parts[2];
          if (storageId.isNotEmpty && storageId != 'emulated') {
            return 'Storage $storageId';
          }
        }
      }
    }

    // For iOS or other cases, use the last part of the path
    final parts = path.split('/');
    final lastPart =
        parts.lastWhere((part) => part.isNotEmpty, orElse: () => '');
    return lastPart.isEmpty ? 'Root' : lastPart;
  }

  void _showTabOptions(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final backgroundColor =
        isDarkMode ? theme.colorScheme.surface : theme.colorScheme.surface;
    final textColor = isDarkMode
        ? theme.textTheme.bodyMedium?.color
        : theme.textTheme.bodyMedium?.color;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
        backgroundColor: backgroundColor,
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dialog title
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
                child: Row(
                  children: [
                    Text(
                      context.tr.tabManager,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        PhosphorIconsLight.x,
                        size: 20,
                        color: textColor?.withValues(alpha: 0.7),
                      ),
                      onPressed: () => RouteUtils.safePopDialog(context),
                      iconSize: 20,
                      style: IconButton.styleFrom(
                        backgroundColor: isDarkMode
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Option items
              _buildOptionItem(
                context,
                icon: PhosphorIconsLight.plusCircle,
                text: context.tr.addNewTab,
                onTap: () {
                  RouteUtils.safePopDialog(context);
                  _handleAddNewTab();
                },
              ),
              _buildOptionItem(
                context,
                icon: PhosphorIconsLight.x,
                text: context.tr.closeTab,
                onTap: () {
                  RouteUtils.safePopDialog(context);
                  _handleCloseCurrentTab();
                },
              ),
              // Removed SMB Network and Network browsing entries.
              // Add 'Close all tabs' option
              _buildOptionItem(
                context,
                icon: PhosphorIconsLight.xCircle,
                text: context.tr.closeAllTabs,
                onTap: () {
                  RouteUtils.safePopDialog(context);
                  _handleCloseAllTabs();
                },
              ),
              if (_isDesktop)
                _buildOptionItem(
                  context,
                  icon: PhosphorIconsLight.appWindow,
                  text: context.tr.newWindow,
                  onTap: () async {
                    RouteUtils.safePopDialog(context);
                    await locator<DesktopWindowingService>().openNewWindow();
                  },
                ),
              if (_isDesktop)
                _buildOptionItem(
                  context,
                  icon: PhosphorIconsLight.gitMerge,
                  text: context.tr.mergeWindowIntoThis,
                  onTap: () async {
                    RouteUtils.safePopDialog(context);
                    await _mergeWindowIntoThis(context);
                  },
                ),
              _buildOptionItem(
                context,
                icon: PhosphorIconsLight.gear,
                text: context.tr.settings,
                onTap: () {
                  RouteUtils.safePopDialog(context);
                  final tabBloc = BlocProvider.of<TabManagerBloc>(context);
                  final existingTab = tabBloc.state.tabs.firstWhere(
                    (tab) => tab.path == kSettingsPath,
                    orElse: () => TabData(id: '', name: '', path: ''),
                  );
                  if (existingTab.id.isNotEmpty) {
                    tabBloc.add(SwitchToTab(existingTab.id));
                  } else {
                    tabBloc.add(AddTab(
                      path: kSettingsPath,
                      name: context.tr.settings,
                      switchToTab: true,
                    ));
                  }
                },
              ),
              // Native Streaming Test removed - using flutter_vlc_player now
            ],
          ),
        ),
      ),
    );
  }

  // Close all open tabs
  void _handleCloseAllTabs() {
    try {
      final state = context.read<TabManagerBloc>().state;
      final tabs = List.of(state.tabs);
      for (final tab in tabs) {
        context.read<TabManagerBloc>().add(CloseTab(tab.id));
      }
    } catch (e) {
      debugPrint('Error closing all tabs: $e');
    }
  }

  // Helper method to build menu options
  Widget _buildOptionItem(
    BuildContext context, {
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDarkMode
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : theme.colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Icon(
                icon,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ...existing code...
}

enum _DesktopTabAction {
  moveToNewWindow,
  moveToWindow,
  closeTab,
}

class _CachedTabContent {
  final String path;
  final String? splitPanePath;
  final Widget widget;

  const _CachedTabContent({
    required this.path,
    required this.widget,
    this.splitPanePath,
  });
}

class _ResolvedTabMoveSelection {
  final List<String> tabIds;
  final List<WindowTabPayload> payloads;

  const _ResolvedTabMoveSelection({
    required this.tabIds,
    required this.payloads,
  });
}
