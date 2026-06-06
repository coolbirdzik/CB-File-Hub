import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:math';
import 'tab_data.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/media/photo_thumbnail_helper.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/tab_activity/tab_activity_manager.dart';

/// Events for the TabManager
abstract class TabEvent {}

/// Event to add a new tab
class AddTab extends TabEvent {
  final String path;
  final String? name;
  final bool switchToTab;
  final String?
      highlightedFileName; // File to highlight/focus after opening tab

  AddTab({
    required this.path,
    this.name,
    this.switchToTab = true,
    this.highlightedFileName,
  });
}

/// Event to switch to a tab
class SwitchToTab extends TabEvent {
  final String tabId;

  SwitchToTab(this.tabId);
}

/// Event to close a tab
class CloseTab extends TabEvent {
  final String tabId;

  CloseTab(this.tabId);
}

/// Event to update a tab's path
class UpdateTabPath extends TabEvent {
  final String tabId;
  final String newPath;

  UpdateTabPath(this.tabId, this.newPath);
}

/// Event to update a tab's name
class UpdateTabName extends TabEvent {
  final String tabId;
  final String newName;

  UpdateTabName(this.tabId, this.newName);
}

/// Event to toggle a tab's pinned status
class ToggleTabPin extends TabEvent {
  final String tabId;

  ToggleTabPin(this.tabId);
}

/// Event to update a tab's loading state
class UpdateTabLoading extends TabEvent {
  final String tabId;
  final bool isLoading;

  UpdateTabLoading(this.tabId, this.isLoading);
}

/// Event to add a path to tab navigation history
class AddToTabHistory extends TabEvent {
  final String tabId;
  final String path;

  AddToTabHistory(this.tabId, this.path);
}

/// Event to close all tabs
class CloseAllTabs extends TabEvent {}

/// Event to close every tab except [keepTabId].
class CloseOtherTabs extends TabEvent {
  final String keepTabId;

  CloseOtherTabs(this.keepTabId);
}

/// Event to update tab thumbnail
class UpdateTabThumbnail extends TabEvent {
  final String tabId;
  final Uint8List thumbnail;

  UpdateTabThumbnail(this.tabId, this.thumbnail);
}

/// Event to reorder tab positions
class ReorderTab extends TabEvent {
  final int fromIndex;
  final int toIndex;

  ReorderTab({
    required this.fromIndex,
    required this.toIndex,
  });
}

/// Event to clear any multi-tab selection.
class ClearTabSelection extends TabEvent {}

/// Event to toggle a tab's selection state (desktop-only UX).
class ToggleTabSelection extends TabEvent {
  final String tabId;

  ToggleTabSelection(this.tabId);
}

/// Event to open the right-hand pane of a split view inside a tab.
class OpenSplitPane extends TabEvent {
  final String tabId;
  final String path;

  OpenSplitPane({required this.tabId, required this.path});
}

/// Event to close the right-hand pane of a split view inside a tab.
class CloseSplitPane extends TabEvent {
  final String tabId;

  CloseSplitPane({required this.tabId});
}

/// State for the TabManager
class TabManagerState {
  final List<TabData> tabs;
  final String? activeTabId;
  final Set<String> selectedTabIds;

  TabManagerState({
    required this.tabs,
    this.activeTabId,
    Set<String>? selectedTabIds,
  }) : selectedTabIds = selectedTabIds ?? <String>{};

  TabData? get activeTab => activeTabId != null
      ? tabs.firstWhere((tab) => tab.id == activeTabId,
          orElse: () => tabs.first)
      : (tabs.isNotEmpty ? tabs.first : null);

