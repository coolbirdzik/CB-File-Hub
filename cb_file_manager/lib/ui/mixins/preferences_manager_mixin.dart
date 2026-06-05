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

  String get preferencePath => folderListBloc.state.currentPath.path;

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

      final folderPreferencePath = preferencePath;
      final folderSortManager = FolderSortManager();
      final globalViewMode = await prefs.getViewMode();
      final loadedViewMode =
          await folderSortManager.getFolderViewMode(folderPreferencePath) ??
              globalViewMode;
      final globalSortOption = await prefs.getSortOption();
      final sortOption =
          await folderSortManager.getFolderSortOption(folderPreferencePath) ??
              globalSortOption;
      final loadedGridZoomLevel = await folderSortManager
              .getFolderGridZoomLevel(folderPreferencePath) ??
          await prefs.getGridZoomLevel();
      final loadedColumnVisibility =
          await folderSortManager.getFolderColumnVisibility(
                folderPreferencePath,
              ) ??
              await prefs.getColumnVisibility();
      final loadedShowFileTags =
          await folderSortManager.getFolderShowFileTags(folderPreferencePath) ??
              await prefs.getShowFileTags();
      final loadedPreviewPaneVisible =
          await folderSortManager.getFolderPreviewPaneVisible(
                folderPreferencePath,
              ) ??
              await prefs.getPreviewPaneVisible();
      final loadedPreviewPaneWidth =
          await folderSortManager.getFolderPreviewPaneWidth(
                folderPreferencePath,
              ) ??
              await prefs.getPreviewPaneWidth();
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
        folderListBloc.add(SetSortOption(
          sortOption,
          persist: false,
        ));
        folderListBloc.add(SetGridZoom(resolvedGridZoom));
      }
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    }
  }

  /// Save view mode setting to storage
  Future<void> saveViewModeSetting(ViewMode mode, {String? currentPath}) async {
    try {
      await UserPreferences.instance.init();
      final folderSortManager = FolderSortManager();
      await folderSortManager.saveFolderViewMode(
        currentPath ?? preferencePath,
        mode,
      );
    } catch (e) {
      debugPrint('Error saving view mode: $e');
    }
  }

  /// Save sort option setting to storage
  Future<void> saveSortSetting(SortOption option, String currentPath) async {
    try {
      await UserPreferences.instance.init();
      final folderSortManager = FolderSortManager();
      await folderSortManager.saveFolderSortOption(currentPath, option);
    } catch (e) {
      debugPrint('Error saving sort option: $e');
    }
  }

  /// Save grid zoom level setting to storage
  Future<void> saveGridZoomSetting(int zoomLevel) async {
    try {
      await UserPreferences.instance.init();
      await FolderSortManager().saveFolderGridZoomLevel(
        preferencePath,
        zoomLevel,
      );
      setState(() {
        gridZoomLevel = zoomLevel;
      });
    } catch (e) {
      debugPrint('Error saving grid zoom level: $e');
    }
  }

  /// Toggle between view modes
  /// (list -> grid -> gridPreview (desktop) -> details -> columns (desktop) -> tree -> list)
  void toggleViewMode() {
    setState(() {
      if (viewMode == ViewMode.list) {
        viewMode = ViewMode.grid;
      } else if (viewMode == ViewMode.grid) {
        viewMode = isDesktopPlatform ? ViewMode.gridPreview : ViewMode.details;
      } else if (viewMode == ViewMode.gridPreview) {
        viewMode = ViewMode.details;
      } else if (viewMode == ViewMode.details) {
        viewMode = isDesktopPlatform ? ViewMode.columns : ViewMode.tree;
      } else if (viewMode == ViewMode.columns) {
        viewMode = ViewMode.tree;
      } else {
        // tree (or any unhandled) → list
        viewMode = ViewMode.list;
      }
    });

    folderListBloc.add(SetViewMode(viewMode));
    saveViewModeSetting(viewMode);
  }

  /// Set view mode directly to a specific mode
  void setViewMode(ViewMode mode, {String? tabId}) {
    setState(() {
      viewMode = !isDesktopPlatform && mode == ViewMode.gridPreview
          ? ViewMode.grid
          : mode;
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
      await UserPreferences.instance.init();
      await FolderSortManager().saveFolderPreviewPaneWidth(
        preferencePath,
        width,
      );
    } catch (e) {
      debugPrint('Error saving preview pane width: $e');
    }
  }

  /// Persist preview pane visibility to storage
  Future<void> savePreviewPaneVisibilitySetting(bool visible) async {
    try {
      await UserPreferences.instance.init();
      await FolderSortManager().saveFolderPreviewPaneVisible(
        preferencePath,
        visible,
      );
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
          await UserPreferences.instance.init();
          await FolderSortManager().saveFolderColumnVisibility(
            preferencePath,
            visibility,
          );
        } catch (e) {
          debugPrint('Error saving column visibility: $e');
        }
      },
    );
  }

  Future<void> saveShowFileTagsSetting(bool visible) async {
    try {
      await UserPreferences.instance.init();
      await FolderSortManager().saveFolderShowFileTags(
        preferencePath,
        visible,
      );
      if (!mounted) return;
      setState(() {
        showFileTags = visible;
      });
    } catch (e) {
      debugPrint('Error saving show file tags: $e');
    }
  }
}
