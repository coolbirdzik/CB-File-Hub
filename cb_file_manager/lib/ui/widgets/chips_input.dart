import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';
import 'package:cb_file_manager/ui/widgets/tag_chip.dart';

class ChipsInput<T> extends StatefulWidget {
  const ChipsInput({
    super.key,
    required this.values,
    this.decoration = const InputDecoration(),
    this.style,
    this.strutStyle,
    required this.chipBuilder,
    required this.onChanged,
    this.onChipTapped,
    this.onSubmitted,
    this.onTextChanged,
    this.suggestions = const [],
    this.onSuggestionSelected,
    this.suggestionBuilder,
    this.enableColonAutocomplete = false,
    this.scopeParent,
    this.onScopeChanged,
  });

  final List<T> values;
  final InputDecoration decoration;
  final TextStyle? style;
  final StrutStyle? strutStyle;

  final ValueChanged<List<T>> onChanged;
  final ValueChanged<T>? onChipTapped;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onTextChanged;

  /// Autocomplete suggestions shown below the input.
  /// Press Tab or click to pick a suggestion.
  final List<String> suggestions;

  /// Called when a suggestion is picked (via Tab or click).
  final ValueChanged<String>? onSuggestionSelected;

  /// Custom builder for suggestion items. If null, uses default rendering.
  /// Parameters: context, suggestion string, isHighlighted, tagColor.
  final Widget Function(
    BuildContext context,
    String suggestion,
    bool isHighlighted,
    Color tagColor,
  )?
  suggestionBuilder;

  /// When true, pressing ":" while a suggestion is highlighted promotes that
  /// suggestion into a "parent:" prefix in the input, so the user can keep
  /// typing/autocompleting the child tag. Used for the parent:child hierarchy
  /// syntax in the tag dialog.
  final bool enableColonAutocomplete;

  /// The parent tag the field is scoped to, or null when typing at the top
  /// level. While scoped, a pill is shown after the selected tag chips and
  /// immediately before the child draft — the caller composes
  /// "parent:child" itself and decides when the scope is dropped.
  final String? scopeParent;

  /// Called when the scope changes: a parent is entered (":" or "->" on a
  /// highlighted suggestion) or left (Backspace on an empty draft, or the
  /// pill's "x"). Leaving this null keeps the older inline "parent:" prefix
  /// behavior of [enableColonAutocomplete].
  final ValueChanged<String?>? onScopeChanged;

  final Widget Function(BuildContext context, T data) chipBuilder;

  @override
  ChipsInputState<T> createState() => ChipsInputState<T>();
}

class ChipsInputState<T> extends State<ChipsInput<T>> {
  /// Height of one row of the field. The strut is forced to it so a row of
  /// chips and a row of plain text are the same height (the field does not
  /// jump when the first chip lands) and is taller than a chip, so chips
  /// neither touch the floating label / border nor overlap when they wrap.
  static const double _kRowHeight = 36;
  static const double _kStrutFontSize = 16;

  late final ChipsInputEditingController<T> controller;
  late final FocusNode _focusNode;

  String _previousText = '';
  TextSelection? _previousSelection;

  /// Index of the currently highlighted suggestion (-1 = none).
  int _highlightedIndex = 0;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();

