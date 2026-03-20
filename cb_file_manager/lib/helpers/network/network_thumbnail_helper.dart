import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:cb_file_manager/services/network_browsing/network_service_base.dart';
import 'package:cb_file_manager/services/network_browsing/network_service_registry.dart';
import 'package:cb_file_manager/services/network_browsing/smb_service.dart';
import 'package:cb_file_manager/services/network_browsing/mobile_smb_service.dart';
import 'package:cb_file_manager/services/streaming/smb_http_proxy_server.dart';
import 'package:cb_file_manager/ui/state/video_ui_state.dart';
import 'package:image/image.dart' as img;
import 'win32_smb_helper.dart';
import 'smb_native_thumbnail_helper.dart';
import 'network_file_cache_service.dart';
import '../core/path_utils.dart';
import '../core/app_path_helper.dart';

/// Exception thrown when thumbnail generation is skipped due to backoff
class ThumbnailSkippedException implements Exception {
  final String message;
  ThumbnailSkippedException(this.message);

  @override
  String toString() => 'ThumbnailSkippedException: $message';
}

/// Helper class for generating thumbnails for network files
// Helper class for queued thumbnail requests
class _QueuedThumbnailRequest {
  final String path;
  final String key;
  final int size;
  final bool isSmb;
  final Completer<String?> completer;

  _QueuedThumbnailRequest(this.path, this.key, this.size, this.isSmb)
      : completer = Completer<String?>();
}

class NetworkThumbnailHelper {
  static final NetworkThumbnailHelper _instance =
      NetworkThumbnailHelper._internal();
  factory NetworkThumbnailHelper() => _instance;
  NetworkThumbnailHelper._internal() {
    _initializeCacheDirectory();
  }

  // Cache service
  final NetworkFileCacheService _cacheService = NetworkFileCacheService();

  // SMB helper for Windows
  final Win32SmbHelper _win32SmbHelper = Win32SmbHelper();

  /// Cache for network thumbnails to avoid re-downloading
  final Map<String, String> _thumbnailPathCache = {};

  /// Cache for failed thumbnail attempts to avoid retrying repeatedly
  static final Map<String, DateTime> _failedAttempts = {};
  static const Duration _retryInterval = Duration(minutes: 5);

  /// Pending thumbnail requests to avoid duplicates
  final Map<String, Future<String?>> _pendingRequests = {};

  // Limit concurrent thumbnail generation (optimized for UI responsiveness)
  static int _activeRequests = 0;
  static const int _maxConcurrentRequests = 1; // Giảm xuống 1 khi scroll nhanh

  // Debouncing for rapid requests (tăng delay khi scroll)
  static final Map<String, Timer> _debounceTimers = {};
  static Duration _debounceDelay = const Duration(
    milliseconds: 200,
  ); // Tăng delay mặc định

  // Scroll detection (we only track whether scrolling is active)
  static bool _isScrolling = false;
  static Timer? _scrollTimer;

  // Queue for pending thumbnail requests
  static final List<_QueuedThumbnailRequest> _requestQueue = [];

  // Maximum queue size to prevent memory issues
  static const int _maxQueueSize = 50; // Giảm xuống để tránh memory pressure

  // Cache directory management
  static Directory? _cacheDirectory;

  // Cache cleanup settings
  static const int _maxCacheFiles = 500;
  static const int _maxCacheSizeMB = 100;
  static const Duration _maxCacheAge = Duration(days: 7);

  // Cleanup tracking
  static DateTime? _lastCleanup;
  static const Duration _cleanupInterval = Duration(hours: 6);

  // Biến đếm để theo dõi và dọn dẹp
  static int _processedCount = 0;
  static const int _cleanupThreshold = 40;

  // Thêm chức năng theo dõi thumbnail ưu tiên
  static final Set<String> _visiblePaths = {};
  static final Set<String> _cancelledPaths = {};

  // Keep track of processing isolates for cancellation
  static final Map<String, SendPort?> _isolatePorts = {};

  /// Đánh dấu thumbnail đang hiển thị (ưu tiên cao)
  void markVisible(String path) {
    _visiblePaths.add(path);

    // Update scroll detection
    _updateScrollState();

    // Di chuyển các request đang hiển thị lên đầu queue
    if (_requestQueue.isNotEmpty) {
      final idx = _requestQueue.indexWhere((req) => req.path == path);
      if (idx > 0) {
        final req = _requestQueue.removeAt(idx);
        _requestQueue.insert(0, req);
        // debugPrint('Đã di chuyển request cho $path lên đầu hàng đợi');
      }
    }
  }

  /// Update scroll state and adjust performance accordingly
  void _updateScrollState() {
    _scrollTimer?.cancel();

    if (!_isScrolling) {
      _isScrolling = true;
      // Increase debounce delay during scroll
      _debounceDelay = const Duration(milliseconds: 500);
      // debugPrint('Scroll detected - increasing debounce delay and reducing concurrency');
    }

    // Set timer to detect when scrolling stops
    _scrollTimer = Timer(const Duration(milliseconds: 300), () {
      _isScrolling = false;
      // Restore normal debounce delay
      _debounceDelay = const Duration(milliseconds: 150);
      // debugPrint('Scroll stopped - restoring normal performance settings');

      // Process queued requests now that scrolling stopped
      _processNextQueuedRequest();
    });
  }

