import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Handles keyboard events.
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart'; // Add TabManager import
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'search_tips_dialog.dart';

/// Search bar displayed directly in the toolbar.
class SearchBar extends StatefulWidget {
  final String currentPath;
  final VoidCallback onCloseSearch;
  final String tabId; // Add tabId property
  final String? initialQuery;
  final ValueChanged<String>? onSearch;
  final void Function(String query, bool useRegex)? onSearchWithOptions;
  final void Function(List<String> tags, bool isGlobalSearch)? onTagSearch;
  final ValueChanged<String>? onQueryChanged;
  final VoidCallback? onClearSearch;
  final String? hintText;
  final bool showTipsButton;
  final bool showTagSearch;
  final bool showGlobalSearchToggle;
  final bool showRegexToggle;
  final bool showClearButton;

  /// Optional: provide the [FolderListBloc] directly so the widget works
  /// even when rendered outside its normal [BlocProvider] subtree
  /// (e.g. in the shared app bar of the split-pane view).
  final FolderListBloc? folderListBloc;

  const SearchBar({
    Key? key,
    required this.currentPath,
    required this.onCloseSearch,
    required this.tabId, // Include tabId in constructor
    this.folderListBloc,
    this.initialQuery,
    this.onSearch,
    this.onSearchWithOptions,
    this.onTagSearch,
    this.onQueryChanged,
    this.onClearSearch,
    this.hintText,
    this.showTipsButton = true,
    this.showTagSearch = true,
    this.showGlobalSearchToggle = true,
    this.showRegexToggle = true,
    this.showClearButton = false,
  }) : super(key: key);

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _suggestionsLink = LayerLink();
  final Object _tapRegionGroupId = Object();
  bool _isSearchingTags = false;
  List<String> _suggestedTags = [];
  bool _isGlobalSearch = false;
  bool _useRegex = false;
  double _suggestionsWidth = 320;

  // Stores the active autocomplete overlay.
  OverlayEntry? _overlayEntry;

