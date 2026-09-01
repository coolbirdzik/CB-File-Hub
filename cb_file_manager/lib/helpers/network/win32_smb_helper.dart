import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';
import 'package:image/image.dart' as img;

import '../media/fc_native_video_thumbnail.dart';
import '../media/video_thumbnail_helper.dart';
import 'network_file_cache_service.dart';
import '../core/app_path_helper.dart';

/// Helper class for working with SMB files via Win32 API
/// Provides methods for creating thumbnails and streaming files
class Win32SmbHelper {
  // Singleton instance
  static final Win32SmbHelper _instance = Win32SmbHelper._internal();
  factory Win32SmbHelper() => _instance;
  Win32SmbHelper._internal();

  // Cache for temporary files
  final Map<String, String> _tempFileCache = {};

  // Cache for thumbnails
  final Map<String, Uint8List> _thumbnailCache = {};

  // Cache service for network files
  final NetworkFileCacheService _cacheService = NetworkFileCacheService();

  // Active operations tracking (concurrency limit constant was unused)
  final Set<String> _activeOperations = {};
  final Map<String, Completer<Uint8List?>> _pendingOperations = {};

  // Flag to check if we're running on Windows
  bool get _isWindows => Platform.isWindows;

  // Thumbnail settings
  static const int _standardThumbnailSize = 256;
  static const int _maxReadBufferSize = 4 * 1024 * 1024; // 4MB limit

  /// Convert a UNC path to a local temporary file
  /// This creates a temporary copy of the file for efficient access
  /// Returns the path to the temporary file
  Future<String?> uncPathToTempFile(String uncPath,
      {bool forceRefresh = false,
      int? maxBytes,
      bool highPriority = false}) async {
    if (!_isWindows) return null;

    try {
      // Check if we already have this file cached
      if (!forceRefresh && _tempFileCache.containsKey(uncPath)) {
        final cachedPath = _tempFileCache[uncPath];
        if (cachedPath != null && File(cachedPath).existsSync()) {
          return cachedPath;
        }
        // Remove invalid cache entry
        _tempFileCache.remove(uncPath);
      }

      // Create temp directory bên trong cb_file_hub/temp_files
      final tempDir = await AppPathHelper.getTempFilesDir();
      final fileName = p.basename(uncPath);
      final tempFilePath = p.join(tempDir.path,
          'smb_temp_${DateTime.now().millisecondsSinceEpoch}_$fileName');

      // Use optimized file copy for high priority items (like visible thumbnails)
      if (highPriority) {
        final result =
            await _fastUncPathToTemp(uncPath, tempFilePath, maxBytes);
        if (result != null) {
          return result;
        }
        // Fall back to standard method if fast path fails
      }

      // Open the UNC file with Win32 API
      final uncPathPtr = uncPath.toNativeUtf16();
      final hFile = CreateFile(
          uncPathPtr,
          GENERIC_READ,
          FILE_SHARE_READ | FILE_SHARE_WRITE,
          nullptr,
          OPEN_EXISTING,
          FILE_ATTRIBUTE_NORMAL,
          NULL);

      if (hFile == INVALID_HANDLE_VALUE) {
        final error = GetLastError();
        debugPrint('Failed to open UNC file: $uncPath, error: $error');
        malloc.free(uncPathPtr);
        return null;
      }

      try {
        // Get file size
        final fileSizeHigh = calloc<Uint32>();
        final fileSizeLow = GetFileSize(hFile, fileSizeHigh);
        final fileSize = fileSizeLow + (fileSizeHigh.value << 32);
        calloc.free(fileSizeHigh);

        if (fileSize <= 0) {
          debugPrint('Invalid file size for: $uncPath');
          return null;
        }

        // If maxBytes is specified, only copy that much data
        final bytesToCopy = maxBytes != null
            ? min(maxBytes, fileSize)
            : min(
                fileSize, 4 * 1024 * 1024); // Limit max size to 4MB by default

        // Create temp file
        final tempFile = File(tempFilePath);
        final sink = tempFile.openWrite();

        // Use larger buffer for better performance
        const bufferSize = 256 * 1024; // 256KB chunks
        final buffer = calloc<Uint8>(bufferSize);

        try {
          var bytesRead = 0;
          final bytesReadPtr = calloc<Uint32>();
          bool readError = false;

          while (bytesRead < bytesToCopy && !readError) {
            final readResult = ReadFile(
                hFile,
                buffer,
                min(bufferSize, bytesToCopy - bytesRead),
                bytesReadPtr,
                nullptr);

            if (readResult == 0) {
              final error = GetLastError();
              // Only log as error if it's not end of file
              if (error != ERROR_HANDLE_EOF) {
                debugPrint('Error reading file: $uncPath, error: $error');
                readError = true;
              }
              break;
            }

            final chunkSize = bytesReadPtr.value;
            if (chunkSize == 0) break; // End of file

            // Write chunk to temp file
            sink.add(buffer.asTypedList(chunkSize));

            bytesRead += chunkSize;

            // Yield to event loop every ~1MB copied to keep UI responsive
            if (bytesRead % (1024 * 1024) == 0) {
              await Future.delayed(Duration.zero);
            }
          }

          calloc.free(bytesReadPtr);

          // If we have read some data but encountered an error, we'll still use what we have
          if (readError && bytesRead == 0) {
            await sink.close();
            await tempFile.delete();
            return null;
          }
        } finally {
          calloc.free(buffer);
          await sink.close();
        }

        // Only cache if we got enough data
        final fileStats = await tempFile.stat();
        if (fileStats.size > 0) {
          _tempFileCache[uncPath] = tempFilePath;
          return tempFilePath;
        } else {
          // Clean up empty file
          await tempFile.delete();
          return null;
        }
      } finally {
        CloseHandle(hFile);
        malloc.free(uncPathPtr);
      }
    } catch (e) {
      debugPrint('Error creating temp file for $uncPath: $e');
      return null;
    }
  }