  TabManagerState copyWith({
    List<TabData>? tabs,
    String? activeTabId,
    bool clearActiveTabId = false,
    Set<String>? selectedTabIds,
    bool clearSelectedTabIds = false,
  }) {
    return TabManagerState(
      tabs: tabs ?? this.tabs,
      activeTabId: clearActiveTabId ? null : (activeTabId ?? this.activeTabId),
      selectedTabIds: clearSelectedTabIds
          ? <String>{}
          : (selectedTabIds ?? this.selectedTabIds),
    );
  }
}

/// Helper class used to resolve a split-pane tabId to its parent and nested tab.
class _SplitTabResolution {
  final TabData parent;
  final TabData splitTab;
  final int parentIndex;

  const _SplitTabResolution({
    required this.parent,
    required this.splitTab,
    required this.parentIndex,
  });
}

/// BLoC for managing tabs
class TabManagerBloc extends Bloc<TabEvent, TabManagerState> {
  /// Resolves the activity manager lazily so this bloc can be unit-tested
  /// without a registered service locator.
  TabActivityManager? get _activity {
    if (!locator.isRegistered<TabActivityManager>()) return null;
    try {
      return locator<TabActivityManager>();
    } catch (_) {
      return null;
    }
  }

  TabManagerBloc() : super(TabManagerState(tabs: [])) {
    on<AddTab>(_onAddTab);
    on<SwitchToTab>(_onSwitchToTab);
    on<CloseTab>(_onCloseTab);
    on<CloseAllTabs>(_onCloseAllTabs);
    on<CloseOtherTabs>(_onCloseOtherTabs);
    on<UpdateTabPath>(_onUpdateTabPath);
    on<UpdateTabName>(_onUpdateTabName);
    on<ToggleTabPin>(_onToggleTabPin);
    on<UpdateTabLoading>(_onUpdateTabLoading);
    on<AddToTabHistory>(_onAddToTabHistory);
    on<UpdateTabThumbnail>(_onUpdateTabThumbnail);
    on<ReorderTab>(_onReorderTab);
    on<ClearTabSelection>(_onClearTabSelection);
    on<ToggleTabSelection>(_onToggleTabSelection);
    on<OpenSplitPane>(_onOpenSplitPane);
    on<CloseSplitPane>(_onCloseSplitPane);
  }

  void _onAddTab(AddTab event, Emitter<TabManagerState> emit) {
    final random = Random();
    final newTabId =
        'tab_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(10000)}';

    debugPrint(
        'TabManagerBloc._onAddTab: path=${event.path}, highlightedFileName=${event.highlightedFileName}');
    final newTab = TabData(
      id: newTabId,
      name: event.name ?? _extractNameFromPath(event.path),
      path: event.path,
      isLoading: false,
      highlightedFileName: event.highlightedFileName,
    );

    final tabs = List<TabData>.from(state.tabs)..add(newTab);

    // Track newly opened tab in the activity manager. If the user is
    // switching to it, mark it as focused; otherwise it starts as background.
    final activity = _activity;
    if (activity != null) {
      if (event.switchToTab) {
        activity.onTabFocused(newTabId, path: event.path);
      } else {
        activity.onTabInteraction(newTabId, path: event.path);
      }
    }

    emit(state.copyWith(
      tabs: tabs,
      activeTabId: event.switchToTab ? newTabId : state.activeTabId,
      // When a new tab becomes active (e.g., Ctrl+N), clear multi-selection.
      selectedTabIds: event.switchToTab ? <String>{} : state.selectedTabIds,
    ));
  }

  void _onSwitchToTab(SwitchToTab event, Emitter<TabManagerState> emit) {
    if (state.tabs.any((tab) => tab.id == event.tabId)) {
      final activity = _activity;
      if (activity != null) {
        final tab = state.tabs.firstWhere((t) => t.id == event.tabId);
        activity.onTabFocused(event.tabId, path: tab.path);
      }
      emit(state.copyWith(activeTabId: event.tabId));
    }
  }

