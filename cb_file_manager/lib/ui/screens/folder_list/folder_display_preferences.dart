import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/view_mode_utils.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pathlib;

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

  FolderDisplaySettings _withViewMode(ViewMode mode) =>
      _over(FolderDisplayOverrides(viewMode: mode));
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
  FolderViewModePreference _viewModePreference =
      FolderViewModePreference.mediaGrid;

  // Only remember the classification, never the listing or an inferred override.
  // Large folders that the listing cache skips can still restore their layout.
  final Map<String, bool> _mediaOnlyFolders = {};

  /// Until media detection has a listing, avoid a skeleton in the wrong view.
  bool needsListingForViewMode(String path) {
    if (path.isEmpty || path.startsWith('#') || path.contains('://')) {
      return false;
    }
    if (_defaults == null) return true;
    return _viewModePreference == FolderViewModePreference.mediaGrid &&
        FolderSortManager().cachedOverrides(path)?.viewMode == null &&
        !_mediaOnlyFolders.containsKey(_pathKey(path));
  }

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
    if (overrides == null) return null;
    final settings = defaults._over(overrides);
    if (overrides.viewMode != null) return settings;
    if (_viewModePreference == FolderViewModePreference.mediaGrid) {
      return _mediaOnlyFolders[_pathKey(path)] == true
          ? settings._withViewMode(ViewMode.grid)
          : settings;
    }
    for (final parent in _parents(path)) {
      final inherited = FolderSortManager().cachedOverrides(parent);
      if (inherited == null) return null;
      if (inherited.viewMode != null) {
        return settings._withViewMode(inherited.viewMode!);
      }
    }
    return settings;
  }

  Future<FolderDisplaySettings> resolve(
    String path, {
    List<File>? files,
    List<Directory>? folders,
  }) async {
    if (files != null && folders != null) {
      final key = _pathKey(path);
      _mediaOnlyFolders.remove(key);
      _mediaOnlyFolders[key] =
          folders.isEmpty &&
          files.isNotEmpty &&
          files.every((file) => FileTypeUtils.isMediaFile(file.path));
      if (_mediaOnlyFolders.length > 128) {
        _mediaOnlyFolders.remove(_mediaOnlyFolders.keys.first);
      }
    }
    final defaults = await _loadDefaults();
    final overrides = await FolderSortManager().getOverrides(path);
    final settings = defaults._over(overrides);
    if (overrides.viewMode != null) return settings;
    if (_viewModePreference == FolderViewModePreference.mediaGrid) {
      return _mediaOnlyFolders[_pathKey(path)] == true
          ? settings._withViewMode(ViewMode.grid)
          : settings;
    }
    for (final parent in _parents(path)) {
      final inherited =
          FolderSortManager().cachedOverrides(parent) ??
          await FolderSortManager().getOverrides(parent);
      if (inherited.viewMode != null) {
        return settings._withViewMode(inherited.viewMode!);
      }
    }
    return settings;
  }

  String _pathKey(String path) {
    final normalized = pathlib.normalize(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Iterable<String> _parents(String path) sync* {
    // Virtual screens and remote URL schemes have their own view preferences.
    if (path.isEmpty || path.startsWith('#') || path.contains('://')) return;
    var current = pathlib.normalize(path);
    while (true) {
      final parent = pathlib.dirname(current);
      if (parent == current || parent == '.') return;
      yield parent;
      current = parent;
    }
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
        final viewModePreference = await prefs.getFolderViewModePreference();
        final loaded = FolderDisplaySettings(
          viewMode: ViewModeUtils.normalize(await prefs.getViewMode()),
          sortOption: await prefs.getSortOption(),
          gridZoomLevel: await prefs.getGridZoomLevel(),
          columnVisibility: await prefs.getColumnVisibility(),
          showFileTags: await prefs.getShowFileTags(),
        );
        // A default saved meanwhile invalidated this read; the next call
        // reads again.
        if (generation == _defaultsGeneration) {
          _defaults = loaded;
          _viewModePreference = viewModePreference;
        }
        return loaded;
      } catch (_) {
        if (generation == _defaultsGeneration) _loadingDefaults = null;
        rethrow;
      }
    }();
  }
}
