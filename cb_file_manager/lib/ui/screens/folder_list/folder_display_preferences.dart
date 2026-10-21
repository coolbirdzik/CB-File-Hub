import 'dart:async';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/view_mode_utils.dart';
import 'package:flutter/foundation.dart';

/// How a folder is shown: its own saved settings over the global defaults.
@immutable
class FolderDisplaySettings {
  const FolderDisplaySettings({
    required this.viewMode,
    required this.sortOption,
    required this.gridZoomLevel,
    required this.columnVisibility,
    required this.showFileTags,
  });

  final ViewMode viewMode;
  final SortOption sortOption;

  /// As saved; callers clamp it to the width they have.
  final int gridZoomLevel;
  final ColumnVisibility columnVisibility;
  final bool showFileTags;

  FolderDisplaySettings _over(FolderDisplayOverrides overrides) =>
      FolderDisplaySettings(
        viewMode: ViewModeUtils.normalize(overrides.viewMode ?? viewMode),
        sortOption: overrides.sortOption ?? sortOption,
        gridZoomLevel: overrides.gridZoomLevel ?? gridZoomLevel,
        columnVisibility: overrides.columnVisibility ?? columnVisibility,
        showFileTags: overrides.showFileTags ?? showFileTags,
      );
}

/// Resolves [FolderDisplaySettings] for a path.
///
/// The global defaults and every saved folder are kept in memory after
/// [warmUp], so a new tab or a navigation gets the right view mode, sort and
/// columns synchronously ([cached]) instead of showing the defaults until a
/// handful of database reads come back.
class FolderDisplayPreferences {
  FolderDisplayPreferences._();

  static final instance = FolderDisplayPreferences._();

  FolderDisplaySettings? _defaults;
  Future<FolderDisplaySettings>? _loadingDefaults;
  int _defaultsGeneration = 0;

  /// Loads the defaults and every saved folder. Safe to call more than once.
  Future<void> warmUp() async {
    await _loadDefaults();
    try {
      await FolderSortManager().preloadAll();
    } catch (e) {
      debugPrint('FolderDisplayPreferences.warmUp: $e');
    }
  }

  /// The settings of [path] from memory, or null when something is not
  /// loaded yet (then use [resolve]).
  FolderDisplaySettings? cached(String path) {
    final defaults = _defaults;
    if (defaults == null) return null;
    final overrides = FolderSortManager().cachedOverrides(path);
    return overrides == null ? null : defaults._over(overrides);
  }

  Future<FolderDisplaySettings> resolve(String path) async {
    final defaults = await _loadDefaults();
    final overrides = await FolderSortManager().getOverrides(path);
    return defaults._over(overrides);
  }

  /// Drops the cached defaults after a global display preference changed.
  void invalidateDefaults() {
    _defaults = null;
    _loadingDefaults = null;
    _defaultsGeneration++;
  }

  Future<FolderDisplaySettings> _loadDefaults() {
    final defaults = _defaults;
    if (defaults != null) return Future.value(defaults);
    return _loadingDefaults ??= () async {
      final generation = _defaultsGeneration;
      try {
        final prefs = UserPreferences.instance;
        await prefs.init();
        final loaded = FolderDisplaySettings(
          viewMode: ViewModeUtils.normalize(await prefs.getViewMode()),
          sortOption: await prefs.getSortOption(),
          gridZoomLevel: await prefs.getGridZoomLevel(),
          columnVisibility: await prefs.getColumnVisibility(),
          showFileTags: await prefs.getShowFileTags(),
        );
        // A default saved meanwhile invalidated this read; the next call
        // reads again.
        if (generation == _defaultsGeneration) _defaults = loaded;
        return loaded;
      } catch (_) {
        if (generation == _defaultsGeneration) _loadingDefaults = null;
        rethrow;
      }
    }();
  }
}