  void _onCloseTab(CloseTab event, Emitter<TabManagerState> emit) {
    if (state.tabs.isEmpty) return;

    // Evict photo thumbnails for the tab's path from the short-term memory
    // cache so they don't linger after the user closes the tab.
    final closingTab = state.tabs
        .firstWhere((t) => t.id == event.tabId, orElse: () => state.tabs.first);
    if (closingTab.id == event.tabId) {
      // Fire-and-forget: non-critical cache maintenance.
      PhotoThumbnailHelper.evictForPaths([closingTab.path]);
    }

    final tabs = state.tabs.where((tab) => tab.id != event.tabId).toList();
    final selected =
        state.selectedTabIds.where((id) => id != event.tabId).toSet();

    // Notify activity manager that this tab was closed so it can release
    // any per-tab tracking and downstream caches.
    _activity?.onTabClosed(event.tabId);

    // If we're closing the active tab, switch to another tab
    String? newActiveTabId;
    if (state.activeTabId == event.tabId) {
      final closedTabIndex =
          state.tabs.indexWhere((tab) => tab.id == event.tabId);
      if (closedTabIndex >= 0 && tabs.isNotEmpty) {
        // Try to select the tab to the right, or if that's not possible, to the left
        final newSelectedIndex = min(closedTabIndex, tabs.length - 1);
        newActiveTabId = tabs[newSelectedIndex].id;
      } else {
        newActiveTabId = null;
      }
    } else {
      newActiveTabId = state.activeTabId;
    }

    emit(state.copyWith(
      tabs: tabs,
      activeTabId: newActiveTabId,
      clearActiveTabId: newActiveTabId == null,
      selectedTabIds: selected,
    ));
  }

  void _onCloseAllTabs(CloseAllTabs event, Emitter<TabManagerState> emit) {
    final activity = _activity;
    if (activity != null) {
      for (final tab in state.tabs) {
        activity.onTabClosed(tab.id);
      }
    }
    emit(state.copyWith(
      tabs: [],
      activeTabId: null,
      clearActiveTabId: true,
      clearSelectedTabIds: true,
    ));
  }

  void _onCloseOtherTabs(CloseOtherTabs event, Emitter<TabManagerState> emit) {
    if (state.tabs.isEmpty) return;
    if (!state.tabs.any((t) => t.id == event.keepTabId)) return;

    final activity = _activity;
    final closing =
        state.tabs.where((tab) => tab.id != event.keepTabId).toList();
    if (closing.isEmpty) return;

    if (activity != null) {
      for (final tab in closing) {
        activity.onTabClosed(tab.id);
      }
    }

    final keep = state.tabs.firstWhere((t) => t.id == event.keepTabId);
    emit(state.copyWith(
      tabs: <TabData>[keep],
      activeTabId: keep.id,
      clearSelectedTabIds: true,
    ));
  }

  void _onClearTabSelection(
      ClearTabSelection event, Emitter<TabManagerState> emit) {
    if (state.selectedTabIds.isEmpty) return;
    emit(state.copyWith(clearSelectedTabIds: true));
  }

  void _onToggleTabSelection(
      ToggleTabSelection event, Emitter<TabManagerState> emit) {
    if (!state.tabs.any((t) => t.id == event.tabId)) return;

    final selected = Set<String>.from(state.selectedTabIds);
    if (selected.contains(event.tabId)) {
      selected.remove(event.tabId);
    } else {
      selected.add(event.tabId);
    }
    emit(state.copyWith(selectedTabIds: selected));
  }

  void _onOpenSplitPane(OpenSplitPane event, Emitter<TabManagerState> emit) {
    final tabs = state.tabs.map((tab) {
      if (tab.id == event.tabId) {
        final splitId = '${event.tabId}_split';
        final splitTab = TabData(
          id: splitId,
          name: '',
          path: event.path,
        );
        return tab.copyWith(
          splitPanePath: event.path,
          splitPaneTabData: splitTab,
        );
      }
      return tab;
    }).toList();
    emit(state.copyWith(tabs: tabs));
  }

