import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:uuid/uuid.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';

/// Service for managing cached files from network sources
class NetworkFileCacheService {
  static final NetworkFileCacheService _instance =
      NetworkFileCacheService._internal();
  factory NetworkFileCacheService() => _instance;
  NetworkFileCacheService._internal();

  // Custom cache manager instance
  final _cacheManager = DefaultCacheManager();

  // For tracking ongoing operations
  final Map<String, Future<File>> _pendingOperations = {};

  // For tracking active stream buffers
  final Map<String, _StreamBufferInfo> _activeStreamBuffers = {};

  /// Check if a file is a video based on extension
  bool isVideoFile(String path) {
    return FileTypeUtils.isVideoFile(path);
  }

  /// Check if a file is an image based on extension
  bool isImageFile(String path) {
    return FileTypeUtils.isImageFile(path);
  }

  /// Get cache key for a file path
  String _getCacheKey(String path) {
    // Create a deterministic but unique key
    return 'network-${const Uuid().v5(Namespace.url.value, path)}';
  }

  /// Get thumbnail cache key
  String _getThumbnailCacheKey(String path, int size) {
    return 'thumb-$size-${_getCacheKey(path)}';
  }

  /// Buffer part of a network file
  /// Returns a `Future<File>` with the cached file
  Future<File> bufferPartialFile(
    String path,
    Stream<List<int>> fileStream, {
    int? maxBytes,
  }) async {
    final cacheKey = _getCacheKey(path);

    // Check if operation is already in progress
    if (_pendingOperations.containsKey(cacheKey)) {
      return _pendingOperations[cacheKey]!;
    }

    // Create new operation
    final operation = _doCacheFile(cacheKey, fileStream, maxBytes: maxBytes);
    _pendingOperations[cacheKey] = operation;

    // Clean up pending operation when complete
    operation.whenComplete(() {
      _pendingOperations.remove(cacheKey);
    });

    return operation;
  }

  /// Process the actual caching operation
  Future<File> _doCacheFile(
    String key,
    Stream<List<int>> fileStream, {
    int? maxBytes,
  }) async {
    try {
      // Check if already cached
      final fileFromCache = await _cacheManager.getFileFromCache(key);
      if (fileFromCache != null) {
        return fileFromCache.file;
      }

      // Create a buffer to collect data
      final buffer = <int>[];
      int totalBytes = 0;
      final maxSize =
          maxBytes ??
          16 * 1024 * 1024 -
              8; // Slightly under 16MB for video streaming buffering

      try {
        await for (final chunk in fileStream) {
          // Determine how many bytes we can still accept without exceeding maxSize
          final int remaining = maxSize - totalBytes;

          if (remaining <= 0) {
            // We have reached the limit, stop reading further
            break;
          }

          if (chunk.length > remaining) {
            // Only take the portion of the chunk that fits within the limit
            buffer.addAll(chunk.sublist(0, remaining));
            totalBytes += remaining;
            break; // Reached the maximum allowed size
          } else {
            // Whole chunk fits
            buffer.addAll(chunk);
            totalBytes += chunk.length;

            if (totalBytes >= maxSize) {
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Error reading file stream: $e');
        // Continue with what we have so far
      }

      if (buffer.isEmpty) {
        throw Exception('No data received from stream');
      }

      // Put data in the cache
      final fileBytes = Uint8List.fromList(buffer);
      final fileInfo = await _cacheManager.putFile(
        key,
        fileBytes,
        key: key,
        maxAge: const Duration(days: 7),
      );

      return fileInfo;
    } catch (e) {
      debugPrint('Error caching file: $e');
      rethrow;
    }
  }

  /// Creates a stream that buffers data as it goes and forwards it to a controller
  /// This allows for progressive loading/streaming of content
  /// Returns a StreamSubscription that should be canceled when done
  StreamSubscription<List<int>> bufferStreamAndForward(
    String path,
    Stream<List<int>> sourceStream,
    StreamController<List<int>> targetController,
  ) {
    final cacheKey = _getCacheKey(path);
    final buffer = <int>[];
    int totalBytes = 0;

    // Create buffer info object
    final bufferInfo = _StreamBufferInfo(buffer, targetController, path);
    _activeStreamBuffers[cacheKey] = bufferInfo;

    // Listen to the source stream
    final subscription = sourceStream.listen(
      (data) {
        // Add data to buffer
        buffer.addAll(data);
        totalBytes += data.length;

        // Forward to target controller
        if (!targetController.isClosed) {
          targetController.add(data);
        }

        // Periodically save buffer to cache
        if (totalBytes >= bufferInfo.nextCachingThreshold) {
          _cacheBufferData(cacheKey, buffer);
          bufferInfo.nextCachingThreshold =
              totalBytes + 4096 * 1024; // Cache every 4MB for video streaming
        }
      },
      onError: (error) {
        debugPrint('Error in network stream: $error');
        if (!targetController.isClosed) {
          targetController.addError(error);
          targetController.close();
        }
      },
      onDone: () async {
        // Save the complete buffer to cache
        await _cacheBufferData(cacheKey, buffer);

        // Close the target controller
        if (!targetController.isClosed) {
          targetController.close();
        }

        // Clean up
        _activeStreamBuffers.remove(cacheKey);
      },
      cancelOnError: false,
    );

    // Clean up when target controller is closed
    targetController.onCancel = () {
      subscription.cancel();
      _activeStreamBuffers.remove(cacheKey);
    };

    return subscription;
  }

  // Helper to save buffer data to cache
  Future<void> _cacheBufferData(String key, List<int> buffer) async {
    try {
      if (buffer.isEmpty) return;

      final fileBytes = Uint8List.fromList(buffer);
      await _cacheManager.putFile(
        key,
        fileBytes,
        key: key,
        maxAge: const Duration(days: 7),
      );
    } catch (e) {
      debugPrint('Error caching buffer data: $e');
    }
  }

  /// Cache a thumbnail
  Future<File> cacheThumbnail(
    String path,
    Uint8List thumbnailData,
    int size,
  ) async {
    final cacheKey = _getThumbnailCacheKey(path, size);
    final fileInfo = await _cacheManager.putFile(
      cacheKey,
      thumbnailData,
      key: cacheKey,
      maxAge: const Duration(days: 14), // Keep thumbnails longer
    );
    return fileInfo;
  }

  /// Get cached file if available
  Future<File?> getCachedFile(String path) async {
    final cacheKey = _getCacheKey(path);
    final fileInfo = await _cacheManager.getFileFromCache(cacheKey);
    return fileInfo?.file;
  }

  /// Get cached thumbnail if available
  Future<File?> getCachedThumbnail(String path, int size) async {
    final cacheKey = _getThumbnailCacheKey(path, size);
    final fileInfo = await _cacheManager.getFileFromCache(cacheKey);
    return fileInfo?.file;
  }

  /// Clean up cache
  Future<void> clearCache() async {
    await _cacheManager.emptyCache();
  }

  /// Remove single item from cache
  Future<void> removeCachedFile(String path) async {
    final cacheKey = _getCacheKey(path);
    await _cacheManager.removeFile(cacheKey);
  }
}

/// Helper class to track buffering information for a stream
class _StreamBufferInfo {
  final List<int> buffer;
  final StreamController<List<int>> controller;
  final String path;
  int nextCachingThreshold =
      4096 * 1024; // 4MB initial threshold for video streaming

  _StreamBufferInfo(this.buffer, this.controller, this.path);
}
