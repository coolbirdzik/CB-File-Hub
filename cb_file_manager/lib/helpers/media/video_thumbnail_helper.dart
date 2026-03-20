import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path/path.dart' as path;
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/core/app_path_helper.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'fc_native_video_thumbnail.dart';

/// Enum for thumbnail generation mode
enum ThumbnailMode {
  /// Fast mode: uses OS built-in methods (Windows shell, Android MediaStore, etc.)
  fast,

  /// Custom mode: uses FFmpeg with user-configurable timestamp position
  custom,
}

/// Status information for thumbnail generation
class ThumbnailGenerationStatus {
  /// The video path being processed
  final String videoPath;

  /// Whether the thumbnail is currently being generated
  final bool isGenerating;

  /// The generation mode being used
  final ThumbnailMode mode;

  /// The position percentage (only for custom mode)
  final int? positionPercent;

  /// The timestamp in seconds (only for custom mode)
  final int? timestampSeconds;

  /// Status message for display
  final String statusMessage;

  const ThumbnailGenerationStatus({
    required this.videoPath,
    required this.isGenerating,
    required this.mode,
    this.positionPercent,
    this.timestampSeconds,
    required this.statusMessage,
  });
}

/// Cache for video durations to avoid repeated native calls
final Map<String, int> _durationCache = {};

/// Get actual video duration using native FFmpeg library (Windows) or estimation (other platforms)
Future<int> _getActualVideoDuration(String videoPath) async {
  // Check cache first
  if (_durationCache.containsKey(videoPath)) {
    return _durationCache[videoPath]!;
  }

  if (Platform.isWindows) {
    try {
      // Native call runs on background thread, won't block UI
      final duration = await FcNativeVideoThumbnail.getVideoDuration(videoPath);
      if (duration > 0) {
        final durationInt = duration.round();
        _durationCache[videoPath] = durationInt;
        return durationInt;
      }
    } catch (e) {
      debugPrint(
          'VideoThumbnail: ✗ FFmpeg native exception for $videoPath: $e');
    }
  }

  // Fallback to estimation if native method not available or failed
  debugPrint(
      'VideoThumbnail: Using file size estimation for duration of $videoPath');
  return _getEstimatedVideoDurationIsolate(videoPath);
}

Future<int> _getEstimatedVideoDurationIsolate(String videoPath) async {
  try {
    final videoFile = File(videoPath);
    if (await videoFile.exists()) {
      final fileSize = await videoFile.length();

      // Get file extension to better estimate duration
      final extension = videoPath.toLowerCase().split('.').last;

      // Different estimation based on video format
      double estimationFactor;
      switch (extension) {
        case 'mp4':
        case 'mov':
        case 'avi':
          estimationFactor = 8.0; // 8 seconds per MB (higher quality)
          break;
        case 'mkv':
        case 'webm':
          estimationFactor = 10.0; // 10 seconds per MB (medium quality)
          break;
        case 'flv':
        case '3gp':
          estimationFactor = 15.0; // 15 seconds per MB (lower quality)
          break;
        default:
          estimationFactor = 10.0; // Default estimation
      }

      final estimatedSeconds =
          (fileSize / (1024 * 1024) * estimationFactor).round();

      // Clamp to reasonable bounds (minimum 10 seconds, maximum 10 minutes for estimation)
      final clampedDuration = estimatedSeconds.clamp(10, 600);

      debugPrint(
        'VideoThumbnail: Estimated duration for $videoPath: ${clampedDuration}s (${fileSize / (1024 * 1024)} MB, factor: $estimationFactor)',
      );

      return clampedDuration > 0 ? clampedDuration : 60;
    }
  } catch (e) {
    debugPrint('VideoThumbnail: Error estimating duration for $videoPath: $e');
  }

  // Default fallback
  return 60;
}

Future<int> _calculateTimestampFromPercentageIsolate(
  String videoPath,
  double percentage,
) async {
  // Use actual duration from ffprobe when available for accurate timestamp
  final actualDuration = await _getActualVideoDuration(videoPath);

  // Ensure percentage is within valid range
  final validPercentage = percentage.clamp(0.0, 100.0);

  // For very short videos, use a fixed timestamp
  if (actualDuration <= 10) {
    final timestamp = (actualDuration / 2).round().clamp(2, actualDuration - 2);
    return timestamp;
  }

  // Avoid the first and last 10% of the video to prevent black screens
  double adjustedPercentage = validPercentage;
  if (validPercentage < 10.0) {
    adjustedPercentage = 10.0; // Start at 10% minimum
  } else if (validPercentage > 90.0) {
    adjustedPercentage = 90.0; // End at 90% maximum
  }

  // Calculate timestamp in seconds
  int timestampSeconds =
      ((adjustedPercentage / 100.0) * actualDuration).round();

  // Ensure timestamp is within safe bounds (avoid first/last 5 seconds)
  const minTimestamp = 5;
  final maxTimestamp =
      actualDuration > 10 ? actualDuration - 5 : actualDuration ~/ 2;
  timestampSeconds = timestampSeconds.clamp(minTimestamp, maxTimestamp);

  return timestampSeconds;
}

class _ThumbnailIsolateArgs {
  final String videoPath;
  final String cacheFilename;
  final String absoluteVideoPath;
  final double thumbnailPercentage;
  final int quality;
  final int maxSize;
  final bool isWindows;
  final RootIsolateToken? rootIsolateToken;
  final bool forceRegenerate;
  final bool useFastMode;

  _ThumbnailIsolateArgs({
    required this.videoPath,
    required this.cacheFilename,
    required this.absoluteVideoPath,
    required this.thumbnailPercentage,
    required this.quality,
    required this.maxSize,
    required this.isWindows,
    required this.rootIsolateToken,
    required this.forceRegenerate,
    required this.useFastMode,
  });
}

Future<String?> _generateThumbnailIsolate(_ThumbnailIsolateArgs args) async {
  String? finalThumbnailPath;

  try {
    // Safely initialize BackgroundIsolateBinaryMessenger with proper error handling
    if (args.rootIsolateToken != null) {
      try {
        BackgroundIsolateBinaryMessenger.ensureInitialized(
          args.rootIsolateToken!,
        );
      } catch (e) {
        // This is a known issue in some Flutter environments where ensureInitialized
        // can throw a type cast error. We catch it here to allow thumbnail generation
        // to proceed (though platform channels might fail, we have fallbacks).
        debugPrint(
          'VideoThumbnail (Isolate): Failed to initialize BackgroundIsolateBinaryMessenger: $e',
        );
      }
    } else {
      debugPrint(
        'VideoThumbnail (Isolate): Warning - RootIsolateToken is null, platform channels may fail.',
      );
    }

    final Directory tempDir = await AppPathHelper.getVideoCacheDir();
    final String thumbnailPath = path.join(tempDir.path, args.cacheFilename);
    final cacheFile = File(thumbnailPath);

    // Non-blocking file check
    bool cacheExists = false;
    try {
      cacheExists = !args.forceRegenerate &&
          await cacheFile.exists() &&
          await cacheFile.length() > 0;

      if (cacheExists) {
        return thumbnailPath;
      }
    } catch (e) {
      debugPrint(
        'VideoThumbnail (Isolate): Error checking cache file $thumbnailPath: $e',
      );
    }

    // Delete existing thumbnail if force regenerating
    if (args.forceRegenerate) {
      try {
        if (await cacheFile.exists()) {
          await cacheFile.delete();
        }
      } catch (e) {
        debugPrint(
          'VideoThumbnail (Isolate): Error deleting existing thumbnail during forceRegenerate: $e',
        );
      }
    }

    // Determine timestamp based on mode
    int? timeMs;
    if (!args.useFastMode) {
      // Custom mode: calculate timestamp from percentage
      final int timestampSeconds =
          await _calculateTimestampFromPercentageIsolate(
        args.videoPath,
        args.thumbnailPercentage,
      );
      timeMs = timestampSeconds * 1000;
      debugPrint(
        'VideoThumbnail (Isolate): [Custom Mode] Using ${timestampSeconds}s (${args.thumbnailPercentage.toInt()}%)',
      );
    } else {
      // Fast mode: let the package decide (usually first frame or system default)
      timeMs = 0;
      debugPrint(
        'VideoThumbnail (Isolate): [Fast Mode] Using system default timestamp',
      );
    }

    // Use VideoThumbnail package (works on Android, iOS, macOS, Linux)
    try {
      final thumbnailFile = await VideoThumbnail.thumbnailFile(
        video: args.absoluteVideoPath,
        thumbnailPath: thumbnailPath,
        imageFormat: ImageFormat.JPEG,
        quality: args.quality,
        maxHeight: args.maxSize,
        maxWidth: args.maxSize,
        timeMs: timeMs,
      );

      if (thumbnailFile != null) {
        final bool fileValid = await _isFileValidNonBlocking(thumbnailFile);
        if (fileValid) {
          finalThumbnailPath = thumbnailFile;
          return finalThumbnailPath;
        }
      }
    } catch (e, stackTrace) {
      debugPrint(
        'VideoThumbnail (Isolate): video_thumbnail error for ${args.absoluteVideoPath}: $e\n$stackTrace',
      );
    }
  } catch (e, stackTrace) {
    debugPrint(
      'VideoThumbnail (Isolate): General error for ${args.videoPath}: $e\n$stackTrace',
    );
  }

  return null;
}