  void _onCloseSplitPane(CloseSplitPane event, Emitter<TabManagerState> emit) {
    final tabs = state.tabs.map((tab) {
      if (tab.id == event.tabId) {
        return tab.copyWith(clearSplitPane: true);
      }
      return tab;
    }).toList();
    emit(state.copyWith(tabs: tabs));
  }

  // ---------------------------------------------------------------------------
  // Split-pane routing helpers
  // ---------------------------------------------------------------------------

  /// If [tabId] ends with `_split`, returns the parent tab and the nested
  /// [splitPaneTabData]. Otherwise returns null.
  _SplitTabResolution? _resolveSplitTab(String tabId) {
    if (!tabId.endsWith('_split')) return null;
    final parentId = tabId.substring(0, tabId.length - '_split'.length);
    final idx = state.tabs.indexWhere((t) => t.id == parentId);
    if (idx == -1) return null;
    final parent = state.tabs[idx];
    final splitTab = parent.splitPaneTabData;
    if (splitTab == null) return null;
    return _SplitTabResolution(
        parent: parent, splitTab: splitTab, parentIndex: idx);
  }

  /// Update the nested [splitPaneTabData] on [parent] and emit new state.
  void _emitWithUpdatedSplitTab(
    Emitter<TabManagerState> emit,
    int parentIndex,
    TabData updatedSplitTab,
  ) {
    final tabs = List<TabData>.from(state.tabs);
    tabs[parentIndex] = tabs[parentIndex].copyWith(
      splitPanePath: updatedSplitTab.path,
      splitPaneTabData: updatedSplitTab,
    );
    emit(state.copyWith(tabs: tabs));
  }

  void _onUpdateTabPath(UpdateTabPath event, Emitter<TabManagerState> emit) {
    debugPrint(
        'BLOC_DEBUG: _onUpdateTabPath called for tab ${event.tabId}, newPath: ${event.newPath}');

    // Route to nested split-pane tab if applicable.
    final split = _resolveSplitTab(event.tabId);
    if (split != null) {
      final st = split.splitTab;
      if (st.path == event.newPath) return;
      st.updatePath(event.newPath);
      _emitWithUpdatedSplitTab(
          emit, split.parentIndex, st.copyWith(path: event.newPath));
      return;
    }

    // Check if the path is actually changing
    final currentTab = state.tabs.firstWhere(
      (tab) => tab.id == event.tabId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );

    debugPrint('BLOC_DEBUG: Current tab path: ${currentTab.path}');

    // If the path is the same as the current path, don't update
    if (currentTab.path == event.newPath) {
      debugPrint('BLOC_DEBUG: Path unchanged, skipping update');
      return;
    }

    final tabs = state.tabs.map((tab) {
      if (tab.id == event.tabId) {
        debugPrint(
            'BLOC_DEBUG: Before updatePath - history: ${tab.navigationHistory}');
        debugPrint('BLOC_DEBUG: Before updatePath - current path: ${tab.path}');

        // First add the new path to the navigation history of the existing tab
        tab.updatePath(event.newPath);

        debugPrint(
            'BLOC_DEBUG: After updatePath - history: ${tab.navigationHistory}');

        // Then create a new tab instance with the updated path
        final updatedTab = tab.copyWith(path: event.newPath);
        debugPrint(
            'BLOC_DEBUG: After copyWith - new tab history: ${updatedTab.navigationHistory}');
        return updatedTab;
      }
      return tab;
    }).toList();

    debugPrint('BLOC_DEBUG: Emitting new state with updated tab path');
    // Path navigation counts as interaction; keep activity manager in sync.
    _activity?.onTabInteraction(event.tabId, path: event.newPath);
    emit(state.copyWith(tabs: tabs));
  }

