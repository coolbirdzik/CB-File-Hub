import 'package:cb_file_manager/helpers/core/desktop_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Shared bindings for both basic file surfaces and navigable folder views.
abstract final class FileKeyboardShortcuts {
  static KeyEventResult handleSearch({
    required bool isDesktop,
    required KeyEvent? event,
    VoidCallback? onSearch,
  }) {
    if (isDesktop &&
        event != null &&
        onSearch != null &&
        DesktopShortcuts.matchesPrimary(event, LogicalKeyboardKey.keyF)) {
      onSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static KeyEventResult handle({
    required bool isDesktop,
    required KeyEvent? event,
    VoidCallback? onEscape,
    VoidCallback? onRefresh,
    VoidCallback? onSelectAll,
    void Function(bool permanent)? onDelete,
    VoidCallback? onCopy,
    VoidCallback? onCut,
    VoidCallback? onPaste,
    VoidCallback? onRename,
    VoidCallback? onSearch,
    VoidCallback? onBack,
    VoidCallback? onForward,
  }) {
    final searchResult = handleSearch(
      isDesktop: isDesktop,
      event: event,
      onSearch: onSearch,
    );
    if (searchResult != KeyEventResult.ignored) return searchResult;
    if (!isDesktop || event == null || DesktopShortcuts.isTextInputFocused) {
      return KeyEventResult.ignored;
    }

    bool plain(LogicalKeyboardKey key, {bool shift = false}) =>
        DesktopShortcuts.matches(event, key, shift: shift);
    bool primary(LogicalKeyboardKey key) =>
        DesktopShortcuts.matchesPrimary(event, key);

    VoidCallback? action;
    if (plain(LogicalKeyboardKey.escape)) {
      action = onEscape;
    } else if (plain(LogicalKeyboardKey.f5) ||
        primary(LogicalKeyboardKey.keyR)) {
      action = onRefresh;
    } else if (primary(LogicalKeyboardKey.keyA)) {
      action = onSelectAll;
    } else if (primary(LogicalKeyboardKey.keyC)) {
      action = onCopy;
    } else if (primary(LogicalKeyboardKey.keyX)) {
      action = onCut;
    } else if (primary(LogicalKeyboardKey.keyV)) {
      action = onPaste;
    } else if (plain(LogicalKeyboardKey.f2) ||
        (DesktopShortcuts.isMacOS &&
            (plain(LogicalKeyboardKey.enter) ||
                plain(LogicalKeyboardKey.numpadEnter)))) {
      action = onRename;
    } else if (primary(LogicalKeyboardKey.bracketLeft) ||
        DesktopShortcuts.matches(
          event,
          LogicalKeyboardKey.arrowLeft,
          alt: true,
        )) {
      action = onBack;
    } else if (primary(LogicalKeyboardKey.bracketRight) ||
        DesktopShortcuts.matches(
          event,
          LogicalKeyboardKey.arrowRight,
          alt: true,
        )) {
      action = onForward;
    } else {
      final macTrash =
          DesktopShortcuts.isMacOS &&
          DesktopShortcuts.matches(
            event,
            LogicalKeyboardKey.backspace,
            meta: true,
          );
      final macPermanent =
          DesktopShortcuts.isMacOS &&
          DesktopShortcuts.matches(
            event,
            LogicalKeyboardKey.backspace,
            meta: true,
            alt: true,
          );
      final permanent =
          plain(LogicalKeyboardKey.delete, shift: true) || macPermanent;
      if (onDelete != null &&
          (plain(LogicalKeyboardKey.delete) || macTrash || permanent)) {
        onDelete(permanent);
        return KeyEventResult.handled;
      }
    }
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }
}
