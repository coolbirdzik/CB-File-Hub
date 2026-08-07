import 'dart:async';
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
  final int? submenuId;
  final String? label;
  final bool isEnabled;
  final bool isChecked;
  final Uint8List? iconBytes;
  final List<WindowsShellMenuEntry> children;

  const WindowsShellMenuEntry({
    required this.type,
    this.commandId,
    this.submenuId,
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
      submenuId: map['submenuId'] as int?,
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

class _CachedWindowsShellMenuSession {
  final String selectionKey;
  final WindowsShellMenuSession? session;
  DateTime expiresAt;
  int activeLeases = 0;

  _CachedWindowsShellMenuSession({
    required this.selectionKey,
    required this.session,
    required this.expiresAt,
  });
}

class WindowsShellContextMenu {
  static const MethodChannel _channel =
      MethodChannel('cb_file_manager/shell_context_menu');
  // Keep one target-bound native session warm for repeated context-menu opens.
  // A longer-lived cross-target cache is unsafe because Shell command IDs and
  // handlers are created for the exact PIDL selection passed by the caller.
  static const Duration thirdPartyMenuCacheDuration = Duration(minutes: 5);

  static _CachedWindowsShellMenuSession? _cachedThirdPartyMenu;
  static Future<WindowsShellMenuSession?>? _pendingThirdPartyMenuLoad;
  static String? _pendingThirdPartyMenuSelectionKey;
  static Timer? _thirdPartyMenuExpiryTimer;
  static final Map<String, List<WindowsShellMenuEntry>>
      _cachedThirdPartySubmenus = <String, List<WindowsShellMenuEntry>>{};
  static final Map<String, Future<List<WindowsShellMenuEntry>>>
      _pendingThirdPartySubmenuLoads =
      <String, Future<List<WindowsShellMenuEntry>>>{};

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

  /// Loads and briefly caches the native Shell session for an exact path
  /// selection. Command IDs are session-specific, so entries are never shared
  /// across different targets.
  static Future<WindowsShellMenuSession?> loadThirdPartyMenu({
    required List<String> paths,
  }) async {
    if (!Platform.isWindows || paths.isEmpty) {
      return null;
    }

    final selectionKey = _thirdPartyMenuSelectionKey(paths);
    if (selectionKey.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final cached = _cachedThirdPartyMenu;
    if (cached != null &&
        cached.selectionKey == selectionKey &&
        (cached.activeLeases > 0 || now.isBefore(cached.expiresAt))) {
      cached.expiresAt = now.add(thirdPartyMenuCacheDuration);
      _scheduleThirdPartyMenuExpiry(cached);
      return cached.session;
    }

    final pendingLoad = _pendingThirdPartyMenuLoad;
    if (pendingLoad != null) {
      if (_pendingThirdPartyMenuSelectionKey == selectionKey) {
        return pendingLoad;
      }
      await pendingLoad;
      return loadThirdPartyMenu(paths: paths);
    }

    await _evictCachedThirdPartyMenu();

    final loadFuture = _loadThirdPartyMenuUncached(paths: paths);
    _pendingThirdPartyMenuLoad = loadFuture;
    _pendingThirdPartyMenuSelectionKey = selectionKey;

    final session = await loadFuture;
    if (identical(_pendingThirdPartyMenuLoad, loadFuture)) {
      _pendingThirdPartyMenuLoad = null;
      _pendingThirdPartyMenuSelectionKey = null;
      final entry = _CachedWindowsShellMenuSession(
        selectionKey: selectionKey,
        session: session,
        expiresAt: DateTime.now().add(thirdPartyMenuCacheDuration),
      );
      _cachedThirdPartyMenu = entry;
      _scheduleThirdPartyMenuExpiry(entry);
    }
    return session;
  }

  static Future<WindowsShellMenuSession?> _loadThirdPartyMenuUncached({
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

  static Future<List<WindowsShellMenuEntry>> loadThirdPartySubmenu({
    required String sessionId,
    required int submenuId,
  }) async {
    if (!Platform.isWindows || sessionId.isEmpty || submenuId <= 0) {
      return const <WindowsShellMenuEntry>[];
    }

    final cacheKey = '$sessionId:$submenuId';
    final cached = _cachedThirdPartySubmenus[cacheKey];
    if (cached != null) {
      return cached;
    }

    final pending = _pendingThirdPartySubmenuLoads[cacheKey];
    if (pending != null) {
      return pending;
    }

    final loadFuture = _loadThirdPartySubmenuUncached(
      sessionId: sessionId,
      submenuId: submenuId,
    );
    _pendingThirdPartySubmenuLoads[cacheKey] = loadFuture;
    final entries = await loadFuture;
    if (identical(_pendingThirdPartySubmenuLoads[cacheKey], loadFuture)) {
      _pendingThirdPartySubmenuLoads.remove(cacheKey);
      _cachedThirdPartySubmenus[cacheKey] = entries;
    }
    return entries;
  }

  static Future<List<WindowsShellMenuEntry>> _loadThirdPartySubmenuUncached({
    required String sessionId,
    required int submenuId,
  }) async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'loadContextMenuSubmenu',
        <String, Object?>{
          'sessionId': sessionId,
          'submenuId': submenuId,
        },
      );
      if (result is! List<Object?>) {
        return const <WindowsShellMenuEntry>[];
      }
      return result
          .whereType<Map<Object?, Object?>>()
          .map(WindowsShellMenuEntry.fromMap)
          .toList(growable: false);
    } catch (_) {
      return const <WindowsShellMenuEntry>[];
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
      final invoked = result == true;
      if (invoked) {
        _forgetCachedThirdPartyMenuSession(sessionId);
      }
      return invoked;
    } catch (_) {
      return false;
    }
  }

  static Future<void> releaseSession(String sessionId) async {
    if (!Platform.isWindows || sessionId.isEmpty) {
      return;
    }

    _forgetCachedThirdPartyMenuSession(sessionId);
    await _releaseSessionNative(sessionId);
  }

  static Future<void> clearThirdPartyMenuCache() async {
    final pendingLoad = _pendingThirdPartyMenuLoad;
    if (pendingLoad != null) {
      await pendingLoad;
    }
    await _evictCachedThirdPartyMenu();
  }

  /// Prevents TTL eviction while a visible Flutter submenu still references
  /// this native Shell session.
  static void retainCachedThirdPartyMenuSession(String sessionId) {
    final cached = _cachedThirdPartyMenu;
    if (cached == null || cached.session?.id != sessionId) {
      return;
    }
    cached.activeLeases++;
    _thirdPartyMenuExpiryTimer?.cancel();
    _thirdPartyMenuExpiryTimer = null;
  }

  static void releaseCachedThirdPartyMenuSession(String sessionId) {
    final cached = _cachedThirdPartyMenu;
    if (cached == null ||
        cached.session?.id != sessionId ||
        cached.activeLeases == 0) {
      return;
    }
    cached.activeLeases--;
    if (cached.activeLeases == 0) {
      cached.expiresAt = DateTime.now().add(thirdPartyMenuCacheDuration);
      _scheduleThirdPartyMenuExpiry(cached);
    }
  }

  static String _thirdPartyMenuSelectionKey(List<String> paths) {
    final normalizedPaths = paths
        .map(
          (path) => path
              .trim()
              .replaceAll('/', r'\')
              .replaceFirst(RegExp(r'\\+$'), '')
              .toLowerCase(),
        )
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    final extendedVerbs = HardwareKeyboard.instance.isShiftPressed ? '1' : '0';
    return '$extendedVerbs|${normalizedPaths.join('\u0000')}';
  }

  static void _scheduleThirdPartyMenuExpiry(
    _CachedWindowsShellMenuSession entry,
  ) {
    _thirdPartyMenuExpiryTimer?.cancel();
    if (entry.activeLeases > 0) {
      _thirdPartyMenuExpiryTimer = null;
      return;
    }
    final delay = entry.expiresAt.difference(DateTime.now());
    _thirdPartyMenuExpiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        if (identical(_cachedThirdPartyMenu, entry)) {
          unawaited(_evictCachedThirdPartyMenu());
        }
      },
    );
  }

  static void _forgetCachedThirdPartyMenuSession(String sessionId) {
    final cached = _cachedThirdPartyMenu;
    if (cached?.session?.id != sessionId) {
      return;
    }
    _thirdPartyMenuExpiryTimer?.cancel();
    _thirdPartyMenuExpiryTimer = null;
    _cachedThirdPartyMenu = null;
    _removeCachedThirdPartySubmenus(sessionId);
  }

  static Future<void> _evictCachedThirdPartyMenu() async {
    final cached = _cachedThirdPartyMenu;
    _thirdPartyMenuExpiryTimer?.cancel();
    _thirdPartyMenuExpiryTimer = null;
    _cachedThirdPartyMenu = null;

    final sessionId = cached?.session?.id;
    if (sessionId != null && sessionId.isNotEmpty) {
      _removeCachedThirdPartySubmenus(sessionId);
      await _releaseSessionNative(sessionId);
    }
  }

  static void _removeCachedThirdPartySubmenus(String sessionId) {
    final prefix = '$sessionId:';
    _cachedThirdPartySubmenus.removeWhere(
      (key, _) => key.startsWith(prefix),
    );
    _pendingThirdPartySubmenuLoads.removeWhere(
      (key, _) => key.startsWith(prefix),
    );
  }

  static Future<void> _releaseSessionNative(String sessionId) async {
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
