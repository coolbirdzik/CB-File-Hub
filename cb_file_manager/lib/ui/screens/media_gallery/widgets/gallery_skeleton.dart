import 'package:flutter/material.dart';
import '../../../components/common/skeleton_helper.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';

/// Gallery skeleton for image/video gallery screens
/// Now uses unified skeleton system with automatic mobile/desktop adaptation
@Deprecated(
    'Use SkeletonHelper.mediaGallery() instead for consistent skeleton loading')
class GallerySkeleton extends StatelessWidget {
  final bool isGrid;
  final double thumbnailSize;

  const GallerySkeleton({
    Key? key,
    required this.isGrid,
    required this.thumbnailSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use unified skeleton system
    // Automatically handles mobile/desktop differences
    final maxCols = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.columns,
      minValue: UserPreferences.minThumbnailSize.round(),
      maxValue: UserPreferences.maxThumbnailSize.round(),
      spacing: 6.0,
    );
    final gridCols = thumbnailSize
        .round()
        .clamp(UserPreferences.minThumbnailSize.round(), maxCols)
        .toInt();
    return SkeletonHelper.mediaGallery(
      isGrid: isGrid,
      crossAxisCount: gridCols,
      itemCount: 12,
    );
  }
}
