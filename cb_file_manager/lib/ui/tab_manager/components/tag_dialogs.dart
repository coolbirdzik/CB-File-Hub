import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:cb_file_manager/helpers/tags/batch_tag_manager.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/widgets/resizable_dialog.dart';
import 'package:cb_file_manager/ui/widgets/tag_browse_section.dart';
import 'package:cb_file_manager/ui/widgets/tag_management_section.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import '../../utils/route.dart';

// ─────────────────────────────────────────────────────────────────────────
// Shared tag-hierarchy helpers (parent:child syntax + autocomplete)
//
// These top-level helpers are used by both the single-file dialog
// (_SingleFileTagDialog) and the batch dialog (showBatchAddTagDialog) so the
// "type parent:child to create a new tag under a parent" behavior stays
// consistent across both flows.
// ─────────────────────────────────────────────────────────────────────────

/// Result of parsing a "parent:child1,child2" style input.
class ParsedHierarchyInput {
  const ParsedHierarchyInput(this.parentName, this.childNames);
  final String parentName;
  final List<String> childNames;

  bool get isValid => parentName.isNotEmpty && childNames.isNotEmpty;
}

/// Parses "parent:child1, child2" input into a parent name and its children.
/// Returns null when there is no colon (not a hierarchy input).
ParsedHierarchyInput? parseHierarchyInput(String input) {
  final colonIndex = input.indexOf(':');
  if (colonIndex < 0) return null;

  final parentName = input.substring(0, colonIndex).trim();
  final childrenPart = input.substring(colonIndex + 1).trim();

  final childNames = childrenPart
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList(growable: false);

  return ParsedHierarchyInput(parentName, childNames);
}

/// Computes autocomplete suggestions for a tag input, honoring the
/// "parent:child" hierarchy syntax.
///
/// - When the query contains ":", suggests existing children of the typed
///   parent (filtered by the partial child being typed, comma-aware).
/// - Otherwise runs a regular tag search with parents ordered first.
///
/// [isSelected] excludes tags already chosen. Results are capped at 10.
Future<List<String>> computeTagSuggestions(
  String query, {
  required TagHierarchyManager hierarchyManager,
  required bool Function(String tag) isSelected,
}) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const <String>[];

  // parent:child context — suggest existing children of the parent.
  final colonIndex = trimmed.indexOf(':');
  if (colonIndex >= 0) {
    final parentPart = trimmed.substring(0, colonIndex).trim();
    final childPart = trimmed.substring(colonIndex + 1).trim();

    if (parentPart.isNotEmpty) {
      final children = hierarchyManager.getChildren(parentPart);

      if (childPart.isEmpty) {
        return children
            .where((c) => !isSelected(c))
            .take(10)
            .toList(growable: false);
      }

      // Comma-separated: only match the partial entry being typed now.
      final existingChildren = childPart
          .split(',')
          .map((c) => c.trim().toLowerCase())
          .where((c) => c.isNotEmpty)
          .toSet();
      final currentPart = childPart.split(',').last.trim().toLowerCase();

      return children
          .where((c) {
            final normalized = c.toLowerCase();
            return !existingChildren.contains(normalized) &&
                !isSelected(c) &&
                (currentPart.isEmpty || normalized.contains(currentPart));
          })
          .take(10)
          .toList(growable: false);
    }
  }

  // Regular search with hierarchy-aware ordering (parents first).
  final suggestions = await TagManager.instance.searchTags(trimmed);
  final sorted = suggestions.where((tag) => !isSelected(tag)).toList();
  sorted.sort((a, b) {
    final aIsParent = hierarchyManager.isParent(a);
    final bIsParent = hierarchyManager.isParent(b);
    if (aIsParent && !bIsParent) return -1;
    if (!aIsParent && bIsParent) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return sorted.take(10).toList(growable: false);
}

/// Given the current draft text and a picked suggestion, reconstructs the full
/// text that should be added.
///
/// In "parent:child" context the suggestion is the child tag, so the parent
/// prefix (and any earlier comma-separated children) are preserved. Otherwise
/// the suggestion is returned as-is.
String resolvePickedSuggestion(String draftText, String suggestion) {
  final colonIndex = draftText.indexOf(':');
  if (colonIndex >= 0) {
    final parentPart = draftText.substring(0, colonIndex).trim();
    final childrenPart = draftText.substring(colonIndex + 1);
    if (parentPart.isNotEmpty) {
      final commaIndex = childrenPart.lastIndexOf(',');
      final prefix =
          commaIndex >= 0 ? childrenPart.substring(0, commaIndex + 1) : '';
      return '$parentPart:$prefix${suggestion.trim()}';
    }
  }
  return suggestion;
}

/// Persists a parent:child hierarchy: ensures both tags exist and links them.
/// Fire-and-forget friendly (awaited internally but errors are logged).
Future<void> createHierarchyRelationships(
  TagHierarchyManager hierarchyManager,
  String parentName,
  List<String> childNames,
) async {
  await TagManager.addStandaloneTag(parentName);
  for (final childName in childNames) {
    await TagManager.addStandaloneTag(childName);
    final ok = await hierarchyManager.addChild(parentName, childName);
    if (!ok) {
      AppLogger.warning(
        '[ManageTags] Failed to create hierarchy',
        error: 'parent=$parentName child=$childName',
      );
    }
  }
}

/// Shared suggestion list item with thumbnail (40x40), hierarchy context, and
/// highlighting. Used by both the single-file and batch tag dialogs.
Widget buildTagSuggestionItem(
  BuildContext context,
  String suggestion,
  bool isHighlighted,
  Color tagColor, {
  required TagThumbnailManager thumbnailManager,
  required TagHierarchyManager hierarchyManager,
}) {
  final theme = Theme.of(context);
  final thumbnailPath = thumbnailManager.getThumbnailSync(suggestion);
  final parents = hierarchyManager.getParents(suggestion);
  final children = hierarchyManager.getChildren(suggestion);

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      children: [
        if (thumbnailPath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(thumbnailPath),
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(PhosphorIconsLight.tag, size: 18, color: tagColor),
              ),
            ),
          )
        else
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tagColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              hierarchyManager.isParent(suggestion)
                  ? PhosphorIconsLight.treeStructure
                  : PhosphorIconsLight.tag,
              size: 18,
              color: tagColor,
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                suggestion,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (parents.isNotEmpty)
                Text(
                  'Parent: ${parents.join(", ")}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (children.isNotEmpty)
                Text(
                  '${children.length} child${children.length > 1 ? "ren" : ""}: ${children.take(3).join(", ")}${children.length > 3 ? "..." : ""}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (isHighlighted)
          Icon(
            PhosphorIconsLight.arrowRight,
            size: 14,
            color: theme.colorScheme.primary,
          ),
      ],
    ),
  );
}