    controller = ChipsInputEditingController<T>(
      <T>[...widget.values],
      widget.chipBuilder,
      _exitScope,
      scopeParent: widget.scopeParent,
    );
    controller.addListener(_textListener);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant ChipsInput<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset highlight when suggestions change
    if (widget.suggestions != oldWidget.suggestions) {
      _highlightedIndex = 0;
      _updateOverlay();
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    controller.removeListener(_textListener);
    controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    } else {
      _updateOverlay();
    }
  }

  // ── Overlay management ──

  void _updateOverlay() {
    // Always defer overlay mutations to avoid calling setState/markNeedsBuild
    // during a build phase (e.g. when called from didUpdateWidget).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.suggestions.isNotEmpty && _focusNode.hasFocus) {
        if (_overlayEntry != null) {
          _overlayEntry!.markNeedsBuild();
        } else {
          _overlayEntry = _buildOverlayEntry();
          Overlay.of(context).insert(_overlayEntry!);
        }
      } else {
        _removeOverlay();
      }
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _buildOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) {
        final suggestions = widget.suggestions;
        if (suggestions.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 4),
            child: TextFieldTapRegion(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Color.alphaBlend(
                  isDark
                      ? theme.colorScheme.surfaceContainerHigh
                      : theme.colorScheme.surface,
                  isDark ? const Color(0xFF1E1E1E) : Colors.white,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Row(
                          children: [
                            Icon(
                              PhosphorIconsLight.magnifyingGlass,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Suggestions',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            const Spacer(),
                            if (widget.onScopeChanged != null &&
                                widget.scopeParent == null) ...[
                              _keyHintBadge(theme, '→'),
                              const SizedBox(width: 4),
                            ],
                            _keyHintBadge(theme, 'Tab ↹'),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          itemCount: suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = suggestions[index];
                            final isHighlighted = index == _highlightedIndex;
                            final tagColor = TagColorManager.instance
                                .getTagColor(suggestion);

                            // Use custom builder if provided
                            if (widget.suggestionBuilder != null) {
                              return InkWell(
                                onTap: () => _pickSuggestion(suggestion),
                                child: Container(
                                  color: isHighlighted
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.1,
                                        )
                                      : null,
                                  child: widget.suggestionBuilder!(
                                    context,
                                    suggestion,
                                    isHighlighted,
                                    tagColor,
                                  ),
                                ),
                              );
                            }

                            return InkWell(
                              onTap: () => _pickSuggestion(suggestion),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                color: isHighlighted
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.1,
                                      )
                                    : null,
                                child: Row(
                                  children: [
                                    Icon(
                                      PhosphorIconsLight.tag,
                                      size: 16,
                                      color: tagColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        suggestion,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isHighlighted
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: theme.colorScheme.onSurface,
                                        ),
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
        );
      },
    );
  }

  /// Small keycap badge in the suggestion overlay header.
  Widget _keyHintBadge(ThemeData theme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  void _pickSuggestion(String suggestion) {
    widget.onSuggestionSelected?.call(suggestion);
    _focusNode.requestFocus();
  }

  /// Replaces the currently-typed text with `"<parent>:"` so the user can keep
  /// typing/autocompleting the child tag.
  void _promoteToParent(String parent) {
    final String chipChars =
        String.fromCharCode(
          ChipsInputEditingController.kObjectReplacementChar,
        ) *
        widget.values.length;
    final String newTyped = '$parent:';
    controller.value = TextEditingValue(
      text: '$chipChars$newTyped',
      selection: TextSelection.collapsed(
        offset: chipChars.length + newTyped.length,
      ),
    );
    _focusNode.requestFocus();
    widget.onTextChanged?.call(newTyped);
  }

  /// Enters [parent] as the field's scope: the draft is cleared and the parent
  /// is handed to the caller, which shows it as a pill and composes
  /// "parent:child" on every submit until the scope is left.
  void _enterScope(String parent) {
    _clearDraft();
    widget.onScopeChanged!(parent);
    _restoreDraftFocusAfterScopeChange();
  }

  void _exitScope() {
    widget.onScopeChanged?.call(null);
    _restoreDraftFocusAfterScopeChange();
  }

  /// A scope change rebuilds the multiline field to insert/remove the parent
  /// pill. With many wrapped chips Flutter can restore the click-derived text
  /// selection after that rebuild, which puts the caret near the first chip.
  /// Re-assert the logical draft end after layout so child typing always
  /// resumes after every selected tag.
  void _restoreDraftFocusAfterScopeChange() {
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final draftEnd = controller.draftEndOffset;
      controller.selection = TextSelection.collapsed(offset: draftEnd);
      _focusNode.requestFocus();
    });
  }

  /// Wipes the typed draft while keeping the chips. Programmatic controller
  /// writes do not fire [TextField.onChanged], so [onTextChanged] is notified
  /// by hand.
  void _clearDraft() {
    final String chipChars = controller.prefixFor(
      valueCount: widget.values.length,
      scopeParent: widget.scopeParent,
    );
    controller.value = TextEditingValue(
      text: chipChars,
      selection: TextSelection.collapsed(offset: chipChars.length),
    );
    widget.onTextChanged?.call('');
  }

  // ── Key handling (Tab / Arrow navigation) ──

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final suggestions = widget.suggestions;

    // The replacement characters represent existing chips and must not be
    // included when selecting the editable draft. Otherwise, typing after
    // Ctrl/Cmd+A removes those placeholders while the chips are still present,
    // causing the new text to render on top of the existing tags.
    final isSelectAll =
        event.logicalKey == LogicalKeyboardKey.keyA &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
    if (isSelectAll) {
      final draftStart = countPrefixReplacements(controller.text);
      controller.selection = TextSelection(
        baseOffset: draftStart,
        extentOffset: controller.text.length,
      );
      return KeyEventResult.handled;
    }

    final bool scopeEnabled = widget.onScopeChanged != null;
    final String typed = controller.textWithoutReplacements;

    // Backspace on an empty draft leaves the parent scope. The pill sits
    // between the chips and the caret, so it is what Backspace reaches first;
    // deleting a chip stays one Backspace further back.
    if (scopeEnabled &&
        widget.scopeParent != null &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        typed.isEmpty) {
      _exitScope();
      return KeyEventResult.handled;
    }

    // ":" turns the highlighted suggestion into the parent tag: the pill in
    // scope mode, an inline "parent:" prefix otherwise. While scoped the key
    // is swallowed so the draft never carries a colon of its own — the caller
    // composes "parent:child" from the scope, and a second colon would make
    // "parent:child:grandchild", which parseHierarchyInput cannot represent.
    if (widget.enableColonAutocomplete && event.character == ':') {
      if (scopeEnabled && widget.scopeParent != null) {
        return KeyEventResult.handled;
      }
      if (suggestions.isNotEmpty && !typed.contains(':')) {
        final index = _highlightedIndex.clamp(0, suggestions.length - 1);
        if (scopeEnabled) {
          _enterScope(suggestions[index]);
        } else {
          _promoteToParent(suggestions[index]);
        }
        return KeyEventResult.handled;
      }
    }

    // Right arrow drills into the highlighted suggestion, but only with the
    // caret already parked at the end of the draft, so it still moves the
    // cursor everywhere else. If autocomplete has no match (or has not
    // arrived yet), the typed draft becomes a new parent instead. This makes
    // "type parent, then press right" a consistent way to start a child tag.
    if (scopeEnabled &&
        widget.scopeParent == null &&
        event.logicalKey == LogicalKeyboardKey.arrowRight &&
        controller.selection.isCollapsed &&
        controller.selection.baseOffset >= controller.text.length) {
      final typedParent = typed.trim();
      if (suggestions.isNotEmpty) {
        final index = _highlightedIndex.clamp(0, suggestions.length - 1);
        _enterScope(suggestions[index]);
        return KeyEventResult.handled;
      }
      if (typedParent.isNotEmpty) {
        _enterScope(typedParent);
        return KeyEventResult.handled;
      }
    }

    if (suggestions.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      // Pick the highlighted suggestion
      final index = _highlightedIndex.clamp(0, suggestions.length - 1);
      _pickSuggestion(suggestions[index]);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % suggestions.length;
      });
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex =
            (_highlightedIndex - 1 + suggestions.length) % suggestions.length;
      });
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ── Text listener ──

  void _textListener() {
    final String currentText = controller.text;

    if (_previousSelection != null) {
      final int currentNumber = countReplacements(currentText);
      final int previousNumber = countReplacements(_previousText);

      final int cursorEnd = _previousSelection!.extentOffset;
      final int cursorStart = _previousSelection!.baseOffset;

      final List<T> values = <T>[...widget.values];

      // If the current number and the previous number of replacements are different, then
      // the user has deleted the InputChip using the keyboard. In this case, we trigger
      // the onChanged callback. We need to be sure also that the current number of
      // replacements is different from the input chip to avoid double-deletion.
      if (currentNumber < previousNumber && currentNumber != values.length) {
        if (cursorStart == cursorEnd) {
          values.removeRange(cursorStart - 1, cursorEnd);
        } else {
          if (cursorStart > cursorEnd) {
            values.removeRange(cursorEnd, cursorStart);
          } else {
            values.removeRange(cursorStart, cursorEnd);
          }
        }
        widget.onChanged(values);
      }
    }

    _previousText = currentText;
    _previousSelection = controller.selection;
  }

  static int countReplacements(String text) {
    return text.codeUnits
        .where(
          (int u) => u == ChipsInputEditingController.kObjectReplacementChar,
        )
        .length;
  }

  static int countPrefixReplacements(String text) {
    return text.codeUnits.where((int unit) {
      return unit == ChipsInputEditingController.kObjectReplacementChar ||
          unit == ChipsInputEditingController.kScopeReplacementChar;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    controller.updateValues(<T>[...widget.values]);
    controller.updateScope(widget.scopeParent, _exitScope);

    // Create a decoration that ensures proper padding for chips
    final InputDecoration adjustedDecoration = widget.decoration.copyWith(
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      isDense: false,
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: FocusScope(
        onKeyEvent: _handleKeyEvent,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: TextField(
            minLines: 1,
            maxLines: 8,
            textInputAction: TextInputAction.done,
            style: widget.style,
            strutStyle:
                widget.strutStyle ??
                const StrutStyle(
                  fontSize: _kStrutFontSize,
                  height: _kRowHeight / _kStrutFontSize,
                  forceStrutHeight: true,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
            // Keep the caret text-sized; it would otherwise span the whole row.
            cursorHeight: widget.strutStyle == null
                ? (widget.style?.fontSize ?? _kStrutFontSize) * 1.25
                : null,
            controller: controller,
            focusNode: _focusNode,
            inputFormatters: const <TextInputFormatter>[
              _ChipPrefixTextInputFormatter(),
            ],
            decoration: adjustedDecoration,
            onChanged: (String value) =>
                widget.onTextChanged?.call(controller.textWithoutReplacements),
            onSubmitted: (String value) {
              widget.onSubmitted?.call(controller.textWithoutReplacements);
              // Re-focus the input so the user can continue typing tags
              _focusNode.requestFocus();
            },
          ),
        ),
      ),
    );
  }
}

class ChipsInputEditingController<T> extends TextEditingController {
  ChipsInputEditingController(
    this.values,
    this.chipBuilder,
    this._onScopeExit, {
    this.scopeParent,
  }) : super() {
    final prefix = prefixFor(
      valueCount: values.length,
      scopeParent: scopeParent,
    );
    final text = _emptyDraftText(prefix, scopeParent);
    value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: prefix.length),
    );
  }

  // This constant character acts as a placeholder in the TextField text value.
  // There will be one character for each of the InputChip displayed.
  static const int kObjectReplacementChar = 0xFFFE;

  /// A separate placeholder keeps the parent scope pill in the editable text
  /// flow without making it look like one of the selected value chips.
  static const int kScopeReplacementChar = 0xFFFC;

  /// One replacement character for the visible inline child-input hint.
  /// The caret sits immediately before it; typing replaces it with the draft.
  static const int kInputHintReplacementChar = 0xFFFB;

  List<T> values;
  String? scopeParent;
  VoidCallback _onScopeExit;

  final Widget Function(BuildContext context, T data) chipBuilder;

  /// Called whenever chip is either added or removed
  /// from the outside the context of the text field.
  void updateValues(List<T> values) {
    if (values.length != this.values.length) {
      final prefix = prefixFor(
        valueCount: values.length,
        scopeParent: scopeParent,
      );
      final text = _emptyDraftText(prefix, scopeParent);
      value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: prefix.length),
      );
      this.values = values;
    }
  }

  void updateScope(String? scopeParent, VoidCallback onScopeExit) {
    _onScopeExit = onScopeExit;
    if (scopeParent == this.scopeParent) return;

    final draft = textWithoutReplacements;
    this.scopeParent = scopeParent;
    final prefix = prefixFor(
      valueCount: values.length,
      scopeParent: scopeParent,
    );
    final text = draft.isEmpty
        ? _emptyDraftText(prefix, scopeParent)
        : '$prefix$draft';
    value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: draft.isEmpty ? prefix.length : text.length,
      ),
    );
  }

  String prefixFor({required int valueCount, required String? scopeParent}) {
    final chip = String.fromCharCode(kObjectReplacementChar);
    final scope = String.fromCharCode(kScopeReplacementChar);
    return '${chip * valueCount}${scopeParent == null ? '' : scope}';
  }

  String _emptyDraftText(String prefix, String? scopeParent) {
    if (scopeParent == null) return prefix;
    return '$prefix${String.fromCharCode(kInputHintReplacementChar)}';
  }

  String get textWithoutReplacements {
    final chip = String.fromCharCode(kObjectReplacementChar);
    final scope = String.fromCharCode(kScopeReplacementChar);
    final hint = String.fromCharCode(kInputHintReplacementChar);
    return text.replaceAll(chip, '').replaceAll(scope, '').replaceAll(hint, '');
  }

  String get textWithReplacements => text;

  int get draftEndOffset {
    final hintIndex = text.codeUnits.indexOf(kInputHintReplacementChar);
    return hintIndex < 0 ? text.length : hintIndex;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Create a list to hold all spans
    final List<InlineSpan> spans = <InlineSpan>[];

    // Chips are centered in the row; the forced strut in ChipsInputState
    // provides the vertical breathing room, so no per-row offsets are needed.
    for (int i = 0; i < values.length; i++) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: chipBuilder(context, values[i]),
          ),
        ),
      );
    }

    final parent = scopeParent;
    if (parent != null) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: TagScopeChip(parent: parent, onExit: _onScopeExit),
        ),
      );
    }

    if (text.codeUnits.contains(kInputHintReplacementChar)) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: ChildTagInputHint(
            label: AppLocalizations.of(context)!.childTagInputHint,
          ),
        ),
      );
    }

    // Add text input after chips
    if (textWithoutReplacements.isNotEmpty) {
      spans.add(TextSpan(text: textWithoutReplacements));
    }

    return TextSpan(style: style, children: spans);
  }
}

