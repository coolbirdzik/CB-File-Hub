import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/widgets/tags_overlay.dart';

class GalleryMasonryTile extends StatelessWidget {
  final File file;
  final bool isSelected;
  final bool isSelectionMode;
  final List<String> tags;
  final int gridSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<double> Function(File) getAspectRatio;

  // PERFORMANCE: Static cache for aspect ratios to avoid FutureBuilder recalculation during scrolling
  static final Map<String, double> _aspectRatioCache = {};

  const GalleryMasonryTile({
    Key? key,
    required this.file,
    required this.isSelected,
    required this.isSelectionMode,
    required this.tags,
    required this.gridSize,
    required this.onTap,
    required this.onLongPress,
    required this.getAspectRatio,
  }) : super(key: key);

  /// Clear the aspect ratio cache (useful when switching directories)
  static void clearAspectRatioCache() {
    _aspectRatioCache.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = file.path.split(Platform.pathSeparator).last;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      // PERFORMANCE: Wrap in RepaintBoundary to isolate repaints
      child: RepaintBoundary(
        // PERFORMANCE: Check cache first to avoid FutureBuilder recalculation
        child: _aspectRatioCache.containsKey(file.path)
            ? _buildTileContent(_aspectRatioCache[file.path]!, theme, fileName)
            : FutureBuilder<double>(
                // PERFORMANCE: Use file path as key to cache aspect ratio results
                key: ValueKey('aspect-${file.path}'),
                future: getAspectRatio(file),
                builder: (context, snapshot) {
                  final ratio = snapshot.data ?? 1.0;
                  // Cache the aspect ratio once calculated
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData) {
                    _aspectRatioCache[file.path] = ratio;
                  }
                  return _buildTileContent(ratio, theme, fileName);
                },
              ),
      ),
    );
  }

  Widget _buildTileContent(double ratio, ThemeData theme, String fileName) {
    return Stack(
      children: [
        // Main image container with flat, borderless design
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
            child: AspectRatio(
              aspectRatio: ratio,
              child: Hero(
                tag: file.path,
                child: ThumbnailLoader(
                  filePath: file.path,
                  isVideo: false,
                  isImage: true,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(8),
                  fallbackBuilder: () => Center(
                    child: Icon(
                      PhosphorIconsLight.imageBroken,
                      size: 32,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Frosted glass filename label at bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.5),
                    ],
                  ),
                ),
                child: Text(
                  fileName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),

        if (tags.isNotEmpty) TagsOverlay(tags: tags, gridSize: gridSize),
        
        // Selection overlay with frosted glass effect
        if (isSelectionMode)
          Positioned(
            top: 8,
            right: 8,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSelected ? PhosphorIconsLight.checkCircle : PhosphorIconsLight.circle,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        
        // Subtle selection border
        if (isSelected)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}




