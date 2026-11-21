// Keep the pinned Flutter SDK's internal windowing API in this file.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/src/foundation/_features.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_win32.dart';
import 'package:flutter/widgets.dart';

import 'window_startup_payload.dart';
import 'windows_engine_host.dart';

class WindowsSharedEngineWindows extends ChangeNotifier {
  static const environmentKey = 'CB_SHARED_ENGINE_WINDOWS';
  static const _retainReason = 'shared-browser-windows';

  static int enableBeforeBinding() {
    if (!Platform.isWindows) return 0;
    final env = Platform.environment;
    final role = env[WindowStartupPayload.envWindowRoleKey] ?? '';
    if ((role.isNotEmpty && role != 'normal') ||
        env[WindowStartupPayload.envStartHiddenKey] == '1' ||
        env[WindowStartupPayload.envStartDraggingKey] == '1' ||
        env['CB_PIP_MODE'] == '1' ||
        env['CB_VIDEO_WINDOW'] == '1') {
      return 0;
    }
    final count = int.tryParse(env[environmentKey] ?? '') ?? 1;
    if (count <= 0) return 0;
    isWindowingEnabled = true;
    return count;
  }

  final _windows = <WindowController, WindowStartupPayload>{};

  static final _configureFrame = ffi.DynamicLibrary.executable()
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)
      >('CBConfigureSharedWindowFrame');

  static final _requestTitleBarDrag = ffi.DynamicLibrary.executable()
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)
      >('CBStartSharedWindowDrag');

  static void _startDragging(WindowController controller) {
    if (controller is WindowControllerWin32 && !controller.isDestroyed) {
      _requestTitleBarDrag(controller.windowHandle);
    }
  }

  bool open(WindowStartupPayload payload) {
    WindowController? createdWindow;
    try {
      late final WindowController controller;
      controller = WindowController(
        title: 'CB File Hub',
        size: const Size(1200, 800),
        constraints: const BoxConstraints(minWidth: 800, minHeight: 600),
        delegate: _SharedWindowDelegate(() {
          if (_windows.remove(controller) == null) return;
          if (_windows.isEmpty) {
            unawaited(WindowsEngineHost.retainWhileBusy(_retainReason, false));
          }
          notifyListeners();
        }),
      );
      createdWindow = controller;
      if (controller is WindowControllerWin32 &&
          _configureFrame(controller.windowHandle) == 0) {
        controller.destroy();
        return false;
      }
      _windows[controller] = payload;
      if (_windows.length == 1) {
        // The main HWND can close while the engine still owns these views.
        unawaited(WindowsEngineHost.retainWhileBusy(_retainReason, true));
      }
      notifyListeners();
      return true;
    } catch (error, stack) {
      createdWindow?.destroy();
      debugPrint('Could not open a shared-engine window: $error\n$stack');
      return false;
    }
  }

  Widget host({
    required Widget primary,
    required Widget Function(WindowStartupPayload payload) buildWindow,
  }) {
    final implicitView =
        WidgetsBinding.instance.platformDispatcher.implicitView!;
    return ListenableBuilder(
      listenable: this,
      child: View(
        view: implicitView,
        child: WindowsSharedEngineScope(child: primary),
      ),
      builder: (context, primaryView) => ViewCollection(
        views: [
          primaryView!,
          for (final entry in _windows.entries)
            if (!entry.key.isDestroyed)
              Window(
                key: ObjectKey(entry.key),
                controller: entry.key,
                child: WindowsSharedEngineScope(
                  controller: entry.key,
                  startDragging: () => _startDragging(entry.key),
                  child: buildWindow(entry.value),
                ),
              ),
        ],
      ),
    );
  }
}

class WindowsSharedEngineScope extends InheritedWidget {
  const WindowsSharedEngineScope({
    super.key,
    this._controller,
    this.startDragging,
    required super.child,
  });

  final WindowController? _controller;
  final VoidCallback? startDragging;

  bool get isAdditional => _controller != null;
  Listenable? get captionChanges => _controller;
  bool get isMaximized => switch (_controller) {
    final controller? when !controller.isDestroyed => controller.isMaximized,
    _ => false,
  };

  void minimize() {
    final controller = _controller;
    if (controller != null && !controller.isDestroyed) {
      controller.setMinimized(true);
    }
  }

  void toggleMaximized() {
    final controller = _controller;
    if (controller != null && !controller.isDestroyed) {
      controller.setMaximized(!controller.isMaximized);
    }
  }

  void closeWindow() {
    final controller = _controller;
    if (controller != null && !controller.isDestroyed) controller.destroy();
  }

  static WindowsSharedEngineScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WindowsSharedEngineScope>();

  @override
  bool updateShouldNotify(WindowsSharedEngineScope oldWidget) => false;
}

class _SharedWindowDelegate with WindowControllerDelegate {
  _SharedWindowDelegate(this.onClosed);

  final VoidCallback onClosed;

  @override
  void onWindowDestroyed() => onClosed();
}