/// Keeps the editable draft after the replacement characters that represent
/// selected chips and the optional parent-scope pill.
///
/// Flutter can place the raw text selection before (or between) replacement
/// characters when a user clicks a wrapped chip field. The controller renders
/// the draft after all chips, so inserting at that raw offset makes the caret
/// appear to jump back into the chip list. Canonicalizing the editing value
/// keeps the raw text order aligned with the visual order while preserving the
/// draft-relative selection and IME composing range.
class _ChipPrefixTextInputFormatter extends TextInputFormatter {
  const _ChipPrefixTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final chipReplacement = String.fromCharCode(
      ChipsInputEditingController.kObjectReplacementChar,
    );
    final scopeReplacement = String.fromCharCode(
      ChipsInputEditingController.kScopeReplacementChar,
    );
    final hintReplacement = String.fromCharCode(
      ChipsInputEditingController.kInputHintReplacementChar,
    );
    final chipCount = ChipsInputState.countReplacements(newValue.text);
    final scopeCount = newValue.text.codeUnits
        .where(
          (unit) => unit == ChipsInputEditingController.kScopeReplacementChar,
        )
        .length;
    final prefixLength = chipCount + scopeCount;
    final draft = newValue.text
        .replaceAll(chipReplacement, '')
        .replaceAll(scopeReplacement, '')
        .replaceAll(hintReplacement, '');
    final normalizedText =
        chipReplacement * chipCount +
        scopeReplacement * scopeCount +
        (scopeCount > 0 && draft.isEmpty ? hintReplacement : draft);

