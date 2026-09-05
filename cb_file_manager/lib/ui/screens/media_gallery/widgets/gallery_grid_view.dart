import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/widgets/gallery_tile.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/widgets/gallery_masonry_tile.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';

class GalleryGridView extends StatelessWidget {
  final List<File> imageFiles;
  final Map<String, List<String>> fileTagsMap;
  final Set<String> selectedFilePaths;
  final bool isSelectionMode;
  final bool isMasonry;
  final double thumbnailSize;
  final Function(File, int) onTap;
  final Function(File) onLongPress;
  final Future<double> Function(File) getAspectRatio;

  const GalleryGridView({
    super.key,
    required this.imageFiles,
    required this.fileTagsMap,
    required this.selectedFilePaths,
    required this.isSelectionMode,
    required this.isMasonry,
    required this.thumbnailSize,
    required this.onTap,
    required this.onLongPress,
    required this.getAspectRatio,
  });

  @override
  Widget build(BuildContext context) {
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

    if (isMasonry) {
      return MasonryGridView.count(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        crossAxisCount: gridCols,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        itemCount: imageFiles.length,
        itemBuilder: (context, index) {
          final file = imageFiles[index];
          final isSelected = selectedFilePaths.contains(file.path);
          final tags = fileTagsMap[file.path] ?? [];
          // PERFORMANCE: Wrap each tile in RepaintBoundary to isolate repaints
          return RepaintBoundary(
            child: GalleryMasonryTile(
              key: ValueKey(file.path), // Add key for better widget reuse
              file: file,
              isSelected: isSelected,
              isSelectionMode: isSelectionMode,
              tags: tags,
              gridSize: gridCols,
              onTap: () => onTap(file, index),
              onLongPress: () => onLongPress(file),
              getAspectRatio: getAspectRatio,
            ),
          );
        },
      );
    }

    final childAspect = gridCols >= 4
        ? 1.0
        : 0.9; // More square on denser grids
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridCols,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: childAspect,
      ),
      itemCount: imageFiles.length,
      itemBuilder: (context, index) {
        final file = imageFiles[index];
        final isSelected = selectedFilePaths.contains(file.path);
        final tags = fileTagsMap[file.path] ?? [];
        // PERFORMANCE: Wrap each tile in RepaintBoundary to isolate repaints
        return RepaintBoundary(
          child: GalleryTile(
            key: ValueKey(file.path), // Add key for better widget reuse
            file: file,
            isSelected: isSelected,
            isSelectionMode: isSelectionMode,
            tags: tags,
            gridSize: gridCols,
            onTap: () => onTap(file, index),
            onLongPress: () => onLongPress(file),
          ),
        );
      },
    );
  }
}