/// Dialog for adding a tag to a file
void showAddTagToFileDialog(BuildContext context, String filePath) {
  AppLogger.info('[ManageTags][Dialog] Opening dialog for $filePath');

  void refreshParentUI(String filePath, {bool preserveScroll = true}) {
    TagManager.clearCache();
    if (preserveScroll) {
      TagManager.instance.notifyTagChanged("preserve_scroll:$filePath");
    } else {
      TagManager.instance.notifyTagChanged(filePath);
    }
    TagManager.instance.notifyTagChanged(filePath);
    TagManager.instance.notifyTagChanged("global:tag_updated");
  }

  RouteUtils.showAcrylicDialog(
    context: context,
    builder: (dialogContext) {
      AppLogger.debug('[ManageTags][Dialog] showDialog builder for $filePath');
      return _SingleFileTagDialog(filePath: filePath);
    },
  ).then((result) {
    if (result == true) {
      AppLogger.info('[ManageTags][Dialog] Refresh triggered after save',
          error: 'filePath=$filePath');
      refreshParentUI(filePath);
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppToast.success(context, l10n.tagsSavedSuccessfully);
      }
    }
  });
}

class _SingleFileTagDialog extends StatefulWidget {
  final String filePath;

  const _SingleFileTagDialog({required this.filePath});

  @override
  State<_SingleFileTagDialog> createState() => _SingleFileTagDialogState();
}

class _SingleFileTagDialogState extends State<_SingleFileTagDialog> {
  List<String> _originalTags = <String>[];
  List<String> _selectedTags = <String>[];
  List<String> _tagSuggestions = <String>[];
  String _draftTagText = '';
  bool _isLoading = true;
  bool _isSaving = false;
  Timer? _debounceTimer;
  final _thumbnailManager = TagThumbnailManager.instance;
  final _hierarchyManager = TagHierarchyManager.instance;

  @override
  void initState() {
    super.initState();
    _loadTags();
    _initManagers();
  }

