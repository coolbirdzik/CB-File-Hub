import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';

enum GridSizeMode { columns, referenceWidth }

class GridZoomConstraints {
  static const double defaultGridSpacing = 8.0;
  static const double defaultReferenceWidth = 960.0;
  static const double defaultMinItemWidth = 72.0;
  static const double defaultGridMinWidth = 56.0;

  // ── Shared file-grid parameters ─────────────────────────────────────────
  // These must stay in sync with FileListViewBuilder._gridSpacing /
  // _gridReferenceWidth so that every screen using a grid shows the same
  // column density for the same zoom level.
  static const double fileGridSpacing = 8.0;
  static const double fileGridReferenceWidth = 960.0;
  static const double fileGridMinItemWidth = 56.0;

  // ── Grid item name area ──────────────────────────────────────────────────
  // Fixed height reserved for the filename label below the thumbnail.
  // Using a fixed height ensures all thumbnails are the same size regardless
  // of whether the filename wraps to 1 or 2 lines.
  //
  // Breakdown: top padding (4) + 2 lines × lineHeight (~16px) = 36px → 40px
  // With tags:  + tag row height (~18px) = ~54px → 58px
  static const double gridItemNameAreaHeight = 40.0;
  static const double gridItemNameAreaHeightWithTags = 58.0;

  // Font size used for grid item filenames (kept here so label height above
  // stays consistent if the font size ever changes).
  static const double gridItemFilenameFontSize = 12.0;

  /// Returns the ideal item width for [zoomLevel] using the canonical
  /// file-browser formula.  Same calculation as
  /// [FileListViewBuilder._gridItemWidthForZoom].
  static double itemWidthForZoom(int zoomLevel) {
    final clamped = zoomLevel.clamp(
      UserPreferences.minGridZoomLevel,
      UserPreferences.maxGridZoomLevel,
    );
    final totalSpacing = fileGridSpacing * (clamped - 1);
    return math.max(
      fileGridMinItemWidth,
      (fileGridReferenceWidth - totalSpacing) / clamped,
    );
  }

  /// Returns the actual column count for [zoomLevel] at [availableWidth],
  /// matching the layout produced by [FileListViewBuilder].
  static int columnCountForZoom(int zoomLevel, double availableWidth) {
    final itemWidth = itemWidthForZoom(zoomLevel);
    final raw =
        ((math.max(0.0, availableWidth) + fileGridSpacing) /
                (itemWidth + fileGridSpacing))
            .floor();
    return math.max(1, raw);
  }

  static int maxGridSize({
    required double availableWidth,
    GridSizeMode mode = GridSizeMode.referenceWidth,
    double minItemWidth = defaultMinItemWidth,
    double spacing = defaultGridSpacing,
    double referenceWidth = defaultReferenceWidth,
    double gridMinWidth = defaultGridMinWidth,
    int minValue = UserPreferences.minGridZoomLevel,
    int maxValue = UserPreferences.maxGridZoomLevel,
  }) {
    final safeWidth = math.max(0.0, availableWidth - (spacing * 2));
    final maxColumns = ((safeWidth + spacing) / (minItemWidth + spacing))
        .floor();
    final cappedColumns = maxColumns.clamp(minValue, maxValue).toInt();
    if (mode == GridSizeMode.columns) {
      return cappedColumns;
    }

    for (int zoom = maxValue; zoom >= minValue; zoom--) {
      final itemWidth = _gridItemWidthForZoom(
        zoom,
        referenceWidth: referenceWidth,
        spacing: spacing,
        minWidth: gridMinWidth,
      );
      final columns = ((safeWidth + spacing) / (itemWidth + spacing)).floor();
      if (columns <= cappedColumns) {
        return zoom;
      }
    }

    return minValue;
  }

  static int maxGridSizeForContext(
    BuildContext context, {
    GridSizeMode mode = GridSizeMode.referenceWidth,
    double minItemWidth = defaultMinItemWidth,
    double spacing = defaultGridSpacing,
    double referenceWidth = defaultReferenceWidth,
    double gridMinWidth = defaultGridMinWidth,
    int minValue = UserPreferences.minGridZoomLevel,
    int maxValue = UserPreferences.maxGridZoomLevel,
  }) {
    final width = MediaQuery.of(context).size.width;
    return maxGridSize(
      availableWidth: width,
      mode: mode,
      minItemWidth: minItemWidth,
      spacing: spacing,
      referenceWidth: referenceWidth,
      gridMinWidth: gridMinWidth,
      minValue: minValue,
      maxValue: maxValue,
    );
  }

  static int clampGridSizeForWidth(
    int value, {
    required double availableWidth,
    GridSizeMode mode = GridSizeMode.referenceWidth,
    double minItemWidth = defaultMinItemWidth,
    double spacing = defaultGridSpacing,
    double referenceWidth = defaultReferenceWidth,
    double gridMinWidth = defaultGridMinWidth,
    int minValue = UserPreferences.minGridZoomLevel,
    int maxValue = UserPreferences.maxGridZoomLevel,
  }) {
    final maxSize = maxGridSize(
      availableWidth: availableWidth,
      mode: mode,
      minItemWidth: minItemWidth,
      spacing: spacing,
      referenceWidth: referenceWidth,
      gridMinWidth: gridMinWidth,
      minValue: minValue,
      maxValue: maxValue,
    );
    return value.clamp(minValue, maxSize).toInt();
  }

  static double _gridItemWidthForZoom(
    int zoom, {
    required double referenceWidth,
    required double spacing,
    required double minWidth,
  }) {
    final totalSpacing = spacing * (zoom - 1);
    return math.max(minWidth, (referenceWidth - totalSpacing) / zoom);
  }
}
