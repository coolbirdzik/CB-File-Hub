import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

/// Mixin providing user preferences management for screens
mixin PreferencesMixin<T extends StatefulWidget> on State<T> {
  UserPreferences get preferences => UserPreferences.instance;

  /// Current view mode
  ViewMode _viewMode = ViewMode.list;
  ViewMode get viewMode => _viewMode;

  /// Current sort option
  SortOption _sortOption = SortOption.nameAsc;
  SortOption get sortOption => _sortOption;

  /// Grid zoom level (columns count)
  int _gridZoomLevel = 3;
  int get gridZoomLevel => _gridZoomLevel;

  /// Column visibility settings
  ColumnVisibility _columnVisibility = const ColumnVisibility();
  ColumnVisibility get columnVisibility => _columnVisibility;

  /// Load all preferences from storage
  Future<void> loadPreferences() async {
    try {
      await preferences.init();

      final viewMode = await preferences.getViewMode();
      final effectiveViewMode = viewMode == ViewMode.gridPreview
          ? ViewMode.grid
          : viewMode;
      final sortOption = await preferences.getSortOption();
      final gridZoomLevel = await preferences.getGridZoomLevel();
      final columnVisibility = await preferences.getColumnVisibility();

      if (mounted) {
        setState(() {
          _viewMode = effectiveViewMode;
          _sortOption = sortOption;
          _gridZoomLevel = gridZoomLevel;
          _columnVisibility = columnVisibility;
        });
      }
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    }
  }

  /// Save view mode preference
  Future<void> saveViewMode(ViewMode mode) async {
    try {
      await preferences.init();
      await preferences.setViewMode(mode);
      if (mounted) {
        setState(() {
          _viewMode = mode;
        });
      }
    } catch (e) {
      debugPrint('Error saving view mode: $e');
    }
  }

  /// Save sort option preference
  Future<void> saveSortOption(SortOption option) async {
    try {
      await preferences.init();
      await preferences.setSortOption(option);
      if (mounted) {
        setState(() {
          _sortOption = option;
        });
      }
    } catch (e) {
      debugPrint('Error saving sort option: $e');
    }
  }

  /// Save grid zoom level
  Future<void> saveGridZoomLevel(int level) async {
    try {
      await preferences.init();
      await preferences.setGridZoomLevel(level);
      if (mounted) {
        setState(() {
          _gridZoomLevel = level;
        });
      }
    } catch (e) {
      debugPrint('Error saving grid zoom level: $e');
    }
  }

  /// Save column visibility
  Future<void> saveColumnVisibility(ColumnVisibility visibility) async {
    try {
      await preferences.init();
      await preferences.setColumnVisibility(visibility);
      if (mounted) {
        setState(() {
          _columnVisibility = visibility;
        });
      }
    } catch (e) {
      debugPrint('Error saving column visibility: $e');
    }
  }

  /// Toggle between grid and list view
  void toggleViewMode() {
    final newMode = _viewMode == ViewMode.grid ? ViewMode.list : ViewMode.grid;
    saveViewMode(newMode);
  }

  /// Update sort option and save
  void updateSortOption(SortOption option) {
    if (_sortOption != option) {
      saveSortOption(option);
    }
  }

  /// Update grid zoom level and save
  void updateGridZoomLevel(int level) {
    if (_gridZoomLevel != level) {
      saveGridZoomLevel(level);
    }
  }
}