  void _onUpdateTabName(UpdateTabName event, Emitter<TabManagerState> emit) {
    // Split-pane tab names are not shown in the tab bar — silently ignore.
    if (_resolveSplitTab(event.tabId) != null) return;

    final tabs = state.tabs.map((tab) {
      if (tab.id == event.tabId) {
        return tab.copyWith(name: event.newName);
      }
      return tab;
    }).toList();

    emit(state.copyWith(tabs: tabs));
  }

  void _onToggleTabPin(ToggleTabPin event, Emitter<TabManagerState> emit) {
    final tabs = state.tabs.map((tab) {
      if (tab.id == event.tabId) {
        return TabData(
          id: tab.id,
          name: tab.name,
          path: tab.path,
          icon: tab.icon,
          isPinned: !tab.isPinned,
          isLoading: tab.isLoading,
        );
      }
      return tab;
    }).toList();

    emit(state.copyWith(tabs: tabs));
  }

  void _onAddToTabHistory(
      AddToTabHistory event, Emitter<TabManagerState> emit) {
    // Route to nested split-pane tab if applicable.
    final split = _resolveSplitTab(event.tabId);
    if (split != null) {
      final st = split.splitTab;
      final List<String> updatedHistory = List.from(st.navigationHistory);
      if (event.path != st.path && !updatedHistory.contains(event.path)) {
        updatedHistory.add(event.path);
      }
      _emitWithUpdatedSplitTab(emit, split.parentIndex,
          st.copyWith(navigationHistory: updatedHistory));
      return;
    }

    final tabs = state.tabs.map((tab) {
      if (tab.id == event.tabId) {
        final List<String> updatedHistory = List.from(tab.navigationHistory);

        // Only add if path is different from current path AND not already in history
        if (event.path != tab.path && !updatedHistory.contains(event.path)) {
          updatedHistory.add(event.path);
          debugPrint('Added to navigation history: ${event.path}');
          debugPrint('Updated history: $updatedHistory');
        } else {
          debugPrint(
              'Skipped adding path: ${event.path} (current: ${tab.path}, already in history: ${updatedHistory.contains(event.path)})');
        }
        return tab.copyWith(navigationHistory: updatedHistory);
      }
      return tab;
    }).toList();

    emit(state.copyWith(tabs: tabs));
  }

  void _onUpdateTabLoading(
      UpdateTabLoading event, Emitter<TabManagerState> emit) {
    // Ignore loading state updates for the split pane — they don’t affect the tab bar.
    if (_resolveSplitTab(event.tabId) != null) return;

    final tabs = state.tabs.map((tab) {
      if (tab.id == event.tabId) {
        return tab.copyWith(isLoading: event.isLoading);
      }
      return tab;
    }).toList();

    emit(state.copyWith(tabs: tabs));
  }

  String _extractNameFromPath(String path) {
    final pathParts = path.split('/');
    return pathParts.isEmpty || pathParts.last.isEmpty
        ? 'Root'
        : pathParts.last;
  }

  // Add methods for navigation history management
  bool canTabNavigateBack(String tabId) {
    final split = _resolveSplitTab(tabId);
    if (split != null) return split.splitTab.navigationHistory.length > 1;

    final tab = state.tabs.firstWhere(
      (tab) => tab.id == tabId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );
    return tab.navigationHistory.length > 1;
  }

  String? getTabPreviousPath(String tabId) {
    final split = _resolveSplitTab(tabId);
    if (split != null) return split.splitTab.getPreviousPath();

    final tab = state.tabs.firstWhere(
      (tab) => tab.id == tabId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );
    return tab.getPreviousPath();
  }