    int mapOffset(int offset) {
      if (offset < 0) return offset;
      final safeOffset = offset.clamp(0, newValue.text.length);
      final draftUnitsBeforeOffset = newValue.text
          .substring(0, safeOffset)
          .codeUnits
          .where(
            (unit) =>
                unit != ChipsInputEditingController.kObjectReplacementChar &&
                unit != ChipsInputEditingController.kScopeReplacementChar &&
                unit != ChipsInputEditingController.kInputHintReplacementChar,
          )
          .length;
      return prefixLength + draftUnitsBeforeOffset;
    }

    final selection = TextSelection(
      baseOffset: mapOffset(newValue.selection.baseOffset),
      extentOffset: mapOffset(newValue.selection.extentOffset),
      affinity: newValue.selection.affinity,
      isDirectional: newValue.selection.isDirectional,
    );

    final composing = newValue.composing.isValid
        ? TextRange(
            start: mapOffset(newValue.composing.start),
            end: mapOffset(newValue.composing.end),
          )
        : TextRange.empty;

    return newValue.copyWith(
      text: normalizedText,
      selection: selection,
      composing: composing,
    );
  }
}

/// The parent pill that rides after selected chips in a scoped [ChipsInput]:
/// while it is showing, everything typed after it is added as a child of
/// [parent]. It deliberately reads as a breadcrumb rather than a tag chip.
class TagScopeChip extends StatelessWidget {
  const TagScopeChip({super.key, required this.parent, required this.onExit});

