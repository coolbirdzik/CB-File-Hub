import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/utils/platform_utils.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';

/// Mixin for managing user preferences related to folder list display
///
/// This mixin handles:
/// - View mode (list, grid, details)
/// - Grid zoom level
/// - Column visibility for details view
/// - File tags display
/// - Sort options
///
/// Usage:
/// ```dart
/// class MyState extends State<MyWidget> with PreferencesManagerMixin {
///   @override
///   FolderListBloc get folderListBloc => _folderListBloc;
///
///   @override
///   void initState() {
///     super.initState();
///     loadPreferences();
///   }
/// }
/// ```
mixin PreferencesManagerMixin<T extends StatefulWidget> on State<T> {
  /// The FolderListBloc instance to send events to
  FolderListBloc get folderListBloc;

  /// Current view mode (list, grid, or details)
  ViewMode viewMode = ViewMode.list; // Default to list view

  /// Current grid zoom level (number of columns in grid view)
  int gridZoomLevel = 4; // Default zoom level

  /// Column visibility settings for details view
  ColumnVisibility columnVisibility =
      const ColumnVisibility(); // Default visibility

  /// Whether to show file tags
  bool showFileTags = true; // Default value to prevent LateInitializationError

  /// Whether to show the preview pane in grid preview mode
  bool isPreviewPaneVisible = true;

  /// Width of the preview pane in grid preview mode
  double previewPaneWidth = UserPreferences.defaultPreviewPaneWidth;

  /// Load all preferences from storage
  Future<void> loadPreferences() async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();

      final loadedViewMode = await prefs.getViewMode();
      final sortOption = await prefs.getSortOption();
      final loadedGridZoomLevel = await prefs.getGridZoomLevel();
      final loadedColumnVisibility = await prefs.getColumnVisibility();
      final loadedShowFileTags = await prefs.getShowFileTags();
      final loadedPreviewPaneVisible = await prefs.getPreviewPaneVisible();
      final loadedPreviewPaneWidth = await prefs.getPreviewPaneWidth();
      final effectiveViewMode =
          !isDesktopPlatform && loadedViewMode == ViewMode.gridPreview
              ? ViewMode.grid
              : loadedViewMode;

      if (mounted) {
        final maxZoom = GridZoomConstraints.maxGridSizeForContext(
          context,
          mode: GridSizeMode.referenceWidth,
        );
        final resolvedGridZoom = loadedGridZoomLevel
            .clamp(UserPreferences.minGridZoomLevel, maxZoom)
            .toInt();
        setState(() {
          viewMode = effectiveViewMode;
          gridZoomLevel = resolvedGridZoom;
          columnVisibility = loadedColumnVisibility;
          showFileTags = loadedShowFileTags;
          isPreviewPaneVisible = loadedPreviewPaneVisible;
          previewPaneWidth = loadedPreviewPaneWidth;
        });

        folderListBloc.add(SetViewMode(effectiveViewMode));
        folderListBloc.add(SetSortOption(sortOption));
        folderListBloc.add(SetGridZoom(resolvedGridZoom));
      }
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    }
  }

  /// Save view mode setting to storage
  Future<void> saveViewModeSetting(ViewMode mode) async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setViewMode(mode);
    } catch (e) {
      debugPrint('Error saving view mode: $e');
    }
  }

  /// Save sort option setting to storage
  Future<void> saveSortSetting(SortOption option, String currentPath) async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setSortOption(option);
      final folderSortManager = FolderSortManager();
      await folderSortManager.saveFolderSortOption(currentPath, option);
    } catch (e) {
      debugPrint('Error saving sort option: $e');
    }
  }

  /// Save grid zoom level setting to storage
  Future<void> saveGridZoomSetting(int zoomLevel) async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setGridZoomLevel(zoomLevel);
      setState(() {
        gridZoomLevel = zoomLevel;
      });
    } catch (e) {
      debugPrint('Error saving grid zoom level: $e');
    }
  }

  /// Toggle between view modes (list -> grid -> details -> list)
  void toggleViewMode() {
    setState(() {
      // Cycle through view modes: list -> grid -> grid preview -> details -> list
      if (viewMode == ViewMode.list) {
        viewMode = ViewMode.grid;
      } else if (viewMode == ViewMode.grid) {
        viewMode = isDesktopPlatform ? ViewMode.gridPreview : ViewMode.details;
      } else if (viewMode == ViewMode.gridPreview) {
        viewMode = ViewMode.details;
      } else {
        viewMode = ViewMode.list;
      }
    });

    folderListBloc.add(SetViewMode(viewMode));
    saveViewModeSetting(viewMode);
  }

  /// Set view mode directly to a specific mode
  void setViewMode(ViewMode mode, {String? tabId}) {
    final effectiveMode = !isDesktopPlatform && mode == ViewMode.gridPreview
        ? ViewMode.grid
        : mode;
    setState(() {
      viewMode = effectiveMode;
    });

    folderListBloc.add(SetViewMode(viewMode));
    saveViewModeSetting(viewMode);
  }

  /// Handle grid zoom level change
  void handleGridZoomChange(int zoomLevel) {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final clamped =
        zoomLevel.clamp(UserPreferences.minGridZoomLevel, maxZoom).toInt();
    folderListBloc.add(SetGridZoom(clamped));
    saveGridZoomSetting(clamped);
  }

  /// Handle zoom level change via mouse wheel or other input
  ///
  /// [direction] - positive to zoom in (more columns), negative to zoom out (fewer columns)
  void handleZoomLevelChange(int direction) {
    // Reverse direction: increase zoom when scrolling down (direction > 0), decrease when scrolling up (direction < 0)
    final currentZoom = gridZoomLevel;
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final newZoom = (currentZoom + direction)
        .clamp(UserPreferences.minGridZoomLevel, maxZoom)
        .toInt();

    if (newZoom != currentZoom) {
      folderListBloc.add(SetGridZoom(newZoom));
      saveGridZoomSetting(newZoom);
    }
  }

  /// Toggle preview pane visibility
  void togglePreviewPaneVisibility() {
    setState(() {
      isPreviewPaneVisible = !isPreviewPaneVisible;
    });
    savePreviewPaneVisibilitySetting(isPreviewPaneVisible);
  }

  /// Update preview pane width without persisting
  void updatePreviewPaneWidth(double width) {
    setState(() {
      previewPaneWidth = width;
    });
  }

  /// Persist preview pane width to storage
  Future<void> savePreviewPaneWidthSetting(double width) async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setPreviewPaneWidth(width);
    } catch (e) {
      debugPrint('Error saving preview pane width: $e');
    }
  }

  /// Persist preview pane visibility to storage
  Future<void> savePreviewPaneVisibilitySetting(bool visible) async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setPreviewPaneVisible(visible);
    } catch (e) {
      debugPrint('Error saving preview pane visibility: $e');
    }
  }

  /// Show column visibility dialog for details view
  void showColumnVisibilityDialog(BuildContext context) {
    SharedActionBar.showColumnVisibilityDialog(
      context,
      currentVisibility: columnVisibility,
      onApply: (ColumnVisibility visibility) async {
        setState(() {
          columnVisibility = visibility;
        });

        try {
          final UserPreferences prefs = UserPreferences.instance;
          await prefs.init();
          await prefs.setColumnVisibility(visibility);
        } catch (e) {
          debugPrint('Error saving column visibility: $e');
        }
      },
    );
  }
}