  // Handle backwards navigation for a tab and return the new path
  String? backNavigationToPath(String tabId) {
    // Route to nested split-pane tab if applicable.
    final split = _resolveSplitTab(tabId);
    if (split != null) {
      final st = split.splitTab;
      final previousPath = st.navigateBack();
      if (previousPath != null) {
        final updatedSplitTab = st.copyWith(path: previousPath);
        final tabs = List<TabData>.from(state.tabs);
        tabs[split.parentIndex] = tabs[split.parentIndex].copyWith(
          splitPanePath: previousPath,
          splitPaneTabData: updatedSplitTab,
        );
        // ignore: invalid_use_of_visible_for_testing_member
        emit(state.copyWith(tabs: tabs));
        return previousPath;
      }
      return null;
    }

    // Find the tab with this ID
    final tabIndex = state.tabs.indexWhere((tab) => tab.id == tabId);
    if (tabIndex == -1) return null;

    // Get a mutable copy of the tabs
    final tabs = List<TabData>.from(state.tabs);
    final currentTab = tabs[tabIndex];

    debugPrint('TabManager: backNavigationToPath for tab: $tabId');
    debugPrint('TabManager: Current path: ${currentTab.path}');
    debugPrint(
        'TabManager: Navigation history before: ${currentTab.navigationHistory}');

    // Navigate back for this specific tab
    final previousPath = tabs[tabIndex].navigateBack();
    debugPrint('TabManager: navigateBack() returned: $previousPath');
    debugPrint(
        'TabManager: Navigation history after: ${tabs[tabIndex].navigationHistory}');

    if (previousPath != null) {
      // Update the tab with the new path (history already updated by navigateBack)
      tabs[tabIndex] = tabs[tabIndex].copyWith(path: previousPath);

      // Emit the new state directly (don't use UpdateTabPath as it would modify history again)
      // ignore: invalid_use_of_visible_for_testing_member
      emit(state.copyWith(tabs: tabs));

      debugPrint('TabManager: Successfully navigated back to: $previousPath');

      // Return the path we navigated to
      return previousPath;
    }

    debugPrint('TabManager: Cannot navigate back - previousPath is null');
    return null;
  }

  // Handle forwards navigation for a tab and return the new path
  String? forwardNavigationToPath(String tabId) {
    // Route to nested split-pane tab if applicable.
    final split = _resolveSplitTab(tabId);
    if (split != null) {
      final st = split.splitTab;
      final nextPath = st.navigateForward();
      if (nextPath != null) {
        final updatedSplitTab = st.copyWith(path: nextPath);
        final tabs = List<TabData>.from(state.tabs);
        tabs[split.parentIndex] = tabs[split.parentIndex].copyWith(
          splitPanePath: nextPath,
          splitPaneTabData: updatedSplitTab,
        );
        // ignore: invalid_use_of_visible_for_testing_member
        emit(state.copyWith(tabs: tabs));
        return nextPath;
      }
      return null;
    }

    // Find the tab with this ID
    final tabIndex = state.tabs.indexWhere((tab) => tab.id == tabId);
    if (tabIndex == -1) return null;

    // Get a mutable copy of the tabs
    final tabs = List<TabData>.from(state.tabs);

    // Navigate forward for this specific tab
    final nextPath = tabs[tabIndex].navigateForward();
    if (nextPath != null) {
      // Update the tab with the new path (history already updated by navigateForward)
      tabs[tabIndex] = tabs[tabIndex].copyWith(path: nextPath);

      // Emit the new state directly (don't use UpdateTabPath as it would modify history again)
      // ignore: invalid_use_of_visible_for_testing_member
      emit(state.copyWith(tabs: tabs));

      // Return the path we navigated to
      return nextPath;
    }

    return null;
  }

  // Get the full navigation history for a tab
  List<String> getTabHistory(String tabId) {
    final split = _resolveSplitTab(tabId);
    if (split != null) return List.from(split.splitTab.navigationHistory);

    final tab = state.tabs.firstWhere(
      (tab) => tab.id == tabId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );
    return List.from(tab.navigationHistory);
  }

