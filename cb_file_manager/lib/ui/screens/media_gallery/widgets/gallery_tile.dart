import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/widgets/tags_overlay.dart';

class GalleryTile extends StatelessWidget {
  final File file;
  final bool isSelected;
  final bool isSelectionMode;
  final List<String> tags;
  final int gridSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const GalleryTile({
    Key? key,
    required this.file,
    required this.isSelected,
    required this.isSelectionMode,
    required this.tags,
    required this.gridSize,
    required this.onTap,
    required this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = file.path.split(Platform.pathSeparator).last;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: [
          // Main image container with flat, borderless design
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
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
          
          // Tags overlay
          if (tags.isNotEmpty) 
            TagsOverlay(tags: tags, gridSize: gridSize),
          
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
                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          
          // Subtle hover/selection border
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
      ),
    );
  }
}




