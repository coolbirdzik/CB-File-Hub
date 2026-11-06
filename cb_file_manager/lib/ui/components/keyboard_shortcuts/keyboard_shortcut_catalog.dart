import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../helpers/core/desktop_shortcuts.dart';
import '../../tab_manager/core/tab_keyboard_shortcuts.dart';
import 'key_caps.dart';

/// One action and the key combos that trigger it (any one of them works).
@immutable
class KeyboardShortcutEntry {
  final String label;
  final List<List<String>> combos;

  const KeyboardShortcutEntry(this.label, this.combos);
}

/// Shortcuts that work in one place — the whole window, the file list, the
/// image viewer, … — shown under that scope's title.
@immutable
class KeyboardShortcutGroup {
  final String title;
  final IconData icon;
  final List<KeyboardShortcutEntry> entries;

  const KeyboardShortcutGroup({
    required this.title,
    required this.icon,
    required this.entries,
  });
}

/// The label for a tab-shell [intent], or null for an intent the reference
/// does not know yet (the catalog test fails on that, so a new binding cannot
/// silently go undocumented).
String? tabShortcutLabel(Intent intent, AppLocalizations l10n) {
  return switch (intent) {
    OpenCommandPaletteIntent() => l10n.commandPaletteTitle,
    CreateNewTabIntent() => l10n.newTab,
    CloseTabIntent() => l10n.closeTab,
    CreateNewWindowIntent() => l10n.newWindow,
    ToggleSplitViewIntent() => l10n.commandPaletteToggleSplit,
    CycleTabIntent(:final delta) =>
      delta > 0 ? l10n.shortcutNextTab : l10n.shortcutPreviousTab,
    SwitchToTabIntent() => l10n.shortcutSwitchToTab,
    _ => null,
  };
}

/// The tab & window group, generated from [tabKeyboardShortcuts] — the map
/// the tab shell actually installs — so the reference cannot drift from the
/// bindings. On macOS the ⌘ form is shown where a Ctrl alias also exists.
KeyboardShortcutGroup tabShortcutGroup(AppLocalizations l10n) {
  final bindings = <(String, SingleActivator)>[];
  for (final MapEntry(:key, :value) in tabKeyboardShortcuts().entries) {
    final label = tabShortcutLabel(value, l10n);
    if (label == null || key is! SingleActivator) continue;
    bindings.add((label, key));
  }

  bool hasMetaTwin(String label, SingleActivator a) => bindings.any(
    (b) =>
        b.$1 == label &&
        b.$2.meta &&
        !b.$2.control &&
        b.$2.trigger == a.trigger &&
        b.$2.shift == a.shift &&
        b.$2.alt == a.alt,
  );

  final combos = <String, List<List<String>>>{};
  for (final (label, activator) in bindings) {
    if (DesktopShortcuts.isMacOS &&
        activator.control &&
        !activator.meta &&
        hasMetaTwin(label, activator)) {
      continue;
    }
    var caps = KeyCaps.forActivator(activator);
    // Nine "go to tab N" bindings read as one row: Ctrl 1–9.
    if (label == l10n.shortcutSwitchToTab) {
      caps = [...caps.sublist(0, caps.length - 1), '1–9'];
    }
    final list = combos.putIfAbsent(label, () => []);
    if (!list.any((c) => c.join('+') == caps.join('+'))) list.add(caps);
  }
  return KeyboardShortcutGroup(
    title: l10n.shortcutsGroupTabs,
    icon: PhosphorIconsLight.browsers,
    entries: [
      for (final MapEntry(:key, :value) in combos.entries)
        KeyboardShortcutEntry(key, value),
    ],
  );
}

