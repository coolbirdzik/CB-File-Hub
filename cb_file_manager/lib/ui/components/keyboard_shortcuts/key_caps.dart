import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

import '../../../helpers/core/desktop_shortcuts.dart';

/// Key-cap labels for showing shortcuts — shared by the command palette, the
/// keyboard shortcuts reference and the Home keyboard tip, so a combo looks
/// identical wherever it appears.
///
/// macOS uses the system symbols (⌃ ⌥ ⇧ ⌘); other platforms spell the
/// modifiers out (Ctrl, Alt, Shift), the way their own menus do.
abstract final class KeyCaps {
  static bool get _mac => DesktopShortcuts.isMacOS;

  /// The platform's primary modifier: ⌘ on macOS, Ctrl elsewhere.
  static String get primary => _mac ? '⌘' : 'Ctrl';

  /// The Control key itself, for handlers that check Ctrl on every platform.
  static String get control => _mac ? '⌃' : 'Ctrl';
  static String get alt => _mac ? '⌥' : 'Alt';
  static String get shift => _mac ? '⇧' : 'Shift';
  static String get enter => '↵';
  static String get escape => 'Esc';
  static String get backspace => _mac ? '⌫' : 'Backspace';
  static String get delete => _mac ? '⌦' : 'Del';

  /// The primary modifier (plus optional Shift/Alt) and [key] — `Ctrl` `T`.
  static List<String> chord(
    String key, {
    bool shift = false,
    bool alt = false,
  }) {
    return [primary, if (alt) KeyCaps.alt, if (shift) KeyCaps.shift, key];
  }

  /// The caps for one [SingleActivator], modifiers first in platform order.
  static List<String> forActivator(SingleActivator activator) {
    final caps = <String>[];
    if (_mac) {
      if (activator.control) caps.add('⌃');
      if (activator.alt) caps.add('⌥');
      if (activator.shift) caps.add('⇧');
      if (activator.meta) caps.add('⌘');
    } else {
      if (activator.control) caps.add('Ctrl');
      if (activator.alt) caps.add('Alt');
      if (activator.shift) caps.add('Shift');
      if (activator.meta) caps.add('Win');
    }
    caps.add(forKey(activator.trigger));
    return caps;
  }

  /// The cap for a single key: arrows and Enter as symbols, letters upper
  /// case, everything else by its key label.
  static String forKey(LogicalKeyboardKey key) {
    final named = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.arrowUp: '↑',
      LogicalKeyboardKey.arrowDown: '↓',
      LogicalKeyboardKey.arrowLeft: '←',
      LogicalKeyboardKey.arrowRight: '→',
      LogicalKeyboardKey.enter: enter,
      LogicalKeyboardKey.numpadEnter: enter,
      LogicalKeyboardKey.escape: escape,
      LogicalKeyboardKey.tab: _mac ? '⇥' : 'Tab',
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.backspace: backspace,
      LogicalKeyboardKey.delete: delete,
    };
    final cap = named[key];
    if (cap != null) return cap;
    final label = key.keyLabel;
    if (label.isEmpty) return key.debugName ?? '?';
    return label.length == 1 ? label.toUpperCase() : label;
  }
}
