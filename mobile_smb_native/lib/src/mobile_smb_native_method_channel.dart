import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'smb_file.dart';
import 'smb_connection_config.dart';
import 'mobile_smb_native_platform_interface.dart';
import 'smb_platform_service.dart';
import 'smb_playback_channel.dart';

/// An implementation of [MobileSmbNativePlatform] that uses method channels.
class MethodChannelMobileSmbNative extends MobileSmbNativePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('mobile_smb_native');

  @override
  Future<SmbPlaybackReader?> openPlaybackReader(
    SmbConnectionConfig config,
    String path,
  ) async => Platform.isAndroid ? SmbPlaybackChannel.open(config, path) : null;

  @override
  Future<bool> connect(SmbConnectionConfig config) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'connect',
        {
          'host': config.host,
          'port': config.port,
          'username': config.username,
          'password': config.password,
          'shareName': config.shareName,
          'timeoutMs': config.timeoutMs,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('SMB connection error: ${e.message}');
      return false;
    }
  }

  @override
  Future<bool> disconnect() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('disconnect');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('SMB disconnect error: ${e.message}');
      return false;
    }
  }

  @override
  Future<List<String>> listShares() async {
    try {
      final result =
          await methodChannel.invokeMethod<List<dynamic>>('listShares');
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      debugPrint('SMB listShares error: ${e.message}');
      return [];
    }
  }

  @override
  Future<List<SmbFile>> listDirectory(String path) async {
    try {
      final result = await methodChannel.invokeMethod<List<dynamic>>(
        'listDirectory',
        {'path': path},
      );
      if (result == null) return [];

      return result.map((item) {
        final map = Map<String, dynamic>.from(item);
        return SmbFile(
          name: map['name'] as String,
          path: map['path'] as String,
          size: map['size'] as int,
          lastModified: DateTime.fromMillisecondsSinceEpoch(
            map['lastModified'] as int,
          ),
          isDirectory: map['isDirectory'] as bool,
        );
      }).toList();
    } on PlatformException catch (e) {
      debugPrint('SMB listDirectory error: ${e.message}');
      return [];
    }
  }

  @override
  Future<List<int>> readFile(String path) async {
    try {
      final result = await methodChannel.invokeMethod<Uint8List>(
        'readFile',
        {'path': path},
      );
      if (result == null) {
        throw Exception('SMB readFile returned null for path: $path');
      }
      return result.toList();
    } on PlatformException catch (e) {
      debugPrint('SMB readFile error: ${e.message}');
      throw Exception('SMB readFile failed for path: $path - ${e.message}');
    }
  }

  @override
  Future<bool> writeFile(String path, List<int> data) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'writeFile',
        {
          'path': path,
          'data': Uint8List.fromList(data),
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('SMB writeFile error: ${e.message}');
      return false;
    }
  }

  @override
  Future<bool> delete(String path) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'delete',
        {'path': path},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('SMB delete error: ${e.message}');
      return false;
    }
  }

  @override
  Future<bool> createDirectory(String path) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'createDirectory',
        {'path': path},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('SMB createDirectory error: ${e.message}');
      return false;
    }
  }

  @override
  Future<bool> isConnected() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('isConnected');
      return result ?? false;
    } catch (e) {
      debugPrint('SMB isConnected error: $e');
      return false;
    }
  }

  @override
  Future<SmbFile?> getFileInfo(String path) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
          'getFileInfo',
          {'path': path},
        );
        if (result == null) {
          return null;
        }
        final map = Map<String, dynamic>.from(result);
        return SmbFile(
          name: map['name'] as String,
          path: map['path'] as String,
          size: map['size'] as int,
          lastModified: DateTime.fromMillisecondsSinceEpoch(
            map['lastModified'] as int,
          ),
          isDirectory: map['isDirectory'] as bool,
        );
      }

      final service = SmbPlatformService.instance;
      if (!service.isConnected) {
        return null;
      }

      // Fallback: list directory and locate file.
      final lastSlash = path.lastIndexOf('/');
      final parentPath = lastSlash > 0 ? path.substring(0, lastSlash) : '';
      final fileName = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;

      final files =
          await service.listDirectory(parentPath.isEmpty ? '/' : parentPath);
      return files.firstWhere(
        (file) => file.name == fileName,
        orElse: () => throw Exception('File not found'),
      );
    } catch (e) {
      debugPrint('SMB getFileInfo error: $e');
      return null;
    }
  }

  @override
  Stream<List<int>>? openFileStream(String path) {
    try {
      debugPrint('SMB openFileStream: Starting stream for path: $path');

      // On mobile platforms, use method channel streaming
      if (Platform.isAndroid || Platform.isIOS) {
        debugPrint(
            'SMB openFileStream: Using method channel streaming for mobile');
        // First start the native stream, then return the event channel stream
        return Stream.fromFuture(_startFileStreamOnNative(path)).asyncExpand(
            (_) => _createMobileFileStream(path) ?? const Stream.empty());
      }

      // Use the platform service for streaming on desktop
      final service = SmbPlatformService.instance;
      if (!service.isConnected) {
        debugPrint('SMB openFileStream: Not connected to SMB server');
        return null;
      }

      debugPrint(
          'SMB openFileStream: Creating stream using SmbPlatformService...');
      final stream = service.streamFile(path);
      if (stream == null) {
        debugPrint('SMB openFileStream: Failed to create stream');
        return null;
      }
      return stream.map((chunk) {
        return chunk.toList();
      }).handleError((error, stackTrace) {
        debugPrint('SMB openFileStream: Stream error: $error');
        debugPrint('SMB openFileStream: Stack trace: $stackTrace');
        throw error;
      });
    } catch (e) {
      debugPrint('SMB openFileStream error: $e');
      return null;
    }
  }

  Stream<List<int>>? _createMobileFileStream(String path) {
    try {
      debugPrint('SMB _createMobileFileStream: Starting for path: $path');

      // Create event channel for receiving stream data
      final sanitizedPath = path.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final channelName = 'mobile_smb_native/stream_$sanitizedPath';
      final eventChannel = EventChannel(channelName);

      debugPrint(
          'SMB _createMobileFileStream: Created event channel: $channelName');

      // Return a stream that starts the file stream when listened to
      return eventChannel.receiveBroadcastStream().asyncMap((data) async {
        if (data is List) {
          return List<int>.from(data);
        }
        return <int>[];
      }).handleError((error) {
        debugPrint('SMB _createMobileFileStream: Stream error: $error');
        throw error;
      });
    } catch (e) {
      debugPrint('SMB _createMobileFileStream error: $e');
      return null;
    }
  }

  Future<void> _startFileStreamOnNative(String path) async {
    try {
      debugPrint('SMB _startFileStreamOnNative: Starting for path: $path');
      await methodChannel.invokeMethod('startFileStream', {'path': path});
      debugPrint('SMB _startFileStreamOnNative: Successfully started stream');
    } catch (e) {
      debugPrint('SMB _startFileStreamOnNative error: $e');
      rethrow;
    }
  }

  @override
  Future<String> getSmbVersion() async {
    try {
      final result = await methodChannel.invokeMethod<String>('getSmbVersion');
      return result ?? 'Unknown';
    } on PlatformException catch (e) {
      debugPrint('SMB getSmbVersion error: ${e.message}');
      return 'Unknown';
    }
  }

  @override
  Future<String> getConnectionInfo() async {
    try {
      final result =
          await methodChannel.invokeMethod<String>('getConnectionInfo');
      return result ?? 'Not connected';
    } on PlatformException catch (e) {
      debugPrint('SMB getConnectionInfo error: ${e.message}');
      return 'Not connected';
    }
  }

  @override
  Future<int?> getNativeContext() async {
    try {
      final result = await methodChannel.invokeMethod<int>('getNativeContext');
      return result;
    } on PlatformException catch (e) {
      debugPrint('SMB getNativeContext error: ${e.message}');
      return null;
    }
  }

  @override
  Stream<List<int>>? openFileStreamOptimized(String path,
      {int chunkSize = 1024 * 1024}) {
    try {
      debugPrint(
          'SMB openFileStreamOptimized: Starting optimized stream for path: $path');
      debugPrint('SMB openFileStreamOptimized: Chunk size: $chunkSize bytes');

      // On mobile platforms, use method channel streaming with optimized settings
      if (Platform.isAndroid || Platform.isIOS) {
        debugPrint(
            'SMB openFileStreamOptimized: Using optimized method channel streaming for mobile');
        // First start the native optimized stream, then return the event channel stream
        return Stream.fromFuture(
                _startOptimizedFileStreamOnNative(path, chunkSize))
            .asyncExpand((_) =>
                _createOptimizedMobileFileStream(path, chunkSize) ??
                const Stream.empty());
      }

      // Use the platform service for streaming on desktop
      final service = SmbPlatformService.instance;
      if (!service.isConnected) {
        debugPrint('SMB openFileStreamOptimized: Not connected to SMB server');
        return null;
      }

      debugPrint(
          'SMB openFileStreamOptimized: Creating optimized stream using SmbPlatformService...');
      final stream = service.streamFile(path);
      if (stream == null) {
        debugPrint('SMB openFileStreamOptimized: Failed to create stream');
        return null;
      }
      return stream.map((chunk) {
        return chunk.toList();
      }).handleError((error, stackTrace) {
        debugPrint('SMB openFileStreamOptimized: Stream error: $error');
        debugPrint('SMB openFileStreamOptimized: Stack trace: $stackTrace');
        throw error;
      });
    } catch (e) {
      debugPrint('SMB openFileStreamOptimized error: $e');
      return null;
    }
  }

  @override
  Stream<List<int>>? seekFileStreamOptimized(String path, int offset,
      {int chunkSize = 1024 * 1024}) {
    try {
      debugPrint(
          'SMB seekFileStreamOptimized: Starting seek stream for path: $path at offset: $offset');
      debugPrint('SMB seekFileStreamOptimized: Chunk size: $chunkSize bytes');

      // On mobile platforms, use method channel streaming with seek support
      if (Platform.isAndroid || Platform.isIOS) {
        debugPrint(
            'SMB seekFileStreamOptimized: Using optimized method channel streaming with seek for mobile');
        // First start the native seek stream, then return the event channel stream
        return Stream.fromFuture(
                _startSeekFileStreamOnNative(path, offset, chunkSize))
            .asyncExpand((_) =>
                _createSeekMobileFileStream(path, offset, chunkSize) ??
                const Stream.empty());
      }

      // Use the platform service for streaming on desktop with seek
      final service = SmbPlatformService.instance;
      if (!service.isConnected) {
        debugPrint('SMB seekFileStreamOptimized: Not connected to SMB server');
        return null;
      }

      debugPrint(
          'SMB seekFileStreamOptimized: Creating seek stream using SmbPlatformService...');
      final stream = service.seekFileStream(path, offset);
      if (stream == null) {
        debugPrint('SMB seekFileStreamOptimized: Failed to create seek stream');
        return null;
      }
      return stream.map((chunk) {
        return chunk.toList();
      }).handleError((error, stackTrace) {
        debugPrint('SMB seekFileStreamOptimized: Stream error: $error');
        debugPrint('SMB seekFileStreamOptimized: Stack trace: $stackTrace');
        throw error;
      });
    } catch (e) {
      debugPrint('SMB seekFileStreamOptimized error: $e');
      return null;
    }
  }

  Stream<List<int>>? _createOptimizedMobileFileStream(
      String path, int chunkSize) {
    try {
      debugPrint(
          'SMB _createOptimizedMobileFileStream: Starting for path: $path');
      debugPrint(
          'SMB _createOptimizedMobileFileStream: Chunk size: $chunkSize bytes');

      // Create event channel for receiving optimized stream data
      final sanitizedPath = path.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final channelName = 'mobile_smb_native/optimized_stream_$sanitizedPath';
      final eventChannel = EventChannel(channelName);

      debugPrint(
          'SMB _createOptimizedMobileFileStream: Created optimized event channel: $channelName');

      // Return a stream that starts the optimized file stream when listened to
      return eventChannel.receiveBroadcastStream().asyncMap((data) async {
        if (data is List) {
          // Convert List to List<int> more efficiently
          return data.cast<int>();
        } else if (data is Uint8List) {
          // Handle ByteArray data directly
          return data.toList();
        }
        return <int>[];
      }).handleError((error) {
        debugPrint(
            'SMB _createOptimizedMobileFileStream: Stream error: $error');
        throw error;
      }).timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('SMB _createOptimizedMobileFileStream error: $e');
      return null;
    }
  }

  Future<void> _startOptimizedFileStreamOnNative(
      String path, int chunkSize) async {
    try {
      debugPrint(
          'SMB _startOptimizedFileStreamOnNative: Starting for path: $path');
      debugPrint(
          'SMB _startOptimizedFileStreamOnNative: Chunk size: $chunkSize bytes');
      await methodChannel.invokeMethod('startOptimizedFileStream', {
        'path': path,
        'chunkSize': chunkSize,
      });
      debugPrint(
          'SMB _startOptimizedFileStreamOnNative: Successfully started optimized stream');
    } catch (e) {
      debugPrint('SMB _startOptimizedFileStreamOnNative error: $e');
      rethrow;
    }
  }

  Stream<List<int>>? _createSeekMobileFileStream(
      String path, int offset, int chunkSize) {
    try {
      debugPrint(
          'SMB _createSeekMobileFileStream: Starting for path: $path at offset: $offset');
      debugPrint(
          'SMB _createSeekMobileFileStream: Chunk size: $chunkSize bytes');

      // Create event channel for receiving seek stream data
      final sanitizedPath = path.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final channelName = 'mobile_smb_native/seek_stream_$sanitizedPath';
      final eventChannel = EventChannel(channelName);

      debugPrint(
          'SMB _createSeekMobileFileStream: Created seek event channel: $channelName');

      // Return a stream that starts the seek stream when listened to
      return eventChannel.receiveBroadcastStream().asyncMap((data) async {
        if (data is Uint8List) {
          return data.toList();
        } else if (data is List<int>) {
          return data;
        } else if (data is List) {
          return List<int>.from(data);
        }
        return <int>[];
      }).handleError((error) {
        debugPrint('SMB _createSeekMobileFileStream: Stream error: $error');
        throw error;
      });
    } catch (e) {
      debugPrint('SMB _createSeekMobileFileStream error: $e');
      return null;
    }
  }

  Future<void> _startSeekFileStreamOnNative(
      String path, int offset, int chunkSize) async {
    try {
      debugPrint(
          'SMB _startSeekFileStreamOnNative: Starting for path: $path at offset: $offset');
      debugPrint(
          'SMB _startSeekFileStreamOnNative: Chunk size: $chunkSize bytes');
      await methodChannel.invokeMethod('seekFileStream', {
        'path': path,
        'offset': offset,
        'chunkSize': chunkSize,
      });
      debugPrint(
          'SMB _startSeekFileStreamOnNative: Successfully started seek stream');
    } catch (e) {
      debugPrint('SMB _startSeekFileStreamOnNative error: $e');
      rethrow;
    }
  }
}