  Future<void> _initManagers() async {
    await Future.wait([
      _thumbnailManager.initialize(),
      _hierarchyManager.initialize(),
    ]);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTags() async {
    AppLogger.info('[ManageTags][Dialog] Loading tags',
        error: 'filePath=${widget.filePath}');
    try {
      final tags = await TagManager.getTags(widget.filePath);
      if (!mounted) {
        return;
      }

      setState(() {
        _originalTags = List<String>.from(tags);
        _selectedTags = List<String>.from(tags);
        _isLoading = false;
      });
      AppLogger.info('[ManageTags][Dialog] Loaded tags',
          error: 'filePath=${widget.filePath} tags=$tags');
    } catch (error, stackTrace) {
      AppLogger.error(
        '[ManageTags][Dialog] Failed to load tags',
        error: 'filePath=${widget.filePath} error=$error',
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateTagSuggestions(String text) async {
    _debounceTimer?.cancel();
    final query = text.trim();

    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _tagSuggestions = <String>[];
      });
      return;
    }

    // Debounce 100ms
    _debounceTimer = Timer(const Duration(milliseconds: 100), () async {
      final suggestions = await computeTagSuggestions(
        query,
        hierarchyManager: _hierarchyManager,
        isSelected: _containsTag,
      );
      if (!mounted) return;
      setState(() {
        _tagSuggestions = suggestions;
      });
    });
  }

  bool _containsTag(String tag) {
    final normalizedTag = tag.trim().toLowerCase();
    return _selectedTags.any((selectedTag) {
      return selectedTag.trim().toLowerCase() == normalizedTag;
    });
  }

  /// Handles picking a suggestion from the autocomplete overlay.
  ///
  /// When the user is typing in "parent:child" context (the draft already has a
  /// colon), the suggestion is the child tag — reconstruct the full
  /// "parent:child" input so the hierarchy relationship is created. Otherwise
  /// add the suggestion as-is.
  void _onSuggestionSelected(String suggestion) {
    _addTag(resolvePickedSuggestion(_draftTagText, suggestion));
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim();
    if (tag.isEmpty) {
      _draftTagText = '';
      return;
    }

    // Handle parent:child format
    if (tag.contains(':')) {
      _addHierarchyTags(tag);
      return;
    }

    if (_containsTag(tag)) {
      _draftTagText = '';
      return;
    }

    setState(() {
      _selectedTags = <String>[..._selectedTags, tag];
      _draftTagText = '';
      _tagSuggestions = <String>[];
    });
    AppLogger.info('[ManageTags][Dialog] Tag added',
        error: 'filePath=${widget.filePath} tag=$tag');
  }

  /// Parse and add tags in parent:child format.
  /// Creates hierarchy relationships and adds all tags to the selection.
  void _addHierarchyTags(String input) {
    final parsed = parseHierarchyInput(input);
    if (parsed == null || !parsed.isValid) return;

    final parentName = parsed.parentName;
    final childNames = parsed.childNames;

    // Only add child tags to the file's tag list.
    // The parent tag is created/ensured in the tag store via
    // createHierarchyRelationships but is NOT automatically assigned to the
    // file — the user typed "parent:child" to create a child under a parent,
    // not to assign the parent itself.
    final tagsToAdd = childNames
        .where((child) => !_containsTag(child))
        .toList(growable: false);

    if (tagsToAdd.isEmpty) {
      _draftTagText = '';
      return;
    }

    setState(() {
      _selectedTags = <String>[..._selectedTags, ...tagsToAdd];
      _draftTagText = '';
      _tagSuggestions = <String>[];
    });

    // Create hierarchy relationships asynchronously (fire and forget)
    createHierarchyRelationships(_hierarchyManager, parentName, childNames);

    AppLogger.info('[ManageTags][Dialog] Hierarchy tags added',
        error:
            'filePath=${widget.filePath} parent=$parentName children=$childNames');
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedTags = _selectedTags.where((value) => value != tag).toList();
    });
    AppLogger.info('[ManageTags][Dialog] Tag removed',
        error: 'filePath=${widget.filePath} tag=$tag');
  }

  void _commitDraftTag() {
    final draft = _draftTagText.trim();
    if (draft.isEmpty) {
      return;
    }
    _addTag(draft);
  }

  bool get _hasChanges {
    final original = _originalTags.map((tag) => tag.trim()).toSet();
    final current = _selectedTags.map((tag) => tag.trim()).toSet();
    return original.length != current.length || !original.containsAll(current);
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }

    AppLogger.info('[ManageTags][Dialog] Save pressed',
        error:
            'filePath=${widget.filePath} selectedTags=$_selectedTags draftTagText=$_draftTagText');

    setState(() {
      _isSaving = true;
    });

    try {
      _commitDraftTag();

      final tagsToPersist = List<String>.from(_selectedTags);
      AppLogger.info('[ManageTags][Dialog] Persisting tags',
          error: 'filePath=${widget.filePath} tags=$tagsToPersist');

      if (_hasChanges || _draftTagText.trim().isNotEmpty) {
        final success =
            await TagManager.setTags(widget.filePath, tagsToPersist);
        if (!success) {
          throw Exception('Failed to persist tags for "${widget.filePath}"');
        }
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop(true);
    } catch (error, stackTrace) {
      final l10n = AppLocalizations.of(context)!;
      AppLogger.error(
        '[ManageTags][Dialog] Save failed',
        error: 'filePath=${widget.filePath} error=$error',
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      AppToast.error(context, l10n.errorSavingTags(error.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildTagInputSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return _buildSectionCard(
      icon: PhosphorIconsLight.pencilSimpleLine,
      title: l10n.addTag,
      subtitle:
          'Type a tag, or use parent:child. Press ":" on a suggestion to make it the parent.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChipsInput<String>(
            values: _selectedTags,
            suggestions: _tagSuggestions,
            enableColonAutocomplete: true,
            onSuggestionSelected: _onSuggestionSelected,
            suggestionBuilder: _buildSuggestionItem,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.transparent,
                  width: 0,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.transparent,
                  width: 0,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.48),
                  width: 1,
                ),
              ),
              labelText: l10n.tagName,
              hintText: '${l10n.enterTagName} (e.g. Actress:Hung)',
              prefixIcon: const Icon(PhosphorIconsLight.tag),
              filled: true,
              fillColor: WidgetStateColor.resolveWith((states) {
                final focused = states.contains(WidgetState.focused);
                return theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: isDarkMode
                      ? (focused ? 0.56 : 0.42)
                      : (focused ? 0.34 : 0.2),
                );
              }),
            ),
            style: const TextStyle(fontSize: 16),
            onChanged: (updatedTags) {
              setState(() {
                _selectedTags = List<String>.from(updatedTags);
              });
            },
            onTextChanged: (value) {
              _draftTagText = value;
              _updateTagSuggestions(value);
            },
            onSubmitted: _addTag,
            chipBuilder: (context, tag) {
              return TagInputChip(
                tag: tag,
                onDeleted: _removeTag,
                onSelected: (_) {},
              );
            },
          ),
        ],
      ),
    );
  }

  /// Custom suggestion item with thumbnail (40x40), hierarchy context, and
  /// highlighted matching text.
  Widget _buildSuggestionItem(BuildContext context, String suggestion,
      bool isHighlighted, Color tagColor) {
    return buildTagSuggestionItem(
      context,
      suggestion,
      isHighlighted,
      tagColor,
      thumbnailManager: _thumbnailManager,
      hierarchyManager: _hierarchyManager,
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return ResizableDialog(
      prefsKeyPrefix: 'manage_tags_dialog',
      minSize: const Size(460, 420),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.manageTags,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.file,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.filePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      contentBuilder: (context, dialogSize) {
        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        // The browse tree gets whatever vertical room is left after the fixed
        // sections, so resizing the dialog actually grows the tag list.
        final browseHeight = (dialogSize.height - 520).clamp(160.0, 900.0);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTagInputSection(l10n),
              const SizedBox(height: 18),
              _buildSectionCard(
                icon: PhosphorIconsLight.sparkle,
                title: 'Quick Picks',
                subtitle: 'Choose from popular and recently used tags',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PopularTagsWidget(
                      onTagSelected: _addTag,
                    ),
                    const SizedBox(height: 18),
                    RecentTagsWidget(
                      onTagSelected: _addTag,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildSectionCard(
                icon: PhosphorIconsLight.treeStructure,
                title: l10n.allTags,
                subtitle:
                    'Browse the tag tree — expand a parent to pick its children.',
                child: TagBrowseSection(
                  selectedTags: _selectedTags,
                  onTagSelected: _addTag,
                  maxHeight: browseHeight,
                ),
              ),
            ],
          ),
        );
      },
      actions: [
        TextFieldTapRegion(
          child: TextButton(
            onPressed: _isSaving
                ? null
                : () {
                    AppLogger.info('[ManageTags][Dialog] Close pressed',
                        error: 'filePath=${widget.filePath}');
                    Navigator.of(context, rootNavigator: true).pop(false);
                  },
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(l10n.close.toUpperCase()),
          ),
        ),
        TextFieldTapRegion(
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.save.toUpperCase()),
          ),
        ),
      ],
    );
  }
}

