import 'dart:io';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';

// State
class DrawerState extends Equatable {
  final List<Directory> storageLocations;
  final List<String> pinnedPaths;
  final String activeTabId;
  final bool isStorageExpanded;
  final bool isPinnedExpanded;
  final bool isLoading;
  final String? error;

  const DrawerState({
    this.storageLocations = const [],
    this.pinnedPaths = const [],
    this.activeTabId = '',
    this.isStorageExpanded = false,
    this.isPinnedExpanded = false,
    this.isLoading = false,
    this.error,
  });

  DrawerState copyWith({
    List<Directory>? storageLocations,
    List<String>? pinnedPaths,
    String? activeTabId,
    bool? isStorageExpanded,
    bool? isPinnedExpanded,
    bool? isLoading,
    String? error,
  }) {
    return DrawerState(
      storageLocations: storageLocations ?? this.storageLocations,
      pinnedPaths: pinnedPaths ?? this.pinnedPaths,
      activeTabId: activeTabId ?? this.activeTabId,
      isStorageExpanded: isStorageExpanded ?? this.isStorageExpanded,
      isPinnedExpanded: isPinnedExpanded ?? this.isPinnedExpanded,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  @override
  List<Object?> get props => [
    storageLocations,
    pinnedPaths,
    activeTabId,
    isStorageExpanded,
    isPinnedExpanded,
    isLoading,
    error,
  ];
}

// Cubit
class DrawerCubit extends Cubit<DrawerState> {
  static const String _storageSectionKey = 'storage';
  static const String _pinnedSectionKey = 'pinned';
  static const String _defaultTabId = '__global__';

  Timer? _syncTimer;

  DrawerCubit() : super(const DrawerState()) {
    _startSyncTimer();
  }

  String _normalizeTabId(String? tabId) {
    final normalized = tabId?.trim() ?? '';
    if (normalized.isEmpty) return _defaultTabId;
    return normalized;
  }

  void _startSyncTimer() {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (!isDesktop) return;
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _syncPinnedPaths();
    });
  }

