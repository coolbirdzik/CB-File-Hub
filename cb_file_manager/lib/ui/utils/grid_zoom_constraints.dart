import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';

enum GridSizeMode {
  columns,
  referenceWidth,
}

class GridZoomConstraints {
  static const double defaultGridSpacing = 8.0;
  static const double defaultReferenceWidth = 960.0;
  static const double defaultMinItemWidth = 72.0;
  static const double defaultGridMinWidth = 56.0;

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
    final maxColumns =
        ((safeWidth + spacing) / (minItemWidth + spacing)).floor();
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
