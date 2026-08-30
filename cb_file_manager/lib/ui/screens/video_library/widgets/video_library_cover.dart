import 'dart:io';

import 'package:flutter/material.dart';

/// Displays a video library cover image, falling back to a tinted gradient
/// placeholder (with an optional label) when no cover is set or the image
/// file cannot be loaded.
class VideoLibraryCover extends StatelessWidget {
  final String? coverImagePath;
  final IconData placeholderIcon;
  final Color accentColor;
  final String? placeholderLabel;

  const VideoLibraryCover({
    Key? key,
    required this.coverImagePath,
    required this.placeholderIcon,
    required this.accentColor,
    this.placeholderLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final coverPath = coverImagePath;
    if (coverPath != null) {
      return Image.file(
        File(coverPath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(context),
      );
    }
    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              accentColor.withValues(alpha: 0.28),
              cs.surfaceContainerHigh,
            ),
            Color.alphaBlend(
              accentColor.withValues(alpha: 0.10),
              cs.surfaceContainer,
            ),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              placeholderIcon,
              size: 40,
              color: accentColor.withValues(alpha: 0.8),
            ),
            if (placeholderLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                placeholderLabel!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