  // Tracks the selected tag in the suggestion list.
  int _selectedTagIndex = -1;
  List<String> _currentTags = [];

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery ?? '';
    // Focus the search field when it appears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });

    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);

    // Load popular tags.
    _loadPopularTags();
  }

  @override
  void didUpdateWidget(SearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabId != widget.tabId ||
        oldWidget.currentPath != widget.currentPath) {
      _removeOverlay();
    }
    if (oldWidget.initialQuery != widget.initialQuery &&
        widget.initialQuery != _searchController.text) {
      final query = widget.initialQuery ?? '';
      _searchController.text = query;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: query.length),
      );
    }
  }

  Future<void> _loadPopularTags() async {
    try {
      final popularTags = await TagManager.instance.getPopularTags(limit: 10);
      setState(() {
        _suggestedTags = popularTags.keys.toList();
      });
    } catch (e) {
      debugPrint('Error loading popular tags: $e');
    }
  }

  @override
  void deactivate() {
    _removeOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    // Remove the overlay before disposing the widget.
    _removeOverlay();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // Removes the autocomplete overlay when it is no longer needed.
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updateSuggestionsGeometry() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      _removeOverlay();
      return;
    }

    _suggestionsWidth =
        (renderObject.size.width - 24).clamp(0, double.infinity).toDouble();
  }

  void _onSearchFocusChanged() {
    if (!_searchFocusNode.hasFocus) {
      _removeOverlay();
    }
  }

  void _handleTapOutside() {
    _removeOverlay();
    _searchFocusNode.unfocus();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    widget.onQueryChanged?.call(_searchController.text);

    if (!widget.showTagSearch) {
      setState(() {
        _isSearchingTags = false;
      });
      _removeOverlay();
      return;
    }

    // Check whether this is a tag search.
    if (query.contains('#')) {
      final int hashPosition = query.lastIndexOf('#');
      final String tagQuery = query.substring(hashPosition + 1).trim();

      // Show or update autocomplete suggestions while typing after #.
      if (_searchFocusNode.hasFocus) {
        // Update results if the overlay is already visible.
        if (_overlayEntry != null) {
          _updateTagSuggestions(tagQuery);
        } else if (query.endsWith('#') || tagQuery.isNotEmpty) {
          // Show suggestions after # or after the first tag character.
          _showTagSuggestionsDialog(tagQuery);
        }
      }

      setState(() {
        _isSearchingTags = true;
      });
    } else {
      setState(() {
        _isSearchingTags = false;
      });
      // Close the overlay when this is no longer a tag search.
      _removeOverlay();
    }
  }

  // Updates tag suggestions based on the current input.
  Future<void> _updateTagSuggestions(String tagQuery) async {
    if (!_searchFocusNode.hasFocus) {
      _removeOverlay();
      return;
    }

    List<String> tags = [];

    if (tagQuery.isEmpty) {
      // Show popular tags when there is no query.
      tags = _suggestedTags;
    } else {
      // Search for tags matching the query.
      tags = await TagManager.instance.searchTags(tagQuery);
    }

    // Update the tag list and UI.
    if (mounted) {
      setState(() {
        _currentTags = List.from(tags);
        // Reset selection when the list changes.
        _selectedTagIndex = tags.isNotEmpty ? 0 : -1;
      });

      // Update the overlay if it is visible.
      _updateOverlay();
    }
  }

  // Shows tag suggestions in an overlay so input remains usable.
  void _showTagSuggestionsDialog(String tagQuery) async {
    if (!_searchFocusNode.hasFocus) return;

    // Remove any existing overlay first.
    _removeOverlay();

    // Search for matching tags.
    List<String> tags = [];
    if (tagQuery.isEmpty) {
      tags = _suggestedTags;
    } else {
      tags = await TagManager.instance.searchTags(tagQuery);
    }

    // Do not show an empty popular-tag popup.
    if (tags.isEmpty && tagQuery.isEmpty) return;

    // Stop if the widget was disposed while waiting.
    if (!mounted) return;

    final localizations = AppLocalizations.of(context)!;

    // Reset the selected tag index.
    _selectedTagIndex = tags.isNotEmpty ? 0 : -1;
    _currentTags = List.from(tags);
    _updateSuggestionsGeometry();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Create a new overlay entry.
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: CompositedTransformFollower(
            link: _suggestionsLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(12, 4),
            child: Align(
              alignment: Alignment.topLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: TextFieldTapRegion(
                child: TapRegion(
                  groupId: _tapRegionGroupId,
                  child: SizedBox(
                    width: _suggestionsWidth,
                    child: Material(
                      elevation: 0,
                      borderRadius: BorderRadius.circular(16),
                      color:
                          isDark ? Colors.grey[850] : theme.colorScheme.surface,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey[850]
                              : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [],
                          border: Border.all(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        constraints: const BoxConstraints(
                          maxHeight: 300,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${localizations.suggestedTags} (${_currentTags.length} ${localizations.results})',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  // Close overlay.
                                  InkWell(
                                    onTap: _removeOverlay,
                                    borderRadius: BorderRadius.circular(16.0),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Icon(
                                        PhosphorIconsLight.x,
                                        size: 16,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, thickness: 1),
                            _currentTags.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      localizations.noMatchingTags,
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : Flexible(
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      itemCount: _currentTags.length,
                                      itemBuilder: (context, index) {
                                        final bool isSelected =
                                            index == _selectedTagIndex;
                                        return InkWell(
                                          onTap: () {
                                            _applySelectedTag(
                                              _currentTags[index],
                                              submitSearch: true,
                                            );
                                            _removeOverlay();
                                          },
                                          child: Container(
                                            color: isSelected
                                                ? theme.colorScheme
                                                    .primaryContainer
                                                : Colors.transparent,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8.0,
                                                horizontal: 16.0),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  PhosphorIconsLight
                                                      .shoppingBagOpen,
                                                  size: 16,
                                                  color: isSelected
                                                      ? theme
                                                          .colorScheme.primary
                                                      : theme
                                                          .colorScheme.primary
                                                          .withValues(
                                                              alpha: 0.7),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    _currentTags[index],
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: isSelected
                                                          ? theme.colorScheme
                                                              .onPrimaryContainer
                                                          : theme.colorScheme
                                                              .onSurface,
                                                      fontWeight: isSelected
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                ),
                                                if (isSelected)
                                                  Icon(
                                                    PhosphorIconsLight
                                                        .arrowRight,
                                                    size: 14,
                                                    color: theme
                                                        .colorScheme.primary,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
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
          ),
        );
      },
    );

    // Show the overlay.
    Overlay.of(context).insert(_overlayEntry!);

    // Keep focus in the text field so keyboard navigation keeps working.
    _searchFocusNode.requestFocus();
  }

  // Applies the selected tag to the text input.
  void _applySelectedTag(String tag, {bool submitSearch = false}) {
    if (!mounted) return;

    // Update the text input with the selected tag.
    final text = _searchController.text;
    final hashIndex = text.lastIndexOf('#');
    final newText = '${text.substring(0, hashIndex + 1)}$tag ';

    // Update the text and caret position.
    setState(() {
      _searchController.text = newText;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
    });

    if (submitSearch) {
      _performSearch();
    }

    // Keep the field focused after updating the text.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  // Parses the search query and extracts multiple tags.
  List<String> _extractTags(String query) {
    List<String> tags = [];

    // Use regex to find all patterns that start with # and continue until another # or end of string
    RegExp tagRegex = RegExp(r'#([^\s#][^#]*?)(?=\s+#|\s*$)');
    final matches = tagRegex.allMatches(query);

    for (var match in matches) {
      if (match.group(1) != null && match.group(1)!.isNotEmpty) {
        // Trim trailing whitespace but preserve spaces within the tag
        String tag = match.group(1)!.trimRight();
        if (tag.isNotEmpty) {
          tags.add(tag);
        }
      }
    }

    // If no matches found using the regex, fallback to simpler method
    if (tags.isEmpty) {
      // Check if there's a single tag in the query
      if (query.startsWith('#') && query.length > 1) {
        String tag = query.substring(1).trim();
        if (tag.isNotEmpty) {
          tags.add(tag);
        }
      }
    }

    // Remove duplicates
    return tags.toSet().toList();
  }

  void _performSearch() {
    if (_searchController.text.isEmpty) {
      return;
    }

    final query = _searchController.text;

    // Check if it's a tag search (contains # character)
    if (_isSearchingTags || query.contains('#')) {
      // Extract all tags from the query
      List<String> tags = _extractTags(query);

      // If no valid tags were found, don't search
      if (tags.isEmpty) {
        return;
      }

      if (widget.onTagSearch != null) {
        widget.onTagSearch!(tags, _isGlobalSearch);
        return;
      }

      // Get the current path before performing search
      final currentPath = widget.currentPath;
      final folderListBloc =
          widget.folderListBloc ?? BlocProvider.of<FolderListBloc>(context);
      final tabBloc = BlocProvider.of<TabManagerBloc>(context);
      // Add the current path to tab history before performing the search
      // This will allow back button to return to the normal view
      tabBloc.add(AddToTabHistory(widget.tabId, currentPath));

      // Check if user wants a global search
      if (_isGlobalSearch) {
        // Use the new event for global multi-tag search
        if (tags.length == 1) {
          // If only one tag, use the existing single tag search
          folderListBloc.add(SearchByTagGlobally(tags.first));
        } else {
          // If multiple tags, use the new multi-tag search
          folderListBloc.add(SearchByMultipleTagsGlobally(tags));
        }
      } else {
        // Use the new event for local multi-tag search
        if (tags.length == 1) {
          // If only one tag, use the existing single tag search
          folderListBloc.add(SearchByTag(tags.first));
        } else {
          // If multiple tags, use the new multi-tag search
          folderListBloc.add(SearchByMultipleTags(tags));
        }
      }
    } else {
      if (widget.onSearchWithOptions != null) {
        widget.onSearchWithOptions!(_searchController.text, _useRegex);
        return;
      }

      if (widget.onSearch != null) {
        widget.onSearch!(_searchController.text);
        return;
      }

      // Get the current path before performing search
      final currentPath = widget.currentPath;
      final folderListBloc =
          widget.folderListBloc ?? BlocProvider.of<FolderListBloc>(context);
      final tabBloc = BlocProvider.of<TabManagerBloc>(context);

      // Add the current path to tab history before performing the search
      // This will allow back button to return to the normal view
      tabBloc.add(AddToTabHistory(widget.tabId, currentPath));

      // Search by file name.
      folderListBloc.add(
        SearchByFileName(
          query,
          recursive: _isGlobalSearch,
          useRegex: _useRegex,
        ),
      );
    }
  }

  // Shows the search tips dialog.
  void _showSearchTipsDialog(BuildContext context) {
    showSearchTipsDialog(context);
  }

  // Refreshes the overlay after selection changes.
  void _updateOverlay() {
    if (_overlayEntry != null) {
      _updateSuggestionsGeometry();
      _overlayEntry!.markNeedsBuild();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final localizations = AppLocalizations.of(context)!;

    return TapRegion(
      groupId: _tapRegionGroupId,
      onTapOutside: (_) => _handleTapOutside(),
      child: CompositedTransformTarget(
        link: _suggestionsLink,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 48,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [],
            border: Border.all(
              color: _isSearchingTags
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 4),
              // Animated icon that changes between search and tag
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: _isSearchingTags
                    ? Icon(
                        PhosphorIconsLight.shoppingBagOpen,
                        key: const ValueKey('tagIcon'),
                        color: theme.colorScheme.primary,
                      )
                    : Icon(
                        PhosphorIconsLight.magnifyingGlass,
                        key: const ValueKey('searchIcon'),
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
              ),
              Expanded(
                child: Focus(
                  // Handle navigation keys for the autocomplete overlay.
                  onKeyEvent: (FocusNode node, KeyEvent event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      // ESC closes tag suggestions first, then closes search mode.
                      if (_overlayEntry != null) {
                        _removeOverlay();
                      } else {
                        widget.onCloseSearch();
                      }
                      return KeyEventResult.handled;
                    }

                    if (_overlayEntry != null &&
                        _currentTags.isNotEmpty &&
                        _isSearchingTags) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          setState(() {
                            if (_selectedTagIndex < _currentTags.length - 1) {
                              _selectedTagIndex++;
                            } else {
                              _selectedTagIndex = 0;
                            }
                          });
                          _updateOverlay();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowUp) {
                          setState(() {
                            if (_selectedTagIndex > 0) {
                              _selectedTagIndex--;
                            } else {
                              _selectedTagIndex = _currentTags.length - 1;
                            }
                          });
                          _updateOverlay();
                          return KeyEventResult.handled;
                        } else if ((event.logicalKey ==
                                    LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.tab) &&
                            _selectedTagIndex >= 0) {
                          // Select the highlighted tag with Enter or Tab.
                          _applySelectedTag(_currentTags[_selectedTagIndex]);
                          _removeOverlay();
                          return KeyEventResult.handled;
                        }
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: TextStyle(
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: _isSearchingTags
                          ? localizations.searchHintTextTags
                          : widget.hintText ?? localizations.searchHintText,
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
              ),
              // Tips button
              if (widget.showTipsButton)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showSearchTipsDialog(context),
                    child: Tooltip(
                      message: AppLocalizations.of(context)!.searchTips,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          PhosphorIconsLight.info,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              // Tag suggestion button - Only show when in tag search mode
              if (widget.showTagSearch && _isSearchingTags)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      _searchFocusNode.requestFocus();
                      final query = _searchController.text;
                      if (query.contains('#')) {
                        final hashPosition = query.lastIndexOf('#');
                        final tagQuery =
                            query.substring(hashPosition + 1).trim();
                        _showTagSuggestionsDialog(tagQuery);
                      }
                    },
                    child: Tooltip(
                      message: AppLocalizations.of(context)!.viewTagSuggestions,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          PhosphorIconsLight.listBullets,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              // Global search toggle button
              if (widget.showGlobalSearchToggle)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                        _isGlobalSearch = !_isGlobalSearch;
                      });
                      // Show a short snackbar when switching modes.
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(_isGlobalSearch
                              ? AppLocalizations.of(context)!
                                  .globalSearchModeEnabled
                              : AppLocalizations.of(context)!
                                  .localSearchModeEnabled),
                          duration: const Duration(milliseconds: 1000),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          margin: const EdgeInsets.all(8),
                        ),
                      );
                    },
                    child: Tooltip(
                      message: _isGlobalSearch
                          ? AppLocalizations.of(context)!.globalSearchMode
                          : AppLocalizations.of(context)!.localSearchMode,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _isGlobalSearch
                              ? Icon(
                                  PhosphorIconsLight.globe,
                                  key: const ValueKey('globalIcon'),
                                  color: theme.colorScheme.primary,
                                  size: 20,
                                )
                              : Icon(
                                  PhosphorIconsLight.folder,
                                  key: const ValueKey('folderIcon'),
                                  size: 20,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Regex toggle button - only for filename search
              if (widget.showRegexToggle && !_isSearchingTags)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                        _useRegex = !_useRegex;
                      });
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(_useRegex
                              ? AppLocalizations.of(context)!.regexModeEnabled
                              : AppLocalizations.of(context)!
                                  .regexModeDisabled),
                          duration: const Duration(milliseconds: 1000),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          margin: const EdgeInsets.all(8),
                        ),
                      );
                    },
                    child: Tooltip(
                      message: AppLocalizations.of(context)!.regexMode,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          PhosphorIconsLight.bracketsCurly,
                          color: _useRegex
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              // Search button
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _performSearch,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(
                      PhosphorIconsLight.magnifyingGlass,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                ),
              ),
              if (widget.showClearButton && _searchController.text.isNotEmpty)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      _searchController.clear();
                      widget.onClearSearch?.call();
                    },
                    child: Tooltip(
                      message: AppLocalizations.of(context)!.clearSearch,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          PhosphorIconsLight.broom,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
