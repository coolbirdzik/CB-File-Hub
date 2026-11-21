import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/mobile/mobile_file_actions_controller.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';

/// Mixin providing common gallery screen functionality
/// Includes mobile controller, search, and grid size management
mixin GalleryMixin<T extends StatefulWidget> on State<T> {
  /// Mobile actions controller for action bar
  MobileFileActionsController? mobileController;

  /// Controller ID counter for unique IDs
  static int _controllerIdCounter = 0;

  /// Current search query
  String? searchQuery;

  /// Grid size (thumbnail size / columns count)
  double thumbnailSize = 3.0;

  /// Current folder path for settings
  String get currentPath;

  /// User preferences instance
  UserPreferences get preferences => UserPreferences.instance;

  /// Current view mode
  ViewMode get viewMode;
  set viewMode(ViewMode mode);

  /// Current sort option
  SortOption get sortOption;
  set sortOption(SortOption option);

  /// Initialize mobile controller with callbacks
  void initMobileController(String prefix) {
    final controllerId = '${prefix}_${_controllerIdCounter++}';
    mobileController = MobileFileActionsController.forTab(controllerId);
    registerMobileControllerCallbacks();
  }

  /// Register mobile controller callbacks - override in implementing class
  void registerMobileControllerCallbacks() {
    if (mobileController == null) return;

    mobileController!.onSearchSubmitted = (query) {
      setState(() {
        searchQuery = query;
      });
    };

    mobileController!.onSortOptionSelected = (option) {
      setSortOption(option);
    };

    mobileController!.onViewModeToggled = (mode) {
      setState(() {
        viewMode = mode;
        mobileController!.currentViewMode = mode;
      });
      saveViewModeSetting(mode);
    };

    mobileController!.onRefresh = () {
      onRefresh();
    };

    mobileController!.onGridSizePressed = () {
      showGridSizeDialogWithCallback();
    };

    mobileController!.onSelectionModeToggled = () {
      onSelectionModeToggled();
    };
  }

  /// Update mobile controller state with current values
  void updateMobileControllerState() {
    if (mobileController == null) return;

    mobileController!.currentSortOption = sortOption;
    mobileController!.currentViewMode = viewMode;
    mobileController!.currentGridSize = thumbnailSize.round();
  }

  /// Cleanup mobile controller
  void disposeMobileController() {
    if (mobileController != null) {
      MobileFileActionsController.removeTab(mobileController!.tabId);
    }
  }

  /// Build mobile action bar
  Widget buildMobileActionBar(BuildContext context) {
    if (mobileController == null) return const SizedBox.shrink();
    return mobileController!.buildMobileActionBar(context, viewMode: viewMode);
  }

  /// Set sort option and save to preferences
  Future<void> setSortOption(SortOption option) async {
    if (sortOption != option) {
      setState(() {
        sortOption = option;
      });

      // Update controller state
      if (mobileController != null) {
        mobileController!.currentSortOption = option;
      }

      // Save preferences
      try {
        await preferences.setSortOption(option);

        // Save folder-specific setting
        final folderSortManager = FolderSortManager();
        await folderSortManager.saveFolderSortOption(currentPath, option);
      } catch (e) {
        debugPrint('Error saving sort option: $e');
      }

      // Trigger re-sort
      onSortChanged();
    }
  }

  /// Save view mode setting
  Future<void> saveViewModeSetting(ViewMode mode) async {
    try {
      await preferences.init();
      await preferences.setViewMode(mode);
    } catch (e) {
      debugPrint('Error saving view mode: $e');
    }
  }

  /// Show grid size dialog with callback
  void showGridSizeDialogWithCallback() {
    SharedActionBar.showGridSizeDialog(
      context,
      currentGridSize: thumbnailSize.round(),
      onApply: (size) async {
        setState(() {
          thumbnailSize = size.toDouble();
        });

        // Update controller state
        if (mobileController != null) {
          mobileController!.currentGridSize = size;
        }

        // Save to preferences - override in subclass
        await onGridSizeChanged(size);
      },
      sizeMode: GridSizeMode.columns,
      minGridSize: UserPreferences.minThumbnailSize.round(),
      maxGridSize: UserPreferences.maxThumbnailSize.round(),
      gridSpacing: 6.0,
    );
  }

  /// Callbacks to be implemented by subclass
  void onRefresh();
  void onSortChanged();
  void onSelectionModeToggled();
  Future<void> onGridSizeChanged(int size);

  /// Check if platform is mobile
  bool get isMobile => Platform.isAndroid || Platform.isIOS;
}
