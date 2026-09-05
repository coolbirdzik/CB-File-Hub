import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for managing memory and preventing ImageReader_JNI errors
class MemoryManagementService {
  static final MemoryManagementService _instance =
      MemoryManagementService._internal();
  factory MemoryManagementService() => _instance;
  MemoryManagementService._internal();

  static const MethodChannel _channel = MethodChannel('memory_management');
  static const EventChannel _memoryEventChannel = EventChannel('memory_events');

  bool _isInitialized = false;
  StreamSubscription? _memoryEventSubscription;

  /// Initialize the memory management service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (Platform.isAndroid) {
        // Set up method channel for Android-specific memory management
        _channel.setMethodCallHandler(_handleMethodCall);

        // Listen to memory events from Android
        _memoryEventSubscription = _memoryEventChannel
            .receiveBroadcastStream()
            .listen(
              (event) {
                _handleMemoryEvent(event);
              },
              onError: (error) {
                debugPrint(
                  'MemoryManagementService: Error receiving memory events: $error',
                );
              },
            );

        // Initialize Android memory management
        await _channel.invokeMethod('initialize');
      }

      _isInitialized = true;
      debugPrint('MemoryManagementService: Initialized successfully');
    } catch (e) {
      debugPrint('MemoryManagementService: Error initializing: $e');
    }
  }

  /// Handle method calls from Android
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onMemoryPressure':
        _handleMemoryPressure(call.arguments);
        break;
      case 'onImageReaderError':
        _handleImageReaderError(call.arguments);
        break;
      default:
        debugPrint(
          'MemoryManagementService: Unknown method call: ${call.method}',
        );
    }
  }

  /// Handle memory events from Android
  void _handleMemoryEvent(dynamic event) {
    try {
      if (event is Map) {
        final eventType = event['type'] as String?;
        final data = event['data'];

        switch (eventType) {
          case 'memory_pressure':
            _handleMemoryPressure(data);
            break;
          case 'image_reader_error':
            _handleImageReaderError(data);
            break;
          case 'buffer_full':
            _handleBufferFull(data);
            break;
          default:
            debugPrint(
              'MemoryManagementService: Unknown memory event: $eventType',
            );
        }
      }
    } catch (e) {
      debugPrint('MemoryManagementService: Error handling memory event: $e');
    }
  }

  /// Handle memory pressure events
  void _handleMemoryPressure(dynamic data) {
    debugPrint('MemoryManagementService: Memory pressure detected: $data');

    // Trigger garbage collection
    _forceGarbageCollection();

    // Notify listeners
    _onMemoryPressureController.add(data);
  }

  /// Handle ImageReader_JNI errors
  void _handleImageReaderError(dynamic data) {
    debugPrint(
      'MemoryManagementService: ImageReader_JNI error detected: $data',
    );

    // Force aggressive cleanup
    _forceAggressiveCleanup();

    // Notify listeners
    _onImageReaderErrorController.add(data);
  }

  /// Handle buffer full events
  void _handleBufferFull(dynamic data) {
    debugPrint('MemoryManagementService: Buffer full detected: $data');

    // Trigger buffer cleanup
    _forceBufferCleanup();

    // Notify listeners
    _onBufferFullController.add(data);
  }

  /// Force garbage collection
  Future<void> forceGarbageCollection() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('forceGarbageCollection');
      } else {
        _forceGarbageCollection();
      }
    } catch (e) {
      debugPrint(
        'MemoryManagementService: Error forcing garbage collection: $e',
      );
    }
  }

  /// Force aggressive cleanup
  Future<void> forceAggressiveCleanup() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('forceAggressiveCleanup');
      } else {
        _forceAggressiveCleanup();
      }
    } catch (e) {
      debugPrint(
        'MemoryManagementService: Error forcing aggressive cleanup: $e',
      );
    }
  }

  /// Force buffer cleanup
  Future<void> forceBufferCleanup() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('forceBufferCleanup');
      } else {
        _forceBufferCleanup();
      }
    } catch (e) {
      debugPrint('MemoryManagementService: Error forcing buffer cleanup: $e');
    }
  }

  /// Get current memory usage
  Future<Map<String, dynamic>?> getMemoryUsage() async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod('getMemoryUsage');
        return result as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('MemoryManagementService: Error getting memory usage: $e');
    }
    return null;
  }

  /// Check if memory pressure is high
  Future<bool> isMemoryPressureHigh() async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod('isMemoryPressureHigh');
        return result as bool? ?? false;
      }
    } catch (e) {
      debugPrint('MemoryManagementService: Error checking memory pressure: $e');
    }
    return false;
  }

  /// Set buffer size for video playback
  Future<void> setVideoBufferSize(int sizeInBytes) async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('setVideoBufferSize', {
          'size': sizeInBytes,
        });
      }
    } catch (e) {
      debugPrint(
        'MemoryManagementService: Error setting video buffer size: $e',
      );
    }
  }

  /// Enable/disable aggressive memory management
  Future<void> setAggressiveMemoryManagement(bool enabled) async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('setAggressiveMemoryManagement', {
          'enabled': enabled,
        });
      }
    } catch (e) {
      debugPrint(
        'MemoryManagementService: Error setting aggressive memory management: $e',
      );
    }
  }

  /// Private method to force garbage collection
  void _forceGarbageCollection() {
    debugPrint('MemoryManagementService: Forcing garbage collection');
    // This is a fallback for non-Android platforms
  }

  /// Private method to force aggressive cleanup
  void _forceAggressiveCleanup() {
    debugPrint('MemoryManagementService: Forcing aggressive cleanup');
    // This is a fallback for non-Android platforms
  }

  /// Private method to force buffer cleanup
  void _forceBufferCleanup() {
    debugPrint('MemoryManagementService: Forcing buffer cleanup');
    // This is a fallback for non-Android platforms
  }

  // Event controllers for notifying listeners
  final StreamController<dynamic> _onMemoryPressureController =
      StreamController<dynamic>.broadcast();
  final StreamController<dynamic> _onImageReaderErrorController =
      StreamController<dynamic>.broadcast();
  final StreamController<dynamic> _onBufferFullController =
      StreamController<dynamic>.broadcast();

  // Public streams for listening to events
  Stream<dynamic> get onMemoryPressure => _onMemoryPressureController.stream;
  Stream<dynamic> get onImageReaderError =>
      _onImageReaderErrorController.stream;
  Stream<dynamic> get onBufferFull => _onBufferFullController.stream;

  /// Dispose resources
  void dispose() {
    _memoryEventSubscription?.cancel();
    _memoryEventSubscription = null;
    _onMemoryPressureController.close();
    _onImageReaderErrorController.close();
    _onBufferFullController.close();
    debugPrint('MemoryManagementService: Disposed resources');
  }
}
