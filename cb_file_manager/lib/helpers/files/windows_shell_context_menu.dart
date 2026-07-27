import 'dart:io';

import 'package:flutter/services.dart';

class WindowsMenuEntry {
  final String type;
  final String? id;
  final String? label;

  const WindowsMenuEntry._(this.type, {this.id, this.label});

  const WindowsMenuEntry.item({
    required String id,
    required String label,
  }) : this._('item', id: id, label: label);

  const WindowsMenuEntry.separator() : this._('separator');

  Map<String, Object?> toMap() => {
        'type': type,
        if (id != null) 'id': id,
        if (label != null) 'label': label,
      };
}

class WindowsCombinedMenuResult {
  final bool shown;
  final String? action;

  const WindowsCombinedMenuResult({
    required this.shown,
    required this.action,
  });

  factory WindowsCombinedMenuResult.fromMap(Map<Object?, Object?> map) {
    final shown = map['shown'] == true;
    final actionValue = map['action'];
    final action = actionValue is String ? actionValue : null;
    return WindowsCombinedMenuResult(shown: shown, action: action);
  }
}

class WindowsShellMenuEntry {
  final String type;
  final int? commandId;
  final String? label;
  final bool isEnabled;
  final bool isChecked;
  final Uint8List? iconBytes;
  final List<WindowsShellMenuEntry> children;

  const WindowsShellMenuEntry({
    required this.type,
    this.commandId,
    this.label,
    this.isEnabled = true,
    this.isChecked = false,
    this.iconBytes,
    this.children = const [],
  });

  factory WindowsShellMenuEntry.fromMap(Map<Object?, Object?> map) {
    final rawChildren = map['children'];
    return WindowsShellMenuEntry(
      type: map['type'] as String? ?? 'item',
      commandId: map['commandId'] as int?,
      label: map['label'] as String?,
      isEnabled: map['enabled'] != false,
      isChecked: map['checked'] == true,
      iconBytes: map['iconBytes'] as Uint8List?,
      children: rawChildren is List<Object?>
          ? rawChildren
              .whereType<Map<Object?, Object?>>()
              .map(WindowsShellMenuEntry.fromMap)
              .toList(growable: false)
          : const [],
    );
  }
}

class WindowsShellMenuSession {
  final String id;
  final List<WindowsShellMenuEntry> entries;

  const WindowsShellMenuSession({
    required this.id,
    required this.entries,
  });

  factory WindowsShellMenuSession.fromMap(Map<Object?, Object?> map) {
    final rawEntries = map['entries'];
    return WindowsShellMenuSession(
      id: map['sessionId'] as String? ?? '',
      entries: rawEntries is List<Object?>
          ? rawEntries
              .whereType<Map<Object?, Object?>>()
              .map(WindowsShellMenuEntry.fromMap)
              .toList(growable: false)
          : const [],
    );
  }
}

class WindowsShellContextMenu {
  static const MethodChannel _channel =
      MethodChannel('cb_file_manager/shell_context_menu');

  static Future<bool> showForPaths({
    required List<String> paths,
    Offset? globalPosition,
    double devicePixelRatio = 1.0,
  }) async {
    if (!Platform.isWindows || paths.isEmpty) {
      return false;
    }

    try {
      final Map<String, Object?> arguments = {
        'paths': paths,
        if (globalPosition != null) 'x': globalPosition.dx,
        if (globalPosition != null) 'y': globalPosition.dy,
        'devicePixelRatio': devicePixelRatio,
      };

      final result = await _channel.invokeMethod<Object?>(
        'showContextMenu',
        arguments,
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<WindowsCombinedMenuResult> showCombinedMenu({
    required List<String> paths,
    required List<WindowsMenuEntry> items,
    required String shellSubmenuLabel,
    Offset? globalPosition,
    double devicePixelRatio = 1.0,
  }) async {
    if (!Platform.isWindows || paths.isEmpty) {
      return const WindowsCombinedMenuResult(shown: false, action: null);
    }

    try {
      final Map<String, Object?> arguments = {
        'paths': paths,
        'items': items.map((e) => e.toMap()).toList(growable: false),
        'shellSubmenuLabel': shellSubmenuLabel,
        if (globalPosition != null) 'x': globalPosition.dx,
        if (globalPosition != null) 'y': globalPosition.dy,
        'devicePixelRatio': devicePixelRatio,
      };

      final result = await _channel.invokeMethod<Object?>(
        'showCombinedMenu',
        arguments,
      );

      if (result is Map<Object?, Object?>) {
        return WindowsCombinedMenuResult.fromMap(result);
      }

      return const WindowsCombinedMenuResult(shown: false, action: null);
    } catch (_) {
      return const WindowsCombinedMenuResult(shown: false, action: null);
    }
  }

  static Future<WindowsCombinedMenuResult> showMergedMenu({
    required List<String> paths,
    required List<WindowsMenuEntry> items,
    Offset? globalPosition,
    double devicePixelRatio = 1.0,
  }) async {
    if (!Platform.isWindows || paths.isEmpty) {
      return const WindowsCombinedMenuResult(shown: false, action: null);
    }

    try {
      final Map<String, Object?> arguments = {
        'paths': paths,
        'items': items.map((e) => e.toMap()).toList(growable: false),
        if (globalPosition != null) 'x': globalPosition.dx,
        if (globalPosition != null) 'y': globalPosition.dy,
        'devicePixelRatio': devicePixelRatio,
      };

      final result = await _channel.invokeMethod<Object?>(
        'showMergedMenu',
        arguments,
      );

      if (result is Map<Object?, Object?>) {
        return WindowsCombinedMenuResult.fromMap(result);
      }

      return const WindowsCombinedMenuResult(shown: false, action: null);
    } catch (_) {
      return const WindowsCombinedMenuResult(shown: false, action: null);
    }
  }

  static Future<bool> invokeVerb({
    required List<String> paths,
    required String verb,
  }) async {
    if (!Platform.isWindows || paths.isEmpty || verb.trim().isEmpty) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<Object?>(
        'invokeVerb',
        <String, Object?>{
          'paths': paths,
          'verb': verb.trim(),
        },
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<WindowsShellMenuSession?> loadThirdPartyMenu({
    required List<String> paths,
  }) async {
    if (!Platform.isWindows || paths.isEmpty) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod<Object?>(
        'loadThirdPartyMenu',
        <String, Object?>{'paths': paths},
      );
      if (result is! Map<Object?, Object?>) {
        return null;
      }

      final session = WindowsShellMenuSession.fromMap(result);
      if (session.id.isEmpty || session.entries.isEmpty) {
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> invokeSessionCommand({
    required String sessionId,
    required int commandId,
  }) async {
    if (!Platform.isWindows || sessionId.isEmpty) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<Object?>(
        'invokeContextMenuCommand',
        <String, Object?>{
          'sessionId': sessionId,
          'commandId': commandId,
        },
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> releaseSession(String sessionId) async {
    if (!Platform.isWindows || sessionId.isEmpty) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(
        'releaseContextMenuSession',
        <String, Object?>{'sessionId': sessionId},
      );
    } catch (_) {
      // The session may already be released after invoking a Shell command.
    }
  }
}
