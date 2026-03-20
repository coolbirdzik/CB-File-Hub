import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';

/// Horizontal scrollable tag filter bar for filtering videos by tags
class VideoTagFilterBar extends StatefulWidget {
  final Set<String> selectedTags;
  final Function(Set<String>) onTagsChanged;
  final String? libraryPath;
  final bool globalSearch;

  const VideoTagFilterBar({
    Key? key,
    required this.selectedTags,
    required this.onTagsChanged,
    this.libraryPath,
    this.globalSearch = false,
  }) : super(key: key);

  @override
  State<VideoTagFilterBar> createState() => _VideoTagFilterBarState();
}

class _VideoTagFilterBarState extends State<VideoTagFilterBar> {
  List<String> _availableTags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() {
      _isLoading = true;
    });

    List<String> tags;
    if (widget.globalSearch || widget.libraryPath == null) {
      // Get all unique tags from the system
      tags = await TagManager.getRecentTags(limit: 50);
    } else {
      // Get tags from specific directory
      tags = (await TagManager.getAllUniqueTags(widget.libraryPath!)).toList();
    }

    if (mounted) {
      setState(() {
        _availableTags = tags;
        _isLoading = false;
      });
    }
  }

  void _toggleTag(String tag) {
    final newSelectedTags = Set<String>.from(widget.selectedTags);
    if (newSelectedTags.contains(tag)) {
      newSelectedTags.remove(tag);
    } else {
      newSelectedTags.add(tag);
    }
    widget.onTagsChanged(newSelectedTags);
  }

  void _clearAllTags() {
    widget.onTagsChanged({});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    if (_isLoading) {
      return Container(
        height: 50,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    if (_availableTags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Filter label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.funnelSimple,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  localizations.filterByTags,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

          // Tag chips scrollable list
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _availableTags.length,
              itemBuilder: (context, index) {
                final tag = _availableTags[index];
                final isSelected = widget.selectedTags.contains(tag);

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(tag),
                    selected: isSelected,
                    onSelected: (_) => _toggleTag(tag),
                    selectedColor: theme.colorScheme.primaryContainer,
                    checkmarkColor: theme.colorScheme.primary,
                    showCheckmark: true,
                  ),
                );
              },
            ),
          ),

          // Clear button
          if (widget.selectedTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                onPressed: _clearAllTags,
                icon: const Icon(PhosphorIconsLight.x, size: 18),
                label: Text(localizations.clearTagFilter),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
