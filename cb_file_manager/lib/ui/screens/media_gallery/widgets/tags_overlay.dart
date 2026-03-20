import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/widgets/tag_chip.dart';

class TagsOverlay extends StatelessWidget {
  final List<String> tags;
  final int gridSize;
  final Function(String)? onTagTap;

  const TagsOverlay({
    Key? key,
    required this.tags,
    required this.gridSize,
    this.onTagTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    // Determine compactness and number of tags based on grid size
    bool verySmallGrid = gridSize >= 5;
    bool smallGrid = gridSize == 4;
    bool mediumGrid = gridSize == 3;
    bool largeGrid = gridSize <= 2;

    List<Widget> tagWidgets = [];
    int maxTagsToShow = 1;
    bool useCompactChips = true;

    if (largeGrid) {
      maxTagsToShow = 3;
      useCompactChips = false;
    } else if (mediumGrid) {
      maxTagsToShow = 2;
      useCompactChips = true;
    } else if (smallGrid) {
      maxTagsToShow = 1;
      useCompactChips = true;
    } else if (verySmallGrid) {
      // Only show icon and count for very small items with frosted glass
      return Positioned(
        bottom: 4,
        left: 4,
        right: 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsLight.tag, color: Colors.white, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    '${tags.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    for (int i = 0; i < tags.length && i < maxTagsToShow; i++) {
      tagWidgets.add(TagChip(
          tag: tags[i],
          isCompact: useCompactChips,
          onTap: onTagTap != null ? () => onTagTap!(tags[i]) : null));
    }

    if (tags.length > maxTagsToShow) {
      tagWidgets.add(Text(
        '+${tags.length - maxTagsToShow}',
        style:
            TextStyle(color: Colors.white, fontSize: useCompactChips ? 10 : 12),
      ));
    }

    return Positioned(
      bottom: 5,
      left: 5,
      right: 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              alignment: WrapAlignment.start,
              children: tagWidgets,
            ),
          ),
        ),
      ),
    );
  }
}




