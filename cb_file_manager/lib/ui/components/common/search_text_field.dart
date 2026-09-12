import 'package:flutter/material.dart';

/// A search controller whose query listeners ignore caret/selection changes.
/// Normal controller listeners remain available to EditableText.
class SearchTextController extends TextEditingController {
  SearchTextController({super.text}) {
    _lastText = text;
    addListener(_notifyQueryChanged);
  }

  late String _lastText;
  final Set<VoidCallback> _queryListeners = {};

  void addQueryListener(VoidCallback listener) => _queryListeners.add(listener);
  void removeQueryListener(VoidCallback listener) =>
      _queryListeners.remove(listener);

  void _notifyQueryChanged() {
    if (text == _lastText ||
        value.composing.isValid && !value.composing.isCollapsed) {
      return;
    }
    _lastText = text;
    for (final listener in List<VoidCallback>.of(_queryListeners)) {
      if (_queryListeners.contains(listener)) listener();
    }
  }

  @override
  void dispose() {
    _queryListeners.clear();
    super.dispose();
  }
}

/// Common single-line search input. Keep native text selection and shortcuts;
/// screens supply decoration and choose live filtering or submitted searching.
class SearchTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final Color? cursorColor;
  final double? cursorHeight;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool? enabled;
  final TapRegionCallback? onTapOutside;
  final TextInputAction textInputAction;
  final int maxLines;

  const SearchTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.style,
    this.strutStyle,
    this.cursorColor,
    this.cursorHeight,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.enabled,
    this.onTapOutside,
    this.textInputAction = TextInputAction.search,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: decoration,
      style: style,
      strutStyle: strutStyle,
      cursorColor: cursorColor,
      cursorHeight: cursorHeight,
      textAlign: textAlign,
      textAlignVertical: textAlignVertical,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      onTapOutside: onTapOutside,
      textInputAction: textInputAction,
      maxLines: maxLines,
    ),
  );
}
