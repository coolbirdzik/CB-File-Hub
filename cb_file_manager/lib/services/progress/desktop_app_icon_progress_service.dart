import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/services/app_update/app_update_service.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DesktopAppIconProgressService {
  static const _channel = MethodChannel('cb_file_manager/app_icon');

  DesktopAppIconProgressService({this._progressController});

  OperationProgressController? _progressController;
  final AppUpdateService _updates = AppUpdateService.instance;
  bool _started = false;
  int? _badgeCount;

  void start(OperationProgressController progressController) {
    if (_started && identical(_progressController, progressController)) return;
    stop();
    _progressController = progressController;
    _progressController?.addListener(_syncFromController);
    _updates.addListener(_syncBadge);
    _started = true;
    _syncFromController();
  }

  Future<void> stop() async {
    _progressController?.removeListener(_syncFromController);
    _updates.removeListener(_syncBadge);
    _started = false;
    await clearProgress();
    await setBadgeCount(0);
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

  /// Shows [count] as a numbered overlay on the taskbar button; 0 clears it.
  Future<void> setBadgeCount(int count) async {
    if (!Platform.isWindows || _badgeCount == count) return;
    _badgeCount = count;
    try {
      await _channel.invokeMethod<bool>('setTaskbarBadge', {'count': count});
    } catch (e) {
      if (kDebugMode) debugPrint('[AppIconProgress] setBadge error: $e');
    }
  }

  /// Mirrors the Status Center bell: unseen notifications plus an update the
  /// user has not looked at.
  void _syncBadge() {
    final controller = _progressController;
    if (controller == null) return;
    final count = controller.unseenCount + (_updates.hasUnseenUpdate ? 1 : 0);
    unawaited(setBadgeCount(count));
  }

  void _syncFromController() {
    _syncBadge();
    final aggregate = _progressController?.aggregateProgress;
    if (aggregate == null || !aggregate.hasRunning) {
      unawaited(clearProgress());
      return;
    }

    unawaited(
      setProgress(
        aggregate.fraction,
        indeterminate: aggregate.isIndeterminate,
        error: aggregate.hasError,
      ),
    );
  }
}