  final String parent;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;
    final tagColor = TagColorManager.instance.getTagColor(parent);
    final foregroundColor = TagChipStyle.readableOn(
      Color.alphaBlend(
        TagChipStyle.tint(tagColor, isDark: isDark),
        theme.colorScheme.surface,
      ),
    );
    final contentColor = foregroundColor == Colors.white
        ? Colors.white
        : tagColor;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 5, 5),
        decoration: TagChipStyle.decoration(tagColor, isDark: isDark),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${l10n.parentTagLabel}:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: contentColor.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                parent,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: contentColor,
                ),
              ),
            ),
            Icon(
              PhosphorIconsLight.caretRight,
              size: 12,
              color: contentColor.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 5),
            Tooltip(
              message: l10n.exitTagScope(parent),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onExit,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    PhosphorIconsLight.x,
                    size: 12,
                    color: contentColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ghost text rendered at the actual child-draft caret position. It occupies
/// one replacement character and disappears as soon as the user types.
class ChildTagInputHint extends StatelessWidget {
  const ChildTagInputHint({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.62);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: color,
        ),
      ),
    );
  }
}

class TagInputChip extends StatefulWidget {
  const TagInputChip({
    super.key,
    required this.tag,
    required this.onDeleted,
    required this.onSelected,
  });