// Helper method to check if file exists and is valid without blocking
Future<bool> _isFileValidNonBlocking(String filePath) async {
  try {
    final file = File(filePath);
    final exists = await file.exists();
    if (!exists) return false;

    final length = await file.length();
    return length > 0;
  } catch (e) {
    debugPrint('VideoThumbnail (Isolate): Error validating file $filePath: $e');
    return false;
  }
}

class VideoThumbnailHelper {
  // Add a StreamController to notify when cache is cleared
  static final StreamController<void> _cacheChangedController =
      StreamController<void>.broadcast();

  // Expose a stream that widgets can listen to
  static Stream<void> get onCacheChanged => _cacheChangedController.stream;

  // Stream to notify when a specific thumbnail is generated and ready
  static final StreamController<String> _thumbnailReadyController =
      StreamController<String>.broadcast();
  static Stream<String> get onThumbnailReady =>
      _thumbnailReadyController.stream;

  /// Stream to notify about generation status for a specific video
  /// Emits a ThumbnailGenerationStatus with video path and status info
  static final StreamController<ThumbnailGenerationStatus>
      _generationStatusController =
      StreamController<ThumbnailGenerationStatus>.broadcast();
  static Stream<ThumbnailGenerationStatus> get onGenerationStatus =>
      _generationStatusController.stream;

  // Method to notify listeners that cache has changed
  static void _notifyCacheChanged() {
    _cacheChangedController.add(null);
  }

  /// Dispose resources
  static void dispose() {
    _cacheChangedController.close();
    _thumbnailReadyController.close();
    _generationStatusController.close();
  }

  // Track which paths have been logged to avoid spamming logs
  static final Set<String> _loggedPaths = {};
  static DateTime _lastLogCleanup = DateTime.now();

  static final LinkedHashMap<String, String> _fileCache =
      LinkedHashMap<String, String>();

  static final _processingQueue = <_ThumbnailRequest>[];
  static final _pendingQueue = <_ThumbnailRequest>[];

  static bool _isProcessingQueue = false;

  // Higher priority for visible thumbnails
  static const int _visiblePriority = 100;
  // Medium priority for prefetch operations
  static const int _prefetchPriority = 20;
  // Lower priority for background operations
  static const int _defaultPriority = 0;

  // PERFORMANCE: Further reduced cache size for better memory management on desktop
  static const int _maxFileCacheSize = 150; // Further reduced from 300

  // PERFORMANCE: Balanced quality for good appearance
  static const int thumbnailQuality = 75;
  // Moderate size for good quality thumbnails
  static const int maxThumbnailSize = 240;

  static bool get _isWindows => Platform.isWindows;

  static DateTime _lastCleanupTime = DateTime.now();

  static String _currentDirectory = '';

  static bool _verboseLogging = false;

  static String? _cacheIndexFilePath;

  static bool _cacheInitialized = false;

  static final UserPreferences _userPrefs = UserPreferences.instance;
  static bool _userPrefsInitialized = false;
  static double _thumbnailPercentage = 10.0;
  static ThumbnailMode _thumbnailMode = ThumbnailMode.custom;
  static int _maxConcurrency = 8;

  /// Get current thumbnail mode
  static ThumbnailMode get currentMode => _thumbnailMode;

  /// Get current max concurrency setting
  static int get maxConcurrency => _maxConcurrency;

  // Add method to refresh percentage from preferences
  static Future<void> refreshThumbnailPercentage() async {
    try {
      if (!_userPrefsInitialized) {
        await _userPrefs.init();
        _userPrefsInitialized = true;
      }

      final percentage = await _userPrefs.getVideoThumbnailPercentage();
      final oldPercentage = _thumbnailPercentage;
      _thumbnailPercentage = percentage.toDouble();

      // Also refresh thumbnail mode
      final modeString = await _userPrefs.getThumbnailMode();
      final oldMode = _thumbnailMode;
      _thumbnailMode =
          modeString == 'fast' ? ThumbnailMode.fast : ThumbnailMode.custom;

      debugPrint(
        'VideoThumbnail: Refreshed settings - percentage: $oldPercentage% -> $_thumbnailPercentage%, mode: ${oldMode.name} -> ${_thumbnailMode.name}',
      );

      // Clear cache if percentage changed significantly or mode changed to regenerate thumbnails
      final modeChanged = oldMode != _thumbnailMode;
      final percentageChanged =
          (oldPercentage - _thumbnailPercentage).abs() > 5.0;

      if (modeChanged ||
          (percentageChanged && _thumbnailMode == ThumbnailMode.custom)) {
        debugPrint(
          'VideoThumbnail: Settings changed significantly, clearing cache to regenerate thumbnails',
        );
        await clearCache();
      }
    } catch (e) {
      debugPrint('VideoThumbnail: Error refreshing thumbnail settings: $e');
    }
  }

  /// Refresh thumbnail mode from preferences
  static Future<void> refreshThumbnailMode() async {
    try {
      if (!_userPrefsInitialized) {
        await _userPrefs.init();
        _userPrefsInitialized = true;
      }

      final modeString = await _userPrefs.getThumbnailMode();
      final oldMode = _thumbnailMode;
      _thumbnailMode =
          modeString == 'fast' ? ThumbnailMode.fast : ThumbnailMode.custom;

      debugPrint(
        'VideoThumbnail: Refreshed thumbnail mode from ${oldMode.name} to ${_thumbnailMode.name}',
      );

      // Clear cache if mode changed to regenerate thumbnails
      if (oldMode != _thumbnailMode) {
        debugPrint(
          'VideoThumbnail: Mode changed, clearing cache to regenerate thumbnails',
        );
        await clearCache();
      }
    } catch (e) {
      debugPrint('VideoThumbnail: Error refreshing thumbnail mode: $e');
    }
  }

  /// Refresh max concurrency from preferences
  static Future<void> refreshMaxConcurrency() async {
    try {
      if (!_userPrefsInitialized) {
        await _userPrefs.init();
        _userPrefsInitialized = true;
      }

      final concurrency = await _userPrefs.getMaxThumbnailConcurrency();
      final oldConcurrency = _maxConcurrency;
      _maxConcurrency = concurrency;

      debugPrint(
        'VideoThumbnail: Refreshed max concurrency from $oldConcurrency to $_maxConcurrency',
      );
    } catch (e) {
      debugPrint('VideoThumbnail: Error refreshing max concurrency: $e');
    }
  }

  static Timer? _saveCacheTimer;
  static const Duration _saveCacheThrottleDuration = Duration(seconds: 10);

  static bool _initializing = false;
  static Completer<void> _initCompleter = Completer<void>();

  /// Tạo một cache lưu trữ các đường dẫn thumbnail trong bộ nhớ
  /// Được sử dụng cho hiển thị nhanh khi cuộn
  static final Map<String, String> _inMemoryPathCache = {};

  /// PERFORMANCE: Further reduced memory cache size for better performance
  /// Kích thước tối đa của cache trong bộ nhớ
  static const int _maxMemoryCacheSize = 150; // Further reduced from 300

  /// Thời gian trước khi dọn dẹp cache (reduced for more frequent cleanup)
  static const Duration _memoryCacheCleanupInterval = Duration(
    minutes: 5,
  ); // Reduced from 10

  /// Thời điểm dọn dẹp cache cuối cùng
  static DateTime _lastMemoryCacheCleanup = DateTime.now();

  /// A tracker to remember which items have had loading attempts
  /// This prevents items from being forgotten after scrolling
  static final Set<String> _attemptedPaths = {};

  // Add a static flag to check if processing should continue
  static bool _shouldStopProcessing = false;

  static void setVerboseLogging(bool enabled) {
    _verboseLogging = enabled;
  }

  static void _log(String message, {bool forceShow = false}) {
    if (_verboseLogging || forceShow) {
      debugPrint(message);
    }
  }

