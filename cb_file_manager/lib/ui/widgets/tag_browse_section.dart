import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

/// Layout used by [TagBrowseSection].
enum TagBrowseViewMode { tree, grid }

/// One visible line of the browse tree.
class _BrowseRow {
  const _BrowseRow({
    required this.normalized,
    required this.display,
    required this.depth,
    required this.childCount,
    required this.isExpanded,
  });

  final String normalized;
  final String display;
  final int depth;
  final int childCount;
  final bool isExpanded;

  bool get hasChildren => childCount > 0;
}

/// Hierarchical tag browser: lists the whole tag catalog as a parent/child tree
/// with a local filter, expand/collapse, and tap-to-assign.
///
/// Used by the tag assignment dialogs as the "browse" counterpart of the quick
/// picks row. Reads [TagHierarchyManager] for the tree and
/// [TagManager.getAllUniqueTags] for the flat catalog (so standalone tags and
/// tags without hierarchy still show up as roots).
class TagBrowseSection extends StatefulWidget {
  const TagBrowseSection({
    Key? key,
    required this.onTagSelected,
    this.selectedTags = const <String>[],
    this.maxHeight = 260,
  }) : super(key: key);

  /// Called with the original-cased tag name when a row is tapped.
  final ValueChanged<String> onTagSelected;

  /// Tags already assigned in the host dialog (shown with a check mark).
  final List<String> selectedTags;

  /// Height budget for the scrollable tree/grid area.
  final double maxHeight;

  @override
  State<TagBrowseSection> createState() => _TagBrowseSectionState();
}

class _TagBrowseSectionState extends State<TagBrowseSection> {
  /// Persisted layout choice so the dialog reopens in the same mode.
  static const String _viewModePrefsKey = 'tag_browse_view_mode';

  final _hierarchyManager = TagHierarchyManager.instance;
  final _thumbnailManager = TagThumbnailManager.instance;
  final _colorManager = TagColorManager.instance;
  final TextEditingController _searchController = TextEditingController();

  /// normalized tag -> display (original casing) name.
  Map<String, String> _display = <String, String>{};

  /// Tags with no parent, sorted by display name.
  List<String> _roots = <String>[];

  final Set<String> _expanded = <String>{};

  /// Grid drill-down path (normalized tags). Empty means "at the roots".
  final List<String> _gridPath = <String>[];

  TagBrowseViewMode _viewMode = TagBrowseViewMode.tree;
  String _query = '';
  bool _isLoading = true;

