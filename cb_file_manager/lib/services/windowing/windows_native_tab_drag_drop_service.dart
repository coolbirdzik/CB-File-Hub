import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/desktop/desktop_tab_drag_data.dart';
import 'package:cb_file_manager/ui/tab_manager/desktop/external_tab_drop_controller.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'window_startup_payload.dart';
import 'windows_explorer_drag_drop_service.dart';
import '../torrent/torrent_launch_request.dart';

enum WindowsNativeTabDragResult { moved, detached, canceled }

/// How a tab pulled out of the strip was released.
enum TabTearOffOutcome {
  /// On empty space: the tabs get a window of their own there.
  detached,

  /// On another window's tab strip, which took the tabs.
  merged,

  /// Back on this window's own tab strip.
  returned,

  /// Escape was pressed.
  canceled,

  /// On empty space, and the window readied for the tabs ([TabTearOff.handTo])
  /// already appeared in the preview's place.
  revealed,
}

class TabTearOffResult {
  final TabTearOffOutcome outcome;

  /// Where the new window's content goes, in physical screen pixels.
  final Offset windowOrigin;

  /// The release point in this window's logical coordinates.
  final Offset dropPosition;

  const TabTearOffResult({
    required this.outcome,
    required this.windowOrigin,
    required this.dropPosition,
  });
}

/// A running tear-off: the drag preview follows the cursor until [result].
class TabTearOff {
  TabTearOff._(this.result);

  final Future<TabTearOffResult> result;

  /// Names the window (top-level handle) that is to appear in the preview's
  /// place on release, which then happens natively, without a round trip.
  Future<void> handTo(int windowHandle) =>
      WindowsNativeTabDragDropService._setTabTearOffTarget(windowHandle);

  /// Removes a detached preview; call once the real window is on screen.
  Future<void> end() => WindowsNativeTabDragDropService._endTabTearOff();
}

class WindowsNativeTabDragDropService {
  static const MethodChannel _channel = MethodChannel(
    'cb_file_manager/window_utils',
  );

  static bool _initialized = false;
  static TabManagerBloc? _tabBloc;
  static void Function(List<String>)? onTorrentSources;
  static void Function()? onTorrentNotificationClicked;
  static final ValueNotifier<bool> isDragHoveringWindow = ValueNotifier<bool>(
    false,
  );

  /// This window's tab strip as a target for windows dragged by their tab.
  static final ExternalTabDropController externalTabDrop =
      ExternalTabDropController(
        onStripBoundsChanged: (bounds) => unawaited(setTabStripBounds(bounds)),
      );

  /// This window was dragged by its tab onto another window's tab strip, which
  /// now holds its tabs.
  static void Function()? onTabWindowMerged;

  static Completer<TabTearOffResult>? _tearOff;

  /// This window, readied for a tear-off, was placed and shown by the drag
  /// preview's release.
  static void Function()? onTabWindowRevealed;

  static void initialize(TabManagerBloc tabBloc) {
    _tabBloc = tabBloc;
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onTorrentNotificationClicked') {
        onTorrentNotificationClicked?.call();
        return;
      }
      if (call.method == 'onNativeTorrentSources') {
        final arguments = call.arguments;
        if (arguments is List &&
            arguments.isNotEmpty &&
            arguments.length <= 100 &&
            arguments.every(
              (source) =>
                  source is String && TorrentLaunchRequest.isSource(source),
            )) {
          onTorrentSources?.call(arguments.cast<String>().toList());
        }
        return;
      }
      if (WindowsExplorerDragDropService.handleNativeMethodCall(call)) {
        return;
      }

      switch (call.method) {
        case 'onTabMergeHover':
          _handleTabMergeHover(call.arguments);
          return;
        case 'onTabMergeDrop':
          _handleTabMergeDrop(call.arguments);
          return;
        case 'onTabWindowMerged':
          onTabWindowMerged?.call();
          return;
        case 'onTabTearOffEnded':
          _handleTabTearOffEnded(call.arguments);
          return;
        case 'onTabWindowRevealed':
          onTabWindowRevealed?.call();
          return;
      }

      if (call.method == 'onNativeTabDragHover') {
        final arg = call.arguments;
        if (arg is bool) {
          isDragHoveringWindow.value = arg;
        }
        return;
      }

      if (call.method != 'onNativeTabDrop') return;