  /// Đánh dấu thumbnail không còn hiển thị
  void markInvisible(String path) {
    _visiblePaths.remove(path);

    // Cancel any pending/processing requests for this path
    _cancelPath(path);
  }

  /// Cancel processing for a specific path
  void _cancelPath(String path) {
    _cancelledPaths.add(path);

    // Cancel debounce timers for all sizes of this path.
    final prefix = '$path:';
    final debounceKeys =
        _debounceTimers.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in debounceKeys) {
      _debounceTimers[key]?.cancel();
      _debounceTimers.remove(key);
    }

    // Remove from queue
    _requestQueue.removeWhere((request) {
      if (request.path == path) {
        if (!request.completer.isCompleted) {
          request.completer.complete(null);
        }
        return true;
      }
      return false;
    });

    // Cancel isolate if running
    final isolatePort = _isolatePorts[path];
    if (isolatePort != null) {
      try {
        isolatePort.send({'action': 'cancel'});
      } catch (e) {
        debugPrint('Error cancelling isolate for $path: $e');
      }
      _isolatePorts.remove(path);
    }

    // debugPrint('Cancelled thumbnail processing for invisible path: $path');
  }

  /// Cancel all in-flight and queued thumbnail work.
  ///
  /// This is useful when navigating away from a folder, especially on SMB where
  /// concurrent background thumbnail work can interfere with directory listing.
  void cancelAllRequests() {
    // Mark all currently visible paths as cancelled.
    final pathsToCancel = Set<String>.from(_visiblePaths);
    for (final p in pathsToCancel) {
      _cancelPath(p);
    }
    _visiblePaths.clear();

    // Cancel any remaining debounce timers (defensive).
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();

    // Clear any remaining queued requests (defensive).
    for (final request in _requestQueue) {
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
    }
    _requestQueue.clear();
  }

  /// Initialize cache directory
  Future<void> _initializeCacheDirectory() async {
    try {
      if (_cacheDirectory == null) {
        // Luôn bảo đảm cache nằm trong <root>/network_thumbnails
        final desiredDir = await AppPathHelper.getNetworkCacheDir();

        // Nếu _cacheDirectory đã được tạo trước đó ở nơi khác, di chuyển/mig về đúng chỗ
        if (_cacheDirectory != null &&
            _cacheDirectory!.path != desiredDir.path) {
          try {
            // Move existing files
            if (await _cacheDirectory!.exists()) {
              final files = await _cacheDirectory!.list().toList();
              for (final entity in files) {
                if (entity is File) {
                  final newPath = p.join(
                    desiredDir.path,
                    p.basename(entity.path),
                  );
                  await entity.rename(newPath);
                }
              }
              // Delete old empty dir
              await _cacheDirectory!.delete(recursive: true);
            }
          } catch (e) {
            debugPrint('Error migrating old SMB cache dir: $e');
          }
        }

        _cacheDirectory = desiredDir;

        if (!await _cacheDirectory!.exists()) {
          await _cacheDirectory!.create(recursive: true);
          debugPrint(
            'Created SMB thumbnail cache directory: ${_cacheDirectory!.path}',
          );
        }

        // Perform initial cleanup
        await _performCacheCleanup();
      }
    } catch (e) {
      debugPrint('Error initializing cache directory: $e');
    }
  }

  /// Perform cache cleanup based on age, size, and file count
  Future<void> _performCacheCleanup() async {
    try {
      if (_cacheDirectory == null || !await _cacheDirectory!.exists()) {
        return;
      }

      final now = DateTime.now();

      // Check if we need to cleanup
      if (_lastCleanup != null &&
          now.difference(_lastCleanup!) < _cleanupInterval) {
        return;
      }

      _lastCleanup = now;

      debugPrint('Starting cache cleanup...');

      final files = await _cacheDirectory!.list().toList();
      final thumbnailFiles = files.whereType<File>().cast<File>().toList();

      if (thumbnailFiles.isEmpty) {
        debugPrint('No files to cleanup');
        return;
      }

      // Sort files by last modified time (oldest first)
      thumbnailFiles.sort((a, b) {
        final aTime = a.lastModifiedSync();
        final bTime = b.lastModifiedSync();
        return aTime.compareTo(bTime);
      });

      int deletedCount = 0;
      int totalSize = 0;

      // Step 1: Delete files older than maxCacheAge
      for (final file in thumbnailFiles) {
        try {
          final fileTime = file.lastModifiedSync();
          if (now.difference(fileTime) > _maxCacheAge) {
            await file.delete();
            deletedCount++;
            debugPrint('Deleted old file: ${p.basename(file.path)}');
          } else {
            final size = await file.length();
            totalSize += size;
          }
        } catch (e) {
          debugPrint('Error checking file age: $e');
        }
      }

      // Step 2: Check remaining files after age-based cleanup
      final remainingFiles = await _cacheDirectory!
          .list()
          .where((f) => f is File)
          .cast<File>()
          .toList();

      // Step 3: Delete files if count exceeds limit
      if (remainingFiles.length > _maxCacheFiles) {
        final filesToDelete = remainingFiles.length - _maxCacheFiles;
        for (int i = 0; i < filesToDelete; i++) {
          try {
            await remainingFiles[i].delete();
            deletedCount++;
            debugPrint(
              'Deleted excess file: ${p.basename(remainingFiles[i].path)}',
            );
          } catch (e) {
            debugPrint('Error deleting excess file: $e');
          }
        }
      }

      // Step 4: Check total size and delete oldest files if needed
      if (totalSize > _maxCacheSizeMB * 1024 * 1024) {
        final finalFiles = await _cacheDirectory!
            .list()
            .where((f) => f is File)
            .cast<File>()
            .toList();

        finalFiles.sort((a, b) {
          final aTime = a.lastModifiedSync();
          final bTime = b.lastModifiedSync();
          return aTime.compareTo(bTime);
        });

        int currentSize = 0;
        for (final file in finalFiles) {
          try {
            final size = await file.length();
            currentSize += size;
          } catch (e) {
            // debugPrint('Error getting file size: $e');
          }
        }

        const targetSize = _maxCacheSizeMB * 1024 * 1024;
        for (final file in finalFiles) {
          if (currentSize <= targetSize) break;

          try {
            final size = await file.length();
            await file.delete();
            currentSize -= size;
            deletedCount++;
            debugPrint('Deleted oversized file: ${p.basename(file.path)}');
          } catch (e) {
            debugPrint('Error deleting oversized file: $e');
          }
        }
      }

      debugPrint('Cache cleanup completed. Deleted $deletedCount files');
    } catch (e) {
      debugPrint('Error during cache cleanup: $e');
    }
  }

  /// Get thumbnail file path in cache directory
  String _getThumbnailFilePath(String networkFilePath, int size) {
    if (_cacheDirectory == null) {
      throw StateError('Cache directory not initialized');
    }

    // Làm sạch đường dẫn trước
    final sanitizedPath = sanitizePath(networkFilePath);

    // Create a safe filename from the network path
    final fileName =
        p.basename(sanitizedPath).replaceAll(RegExp(r'[<>:"/\\|?*%]'), '_');

    // Create a unique identifier for the path to avoid collisions
    final pathHash = sanitizedPath.hashCode.abs().toString();

    return p.join(
      _cacheDirectory!.path,
      'thumb_${pathHash}_${fileName}_$size.png',
    );
  }

  /// Generate a thumbnail for a network file path
  ///
  /// Returns the local path to the generated thumbnail or null if generation failed
  Future<String?> generateThumbnail(
    String networkFilePath, {
    int size = 128,
  }) async {
    final requestKey = '$networkFilePath:$size';

    // Remove from cancelled paths if was cancelled before
    _cancelledPaths.remove(networkFilePath);

    // Đánh dấu path này là đang hiển thị (ưu tiên cao)
    markVisible(networkFilePath);

    // Check if this specific thumbnail was recently attempted and failed
    final lastFailed = _failedAttempts[requestKey];
    if (lastFailed != null) {
      final durationSinceLast = DateTime.now().difference(lastFailed);

      // Count failed attempts for this specific file in the last hour
      final filePrefix = networkFilePath;
      final retryCount = _failedAttempts.entries
          .where(
            (entry) =>
                entry.key.startsWith(filePrefix) &&
                entry.value.isAfter(
                  DateTime.now().subtract(const Duration(hours: 1)),
                ),
          )
          .length;

      // Progressive backoff: 2min, 5min, 10min, 20min, then 30min max
      final backoffMinutes = retryCount <= 1
          ? 2
          : retryCount == 2
              ? 5
              : retryCount == 3
                  ? 10
                  : retryCount == 4
                      ? 20
                      : 30;
      final backoffDelay = Duration(minutes: backoffMinutes);

      if (durationSinceLast < backoffDelay) {
        // Skip if failed within backoff period
        debugPrint(
          'Skipping thumbnail generation for $networkFilePath (failed $retryCount times, backoff ${backoffMinutes}min)',
        );
        // Return a special marker to indicate skip due to backoff
        throw ThumbnailSkippedException(
          'Skipped due to backoff: $networkFilePath',
        );
      }
    }

    // Debounce rapid requests to prevent UI lag
    final existingTimer = _debounceTimers[requestKey];
    if (existingTimer != null) {
      existingTimer.cancel();
    }

    final completer = Completer<String?>();
    _debounceTimers[requestKey] = Timer(_debounceDelay, () async {
      _debounceTimers.remove(requestKey);

      // Check if still visible after debounce
      if (!_visiblePaths.contains(networkFilePath)) {
        completer.complete(null);
        return;
      }

      // During scrolling, further delay the actual generation
      if (_isScrolling) {
        // Re-debounce with longer delay during scroll
        _debounceTimers[requestKey] = Timer(
          const Duration(milliseconds: 800),
          () async {
            _debounceTimers.remove(requestKey);
            if (_visiblePaths.contains(networkFilePath) && !_isScrolling) {
              final result = await _actuallyGenerateThumbnail(
                networkFilePath,
                size,
              );
              completer.complete(result);
            } else {
              completer.complete(null);
            }
          },
        );
        return;
      }

      final result = await _actuallyGenerateThumbnail(networkFilePath, size);
      completer.complete(result);
    });

    return completer.future;
  }

  /// Actually generate the thumbnail (called after debouncing)
  Future<String?> _actuallyGenerateThumbnail(
    String networkFilePath,
    int size,
  ) async {
    final requestKey = '$networkFilePath:$size';

    // Avoid expensive thumbnail work while a video player is active.
    // On Android this can contend for IO/CPU and cause playback stutter.
    if (Platform.isAndroid && VideoUiState.isPlayerActive.value) {
      return null;
    }

    // Check if request is already pending
    if (_pendingRequests.containsKey(requestKey)) {
      return _pendingRequests[requestKey];
    }

    // Ensure cache directory is initialized
    await _initializeCacheDirectory();

    // Check if we already have a cached thumbnail in our cache directory
    try {
      final thumbnailPath = _getThumbnailFilePath(networkFilePath, size);
      if (File(thumbnailPath).existsSync()) {
        _thumbnailPathCache[networkFilePath] = thumbnailPath;
        return thumbnailPath;
      }
    } catch (e) {
      debugPrint('Error checking cached thumbnail: $e');
    }

    // Check if this is a recent failed attempt
    if (_failedAttempts.containsKey(requestKey)) {
      final failedTime = _failedAttempts[requestKey]!;
      if (DateTime.now().difference(failedTime) < _retryInterval) {
        debugPrint('Skipping recently failed thumbnail: $networkFilePath');
        return null;
      }
      // Reset failed attempt if retry interval has passed
      _failedAttempts.remove(requestKey);
    }

    // Dynamic concurrent request limit based on scroll state
    final effectiveMaxRequests = _isScrolling ? 0 : _maxConcurrentRequests;

    // Limit concurrent requests
    if (_activeRequests >= effectiveMaxRequests) {
      // During scrolling, drop non-visible requests immediately
      if (_isScrolling && !_visiblePaths.contains(networkFilePath)) {
        // debugPrint('Dropping non-visible thumbnail request during scroll: $networkFilePath');
        return null;
      }

      // Check if queue is full
      if (_requestQueue.length >= _maxQueueSize) {
        // Remove oldest non-visible requests to make space
        _requestQueue.removeWhere((req) {
          if (!_visiblePaths.contains(req.path)) {
            if (!req.completer.isCompleted) {
              req.completer.complete(null);
            }
            return true;
          }
          return false;
        });

        // If still full, drop this request
        if (_requestQueue.length >= _maxQueueSize) {
          // debugPrint('Thumbnail queue full, dropping request for: $networkFilePath');
          return null;
        }
      }

      // Không bỏ qua yêu cầu – chỉ cần xếp vào hàng đợi, hệ thống sẽ xử lý dần
      final isSmbFile = networkFilePath.toLowerCase().startsWith(
            '#network/smb/'.toLowerCase(),
          );
      final request = _QueuedThumbnailRequest(
        networkFilePath,
        requestKey,
        size,
        isSmbFile,
      );

      // Add to queue with smart insertion (visible paths first)
      if (_visiblePaths.contains(networkFilePath)) {
        _requestQueue.insert(0, request); // Priority insertion
      } else {
        // During scroll, don't queue non-visible items
        if (_isScrolling) {
          request.completer.complete(null);
          return request.completer.future;
        }
        _requestQueue.add(request); // Normal insertion
      }

      // Return a future that will complete when this request is processed
      return request.completer.future;
    }

    _activeRequests++;

    try {
      // For SMB files (case-insensitive check for convenience)
      if (networkFilePath.toLowerCase().startsWith(
            '#network/smb/'.toLowerCase(),
          )) {
        // Store the future to prevent duplicate requests
        final timeout = (Platform.isAndroid || Platform.isIOS)
            ? const Duration(seconds: 6)
            : const Duration(seconds: 3);
        final future = _generateSMBThumbnail(networkFilePath, size).timeout(
          timeout,
          onTimeout: () => null,
        ); // Shorter timeout
        _pendingRequests[requestKey] = future;

        // Clean up pending request when done
        future.whenComplete(() {
          _pendingRequests.remove(requestKey);
          _activeRequests--; // Decrement active requests
          _isolatePorts.remove(networkFilePath); // Clean up isolate tracking

          // Tăng bộ đếm và dọn dẹp nếu cần
          _processedCount++;
          if (_processedCount >= _cleanupThreshold) {
            _cleanupResources();
          }

          // Process next request in queue if any - schedule on next frame
          scheduleMicrotask(_processNextQueuedRequest);
        });

        return future;
      }

      // For other network protocols (not implemented yet)
      _activeRequests--;
      _processNextQueuedRequest();
      return null;
    } catch (e) {
      _activeRequests--;
      _processNextQueuedRequest();
      return null;
    }
  }

  /// Generate a thumbnail for an SMB file
  Future<String?> _generateSMBThumbnail(String smbFilePath, int size) async {
    // Early cancellation check
    if (_cancelledPaths.contains(smbFilePath) ||
        !_visiblePaths.contains(smbFilePath)) {
      // debugPrint('Cancelled SMB thumbnail generation for: $smbFilePath');
      return null;
    }

    // debugPrint('Generating SMB thumbnail for: $smbFilePath (size: $size)');
    try {
      // Get the appropriate service for this path
      final registry = NetworkServiceRegistry();
      final service = registry.getServiceForPath(smbFilePath);

      // debugPrint(
      //   'Service for path $smbFilePath: ${service?.runtimeType} - ${service?.toString()}',
      // );

      if (service is SMBService || service is MobileSMBService) {
        // debugPrint('Using SMB service for thumbnail generation');

        // Check file type
        final isVideo = _cacheService.isVideoFile(smbFilePath);
        final isImage = _cacheService.isImageFile(smbFilePath);

        if (!isVideo && !isImage) {
          // debugPrint('Unsupported file type for thumbnail: $smbFilePath');
          return null;
        }

        // 1) Direct SMB native thumbnail (fastest & best quality)
        if (Platform.isWindows) {
          final unc = smbTabPathToUNC(smbFilePath);
          try {
            final thumbnailData =
                await SmbNativeThumbnailHelper.generateThumbnailDirect(
              filePath: unc,
              thumbnailSize: size,
              useFastMode: false, // Use high quality mode
            ).timeout(const Duration(seconds: 2), onTimeout: () => null);

            if (thumbnailData != null && thumbnailData.isNotEmpty) {
              return await _saveThumbnailToFile(
                smbFilePath,
                thumbnailData,
                size,
              );
            }
          } catch (e) {
            // debugPrint('Direct SMB native thumbnail failed: $e');
          }
        }

        // 2) Fallback: SMBService/MobileSMBService thumbnail (via native methods)
        if (service is SMBService || service is MobileSMBService) {
          try {
            final bytes = await service
                ?.getThumbnail(smbFilePath, size)
                .timeout(const Duration(seconds: 5), onTimeout: () => null);
            if (bytes != null && bytes.isNotEmpty) {
              return await _saveThumbnailToFile(smbFilePath, bytes, size);
            }
          } catch (e) {
            // debugPrint('Service thumbnail generation failed: $e');
          }
        }

        // On mobile, avoid VideoThumbnail/MediaMetadataRetriever-based fallbacks for SMB videos.
        // Those can block the Android main thread and make navigation/back unresponsive.
        if ((Platform.isAndroid || Platform.isIOS) && isVideo) {
          _failedAttempts['$smbFilePath:$size'] = DateTime.now();
          return null;
        }

        // 3) Fallback: Win32 helper (last resort, Windows only)
        if (Platform.isWindows) {
          final unc = smbTabPathToUNC(smbFilePath);
          final thumbnailData = await _generateWindowsNativeThumbnail(
            unc,
            size,
            isVideo,
          );
          if (thumbnailData != null) {
            return await _saveThumbnailToFile(smbFilePath, thumbnailData, size);
          }
        }

        // 3b) Mobile SMB image: stream bytes and generate a thumbnail in an isolate.
        if ((Platform.isAndroid || Platform.isIOS) && isImage) {
          try {
            final bytes = await _generateMobileSmbImageThumbnailBytes(
              service: service,
              smbTabPath: smbFilePath,
              size: size,
            );
            if (bytes != null && bytes.isNotEmpty) {
              return await _saveThumbnailToFile(smbFilePath, bytes, size);
            }
          } catch (_) {
            // Ignore: thumbnail fallback is best-effort.
          }
        }

        // 4) Nếu tất cả native methods thất bại, ghi nhận thất bại và trả null.
        // debugPrint('All thumbnail generation methods failed for: $smbFilePath');
        _failedAttempts['$smbFilePath:$size'] = DateTime.now();
        return null;
      } else {
        debugPrint('No SMB service available for: $smbFilePath');
        _failedAttempts['$smbFilePath:$size'] = DateTime.now();
      }
    } catch (e) {
      debugPrint('Error generating SMB thumbnail: $e');
      // Ghi nhận thất bại ở đây thay vì trong hàm con
      _failedAttempts['$smbFilePath:$size'] = DateTime.now();
    }

    return null;
  }

  Future<Uint8List?> _generateMobileSmbVideoThumbnailBytes({
    required NetworkServiceBase? service,
    required String smbTabPath,
    required int size,
  }) async {
    final smbUrl = await _tryResolveSmbUrlForProxy(service, smbTabPath);
    if (smbUrl == null || smbUrl.isEmpty) {
      return null;
    }

    final httpUrl = await SmbHttpProxyServer.instance.urlFor(smbUrl);

    return await VideoThumbnail.thumbnailData(
      video: httpUrl.toString(),
      imageFormat: ImageFormat.PNG,
      maxWidth: size,
      maxHeight: size,
      quality: 100,
      timeMs: 1000,
    );
  }

  Future<Uint8List?> _generateMobileSmbImageThumbnailBytes({
    required NetworkServiceBase? service,
    required String smbTabPath,
    required int size,
  }) async {
    final stream = service?.openFileStream(smbTabPath);
    if (stream == null) return null;

    final bytes = BytesBuilder(copy: false);
    int total = 0;
    const limit = 20 * 1024 * 1024;

    await for (final chunk in stream) {
      if (_cancelledPaths.contains(smbTabPath) ||
          !_visiblePaths.contains(smbTabPath)) {
        break;
      }

      bytes.add(chunk);
      total += chunk.length;
      if (total >= limit) break;
    }

    final data = bytes.takeBytes();
    if (data.isEmpty) return null;

    return compute(_generateImageThumbnailBytes, {
      'bytes': data,
      'size': size,
    });
  }

  Future<String?> _tryResolveSmbUrlForProxy(
    NetworkServiceBase? service,
    String smbTabPath,
  ) async {
    try {
      if (service is MobileSMBService) {
        return await service.getSmbDirectLink(smbTabPath);
      }
    } catch (_) {}

    // Best-effort fallback: build an unauthenticated SMB URL from the tab path.
    final parts = smbTabPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 4) return null;
    final scheme = parts[1].toLowerCase();
    if (scheme != 'smb') return null;

    final host = Uri.decodeComponent(parts[2]);
    final share = Uri.decodeComponent(parts[3]);
    final remaining = parts.length > 4
        ? parts.sublist(4).map(Uri.decodeComponent).toList()
        : <String>[];
    final encodedPath =
        [share, ...remaining].map(Uri.encodeComponent).join('/');
    return 'smb://$host/$encodedPath';
  }

  static int _mobileVideoPrefixLimitBytes(String smbTabPath) {
    final ext = p.extension(smbTabPath).toLowerCase();
    if (ext == '.mp4' || ext == '.m4v' || ext == '.mov') {
      return 12 * 1024 * 1024;
    }
    return 6 * 1024 * 1024;
  }

  static bool _isFastStartMp4Candidate(String smbTabPath) {
    final ext = p.extension(smbTabPath).toLowerCase();
    return ext == '.mp4' || ext == '.m4v' || ext == '.mov';
  }

  static bool _containsMoovAtom(
    List<int> last3,
    List<int> chunk, {
    required void Function(List<int>) outLast3,
  }) {
    const moov = [0x6D, 0x6F, 0x6F, 0x76]; // "moov"
    final combined = <int>[]
      ..addAll(last3)
      ..addAll(chunk);

    for (var i = 0; i + 3 < combined.length; i++) {
      if (combined[i] == moov[0] &&
          combined[i + 1] == moov[1] &&
          combined[i + 2] == moov[2] &&
          combined[i + 3] == moov[3]) {
        outLast3(_lastN([...last3, ...chunk], 3));
        return true;
      }
    }

    outLast3(_lastN([...last3, ...chunk], 3));
    return false;
  }

  static List<int> _lastN(List<int> data, int n) {
    if (n <= 0) return const <int>[];
    if (data.length <= n) return List<int>.from(data);
    return data.sublist(data.length - n);
  }

  /// Generate thumbnails using Windows native APIs (much faster)
  Future<Uint8List?> _generateWindowsNativeThumbnail(
    String path,
    int size,
    bool isVideo,
  ) async {
    try {
      if (isVideo) {
        // Use direct Win32 helper for video thumbnails
        return await _win32SmbHelper.generateVideoThumbnail(path, size);
      } else {
        // Use direct Win32 helper for image thumbnails
        return await _win32SmbHelper.generateImageThumbnail(path, size);
      }
    } catch (e) {
      debugPrint('Error in Windows native thumbnail: $e');
      return null;
    }
  }

  // Xoá hoàn toàn _generateVideoThumbnail fallback – không dùng nữa.

  // Top-level worker function for image thumbnail generation in an isolate.
  // It reads the source image [sourcePath], creates a resized & enhanced
  // thumbnail, writes it to [targetPath] and returns the path on success or
  // null on failure.
  @pragma('vm:entry-point')
  static Future<String?> _imageThumbnailIsolate(
    Map<String, dynamic> params,
  ) async {
    final String sourcePath = params['sourcePath'] as String;
    final String targetPath = params['targetPath'] as String;
    final int size = params['size'] as int;

    try {
      final bytes = await File(sourcePath).readAsBytes();

      // Validate image data before decoding
      if (bytes.isEmpty) {
        debugPrint(
            'NetworkThumbnail (Isolate): Empty image data for $sourcePath');
        return null;
      }

      if (bytes.length < 100) {
        debugPrint(
            'NetworkThumbnail (Isolate): Image data too small (${bytes.length} bytes) for $sourcePath');
        return null;
      }

      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint(
            'NetworkThumbnail (Isolate): Failed to decode image data (${bytes.length} bytes) for $sourcePath - invalid image data');
        return null;
      }

      final double aspectRatio = decoded.width / decoded.height;
      int thumbW, thumbH;
      if (aspectRatio > 1) {
        thumbW = size;
        thumbH = (size / aspectRatio).round();
      } else {
        thumbH = size;
        thumbW = (size * aspectRatio).round();
      }
      thumbW = thumbW.clamp(1, size);
      thumbH = thumbH.clamp(1, size);

      img.Image thumb = img.copyResize(
        decoded,
        width: thumbW,
        height: thumbH,
        interpolation: img.Interpolation.average,
      );

      // Light enhancements for better perceived quality
      thumb = img.adjustColor(
        thumb,
        contrast: 1.05,
        saturation: 1.1,
        brightness: 1.02,
      );

      if (thumb.width <= 256 && thumb.height <= 256) {
        try {
          thumb = img.convolution(
            thumb,
            filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
            div: 1,
          );
        } catch (_) {
          // Ignore convolution errors
        }
      }

      final Uint8List encoded = Uint8List.fromList(
        img.encodePng(thumb, level: 6),
      );
      await File(targetPath).writeAsBytes(encoded);
      return targetPath;
    } catch (_) {
      return null;
    }
  }

  /// Save thumbnail data to file and return path
  Future<String?> _saveThumbnailToFile(
    String smbFilePath,
    Uint8List thumbnailData,
    int size,
  ) async {
    try {
      if (thumbnailData.isEmpty) {
        debugPrint('Thumbnail data is empty for $smbFilePath');
        return null;
      }

      // Ensure cache directory is initialized
      await _initializeCacheDirectory();

      // Save to our dedicated cache directory
      final thumbnailPath = _getThumbnailFilePath(smbFilePath, size);
      final file = File(thumbnailPath);

      try {
        // Create parent directory if it doesn't exist
        await file.parent.create(recursive: true);

        // Write the thumbnail data to a file
        await file.writeAsBytes(thumbnailData);

        if (await file.exists() && await file.length() > 0) {
          // debugPrint('Successfully created thumbnail at: $thumbnailPath');
          _thumbnailPathCache[smbFilePath] = thumbnailPath;
          return thumbnailPath;
        } else {
          // debugPrint('Created thumbnail file is empty or missing: $thumbnailPath');
          return null;
        }
      } catch (e) {
        debugPrint('Error writing thumbnail file: $e');

        // Thử xóa file cũ nếu có lỗi
        try {
          if (await file.exists()) {
            await file.delete();
            debugPrint('Deleted corrupted thumbnail file: $thumbnailPath');
          }
        } catch (deleteError) {
          debugPrint('Error deleting corrupted thumbnail: $deleteError');
        }

        return null;
      }
    } catch (e) {
      debugPrint('Error saving thumbnail to file: $e');
      return null;
    }
  }

  /// Clear the thumbnail cache
  Future<void> clearCache() async {
    try {
      // Clean up our cache directory
      if (_cacheDirectory != null && await _cacheDirectory!.exists()) {
        try {
          await _cacheDirectory!.delete(recursive: true);
        } catch (e) {
          debugPrint('Error deleting cache directory: $e');
        }
        await _cacheDirectory!.create(recursive: true);
        // debugPrint('Cleared SMB thumbnail cache directory');
      }
    } catch (e) {
      debugPrint('Error clearing cache directory: $e');
    }

    _thumbnailPathCache.clear();
    _pendingRequests.clear();
    _failedAttempts.clear();
    // debugPrint('NetworkThumbnailHelper: Cleared all caches and failed attempts');

    // Clear the queue
    for (final request in _requestQueue) {
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
    }
    _requestQueue.clear();

    // Reset active requests counter
    _activeRequests = 0;
    _processedCount = 0;

    // Reset cleanup tracking
    _lastCleanup = null;
  }

  /// Clear cache and force regenerate thumbnails for debugging
  static Future<void> clearCacheAndForceRegenerate() async {
    // debugPrint('NetworkThumbnailHelper: Force clearing cache and regenerating thumbnails...');
    final instance = NetworkThumbnailHelper();
    await instance.clearCache();
    // debugPrint('NetworkThumbnailHelper: Cache cleared, thumbnails will be regenerated on next request');
  }

  /// Reset failed attempts tracking (useful when network connection changes)
  static void resetFailedAttempts() {
    _failedAttempts.clear();
  }

  /// Get cache directory path for debugging
  Future<String?> getCacheDirectoryPath() async {
    if (_cacheDirectory == null) {
      await _initializeCacheDirectory();
    }
    return _cacheDirectory?.path;
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      if (_cacheDirectory == null || !await _cacheDirectory!.exists()) {
        return {'exists': false, 'fileCount': 0, 'totalSize': 0, 'path': null};
      }

      final files = await _cacheDirectory!
          .list(recursive: true, followLinks: false)
          .where((f) => f is File)
          .cast<File>()
          .toList();
      int totalSize = 0;

      for (final file in files) {
        try {
          totalSize += await file.length();
        } catch (e) {
          // debugPrint('Error getting file size: $e');
        }
      }

      return {
        'exists': true,
        'fileCount': files.length,
        'totalSize': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'path': _cacheDirectory!.path,
        'lastCleanup': _lastCleanup?.toIso8601String(),
      };
    } catch (e) {
      debugPrint('Error getting cache stats: $e');
      return {'error': e.toString()};
    }
  }

  /// Force cache cleanup
  Future<void> forceCacheCleanup() async {
    _lastCleanup = null; // Reset to force cleanup
    await _performCacheCleanup();
  }

  // NOTE: Restored helper methods that were removed during refactor ----------------

  // Process next item in queue when a slot becomes available
  void _processNextQueuedRequest() {
    if (_requestQueue.isEmpty) return;

    // During scrolling, don't process any new requests
    if (_isScrolling) {
      // debugPrint('Skipping queue processing during scroll');
      return;
    }

    if (_activeRequests >= _maxConcurrentRequests) return;

    // Clean up cancelled requests first
    _requestQueue.removeWhere((req) {
      if (_cancelledPaths.contains(req.path)) {
        if (!req.completer.isCompleted) {
          req.completer.complete(null);
        }
        return true;
      }
      return false;
    });

    if (_requestQueue.isEmpty) return;

    // Smart priority selection: visible paths first, then by order
    int index = _requestQueue.indexWhere((r) => _visiblePaths.contains(r.path));
    if (index == -1) {
      // No visible items, check if we should process non-visible items
      // Only process if we have low memory pressure and not scrolling
      if (_requestQueue.length > _maxQueueSize * 0.8 || _isScrolling) {
        // High memory pressure or scrolling - only process visible items
        return;
      }
      index = 0;
    }

    final request = _requestQueue.removeAt(index);

    // Final cancellation check
    if (_cancelledPaths.contains(request.path)) {
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
      // Try next item with frame budget
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processNextQueuedRequest();
      });
      return;
    }

    _activeRequests++;

    final future = request.isSmb
        ? _generateSMBThumbnail(request.path, request.size).timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          ) // Shorter timeout
        : Future<String?>.value(null);

    _pendingRequests[request.key] = future;

    future.whenComplete(() {
      _pendingRequests.remove(request.key);
      _activeRequests--;
      _isolatePorts.remove(request.path);

      _processedCount++;
      if (_processedCount >= _cleanupThreshold) {
        _processedCount = 0;
        _cleanupResources();
      }

      // Schedule next processing with frame budget awareness
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isScrolling) {
          _processNextQueuedRequest();
        }
      });
    });

    future.then((result) {
      if (!request.completer.isCompleted) {
        request.completer.complete(result);
      }
    }).catchError((error) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error);
      }
    });
  }

  // Basic resource cleanup: trims caches and triggers periodic cleanup
  void _cleanupResources() {
    // Aggressive memory pressure management
    const memoryPressureThreshold = 0.8; // 80% of limits

    // Trim thumbnail path cache if too large
    if (_thumbnailPathCache.length > 100) {
      // Reduced from 300
      final keysToRemove = <String>[];
      for (final key in _thumbnailPathCache.keys) {
        if (!_visiblePaths.contains(key)) {
          keysToRemove.add(key);
        }
      }
      for (final key in keysToRemove) {
        _thumbnailPathCache.remove(key);
      }
    }

    // Cancel stale pending requests (older than 1 minute) - more aggressive
    final now = DateTime.now();
    final stalePendingRequests = <String>[];
    _pendingRequests.forEach((key, future) {
      final failed = _failedAttempts[key];
      if (failed != null &&
          now.difference(failed) > const Duration(minutes: 1)) {
        stalePendingRequests.add(key);
      }
    });
    for (final key in stalePendingRequests) {
      _pendingRequests.remove(key);
    }

    // Clean up cancelled paths periodically
    if (_cancelledPaths.length > 50) {
      _cancelledPaths.clear();
    }

    // Clean up isolate ports for completed/cancelled requests
    final isolateKeysToRemove = <String>[];
    for (final path in _isolatePorts.keys) {
      if (_cancelledPaths.contains(path) || !_visiblePaths.contains(path)) {
        isolateKeysToRemove.add(path);
      }
    }
    for (final key in isolateKeysToRemove) {
      _isolatePorts.remove(key);
    }

    // Clean up debounce timers
    final timerKeysToRemove = <String>[];
    for (final key in _debounceTimers.keys) {
      if (!_debounceTimers[key]!.isActive) {
        timerKeysToRemove.add(key);
      }
    }
    for (final key in timerKeysToRemove) {
      _debounceTimers.remove(key);
    }

    // Only perform cache cleanup if not under memory pressure
    if (_requestQueue.length < _maxQueueSize * memoryPressureThreshold) {
      scheduleMicrotask(_performCacheCleanup);
    }
  }
}

@pragma('vm:entry-point')
Uint8List? _generateImageThumbnailBytes(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List?;
  final size = params['size'] as int?;
  if (bytes == null || bytes.isEmpty || size == null || size <= 0) {
    return null;
  }

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final double aspectRatio = decoded.width / decoded.height;
  int thumbW, thumbH;
  if (aspectRatio > 1) {
    thumbW = size;
    thumbH = (size / aspectRatio).round();
  } else {
    thumbH = size;
    thumbW = (size * aspectRatio).round();
  }
  thumbW = thumbW.clamp(1, size);
  thumbH = thumbH.clamp(1, size);

  var thumb = img.copyResize(
    decoded,
    width: thumbW,
    height: thumbH,
    interpolation: img.Interpolation.average,
  );

  thumb = img.adjustColor(
    thumb,
    contrast: 1.05,
    saturation: 1.1,
    brightness: 1.02,
  );

  if (thumb.width <= 256 && thumb.height <= 256) {
    try {
      thumb = img.convolution(
        thumb,
        filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
        div: 1,
      );
    } catch (_) {
      // Ignore convolution errors.
    }
  }

  return Uint8List.fromList(img.encodePng(thumb, level: 6));
}
