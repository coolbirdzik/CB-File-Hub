import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Platform conventions shared by tab, file, and selection shortcuts.
abstract final class DesktopShortcuts {
  static bool get isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  /// Keep Ctrl aliases on macOS for existing users and external keyboards.
  static bool get isPrimaryPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      (isMacOS && HardwareKeyboard.instance.isMetaPressed);

  static Iterable<SingleActivator> primary(
    LogicalKeyboardKey key, {
    bool shift = false,
    bool alt = false,
    bool includeRepeats = false,
  }) sync* {
    yield SingleActivator(
      key,
      control: true,
      shift: shift,
      alt: alt,
      includeRepeats: includeRepeats,
    );
    if (isMacOS) {
      yield SingleActivator(
        key,
        meta: true,
        shift: shift,
        alt: alt,
        includeRepeats: includeRepeats,
      );
    }
  }

  static bool matchesPrimary(
    KeyEvent event,
    LogicalKeyboardKey key, {
    bool shift = false,
    bool alt = false,
  }) => primary(
    key,
    shift: shift,
    alt: alt,
  ).any((activator) => activator.accepts(event, HardwareKeyboard.instance));

  static bool matches(
    KeyEvent event,
    LogicalKeyboardKey key, {
    bool shift = false,
    bool control = false,
    bool meta = false,
    bool alt = false,
    bool includeRepeats = false,
  }) => SingleActivator(
    key,
    shift: shift,
    control: control,
    meta: meta,
    alt: alt,
    includeRepeats: includeRepeats,
  ).accepts(event, HardwareKeyboard.instance);

  static bool get isTextInputFocused {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null);
  }
}