  /// Pending single-tap used to tell a click apart from a double-click on
  /// desktop, mirroring the tag management screen's 250ms window.
  Timer? _singleTapTimer;
  String? _pendingTapTag;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _load();
    _loadViewMode();
    _hierarchyManager.addListener(_handleHierarchyChanged);
  }

  Future<void> _loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_viewModePrefsKey);
      if (stored == null || !mounted) return;
      final mode = TagBrowseViewMode.values.firstWhere(
        (value) => value.name == stored,
        orElse: () => TagBrowseViewMode.tree,
      );
      if (mode == _viewMode) return;
      setState(() => _viewMode = mode);
    } catch (error) {
      AppLogger.warning('[TagBrowse] Failed to read view mode: $error');
    }
  }

  Future<void> _setViewMode(TagBrowseViewMode mode) async {
    if (mode == _viewMode) return;
    setState(() {
      _viewMode = mode;
      if (mode == TagBrowseViewMode.grid) {
        _gridPath.clear();
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewModePrefsKey, mode.name);
    } catch (error) {
      AppLogger.warning('[TagBrowse] Failed to persist view mode: $error');
    }
  }

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    _hierarchyManager.removeListener(_handleHierarchyChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleHierarchyChanged() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    try {
      await Future.wait([
        _hierarchyManager.initialize(),
        _thumbnailManager.initialize(),
      ]);

      final allTags = await TagManager.getAllUniqueTags('');
      final display = <String, String>{};

      void register(String tag) {
        final trimmed = tag.trim();
        if (trimmed.isEmpty) return;
        display.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
      }

      for (final tag in allTags) {
        register(tag);
      }
      // Hierarchy nodes are stored normalized; make sure they exist as rows even
      // when no file currently carries them.
      for (final entry in _hierarchyManager.getHierarchyTree().entries) {
        register(entry.key);
        for (final child in entry.value) {
          register(child);
        }
      }

      final roots = display.keys
          .where(
              (normalized) => _hierarchyManager.getParents(normalized).isEmpty)
          .toList();
      roots.sort((a, b) => _compareDisplay(display, a, b));

      if (!mounted) return;
      setState(() {
        _display = display;
        _roots = roots;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        '[TagBrowse] Failed to load tag tree',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  int _compareDisplay(Map<String, String> display, String a, String b) {
    final aName = (display[a] ?? a).toLowerCase();
    final bName = (display[b] ?? b).toLowerCase();
    return aName.compareTo(bName);
  }

  String _nameOf(String normalized) => _display[normalized] ?? normalized;

  bool _isSelected(String normalized) {
    return widget.selectedTags
        .any((tag) => tag.trim().toLowerCase() == normalized);
  }

  /// Tags matching the current query plus all of their ancestors, so matches
  /// stay reachable in the tree. Returns null when no filter is active.
  Set<String>? _filterSet() {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return null;

    final keep = <String>{};
    for (final normalized in _display.keys) {
      if (_nameOf(normalized).toLowerCase().contains(needle)) {
        keep.add(normalized);
        _collectAncestors(normalized, keep, <String>{});
      }
    }
    return keep;
  }

  void _collectAncestors(
      String normalized, Set<String> into, Set<String> seen) {
    if (!seen.add(normalized)) return;
    for (final parent in _hierarchyManager.getParents(normalized)) {
      into.add(parent);
      _collectAncestors(parent, into, seen);
    }
  }

  List<_BrowseRow> _buildRows() {
    final filter = _filterSet();
    final rows = <_BrowseRow>[];

    void walk(String normalized, int depth, Set<String> path) {
      if (filter != null && !filter.contains(normalized)) return;
      if (!path.add(normalized)) return; // cycle guard

      final children = _hierarchyManager.getChildren(normalized).toList()
        ..sort((a, b) => _compareDisplay(_display, a, b));
      final visibleChildren = filter == null
          ? children
          : children.where(filter.contains).toList(growable: false);

      // While filtering, keep the path to matches open automatically.
      final isExpanded = filter != null ? true : _expanded.contains(normalized);

      rows.add(_BrowseRow(
        normalized: normalized,
        display: _nameOf(normalized),
        depth: depth,
        childCount: visibleChildren.length,
        isExpanded: isExpanded,
      ));

      if (isExpanded) {
        for (final child in visibleChildren) {
          walk(child, depth + 1, path);
        }
      }

      path.remove(normalized);
    }

    for (final root in _roots) {
      walk(root, 0, <String>{});
    }
    return rows;
  }

  void _toggle(String normalized) {
    setState(() {
      if (!_expanded.remove(normalized)) {
        _expanded.add(normalized);
      }
    });
  }

  // ── Grid mode ────────────────────────────────────────────────────────────

  /// Tags shown by the grid at the current drill-down level.
  ///
  /// With an active query the grid goes flat and lists every match, so a tag
  /// buried deep in the tree is still one tap away.
  List<String> _gridEntries() {
    final filter = _filterSet();
    if (filter != null) {
      final needle = _query.trim().toLowerCase();
      final matches = _display.keys
          .where((n) => _nameOf(n).toLowerCase().contains(needle))
          .toList();
      matches.sort((a, b) => _compareDisplay(_display, a, b));
      return matches;
    }

    if (_gridPath.isEmpty) {
      return _roots;
    }

    final children = _hierarchyManager.getChildren(_gridPath.last).toList()
      ..sort((a, b) => _compareDisplay(_display, a, b));
    return children;
  }

  void _enterGridFolder(String normalized) {
    setState(() {
      _gridPath.add(normalized);
    });
  }

  void _popGridTo(int depth) {
    setState(() {
      _gridPath.removeRange(depth, _gridPath.length);
    });
  }

  /// Double-click behavior, mirroring the tag management screen: activating a
  /// parent tag drills into its children, activating a leaf falls back to
  /// assigning it (there is nothing to open inside a leaf here).
  ///
  /// In grid mode "drill" means navigating into the tag; in tree mode it means
  /// expanding the node.
  void _activateTag(String normalized) {
    final hasChildren = _hierarchyManager.getChildren(normalized).isNotEmpty;
    if (!hasChildren) {
      widget.onTagSelected(_nameOf(normalized));
      return;
    }

    if (_viewMode == TagBrowseViewMode.tree) {
      // While filtering, the tree is force-expanded, so there is nothing to do.
      if (_query.trim().isEmpty && !_expanded.contains(normalized)) {
        _toggle(normalized);
      }
      return;
    }

    _drillIntoGrid(normalized);
  }

  /// Navigates the grid to the children of [normalized], clearing an active
  /// query first because filtering flattens the grid.
  void _drillIntoGrid(String normalized) {
    if (_query.trim().isNotEmpty) {
      _searchController.clear();
      setState(() {
        _query = '';
        _gridPath
          ..clear()
          ..addAll(_pathTo(normalized));
      });
      return;
    }
    _enterGridFolder(normalized);
  }

  /// Single tap with double-click detection.
  ///
  /// Desktop: the assign action is delayed 250ms; a second tap inside that
  /// window cancels it and activates the tag instead (drill into children).
  /// Touch: there is no double-tap, so a tap assigns immediately.
  void _handleTagTap(String normalized) {
    if (!_isDesktop) {
      widget.onTagSelected(_nameOf(normalized));
      return;
    }

    // Leaves have nothing to drill into — assign right away, no delay.
    if (_hierarchyManager.getChildren(normalized).isEmpty) {
      _singleTapTimer?.cancel();
      _pendingTapTag = null;
      widget.onTagSelected(_nameOf(normalized));
      return;
    }

    if (_singleTapTimer?.isActive == true && _pendingTapTag == normalized) {
      _singleTapTimer!.cancel();
      _pendingTapTag = null;
      _activateTag(normalized);
      return;
    }

    _singleTapTimer?.cancel();
    _pendingTapTag = normalized;
    _singleTapTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _pendingTapTag != normalized) return;
      _pendingTapTag = null;
      widget.onTagSelected(_nameOf(normalized));
    });
  }

  void _handleTagDoubleTap(String normalized) {
    _singleTapTimer?.cancel();
    _pendingTapTag = null;
    _activateTag(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_isLoading) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final isGrid = _viewMode == TagBrowseViewMode.grid;
    final rows = isGrid ? const <_BrowseRow>[] : _buildRows();
    final gridEntries = isGrid ? _gridEntries() : const <String>[];
    final isEmpty = isGrid ? gridEntries.isEmpty : rows.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildSearchField(l10n, theme)),
            const SizedBox(width: 8),
            _buildViewModeToggle(l10n, theme),
          ],
        ),
        if (isGrid && _query.trim().isEmpty && _gridPath.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildBreadcrumb(l10n, theme),
        ],
        const SizedBox(height: 10),
        Container(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      l10n.noTagsFound,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: isGrid
                      ? _buildGrid(gridEntries)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          itemCount: rows.length,
                          itemBuilder: (context, index) =>
                              _buildRow(rows[index]),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildViewModeToggle(AppLocalizations l10n, ThemeData theme) {
    Widget button(
      TagBrowseViewMode mode,
      IconData icon,
      String tooltip,
    ) {
      final isActive = _viewMode == mode;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _setViewMode(mode),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isActive
                  ? theme.colorScheme.primary.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 17,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            TagBrowseViewMode.tree,
            PhosphorIconsLight.treeStructure,
            l10n.treeViewMode,
          ),
          button(
            TagBrowseViewMode.grid,
            PhosphorIconsLight.gridFour,
            l10n.gridViewMode,
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(AppLocalizations l10n, ThemeData theme) {
    final crumbs = <Widget>[
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _popGridTo(0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            children: [
              Icon(
                PhosphorIconsLight.tag,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                l10n.allTags,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ];

    for (var i = 0; i < _gridPath.length; i++) {
      final isLast = i == _gridPath.length - 1;
      crumbs
        ..add(Icon(
          PhosphorIconsLight.caretRight,
          size: 11,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ))
        ..add(InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isLast ? null : () => _popGridTo(i + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              _nameOf(_gridPath[i]),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                color: isLast
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: crumbs),
    );
  }

  Widget _buildGrid(List<String> entries) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 132,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.86,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => _buildGridTile(entries[index]),
    );
  }

  Widget _buildGridTile(String normalized) {
    final theme = Theme.of(context);
    final display = _nameOf(normalized);
    final tagColor = _colorManager.getTagColor(display);
    final isSelected = _isSelected(normalized);
    final childCount = _hierarchyManager.getChildren(normalized).length;
    final thumbnailPath = _thumbnailManager.getThumbnailSync(normalized);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _handleTagTap(normalized),
      onDoubleTap:
          childCount > 0 ? () => _handleTagDoubleTap(normalized) : null,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.55)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(11),
                    ),
                    child: thumbnailPath != null
                        ? Image.file(
                            File(thumbnailPath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildGridPlaceholder(tagColor, childCount),
                          )
                        : _buildGridPlaceholder(tagColor, childCount),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(
                      isSelected
                          ? PhosphorIconsFill.checkCircle
                          : PhosphorIconsFill.plusCircle,
                      size: 16,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : Colors.black.withValues(alpha: 0.35),
                    ),
                  ),
                  if (childCount > 0)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: _buildOpenChildrenButton(normalized, childCount),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text(
                display,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Drill-down affordance on a parent tile. A single tap on the tile assigns
  /// the tag, a double-click opens its children, and this badge is the explicit
  /// one-tap way in (also the only way on touch, where there is no double-tap).
  Widget _buildOpenChildrenButton(String normalized, int childCount) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '$childCount',
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () {
          _singleTapTimer?.cancel();
          _pendingTapTag = null;
          _drillIntoGrid(normalized);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsLight.folderOpen,
                size: 11,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 3),
              Text(
                '$childCount',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a drill-down path ending at [normalized] by walking up the first
  /// parent at each level (a tag can have several parents; any valid path is
  /// fine for navigation purposes).
  List<String> _pathTo(String normalized) {
    final path = <String>[normalized];
    final seen = <String>{normalized};
    var current = normalized;
    while (true) {
      final parents = _hierarchyManager.getParents(current);
      if (parents.isEmpty) break;
      final parent = parents.first;
      if (!seen.add(parent)) break;
      path.insert(0, parent);
      current = parent;
    }
    return path;
  }

  Widget _buildSearchField(AppLocalizations l10n, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintText: l10n.searchTagsHint,
        prefixIcon: const Icon(PhosphorIconsLight.magnifyingGlass, size: 18),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(PhosphorIconsLight.x, size: 16),
                tooltip: l10n.clearSearch,
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: WidgetStateColor.resolveWith((states) {
          final focused = states.contains(WidgetState.focused);
          return theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: isDark ? (focused ? 0.56 : 0.42) : (focused ? 0.34 : 0.2),
          );
        }),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent, width: 0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent, width: 0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.48),
            width: 1,
          ),
        ),
      ),
      onChanged: (value) => setState(() => _query = value),
    );
  }

  Widget _buildRow(_BrowseRow row) {
    final theme = Theme.of(context);
    final tagColor = _colorManager.getTagColor(row.display);
    final isSelected = _isSelected(row.normalized);

    return InkWell(
      onTap: () => _handleTagTap(row.normalized),
      onDoubleTap:
          row.hasChildren ? () => _handleTagDoubleTap(row.normalized) : null,
      child: Container(
        padding: EdgeInsets.only(
          left: 8 + row.depth * 16,
          right: 10,
          top: 5,
          bottom: 5,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: row.hasChildren
                  ? InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        _singleTapTimer?.cancel();
                        _pendingTapTag = null;
                        _toggle(row.normalized);
                      },
                      child: Icon(
                        row.isExpanded
                            ? PhosphorIconsLight.caretDown
                            : PhosphorIconsLight.caretRight,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 2),
            _buildLeading(row, tagColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                row.display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (row.hasChildren) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${row.childCount}',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(
              isSelected
                  ? PhosphorIconsLight.checkCircle
                  : PhosphorIconsLight.plusCircle,
              size: 15,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(_BrowseRow row, Color tagColor) {
    final thumbnailPath = _thumbnailManager.getThumbnailSync(row.normalized);
    if (thumbnailPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.file(
          File(thumbnailPath),
          width: 22,
          height: 22,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildIconBadge(row, tagColor),
        ),
      );
    }
    return _buildIconBadge(row, tagColor);
  }

  Widget _buildIconBadge(_BrowseRow row, Color tagColor) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(
        row.hasChildren || _hierarchyManager.isParent(row.normalized)
            ? PhosphorIconsLight.treeStructure
            : PhosphorIconsLight.tag,
        size: 13,
        color: tagColor,
      ),
    );
  }

  /// Tinted fallback used by grid tiles that have no thumbnail (or whose
  /// thumbnail file went missing).
  Widget _buildGridPlaceholder(Color tagColor, int childCount) {
    return Container(
      color: tagColor.withValues(alpha: 0.16),
      alignment: Alignment.center,
      child: Icon(
        childCount > 0
            ? PhosphorIconsLight.treeStructure
            : PhosphorIconsLight.tag,
        size: 26,
        color: tagColor,
      ),
    );
  }
}