  /// Fast path optimization for reading UNC files (better for thumbnails)
  Future<String?> _fastUncPathToTemp(
      String uncPath, String tempFilePath, int? maxBytes) async {
    try {
      // Kiểm tra xem đường dẫn có phải dạng UNC không
      if (!uncPath.startsWith('\\\\')) {
        debugPrint('Path is not a valid UNC path: $uncPath');
        return null;
      }

      // Thử mở file với quyền truy cập rộng hơn
      final uncPathPtr = uncPath.toNativeUtf16();
      final hFile = CreateFile(
          uncPathPtr,
          GENERIC_READ,
          FILE_SHARE_READ | FILE_SHARE_WRITE, // Cho phép chia sẻ đọc và ghi
          nullptr,
          OPEN_EXISTING,
          FILE_FLAG_SEQUENTIAL_SCAN, // Optimize for sequential reading
          NULL);

      if (hFile == INVALID_HANDLE_VALUE) {
        final error = GetLastError();
        debugPrint('Fast read failed for: $uncPath, error: $error');
        malloc.free(uncPathPtr);

        // Thử với đường dẫn được mã hóa URL
        try {
          final encodedPath = Uri.encodeFull(uncPath).replaceAll('%5C', '\\');
          if (encodedPath != uncPath) {
            debugPrint('Trying with encoded path: $encodedPath');
            return await _fastUncPathToTemp(
                encodedPath, tempFilePath, maxBytes);
          }
        } catch (e) {
          debugPrint('Error encoding path: $e');
        }

        return null;
      }

      try {
        // Get file size
        final fileSizeHigh = calloc<Uint32>();
        final fileSizeLow = GetFileSize(hFile, fileSizeHigh);
        final fileSize = fileSizeLow + (fileSizeHigh.value << 32);
        calloc.free(fileSizeHigh);

        // If maxBytes is specified, only copy that much data
        final bytesToCopy = maxBytes != null
            ? min(maxBytes, fileSize)
            : min(fileSize, _maxReadBufferSize); // Limit to reasonable size

        // For very small files, read all at once
        if (bytesToCopy < 1024 * 1024) {
          // 1MB
          final buffer = calloc<Uint8>(bytesToCopy);
          final bytesReadPtr = calloc<Uint32>();

          try {
            final readResult =
                ReadFile(hFile, buffer, bytesToCopy, bytesReadPtr, nullptr);
            if (readResult != 0 && bytesReadPtr.value > 0) {
              // Write data to file at once
              final tempFile = File(tempFilePath);
              await tempFile
                  .writeAsBytes(buffer.asTypedList(bytesReadPtr.value));

              // Cache the temp file path
              _tempFileCache[uncPath] = tempFilePath;
              return tempFilePath;
            }
          } finally {
            calloc.free(buffer);
            calloc.free(bytesReadPtr);
          }
        }

        // For larger files, use chunked reading
        const bufferSize = 512 * 1024; // 512KB chunks for faster reading
        final buffer = calloc<Uint8>(bufferSize);
        final tempFile = File(tempFilePath);
        final sink = tempFile.openWrite();
        final bytesReadPtr = calloc<Uint32>();

        try {
          var bytesRead = 0;

          while (bytesRead < bytesToCopy) {
            final readResult = ReadFile(
                hFile,
                buffer,
                min(bufferSize, bytesToCopy - bytesRead),
                bytesReadPtr,
                nullptr);

            if (readResult == 0) {
              final error = GetLastError();
              debugPrint('Error in fast reading: $uncPath, error: $error');
              break;
            }

            final chunkSize = bytesReadPtr.value;
            if (chunkSize == 0) break; // End of file

            // Write chunk to temp file
            sink.add(buffer.asTypedList(chunkSize));

            bytesRead += chunkSize;

            // Yield every ~1MB to allow UI frames
            if (bytesRead % (1024 * 1024) == 0) {
              await Future.delayed(Duration.zero);
            }
          }

          await sink.close();

          // Kiểm tra file có dữ liệu không trước khi cache
          if (await tempFile.exists() && await tempFile.length() > 0) {
            // Cache the temp file path
            _tempFileCache[uncPath] = tempFilePath;
            return tempFilePath;
          } else {
            // Xóa file rỗng
            await tempFile.delete();
            return null;
          }
        } finally {
          calloc.free(buffer);
          calloc.free(bytesReadPtr);
        }
      } finally {
        CloseHandle(hFile);
        malloc.free(uncPathPtr);
      }
    } catch (e) {
      debugPrint('Error in fast file copy for $uncPath: $e');
      return null;
    }
  }

