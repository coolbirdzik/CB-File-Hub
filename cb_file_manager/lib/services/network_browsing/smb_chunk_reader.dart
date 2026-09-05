import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:mobile_smb_native/mobile_smb_native.dart';

/// Configuration for the [SmbChunkReader].
///
/// These values are inspired by VLC and typical media-streaming defaults. They
/// are **not** performance-critical for a stub implementation – they merely
/// need to exist so that the rest of the project can compile. Feel free to
/// tweak the defaults later when a real reader is implemented.
class SmbChunkReaderConfig {
  final int maxConnections;
  final int chunkSize;
  final int readAheadSize;
  final int maxReadSize;
  final int socketTimeoutMs;
  final int retryAttempts;
  final bool enablePipelining;
  final bool enableLargeMtu;

  const SmbChunkReaderConfig({
    this.maxConnections = 4,
    this.chunkSize = 256 * 1024,
    this.readAheadSize = 1024 * 1024,
    this.maxReadSize = 1024 * 1024,
    this.socketTimeoutMs = 5000,
    this.retryAttempts = 3,
    this.enablePipelining = true,
    this.enableLargeMtu = true,
  });
}

/// A single chunk of data read from an SMB share.
class SmbChunk {
  final int offset;
  final Uint8List data;
  final DateTime timestamp;
  final bool isLastChunk;

  SmbChunk({
    required this.offset,
    required this.data,
    DateTime? timestamp,
    this.isLastChunk = false,
  }) : timestamp = timestamp ?? DateTime.now();

  int get size => data.length;
  int get endOffset => offset + size;
}

/// **Stub** implementation of an SMB chunk reader.
///
/// The real implementation should perform parallel / pipelined reads via
/// [`MobileSmbClient`].  For now we only supply the API surface that the rest
/// of the app expects so that the project can be built and run without compile
/// errors.  All methods log a warning and do their best to fail gracefully.
class SmbChunkReader {
  final SmbChunkReaderConfig config;
  final MobileSmbClient _client = MobileSmbClient();

  bool _initialized = false;
  String? _currentFilePath;
  int? _fileSize;

  SmbChunkReader({SmbChunkReaderConfig? config})
    : config = config ?? const SmbChunkReaderConfig();

  /// Indicates whether [initialize] has completed successfully.
  bool get isInitialized => _initialized;
  bool get isConnected => _initialized;

  /// Size of the currently opened file, if known.
  int? get fileSize => _fileSize;

  /// Initialise reader for the provided connection.  Returns `true` on success.
  Future<bool> initialize(SmbConnectionConfig connection) async {
    try {
      final connected = await _client.connect(connection);
      if (!connected) {
        debugPrint('SmbChunkReader: failed to connect to SMB server');
        return false;
      }
      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('SmbChunkReader: initialization error: $e');
      return false;
    }
  }

  /// Clean up all resources.
  Future<void> dispose() async {
    await _client.disconnect();
    _initialized = false;
  }

  /// Set the file to be used for subsequent [readChunk] calls.
  Future<bool> setFile(String smbPath) async {
    if (!_initialized) return false;
    _currentFilePath = smbPath;
    try {
      final fileInfo = await _client.getFileInfo(smbPath);
      _fileSize = fileInfo?.size;
    } catch (_) {
      _fileSize = null;
    }
    return true;
  }

  /// Read a chunk of size [length] starting at [offset].
  ///
  /// This implementation uses the `seekFileStreamOptimized` method from `mobile_smb_native`
  /// to perform a true streaming read.
  Future<SmbChunk?> readChunk(int offset, int length) async {
    if (!_initialized || _currentFilePath == null) {
      debugPrint('SmbChunkReader: not initialized or file not set');
      return null;
    }

    try {
      final stream = _client.seekFileStreamOptimized(
        _currentFilePath!,
        offset,
        chunkSize: length,
      );
      if (stream == null) {
        debugPrint('SmbChunkReader: failed to open optimized stream');
        return null;
      }

      final bytes = BytesBuilder(copy: false);
      var remaining = length;
      await for (final chunk in stream) {
        if (chunk.isEmpty) {
          continue;
        }
        if (chunk.length >= remaining) {
          bytes.add(chunk.sublist(0, remaining));
          remaining = 0;
          break;
        }
        bytes.add(chunk);
        remaining -= chunk.length;
        if (remaining <= 0) {
          break;
        }
      }

      final data = bytes.takeBytes();
      if (data.isEmpty) return null;

      final isLast = _fileSize != null && offset + data.length >= _fileSize!;
      return SmbChunk(
        offset: offset,
        data: Uint8List.fromList(data),
        isLastChunk: isLast,
      );
    } catch (e) {
      debugPrint('SmbChunkReader: readChunk error: $e');
      return null;
    }
  }

  int get availableWorkerCount => 0;
  String? get currentPath => _currentFilePath;

  /// Read multiple chunks in parallel.
  ///
  /// Each map in [requests] must contain `offset` and `size` keys.
  /// This stub implementation simply issues sequential [readChunk] calls.
  Future<List<SmbChunk>> readChunksParallel(
    List<Map<String, int>> requests,
  ) async {
    final results = <SmbChunk>[];
    for (final req in requests) {
      final offset = req['offset'] ?? 0;
      final size = req['size'] ?? config.chunkSize;
      final chunk = await readChunk(offset, size);
      if (chunk != null) results.add(chunk);
    }
    return results;
  }
}