/// Dialog for deleting a tag from a file
void showDeleteTagDialog(
  BuildContext context,
  String filePath,
  List<String> tags,
) {
  String? selectedTag = tags.isNotEmpty ? tags.first : null;

  RouteUtils.showAcrylicDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(AppLocalizations.of(context)!.removeTag),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            content: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(
                maxWidth: 450,
                minWidth: 350,
                minHeight: 100,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context)!.selectTagToRemove),
                  const SizedBox(height: 16),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedTag,
                    items: tags.map((tag) {
                      return DropdownMenuItem<String>(
                        value: tag,
                        child: Text(tag),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedTag = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  RouteUtils.safePopDialog(context);
                },
                child: Text(AppLocalizations.of(context)!.cancel.toUpperCase()),
              ),
              TextButton(
                onPressed: () async {
                  if (selectedTag != null) {
                    // Pre-extract all context-dependent values before async gap
                    final l10n = AppLocalizations.of(context)!;
                    final bloc =
                        BlocProvider.of<FolderListBloc>(context, listen: false);
                    final toast = AppToast.capture(context);
                    final navigator = Navigator.of(context);

                    try {
                      await TagManager.removeTag(filePath, selectedTag!);
                      TagManager.clearCache();

                      try {
                        bloc.add(RemoveTagFromFile(filePath, selectedTag!));
                      } catch (_) {}

                      TagManager.instance
                          .notifyTagChanged("tag_only:$filePath");

                      try {
                        toast.success(l10n.tagDeleted(selectedTag!));
                        navigator.pop();
                      } catch (_) {}
                    } catch (e) {
                      try {
                        toast.error(l10n.errorDeletingTag(e.toString()));
                      } catch (_) {}
                    }
                  } else {
                    try {
                      Navigator.of(context).pop();
                    } catch (_) {}
                  }
                },
                child:
                    Text(AppLocalizations.of(context)!.removeTag.toUpperCase()),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Dialog for batch adding tags
void showBatchAddTagDialog(BuildContext context, List<String> selectedFiles) {
  final focusNode = FocusNode();
  final TextEditingController textController = TextEditingController();
  List<String> tagSuggestions = [];
  List<String> selectedTags = [];
  String draftTagText = '';
  bool isSaving = false;

  final thumbnailManager = TagThumbnailManager.instance;
  final hierarchyManager = TagHierarchyManager.instance;
  Future.wait([thumbnailManager.initialize(), hierarchyManager.initialize()]);

  AppLogger.info('[ManageTags][BatchDialog] Opening batch dialog',
      error: 'selectedFiles=$selectedFiles');

  void updateTagSuggestions(String text) async {
    tagSuggestions = await computeTagSuggestions(
      text,
      hierarchyManager: hierarchyManager,
      isSelected: selectedTags.contains,
    );
  }

  /// Handles "parent:child1,child2" input by adding the parent + children to
  /// the selection and creating the hierarchy relationships in the background.
  /// Returns true when the input was hierarchy input (and was handled).
  bool addHierarchyTags(String input) {
    final parsed = parseHierarchyInput(input);
    if (parsed == null || !parsed.isValid) return false;

    // Only add child tags to the selection; the parent is ensured in the
    // tag store via createHierarchyRelationships but NOT auto-assigned.
    final tagsToAdd = parsed.childNames
        .where((child) => !selectedTags.contains(child))
        .toList(growable: false);

    selectedTags.addAll(tagsToAdd);
    textController.clear();
    draftTagText = '';
    tagSuggestions = [];

    createHierarchyRelationships(
        hierarchyManager, parsed.parentName, parsed.childNames);

    AppLogger.info('[ManageTags][BatchDialog] Hierarchy tags added',
        error: 'parent=${parsed.parentName} children=${parsed.childNames}');
    return true;
  }

  void addTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return;

    // parent:child syntax — create hierarchy instead of a flat tag.
    if (trimmed.contains(':')) {
      if (addHierarchyTags(trimmed)) return;
    }

    if (!selectedTags.contains(trimmed)) {
      selectedTags.add(trimmed);
      textController.clear();
      draftTagText = '';
    }
  }

  void commitDraftTag() {
    final trimmedTag = draftTagText.trim();
    if (trimmedTag.isEmpty) {
      return;
    }

    addTag(trimmedTag);
    tagSuggestions = [];
  }

  void refreshParentUIBatch() {
    TagManager.clearCache();

    try {
      if (selectedFiles.isNotEmpty) {
        for (final file in selectedFiles) {
          TagManager.instance.notifyTagChanged("preserve_scroll:$file");
        }
      }
    } catch (_) {}
  }

  final batchTagManager = BatchTagManager.getInstance();
  batchTagManager.findCommonTags(selectedFiles).then((commonTags) {
    if (!context.mounted) return;

    selectedTags = commonTags;
    AppLogger.info('[ManageTags][BatchDialog] Loaded common tags',
        error: 'selectedFiles=$selectedFiles commonTags=$commonTags');

    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            void handleTextChange(String value) {
              draftTagText = value;
              updateTagSuggestions(value);
              setState(() {});
            }

            void handleTagSubmit(String value) {
              if (value.trim().isNotEmpty) {
                setState(() {
                  addTag(value);
                  tagSuggestions = [];
                });
                AppLogger.info('[ManageTags][BatchDialog] Tag submitted',
                    error: 'selectedFiles=$selectedFiles tag=$value');
              }
            }

            void handleTagSelected(String tag) {
              // In the batch dialog, tapping a popular/recent tag should add it
              // to the input (like the single-file dialog), not open a search
              // tab. Opening a search tab here is unexpected for the user.
              setState(() {
                addTag(tag);
                tagSuggestions = [];
              });
              AppLogger.info('[ManageTags][BatchDialog] Quick tag added',
                  error: 'selectedFiles=$selectedFiles tag=$tag');
            }

            return ResizableDialog(
              prefsKeyPrefix: 'batch_tags_dialog',
              minSize: const Size(460, 420),
              title: Text(
                AppLocalizations.of(context)!
                    .batchAddTags(selectedFiles.length),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              contentBuilder: (context, dialogSize) {
                final browseHeight =
                    (dialogSize.height - 510).clamp(160.0, 900.0);
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Focus(
                        focusNode: focusNode,
                        child: ChipsInput<String>(
                          values: selectedTags,
                          suggestions: tagSuggestions,
                          enableColonAutocomplete: true,
                          onSuggestionSelected: (tag) {
                            setState(() {
                              addTag(
                                  resolvePickedSuggestion(draftTagText, tag));
                              tagSuggestions = [];
                            });
                          },
                          suggestionBuilder:
                              (context, suggestion, isHighlighted, tagColor) =>
                                  buildTagSuggestionItem(
                            context,
                            suggestion,
                            isHighlighted,
                            tagColor,
                            thumbnailManager: thumbnailManager,
                            hierarchyManager: hierarchyManager,
                          ),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            labelText: AppLocalizations.of(context)!.tagName,
                            hintText:
                                AppLocalizations.of(context)!.enterTagName,
                            prefixIcon: const Icon(PhosphorIconsLight.tag),
                            filled: true,
                            fillColor:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[800]
                                    : Colors.grey[100],
                          ),
                          onChanged: (updatedTags) {
                            setState(() {
                              selectedTags.clear();
                              selectedTags.addAll(updatedTags);
                            });
                          },
                          onTextChanged: handleTextChange,
                          onSubmitted: handleTagSubmit,
                          chipBuilder: (context, tag) {
                            return TagInputChip(
                              tag: tag,
                              onDeleted: (removedTag) {
                                setState(() {
                                  selectedTags.remove(removedTag);
                                });
                              },
                              onSelected: (selectedTag) {},
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (selectedTags.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.selectedTags,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8.0,
                              runSpacing: 8.0,
                              children: selectedTags.map((tag) {
                                return Chip(
                                  label: Text(tag),
                                  onDeleted: () {
                                    setState(() {
                                      selectedTags.remove(tag);
                                    });
                                  },
                                  deleteIcon: const Icon(PhosphorIconsLight.x,
                                      size: 16),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      const SizedBox(height: 24),
                      PopularTagsWidget(onTagSelected: handleTagSelected),
                      const SizedBox(height: 24),
                      RecentTagsWidget(onTagSelected: handleTagSelected),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Icon(
                            PhosphorIconsLight.treeStructure,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context)!.allTags,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TagBrowseSection(
                        selectedTags: selectedTags,
                        onTagSelected: handleTagSelected,
                        maxHeight: browseHeight,
                      ),
                    ],
                  ),
                );
              },
              actions: [
                TextFieldTapRegion(
                  child: TextButton(
                    onPressed: isSaving
                        ? null
                        : () {
                            RouteUtils.safePopDialog(context);
                          },
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    child: Text(
                        AppLocalizations.of(context)!.cancel.toUpperCase()),
                  ),
                ),
                TextFieldTapRegion(
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            AppLogger.info(
                                '[ManageTags][BatchDialog] Save pressed',
                                error:
                                    'selectedFiles=$selectedFiles selectedTags=$selectedTags draftTagText=$draftTagText');
                            final l10n = AppLocalizations.of(context)!;
                            // Persistence happens through TagManager; UI refresh is
                            // driven by the coalesced tag-change notification fired in
                            // refreshParentUIBatch(). No bloc lookup is needed here.
                            final toast = AppToast.capture(context);
                            final navigator = Navigator.of(context);

                            try {
                              setState(() {
                                commitDraftTag();
                                isSaving = true;
                              });
                              try {
                                toast.info(l10n.applyingChanges);
                              } catch (_) {}

                              TagManager.clearCache();

                              final commonTags = await batchTagManager
                                  .findCommonTags(selectedFiles);

                              int tagsAdded = 0;
                              int tagsRemoved = 0;

                              // Read every file's existing tags in a single batched
                              // round-trip instead of awaiting getTags() one file at
                              // a time — the per-file await was a big part of the UI
                              // stall on large selections.
                              final existingTagsByFile =
                                  await TagManager.getTagsForFiles(
                                      selectedFiles);

                              final Set<String> currentTagsSet =
                                  Set<String>.from(selectedTags);
                              final Set<String> commonTagsSet =
                                  Set<String>.from(commonTags);
                              final commonTagsToRemove =
                                  commonTagsSet.difference(currentTagsSet);

                              for (final filePath in selectedFiles) {
                                final existingTags =
                                    existingTagsByFile[filePath] ??
                                        const <String>[];

                                final Set<String> originalTagsSet =
                                    Set<String>.from(existingTags);
                                final updatedTags =
                                    Set<String>.from(originalTagsSet);

                                updatedTags.removeAll(commonTagsToRemove);
                                tagsRemoved += originalTagsSet
                                    .intersection(commonTagsToRemove)
                                    .length;

                                final tagsToAdd =
                                    currentTagsSet.difference(originalTagsSet);
                                updatedTags.addAll(tagsToAdd);
                                tagsAdded += tagsToAdd.length;

                                // Suppress the per-file tag-change event; a single
                                // coalesced refresh is fired below via
                                // refreshParentUIBatch(). Otherwise each file would
                                // trigger a full folder-list reload.
                                await TagManager.setTags(
                                    filePath, updatedTags.toList(),
                                    notify: false);
                              }

                              refreshParentUIBatch();
                              AppLogger.info(
                                  '[ManageTags][BatchDialog] Save completed',
                                  error:
                                      'selectedFiles=$selectedFiles tagsAdded=$tagsAdded tagsRemoved=$tagsRemoved');

                              try {
                                toast.success(
                                  l10n.tagsUpdated(
                                    selectedFiles.length,
                                    tagsAdded,
                                    tagsRemoved,
                                  ),
                                );
                                navigator.pop();
                              } catch (_) {}
                            } catch (e) {
                              AppLogger.error(
                                '[ManageTags][BatchDialog] Save failed',
                                error: 'selectedFiles=$selectedFiles error=$e',
                              );
                              AppLogger.warning(
                                  'Error processing batch tags: $e');
                              try {
                                toast.error(
                                  l10n.batchTagProcessingError(e.toString()),
                                );
                              } catch (_) {}
                            } finally {
                              // Reset the saving flag only if the dialog is still
                              // open (the success path pops it and unmounts).
                              if (context.mounted) {
                                setState(() {
                                  isSaving = false;
                                });
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            AppLocalizations.of(context)!.save.toUpperCase()),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  });
}

/// Dialog for managing all tags
void showManageTagsDialog(
    BuildContext context, List<String> allTags, String currentPath,
    {List<String>? selectedFiles}) {
  if (selectedFiles != null && selectedFiles.isNotEmpty) {
    showRemoveTagsDialog(context, selectedFiles);
    return;
  }

  final l10n = AppLocalizations.of(context)!;
  AppToast.warning(context, l10n.selectFilesToRemoveTags);
}

/// Shows dialog to remove tags from multiple files
void showRemoveTagsDialog(BuildContext context, List<String> filePaths) {
  void refreshParentUIRemoveTags() {
    TagManager.clearCache();

    try {
      if (filePaths.isNotEmpty) {
        for (final file in filePaths) {
          TagManager.instance.notifyTagChanged("preserve_scroll:$file");
        }
      }
    } catch (_) {}
  }

  RouteUtils.showAcrylicDialog(
    context: context,
    builder: (context) => RemoveTagsChipDialog(
      filePaths: filePaths,
      onTagsRemoved: () {
        refreshParentUIRemoveTags();
      },
    ),
  );
}

/// A stateful dialog for removing tags from multiple files at once
class RemoveTagsChipDialog extends StatefulWidget {
  final List<String> filePaths;
  final VoidCallback onTagsRemoved;

  const RemoveTagsChipDialog(
      {Key? key, required this.filePaths, required this.onTagsRemoved})
      : super(key: key);

  @override
  State<RemoveTagsChipDialog> createState() => _RemoveTagsChipDialogState();
}

class _RemoveTagsChipDialogState extends State<RemoveTagsChipDialog> {
  final Map<String, Set<String>> _fileTagMap = {};
  final Set<String> _commonTags = {};
  final Set<String> _selectedTagsToRemove = {};
  bool _isLoading = true;
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    _loadTagsForFiles();
  }

  Future<void> _loadTagsForFiles() async {
    setState(() => _isLoading = true);

    try {
      for (final filePath in widget.filePaths) {
        final tags = await TagManager.getTags(filePath);
        _fileTagMap[filePath] = tags.toSet();

        if (_fileTagMap.keys.length == 1) {
          _commonTags.addAll(tags);
        } else {
          _commonTags.retainAll(tags.toSet());
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      AppLogger.warning('Error loading tags for multiple files: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleTagSelection(String tag) {
    setState(() {
      if (_selectedTagsToRemove.contains(tag)) {
        _selectedTagsToRemove.remove(tag);
      } else {
        _selectedTagsToRemove.add(tag);
      }
    });
  }

  Future<void> _removeSelectedTags() async {
    if (_selectedTagsToRemove.isEmpty) {
      RouteUtils.safePopDialog(context);
      return;
    }

    setState(() => _isRemoving = true);

    // Pre-extract all context-dependent values before async gap
    final bloc = BlocProvider.of<FolderListBloc>(context, listen: false);
    final toast = AppToast.capture(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context)!;

    try {
      try {
        toast.info(AppLocalizations.of(context)!.applyingChanges);
      } catch (_) {}

      for (final tagToRemove in _selectedTagsToRemove) {
        await BatchTagManager.removeTagFromFilesStatic(
            widget.filePaths, tagToRemove);

        try {
          for (final filePath in widget.filePaths) {
            bloc.add(RemoveTagFromFile(filePath, tagToRemove));
          }
        } catch (_) {}
      }

      try {
        navigator.pop();

        toast.success(l10n.removeTagsSuccess(
          _selectedTagsToRemove.length,
          widget.filePaths.length,
        ));

        TagManager.clearCache();

        for (final file in widget.filePaths) {
          TagManager.instance.notifyTagChanged("preserve_scroll:$file");
        }

        widget.onTagsRemoved();
      } catch (_) {}
    } catch (e) {
      AppLogger.warning('Error removing tags: $e');
      try {
        toast.error(l10n.removeTagsError(e.toString()));
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _isRemoving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double dialogWidth = screenSize.width * 0.5;
    final double dialogHeight = screenSize.height * 0.6;

    return AlertDialog(
      title: Text(
        AppLocalizations.of(context)!
            .removeTagsFromFilesTitle(widget.filePaths.length),
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
          minHeight: dialogHeight * 0.7,
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoading)
              Expanded(
                child: Center(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(AppLocalizations.of(context)!.loadingTags)
                  ],
                )),
              )
            else if (_commonTags.isEmpty && !_isLoading)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIconsLight.info,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!
                            .noCommonTagsAcrossSelectedFiles,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedTagsToRemove.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                            AppLocalizations.of(context)!
                                .tagsSelected(_selectedTagsToRemove.length),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.bold,
                            )),
                      ),
                    const Text(
                      'Chọn thẻ chung để xóa:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[800]
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16.0),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.all(8),
                          children: _commonTags.map((tag) {
                            final isSelected =
                                _selectedTagsToRemove.contains(tag);
                            return CheckboxListTile(
                              title: Text(tag),
                              value: isSelected,
                              onChanged: (_) => _toggleTagSelection(tag),
                              activeColor: Theme.of(context).colorScheme.error,
                              checkColor: Colors.white,
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isRemoving ? null : () => RouteUtils.safePopDialog(context),
          style: TextButton.styleFrom(
            textStyle: const TextStyle(fontSize: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(AppLocalizations.of(context)!.cancel.toUpperCase()),
        ),
        ElevatedButton(
          onPressed: _selectedTagsToRemove.isEmpty ||
                  _isRemoving ||
                  _commonTags.isEmpty
              ? null
              : _removeSelectedTags,
          style: ElevatedButton.styleFrom(
            textStyle: const TextStyle(fontSize: 16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
          ),
          child: _isRemoving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(AppLocalizations.of(context)!.removeTag.toUpperCase()),
        ),
      ],
    );
  }
}