  bool canTabNavigateForward(String tabId) {
    final split = _resolveSplitTab(tabId);
    if (split != null) return split.splitTab.forwardHistory.isNotEmpty;

    final tab = state.tabs.firstWhere(
      (tab) => tab.id == tabId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );
    return tab.forwardHistory.isNotEmpty;
  }

  String? getTabNextPath(String tabId) {
    final tab = state.tabs.firstWhere(
      (tab) => tab.id == tabId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );
    return tab.forwardHistory.isNotEmpty ? tab.forwardHistory.last : null;
  }

  void _onUpdateTabThumbnail(
      UpdateTabThumbnail event, Emitter<TabManagerState> emit) {
    final tabs = state.tabs.map((tab) {
      if (tab.id == event.tabId) {
        return tab.copyWith(
          thumbnail: event.thumbnail,
          thumbnailCapturedAt: DateTime.now(),
        );
      }
      return tab;
    }).toList();

    emit(state.copyWith(tabs: tabs));
  }

  void _onReorderTab(ReorderTab event, Emitter<TabManagerState> emit) {
    if (state.tabs.length < 2) return;
    if (event.fromIndex < 0 || event.fromIndex >= state.tabs.length) return;
    if (event.toIndex < 0 || event.toIndex >= state.tabs.length) return;
    if (event.fromIndex == event.toIndex) return;

    final tabs = List<TabData>.from(state.tabs);
    final movingTab = tabs[event.fromIndex];
    final selectedIds = state.selectedTabIds;
    final shouldMoveSelectionAsGroup =
        selectedIds.length > 1 && selectedIds.contains(movingTab.id);

    if (shouldMoveSelectionAsGroup) {
      final selectedTabs = tabs
          .where((tab) => selectedIds.contains(tab.id))
          .toList(growable: false);
      final selectedCount = selectedTabs.length;
      if (selectedCount > 1) {
        final draggedOffsetInGroup =
            selectedTabs.indexWhere((tab) => tab.id == movingTab.id);
        final unselectedTabs = tabs
            .where((tab) => !selectedIds.contains(tab.id))
            .toList(growable: true);

        final rawInsertIndex = event.toIndex - draggedOffsetInGroup;
        final insertIndex = rawInsertIndex.clamp(0, unselectedTabs.length);
        unselectedTabs.insertAll(insertIndex, selectedTabs);

        emit(state.copyWith(
          tabs: unselectedTabs,
          activeTabId: state.activeTabId,
        ));
        return;
      }
    }

    final moved = tabs.removeAt(event.fromIndex);
    tabs.insert(event.toIndex, moved);

    emit(state.copyWith(
      tabs: tabs,
      activeTabId: state.activeTabId,
    ));
  }
}

/// Helper class for working with the tab system
/// Serves as interface between network browsing and the tab system
class TabNavigator {
  /// Updates the path of a specific tab
  static void updateTabPath(BuildContext context, String tabId, String path) {
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);

    // Check if the path is actually different before updating
    final currentTab = tabBloc.state.tabs.firstWhere(
      (tab) => tab.id == tabId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );

    // Only update if the path has actually changed
    if (currentTab.path != path) {
      tabBloc.add(UpdateTabPath(tabId, path));
      // Note: updatePath() in TabData already handles navigation history
    }
  }

  /// Opens a new tab with the specified path
  static void openTab(BuildContext context, String path,
      {String? title, String? highlightedFileName}) {
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    tabBloc.add(AddTab(
      path: path,
      name: title ?? _extractNameFromPath(path),
      switchToTab: true,
      highlightedFileName: highlightedFileName,
    ));
  }

  /// Closes the specified tab
  static void closeTab(BuildContext context, String tabId) {
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    tabBloc.add(CloseTab(tabId));
  }

  /// Helper method to extract a name from a path
  static String _extractNameFromPath(String path) {
    final pathParts = path.split('/');
    return pathParts.isEmpty || pathParts.last.isEmpty
        ? 'Root'
        : pathParts.last;
  }
}