  // Log with path throttling (private implementation)
  static void _logWithPathThrottle(
    String message,
    String path, {
    bool forceShow = false,
  }) {
    // Clean up logged paths every 60 seconds
    final now = DateTime.now();
    if (now.difference(_lastLogCleanup).inSeconds > 60) {
      _loggedPaths.clear();
      _lastLogCleanup = now;
    }

    // Track more specific message types by using a composite key
    final logKey = '${message.split(":")[0]}:$path';

    // Only log if we haven't logged this path recently
    if (!_loggedPaths.contains(logKey)) {
      _loggedPaths.add(logKey);
      _log(message, forceShow: forceShow);
    }
  }

  // Public log throttling method for use by other classes
  static void logWithThrottle(String message, String path) {
    _logWithPathThrottle(message, path);
  }

  static Future<void> initializeCache() async {
    if (_cacheInitialized) return;
    if (_initializing) return _initCompleter.future;

    _initializing = true;
    _initCompleter = Completer<void>();

    try {
      if (!_userPrefsInitialized) {
        try {
          await _userPrefs.init();
          final percentage = await _userPrefs.getVideoThumbnailPercentage();
          _thumbnailPercentage = percentage.toDouble();

          // Also load thumbnail mode
          final modeString = await _userPrefs.getThumbnailMode();
          _thumbnailMode =
              modeString == 'fast' ? ThumbnailMode.fast : ThumbnailMode.custom;

          // Also load max concurrency
          final concurrency = await _userPrefs.getMaxThumbnailConcurrency();
          _maxConcurrency = concurrency;

          _userPrefsInitialized = true;
          _log(
            'VideoThumbnail: UserPreferences initialized. Percentage: $_thumbnailPercentage%, Mode: ${_thumbnailMode.name}, Concurrency: $_maxConcurrency',
          );
        } catch (e) {
          _log(
            'VideoThumbnail: Error initializing UserPreferences: $e',
            forceShow: true,
          );
          _thumbnailPercentage = 10.0;
          _thumbnailMode = ThumbnailMode.custom;
          _maxConcurrency = 8;
        }
      }

      await _loadCacheFromDisk();
      _cacheInitialized = true;
      _log('VideoThumbnail: Cache system initialized.');

      _initCompleter.complete();
    } catch (e) {
      _log(
        'VideoThumbnail: Error during cache initialization: $e',
        forceShow: true,
      );
      _initCompleter.completeError(e);
      _cacheInitialized = false;
      _userPrefsInitialized = false;
    } finally {
      _initializing = false;
    }
  }

  static void setCurrentDirectory(String dirPath) {
    if (_currentDirectory == dirPath) return;

    _log(
      'VideoThumbnail: Changing directory from "$_currentDirectory" to "$dirPath"',
      forceShow: true,
    );
    _currentDirectory = dirPath;

    cancelThumbnailsNotInDirectory(dirPath);
  }

  static String _normalizePathForComparison(String value) {
    var normalized = path.normalize(value);
    if (Platform.isWindows) {
      normalized = normalized.toLowerCase();
    }
    return normalized;
  }

  /// Get the normalized cache key for a video path
  /// Used for comparing paths in thumbnail ready events
  static String getNormalizedPath(String videoPath) {
    return _cacheKeyForPath(videoPath);
  }

  static String _cacheKeyForPath(String value) {
    if (value.isEmpty) return value;
    if (value.startsWith('#')) return value;

    var resolved = value;
    if (!resolved.startsWith('\\\\') && !resolved.startsWith('//')) {
      resolved = path.absolute(resolved);
    }
    resolved = path.normalize(resolved);

    if (Platform.isWindows) {
      resolved = resolved.replaceAll('/', '\\').toLowerCase();
    }
    return resolved;
  }

  static bool _isSameOrWithinDirectory(String baseDir, String candidateDir) {
    final base = _normalizePathForComparison(baseDir);
    final candidate = _normalizePathForComparison(candidateDir);
    if (candidate == base) {
      return true;
    }
    try {
      return path.isWithin(base, candidate);
    } catch (_) {
      return false;
    }
  }

  static void cancelThumbnailsNotInDirectory(String dirPath) {
    if (dirPath.isEmpty) return;

    int canceledCount = 0;

    // Set flag to stop any new processing
    _shouldStopProcessing = true;

    // Clear pending queue for other directories
    final List<_ThumbnailRequest> requestsToRemove = [];

    for (final request in _pendingQueue) {
      final requestDir = path.dirname(request.videoPath);
      if (!_isSameOrWithinDirectory(dirPath, requestDir)) {
        if (!request.completer.isCompleted) {
          request.completer.complete(null);
        }
        requestsToRemove.add(request);
        canceledCount++;
      }
    }

    _pendingQueue.removeWhere((req) => requestsToRemove.contains(req));

    // Also cancel any currently processing thumbnails
    final List<_ThumbnailRequest> processingsToRemove = [];
    for (final request in _processingQueue) {
      final requestDir = path.dirname(request.videoPath);
      if (!_isSameOrWithinDirectory(dirPath, requestDir)) {
        if (!request.completer.isCompleted) {
          request.completer.complete(null);
        }
        processingsToRemove.add(request);
        canceledCount++;
      }
    }

    _processingQueue.removeWhere((req) => processingsToRemove.contains(req));

    // Reset flag after clearing the queues
    _shouldStopProcessing = false;

    _log(
      'VideoThumbnail: Canceled $canceledCount thumbnails for other directories',
      forceShow: true,
    );
  }

  static bool isSupportedVideoFormat(String filePath) {
    final lowercasePath = filePath.toLowerCase();

    final supportedExtensions = [
      '.mp4',
      '.mov',
      '.avi',
      '.mkv',
      '.wmv',
      '.flv',
      '.webm',
      '.mpg',
      '.mpeg',
      '.m4v',
      '.3gp',
    ];

    return supportedExtensions.any((ext) => lowercasePath.endsWith(ext));
  }

  static Future<void> _addToFileCache(String key, String value) async {
    final file = File(value);
    if (!await file.exists()) {
      _log(
        'VideoThumbnail: Warning - Attempted to cache non-existent file: $value',
      );
      return;
    }

    _fileCache.remove(key);

    if (_fileCache.length >= _maxFileCacheSize) {
      final oldestKey = _fileCache.keys.first;
      _fileCache.remove(oldestKey);
      _log('VideoThumbnail: Removed oldest item from file cache: $oldestKey');
    }

    _fileCache[key] = value;
    _log('VideoThumbnail: Added to file cache: $key => $value');
  }

