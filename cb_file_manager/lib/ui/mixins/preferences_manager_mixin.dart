import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_display_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/utils/platform_utils.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/utils/view_mode_utils.dart';
import 'package:cb_file_manager/ui/utils/view_mode_spectrum.dart';

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

  /// Preview visibility the host keeps for its session (e.g. per tab).
  /// When non-null it wins over the stored default on load.
  bool? get sessionPreviewPaneVisible => null;

  /// Called when the user toggles the preview pane, so the host can keep the
  /// choice for its session. Visibility is not persisted.
  void onPreviewPaneVisibilityChanged(bool visible) {}

  /// Load all preferences from storage
  Future<void> loadPreferences() async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();

      final settings = await FolderDisplayPreferences.instance.resolve(
        preferencePath,
      );
      // Preview pane state is not per folder: visibility comes from the host
      // session (e.g. the tab) and falls back to the stored default.
      final loadedPreviewPaneVisible =
          sessionPreviewPaneVisible ?? await prefs.getPreviewPaneVisible();
      final loadedPreviewPaneWidth = await prefs.getPreviewPaneWidth();

      if (mounted) {
        setState(() {
          isPreviewPaneVisible = loadedPreviewPaneVisible;
          previewPaneWidth = loadedPreviewPaneWidth;
        });
        applyDisplaySettings(settings);
      }
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    }
  }

  /// Shows [settings] (a folder's view mode, sort, zoom, columns and tags).
  ///
  /// Only what differs is sent to the bloc, so settings it already applied
  /// while loading the folder do not re-sort or rebuild the listing. Pass
  /// [inInitState] before the first build: fields are set without
  /// `setState` and the zoom is clamped later, when the size is known.
  void applyDisplaySettings(
    FolderDisplaySettings settings, {
    bool inInitState = false,
  }) {
    final zoom = inInitState
        ? settings.gridZoomLevel
        : settings.gridZoomLevel
              .clamp(
                UserPreferences.minGridZoomLevel,
                GridZoomConstraints.maxGridSizeForContext(
                  context,
                  mode: GridSizeMode.referenceWidth,
                ),
              )
              .toInt();
    void assign() {
      viewMode = settings.viewMode;
      gridZoomLevel = zoom;
      columnVisibility = settings.columnVisibility;
      showFileTags = settings.showFileTags;
    }

    if (inInitState) {
      assign();
    } else if (viewMode != settings.viewMode ||
        gridZoomLevel != zoom ||
        columnVisibility != settings.columnVisibility ||
        showFileTags != settings.showFileTags) {
      setState(assign);
    }

    final current = folderListBloc.state;
    if (current.viewMode != settings.viewMode) {
      folderListBloc.add(SetViewMode(settings.viewMode));
    }
    if (current.sortOption != settings.sortOption) {
      folderListBloc.add(SetSortOption(settings.sortOption, persist: false));
    }
    if (current.gridZoomLevel != zoom) {
      folderListBloc.add(SetGridZoom(zoom));
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
  /// (list -> tiles -> grid -> details -> columns (desktop) -> tree -> list)
  void toggleViewMode() {
    setState(() {
      if (viewMode == ViewMode.list) {
        viewMode = ViewMode.tiles;
      } else if (viewMode == ViewMode.tiles) {
        viewMode = ViewMode.grid;
      } else if (viewMode == ViewMode.grid ||
          viewMode == ViewMode.gridPreview) {
        viewMode = ViewMode.details;
      } else if (viewMode == ViewMode.details) {
        viewMode = isDesktopPlatform ? ViewMode.columns : ViewMode.tree;
      } else if (viewMode == ViewMode.columns) {
        viewMode = ViewMode.tree;
      } else {
        viewMode = ViewMode.list;
      }
    });

    folderListBloc.add(SetViewMode(ViewModeUtils.normalize(viewMode)));
    saveViewModeSetting(ViewModeUtils.normalize(viewMode));
  }

  /// Set view mode directly to a specific mode
  void setViewMode(ViewMode mode, {String? tabId}) {
    final resolved = ViewModeUtils.normalize(
      !isDesktopPlatform && mode == ViewMode.gridPreview ? ViewMode.grid : mode,
    );
    setState(() {
      viewMode = resolved;
    });

    folderListBloc.add(SetViewMode(resolved));
    saveViewModeSetting(resolved);
  }

  /// Handle grid zoom level change
  void handleGridZoomChange(int zoomLevel) {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final clamped = zoomLevel
        .clamp(UserPreferences.minGridZoomLevel, maxZoom)
        .toInt();
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

  /// Supported non-grid view modes for the unified Ctrl+scroll spectrum.
  /// Mobile drops `columns` (and `gridPreview` is always excluded from the
  /// spectrum). Override in a host widget if a screen supports fewer modes.
  Set<ViewMode> get spectrumSupportedModes => isDesktopPlatform
      ? const {
          ViewMode.tree,
          ViewMode.columns,
          ViewMode.details,
          ViewMode.list,
          ViewMode.tiles,
        }
      : const {ViewMode.tree, ViewMode.details, ViewMode.list, ViewMode.tiles};

  /// Handle a unified "view scale" delta from Ctrl+scroll.
  ///
  /// [delta] - `+1` moves toward the spacious end (wider modes / bigger grid
  /// items), `-1` toward the dense end. Walks the full
  /// tree↔column↔detail↔list↔tiles↔grid spectrum, transitioning view mode
  /// and/or adjusting the grid zoom level as needed.
  void handleViewScaleChange(int delta) {
    if (delta == 0) return;
    final currentMode = ViewModeUtils.normalize(folderListBloc.state.viewMode);
    final currentZoom = folderListBloc.state.gridZoomLevel;
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final result = ViewModeSpectrum.step(
      currentMode: currentMode,
      currentZoom: currentZoom,
      supported: spectrumSupportedModes,
      delta: delta,
      minZoom: UserPreferences.minGridZoomLevel,
      maxZoom: maxZoom,
    );

    if (result.mode != currentMode) {
      setViewMode(result.mode);
    }
    if (result.gridZoomLevel != currentZoom) {
      folderListBloc.add(SetGridZoom(result.gridZoomLevel));
      saveGridZoomSetting(result.gridZoomLevel);
    }
  }

  /// Toggle preview pane visibility
  void togglePreviewPaneVisibility() {
    setState(() {
      isPreviewPaneVisible = !isPreviewPaneVisible;
    });
    onPreviewPaneVisibilityChanged(isPreviewPaneVisible);
  }

  /// Update preview pane width without persisting
  void updatePreviewPaneWidth(double width) {
    setState(() {
      previewPaneWidth = width;
    });
  }

  /// Persist preview pane width (one width for every folder)
  Future<void> savePreviewPaneWidthSetting(double width) async {
    try {
      await UserPreferences.instance.init();
      await UserPreferences.instance.setPreviewPaneWidth(width);
    } catch (e) {
      debugPrint('Error saving preview pane width: $e');
    }
  }

  /// Show column visibility dialog for details view
  void showColumnVisibilityDialog(BuildContext context) {
    SharedActionBar.showColumnVisibilityDialog(
      context,
      currentVisibility: columnVisibility,
      onApply: saveColumnVisibility,
    );
  }

  /// Applies and persists the Details columns (shown, order, widths) for
  /// the current folder.
  Future<void> saveColumnVisibility(ColumnVisibility visibility) async {
    if (!mounted) return;
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
  }

  Future<void> saveShowFileTagsSetting(bool visible) async {
    try {
      await UserPreferences.instance.init();
      await FolderSortManager().saveFolderShowFileTags(preferencePath, visible);
      if (!mounted) return;
      setState(() {
        showFileTags = visible;
      });
    } catch (e) {
      debugPrint('Error saving show file tags: $e');
    }
  }
}
