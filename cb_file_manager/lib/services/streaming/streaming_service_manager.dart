import 'package:flutter/foundation.dart';
import '../network_browsing/i_smb_service.dart';
import 'streaming_helper_base.dart';
// import 'native_smb_streaming_helper.dart';

/// Manager for streaming services and helpers
class StreamingServiceManager {
  static final StreamingServiceManager _instance =
      StreamingServiceManager._internal();
  factory StreamingServiceManager() => _instance;
  StreamingServiceManager._internal();

  final List<StreamingHelperBase> _helpers = [];

  /// Initialize the streaming service manager
  void initialize() {
    if (_helpers.isEmpty) {
      // Add native SMB streaming helper with highest priority
      // _helpers.add(NativeSmbStreamingHelper()); // Removed - using flutter_vlc_player

      // Sort helpers by priority (highest first)
      _helpers.sort((a, b) => (b).priority.compareTo((a).priority));

      debugPrint(
          'StreamingServiceManager: Initialized with ${_helpers.length} helpers');
      for (final helper in _helpers) {
        final typedHelper = helper;
        debugPrint(
            '  - ${typedHelper.name} (priority: ${typedHelper.priority})');
      }
    }
  }

  /// Get the best streaming helper for the given service and media type (instance method)
  StreamingHelperBase? _getBestHelperInstance(
      ISmbService smbService, String fileName) {
    for (final helper in _helpers) {
      if (helper.isServiceSupported(smbService) &&
          helper.isSupportedMediaType(fileName)) {
        debugPrint(
            'StreamingServiceManager: Selected ${(helper).name} for $fileName');
        return helper;
      }
    }

    debugPrint(
        'StreamingServiceManager: No suitable helper found for $fileName');
    return null;
  }

  /// Get all available helpers
  List<StreamingHelperBase> get availableHelpers => List.unmodifiable(_helpers);

  /// Get capabilities of all helpers (instance method)
  Map<String, dynamic> _getAllCapabilitiesInstance() {
    final capabilities = <String, dynamic>{};

    for (final helper in _helpers) {
      final typedHelper = helper;
      capabilities[typedHelper.name] = typedHelper.getCapabilities();
    }

    return capabilities;
  }

  /// Check if native streaming is available (instance method)
  bool get _isNativeStreamingAvailableInstance {
    return _helpers.any((helper) => false); // NativeSmbStreamingHelper removed
  }

  /// Static methods for compatibility

  /// Get the best streaming helper for the given service and media type
  static StreamingHelperBase? getBestHelper(
    ISmbService service,
    String mediaType,
  ) {
    final instance = StreamingServiceManager();
    instance.initialize();
    return instance._getBestHelperInstance(service, mediaType);
  }

  /// Get all available helpers
  static List<StreamingHelperBase> getAllHelpers() {
    final instance = StreamingServiceManager();
    instance.initialize();
    return instance.availableHelpers;
  }

  /// Get capabilities of all helpers
  static Map<String, dynamic> getAllCapabilities() {
    final instance = StreamingServiceManager();
    instance.initialize();
    return instance._getAllCapabilitiesInstance();
  }

  /// Check if native streaming is available
  static bool isNativeStreamingAvailable() {
    final instance = StreamingServiceManager();
    instance.initialize();
    return instance._isNativeStreamingAvailableInstance;
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
      'helper': (helper).name,
      'service': service.runtimeType.toString(),
      'mediaType': mediaType,
      'created': DateTime.now().toIso8601String(),
    };
  }
}
