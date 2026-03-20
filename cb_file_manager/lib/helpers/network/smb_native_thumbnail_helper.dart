import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

/// Direct bridge to SMB native thumbnail generation in smb_native.cpp
/// This bypasses fc_native_video_thumbnail.dart for better performance
class SmbNativeThumbnailHelper {
  static const MethodChannel _channel = MethodChannel('smb_native_thumbnail');

  /// Flag to track initialization status
  static bool _initialized = false;

  /// Prevents multiple concurrent native operations (like fc_native_video_thumbnail.dart)
  static bool _operationInProgress = false;

  /// Semaphore to control access to native operations
  static final _operationSemaphore = Completer<void>()..complete();

  /// Maximum time to wait for a native operation
  static const Duration _operationTimeout =
      Duration(seconds: 3); // Shorter for SMB

  /// Initialize the native SMB thumbnail bridge
  static Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      if (!Platform.isWindows) {
        debugPrint(
            'SmbNativeThumbnailHelper: Not running on Windows, initialization skipped');
        return false;
      }

      // Test if the native method is available
      try {
        await _channel.invokeMethod<bool>('isAvailable');
        _initialized = true;
        debugPrint(
            'SmbNativeThumbnailHelper: Native SMB thumbnail bridge initialized');
        return true;
      } on MissingPluginException {
        debugPrint('SmbNativeThumbnailHelper: Native plugin not available');
        return false;
      }
    } catch (e) {
      debugPrint('SmbNativeThumbnailHelper: Failed to initialize: $e');
      return false;
    }
  }

  /// Generate thumbnail directly using smb_native.cpp functions
  ///
  /// This calls GetThumbnail() or GetThumbnailFast() from smb_native.cpp
  /// - [filePath]: UNC path to the file (e.g., \\server\share\path\file.mp4)
  /// - [thumbnailSize]: Size of the thumbnail (width/height)
  /// - [useFastMode]: Use GetThumbnailFast() for BMP format (faster but larger)
  ///
  /// Returns raw thumbnail data as Uint8List or null if failed
  static Future<Uint8List?> generateThumbnailDirect({
    required String filePath,
    int thumbnailSize = 128,
    bool useFastMode = false,
  }) async {
    if (!Platform.isWindows) {
      debugPrint('SmbNativeThumbnailHelper: Not running on Windows');
      return null;
    }

    // Ensure the bridge is initialized
    if (!_initialized) {
      final initResult = await initialize();
      if (!initResult) return null;
    }

    try {
      // Basic validation
      if (filePath.isEmpty) {
        debugPrint('SmbNativeThumbnailHelper: Invalid file path');
        return null;
      }

      // Check format support
      if (!isSupportedFormat(filePath)) {
        debugPrint(
            'SmbNativeThumbnailHelper: Potentially unsupported format: $filePath');
        // Still try but with lower expectations
      }

      // Wait for operation slot (like fc_native_video_thumbnail.dart)
      if (_operationInProgress) {
        debugPrint(
            'SmbNativeThumbnailHelper: Another operation in progress, waiting...');

        if (_operationSemaphore.isCompleted) {
          var oldSemaphore = _operationSemaphore;
          await oldSemaphore.future;
        } else {
          try {
            await _operationSemaphore.future.timeout(_operationTimeout);
          } catch (e) {
            debugPrint(
                'SmbNativeThumbnailHelper: Timed out waiting for previous operation');
            return null;
          }
        }
      }

      // Create a new semaphore for the current operation
      var currentSemaphore = Completer<void>();
      _operationInProgress = true;

      try {
        // Call native method
        Uint8List? result;
        try {
          result = await _channel.invokeMethod<Uint8List>(
              useFastMode ? 'getThumbnailFast' : 'getThumbnail', {
            'filePath': filePath,
            'thumbnailSize': thumbnailSize,
          }).timeout(_operationTimeout, onTimeout: () {
            debugPrint(
                'SmbNativeThumbnailHelper: Native operation timed out for $filePath');
            return null;
          });
        } on MissingPluginException catch (e) {
          debugPrint(
              'SmbNativeThumbnailHelper: Plugin not available: ${e.message}');
          return null;
        } on PlatformException catch (e) {
          debugPrint(
              'SmbNativeThumbnailHelper: Platform error for $filePath: ${e.message}');
          return null;
        } catch (e) {
          debugPrint('SmbNativeThumbnailHelper: Channel error: $e');
          return null;
        }

        if (result != null && result.isNotEmpty) {
          debugPrint(
              'SmbNativeThumbnailHelper: Successfully generated thumbnail for $filePath (${result.length} bytes)');
          return result;
        } else {
          debugPrint(
              'SmbNativeThumbnailHelper: Could not extract thumbnail from $filePath (null or empty result)');
          return null;
        }
      } finally {
        _operationInProgress = false;
        currentSemaphore.complete();
      }
    } catch (e, stack) {
      debugPrint(
          'SmbNativeThumbnailHelper: Unhandled error generating thumbnail for $filePath: $e\n$stack');
      return null;
    }
  }

  /// Check if a file format is supported by the Windows thumbnail extractor
  static bool isSupportedFormat(String filePath) {
    if (!Platform.isWindows) return false;

    final extension = path.extension(filePath).toLowerCase();
    // Same list as in smb_native.cpp
    final supportedExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.bmp',
      '.gif',
      '.tiff',
      '.webp',
      '.mp4',
      '.mov',
      '.wmv',
      '.avi',
      '.mkv',
      '.mpg',
      '.mpeg',
      '.m4v',
      '.ts'
    ];

    return supportedExtensions.contains(extension);
  }

  /// Generate thumbnail and save to file (compatible with existing workflow)
  ///
  /// This wraps generateThumbnailDirect() to save the result to a file
  /// Returns the output file path on success, null on failure
  static Future<String?> generateThumbnailToFile({
    required String filePath,
    required String outputPath,
    int thumbnailSize = 128,
    bool useFastMode = false,
  }) async {
    try {
      // Generate thumbnail data
      final thumbnailData = await generateThumbnailDirect(
        filePath: filePath,
        thumbnailSize: thumbnailSize,
        useFastMode: useFastMode,
      );

      if (thumbnailData == null || thumbnailData.isEmpty) {
        return null;
      }

      // Create parent directory if it doesn't exist
      final directory = path.dirname(outputPath);
      await Directory(directory).create(recursive: true);

      // Write to file
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(thumbnailData);

      // Verify the file was created and has content
      if (await outputFile.exists() && await outputFile.length() > 0) {
        debugPrint(
            'SmbNativeThumbnailHelper: Successfully saved thumbnail to $outputPath');
        return outputPath;
      } else {
        debugPrint(
            'SmbNativeThumbnailHelper: File reported as created but doesn\'t exist or is empty at $outputPath');
        try {
          if (await outputFile.exists()) await outputFile.delete();
        } catch (_) {}
        return null;
      }
    } catch (e) {
      debugPrint(
          'SmbNativeThumbnailHelper: Error saving thumbnail to file: $e');
      return null;
    }
  }

  /// Safe wrapper for isolate contexts (similar to fc_native_video_thumbnail.dart)
  static Future<Uint8List?> safeThumbnailGenerate({
    required String filePath,
    int thumbnailSize = 128,
    bool useFastMode = false,
  }) async {
    try {
      return await generateThumbnailDirect(
        filePath: filePath,
        thumbnailSize: thumbnailSize,
        useFastMode: useFastMode,
      );
    } catch (e) {
      debugPrint(
          'SmbNativeThumbnailHelper: Fallback - cannot use platform channels in isolate');
      return null;
    }
  }
}
