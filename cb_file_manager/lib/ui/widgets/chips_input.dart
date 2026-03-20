import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
  }) : super(key: key);

  final List<T> values;
  final InputDecoration decoration;
  final TextStyle? style;
  final StrutStyle? strutStyle;

  final ValueChanged<List<T>> onChanged;
  final ValueChanged<T>? onChipTapped;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onTextChanged;

  final Widget Function(BuildContext context, T data) chipBuilder;

  @override
  ChipsInputState<T> createState() => ChipsInputState<T>();
}

class ChipsInputState<T> extends State<ChipsInput<T>> {
  late final ChipsInputEditingController<T> controller;

  String _previousText = '';
  TextSelection? _previousSelection;

  @override
  void initState() {
    super.initState();

    controller = ChipsInputEditingController<T>(
        <T>[...widget.values], widget.chipBuilder);
    controller.addListener(_textListener);
  }

  @override
  void dispose() {
    controller.removeListener(_textListener);
    controller.dispose();

    super.dispose();
  }

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
      contentPadding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
      isDense: false,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: TextField(
        minLines: 1,
        maxLines: 8,
        textInputAction: TextInputAction.done,
        style: widget.style,
        strutStyle: widget.strutStyle ??
            const StrutStyle(forceStrutHeight: true, height: 1.8),
        controller: controller,
        decoration: adjustedDecoration,
        onChanged: (String value) =>
            widget.onTextChanged?.call(controller.textWithoutReplacements),
        onSubmitted: (String value) =>
            widget.onSubmitted?.call(controller.textWithoutReplacements),
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

      // Add more padding for chips that aren't on the first line
      final verticalPadding = currentLineCount > 0 ? 12.0 : 8.0;

      // Add the chip widget
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: EdgeInsets.only(right: 4, bottom: verticalPadding, top: 4),
          child: chipBuilder(context, values[i]),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use theme colors to better match app design
    final Color tagColor =
        theme.colorScheme.primary.withValues(alpha: isDark ? 0.7 : 0.8);
    final Color tagTextColor = theme.colorScheme.onPrimary;
    final Color iconColor = theme.colorScheme.onPrimary.withValues(alpha: 0.7);

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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: const BoxDecoration(),
                  child: Material(
                    color: Colors.transparent,
                    child: InputChip(
                      key: ObjectKey(widget.tag),
                      label: Text(
                        widget.tag,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tagTextColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                      avatar: Icon(
                        PhosphorIconsLight.tag,
                        size: 14,
                        color: iconColor,
                      ),
                      deleteIconColor: iconColor,
                      backgroundColor: isHovered && !isDeleting
                          ? tagColor.withValues(alpha: 0.9)
                          : tagColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide.none,
                      ),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onDeleted: isDeleting ? null : _handleDelete,
                      deleteIcon: Icon(
                        PhosphorIconsLight.x,
                        size: 16,
                        color: iconColor,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 1),
                      labelPadding: const EdgeInsets.only(left: 1, right: 1),
                      visualDensity:
                          const VisualDensity(horizontal: -4, vertical: -4),
                      onSelected: isDeleting
                          ? null
                          : (bool value) => widget.onSelected(widget.tag),
                      showCheckmark: false,
                      selected: isHovered,
                      selectedColor: tagColor.withValues(alpha: 1.0),
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
