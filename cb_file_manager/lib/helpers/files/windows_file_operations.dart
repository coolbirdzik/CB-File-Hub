import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../utils/app_logger.dart';

/// Helper class for Windows-native file operations with progress dialog
class WindowsFileOperations {
  static const MethodChannel _channel = MethodChannel(
    'cb_file_manager/file_operations',
  );

  /// Check if native Windows file operations are available
  static bool get isAvailable => Platform.isWindows;

  /// Copy files/folders to destination using Windows native IFileOperation
  /// This shows the native Windows copy progress dialog
  static Future<bool> copyItems({
    required List<String> sources,
    required String destination,
  }) async {
    if (!isAvailable || sources.isEmpty) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('copyItems', {
        'sources': sources,
        'destination': destination,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Move files/folders to destination using Windows native IFileOperation
  /// This shows the native Windows move progress dialog
  static Future<bool> moveItems({
    required List<String> sources,
    required String destination,
  }) async {
    if (!isAvailable || sources.isEmpty) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('moveItems', {
        'sources': sources,
        'destination': destination,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Delete files/folders using Windows native IFileOperation in a single
  /// batched call. When [permanent] is false the items are sent to the
  /// Recycle Bin (FOF_ALLOWUNDO). When [silent] is true no UI is shown.
  ///
  /// This is dramatically faster than spawning powershell.exe per file.
  static Future<bool> deleteItems({
    required List<String> sources,
    bool permanent = false,
    bool silent = true,
    bool requireElevation = false,
    Duration? timeout,
  }) async {
    if (sources.isEmpty) {
      return false;
    }

    try {
      final action = permanent ? 'permanent delete' : 'move to Recycle Bin';
      final stopwatch = Stopwatch()..start();
      AppLogger.info(
        '[WindowsFileOperations] Starting $action | count=${sources.length} | silent=$silent | first=${sources.first}'
        '${sources.length > 1 ? ' | last=${sources.last}' : ''}',
      );
      final nativeCall = _channel.invokeMethod<bool>('deleteItems', {
        'sources': sources,
        'permanent': permanent,
        'silent': silent,
        'requireElevation': requireElevation,
        if (timeout != null) 'timeoutMs': timeout.inMilliseconds,
      });
      // Dart-side guard: if the native side hangs (COM deadlock, OneDrive
      // log file blocked indefinitely, etc.), fail fast instead of
      // freezing the UI on the await.
      final result = await (timeout == null
          ? nativeCall
          : nativeCall.timeout(
              timeout + const Duration(milliseconds: 750),
              onTimeout: () {
                AppLogger.warning(
                  '[WindowsFileOperations] Timed out waiting for native deleteItems response | count=${sources.length} | permanent=$permanent | timeoutMs=${timeout.inMilliseconds} | first=${sources.first}',
                );
                return false;
              },
            ));
      stopwatch.stop();
      final ok = result ?? false;
      AppLogger.info(
        '[WindowsFileOperations] Finished $action | count=${sources.length} | ok=$ok | elapsedMs=${stopwatch.elapsedMilliseconds} | first=${sources.first}',
      );
      return ok;
    } catch (e, st) {
      AppLogger.error(
        '[WindowsFileOperations] Failed native delete call | count=${sources.length} | permanent=$permanent | first=${sources.first}',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Enumerate the Windows Recycle Bin via the native Shell COM API.
  ///
  /// When [offset]/[limit] are provided, only that slice is returned in
  /// `items`. `total` always reflects the full size of the bin so the
  /// caller can drive a paged/lazy load.
  ///
  /// Returns `null` if the native method channel is unavailable or fails.
  /// Callers should fall back to a PowerShell-based enumeration in that
  /// case.
  static Future<RecycleBinNativeResult?> enumerateRecycleBin({
    int offset = 0,
    int? limit,
  }) async {
    if (!isAvailable) {
      return null;
    }
    try {
      final stopwatch = Stopwatch()..start();
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'enumerateRecycleBin',
        {if (offset > 0) 'offset': offset, 'limit': ?limit},
      );
      stopwatch.stop();
      if (raw == null) {
        AppLogger.warning(
          '[WindowsFileOperations] Native enumerateRecycleBin returned null',
        );
        return null;
      }
      final rawItems = raw['items'];
      final totalRaw = raw['total'];
      final total = totalRaw is int
          ? totalRaw
          : totalRaw is num
          ? totalRaw.toInt()
          : 0;
      final items = (rawItems is List)
          ? rawItems
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false)
          : const <Map<String, dynamic>>[];
      AppLogger.info(
        '[WindowsFileOperations] Native enumerateRecycleBin finished | offset=$offset | limit=$limit | returned=${items.length} | total=$total | elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return RecycleBinNativeResult(items: items, total: total);
    } on MissingPluginException {
      // Build does not include the new handler yet — let the caller fall
      // back gracefully.
      return null;
    } catch (e, st) {
      AppLogger.error(
        '[WindowsFileOperations] Native enumerateRecycleBin failed: $e',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}

/// Native enumerate-recycle-bin result. Records would be cleaner here but
/// the project's SDK constraint is `>=2.15.0`, which predates record types.
class RecycleBinNativeResult {
  final List<Map<String, dynamic>> items;
  final int total;

  const RecycleBinNativeResult({required this.items, required this.total});
}
