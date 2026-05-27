import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/media/fc_native_video_thumbnail.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:path/path.dart' as path;

/// Represents image dimensions (width x height).
class ImageDimensions {
  final int width;
  final int height;

  const ImageDimensions(this.width, this.height);

  @override
  String toString() => '$width \u00D7 $height';
}

/// A lightweight service that provides on-demand file metadata with caching.
///
/// Expensive operations (image dimensions, video duration, folder item count)
/// are cached to avoid repeated I/O. The cache uses an LRU-style eviction
/// when it exceeds [maxCacheSize].
class FileMetadataService {
  static const int maxCacheSize = 500;

  final Map<String, ImageDimensions?> _dimensionsCache = {};
  final Map<String, Duration?> _durationCache = {};
  final Map<String, int?> _itemCountCache = {};

  // Track in-flight requests to avoid duplicate work
  final Map<String, Future<ImageDimensions?>> _dimensionsInFlight = {};
  final Map<String, Future<Duration?>> _durationInFlight = {};
  final Map<String, Future<int?>> _itemCountInFlight = {};

  /// Get image dimensions by decoding only the header.
  /// Returns null for non-image files or on failure.
  Future<ImageDimensions?> getImageDimensions(String filePath) async {
    if (_dimensionsCache.containsKey(filePath)) {
      return _dimensionsCache[filePath];
    }

    // Check if already in flight
    if (_dimensionsInFlight.containsKey(filePath)) {
      return _dimensionsInFlight[filePath];
    }

    final ext = path.extension(filePath).toLowerCase();
    final category = FileTypeRegistry.getCategory(ext);
    if (category != FileCategory.image) {
      _dimensionsCache[filePath] = null;
      return null;
    }

    final future = _loadImageDimensions(filePath);
    _dimensionsInFlight[filePath] = future;

    try {
      final result = await future;
      _evictIfNeeded(_dimensionsCache);
      _dimensionsCache[filePath] = result;
      return result;
    } finally {
      _dimensionsInFlight.remove(filePath);
    }
  }

  /// Get media duration for video/audio files.
  /// Returns null for non-media files or on failure.
  Future<Duration?> getMediaDuration(String filePath) async {
    if (_durationCache.containsKey(filePath)) {
      return _durationCache[filePath];
    }

    if (_durationInFlight.containsKey(filePath)) {
      return _durationInFlight[filePath];
    }

    final ext = path.extension(filePath).toLowerCase();
    final category = FileTypeRegistry.getCategory(ext);
    if (category != FileCategory.video && category != FileCategory.audio) {
      _durationCache[filePath] = null;
      return null;
    }

    final future = _loadMediaDuration(filePath);
    _durationInFlight[filePath] = future;

    try {
      final result = await future;
      _evictIfNeeded(_durationCache);
      _durationCache[filePath] = result;
      return result;
    } finally {
      _durationInFlight.remove(filePath);
    }
  }

  /// Get the number of direct children in a folder.
  /// Returns null for non-directories or on failure.
  Future<int?> getFolderItemCount(String folderPath) async {
    if (_itemCountCache.containsKey(folderPath)) {
      return _itemCountCache[folderPath];
    }

    if (_itemCountInFlight.containsKey(folderPath)) {
      return _itemCountInFlight[folderPath];
    }

    final future = _loadFolderItemCount(folderPath);
    _itemCountInFlight[folderPath] = future;

    try {
      final result = await future;
      _evictIfNeeded(_itemCountCache);
      _itemCountCache[folderPath] = result;
      return result;
    } finally {
      _itemCountInFlight.remove(folderPath);
    }
  }

  /// Invalidate all cached data for a specific path.
  void invalidate(String path) {
    _dimensionsCache.remove(path);
    _durationCache.remove(path);
    _itemCountCache.remove(path);
  }

  /// Clear all caches.
  void clearAll() {
    _dimensionsCache.clear();
    _durationCache.clear();
    _itemCountCache.clear();
  }

  /// Format a Duration as HH:MM:SS or MM:SS.
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // ─── Private helpers ─────────────────────────────────────────────

  Future<ImageDimensions?> _loadImageDimensions(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final dimensions = ImageDimensions(image.width, image.height);
      image.dispose();
      codec.dispose();
      return dimensions;
    } catch (e) {
      debugPrint('FileMetadataService: Error getting image dimensions: $e');
      return null;
    }
  }

  Future<Duration?> _loadMediaDuration(String filePath) async {
    try {
      // Use the native FFmpeg-based duration extraction (Windows only, fast)
      final seconds = await FcNativeVideoThumbnail.getVideoDuration(filePath);
      if (seconds <= 0) return null;
      return Duration(milliseconds: (seconds * 1000).round());
    } catch (e) {
      debugPrint('FileMetadataService: Error getting media duration: $e');
      return null;
    }
  }

  Future<int?> _loadFolderItemCount(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) return null;

      int count = 0;
      await for (final _ in dir.list(followLinks: false)) {
        count++;
      }
      return count;
    } catch (e) {
      debugPrint('FileMetadataService: Error getting folder item count: $e');
      return null;
    }
  }

  void _evictIfNeeded<T>(Map<String, T> cache) {
    if (cache.length >= maxCacheSize) {
      // Remove oldest 20% of entries
      final keysToRemove = cache.keys.take(cache.length ~/ 5).toList();
      for (final key in keysToRemove) {
        cache.remove(key);
      }
    }
  }
}
