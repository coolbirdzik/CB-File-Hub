import 'dart:async';
import 'dart:math' as math;

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
  /// Press Tab, or Enter after arrow navigation, or click to pick a suggestion.
  final List<String> suggestions;

  /// Called when a suggestion is picked (via keyboard or click).
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
  /// level. While scoped, the draft is edited inside the parent's inline chip.
  /// The caller composes
  /// "parent:child" itself and decides when the scope is dropped.
  final String? scopeParent;

  /// Called when a parent is entered through its child action or ":" / "→",
  /// or left through Esc, Backspace on an empty draft, or the context's "x".
  /// Leaving this null keeps the older inline "parent:" prefix
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
  int _highlightedIndex = -1;
  bool _suggestionNavigated = false;
  bool _suggestionsDismissed = false;

  final LayerLink _layerLink = LayerLink();
  final GlobalKey _targetKey = GlobalKey();
  final GlobalKey _editableKey = GlobalKey();
  final ScrollController _suggestionScroll = ScrollController();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();

    controller = ChipsInputEditingController<T>(
      <T>[...widget.values],
      widget.chipBuilder,
      editingChild: widget.scopeParent != null,
    );
    controller.addListener(_textListener);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant ChipsInput<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.updateChildMode(widget.scopeParent != null);
    // Reset highlight when suggestions change
    if (widget.suggestions != oldWidget.suggestions) {
      _highlightedIndex = -1;
      _suggestionNavigated = false;
      _updateOverlay();
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _suggestionScroll.dispose();
    controller.removeListener(_textListener);
    controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    } else {
      _suggestionsDismissed = false;
      _updateOverlay();
    }
  }

  // ── Overlay management ──

  void _updateOverlay() {
    // Always defer overlay mutations to avoid calling setState/markNeedsBuild
    // during a build phase (e.g. when called from didUpdateWidget).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.suggestions.isNotEmpty &&
          _focusNode.hasFocus &&
          !_suggestionsDismissed) {
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
    return OverlayEntry(
      builder: (context) {
        final suggestions = widget.suggestions;
        if (suggestions.isEmpty) return const SizedBox.shrink();
        final renderBox = _targetKey.currentContext?.findRenderObject();
        if (renderBox is! RenderBox || !renderBox.hasSize) {
          return const SizedBox.shrink();
        }
        final size = renderBox.size;
        final position = renderBox.localToGlobal(Offset.zero);
        final media = MediaQuery.of(context);
        final below =
            media.size.height -
            media.viewInsets.bottom -
            media.padding.bottom -
            position.dy -
            size.height -
            8;
        final above = position.dy - media.padding.top - 8;
        final showAbove = below < 180 && above > below;
        final available = (showAbove ? above : below).clamp(80.0, 280.0);

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: showAbove
                ? Alignment.bottomLeft
                : Alignment.topLeft,
            offset: Offset(0, showAbove ? -4 : size.height + 4),
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
                            Expanded(
                              child: Text(
                                AppLocalizations.of(
                                      context,
                                    )?.tagSuggestionsLabel ??
                                    'Suggested tags',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            if (widget.onScopeChanged != null &&
                                widget.scopeParent == null) ...[
                              _keyHintBadge(theme, '→'),
                              const SizedBox(width: 4),
                            ],
                            _keyHintBadge(theme, '↑↓ Enter'),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: available - 40),
                        child: ListView.builder(
                          controller: _suggestionScroll,
                          itemExtent: _suggestionRowHeight,
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
    _clearDraft();
    _suggestionsDismissed = true;
    _removeOverlay();
    _focusNode.requestFocus();
  }

  double get _suggestionRowHeight => widget.suggestionBuilder == null ? 48 : 72;

  void _revealHighlightedSuggestion() {
    if (!_suggestionScroll.hasClients) return;
    final position = _suggestionScroll.position;
    final start = _highlightedIndex * _suggestionRowHeight;
    final end = start + _suggestionRowHeight;
    final offset = start < position.pixels
        ? start
        : end > position.pixels + position.viewportDimension
        ? end - position.viewportDimension
        : position.pixels;
    _suggestionScroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
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
    _suggestionsDismissed = false;
    _removeOverlay();
    widget.onScopeChanged!(parent);
    _restoreDraftFocusAfterScopeChange();
  }

  void _exitScope() {
    _clearDraft();
    _removeOverlay();
    widget.onScopeChanged?.call(null);
    _restoreDraftFocusAfterScopeChange();
  }

  /// Restore the editable draft's caret after a parent action changes layout.
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
  /// Clears only the editable draft, preserving selected chips and scope.
  void clearDraft() => _clearDraft();

  void _clearDraft() {
    final String chipChars = controller.prefixFor(
      valueCount: widget.values.length,
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

    // Chips sit in the text as placeholder characters, so the editor's own
    // clipboard actions would copy those instead of the tag names.
    final hardware = HardwareKeyboard.instance;
    if ((hardware.isControlPressed || hardware.isMetaPressed) &&
        !hardware.isAltPressed &&
        !hardware.isShiftPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyC && copyTags()) {
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyX && _cutTags()) {
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV &&
          widget.onSubmitted != null) {
        unawaited(_paste(SelectionChangedCause.keyboard));
        return KeyEventResult.handled;
      }
    }

    final bool scopeEnabled = widget.onScopeChanged != null;
    final String typed = controller.textWithoutReplacements;

    // Let the IME finish Vietnamese and other composed text first.
    if (controller.value.composing.isValid &&
        !controller.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (widget.scopeParent != null && scopeEnabled) {
        _exitScope();
        return KeyEventResult.handled;
      }
      if (_overlayEntry != null) {
        _suggestionsDismissed = true;
        _removeOverlay();
        return KeyEventResult.handled;
      }
    }

    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      // Preserve text-selection keys and Shift+Tab focus traversal. Colon is
      // the sole exception because keyboards commonly produce it with Shift.
      if (event.character != ':') return KeyEventResult.ignored;
    }

    // Leave the parent before allowing another Backspace to remove a chip.
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
      if (typed.trim().isNotEmpty && !typed.contains(':')) {
        final parent = suggestions.isNotEmpty && !_suggestionsDismissed
            ? suggestions[_highlightedIndex.clamp(0, suggestions.length - 1)]
            : typed.trim();
        if (scopeEnabled) {
          _enterScope(parent);
        } else {
          _promoteToParent(parent);
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
      if (suggestions.isNotEmpty && !_suggestionsDismissed) {
        final index = _highlightedIndex.clamp(0, suggestions.length - 1);
        _enterScope(suggestions[index]);
        return KeyEventResult.handled;
      }
      if (typedParent.isNotEmpty) {
        _enterScope(typedParent);
        return KeyEventResult.handled;
      }
    }

    if (suggestions.isEmpty || _suggestionsDismissed) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      // Pick the highlighted suggestion
      final index = _highlightedIndex.clamp(0, suggestions.length - 1);
      _pickSuggestion(suggestions[index]);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = _suggestionNavigated
            ? (_highlightedIndex + 1) % suggestions.length
            : 0;
        _suggestionNavigated = true;
      });
      _overlayEntry?.markNeedsBuild();
      _revealHighlightedSuggestion();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex = _suggestionNavigated
            ? (_highlightedIndex - 1 + suggestions.length) % suggestions.length
            : suggestions.length - 1;
        _suggestionNavigated = true;
      });
      _overlayEntry?.markNeedsBuild();
      _revealHighlightedSuggestion();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ── Clipboard ──

  /// Separates tags in copied text, and splits pasted text back into tags.
  static const String tagSeparator = ', ';
  static final RegExp _pastedTagSeparator = RegExp(r'[,;\n\r\t]+');

  /// Splits clipboard text into tag names; empty when it is not a tag list.
  /// "parent:child1, child2" stays whole: the field submits it as one
  /// hierarchy entry.
  static List<String> splitPastedTags(String text) {
    if (text.contains(':')) return const <String>[];
    return text
        .split(_pastedTagSeparator)
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  /// The chips and the draft text covered by the editor's selection.
  ({List<T> chips, String draft}) _selectedParts() {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return (chips: <T>[], draft: '');
    }
    final text = controller.text;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final prefix = controller
        .prefixFor(valueCount: widget.values.length)
        .length
        .clamp(0, widget.values.length);
    final chips = widget.values.sublist(
      math.min(start, prefix),
      math.min(end, prefix),
    );
    final draft = text
        .substring(math.max(start, prefix), math.max(end, prefix))
        .replaceAll(
          String.fromCharCode(
            ChipsInputEditingController.kObjectReplacementChar,
          ),
          '',
        );
    return (chips: chips, draft: draft);
  }

  /// Copies the tag names, joined by [tagSeparator]: the selected chips with
  /// any selected draft text, or every tag when no text is selected. Returns
  /// false, leaving the editor to copy, when only draft text is selected or
  /// there is nothing to copy.
  bool copyTags() {
    final parts = _selectedParts();
    final List<String> items;
    if (parts.chips.isNotEmpty) {
      final draft = parts.draft.trim();
      items = <String>[
        for (final chip in parts.chips) '$chip',
        if (draft.isNotEmpty) draft,
      ];
    } else if (parts.draft.isEmpty && widget.values.isNotEmpty) {
      items = <String>[for (final value in widget.values) '$value'];
    } else {
      return false;
    }
    unawaited(Clipboard.setData(ClipboardData(text: items.join(tagSeparator))));
    return true;
  }

  /// Cuts a selection that covers chips: copies it, then removes those tags
  /// and the selected draft text. Plain draft selections are left to the
  /// editor.
  bool _cutTags() {
    final parts = _selectedParts();
    if (parts.chips.isEmpty || !copyTags()) return false;
    final selection = controller.selection;
    final prefixLength = controller
        .prefixFor(valueCount: widget.values.length)
        .length;
    final draft = controller.textWithoutReplacements;
    final draftStart = (selection.start - prefixLength).clamp(0, draft.length);
    final draftEnd = (selection.end - prefixLength).clamp(0, draft.length);
    final remainingDraft =
        draft.substring(0, draftStart) + draft.substring(draftEnd);
    final remaining = <T>[...widget.values];
    for (final chip in parts.chips) {
      remaining.remove(chip);
    }
    final prefix = controller.prefixFor(valueCount: remaining.length);
    // The tags go through onChanged below; keep the text listener from
    // reading the shorter placeholder run as a second removal.
    _previousSelection = null;
    controller.value = TextEditingValue(
      text: '$prefix$remainingDraft',
      selection: TextSelection.collapsed(offset: prefix.length + draftStart),
    );
    widget.onChanged(remaining);
    widget.onTextChanged?.call(remainingDraft);
    return true;
  }

  /// Pastes a tag list (as [copyTags] writes it) as separate tags through
  /// [ChipsInput.onSubmitted]. Anything else, or a paste into a draft that
  /// keeps text outside the selection, is pasted as text by the editor.
  Future<void> _paste(SelectionChangedCause cause) async {
    final editable = _focusNode.context
        ?.findAncestorStateOfType<EditableTextState>();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final tags = splitPastedTags(data?.text ?? '');
    final draft = controller.textWithoutReplacements;
    final draftReplaced =
        draft.trim().isEmpty || _selectedParts().draft == draft;
    final onSubmitted = widget.onSubmitted;
    if (tags.length < 2 || !draftReplaced || onSubmitted == null) {
      await editable?.pasteText(cause);
      return;
    }
    editable?.hideToolbar();
    for (final tag in tags) {
      onSubmitted(tag);
    }
    _clearDraft();
    _focusNode.requestFocus();
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final items = <ContextMenuButtonItem>[
      for (final item in editableTextState.contextMenuButtonItems)
        switch (item.type) {
          ContextMenuButtonType.copy => item.copyWith(
            onPressed: () {
              if (copyTags()) {
                editableTextState.hideToolbar();
              } else {
                item.onPressed?.call();
              }
            },
          ),
          ContextMenuButtonType.cut => item.copyWith(
            onPressed: () {
              if (_cutTags()) {
                editableTextState.hideToolbar();
              } else {
                item.onPressed?.call();
              }
            },
          ),
          ContextMenuButtonType.paste when widget.onSubmitted != null =>
            item.copyWith(
              onPressed: () => unawaited(_paste(SelectionChangedCause.toolbar)),
            ),
          _ => item,
        },
    ];
    // Without a selection the editor offers no Copy; the tags still can be.
    if (widget.values.isNotEmpty &&
        !items.any((item) => item.type == ContextMenuButtonType.copy)) {
      items.insert(
        0,
        ContextMenuButtonItem(
          label: AppLocalizations.of(context)!.copyTags,
          onPressed: () {
            copyTags();
            editableTextState.hideToolbar();
          },
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  // ── Text listener ──

  void _textListener() {
    final String currentText = controller.text;

    if (_previousSelection != null && !controller.editingChild) {
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
    return countReplacements(text);
  }

  @override
  Widget build(BuildContext context) {
    controller.chipBuilder = widget.chipBuilder;
    controller.updateValues(<T>[...widget.values]);
    final parent = widget.scopeParent;
    final decoration = widget.decoration.copyWith(
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      isDense: false,
    );

    Widget draftField({Color? childColor}) => TextField(
      // Keep the same editor and text-input connection when moving into/out
      // of the parent chip. Only the editing mode and decoration change.
      key: _editableKey,
      minLines: 1,
      maxLines: parent == null ? 8 : 1,
      textInputAction: TextInputAction.done,
      style: parent == null
          ? widget.style
          : Theme.of(context).textTheme.bodyMedium!
                .merge(widget.style)
                .copyWith(fontSize: 13, color: childColor),
      strutStyle: parent == null
          ? widget.strutStyle ??
                const StrutStyle(
                  fontSize: _kStrutFontSize,
                  height: _kRowHeight / _kStrutFontSize,
                  forceStrutHeight: true,
                  leadingDistribution: TextLeadingDistribution.even,
                )
          : null,
      cursorHeight: parent == null
          ? (widget.style?.fontSize ?? _kStrutFontSize) * 1.25
          : 18,
      cursorColor: childColor,
      textAlignVertical: parent == null ? null : TextAlignVertical.center,
      controller: controller,
      focusNode: _focusNode,
      contextMenuBuilder: _buildContextMenu,
      inputFormatters: const [_ChipPrefixTextInputFormatter()],
      decoration: parent == null
          ? decoration
          : InputDecoration(
              hintText: AppLocalizations.of(context)!.childTagInputHint,
              hintStyle: TextStyle(
                color: childColor?.withValues(alpha: .65),
                fontSize: 13,
              ),
              isDense: true,
              // Let the chip's Row center the editor at its natural text height.
              // Neutral density avoids the compact theme's baseline offsets.
              isCollapsed: true,
              visualDensity: VisualDensity.standard,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
      onChanged: (_) {
        _suggestionsDismissed = false;
        _suggestionNavigated = false;
        _highlightedIndex = -1;
        widget.onTextChanged?.call(controller.textWithoutReplacements);
        setState(() {});
        _updateOverlay();
      },
      onSubmitted: (_) {
        if (_suggestionNavigated &&
            widget.suggestions.isNotEmpty &&
            !_suggestionsDismissed) {
          _pickSuggestion(widget.suggestions[_highlightedIndex]);
        } else {
          widget.onSubmitted?.call(controller.textWithoutReplacements);
          _clearDraft();
        }
        _focusNode.requestFocus();
      },
    );

    return CompositedTransformTarget(
      key: _targetKey,
      link: _layerLink,
      child: FocusScope(
        onKeyEvent: _handleKeyEvent,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: parent == null
              ? draftField()
              : InputDecorator(
                  decoration: decoration.copyWith(hintText: null),
                  isFocused: _focusNode.hasFocus,
                  isEmpty: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final tag in widget.values)
                          KeyedSubtree(
                            key: ValueKey<T>(tag),
                            child: widget.chipBuilder(context, tag),
                          ),
                        TagScopeChip(
                          parent: parent,
                          onExit: _exitScope,
                          maxWidth: constraints.maxWidth,
                          draft: controller.textWithoutReplacements,
                          inputBuilder: (color) =>
                              draftField(childColor: color),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class ChipsInputEditingController<T> extends TextEditingController {
  ChipsInputEditingController(
    this.values,
    this.chipBuilder, {
    this.editingChild = false,
  }) : super() {
    final text = prefixFor(valueCount: values.length);
    value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  // This constant character acts as a placeholder in the TextField text value.
  // There will be one character for each of the InputChip displayed.
  static const int kObjectReplacementChar = 0xFFFE;

  List<T> values;
  bool editingChild;

  void updateChildMode(bool enabled) {
    if (editingChild == enabled) return;
    final draft = textWithoutReplacements;
    editingChild = enabled;
    final prefix = prefixFor(valueCount: values.length);
    value = TextEditingValue(
      text: '$prefix$draft',
      selection: TextSelection.collapsed(offset: prefix.length + draft.length),
    );
  }

  /// Replaced on every build so chips never render through a stale closure.
  Widget Function(BuildContext context, T data) chipBuilder;

  /// Called whenever chip is either added or removed
  /// from the outside the context of the text field.
  void updateValues(List<T> values) {
    if (values.length != this.values.length) {
      final prefix = prefixFor(valueCount: values.length);
      final draft = textWithoutReplacements;
      value = TextEditingValue(
        text: '$prefix$draft',
        selection: TextSelection.collapsed(
          offset: prefix.length + draft.length,
        ),
      );
    }
    // Always take the new list: a same-length change (another file's tags,
    // a relabelled chip) must still repaint the chips.
    this.values = values;
  }

  String prefixFor({required int valueCount}) {
    if (editingChild) return '';
    final chip = String.fromCharCode(kObjectReplacementChar);
    return chip * valueCount;
  }

  String get textWithoutReplacements {
    final chip = String.fromCharCode(kObjectReplacementChar);
    return text.replaceAll(chip, '');
  }

  String get textWithReplacements => text;

  int get draftEndOffset => text.length;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (editingChild) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    // Create a list to hold all spans
    final List<InlineSpan> spans = <InlineSpan>[];

    // Chips are centered in the row; the forced strut in ChipsInputState
    // provides the vertical breathing room, so no per-row offsets are needed.
    for (int i = 0; i < values.length; i++) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            // Never transfer a deleted chip's animation/hover state to the
            // next tag at this placeholder position (opacity 0/isDeleting).
            key: ValueKey<T>(values[i]),
            padding: const EdgeInsets.only(right: 4),
            child: chipBuilder(context, values[i]),
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
/// selected chips.
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
    final chipCount = ChipsInputState.countReplacements(newValue.text);
    final prefixLength = chipCount;
    final draft = newValue.text.replaceAll(chipReplacement, '');
    final normalizedText = chipReplacement * chipCount + draft;

    int mapOffset(int offset) {
      if (offset < 0) return offset;
      final safeOffset = offset.clamp(0, newValue.text.length);
      final draftUnitsBeforeOffset = newValue.text
          .substring(0, safeOffset)
          .codeUnits
          .where(
            (unit) =>
                unit != ChipsInputEditingController.kObjectReplacementChar,
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

/// The inline parent chip contains the real child editor, including its caret.
class TagScopeChip extends StatelessWidget {
  const TagScopeChip({
    super.key,
    required this.parent,
    required this.onExit,
    required this.inputBuilder,
    required this.maxWidth,
    required this.draft,
  });

  final String parent;
  final VoidCallback onExit;
  final Widget Function(Color color) inputBuilder;
  final double maxWidth;
  final String draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;
    final tagColor = TagColorManager.instance.getTagColor(parent);
    final foreground = TagChipStyle.readableOn(
      Color.alphaBlend(
        TagChipStyle.tint(tagColor, isDark: isDark),
        theme.colorScheme.surface,
      ),
    );
    final color = foreground == Colors.white ? Colors.white : tagColor;
    final textStyle = theme.textTheme.bodyMedium!.copyWith(fontSize: 13);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final showLabel = maxWidth >= 240;
    final labelStyle = textStyle.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    final parentStyle = textStyle.copyWith(
      fontWeight: FontWeight.w700,
      color: color,
    );
    final parentWidth = measure(parent, parentStyle).clamp(0.0, maxWidth * .32);
    final labelWidth = showLabel
        ? measure('${l10n.parentTagLabel}:', labelStyle) + 4
        : 0;
    final inputWidth =
        measure(draft.isEmpty ? l10n.childTagInputHint : draft, textStyle) + 16;
    final width =
        (labelWidth + parentWidth + inputWidth.clamp(80.0, maxWidth) + 52)
            .clamp(0.0, maxWidth);

    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: TagChipStyle.decoration(tagColor, isDark: isDark),
      child: Row(
        children: [
          if (showLabel) ...[
            Text(
              '${l10n.parentTagLabel}:',
              style: labelStyle.copyWith(color: color.withValues(alpha: .72)),
            ),
            const SizedBox(width: 4),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth * .32),
            child: Tooltip(
              message: parent,
              child: Text(
                parent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: parentStyle,
              ),
            ),
          ),
          Icon(
            PhosphorIconsLight.caretRight,
            size: 12,
            color: color.withValues(alpha: .7),
          ),
          const SizedBox(width: 4),
          Expanded(child: inputBuilder(color)),
          IconButton(
            tooltip: l10n.exitTagScope(parent),
            onPressed: onExit,
            constraints: const BoxConstraints.tightFor(width: 24, height: 32),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              minimumSize: const Size(24, 32),
              maximumSize: const Size(24, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            icon: Icon(PhosphorIconsLight.x, size: 12, color: color),
          ),
        ],
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
    this.label,
    this.tooltip,
  });

  final String tag;
  final ValueChanged<String> onDeleted;
  final ValueChanged<String> onSelected;

  /// Text shown instead of [tag]; colour and callbacks still use [tag].
  final String? label;
  final String? tooltip;

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

    final chip = AnimatedBuilder(
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
                              widget.label ?? widget.tag,
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
    final tooltip = widget.tooltip;
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }
}