  static Future<void> _cleanupOldTempFiles() async {
    final now = DateTime.now();
    if (now.difference(_lastCleanupTime).inHours < 1) {
      return;
    }

    _lastCleanupTime = now;

    try {
      final tempDir = await AppPathHelper.getVideoCacheDir();
      final directory = Directory(tempDir.path);

      final files = await directory
          .list()
          .where((file) => path.basename(file.path).startsWith('thumb_'))
          .toList();

      for (final file in files) {
        if (!_fileCache.values.contains(file.path)) {
          try {
            final stat = await file.stat();
            if (now.difference(stat.modified).inHours > 24) {
              await file.delete();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<void> removeFromCache(String videoPath) async {
    final cacheKey = _cacheKeyForPath(videoPath);
    // Xóa khỏi cache trong bộ nhớ ngay lập tức
    _inMemoryPathCache.remove(videoPath);
    _inMemoryPathCache.remove(cacheKey);

    // Xóa khỏi file cache
    final cachedPath = _fileCache[cacheKey] ?? _fileCache[videoPath];
    if (cachedPath != null) {
      _fileCache.remove(cacheKey);
      _fileCache.remove(videoPath);

      // Xóa file trên đĩa trong background
      unawaited(() async {
        try {
          final file = File(cachedPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          _log('VideoThumbnail: Error deleting invalid cached file: $e');
        }
      }());
    }
  }

  /// Process the thumbnail generation queue
  static Future<void> _processQueue() async {
    if (_isProcessingQueue || _pendingQueue.isEmpty) return;

    _isProcessingQueue = true;

    try {
      while (_pendingQueue.isNotEmpty) {
        // Respect stop flag early
        if (_shouldStopProcessing) {
          _log('VideoThumbnail: Stopping queue processing due to stop flag');
          break;
        }

        // IMPORTANT: Process ONE request at a time to maintain strict
        // top-to-bottom order based on the user's sort selection.
        // The queue is priority-sorted (proactiveGenerateAll assigns
        // decreasing priorities by list position), so processing
        // sequentially guarantees thumbnails appear in sort order.
        final request = _pendingQueue.removeAt(0);

        // Track processing request for cancellation awareness
        _processingQueue.add(request);

        try {
          final result = await _generateThumbnailInternal(
            request.videoPath,
            forceRegenerate: request.forceRegenerate,
            quality: request.quality,
            thumbnailSize: request.thumbnailSize,
          );

          if (result != null) {
            _fileCache[request.videoPath] = result;
            if (!request.completer.isCompleted) {
              request.completer.complete(result);
            }
            // Always notify listeners so widgets that relied solely on the
            // stream (e.g. the proactive-queue path in LazyVideoThumbnail)
            // receive the signal even when _generateThumbnailInternal returned
            // a cached path without firing the notification itself.
            try {
              _thumbnailReadyController.add(request.videoPath);
            } catch (_) {}
          } else {
            if (!request.completer.isCompleted) {
              request.completer.complete(null);
            }
          }
        } catch (e) {
          debugPrint(
            'VideoThumbnail: Error processing request for ${request.videoPath}: $e',
          );
          if (!request.completer.isCompleted) {
            request.completer.complete(null);
          }
        } finally {
          _processingQueue.remove(request);
        }

        // Yield to event loop between items
        if (_pendingQueue.isNotEmpty) {
          await Future.delayed(Duration.zero);
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  static Future<String?> _requestThumbnail(
    String videoPath, {
    int priority = _defaultPriority,
    bool forceRegenerate = false,
    int? quality,
    int? thumbnailSize,
  }) {
    final cacheKey = _cacheKeyForPath(videoPath);
    final existingPending = _pendingQueue.firstWhere(
      (req) => req.videoPath == cacheKey,
      orElse: () => _ThumbnailRequest.empty(),
    );
    final existingProcessing = _processingQueue.firstWhere(
      (req) => req.videoPath == cacheKey,
      orElse: () => _ThumbnailRequest.empty(),
    );

    if (existingPending.videoPath.isNotEmpty &&
        existingPending.priority >= priority) {
      return existingPending.completer.future;
    }
    if (existingProcessing.videoPath.isNotEmpty &&
        existingProcessing.priority >= priority) {
      return existingProcessing.completer.future;
    }

    _ThumbnailRequest? oldRequest;
    if (existingPending.videoPath.isNotEmpty) {
      oldRequest = existingPending;
      _pendingQueue.remove(existingPending);
    }

    final completer = Completer<String?>();
    final newRequest = _ThumbnailRequest(
      videoPath: cacheKey,
      priority: priority,
      completer: completer,
      timestamp: DateTime.now(),
      forceRegenerate: forceRegenerate,
      quality: quality,
      thumbnailSize: thumbnailSize,
    );

    _pendingQueue.add(newRequest);
    _pendingQueue.sort((a, b) {
      if (a.priority != b.priority) {
        return b.priority.compareTo(a.priority);
      }
      return a.timestamp.compareTo(b.timestamp);
    });

    Timer.run(_processQueue);

    if (oldRequest != null && !oldRequest.completer.isCompleted) {
      completer.future.then(
        (value) {
          if (!oldRequest!.completer.isCompleted) {
            oldRequest.completer.complete(value);
          }
        },
        onError: (error, stackTrace) {
          if (!oldRequest!.completer.isCompleted) {
            oldRequest.completer.completeError(error, stackTrace);
          }
        },
      );
    }

    return completer.future;
  }

  static Future<String?> _generateThumbnailInternal(
    String videoPath, {
    bool forceRegenerate = false,
    int? quality,
    int? thumbnailSize,
  }) async {
    try {
      // Check if processing should stop before doing intensive work
      if (_shouldStopProcessing) {
        _log(
          'VideoThumbnail: Generation canceled for $videoPath due to directory change',
        );
        return null;
      }

      if (!forceRegenerate) {
        final cached = await getFromCache(videoPath);
        if (cached != null) {
          return cached;
        }
      }

      final cacheKey = _cacheKeyForPath(videoPath);
      final cacheFilename = _createCacheFilename(cacheKey);

      String absoluteVideoPath = cacheKey;
      if (_isWindows) {
        absoluteVideoPath = absoluteVideoPath.replaceAll('\\', '/');
      }

      if (!_userPrefsInitialized) {
        _log(
          'VideoThumbnail: Warning - UserPrefs not initialized in _generateThumbnailInternal. Using default percentage.',
          forceShow: true,
        );
      }
      final percentage = _thumbnailPercentage.toDouble();

      // PERFORMANCE: Ensure all file I/O operations are async (non-blocking)
      // First check if already exists in cache and valid before using compute
      if (!forceRegenerate && _fileCache.containsKey(cacheKey)) {
        final cachedPath = _fileCache[cacheKey]!;
        final cacheFile = File(cachedPath);
        try {
          // All file operations are already async - verified
          if (await cacheFile.exists() && await cacheFile.length() > 0) {
            _log('VideoThumbnail: Using valid cache for $cacheKey');
            return cachedPath;
          } else {
            _log('VideoThumbnail: Cache invalid for $cacheKey, regenerating');
            _fileCache.remove(cacheKey);
          }
        } catch (e) {
          _log('VideoThumbnail: Error checking cache: $e');
          _fileCache.remove(cacheKey);
        }
      }

      // Check again if we should stop before starting the compute-intensive work
      if (_shouldStopProcessing) {
        _log(
          'VideoThumbnail: Generation canceled for $videoPath due to directory change',
        );
        return null;
      }

      // On Windows, call directly without isolate because VideoThumbnail package
      // doesn't work in isolates due to BackgroundIsolateBinaryMessenger issues
      String? generatedPath;

      if (_isWindows) {
        _log(
            'VideoThumbnail: Using direct generation on Windows for $cacheKey');
        try {
          generatedPath = await _generateThumbnailDirectWindows(
            videoPath: cacheKey,
            cacheFilename: cacheFilename,
            absoluteVideoPath: absoluteVideoPath,
            percentage: percentage.toInt(),
            quality: quality ?? thumbnailQuality,
            maxSize: thumbnailSize ?? maxThumbnailSize,
            forceRegenerate: forceRegenerate,
          );
        } catch (e, stack) {
          _log(
            'VideoThumbnail: Error during direct generation for $videoPath: $e\n$stack',
            forceShow: true,
          );
          return null;
        }
      } else {
        // On non-Windows platforms, use isolates
        final rootToken = RootIsolateToken.instance;
        if (rootToken == null) {
          _log(
            'VideoThumbnail: Error - RootIsolateToken.instance is null.',
            forceShow: true,
          );
        }

        // Emit status for non-Windows platforms
        final mode = _thumbnailMode;
        try {
          _generationStatusController.add(ThumbnailGenerationStatus(
            videoPath: videoPath,
            isGenerating: true,
            mode: mode,
            positionPercent:
                mode == ThumbnailMode.custom ? percentage.toInt() : null,
            statusMessage: mode == ThumbnailMode.fast
                ? 'Fast mode'
                : '${percentage.toInt()}%',
          ));
        } catch (_) {}

        final args = _ThumbnailIsolateArgs(
          videoPath: videoPath,
          cacheFilename: cacheFilename,
          absoluteVideoPath: absoluteVideoPath,
          thumbnailPercentage: percentage,
          quality: quality ?? thumbnailQuality,
          maxSize: thumbnailSize ?? maxThumbnailSize,
          isWindows: _isWindows,
          rootIsolateToken: rootToken,
          forceRegenerate: forceRegenerate,
          useFastMode: mode == ThumbnailMode.fast,
        );

        try {
          generatedPath =
              await compute(_generateThumbnailIsolate, args).timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              _log(
                'VideoThumbnail: Timeout generating thumbnail for $videoPath',
                forceShow: true,
              );
              return null;
            },
          );
        } catch (e, stack) {
          _log(
            'VideoThumbnail: Error during compute for $videoPath: $e\n$stack',
            forceShow: true,
          );
          return null;
        }
      }

      if (generatedPath != null) {
        final resultFile = File(generatedPath);
        if (await resultFile.exists() && await resultFile.length() > 0) {
          await _addToFileCache(cacheKey, generatedPath);
          // Update in-memory for fast subsequent access
          _inMemoryPathCache[cacheKey] = generatedPath;
          // Notify listeners this specific thumbnail is ready
          try {
            _thumbnailReadyController.add(cacheKey);
          } catch (_) {}
          _saveCacheToDiskThrottled();
          return generatedPath;
        } else {
          _log(
            'VideoThumbnail: Compute returned path but file invalid: $generatedPath',
          );
          try {
            if (await resultFile.exists()) await resultFile.delete();
          } catch (_) {}
        }
      }
    } catch (e, stackTrace) {
      _log(
        'VideoThumbnail: Error in _generateThumbnailInternal for $videoPath: $e\n$stackTrace',
        forceShow: true,
      );
    }

    return null;
  }

  /// Generate thumbnail directly on Windows without using compute/isolates
  /// This avoids BackgroundIsolateBinaryMessenger crashes on Windows
  /// The native plugin already uses a C++ thread pool, so no UI blocking
  static Future<String?> _generateThumbnailDirectWindows({
    required String videoPath,
    required String cacheFilename,
    required String absoluteVideoPath,
    required int percentage,
    required int quality,
    required int maxSize,
    required bool forceRegenerate,
  }) async {
    try {
      final tempDir = await AppPathHelper.getVideoCacheDir();
      final thumbnailPath = path.join(tempDir.path, cacheFilename);
      final cacheFile = File(thumbnailPath);

      // Check cache first
      if (!forceRegenerate) {
        try {
          if (await cacheFile.exists() && await cacheFile.length() > 0) {
            return thumbnailPath;
          }
        } catch (e) {
          _log('VideoThumbnail: Error checking cache: $e');
        }
      }

      // Delete existing thumbnail if force regenerating
      if (forceRegenerate && await cacheFile.exists()) {
        try {
          await cacheFile.delete();
        } catch (_) {}
      }

      String? nativePath;
      final mode = _thumbnailMode;

      if (mode == ThumbnailMode.fast) {
        // Fast mode: use OS shell thumbnail (Windows shell cache)
        _log(
            'VideoThumbnail: [Fast Mode] Using shell thumbnail for $videoPath');

        // Emit status for fast mode
        try {
          _generationStatusController.add(ThumbnailGenerationStatus(
            videoPath: videoPath,
            isGenerating: true,
            mode: ThumbnailMode.fast,
            statusMessage: 'Fast mode',
          ));
        } catch (_) {}

        try {
          nativePath = await FcNativeVideoThumbnail.generateThumbnail(
            videoPath: absoluteVideoPath,
            outputPath: thumbnailPath,
            width: maxSize,
            format: 'jpg',
            timeSeconds: null, // Use Windows shell cache
            quality: quality,
          );

          if (nativePath != null) {
            final file = File(nativePath);
            if (await file.exists() && await file.length() > 0) {
              _log(
                  'VideoThumbnail: [Fast Mode] Shell thumbnail successful for $videoPath');
              return nativePath;
            }
          }
        } catch (e) {
          _log(
              'VideoThumbnail: [Fast Mode] Shell thumbnail failed for $videoPath: $e');
        }
      } else {
        // Custom mode: use FFmpeg with user-configured timestamp percentage
        // Using optimized single-pass extraction that gets duration + thumbnail in one file open
        _log(
            'VideoThumbnail: [Custom Mode] Extracting at ${percentage}% of video for $videoPath');

        // Emit status for custom mode with position info
        try {
          _generationStatusController.add(ThumbnailGenerationStatus(
            videoPath: videoPath,
            isGenerating: true,
            mode: ThumbnailMode.custom,
            positionPercent: percentage,
            statusMessage: '${percentage}%',
          ));
        } catch (_) {}

        try {
          // Use the optimized single-pass method that opens the file ONCE
          // This is ~2x faster than separate getVideoDuration + generateThumbnail calls
          nativePath =
              await FcNativeVideoThumbnail.generateThumbnailAtPercentage(
            videoPath: absoluteVideoPath,
            outputPath: thumbnailPath,
            percentage: percentage.toDouble(),
            width: maxSize,
            format: 'jpg',
            quality: quality,
          );

          if (nativePath != null) {
            final file = File(nativePath);
            if (await file.exists() && await file.length() > 0) {
              _log(
                  'VideoThumbnail: [Custom Mode] Extraction successful at ${percentage}% for $videoPath');
              return nativePath;
            }
          }
        } catch (e) {
          _log(
              'VideoThumbnail: [Custom Mode] Extraction failed for $videoPath: $e');
        }

        // Fallback to shell thumbnail only if custom mode extraction failed
        if (nativePath == null) {
          _log(
            'VideoThumbnail: [Custom Mode] Falling back to shell thumbnail for $videoPath',
          );
          try {
            nativePath = await FcNativeVideoThumbnail.generateThumbnail(
              videoPath: absoluteVideoPath,
              outputPath: thumbnailPath,
              width: maxSize,
              format: 'jpg',
              timeSeconds: null,
              quality: quality,
            );
          } catch (e) {
            _log(
                'VideoThumbnail: Shell thumbnail also failed for $videoPath: $e');
          }

          if (nativePath != null) {
            final file = File(nativePath);
            if (await file.exists() && await file.length() > 0) {
              _log(
                  'VideoThumbnail: Thumbnail generation successful for $videoPath');
              return nativePath;
            }
          } else {
            _log(
              'VideoThumbnail: Thumbnail generation returned null for $videoPath',
              forceShow: true,
            );
          }
        }
      }

      return null;
    } catch (e, stackTrace) {
      _log(
        'VideoThumbnail: Error in _generateThumbnailDirectWindows for $videoPath: $e\n$stackTrace',
        forceShow: true,
      );
      return null;
    }
  }

  static String _createCacheFilename(String videoPath) {
    final bytes = utf8.encode(videoPath);
    final digest = md5.convert(bytes);
    return 'thumb_${digest.toString()}.jpg';
  }

  static void _saveCacheToDiskThrottled() {
    if (_saveCacheTimer?.isActive ?? false) {
      _saveCacheTimer!.cancel();
    }
    _saveCacheTimer = Timer(_saveCacheThrottleDuration, () {
      _saveCacheToDiskActual();
      _saveCacheTimer = null;
    });
  }

  static Future<void> _saveCacheToDiskActual() async {
    try {
      if (_cacheIndexFilePath == null) {
        final tempDir = await getTemporaryDirectory();
        _cacheIndexFilePath = path.join(
          tempDir.path,
          'thumbnail_cache_index.json',
        );
      }

      final cacheData = Map<String, String>.from(_fileCache);

      await compute(_saveCacheIsolate, {
        'filePath': _cacheIndexFilePath!,
        'cacheData': cacheData,
      });
    } catch (e) {
      _log('VideoThumbnail: Error initiating cache save: $e', forceShow: true);
    }
  }

  static Future<void> _saveCacheIsolate(Map<String, dynamic> args) async {
    final String filePath = args['filePath'];
    final Map<String, String> cacheData = args['cacheData'];
    try {
      final jsonData = jsonEncode(cacheData);
      await File(filePath).writeAsString(jsonData);
    } catch (e) {
      debugPrint('VideoThumbnail (Isolate): Error saving cache to disk: $e');
    }
  }

  static Future<void> _loadCacheFromDisk() async {
    _log('VideoThumbnail: Loading cache from disk...');
    try {
      _fileCache.clear();

      if (_cacheIndexFilePath == null) {
        final tempDir = await getTemporaryDirectory();
        _cacheIndexFilePath = path.join(
          tempDir.path,
          'thumbnail_cache_index.json',
        );
      }

      final indexFile = File(_cacheIndexFilePath!);
      if (!await indexFile.exists()) {
        _log('VideoThumbnail: No cache index file found.');
        return;
      }

      final jsonData = await indexFile.readAsString();
      try {
        final cacheData = jsonDecode(jsonData) as Map<String, dynamic>;
        int validCount = 0;
        int invalidCount = 0;
        for (final entry in cacheData.entries) {
          final thumbnailPath = entry.value as String?;
          final videoPath = entry.key;
          if (thumbnailPath != null) {
            _fileCache[videoPath] = thumbnailPath;
            validCount++;
          } else {
            invalidCount++;
          }
        }
        _log(
          'VideoThumbnail: Loaded $validCount entries from disk index (ignored $invalidCount invalid).',
        );
      } catch (e) {
        _log(
          'VideoThumbnail: Error decoding cache JSON: $e. Deleting corrupt index.',
          forceShow: true,
        );
        try {
          await indexFile.delete();
        } catch (_) {}
      }
    } catch (e) {
      _log(
        'VideoThumbnail: Error loading cache from disk: $e',
        forceShow: true,
      );
    }
  }

  /// Generate a thumbnail for a video file
  static Future<String?> generateThumbnail(
    String videoPath, {
    bool forceRegenerate = false,
    bool isPriority = false,
    int? quality,
    int? thumbnailSize,
  }) async {
    if (!_cacheInitialized) {
      if (_initializing) {
        await _initCompleter.future;
      } else {
        await initializeCache();
      }
    }

    if (!isSupportedVideoFormat(videoPath)) {
      _log('VideoThumbnail: Unsupported video format: $videoPath');
      return null;
    }

    if (forceRegenerate) {
      _log('VideoThumbnail: Force regenerating thumbnail for: $videoPath');
      final cacheKey = _cacheKeyForPath(videoPath);
      _fileCache.remove(cacheKey);
      _inMemoryPathCache.remove(cacheKey);
    }

    final priority = isPriority ? _visiblePriority : _defaultPriority;

    // Choose sensible defaults if not provided
    final effectiveQuality = quality ?? (isPriority ? 55 : 45);
    final effectiveSize = thumbnailSize ?? (isPriority ? 200 : 160);

    final result = await _requestThumbnail(
      videoPath,
      priority: priority,
      forceRegenerate: forceRegenerate,
      quality: effectiveQuality,
      thumbnailSize: effectiveSize,
    );

    return result;
  }

  static Future<Uint8List?> generateThumbnailData(
    String videoPath, {
    bool isPriority = false,
    bool forceRegenerate = false,
  }) async {
    if (!_cacheInitialized) {
      if (_initializing) {
        await _initCompleter.future;
      } else {
        await initializeCache();
      }
    }

    if (!isSupportedVideoFormat(videoPath)) {
      debugPrint('VideoThumbnail: Unsupported video format: $videoPath');
      return null;
    }

    try {
      final thumbnailPath = await generateThumbnail(
        videoPath,
        isPriority: isPriority,
        forceRegenerate: forceRegenerate,
      );

      if (thumbnailPath != null) {
        try {
          final File thumbnailFile = File(thumbnailPath);
          if (await thumbnailFile.exists()) {
            final bytes = await thumbnailFile.readAsBytes();
            if (bytes.isNotEmpty) {
              return bytes;
            } else {
              debugPrint(
                'VideoThumbnail: Thumbnail file is empty: $thumbnailPath',
              );
              await removeFromCache(videoPath);
              try {
                await thumbnailFile.delete();
              } catch (_) {}
              return null;
            }
          } else {
            debugPrint(
              'VideoThumbnail: Thumbnail file path obtained but file does not exist: $thumbnailPath',
            );
            await removeFromCache(videoPath);
            return null;
          }
        } catch (e) {
          debugPrint(
            'VideoThumbnail: Error reading thumbnail file $thumbnailPath: $e',
          );
          await removeFromCache(videoPath);
          try {
            final file = File(thumbnailPath);
            if (await file.exists()) await file.delete();
          } catch (_) {}
          return null;
        }
      } else {
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint(
        'VideoThumbnail: Error in generateThumbnailData for $videoPath: $e',
      );
      debugPrint('VideoThumbnail: Stack trace: $stackTrace');
    }

    return null;
  }

  static Future<String?> getFromCache(String videoPath) async {
    if (!_cacheInitialized) {
      if (_initializing) {
        await _initCompleter.future;
      } else {
        await initializeCache();
      }
    }

    final cacheKey = _cacheKeyForPath(videoPath);
    final keys = <String>{
      cacheKey,
      videoPath,
    }.where((k) => k.isNotEmpty).toList(growable: false);

    for (final key in keys) {
      if (_inMemoryPathCache.containsKey(key)) {
        final cachedPath = _inMemoryPathCache[key];
        if (cachedPath != null) {
          final cacheFile = File(cachedPath);
          if (await cacheFile.exists()) {
            final value = _inMemoryPathCache.remove(key)!;
            _inMemoryPathCache[key] = value;
            if (cacheKey != key) {
              _inMemoryPathCache[cacheKey] = cachedPath;
            }
            return cachedPath;
          } else {
            _inMemoryPathCache.remove(key);
          }
        }
      }
    }

    for (final key in keys) {
      if (_fileCache.containsKey(key)) {
        final cachedPath = _fileCache[key]!;
        try {
          final file = File(cachedPath);
          if (await file.exists() && await file.length() > 0) {
            _addToMemoryCache(cacheKey, cachedPath);
            if (cacheKey != key) {
              _fileCache[cacheKey] = cachedPath;
            }
            return cachedPath;
          } else {
            _fileCache.remove(key);
          }
        } catch (e) {
          _log('VideoThumbnail: Error checking cache file $cachedPath: $e');
          _fileCache.remove(key);
        }
      }
    }

    try {
      final tempDir = await AppPathHelper.getVideoCacheDir();
      final candidates = <String>{
        path.join(tempDir.path, _createCacheFilename(cacheKey)),
        path.join(tempDir.path, _createCacheFilename(videoPath)),
      }.toList(growable: false);

      for (final candidate in candidates) {
        final file = File(candidate);
        if (await file.exists() && await file.length() > 0) {
          _fileCache[cacheKey] = candidate;
          _addToMemoryCache(cacheKey, candidate);
          return candidate;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Thêm đường dẫn vào cache bộ nhớ với cơ chế LRU (Least Recently Used)
  static void _addToMemoryCache(String videoPath, String thumbnailPath) {
    // Kiểm tra xem đã đến lúc dọn dẹp cache chưa
    final now = DateTime.now();
    if (now.difference(_lastMemoryCacheCleanup) > _memoryCacheCleanupInterval) {
      _cleanMemoryCache();
    }

    // Nếu đã tồn tại, cập nhật lại vị trí
    if (_inMemoryPathCache.containsKey(videoPath)) {
      final value = _inMemoryPathCache.remove(videoPath)!;
      _inMemoryPathCache[videoPath] = value;
      return;
    }

    // Nếu cache đầy, xóa entry cũ nhất (first item in LinkedHashMap)
    if (_inMemoryPathCache.length >= _maxMemoryCacheSize) {
      // Xóa entry đầu tiên (cũ nhất)
      final oldestKey = _inMemoryPathCache.keys.first;
      _inMemoryPathCache.remove(oldestKey);
    }

    // Thêm vào cache
    _inMemoryPathCache[videoPath] = thumbnailPath;
  }

  /// Dọn dẹp cache trong bộ nhớ
  static void _cleanMemoryCache() {
    _log('VideoThumbnail: Cleaning memory cache...');
    _lastMemoryCacheCleanup = DateTime.now();

    // Giữ lại 2/3 các entry gần đây nhất
    if (_inMemoryPathCache.length > _maxMemoryCacheSize / 2) {
      final keepCount = (_maxMemoryCacheSize * 2 / 3).round();
      final keysToRemove = _inMemoryPathCache.keys
          .take(_inMemoryPathCache.length - keepCount)
          .toList();
      for (final key in keysToRemove) {
        _inMemoryPathCache.remove(key);
      }
      _log(
        'VideoThumbnail: Memory cache trimmed to ${_inMemoryPathCache.length} entries',
      );
    }
  }

  static Widget buildVideoThumbnail({
    required String videoPath,
    Widget Function()? fallbackBuilder,
    double width = 200,
    double height = 150,
    BoxFit fit = BoxFit.cover,
    bool isPriority = false,
    bool forceRegenerate = false,
    Key? key,
    void Function(String?)? onThumbnailGenerated,
  }) {
    defaultFallback() => Container(
          color: Colors.grey[300],
          child: const Center(
            child: Icon(PhosphorIconsLight.filmStrip,
                size: 40, color: Colors.grey),
          ),
        );

    final requestedSize =
        (max(width, height).isFinite && max(width, height) > 0)
            ? max(width, height).toInt()
            : null;

    return FutureBuilder<String?>(
      key: key ?? ValueKey('thumb_$videoPath'),
      future: generateThumbnail(
        videoPath,
        isPriority: isPriority,
        forceRegenerate: forceRegenerate,
        thumbnailSize: requestedSize,
        quality: isPriority ? 85 : 60,
      ),
      builder: (context, snapshot) {
        Widget content;
        final thumbnailPath = snapshot.data;

        // Notify the parent when a thumbnail is generated
        if (thumbnailPath != null && onThumbnailGenerated != null) {
          // Use a microtask to avoid calling during build
          scheduleMicrotask(() => onThumbnailGenerated(thumbnailPath));
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            thumbnailPath == null) {
          content = fallbackBuilder?.call() ?? defaultFallback();
        } else if (snapshot.hasError) {
          _log(
            'VideoThumbnail FutureBuilder error for $videoPath: ${snapshot.error}',
          );
          content = fallbackBuilder?.call() ?? defaultFallback();
        } else if (thumbnailPath != null) {
          final int? cWidth =
              (width.isFinite && width > 0) ? width.toInt() : null;
          final int? cHeight =
              (height.isFinite && height > 0) ? height.toInt() : null;
          content = Image(
            image: ResizeImage(
              FileImage(File(thumbnailPath)),
              width: cWidth,
              height: cHeight,
            ),
            key: ValueKey(thumbnailPath),
            width: width,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child,
                    // Add video play icon overlay
                    const Center(
                      child: Icon(
                        PhosphorIconsLight.playCircle,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ],
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              _log('Error loading thumbnail image file $thumbnailPath: $error');
              final cacheKey = _cacheKeyForPath(videoPath);
              _fileCache.remove(cacheKey);
              _inMemoryPathCache.remove(cacheKey);
              unawaited(() async {
                try {
                  final file = File(thumbnailPath);
                  if (await file.exists()) await file.delete();
                } catch (_) {}
              }());
              return fallbackBuilder?.call() ?? defaultFallback();
            },
          );
        } else {
          content = fallbackBuilder?.call() ?? defaultFallback();
        }

        return content;
      },
    );
  }

  static Future<void> clearCache() async {
    _log('VideoThumbnail: Clearing cache...', forceShow: true);

    // Set a flag to prevent new thumbnail requests during cache clearing
    _isProcessingQueue = true;
    _shouldStopProcessing = true;

    try {
      // Clear in-memory caches first
      _fileCache.clear();
      _inMemoryPathCache.clear();

      // Don't clear _attemptedPaths here, we want to regenerate all thumbnails
      // including those that previously failed
      _attemptedPaths.clear();

      // Cancel all pending thumbnail requests first
      final pendingRequests = List<_ThumbnailRequest>.from(_pendingQueue);
      _pendingQueue.clear();

      for (final request in pendingRequests) {
        try {
          if (!request.completer.isCompleted) {
            request.completer.complete(null);
          }
        } catch (e) {
          _log('VideoThumbnail: Error completing pending request: $e');
        }
      }

      // Wait briefly for any ongoing compute operations to finish
      await Future.delayed(const Duration(milliseconds: 100));

      // Cancel all processing requests
      final processingRequests = List<_ThumbnailRequest>.from(_processingQueue);
      _processingQueue.clear();

      for (final request in processingRequests) {
        try {
          if (!request.completer.isCompleted) {
            request.completer.complete(null);
          }
        } catch (e) {
          _log('VideoThumbnail: Error completing processing request: $e');
        }
      }

      // Reset initialization state
      _initializing = false;
      _initCompleter = Completer<void>();

      // Clear Flutter's image cache to prevent memory leaks and old thumbnail display
      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (e) {
        _log('VideoThumbnail: Error clearing PaintingBinding image cache: $e');
      }

      // Delete physical thumbnail files
      try {
        final tempDir = await AppPathHelper.getVideoCacheDir();
        final directory = Directory(tempDir.path);

        if (!await directory.exists()) {
          _log(
            'VideoThumbnail: Temporary directory not found for clearing cache.',
          );
          return;
        }

        final thumbnailFiles = await directory
            .list()
            .where((file) => path.basename(file.path).startsWith('thumb_'))
            .toList();

        int deletedCount = 0;
        for (final file in thumbnailFiles) {
          try {
            if (await file.exists()) {
              await file.delete();
              deletedCount++;
            }
          } catch (e) {
            // Use throttled logging for individual file errors
            _logWithPathThrottle(
              'VideoThumbnail: Error deleting thumbnail file: $e',
              file.path,
            );
          }
        }
        _log('VideoThumbnail: Deleted $deletedCount physical thumbnail files.');

        if (_cacheIndexFilePath != null) {
          final indexFile = File(_cacheIndexFilePath!);
          if (await indexFile.exists()) {
            await indexFile.delete();
            _log('VideoThumbnail: Deleted cache index file.');
          }
        }
      } catch (e) {
        _log(
          'VideoThumbnail: Error clearing physical cache files: $e',
          forceShow: true,
        );
      }

      _lastCleanupTime = DateTime.now();
      _cacheInitialized = false;
      _userPrefsInitialized = false;
      _log('VideoThumbnail: Cache cleared completely.');

      // Notify listeners that cache has been cleared
      _notifyCacheChanged();
    } finally {
      // BUGFIX: Always reset to false so new requests can be processed.
      // Previously restored from wasProcessing which could leave the flag
      // permanently true if the queue was running when clearCache was called,
      // because _processQueue's finally block already set it to false but
      // this finally block would overwrite it back to true.
      _isProcessingQueue = false;
      _shouldStopProcessing = false;
    }
  }

  static Future<void> trimCache() async {
    _log('VideoThumbnail: Trimming cache...');
    if (_fileCache.length > _maxFileCacheSize / 2) {
      final keysToRemoveCount = _fileCache.length - (_maxFileCacheSize ~/ 2);
      final keysToRemove = _fileCache.keys.take(keysToRemoveCount).toList();

      int removedCount = 0;
      for (final key in keysToRemove) {
        _fileCache.remove(key);
        removedCount++;
      }

      _log(
        'VideoThumbnail: Trimmed in-memory cache, removed $removedCount items.',
      );
      _saveCacheToDiskThrottled();
    }

    await _cleanupOldTempFiles();
    _log('VideoThumbnail: Cache trimming complete.');
  }

  /// Proactively generate thumbnails for ALL video files in a directory
  /// Priority is based on list position - top items get highest priority
  /// This ensures thumbnails are generated even for off-screen items
  static Future<void> proactiveGenerateAll(
    List<String> videoPaths, {
    required String directoryPath,
  }) async {
    if (!_cacheInitialized) {
      await initializeCache();
    }

    if (videoPaths.isEmpty) return;

    _log(
      'VideoThumbnail: Proactively generating ${videoPaths.length} thumbnails for $directoryPath',
    );

    // Clear pending queue to prioritize new directory
    _pendingQueue.clear();

    // Add ALL videos to queue with decreasing priority based on position
    // Priority decreases by 1 for each position, ensuring top items are processed first
    for (var i = 0; i < videoPaths.length; i++) {
      final path = videoPaths[i];

      // Check if we're still in the same directory
      if (_currentDirectory != directoryPath) {
        _log(
          'VideoThumbnail: Directory changed, stopping proactive generation',
        );
        break;
      }

      // Calculate priority: first 20 items get visible priority,
      // next 40 get prefetch priority, rest get default priority
      // Within each group, earlier items get higher priority
      int priority;
      if (i < 20) {
        priority = _visiblePriority - i; // 100, 99, 98, ...
      } else if (i < 60) {
        priority = _prefetchPriority + (60 - i); // Decreasing from 60 to 21
      } else {
        priority = _defaultPriority; // 0 for all others
      }

      // Skip if already cached
      final cached = await getFromCache(path);
      if (cached != null) {
        continue;
      }

      _requestThumbnail(
        path,
        priority: priority,
        quality: thumbnailQuality,
        thumbnailSize: maxThumbnailSize,
      );

      // Small yield every 10 items to prevent blocking
      if (i % 10 == 9) {
        await Future.delayed(Duration.zero);
      }
    }

    _log(
      'VideoThumbnail: Queued ${_pendingQueue.length} thumbnails for generation',
    );
  }

  /// Tối ưu việc tải nhiều thumbnail cùng một lúc với hàng đợi ưu tiên
  static Future<void> optimizedBatchPreload(
    List<String> videoPaths, {
    int maxConcurrent = 2,
    int visibleCount = 10,
  }) async {
    if (!_cacheInitialized) {
      await initializeCache();
    }

    if (videoPaths.isEmpty) return;

    // Chia thành 3 nhóm ưu tiên:
    // 1. Nhóm hiển thị - tải ngay với ưu tiên cao
    // 2. Nhóm gần viewport - tải với ưu tiên trung bình
    // 3. Nhóm còn lại - tải với ưu tiên thấp

    final visiblePaths = videoPaths.take(visibleCount).toList();
    final nearPaths =
        videoPaths.skip(visibleCount).take(visibleCount * 2).toList();
    final otherPaths = videoPaths.skip(visibleCount * 3).toList();

    // Tạm dừng các yêu cầu đang chờ để xếp các yêu cầu mới
    _pendingQueue.clear();

    // Thêm vào queue với độ ưu tiên thích hợp
    for (final path in visiblePaths) {
      _requestThumbnail(
        path,
        priority: _visiblePriority,
        quality: 80,
        thumbnailSize: 240,
      );
    }

    // Delay trước khi thêm nhóm kế tiếp để tránh nghẽn
    await Future.delayed(const Duration(milliseconds: 100));

    for (final path in nearPaths) {
      _requestThumbnail(
        path,
        priority: _prefetchPriority,
        quality: 70,
        thumbnailSize: 180,
      );
    }

    // Delay dài hơn trước khi thêm nhóm cuối
    await Future.delayed(const Duration(milliseconds: 200));

    for (final path in otherPaths) {
      _requestThumbnail(
        path,
        priority: _defaultPriority,
        quality: 55,
        thumbnailSize: 140,
      );
    }
  }

  /// Hủy tất cả các yêu cầu đang chờ xử lý
  static void cancelPendingRequests() {
    _pendingQueue.clear();
  }

  /// Flag to mark a thumbnail as attempted for generation
  /// This prevents the need to retry generating already failed thumbnails
  static void markAttempted(String videoPath) {
    _attemptedPaths.add(_cacheKeyForPath(videoPath));
  }

  /// Check if a thumbnail generation was already attempted
  static bool wasAttempted(String videoPath) {
    return _attemptedPaths.contains(_cacheKeyForPath(videoPath));
  }

  /// Check if a video path is already queued (pending or processing)
  /// Used by widgets to avoid re-requesting with a different priority
  /// which would disrupt the sort-order based generation sequence
  static bool isPathQueued(String videoPath) {
    final cacheKey = _cacheKeyForPath(videoPath);
    return _pendingQueue.any((req) => req.videoPath == cacheKey) ||
        _processingQueue.any((req) => req.videoPath == cacheKey);
  }

  /// Restart thumbnail generation for items that come back into viewport
  static Future<String?> restartThumbnailRequest(String videoPath) async {
    final cacheKey = _cacheKeyForPath(videoPath);
    // Remove from attempted paths to allow regeneration
    _attemptedPaths.remove(cacheKey);

    // First try cache
    final cached = await getFromCache(videoPath);
    if (cached != null) {
      return cached;
    }

    // Request with high priority
    return _requestThumbnail(videoPath, priority: _visiblePriority);
  }

  /// Force regenerate a thumbnail even if it's already in cache
  /// Useful when a thumbnail was attempted but failed and needs to be retried
  static Future<String?> forceRegenerateThumbnail(String videoPath) async {
    return generateThumbnail(
      videoPath,
      forceRegenerate: true,
      isPriority: true,
    );
  }

  /// Regenerate thumbnails for all video files in the specified directory
  /// This is useful after clearing the cache to ensure thumbnails are regenerated
  static Future<void> regenerateThumbnailsForDirectory(
    String directoryPath,
  ) async {
    _log(
      'VideoThumbnail: Regenerating thumbnails for directory: $directoryPath',
      forceShow: true,
    );

    if (!_cacheInitialized) {
      await initializeCache();
    }

    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        _log(
          'VideoThumbnail: Directory does not exist: $directoryPath',
          forceShow: true,
        );
        return;
      }

      // Set as current directory
      setCurrentDirectory(directoryPath);

      // Get all video files in the directory
      final fileList = await directory.list().toList();
      final videoPaths = fileList
          .where(
            (entity) => entity is File && isSupportedVideoFormat(entity.path),
          )
          .map((entity) => entity.path)
          .toList();

      if (videoPaths.isEmpty) {
        _log(
          'VideoThumbnail: No video files found in directory',
          forceShow: true,
        );
        return;
      }

      _log(
        'VideoThumbnail: Found ${videoPaths.length} video files to regenerate thumbnails',
        forceShow: true,
      );

      // Clear the attempted paths to force regeneration
      for (final videoPath in videoPaths) {
        _attemptedPaths.remove(videoPath);
      }

      // Use the optimized batch preload with explicit forceRegenerate flag
      // First process the first 10 visible files with higher priority
      final visibleFiles = videoPaths.take(10).toList();
      final remainingFiles = videoPaths.skip(10).toList();

      // Process visible files first with higher priority
      for (final videoPath in visibleFiles) {
        await _requestThumbnail(
          videoPath,
          priority: _visiblePriority,
          forceRegenerate: true,
          quality: 85,
          thumbnailSize: 260,
        );

        // Small delay between each request to prevent system overload
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Then process remaining files with normal priority
      if (remainingFiles.isNotEmpty) {
        await optimizedBatchPreload(
          remainingFiles,
          maxConcurrent: 2,
          visibleCount: 20,
        );
      }

      _log(
        'VideoThumbnail: Regeneration queued for ${videoPaths.length} videos',
        forceShow: true,
      );

      // Notify listeners that cache has changed (thumbnails are being regenerated)
      _notifyCacheChanged();
    } catch (e) {
      _log(
        'VideoThumbnail: Error regenerating thumbnails: $e',
        forceShow: true,
      );
    }
  }

  /// Explicitly stop all thumbnail processing
  /// Call this method when navigating to a different folder or opening a file
  static void stopAllProcessing() {
    _log(
      'VideoThumbnail: Explicitly stopping all thumbnail processing',
      forceShow: true,
    );
    _shouldStopProcessing = true;

    // Clear the processing queue
    for (final request in _processingQueue) {
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
    }

    // Don't actually remove items from processing queue here
    // They'll be cleaned up naturally in the process queue loop

    // Wait a short time before allowing processing to continue
    // This helps prevent immediate restart of processing
    Future.delayed(const Duration(milliseconds: 100), () {
      _shouldStopProcessing = false;
    });
  }

  /// Check if thumbnail processing should stop
  /// This can be called from other classes to check if they should stop processing
  static bool shouldStopProcessing() {
    return _shouldStopProcessing;
  }

  /// Tìm thumbnail trong cache hoặc tạo mới nếu cần
  static Future<String?> getThumbnail(
    String videoPath, {
    bool forceRegenerate = false,
    bool isPriority = false,
    double? thumbnailPercentage,
    int? quality,
    int? thumbnailSize,
  }) async {
    if (!_cacheInitialized) {
      await initializeCache();
    }

    final cacheKey = _cacheKeyForPath(videoPath);
    if (cacheKey.isEmpty || !await File(cacheKey).exists()) {
      _logWithPathThrottle(
        'VideoThumbnail: Invalid video path: $cacheKey',
        cacheKey,
      );
      return null;
    }

    // Check in memory cache first for faster response
    if (!forceRegenerate && _inMemoryPathCache.containsKey(cacheKey)) {
      final cachedPath = _inMemoryPathCache[cacheKey];
      if (cachedPath != null) {
        final cacheFile = File(cachedPath);
        if (await cacheFile.exists()) {
          _logWithPathThrottle(
            'VideoThumbnail: Using in-memory cached thumbnail for $cacheKey',
            cacheKey,
          );
          return cachedPath;
        } else {
          // Remove invalid cache entry
          _inMemoryPathCache.remove(cacheKey);
        }
      }
    }

    // Next check permanent file cache
    if (!forceRegenerate) {
      final cachedPath = await getFromCache(videoPath);
      if (cachedPath != null) {
        _logWithPathThrottle(
          'VideoThumbnail: Using file-cached thumbnail for $cacheKey',
          cacheKey,
        );
        // Also update in-memory cache
        _inMemoryPathCache[cacheKey] = cachedPath;
        return cachedPath;
      }
    }

    // No valid cache entry, generate a new thumbnail
    _logWithPathThrottle(
      'VideoThumbnail: No cache found or regenerate requested for $cacheKey',
      cacheKey,
    );
    // Note: thumbnailPercentage is stored globally but not used directly in generateThumbnail
    return generateThumbnail(
      videoPath,
      forceRegenerate: forceRegenerate,
      isPriority: isPriority,
      quality: quality,
      thumbnailSize: thumbnailSize,
    );
  }

  /// Get the cache directory path where thumbnails are stored
  static Future<String?> getCacheDirectoryPath() async {
    try {
      final dir = await AppPathHelper.getVideoCacheDir();
      return dir.path;
    } catch (e) {
      debugPrint('VideoThumbnail: Error getting cache directory path: $e');
      return null;
    }
  }
}

class _ThumbnailRequest {
  final String videoPath;
  int priority;
  final Completer<String?> completer;
  final DateTime timestamp;
  final bool forceRegenerate;
  final int? quality;
  final int? thumbnailSize;

  _ThumbnailRequest.empty()
      : videoPath = '',
        priority = -1,
        completer = Completer<String?>(),
        timestamp = DateTime(0),
        forceRegenerate = false,
        quality = null,
        thumbnailSize = null;

  _ThumbnailRequest({
    required this.videoPath,
    required this.priority,
    required this.completer,
    required this.timestamp,
    required this.forceRegenerate,
    this.quality,
    this.thumbnailSize,
  });
}
