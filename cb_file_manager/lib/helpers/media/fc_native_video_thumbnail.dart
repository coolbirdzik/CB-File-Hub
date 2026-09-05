import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'thumbnail_queue_manager.dart';

/// A Flutter plugin to access Windows native video thumbnail generation
/// This uses the Windows thumbnail cache system for efficient thumbnail extraction
class FcNativeVideoThumbnail {
  static const MethodChannel _channel = MethodChannel(
    'fc_native_video_thumbnail',
  );

  /// Flag to indicate if this is running on Windows
  static bool get isWindows => Platform.isWindows;

  /// Flag to track initialization status
  static bool _initialized = false;

  /// Maximum time to wait for a native operation (increased for 4K videos)
  static const Duration _operationTimeout = Duration(seconds: 30);

  /// Initialize the plugin
  /// This is automatically called by [generateThumbnail]
  static Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      if (!isWindows) {
        debugPrint(
          'FcNativeVideoThumbnail: Not running on Windows, initialization skipped',
        );
        return false;
      }

      // Nothing to initialize for now, but we could add version checking or capability testing here
      _initialized = true;
      debugPrint(
        'FcNativeVideoThumbnail: Native Windows thumbnail provider initialized',
      );
      return true;
    } catch (e) {
      debugPrint('FcNativeVideoThumbnail: Failed to initialize: $e');
      return false;
    }
  }

  /// Generate a thumbnail for a video file using Windows native APIs
  ///
  /// - [videoPath]: Path to the video file
  /// - [outputPath]: Where to save the thumbnail (must be a valid path)
  /// - [width]: Width of the thumbnail (0 = use original width, negative = use percentage of original)
  /// - [format]: Image format, either 'png' or 'jpg'
  /// - [timeSeconds]: Position in the video (in seconds) to extract the thumbnail from (optional)
  /// - [quality]: Image quality for JPEG format (1-100, default 95, ignored for PNG)
  ///
  /// Returns the path to the generated thumbnail if successful, null otherwise
  static Future<String?> generateThumbnail({
    required String videoPath,
    required String outputPath,
    int width = 1024, // Increased for better quality with HD/4K videos
    String format = 'png',
    int? timeSeconds,
    int quality = 95,
  }) async {
    if (!isWindows) {
      debugPrint(
        'FcNativeVideoThumbnail: Not running on Windows, cannot generate native thumbnail',
      );
      return null;
    }

    // Ensure the plugin is initialized
    if (!_initialized) {
      final initResult = await initialize();
      if (!initResult) return null;
    }

    try {
      // Basic validation before attempting to use the platform channel
      if (videoPath.isEmpty || outputPath.isEmpty) {
        debugPrint('FcNativeVideoThumbnail: Invalid video or output path');
        return null;
      }

      // Validate paths (async)
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        debugPrint(
          'FcNativeVideoThumbnail: Video file does not exist: $videoPath',
        );
        return null;
      }

      // Check for unsupported format by examining the file extension
      if (!isSupportedFormat(videoPath)) {
        debugPrint(
          'FcNativeVideoThumbnail: Potentially unsupported format: $videoPath',
        );
        // Still try but with lower expectations of success
      }

      // Create parent directory if it doesn't exist
      final directory = path.dirname(outputPath);
      await Directory(directory).create(recursive: true);

      // PERFORMANCE: Removed _operationInProgress lock to allow parallel operations
      // Native C++ plugin already handles thread pool internally

      // Call the native method with a timeout and proper error handling
      bool? result;
      try {
        // Wrap platform channel call in try-catch to handle BackgroundIsolateBinaryMessenger errors
        result = await _channel
            .invokeMethod<bool>('getVideoThumbnail', {
              'srcFile': videoPath,
              'destFile': outputPath,
              'width': width,
              'format': format.toLowerCase() == 'png' ? 'png' : 'jpg',
              'timeSeconds': timeSeconds, // Pass the timestamp to native code
              'quality': quality, // Pass quality setting for JPEG format
            })
            .timeout(
              _operationTimeout,
              onTimeout: () {
                debugPrint(
                  'FcNativeVideoThumbnail: Native operation timed out for $videoPath',
                );
                return false;
              },
            );
      } on MissingPluginException catch (e) {
        debugPrint(
          'FcNativeVideoThumbnail: Plugin not available: ${e.message}',
        );
        return null;
      } on PlatformException catch (e) {
        // Handle specific platform exception
        debugPrint(
          'FcNativeVideoThumbnail: Platform error for $videoPath: ${e.message}',
        );
        return null;
      } catch (e) {
        // Handle any other exceptions from the platform channel
        debugPrint('FcNativeVideoThumbnail: Channel error: $e');
        return null;
      }

      // Check if result is null (can happen with BackgroundIsolateBinaryMessenger issues)
      if (result == null) {
        debugPrint('FcNativeVideoThumbnail: Null result from platform channel');
        return null;
      }

      if (result == true) {
        // Verify the thumbnail was created (async)
        final outputFile = File(outputPath);
        if (await outputFile.exists() && await outputFile.length() > 0) {
          // Use async exists() and length()
          debugPrint(
            'FcNativeVideoThumbnail: Successfully generated thumbnail at $outputPath',
          );
          return outputPath;
        } else {
          debugPrint(
            'FcNativeVideoThumbnail: File reported as created but doesn\'t exist or is empty at $outputPath',
          );
          // Attempt to delete potentially corrupt file
          try {
            if (await outputFile.exists()) await outputFile.delete();
          } catch (_) {}
          return null;
        }
      } else {
        // Failed extraction but not an error - common with some video files
        debugPrint(
          'FcNativeVideoThumbnail: Could not extract thumbnail from video $videoPath (native call returned false)',
        );
        return null;
      }
    } catch (e, stack) {
      // Catch any remaining exceptions
      debugPrint(
        'FcNativeVideoThumbnail: Unhandled error generating thumbnail for $videoPath: $e\n$stack',
      );
      return null;
    }
  }

  /// Check if a video format is supported by the Windows thumbnail extractor
  /// This is a conservative list of formats known to work well with Windows thumbnail cache
  static bool isSupportedFormat(String videoPath) {
    if (!isWindows) return false;

    final extension = path.extension(videoPath).toLowerCase();
    // Windows thumbnail cache supports most common video formats
    final supportedExtensions = [
      '.mp4',
      '.mov',
      '.wmv',
      '.avi',
      '.mkv',
      '.mpg',
      '.mpeg',
      '.m4v',
      '.ts',
    ];

    return supportedExtensions.contains(extension);
  }

  /// Generate thumbnail using original video resolution (highest quality)
  static Future<String?> generateOriginalSizeThumbnail({
    required String videoPath,
    required String outputPath,
    String format = 'png',
    int? timeSeconds,
    int quality = 95,
  }) async {
    return generateThumbnail(
      videoPath: videoPath,
      outputPath: outputPath,
      width: 0, // 0 = use original resolution
      format: format,
      timeSeconds: timeSeconds,
      quality: quality,
    );
  }

  /// Generate thumbnail using percentage of original resolution
  /// [percentage] should be between 10 and 100 (e.g., 75 = 75% of original size)
  static Future<String?> generatePercentageThumbnail({
    required String videoPath,
    required String outputPath,
    required int percentage,
    String format = 'png',
    int? timeSeconds,
    int quality = 95,
  }) async {
    if (percentage < 10 || percentage > 100) {
      throw ArgumentError('Percentage must be between 10 and 100');
    }

    return generateThumbnail(
      videoPath: videoPath,
      outputPath: outputPath,
      width: -percentage, // Negative = use percentage
      format: format,
      timeSeconds: timeSeconds,
      quality: quality,
    );
  }

  /// Generate high-quality thumbnail optimized for HD/4K videos
  static Future<String?> generateHDThumbnail({
    required String videoPath,
    required String outputPath,
    String format = 'png',
    int? timeSeconds,
    int quality = 98,
  }) async {
    return generateThumbnail(
      videoPath: videoPath,
      outputPath: outputPath,
      width: 1920, // HD width with intelligent scaling
      format: format,
      timeSeconds: timeSeconds,
      quality: quality,
    );
  }

  /// A safer method to handle isolate contexts
  static Future<String?> safeThumbnailGenerate({
    required String videoPath,
    required String outputPath,
    int width = 1024,
    String format = 'png',
    int? timeSeconds,
    int quality = 95,
  }) async {
    // Use queue manager to prevent UI blocking
    return ThumbnailQueueManager().requestThumbnail(
      videoPath: videoPath,
      outputPath: outputPath,
      generator: () => generateThumbnail(
        videoPath: videoPath,
        outputPath: outputPath,
        width: width,
        format: format,
        timeSeconds: timeSeconds,
        quality: quality,
      ),
      priority: 10,
      isVisible: true,
    );
  }

  /// Get video duration in seconds using FFmpeg native library
  /// Returns the duration in seconds, or -1 if failed
  /// This is much faster than spawning ffprobe.exe process
  static Future<double> getVideoDuration(String videoPath) async {
    if (!isWindows) {
      return -1.0;
    }

    // Ensure the plugin is initialized
    if (!_initialized) {
      final initResult = await initialize();
      if (!initResult) return -1.0;
    }

    try {
      final result = await _channel.invokeMethod<double>('getVideoDuration', {
        'srcFile': videoPath,
      });
      return result ?? -1.0;
    } catch (e) {
      debugPrint('FcNativeVideoThumbnail: Error getting video duration: $e');
      return -1.0;
    }
  }

  /// Generate thumbnail at a percentage of video duration (optimized single-pass)
  ///
  /// This is the FASTEST method for custom mode thumbnail generation because it:
  /// 1. Opens the video file ONCE (not twice like getVideoDuration + generateThumbnail)
  /// 2. Gets duration and extracts thumbnail in a single operation
  /// 3. Uses optimized FFmpeg probe settings for faster file analysis
  /// 4. Uses multi-threaded decoding for faster frame extraction
  /// 5. Uses fast bilinear scaling for quicker image processing
  ///
  /// - [videoPath]: Path to the video file
  /// - [outputPath]: Where to save the thumbnail
  /// - [percentage]: Position in video as percentage (0.0 to 100.0)
  /// - [width]: Width of the thumbnail (0 = use original width)
  /// - [format]: Image format, either 'png' or 'jpg'
  /// - [quality]: Image quality for JPEG format (1-100, default 95)
  ///
  /// Returns the path to the generated thumbnail if successful, null otherwise
  static Future<String?> generateThumbnailAtPercentage({
    required String videoPath,
    required String outputPath,
    required double percentage,
    int width = 1024,
    String format = 'jpg',
    int quality = 95,
  }) async {
    if (!isWindows) {
      debugPrint(
        'FcNativeVideoThumbnail: Not running on Windows, cannot generate native thumbnail',
      );
      return null;
    }

    // Ensure the plugin is initialized
    if (!_initialized) {
      final initResult = await initialize();
      if (!initResult) return null;
    }

    try {
      // Basic validation
      if (videoPath.isEmpty || outputPath.isEmpty) {
        debugPrint('FcNativeVideoThumbnail: Invalid video or output path');
        return null;
      }

      // Validate video file exists (async)
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        debugPrint(
          'FcNativeVideoThumbnail: Video file does not exist: $videoPath',
        );
        return null;
      }

      // Create parent directory if it doesn't exist
      final directory = path.dirname(outputPath);
      await Directory(directory).create(recursive: true);

      // Call the optimized native method
      String? result;
      try {
        result = await _channel
            .invokeMethod<String>('generateThumbnailAtPercentage', {
              'srcFile': videoPath,
              'destFile': outputPath,
              'width': width,
              'format': format.toLowerCase() == 'png' ? 'png' : 'jpg',
              'percentage': percentage,
              'quality': quality,
            })
            .timeout(
              _operationTimeout,
              onTimeout: () {
                debugPrint(
                  'FcNativeVideoThumbnail: Optimized operation timed out for $videoPath',
                );
                return null;
              },
            );
      } on MissingPluginException catch (e) {
        debugPrint(
          'FcNativeVideoThumbnail: Plugin not available: ${e.message}',
        );
        return null;
      } on PlatformException catch (e) {
        debugPrint(
          'FcNativeVideoThumbnail: FFmpeg/custom error for $videoPath: ${e.code} ${e.message}',
        );
        return null;
      } catch (e) {
        debugPrint('FcNativeVideoThumbnail: Channel error: $e');
        return null;
      }

      if (result != null && result.isNotEmpty) {
        // Verify the thumbnail was created (async)
        final outputFile = File(result);
        if (await outputFile.exists() && await outputFile.length() > 0) {
          return result;
        }
        debugPrint(
          'FcNativeVideoThumbnail: FFmpeg reported success but output missing/empty: $result',
        );
      } else {
        debugPrint(
          'FcNativeVideoThumbnail: FFmpeg returned empty result for $videoPath',
        );
      }

      return null;
    } catch (e, stack) {
      debugPrint(
        'FcNativeVideoThumbnail: Error generating thumbnail at percentage for $videoPath: $e\n$stack',
      );
      return null;
    }
  }
}