  /// Generate a thumbnail for a video file on SMB with improved quality
  /// Returns the thumbnail data as a Uint8List
  /// Set isPartialFile to true if the file is only partially downloaded/buffered
  Future<Uint8List?> generateVideoThumbnail(String uncPath, int size,
      {bool isPartialFile = false}) async {
    if (!_isWindows) return null;

    // Normalize size to avoid too many cached variations
    final normalizedSize = _normalizeSize(size);

    // Check cache first
    final cacheKey = '$uncPath:$normalizedSize';
    if (_thumbnailCache.containsKey(cacheKey)) {
      return _thumbnailCache[cacheKey];
    }

    // Handle concurrency
    if (_activeOperations.contains(cacheKey)) {
      // Already processing this thumbnail, wait for it
      if (!_pendingOperations.containsKey(cacheKey)) {
        _pendingOperations[cacheKey] = Completer<Uint8List?>();
      }
      return _pendingOperations[cacheKey]!.future;
    }

    // Mark as active
    _activeOperations.add(cacheKey);
    File? tempFile;
    File? thumbnailFile;

    try {
      // Method 1: First try using FcNativeVideoThumbnail directly with UNC path
      if (FcNativeVideoThumbnail.isSupportedFormat(uncPath)) {
        final tempDir = await AppPathHelper.getTempFilesDir();
        final thumbnailPath = p.join(tempDir.path,
            'smb_thumb_${DateTime.now().millisecondsSinceEpoch}.jpg');

        final result = await FcNativeVideoThumbnail.generateThumbnail(
          videoPath: uncPath,
          outputPath: thumbnailPath,
          width: normalizedSize,
          timeSeconds: 5, // Capture at 5 seconds to avoid black intro
          format: 'jpg',
        );

        if (result != null) {
          thumbnailFile = File(result);
          if (await thumbnailFile.exists()) {
            final thumbnailData = await thumbnailFile.readAsBytes();

            // Enhance image quality if needed
            final enhancedData = await _enhanceThumbnailQuality(thumbnailData);

            _thumbnailCache[cacheKey] = enhancedData;

            // Complete any pending requests
            _completePendingOperations(cacheKey, enhancedData);
            return enhancedData;
          }
        }
      }

      // Method 2: Buffer the video file and process it locally
      // If direct approach failed or we're dealing with a partial file
      final localPath = isPartialFile
          ? uncPath // Use as is if it's already a partial file
          : await uncPathToTempFile(uncPath,
              maxBytes: 1024 * 1024, // 1MB should be enough for video header
              highPriority: true);

      if (localPath == null) {
        debugPrint('Failed to create temporary file for $uncPath');
        _completePendingOperations(cacheKey, null);
        return null;
      }

      tempFile = File(localPath);

      // Method 3: Use the VideoThumbnailHelper (which uses video_thumbnail package)
      final thumbnailPath = await VideoThumbnailHelper.getThumbnail(
        localPath,
        forceRegenerate: true, // Force regenerate since we're having issues
        isPriority: true,
        quality: 90, // High quality value
        thumbnailSize: normalizedSize,
      );

      if (thumbnailPath != null) {
        thumbnailFile = File(thumbnailPath);
        if (await thumbnailFile.exists()) {
          final thumbnailData = await thumbnailFile.readAsBytes();

          // Enhance image quality if needed
          final enhancedData = await _enhanceThumbnailQuality(thumbnailData);

          _thumbnailCache[cacheKey] = enhancedData;

          // Complete any pending requests
          _completePendingOperations(cacheKey, enhancedData);
          return enhancedData;
        }
      }

      // Complete pending operations with null if we got here
      _completePendingOperations(cacheKey, null);
      return null;
    } catch (e) {
      debugPrint('Error generating video thumbnail for $uncPath: $e');
      _completePendingOperations(cacheKey, null);
      return null;
    } finally {
      _activeOperations.remove(cacheKey);

      // Clean up temporary files
      try {
        if (thumbnailFile != null && await thumbnailFile.exists()) {
          await thumbnailFile.delete();
        }

        // Only delete temp file if it's not in our cache
        if (tempFile != null &&
            !_tempFileCache.values.contains(tempFile.path) &&
            await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }

  /// Generate a thumbnail for an image file on SMB with high quality
  /// Returns the thumbnail data as a Uint8List
  Future<Uint8List?> generateImageThumbnail(String uncPath, int size) async {
    if (!_isWindows) return null;

    // Normalize size to avoid too many cached variations
    final normalizedSize = _normalizeSize(size);

    // Check cache first
    final cacheKey = '$uncPath:$normalizedSize';
    if (_thumbnailCache.containsKey(cacheKey)) {
      return _thumbnailCache[cacheKey];
    }

    // Handle concurrency
    if (_activeOperations.contains(cacheKey)) {
      // Already processing this thumbnail, wait for it
      if (!_pendingOperations.containsKey(cacheKey)) {
        _pendingOperations[cacheKey] = Completer<Uint8List?>();
      }
      return _pendingOperations[cacheKey]!.future;
    }

    // Mark as active
    _activeOperations.add(cacheKey);
    File? tempFile;

    try {
      // Create a local temp copy with high priority
      final localPath = await uncPathToTempFile(uncPath,
          highPriority: true,
          maxBytes: 4 * 1024 * 1024); // Limit to 4MB for images

      if (localPath == null) {
        _completePendingOperations(cacheKey, null);
        return null;
      }

      // Use the image package to create a high quality thumbnail
      tempFile = File(localPath);
      final imageBytes = await tempFile.readAsBytes();

      // Use compute to avoid blocking the UI thread
      final thumbnailData = await compute(_createHighQualityImageThumbnail, {
        'imageBytes': imageBytes,
        'size': normalizedSize,
      });

      if (thumbnailData != null) {
        _thumbnailCache[cacheKey] = thumbnailData;
        _completePendingOperations(cacheKey, thumbnailData);
        return thumbnailData;
      }

      _completePendingOperations(cacheKey, null);
      return null;
    } catch (e) {
      debugPrint('Error generating image thumbnail for $uncPath: $e');
      _completePendingOperations(cacheKey, null);
      return null;
    } finally {
      _activeOperations.remove(cacheKey);

      // Clean up temp file if it's not cached
      try {
        if (tempFile != null &&
            !_tempFileCache.values.contains(tempFile.path) &&
            await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }

  /// Complete any pending operations for this key
  void _completePendingOperations(String key, Uint8List? data) {
    if (_pendingOperations.containsKey(key)) {
      if (!_pendingOperations[key]!.isCompleted) {
        _pendingOperations[key]!.complete(data);
      }
      _pendingOperations.remove(key);
    }
  }

  /// Normalize thumbnail size to a standard size to improve cache hits
  int _normalizeSize(int requestedSize) {
    if (requestedSize <= 128) return 128;
    if (requestedSize <= 256) return 256;
    if (requestedSize <= 512) return 512;
    return _standardThumbnailSize;
  }

  /// Enhance thumbnail quality using image processing
  Future<Uint8List> _enhanceThumbnailQuality(Uint8List data) async {
    try {
      // Only enhance if needed (for poor quality thumbnails)
      if (data.length > 8192) {
        // Already decent quality
        return data;
      }

      // Process directly without isolates to avoid issues
      try {
        final image = img.decodeImage(data);
        if (image == null) return data;

        // Apply enhancements
        var enhanced = img.adjustColor(
          image,
          contrast: 1.05, // Slightly increase contrast
          saturation: 1.1, // Increase saturation
          brightness: 1.02, // Slight brightness boost
        );

        // Apply sharpening for small images
        if (image.width <= 256 && image.height <= 256) {
          try {
            enhanced = img.convolution(
              enhanced,
              filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
              div: 1,
            );
          } catch (e) {
            // Ignore convolution errors
            debugPrint('Error in convolution: $e');
          }
        }

        // Encode with high quality
        return Uint8List.fromList(img.encodeJpg(enhanced, quality: 90));
      } catch (e) {
        debugPrint('Error in direct image enhancement: $e');
        return data; // Return original on error
      }
    } catch (e) {
      debugPrint('Error enhancing thumbnail quality: $e');
      return data; // Return original if enhancement fails
    }
  }

  /// Stream a file from SMB with efficient buffering
  /// Returns a Stream<List<int>> for the file data
  Stream<List<int>> streamFile(String uncPath) async* {
    if (!_isWindows) {
      throw UnsupportedError('Win32 SMB streaming only supported on Windows');
    }

    final uncPathPtr = uncPath.toNativeUtf16();
    final hFile = CreateFile(uncPathPtr, GENERIC_READ, FILE_SHARE_READ, nullptr,
        OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL);

    if (hFile == INVALID_HANDLE_VALUE) {
      final error = GetLastError();
      debugPrint('Failed to open file for streaming: $uncPath, error: $error');
      malloc.free(uncPathPtr);
      throw Exception('Could not open file: error $error');
    }

    malloc.free(uncPathPtr);

    try {
      const bufferSize = 256 * 1024; // 256KB chunks for better throughput
      final buffer = calloc<Uint8>(bufferSize);
      final bytesReadPtr = calloc<Uint32>();

      try {
        while (true) {
          final readResult =
              ReadFile(hFile, buffer, bufferSize, bytesReadPtr, nullptr);
          if (readResult == 0) {
            final error = GetLastError();
            if (error != ERROR_SUCCESS) {
              debugPrint('Error reading file: error $error');
              throw Exception('Error reading file: $error');
            }
            break;
          }

          final bytesRead = bytesReadPtr.value;
          if (bytesRead == 0) break; // End of file

          // Convert native buffer to Dart list
          final chunk = Uint8List.fromList(buffer.asTypedList(bytesRead));
          yield chunk;
        }
      } finally {
        calloc.free(buffer);
        calloc.free(bytesReadPtr);
      }
    } finally {
      CloseHandle(hFile);
    }
  }

  /// Creates a buffered stream that caches data as it is read
  /// This allows for progressive loading and seeking in videos
  Stream<List<int>> createBufferedStream(String uncPath) {
    if (!_isWindows) {
      throw UnsupportedError('Win32 SMB streaming only supported on Windows');
    }

    // Get the base stream
    final baseStream = streamFile(uncPath);

    // Create a controller for our buffered stream
    final controller = StreamController<List<int>>();

    // Use the cache service to buffer data as we go
    _cacheService.bufferStreamAndForward(uncPath, baseStream, controller);

    return controller.stream;
  }

  /// Clear thumbnail cache
  void clearThumbnailCache() {
    _thumbnailCache.clear();
  }

  /// Get temporary file cache size
  int get tempFileCacheSize => _tempFileCache.length;

  /// Get the temporary directory path where cache files are stored
  String? get tempDirectoryPath {
    try {
      return AppPathHelper.rootPath ?? Directory.systemTemp.path;
    } catch (e) {
      debugPrint('Error getting temp directory path: $e');
      return null;
    }
  }

  /// Clear temporary file cache
  Future<void> clearTempFileCache() async {
    // Delete all temp files tracked in cache map
    for (final path in _tempFileCache.values) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting temp file: $e');
      }
    }
    _tempFileCache.clear();

    // Additionally, remove any stray files in the temp_files directory
    try {
      final tempDir = await AppPathHelper.getTempFilesDir();
      final entities = await tempDir.list(recursive: false).toList();
      for (final entity in entities) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (e) {
            debugPrint('Error deleting stray temp file: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning temp_files directory: $e');
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    await clearTempFileCache();
    clearThumbnailCache();
  }
}

// Helper function to get minimum of two integers
int min(int a, int b) => a < b ? a : b;

// Helper function to create high quality image thumbnails
Uint8List? _createHighQualityImageThumbnail(Map<String, dynamic> params) {
  try {
    final imageBytes = params['imageBytes'] as Uint8List;
    final size = params['size'] as int;

    // Use the image package directly for better quality
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    // Calculate aspect ratio for resizing
    final aspectRatio = image.width / image.height;
    final int thumbWidth, thumbHeight;

    if (aspectRatio > 1) {
      thumbWidth = size;
      thumbHeight = (size / aspectRatio).round();
    } else {
      thumbHeight = size;
      thumbWidth = (size * aspectRatio).round();
    }

    // Resize image with high quality settings
    final thumbnail = img.copyResize(
      image,
      width: thumbWidth,
      height: thumbHeight,
      interpolation: img.Interpolation.cubic, // High quality resize
    );

    // Apply image enhancement for better quality
    final enhanced = _enhanceImage(thumbnail);

    // Encode as PNG for best quality
    return Uint8List.fromList(img.encodePng(enhanced, level: 6));
  } catch (e) {
    debugPrint('Error in _createHighQualityImageThumbnail: $e');
    return null;
  }
}

// Enhance image quality by applying some basic adjustments
img.Image _enhanceImage(img.Image image) {
  try {
    // Apply subtle contrast enhancement
    var enhanced = img.adjustColor(
      image,
      contrast: 1.05, // Slightly increase contrast
      saturation: 1.1, // Increase saturation for more vivid thumbnails
      brightness: 1.02, // Slightly increase brightness
    );

    // Apply subtle sharpening for small thumbnails
    if (image.width <= 256 && image.height <= 256) {
      enhanced = img.convolution(
        enhanced,
        filter: [0, -1, 0, -1, 5, -1, 0, -1, 0], // Sharpen filter
        div: 1,
      );
    }

    return enhanced;
  } catch (e) {
    debugPrint('Error enhancing image: $e');
    return image; // Return original if enhancement fails
  }
}