  final String tag;
  final ValueChanged<String> onDeleted;
  final ValueChanged<String> onSelected;

  @override
  State<TagInputChip> createState() => _TagInputChipState();
}

class _TagInputChipState extends State<TagInputChip>
    with SingleTickerProviderStateMixin {
  bool isHovered = false;
  bool isDeleting = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDelete() async {
    setState(() => isDeleting = true);
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDeleted(widget.tag);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tagColor = TagColorManager.instance.getTagColor(widget.tag);
    final foregroundColor = TagChipStyle.readableOn(
      Color.alphaBlend(
        TagChipStyle.tint(tagColor, isDark: isDark),
        Theme.of(context).colorScheme.surface,
      ),
    );
    final contentColor = foregroundColor == Colors.white
        ? Colors.white
        : tagColor;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              child: MouseRegion(
                onEnter: (_) => setState(() => isHovered = true),
                onExit: (_) => setState(() => isHovered = false),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: isDeleting
                        ? null
                        : () => widget.onSelected(widget.tag),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: TagChipStyle.decoration(
                        tagColor,
                        isDark: isDark,
                        hovered: isHovered,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsLight.tag,
                            size: 14,
                            color: contentColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              widget.tag,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: contentColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: isDeleting ? null : _handleDelete,
                            child: Icon(
                              PhosphorIconsLight.x,
                              size: 14,
                              color: contentColor,
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
        );
      },
    );
  }
}
