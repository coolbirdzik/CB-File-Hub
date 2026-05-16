import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DesktopAppIconProgressService {
  static const _channel = MethodChannel('cb_file_manager/app_icon');

  DesktopAppIconProgressService({
    OperationProgressController? progressController,
  }) : _progressController = progressController;

  OperationProgressController? _progressController;
  bool _started = false;

  void start(OperationProgressController progressController) {
    if (_started && identical(_progressController, progressController)) return;
    stop();
    _progressController = progressController;
    _progressController?.addListener(_syncFromController);
    _started = true;
    _syncFromController();
  }

  Future<void> stop() async {
    _progressController?.removeListener(_syncFromController);
    _started = false;
    await clearProgress();
  }

  Future<void> clearProgress() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('clearTaskbarProgress');
    } catch (e) {
      if (kDebugMode) debugPrint('[AppIconProgress] clearProgress error: $e');
    }
  }

  Future<void> setProgress(
    double? value, {
    bool indeterminate = false,
    bool error = false,
  }) async {
    if (!Platform.isWindows) return;

    try {
      if (value == null && !indeterminate && !error) {
        await _channel.invokeMethod<bool>('clearTaskbarProgress');
        return;
      }
      final fraction = (value ?? 0.0).clamp(0.0, 1.0);
      await _channel.invokeMethod<bool>('setTaskbarProgress', {
        'fraction': fraction,
        'indeterminate': indeterminate,
        'error': error,
      });
      if (kDebugMode) {
        debugPrint(
          '[AppIconProgress] fraction=$fraction '
          'indeterminate=$indeterminate error=$error',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AppIconProgress] setProgress error: $e');
    }
  }

  void _syncFromController() {
    final aggregate = _progressController?.aggregateProgress;
    if (aggregate == null || !aggregate.hasRunning) {
      unawaited(clearProgress());
      return;
    }

    unawaited(setProgress(
      aggregate.fraction,
      indeterminate: aggregate.isIndeterminate,
      error: aggregate.hasError,
    ));
  }
}
