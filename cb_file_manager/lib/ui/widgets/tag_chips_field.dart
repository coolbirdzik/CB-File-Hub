import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:cb_file_manager/ui/widgets/tag_input_helpers.dart';

/// The tag field shared by the Manage Tags dialogs and the properties pane:
/// assigned tags sit as chips inside the input, suggestions show thumbnails
/// and hierarchy, and ":" / "→" scope the draft under a parent tag.
///
/// Callers own the tag list and the draft/scope state; removing a chip (its
/// "x" or Backspace) is reported per tag through [onRemoved].
class TagChipsField extends StatelessWidget {
  const TagChipsField({
    super.key,
    this.fieldKey,
    required this.tags,
    required this.suggestions,
    required this.scopeParent,
    required this.onScopeChanged,
    required this.onSuggestionSelected,
    required this.onTextChanged,
    required this.onSubmitted,
    required this.onRemoved,
    this.onChipTapped,
    this.chipLabel,
    this.chipTooltip,
    this.hintText,
  });

  /// Lets the owner call [ChipsInputState.clearDraft].
  final GlobalKey<ChipsInputState<String>>? fieldKey;
  final List<String> tags;
  final List<String> suggestions;
  final String? scopeParent;
  final ValueChanged<String?> onScopeChanged;
  final ValueChanged<String> onSuggestionSelected;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onRemoved;
  final ValueChanged<String>? onChipTapped;

  /// Overrides a chip's text, e.g. "work 1/2" for a partial multi-selection.
  final String Function(String tag)? chipLabel;
  final String? Function(String tag)? chipTooltip;

  /// Hint when not scoped; a scoped field always hints at the child name.
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scope = scopeParent;
    return ChipsInput<String>(
      key: fieldKey,
      values: tags,
      suggestions: suggestions,
      enableColonAutocomplete: true,
      scopeParent: scope,
      onScopeChanged: onScopeChanged,
      onSuggestionSelected: onSuggestionSelected,
      suggestionBuilder: (context, suggestion, isHighlighted, tagColor) =>
          buildTagSuggestionItem(
            context,
            suggestion,
            isHighlighted,
            tagColor,
            thumbnailManager: TagThumbnailManager.instance,
            hierarchyManager: TagHierarchyManager.instance,
          ),
      decoration: InputDecoration(
        labelText: l10n.tagName,
        hintText: scope != null
            ? l10n.childTagHint(scope)
            : hintText ?? l10n.enterTagName,
        prefixIcon: const Icon(PhosphorIconsLight.tag),
      ).flat(context, radius: 16),
      style: const TextStyle(fontSize: 16),
      onChanged: (updated) {
        for (final tag in tags) {
          if (!updated.contains(tag)) onRemoved(tag);
        }
      },
      onTextChanged: onTextChanged,
      onSubmitted: onSubmitted,
      chipBuilder: (context, tag) => TagInputChip(
        tag: tag,
        label: chipLabel?.call(tag),
        tooltip: chipTooltip?.call(tag),
        onDeleted: onRemoved,
        onSelected: onChipTapped ?? (_) {},
      ),
    );
  }
}
