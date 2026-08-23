import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

/// Helpers for [ViewMode] normalization and legacy migration.
class ViewModeUtils {
  ViewModeUtils._();

  /// Legacy `gridPreview` is no longer a distinct view mode; it maps to [ViewMode.grid].
  /// Preview visibility is controlled separately via [UserPreferences.getPreviewPaneVisible].
  static ViewMode normalize(ViewMode mode) {
    return mode == ViewMode.gridPreview ? ViewMode.grid : mode;
  }

  static bool isGridLike(ViewMode? mode) {
    if (mode == null) return false;
    return normalize(mode) == ViewMode.grid;
  }
}
