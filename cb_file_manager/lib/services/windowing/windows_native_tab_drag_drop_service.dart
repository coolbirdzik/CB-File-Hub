import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'window_startup_payload.dart';

enum WindowsNativeTabDragResult {
  moved,
  detached,
  canceled,
}

class WindowsNativeTabDragDropService {
  static const MethodChannel _channel =
      MethodChannel('cb_file_manager/window_utils');

  static bool _initialized = false;
  static TabManagerBloc? _tabBloc;
  static final ValueNotifier<bool> isDragHoveringWindow =
      ValueNotifier<bool>(false);

  static void initialize(TabManagerBloc tabBloc) {
    _tabBloc = tabBloc;
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
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
        final decoded = jsonDecode(arg);
        final Map<String, dynamic> payload =
            decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
        final dynamic tabsValue = payload['tabs'];
        if (tabsValue is! List) return;

        final tabs = tabsValue
            .whereType<Map>()
            .map((m) => WindowTabPayload.fromJson(Map<String, dynamic>.from(m)))
            .where((t) => t.path.trim().isNotEmpty)
            .toList(growable: false);

        if (tabs.isEmpty) return;

        final bloc = _tabBloc;
        if (bloc == null) return;

        for (int i = 0; i < tabs.length; i++) {
          final t = tabs[i];
          bloc.add(AddTab(
            path: t.path,
            name: t.name,
            switchToTab: i == tabs.length - 1,
            highlightedFileName: t.highlightedFileName,
          ));
        }
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

  static Future<WindowsNativeTabDragResult> startDrag({
    required List<WindowTabPayload> tabs,
  }) async {
    if (!Platform.isWindows) return WindowsNativeTabDragResult.canceled;
    if (tabs.isEmpty) return WindowsNativeTabDragResult.canceled;

    final payload = jsonEncode(<String, dynamic>{
      'tabs': tabs.map((t) => t.toJson()).toList(growable: false),
    });

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
        <String, dynamic>{
          'any': pid == null,
          if (pid != null) 'pid': pid,
        },
      );
    } catch (_) {}
  }

  static Future<void> forceActivateWindow() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('forceActivateWindow');
    } catch (_) {}
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
      await _channel.invokeMethod<bool>(
        'setWindowsSystemBackdrop',
        <String, dynamic>{
          'enabled': enabled,
          'preferAcrylic': preferAcrylic,
          'isDarkMode': isDarkMode,
        },
      );
    } catch (_) {}
  }
}
