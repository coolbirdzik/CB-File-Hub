import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:flutter/services.dart';

class WindowsExplorerFileDropEvent {
  final List<String> paths;
  final Offset globalPosition;
  final String effect;

  const WindowsExplorerFileDropEvent({
    required this.paths,
    required this.globalPosition,
    required this.effect,
  });
}

enum WindowsExplorerDragResult { moved, canceled }

class WindowsExplorerDragDropService {
  static const MethodChannel _channel = MethodChannel(
    'cb_file_manager/window_utils',
  );

  static final StreamController<WindowsExplorerFileDropEvent> _dropController =
      StreamController<WindowsExplorerFileDropEvent>.broadcast();

  static Stream<WindowsExplorerFileDropEvent> get fileDrops =>
      _dropController.stream;

  static Future<WindowsExplorerDragResult> startFileDrag(
    List<String> paths,
  ) async {
    if (!Platform.isWindows) return WindowsExplorerDragResult.canceled;

    final cleaned = paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty && !path.startsWith('#'))
        .toSet()
        .toList(growable: false);
    if (cleaned.isEmpty) return WindowsExplorerDragResult.canceled;

    try {
      final result = await _channel.invokeMethod<String>(
        'startNativeFileDrag',
        <String, dynamic>{'paths': cleaned},
      );
      return (result ?? '').toLowerCase() == 'moved'
          ? WindowsExplorerDragResult.moved
          : WindowsExplorerDragResult.canceled;
    } on PlatformException catch (e, st) {
      AppLogger.warning(
        'Native file drag is not available on this build.',
        error: e,
        stackTrace: st,
      );
      return WindowsExplorerDragResult.canceled;
    } catch (e, st) {
      AppLogger.warning(
        'Failed to start native file drag.',
        error: e,
        stackTrace: st,
      );
      return WindowsExplorerDragResult.canceled;
    }
  }

  static bool handleNativeMethodCall(MethodCall call) {
    if (call.method != 'onNativeFileDrop') return false;

    final arg = call.arguments;
    if (arg is! Map) return true;

    final paths =
        (arg['paths'] as List?)
            ?.whereType<String>()
            .map((path) => path.trim())
            .where((path) => path.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    if (paths.isEmpty) return true;

    final x = _toDouble(arg['globalX']);
    final y = _toDouble(arg['globalY']);
    final effect = (arg['effect'] as String?) ?? 'move';

    _dropController.add(
      WindowsExplorerFileDropEvent(
        paths: paths,
        globalPosition: Offset(x, y),
        effect: effect,
      ),
    );
    return true;
  }

  static double _toDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return 0;
  }
}