      final arg = call.arguments;
      if (arg is! String || arg.trim().isEmpty) return;

      try {
        final tabs = decodeTabsPayload(arg);
        final bloc = _tabBloc;
        if (tabs.isEmpty || bloc == null) return;
        addTabs(bloc, tabs);
      } catch (e, st) {
        AppLogger.warning(
          'Failed to handle native tab drop payload.',
          error: e,
          stackTrace: st,
        );
      } finally {
        isDragHoveringWindow.value = false;
      }
    });
  }

  static String encodeTabsPayload(List<WindowTabPayload> tabs) {
    return jsonEncode(<String, dynamic>{
      'tabs': tabs.map((t) => t.toJson()).toList(growable: false),
    });
  }

  /// Tabs of a payload built by [encodeTabsPayload]; throws on malformed JSON.
  static List<WindowTabPayload> decodeTabsPayload(String payload) {
    final decoded = jsonDecode(payload);
    final tabsValue = decoded is Map ? decoded['tabs'] : null;
    if (tabsValue is! List) return const <WindowTabPayload>[];
    return tabsValue
        .whereType<Map>()
        .map((m) => WindowTabPayload.fromJson(Map<String, dynamic>.from(m)))
        .where((t) => t.path.trim().isNotEmpty)
        .toList(growable: false);
  }

  /// Adds [tabs] in order, at [insertIndex] when given, activating the last.
  static void addTabs(
    TabManagerBloc bloc,
    List<WindowTabPayload> tabs, {
    int? insertIndex,
  }) {
    if (bloc.isClosed) return;
    for (int i = 0; i < tabs.length; i++) {
      final t = tabs[i];
      bloc.add(
        AddTab(
          path: t.path,
          name: t.name,
          switchToTab: i == tabs.length - 1,
          highlightedFileName: t.highlightedFileName,
          windowPayload: t,
          insertIndex: insertIndex == null ? null : insertIndex + i,
        ),
      );
    }
  }

  /// What a window dragged by its tabs shows over another window's tab strip.
  static String tabDragLabel(List<WindowTabPayload> tabs) {
    if (tabs.isEmpty) return '';
    final first = tabs.first;
    var name = first.name?.trim() ?? '';
    if (name.isEmpty) {
      final parts = first.path
          .split(RegExp(r'[\\/]'))
          .where((p) => p.isNotEmpty);
      name = parts.isEmpty ? first.path : parts.last;
    }
    return tabs.length > 1 ? '$name +${tabs.length - 1}' : name;
  }

  static void _handleTabMergeHover(Object? arguments) {
    if (arguments is! Map) {
      externalTabDrop.hover.value = null;
      return;
    }
    final x = arguments['x'];
    final y = arguments['y'];
    if (x is! num || y is! num) return;
    externalTabDrop.hover.value = ExternalTabDropHover(
      position: Offset(x.toDouble(), y.toDouble()),
      label: (arguments['label'] as String?) ?? '',
    );
  }

  static void _handleTabMergeDrop(Object? arguments) {
    final hover = externalTabDrop.hover;
    final payload = arguments is Map ? arguments['payload'] : null;
    final x = arguments is Map ? arguments['x'] : null;
    final y = arguments is Map ? arguments['y'] : null;
    final bloc = _tabBloc;
    if (payload is! String || bloc == null || bloc.isClosed) {
      hover.value = null;
      return;
    }
    try {
      final tabs = decodeTabsPayload(payload);
      if (tabs.isEmpty) {
        hover.value = null;
        return;
      }
      // Keep the tab bar's gap open until the tabs fill it, so the gap and the
      // inserted tabs swap in one frame instead of closing and reopening.
      final hoverAtDrop = hover.value;
      final expected = bloc.state.tabs.length + tabs.length;
      unawaited(
        bloc.stream
            .firstWhere((state) => state.tabs.length >= expected)
            .timeout(const Duration(milliseconds: 500))
            .then<void>((_) {}, onError: (Object _) {})
            .whenComplete(() {
              if (identical(hover.value, hoverAtDrop)) hover.value = null;
            }),
      );
      addTabs(
        bloc,
        tabs,
        insertIndex: x is num && y is num
            ? externalTabDrop.insertIndexAt(Offset(x.toDouble(), y.toDouble()))
            : null,
      );
    } catch (e, st) {
      hover.value = null;
      AppLogger.warning(
        'Failed to merge tabs from another window.',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Moves this window with the cursor while the left button stays down. With
  /// [anchor] (logical, relative to the window content), the window is first
  /// placed so the anchor sits under the cursor. Releasing over another
  /// window's tab strip merges [mergeTabs] into it, then fires
  /// [onTabWindowMerged]; without [mergeTabs] the window only moves.
  ///
  /// Returns false when no drag started: the button is already up, or
  /// [requireMergeTarget] is set and no other tab window is visible.
  static Future<bool> startTabWindowDrag({
    List<WindowTabPayload> mergeTabs = const <WindowTabPayload>[],
    Offset? anchor,
    bool requireMergeTarget = false,
  }) async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'startTabWindowDrag',
            <String, dynamic>{
              if (anchor != null) ...<String, dynamic>{
                'anchorX': anchor.dx,
                'anchorY': anchor.dy,
              },
              if (mergeTabs.isNotEmpty) ...<String, dynamic>{
                'payload': encodeTabsPayload(mergeTabs),
                'label': tabDragLabel(mergeTabs),
              },
              'requireMergeTarget': requireMergeTarget,
            },
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Shows a preview of the new window under the cursor at once and moves it
  /// on a native thread until the mouse button is released, so pulling a tab
  /// out never waits on another process. The preview shows [tabs]' first tab
  /// as drawn in [geometry] and, with [includeContent], this window's content
  /// below the strip. Returns null when no preview could start.
  static Future<TabTearOff?> startTabTearOff({
    required List<WindowTabPayload> tabs,
    required TabDetachGeometry geometry,
    required Size windowSize,
    required Color bodyColor,
    required bool includeContent,
  }) async {
    if (!Platform.isWindows || tabs.isEmpty || _tearOff != null) return null;
    final completer = Completer<TabTearOffResult>();
    _tearOff = completer;
    var started = false;
    try {
      started =
          await _channel
              .invokeMethod<bool>('startTabTearOff', <String, dynamic>{
                'payload': encodeTabsPayload(tabs),
                'label': tabDragLabel(tabs),
                'anchorX': geometry.windowAnchor.dx,
                'anchorY': geometry.windowAnchor.dy,
                'tabLeft': geometry.tabRect.left,
                'tabTop': geometry.tabRect.top,
                'tabRight': geometry.tabRect.right,
                'tabBottom': geometry.tabRect.bottom,
                'firstTabX': geometry.firstTabOrigin.dx,
                'firstTabY': geometry.firstTabOrigin.dy,
                'stripHeight': geometry.stripBottom,
                'windowWidth': windowSize.width,
                'windowHeight': windowSize.height,
                'bodyColor': bodyColor.toARGB32(),
                'includeContent': includeContent,
              }) ??
          false;
    } catch (_) {}
    if (!started) {
      _tearOff = null;
      return null;
    }
    return TabTearOff._(completer.future);
  }

  static void _handleTabTearOffEnded(Object? arguments) {
    final completer = _tearOff;
    _tearOff = null;
    if (completer == null || completer.isCompleted) return;
    final map = arguments is Map ? arguments : const {};
    double read(String key) => (map[key] as num?)?.toDouble() ?? 0;
    completer.complete(
      TabTearOffResult(
        outcome: TabTearOffOutcome.values.firstWhere(
          (o) => o.name == map['outcome'],
          orElse: () => TabTearOffOutcome.canceled,
        ),
        windowOrigin: Offset(read('windowX'), read('windowY')),
        dropPosition: Offset(read('dropX'), read('dropY')),
      ),
    );
  }

  static Future<void> _setTabTearOffTarget(int windowHandle) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('setTabTearOffTarget', windowHandle);
    } catch (_) {}
  }

  /// This window's top-level handle, or null where there is none.
  static Future<int?> topLevelWindowHandle() async {
    if (!Platform.isWindows) return null;
    try {
      return await _channel.invokeMethod<int>('getTopLevelWindowHandle');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _endTabTearOff() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('endTabTearOff');
    } catch (_) {}
  }

  /// Moves this window so its content's top-left is at [origin], in physical
  /// screen pixels.
  static Future<void> placeWindowClientAt(Offset origin) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('placeWindowClientAt', <String, double>{
        'x': origin.dx,
        'y': origin.dy,
      });
    } catch (_) {}
  }

  /// Keeps this window invisible (DWM-cloaked) while it is shown and keeps
  /// rendering, so it can appear with its content already drawn. Releasing the
  /// hold reveals it, unless a tab drag currently hides it over a tab strip.
  static Future<void> holdTabWindowHidden(bool hold) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('holdTabWindowHidden', hold);
    } catch (_) {}
  }

  /// Publishes where this window accepts tabs dragged from other windows, in
  /// logical view coordinates; null stops accepting them.
  static Future<void> setTabStripBounds(Rect? bounds) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>(
        'setTabStripBounds',
        bounds == null
            ? null
            : <String, double>{
                'left': bounds.left,
                'top': bounds.top,
                'right': bounds.right,
                'bottom': bounds.bottom,
              },
      );
    } catch (_) {}
  }

  static Future<WindowsNativeTabDragResult> startDrag({
    required List<WindowTabPayload> tabs,
  }) async {
    if (!Platform.isWindows) return WindowsNativeTabDragResult.canceled;
    if (tabs.isEmpty) return WindowsNativeTabDragResult.canceled;

    final payload = encodeTabsPayload(tabs);

    try {
      final result = await _channel.invokeMethod<String>(
        'startNativeTabDrag',
        payload,
      );

      switch ((result ?? '').toLowerCase()) {
        case 'moved':
          return WindowsNativeTabDragResult.moved;
        case 'detached':
          return WindowsNativeTabDragResult.detached;
        case 'canceled':
        default:
          return WindowsNativeTabDragResult.canceled;
      }
    } on PlatformException catch (e, st) {
      AppLogger.warning(
        'Native tab drag is not available on this build.',
        error: e,
        stackTrace: st,
      );
      return WindowsNativeTabDragResult.canceled;
    } catch (e, st) {
      AppLogger.warning(
        'Failed to start native tab drag.',
        error: e,
        stackTrace: st,
      );
      return WindowsNativeTabDragResult.canceled;
    }
  }

  static Future<void> allowForegroundWindow({int? pid}) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>(
        'allowForegroundWindow',
        <String, dynamic>{'any': pid == null, 'pid': ?pid},
      );
    } catch (_) {}
  }

  /// Shows this window without activating it. `windowManager.show(inactive:)`
  /// still calls SetForegroundWindow on Windows, which every window of this
  /// process may now do, taking the foreground from a window mid-drag.
  static Future<void> showWindowInactive() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('showWindowInactive');
    } catch (_) {}
  }

  static Future<void> forceActivateWindow() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('forceActivateWindow');
    } catch (_) {}
  }

  static Future<void> setTorrentLaunchPriority(int priority) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('setTorrentLaunchPriority', priority);
    } catch (_) {}
  }

  /// Resizes the window for content of [width] x [height] logical pixels,
  /// around its centre and inside its monitor's work area: at most 85% of it,
  /// at least the 800x600 window minimum. Maximized, minimized and fullscreen
  /// windows are left alone. Returns whether the window was resized.
  static Future<bool> fitWindowToContent(double width, double height) async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel
              .invokeMethod<bool>('fitWindowToContent', <String, double>{
                'width': width,
                'height': height,
                'maxFraction': 0.85,
                'minWidth': 800,
                'minHeight': 600,
              }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> startWindowDragIfMouseDown() async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('startWindowDragIfMouseDown') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setNativeCaptionVisible(bool visible) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>(
        'setNativeCaptionVisible',
        <String, dynamic>{'visible': visible},
      );
    } catch (_) {}
  }

  static Future<void> setNativeSystemMenuVisible(bool visible) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>(
        'setNativeSystemMenuVisible',
        <String, dynamic>{'visible': visible},
      );
    } catch (_) {}
  }

  static Future<void> fitWindowToWorkArea() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('fitWindowToWorkArea');
    } catch (_) {}
  }

  static Future<void> setWindowsSystemBackdrop({
    required bool enabled,
    bool preferAcrylic = true,
    bool isDarkMode = false,
  }) async {
    if (!Platform.isWindows) return;
    try {
      await _channel
          .invokeMethod<bool>('setWindowsSystemBackdrop', <String, dynamic>{
            'enabled': enabled,
            'preferAcrylic': preferAcrylic,
            'isDarkMode': isDarkMode,
          });
    } catch (_) {}
  }
}