  Future<void> _syncPinnedPaths() async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();
      final latest = await prefs.getSidebarPinnedPaths();
      final old = state.pinnedPaths;
      if (latest.length != old.length ||
          latest.any((item) => !old.contains(item))) {
        emit(state.copyWith(pinnedPaths: latest));
      }
    } catch (_) {}
  }

  Future<void> loadStorageLocations({String? activeTabId}) async {
    final normalizedTabId = _normalizeTabId(activeTabId ?? state.activeTabId);
    emit(
      state.copyWith(
        isLoading: true,
        error: null,
        activeTabId: normalizedTabId,
      ),
    );
    try {
      final locations = await getAllStorageLocations();
      final prefs = UserPreferences.instance;
      await prefs.init();
      final pinned = await prefs.getSidebarPinnedPaths();
      final rememberWorkspace = await prefs.getRememberTabWorkspaceEnabled();
      var storageExpanded = false;
      var pinnedExpanded = false;

      if (rememberWorkspace) {
        // First try to get the state for this specific tab
        final storageExpandedTab = await prefs.getDrawerSectionExpanded(
          tabId: normalizedTabId,
          sectionKey: _storageSectionKey,
        );
        final pinnedExpandedTab = await prefs.getDrawerSectionExpanded(
          tabId: normalizedTabId,
          sectionKey: _pinnedSectionKey,
        );

        // If tab-specific state is null (new tab or restored tab with new ID),
        // fallback to the global "last used" state.
        if (storageExpandedTab != null) {
          storageExpanded = storageExpandedTab;
        } else {
          storageExpanded =
              await prefs.getLastDrawerSectionExpanded(
                sectionKey: _storageSectionKey,
              ) ??
              false;
          // Also save this state for the current tab so it's "claimed"
          await prefs.setDrawerSectionExpanded(
            tabId: normalizedTabId,
            sectionKey: _storageSectionKey,
            isExpanded: storageExpanded,
          );
        }

        if (pinnedExpandedTab != null) {
          pinnedExpanded = pinnedExpandedTab;
        } else {
          pinnedExpanded =
              await prefs.getLastDrawerSectionExpanded(
                sectionKey: _pinnedSectionKey,
              ) ??
              false;
          // Also save this state for the current tab so it's "claimed"
          await prefs.setDrawerSectionExpanded(
            tabId: normalizedTabId,
            sectionKey: _pinnedSectionKey,
            isExpanded: pinnedExpanded,
          );
        }
      }
      emit(
        state.copyWith(
          storageLocations: locations,
          pinnedPaths: pinned,
          activeTabId: normalizedTabId,
          isStorageExpanded: storageExpanded,
          isPinnedExpanded: pinnedExpanded,
          isLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> togglePinnedPath(String path) async {
    final target = path.trim();
    if (target.isEmpty) return;

    final prefs = UserPreferences.instance;
    await prefs.init();
    final isPinned = await prefs.isPathPinnedToSidebar(target);
    if (isPinned) {
      await prefs.removeSidebarPinnedPath(target);
    } else {
      await prefs.addSidebarPinnedPath(target);
    }
    await _syncPinnedPaths();
  }

  Future<void> setActiveTab(String? tabId) async {
    final normalizedTabId = _normalizeTabId(tabId);
    if (normalizedTabId == state.activeTabId) {
      return;
    }

    final prefs = UserPreferences.instance;
    await prefs.init();
    final rememberWorkspace = await prefs.getRememberTabWorkspaceEnabled();

    if (!rememberWorkspace) {
      emit(
        state.copyWith(
          activeTabId: normalizedTabId,
          isStorageExpanded: false,
          isPinnedExpanded: false,
        ),
      );
      return;
    }

    var storageExpanded = false;
    var pinnedExpanded = false;

    // First try to get the state for this specific tab
    final storageExpandedTab = await prefs.getDrawerSectionExpanded(
      tabId: normalizedTabId,
      sectionKey: _storageSectionKey,
    );
    final pinnedExpandedTab = await prefs.getDrawerSectionExpanded(
      tabId: normalizedTabId,
      sectionKey: _pinnedSectionKey,
    );

    // If tab-specific state is null (new tab or restored tab with new ID),
    // fallback to the global "last used" state.
    if (storageExpandedTab != null) {
      storageExpanded = storageExpandedTab;
    } else {
      storageExpanded =
          await prefs.getLastDrawerSectionExpanded(
            sectionKey: _storageSectionKey,
          ) ??
          false;
      // Also save this state for the current tab so it's "claimed"
      await prefs.setDrawerSectionExpanded(
        tabId: normalizedTabId,
        sectionKey: _storageSectionKey,
        isExpanded: storageExpanded,
      );
    }

    if (pinnedExpandedTab != null) {
      pinnedExpanded = pinnedExpandedTab;
    } else {
      pinnedExpanded =
          await prefs.getLastDrawerSectionExpanded(
            sectionKey: _pinnedSectionKey,
          ) ??
          false;
      // Also save this state for the current tab so it's "claimed"
      await prefs.setDrawerSectionExpanded(
        tabId: normalizedTabId,
        sectionKey: _pinnedSectionKey,
        isExpanded: pinnedExpanded,
      );
    }

    // Since we switched tabs, we should update the "global last" state to reflect
    // the state of the tab we just switched TO. This ensures that if the app is
    // closed now, it will restore the state of this active tab.
    await prefs.setLastDrawerSectionExpanded(
      sectionKey: _storageSectionKey,
      isExpanded: storageExpanded,
    );
    await prefs.setLastDrawerSectionExpanded(
      sectionKey: _pinnedSectionKey,
      isExpanded: pinnedExpanded,
    );

    emit(
      state.copyWith(
        activeTabId: normalizedTabId,
        isStorageExpanded: storageExpanded,
        isPinnedExpanded: pinnedExpanded,
      ),
    );
  }

  Future<void> setStorageExpanded(bool isExpanded) async {
    emit(state.copyWith(isStorageExpanded: isExpanded));
    final prefs = UserPreferences.instance;
    await prefs.init();

    final rememberWorkspace = await prefs.getRememberTabWorkspaceEnabled();
    if (!rememberWorkspace) return;

    await prefs.setDrawerSectionExpanded(
      tabId: _normalizeTabId(state.activeTabId),
      sectionKey: _storageSectionKey,
      isExpanded: isExpanded,
    );
    // Update global state
    await prefs.setLastDrawerSectionExpanded(
      sectionKey: _storageSectionKey,
      isExpanded: isExpanded,
    );
  }

  Future<void> setPinnedExpanded(bool isExpanded) async {
    emit(state.copyWith(isPinnedExpanded: isExpanded));
    final prefs = UserPreferences.instance;
    await prefs.init();

    final rememberWorkspace = await prefs.getRememberTabWorkspaceEnabled();
    if (!rememberWorkspace) return;

    await prefs.setDrawerSectionExpanded(
      tabId: _normalizeTabId(state.activeTabId),
      sectionKey: _pinnedSectionKey,
      isExpanded: isExpanded,
    );
    // Update global state
    await prefs.setLastDrawerSectionExpanded(
      sectionKey: _pinnedSectionKey,
      isExpanded: isExpanded,
    );
  }

  @override
  Future<void> close() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    return super.close();
  }
}
