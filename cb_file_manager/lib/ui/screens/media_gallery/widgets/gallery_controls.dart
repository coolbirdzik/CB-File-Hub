import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';

class GalleryControls extends StatelessWidget {
  final String? searchQuery;
  final VoidCallback onClearSearch;
  final bool isMasonry;
  final VoidCallback onToggleMasonry;

  const GalleryControls({
    Key? key,
    this.searchQuery,
    required this.onClearSearch,
    required this.isMasonry,
    required this.onToggleMasonry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    
    return Stack(
      children: [
        if (searchQuery != null && searchQuery!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIconsLight.magnifyingGlass, 
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${l10n.search}: "$searchQuery"',
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          PhosphorIconsLight.x, 
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: onClearSearch,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Masonry toggle with frosted glass effect
        Positioned(
          top: 8,
          right: 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onToggleMasonry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isMasonry ? PhosphorIconsLight.gridFour : PhosphorIconsLight.squaresFour,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isMasonry ? l10n.masonryLayoutName : l10n.viewModeGrid,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}




