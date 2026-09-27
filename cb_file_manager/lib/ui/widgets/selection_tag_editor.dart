import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import 'package:cb_file_manager/ui/controllers/selection_tags_controller.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:cb_file_manager/ui/widgets/tag_browse_section.dart';
import 'package:cb_file_manager/ui/widgets/tag_chips_field.dart';
import 'package:cb_file_manager/ui/widgets/tag_input_helpers.dart';
import 'package:cb_file_manager/ui/widgets/tag_management_section.dart';

class SelectionTagEditor extends StatefulWidget {
  const SelectionTagEditor({super.key, required this.controller});
  final SelectionTagsController controller;

  @override
  State<SelectionTagEditor> createState() => _SelectionTagEditorState();
}

class _SelectionTagEditorState extends State<SelectionTagEditor> {
  final _inputKey = GlobalKey<ChipsInputState<String>>();
  final _hierarchy = TagHierarchyManager.instance;
  final _thumbnails = TagThumbnailManager.instance;
  final _colors = TagColorManager.instance;
  late Future<List<String>> _recentTags;
  late Future<Map<String, int>> _popularTags;
  int _catalogRevision = -1;
  Timer? _debounce;
  int _generation = 0;
  bool _browseExpanded = false;
  String _draft = '';
  String? _scope;
  List<String> _suggestions = [];
  late List<String> _selection;

  @override
  void initState() {
    super.initState();
    _selection = widget.controller.paths;
    _colors.addListener(_refresh);
    _loadQuickPicks();
    unawaited(_initialize());
  }

  void _loadQuickPicks() {
    _catalogRevision = widget.controller.revision;
    _recentTags = TagManager.getRecentTags(limit: 6);
    _popularTags = TagManager.instance.getPopularTags(limit: 6);
  }

  @override
  void didUpdateWidget(SelectionTagEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_catalogRevision != widget.controller.revision) _loadQuickPicks();
    // The editor stays mounted across selections (rebuilding it made the pane
    // blink), so an uncommitted draft is discarded here instead.
    if (!identical(_selection, widget.controller.paths)) {
      _selection = widget.controller.paths;
      _debounce?.cancel();
      _generation++;
      _draft = '';
      _scope = null;
      _suggestions = [];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputKey.currentState?.clearDraft();
      });
    }
  }

  Future<void> _initialize() async {
    await Future.wait([_hierarchy.initialize(), _thumbnails.initialize()]);
    _refresh();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _colors.removeListener(_refresh);
    super.dispose();
  }

  String _query(String draft) => _scope == null ? draft : '$_scope:$draft';

  void _suggest(String value) {
    _draft = value;
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _query(value);
    if (query.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 100), () async {
      try {
        final suggestions = await computeTagSuggestions(
          query,
          hierarchyManager: _hierarchy,
          isSelected: widget.controller.isCommon,
        );
        if (mounted && generation == _generation) {
          setState(() => _suggestions = suggestions);
        }
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(() => _suggestions = []);
        }
      }
    });
  }

  void _add(String tag) {
    _inputKey.currentState?.clearDraft();
    _debounce?.cancel();
    _generation++;
    setState(() {
      _draft = '';
      _suggestions = [];
    });
    unawaited(widget.controller.add(tag));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (c.loading && c.tagsByPath.isEmpty) return Text(l10n.loadingTags);
    if (c.loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.operationFailed),
          TextButton(onPressed: c.reload, child: Text(l10n.retry)),
        ],
      );
    }
    final counts = c.counts;
    final total = c.paths.length;
    // Tags of the previous selection stay in the field, dimmed and locked,
    // until the new selection's tags arrive.
    final stale =
        c.loading && !setEquals(c.tagsByPath.keys.toSet(), c.paths.toSet());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.tags, style: theme.textTheme.titleSmall),
        if (c.saving) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IgnorePointer(
              ignoring: stale,
              child: AnimatedOpacity(
                opacity: stale ? .5 : 1,
                duration: const Duration(milliseconds: 150),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: TagChipsField(
                    fieldKey: _inputKey,
                    tags: counts.keys.toList(),
                    suggestions: _suggestions,
                    scopeParent: _scope,
                    onScopeChanged: (value) {
                      setState(() => _scope = value);
                      _suggest('');
                    },
                    hintText: l10n.propertiesTagHint,
                    onTextChanged: _suggest,
                    onSubmitted: (value) => _add(_query(value)),
                    onSuggestionSelected: (value) =>
                        _add(resolvePickedSuggestion(_query(_draft), value)),
                    onRemoved: c.remove,
                    // A tag only some selected files carry reads "tag n/total";
                    // tapping it applies the tag to the rest.
                    chipLabel: total > 1
                        ? (tag) => '$tag ${counts[tag]}/$total'
                        : null,
                    chipTooltip: (tag) =>
                        (counts[tag] ?? 0) < total ? l10n.addTag : null,
                    onChipTapped: (tag) {
                      if ((counts[tag] ?? 0) < total) _add(tag);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            RecentTagsWidget(
              limit: 6,
              onTagSelected: _add,
              loadRecentTags: (_) => _recentTags,
            ),
            const SizedBox(height: 12),
            PopularTagsWidget(
              limit: 6,
              onTagSelected: _add,
              loadPopularTags: (_) => _popularTags,
            ),
            ExpansionTile(
              onExpansionChanged: (value) =>
                  setState(() => _browseExpanded = value),
              tilePadding: EdgeInsets.zero,
              title: Text(l10n.browseTab),
              children: [
                if (_browseExpanded)
                  TagBrowseSection(
                    refreshVersion: widget.controller.revision,
                    selectedTags: counts.keys.where(c.isCommon).toList(),
                    onTagSelected: _add,
                    onTagDeselected: (tag) => c.remove(tag),
                    maxHeight: 220,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
