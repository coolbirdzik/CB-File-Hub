import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';

class ChipsInput<T> extends StatefulWidget {
  const ChipsInput({
    Key? key,
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
  }) : super(key: key);

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
  final Widget Function(BuildContext context, String suggestion,
      bool isHighlighted, Color tagColor)? suggestionBuilder;

  /// When true, pressing ":" while a suggestion is highlighted promotes that
  /// suggestion into a "parent:" prefix in the input, so the user can keep
  /// typing/autocompleting the child tag. Used for the parent:child hierarchy
  /// syntax in the tag dialog.
  final bool enableColonAutocomplete;

  final Widget Function(BuildContext context, T data) chipBuilder;

  @override
  ChipsInputState<T> createState() => ChipsInputState<T>();
}

class ChipsInputState<T> extends State<ChipsInput<T>> {
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
        <T>[...widget.values], widget.chipBuilder);
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Tab ↹',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
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
                                      ? theme.colorScheme.primary
                                          .withValues(alpha: 0.1)
                                      : null,
                                  child: widget.suggestionBuilder!(context,
                                      suggestion, isHighlighted, tagColor),
                                ),
                              );
                            }

                            return InkWell(
                              onTap: () => _pickSuggestion(suggestion),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                color: isHighlighted
                                    ? theme.colorScheme.primary
                                        .withValues(alpha: 0.1)
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

  void _pickSuggestion(String suggestion) {
    widget.onSuggestionSelected?.call(suggestion);
    _focusNode.requestFocus();
  }

  /// Replaces the currently-typed text with "<parent>:" so the user can keep
  /// typing/autocompleting the child tag.
  void _promoteToParent(String parent) {
    final String chipChars = String.fromCharCode(
            ChipsInputEditingController.kObjectReplacementChar) *
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

  // ── Key handling (Tab / Arrow navigation) ──

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final suggestions = widget.suggestions;

    // Promote the highlighted suggestion into a "parent:" prefix when the user
    // presses ":". Lets the user autocomplete the parent tag, then keep typing
    // the child tag (parent:child hierarchy syntax).
    if (widget.enableColonAutocomplete &&
        event.character == ':' &&
        suggestions.isNotEmpty) {
      final typed = controller.textWithoutReplacements;
      if (!typed.contains(':')) {
        final index = _highlightedIndex.clamp(0, suggestions.length - 1);
        _promoteToParent(suggestions[index]);
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
            (int u) => u == ChipsInputEditingController.kObjectReplacementChar)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    controller.updateValues(<T>[...widget.values]);

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
            strutStyle: widget.strutStyle ??
                const StrutStyle(forceStrutHeight: true, height: 1.25),
            controller: controller,
            focusNode: _focusNode,
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
  ChipsInputEditingController(this.values, this.chipBuilder)
      : super(
            text: String.fromCharCode(kObjectReplacementChar) * values.length);

  // This constant character acts as a placeholder in the TextField text value.
  // There will be one character for each of the InputChip displayed.
  static const int kObjectReplacementChar = 0xFFFE;

  List<T> values;

  final Widget Function(BuildContext context, T data) chipBuilder;

  /// Called whenever chip is either added or removed
  /// from the outside the context of the text field.
  void updateValues(List<T> values) {
    if (values.length != this.values.length) {
      final String char = String.fromCharCode(kObjectReplacementChar);
      final int length = values.length;
      value = TextEditingValue(
        text: char * length,
        selection: TextSelection.collapsed(offset: length),
      );
      this.values = values;
    }
  }

  String get textWithoutReplacements {
    final String char = String.fromCharCode(kObjectReplacementChar);
    return text.replaceAll(RegExp(char), '');
  }

  String get textWithReplacements => text;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Create a list to hold all spans
    final List<InlineSpan> spans = <InlineSpan>[];

    // Determine if we need to add line breaks for better spacing
    int currentLineWidth = 0;
    int currentLineCount = 0;
    const int maxLineWidth = 400; // Rough estimate of max line width

    // Add each chip with proper spacing
    for (int i = 0; i < values.length; i++) {
      // Estimate width of this chip (rough approximation)
      final chipWidth = 80 + (values[i].toString().length * 5);

      // Check if we need to add a line break
      if (currentLineWidth > 0 && currentLineWidth + chipWidth > maxLineWidth) {
        // Reset line width and increment line count
        currentLineWidth = 0;
        currentLineCount++;
      }

      // Keep chips visually centered inside the text field line box.
      final verticalPadding = currentLineCount > 0 ? 4.0 : 0.0;

      // Add the chip widget
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: EdgeInsets.only(right: 4, bottom: verticalPadding, top: 0),
          child: Transform.translate(
            offset: const Offset(0, 2),
            child: chipBuilder(context, values[i]),
          ),
        ),
      ));

      // Update current line width
      currentLineWidth += chipWidth;
    }

    // Add text input after chips
    if (textWithoutReplacements.isNotEmpty) {
      spans.add(TextSpan(text: textWithoutReplacements));
    }

    return TextSpan(
      style: style,
      children: spans,
    );
  }
}

class TagInputChip extends StatefulWidget {
  const TagInputChip({
    Key? key,
    required this.tag,
    required this.onDeleted,
    required this.onSelected,
  }) : super(key: key);

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
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
    final backgroundColor = tagColor.withValues(alpha: isDark ? 0.22 : 0.16);
    final foregroundColor = _bestForegroundColor(
      Color.alphaBlend(backgroundColor, Theme.of(context).colorScheme.surface),
    );
    final contentColor =
        foregroundColor == Colors.white ? Colors.white : tagColor;
    final borderColor = tagColor.withValues(alpha: isHovered ? 0.75 : 0.35);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              margin: const EdgeInsets.only(right: 4, top: 2, bottom: 4),
              child: MouseRegion(
                onEnter: (_) => setState(() => isHovered = true),
                onExit: (_) => setState(() => isHovered = false),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap:
                        isDeleting ? null : () => widget.onSelected(widget.tag),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: borderColor,
                          width: 1,
                        ),
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

  Color _bestForegroundColor(Color background) {
    const light = Colors.white;
    const dark = Colors.black;
    final lightContrast = _contrastRatio(background, light);
    final darkContrast = _contrastRatio(background, dark);
    return lightContrast >= darkContrast ? light : dark;
  }

  double _contrastRatio(Color a, Color b) {
    final aLuminance = a.computeLuminance();
    final bLuminance = b.computeLuminance();
    final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
    final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
