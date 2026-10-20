import 'package:cb_file_manager/helpers/core/desktop_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class CreateNewTabIntent extends Intent {
  const CreateNewTabIntent();
}

class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

class CreateNewWindowIntent extends Intent {
  const CreateNewWindowIntent();
}

class SwitchToTabIntent extends Intent {
  final int tabIndex;
  const SwitchToTabIntent(this.tabIndex);
}

class CycleTabIntent extends Intent {
  final int delta;
  const CycleTabIntent(this.delta);
}

class ToggleSplitViewIntent extends Intent {
  const ToggleSplitViewIntent();
}

/// Each command declares its primary binding once, including macOS variants.
Map<ShortcutActivator, Intent> tabKeyboardShortcuts() {
  final shortcuts = <ShortcutActivator, Intent>{};
  void bind(LogicalKeyboardKey key, Intent intent, {bool shift = false}) {
    for (final activator in DesktopShortcuts.primary(key, shift: shift)) {
      shortcuts[activator] = intent;
    }
  }

  bind(LogicalKeyboardKey.keyT, const CreateNewTabIntent());
  bind(LogicalKeyboardKey.keyW, const CloseTabIntent());
  bind(LogicalKeyboardKey.backslash, const ToggleSplitViewIntent());
  shortcuts[const SingleActivator(
        LogicalKeyboardKey.keyN,
        control: true,
        includeRepeats: false,
      )] =
      const CreateNewTabIntent();
  shortcuts[const SingleActivator(
        LogicalKeyboardKey.keyN,
        control: true,
        shift: true,
        includeRepeats: false,
      )] =
      const CreateNewWindowIntent();
  if (DesktopShortcuts.isMacOS) {
    shortcuts[const SingleActivator(
          LogicalKeyboardKey.keyN,
          meta: true,
          includeRepeats: false,
        )] =
        const CreateNewWindowIntent();
    bind(LogicalKeyboardKey.bracketLeft, const CycleTabIntent(-1), shift: true);
    bind(LogicalKeyboardKey.bracketRight, const CycleTabIntent(1), shift: true);
  }
  for (final previous in [false, true]) {
    shortcuts[SingleActivator(
      LogicalKeyboardKey.tab,
      control: true,
      shift: previous,
      includeRepeats: false,
    )] = CycleTabIntent(
      previous ? -1 : 1,
    );
  }
  const digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  for (var index = 0; index < digits.length; index++) {
    bind(digits[index], SwitchToTabIntent(index));
  }
  return shortcuts;
}
