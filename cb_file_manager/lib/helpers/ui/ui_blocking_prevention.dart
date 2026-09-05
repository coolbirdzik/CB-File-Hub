import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Utilities to prevent UI blocking during heavy operations
class UIBlockingPrevention {
  /// Execute function with yield points to prevent UI blocking
  static Future<T> executeWithYield<T>(
    Future<T> Function() operation, {
    Duration yieldInterval = const Duration(milliseconds: 16), // 60fps
    int maxConsecutiveYields = 5,
  }) async {
    final completer = Completer<T>();
    int yieldCount = 0;

    // Start the operation
    operation()
        .then((result) {
          completer.complete(result);
        })
        .catchError((error) {
          completer.completeError(error);
        });

    // Periodically yield to allow UI updates
    Timer.periodic(yieldInterval, (timer) async {
      if (completer.isCompleted) {
        timer.cancel();
        return;
      }

      // Yield control to UI thread
      await Future.delayed(Duration.zero);
      yieldCount++;

      // Prevent infinite yielding
      if (yieldCount >= maxConsecutiveYields) {
        timer.cancel();
      }
    });

    return completer.future;
  }

  /// Execute operation in chunks to prevent blocking
  static Future<List<T>> executeInChunks<T>(
    List<Future<T> Function()> operations, {
    int chunkSize = 1,
    Duration delayBetweenChunks = const Duration(milliseconds: 100),
  }) async {
    final results = <T>[];

    for (int i = 0; i < operations.length; i += chunkSize) {
      final chunk = operations.skip(i).take(chunkSize);

      // Execute chunk
      final chunkResults = await Future.wait(chunk.map((op) => op()));

      results.addAll(chunkResults);

      // Yield control between chunks
      if (i + chunkSize < operations.length) {
        await Future.delayed(delayBetweenChunks);
        // Force a frame
        await SchedulerBinding.instance.endOfFrame;
      }
    }

    return results;
  }

  /// Monitor frame timing to detect UI blocking
  static void startFrameMonitoring({
    Duration warningThreshold = const Duration(milliseconds: 32), // 30fps
    void Function(Duration frameTime)? onSlowFrame,
  }) {
    if (!kDebugMode) return;

    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        final frameTime = timing.totalSpan;
        if (frameTime > warningThreshold) {
          debugPrint('⚠️ Slow frame detected: ${frameTime.inMilliseconds}ms');
          onSlowFrame?.call(frameTime);
        }
      }
    });
  }

  /// Throttle function calls to prevent overwhelming the system
  static Timer? _throttleTimer;
  static Future<T?> throttle<T>(
    Future<T> Function() operation, {
    Duration throttleDuration = const Duration(milliseconds: 200),
  }) async {
    _throttleTimer?.cancel();

    final completer = Completer<T?>();

    _throttleTimer = Timer(throttleDuration, () async {
      try {
        final result = await operation();
        completer.complete(result);
      } catch (e) {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  /// Check if main thread is currently blocked
  static Future<bool> isMainThreadBlocked({
    Duration timeout = const Duration(milliseconds: 50),
  }) async {
    final completer = Completer<bool>();
    final startTime = DateTime.now();

    // Schedule a microtask
    scheduleMicrotask(() {
      final endTime = DateTime.now();
      final delay = endTime.difference(startTime);
      completer.complete(delay > timeout);
    });

    return completer.future.timeout(
      timeout * 2,
      onTimeout: () => true, // Assume blocked if timeout
    );
  }

  /// Force frame rendering
  static Future<void> forceFrame() async {
    // Force a frame to be rendered
    await SchedulerBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 1));
  }
}
