import 'dart:async';
import 'package:cb_file_manager/services/streaming/streaming_helper_base.dart';
// import 'package:cb_file_manager/services/streaming/native_smb_streaming_helper.dart';
import 'package:cb_file_manager/services/network_browsing/i_smb_service.dart';
import '../utils/app_logger.dart';

/// Manager for streaming services and helpers
class StreamingServiceManager {
  static final List<StreamingHelperBase> _helpers = [];
  static bool _initialized = false;

  /// Initialize the streaming service manager
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Add native SMB streaming helper with highest priority
      // _helpers.add(NativeSmbStreamingHelper()); // Removed - using flutter_vlc_player

      // Sort helpers by priority (highest first)
      _helpers.sort((a, b) => (b).priority.compareTo((a).priority));

      _initialized = true;
    } catch (e) {
      AppLogger.error('Error initializing StreamingServiceManager', error: e);
      _initialized = true; // Mark as initialized even if there are errors
    }
  }

  /// Get the best streaming helper for a given service and media type
  static StreamingHelperBase? getBestHelper(
    ISmbService service,
    String mediaType,
  ) {
    if (!_initialized) {
      throw StateError('StreamingServiceManager not initialized');
    }

    for (final helper in _helpers) {
      if (helper.isServiceSupported(service) &&
          helper.isSupportedMediaType(mediaType)) {
        return helper;
      }
    }
    return null;
  }

  /// Get all available streaming helpers
  static Future<List<StreamingHelperBase>> getAllHelpers() async {
    if (!_initialized) {
      await initialize();
    }
    return List.unmodifiable(_helpers);
  }

  /// Get capabilities of all helpers
  static Future<Map<String, dynamic>> getCapabilities() async {
    if (!_initialized) {
      await initialize();
    }

    final capabilities = <String, dynamic>{};
    for (final helper in _helpers) {
      capabilities[helper.name] = helper.getCapabilities();
    }
    return capabilities;
  }

  /// Check if native streaming is available
  static Future<bool> isNativeStreamingAvailable() async {
    try {
      if (!_initialized) {
        await initialize();
      }

      // Check if we have any native streaming helpers
      return _helpers.any((helper) =>
          (helper).name.toLowerCase().contains('native') &&
          (helper).priority >= 1000);
    } catch (e) {
      AppLogger.error('Error checking native streaming availability', error: e);
      return false;
    }
  }

  /// Create a media player using the best available helper
  static Future<dynamic> createMediaPlayer(
    ISmbService service,
    String mediaType,
  ) async {
    final helper = getBestHelper(service, mediaType);
    if (helper == null) {
      throw UnsupportedError('No suitable streaming helper found');
    }

    // Return a placeholder media player object
    return {
      'helper': helper.name,
      'service': service.runtimeType.toString(),
      'mediaType': mediaType,
      'created': DateTime.now().toIso8601String(),
    };
  }
}