/// Every shortcut group, in display order.
///
/// Only the tab group is generated; the others mirror handlers spread over
/// their screens (file list: `file_keyboard_shortcuts.dart` and
/// `tabbed_folder_keyboard_controller.dart`; viewer, player and editor in
/// their screens). Update the matching list here when one of those changes.
List<KeyboardShortcutGroup> keyboardShortcutGroups(AppLocalizations l10n) {
  final mac = DesktopShortcuts.isMacOS;
  List<String> c(String key, {bool shift = false, bool alt = false}) =>
      KeyCaps.chord(key, shift: shift, alt: alt);
  KeyboardShortcutEntry e(String label, List<List<String>> combos) =>
      KeyboardShortcutEntry(label, combos);

  return [
    tabShortcutGroup(l10n),
    KeyboardShortcutGroup(
      title: l10n.commandPaletteTitle,
      icon: PhosphorIconsLight.lightning,
      entries: [
        e(l10n.shortcutMoveSelection, [
          ['↑', '↓'],
        ]),
        e(l10n.shortcutRunSelected, [
          [KeyCaps.enter],
        ]),
        e(l10n.close, [
          [KeyCaps.escape],
        ]),
      ],
    ),
    KeyboardShortcutGroup(
      title: l10n.shortcutsGroupFiles,
      icon: PhosphorIconsLight.folderOpen,
      entries: [
        e(l10n.shortcutOpenSelected, [
          if (mac) ...[
            [KeyCaps.primary, '↓'],
            c('O'),
          ] else
            [KeyCaps.enter],
        ]),
        e(l10n.shortcutOpenInNewWindow, [
          [KeyCaps.shift, KeyCaps.enter],
        ]),
        e(l10n.shortcutMoveSelection, [
          ['↑', '↓', '←', '→'],
        ]),
        e(l10n.shortcutTypeToFind, [
          ['A–Z'],
        ]),
        e(l10n.search, [c('F')]),
        e(l10n.selectAll, [c('A')]),
        e(l10n.copy, [c('C')]),
        e(l10n.cut, [c('X')]),
        e(l10n.shortcutPaste, [c('V')]),
        e(l10n.rename, [
          ['F2'],
          if (mac) [KeyCaps.enter],
        ]),
        if (mac) e(l10n.newFolder, [c('N', shift: true)]),
        e(l10n.moveToTrash, [
          if (mac) [KeyCaps.primary, KeyCaps.backspace] else [KeyCaps.delete],
        ]),
        e(l10n.shortcutDeletePermanently, [
          if (mac)
            [KeyCaps.primary, KeyCaps.alt, KeyCaps.backspace]
          else
            [KeyCaps.shift, KeyCaps.delete],
        ]),
        e(l10n.refresh, [
          ['F5'],
          c('R'),
        ]),
        e(l10n.back, [
          [KeyCaps.alt, '←'],
          c('['),
          [KeyCaps.backspace],
        ]),
        e(l10n.forward, [
          [KeyCaps.alt, '→'],
          c(']'),
        ]),
        e(l10n.parentFolder, [
          if (mac) [KeyCaps.primary, '↑'] else [KeyCaps.alt, '↑'],
        ]),
      ],
    ),
    KeyboardShortcutGroup(
      title: l10n.shortcutsGroupImageViewer,
      icon: PhosphorIconsLight.image,
      entries: [
        e(l10n.shortcutPreviousNext, [
          ['←', '→'],
        ]),
        e(l10n.shortcutFirstLast, [
          ['Home', 'End'],
        ]),
        e(l10n.shortcutZoomIn, [
          ['+'],
        ]),
        e(l10n.shortcutZoomOut, [
          ['−'],
        ]),
        e(l10n.shortcutZoomReset, [
          ['0'],
        ]),
        e(l10n.shortcutRotate, [
          ['R'],
          [KeyCaps.shift, 'R'],
        ]),
        e(l10n.shortcutInfo, [
          ['I'],
        ]),
        e(l10n.shortcutSlideshow, [
          ['Space'],
        ]),
        e(l10n.shortcutFullscreen, [
          ['F'],
          ['F11'],
        ]),
        e(l10n.shortcutPrint, [c('P')]),
        e(l10n.moveToTrash, [
          [KeyCaps.delete],
        ]),
        e(l10n.close, [
          [KeyCaps.escape],
        ]),
      ],
    ),
    KeyboardShortcutGroup(
      title: l10n.shortcutsGroupVideoPlayer,
      icon: PhosphorIconsLight.filmStrip,
      entries: [
        e(l10n.shortcutPlayPause, [
          ['Space'],
        ]),
        e(l10n.shortcutSeek, [
          ['←', '→'],
        ]),
        // The player checks the Control key itself, ⌃ on macOS too.
        e(l10n.shortcutSeekFar, [
          [KeyCaps.control, '←', '→'],
        ]),
        e(l10n.shortcutVolume, [
          ['↑', '↓'],
        ]),
        e(l10n.shortcutMute, [
          ['M'],
        ]),
        e(l10n.shortcutFullscreen, [
          ['F'],
        ]),
        e(l10n.shortcutExitFullscreen, [
          [KeyCaps.escape],
        ]),
      ],
    ),
    KeyboardShortcutGroup(
      title: l10n.shortcutsGroupImageEditor,
      icon: PhosphorIconsLight.paintBrush,
      entries: [
        e(l10n.undo, [c('Z')]),
        e(l10n.shortcutRedo, [c('Y'), c('Z', shift: true)]),
        e(l10n.save, [c('S')]),
        e(l10n.close, [
          [KeyCaps.escape],
        ]),
      ],
    ),
  ];
}
