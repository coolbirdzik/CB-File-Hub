import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';

/// Mobile search dialog with same functionality as desktop search
/// Supports:
/// - Search by filename
/// - Search by tag (#tagname)
/// - Global search toggle
/// - Tag autocomplete
class MobileSearchDialog extends StatefulWidget {
  final String currentPath;
  final String? initialQuery;
  final Function(String query, bool isGlobalSearch) onSearch;
  final VoidCallback? onClear;

  const MobileSearchDialog({
    Key? key,
    required this.currentPath,
    this.initialQuery,
    required this.onSearch,
    this.onClear,
  }) : super(key: key);

  @override
  State<MobileSearchDialog> createState() => _MobileSearchDialogState();
}

class _MobileSearchDialogState extends State<MobileSearchDialog> {
  late TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  bool _isGlobalSearch = false;

  // Cache popular tags to avoid loading every time
  static List<String>? _cachedPopularTags;
  static DateTime? _cacheTime;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _searchController.addListener(_onSearchChanged);

    // Load popular tags asynchronously (don't block UI)
    Future.microtask(() => _loadPopularTags());

    // Delay auto focus to avoid lag (keyboard animation is expensive)
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadPopularTags() async {
    try {
      // Use cache if available and fresh (< 5 minutes old)
      if (_cachedPopularTags != null &&
          _cacheTime != null &&
          DateTime.now().difference(_cacheTime!) < const Duration(minutes: 5)) {
        return;
      }

      // Load from database
      final popularTags = await TagManager.instance.getPopularTags(limit: 10);
      final tagList = popularTags.keys.toList();

      // Update cache
      _cachedPopularTags = tagList;
      _cacheTime = DateTime.now();
    } catch (e) {
      debugPrint('Error loading popular tags: $e');
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();

    // Tag-aware behaviour kept for potential future use; currently a no-op.
    if (query.contains('#')) {
      final int hashPosition = query.lastIndexOf('#');
      final String tagQuery = query.substring(hashPosition + 1).trim();
      _updateTagSuggestions(tagQuery);
    }
  }

  Future<void> _updateTagSuggestions(String tagQuery) async {
    // Tag suggestions are currently disabled for performance.
    // This method is kept for potential future use.
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      Navigator.pop(context);
      widget.onSearch(query, _isGlobalSearch);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    widget.onClear?.call();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    // Use AlertDialog for smooth performance
    return AlertDialog(
      backgroundColor: theme.scaffoldBackgroundColor,
      contentPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            localizations.search,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 16),

          // Search field
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: false, // Don't auto focus to avoid keyboard lag
            style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: localizations.searchByNameOrTag,
              hintStyle: TextStyle(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              prefixIcon: Icon(
                PhosphorIconsLight.magnifyingGlass,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(PhosphorIconsLight.x, size: 20),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16.0),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16.0),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onSubmitted: (_) => _performSearch(),
          ),

          const SizedBox(height: 12),

          // Global search toggle
          InkWell(
            onTap: () {
              setState(() {
                _isGlobalSearch = !_isGlobalSearch;
              });
            },
            borderRadius: BorderRadius.circular(16.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: _isGlobalSearch,
                    onChanged: (value) {
                      setState(() {
                        _isGlobalSearch = value ?? false;
                      });
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizations.globalSearch,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          _isGlobalSearch
                              ? localizations.searchInAllFolders
                              : localizations.searchInCurrentFolder,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tag suggestions (hidden to improve performance)
          // Tag autocomplete disabled for now
          // if (_isSearchingTags && _currentTags.isNotEmpty) ...[
          //   ...
          // ],

          // Search tips (hidden to improve performance)
          // if (!_isSearchingTags && _searchController.text.isEmpty) ...[
          //   const SizedBox(height: 12),
          //   Container(...),
          // ],

          const SizedBox(height: 16),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Clear button (if has query)
              if (_searchController.text.isNotEmpty)
                TextButton(
                  onPressed: _clearSearch,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  child: Text(
                    localizations.clearSearch.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),

              if (_searchController.text.isNotEmpty) const SizedBox(width: 12),

              // Cancel button
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
                child: Text(
                  localizations.cancel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Search button
              FilledButton(
                onPressed: _performSearch,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
                child: Text(
                  localizations.search.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // _buildTip helper removed as current UI doesn't render tips
}
