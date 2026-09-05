import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/utils/view_mode_utils.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

/// Result of a single spectrum step: the resolved view mode and grid zoom level.
class ViewSpectrumResult {
  final ViewMode mode;
  final int gridZoomLevel;

  const ViewSpectrumResult(this.mode, this.gridZoomLevel);

  @override
  bool operator ==(Object other) =>
      other is ViewSpectrumResult &&
      other.mode == mode &&
      other.gridZoomLevel == gridZoomLevel;

  @override
  int get hashCode => Object.hash(mode, gridZoomLevel);

  @override
  String toString() => 'ViewSpectrumResult($mode, zoom: $gridZoomLevel)';
}

/// Maps the discrete view modes plus the continuous grid zoom levels onto a
/// single linear "view scale" spectrum, ordered from densest to most spacious:
///
/// ```
/// tree → columns → details → list → tiles → grid(maxZoom) → ... → grid(minZoom)
/// (densest)                                                  (most spacious)
/// ```
///
/// `delta > 0` moves one stop toward the *spacious* end (bigger items / wider
/// modes); `delta < 0` moves toward the *dense* end. Scrolling clamps at both
/// ends. This is the shared engine that drives Ctrl+scroll on every
/// file-listing page.
///
/// [ViewMode.gridPreview] is deprecated: treat it as [ViewMode.grid] and control
/// preview via a separate pane visibility toggle.
class ViewModeSpectrum {
  /// Canonical dense → spacious order of the non-grid modes.
  static const List<ViewMode> nonGridOrder = [
    ViewMode.tree,
    ViewMode.columns,
    ViewMode.details,
    ViewMode.list,
    ViewMode.tiles,
  ];

  /// Builds the ordered list of non-grid stops a page supports, in canonical
  /// dense → spacious order. [ViewMode.grid]/[ViewMode.gridPreview] entries in
  /// [supported] are ignored here (grid stops are generated separately).
  static List<ViewMode> nonGridStops(Set<ViewMode> supported) => [
    for (final m in nonGridOrder)
      if (supported.contains(m)) m,
  ];

  /// Computes the next `(mode, gridZoomLevel)` for a scroll [delta].
  ///
  /// - [currentMode]   current view mode.
  /// - [currentZoom]   current grid zoom level (column-count semantics:
  ///   higher = more columns = smaller items).
  /// - [supported]     the page's supported non-grid modes. Grid is always
  ///   assumed available. Exclude [ViewMode.gridPreview].
  /// - [minZoom]/[maxZoom] grid zoom bounds. [maxZoom] should already be
  ///   clamped for the current viewport width.
  /// - [delta]         `+1` = more spacious, `-1` = denser.
  ///
  /// While in [ViewMode.gridPreview] the result never transitions to another
  /// mode: it only adjusts zoom within `[minZoom, maxZoom]`, keeping the page
  /// in `gridPreview`.
  static ViewSpectrumResult step({
    required ViewMode currentMode,
    required int currentZoom,
    required Set<ViewMode> supported,
    required int delta,
    int minZoom = UserPreferences.minGridZoomLevel,
    int maxZoom = UserPreferences.maxGridZoomLevel,
  }) {
    final int safeMax = maxZoom < minZoom ? minZoom : maxZoom;
    final int clampedZoom = currentZoom.clamp(minZoom, safeMax).toInt();

    final normalizedMode = ViewModeUtils.normalize(currentMode);

    final List<ViewMode> nonGrid = nonGridStops(supported);

    // Grid stops are appended after the non-grid stops, ordered from the
    // densest grid (maxZoom = smallest items, most columns) toward the most
    // spacious grid (minZoom = biggest items). So a higher spectrum index =
    // more spacious = lower zoom level.
    //
    // Total stops = nonGrid.length + (safeMax - minZoom + 1).
    final int gridStopCount = safeMax - minZoom + 1;
    final int totalStops = nonGrid.length + gridStopCount;

    int currentIndex;
    if (normalizedMode == ViewMode.grid) {
      // Grid stop index: zoom == safeMax → first grid stop (nonGrid.length).
      currentIndex = nonGrid.length + (safeMax - clampedZoom);
    } else {
      final int idx = nonGrid.indexOf(normalizedMode);
      if (idx >= 0) {
        currentIndex = idx;
      } else {
        // Unsupported / unknown mode (e.g. a non-grid mode this page doesn't
        // list): treat as the densest grid stop so scrolling still works.
        currentIndex = nonGrid.length;
      }
    }

    final int nextIndex = (currentIndex + delta)
        .clamp(0, totalStops - 1)
        .toInt();

    if (nextIndex < nonGrid.length) {
      // Landed on a non-grid mode; preserve the current zoom for when the user
      // scrolls back into grid.
      return ViewSpectrumResult(nonGrid[nextIndex], clampedZoom);
    }

    // Landed on a grid stop. First grid stop = safeMax (densest).
    final int gridOffset = nextIndex - nonGrid.length;
    final int zoom = (safeMax - gridOffset).clamp(minZoom, safeMax).toInt();
    return ViewSpectrumResult(ViewMode.grid, zoom);
  }
}
