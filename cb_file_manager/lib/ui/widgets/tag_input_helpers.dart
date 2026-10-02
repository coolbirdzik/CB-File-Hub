import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/text_utils.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

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
/// - Otherwise runs a regular tag search ordered by [rankTagSuggestions].
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
          .take(childPart.split(',').length - 1)
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

  final suggestions = await TagManager.instance.searchTags(trimmed);
  return rankTagSuggestions(
    suggestions.where((tag) => !isSelected(tag)),
    trimmed,
    isParent: hierarchyManager.isParent,
  ).take(10).toList(growable: false);
}

final _wordSeparators = RegExp(r'[\s_\-.:/()\[\]{}]+');

/// Orders matches by how well they fit [query]: exact, exact ignoring accents,
/// prefix, prefix ignoring accents, word start, then anywhere. Within a tier,
/// parents come first, then shorter names, then A-Z.
///
/// Search ignores accents, so "ro" matches "rõ" — but a plain A-Z sort puts
/// "rõ" after "robot" and even "bro"; ranking keeps the closest tag on top.
List<String> rankTagSuggestions(
  Iterable<String> tags,
  String query, {
  bool Function(String tag)? isParent,
}) {
  final lower = query.trim().toLowerCase();
  final folded = TextUtils.normalizeForSearch(lower);
  int tier(String tag) {
    final tagLower = tag.toLowerCase();
    final tagFolded = TextUtils.normalizeForSearch(tagLower);
    if (tagLower == lower) return 0;
    if (tagFolded == folded) return 1;
    if (tagLower.startsWith(lower)) return 2;
    if (tagFolded.startsWith(folded)) return 3;
    if (tagFolded.split(_wordSeparators).any((w) => w.startsWith(folded))) {
      return 4;
    }
    return 5;
  }

  final tiers = {for (final tag in tags) tag: tier(tag)};
  final parents = {
    for (final tag in tiers.keys) tag: isParent?.call(tag) ?? false,
  };
  return tiers.keys.toList()..sort((a, b) {
    final byTier = tiers[a]!.compareTo(tiers[b]!);
    if (byTier != 0) return byTier;
    if (parents[a] != parents[b]) return parents[a]! ? -1 : 1;
    final byLength = a.length.compareTo(b.length);
    if (byLength != 0) return byLength;
    return TextUtils.compareAlphabetically(a, b);
  });
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
      final prefix = commaIndex >= 0
          ? childrenPart.substring(0, commaIndex + 1)
          : '';
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
  List<String> childNames, {
  bool throwOnFailure = false,
}) async {
  final parentSaved = await TagManager.addStandaloneTag(parentName);
  if (!parentSaved && throwOnFailure) {
    throw StateError('Could not save tag $parentName');
  }
  for (final childName in childNames) {
    final childSaved = await TagManager.addStandaloneTag(childName);
    if (!childSaved && throwOnFailure) {
      throw StateError('Could not save tag $childName');
    }
    final ok = await hierarchyManager.addChild(parentName, childName);
    if (!ok) {
      AppLogger.warning(
        '[ManageTags] Failed to create hierarchy',
        error: 'parent=$parentName child=$childName',
      );
      if (throwOnFailure) {
        throw StateError('Could not link $parentName:$childName');
      }
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
              errorBuilder: (_, _, _) => Container(
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (parents.isNotEmpty)
                Text(
                  '${AppLocalizations.of(context)!.parentTagLabel}: ${parents.join(", ")}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
                    ),
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (children.isNotEmpty)
                Text(
                  '${AppLocalizations.of(context)!.childTagCount(children.length)}: ${children.take(3).join(", ")}${children.length > 3 ? "..." : ""}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
                    ),
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
