import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'smb_chunk_reader.dart';

/// Configuration for prefetch controller
class PrefetchControllerConfig {
  final int bufferSize; // Total buffer size in bytes
  final int prefetchSize; // How much to prefetch ahead
  final int maxPrefetchChunks; // Maximum number of chunks to prefetch
  final Duration prefetchTimeout; // Timeout for prefetch operations
  final bool enableCircularBuffer; // Use circular buffer like VLC

  const PrefetchControllerConfig({
    this.bufferSize = 5 * 1024 * 1024, // 5MB buffer
    this.prefetchSize = 2 * 1024 * 1024, // 2MB prefetch
    this.maxPrefetchChunks = 8,
    this.prefetchTimeout = const Duration(seconds: 10),
    this.enableCircularBuffer = true,
  });
}

/// Circular buffer implementation for efficient memory management
class CircularBuffer {
  final int capacity;
  final Map<int, SmbChunk> _chunks = {};
  int _startOffset = 0;
  int _endOffset = 0;
  int _totalSize = 0;

  CircularBuffer(this.capacity);

  void add(SmbChunk chunk) {
    // Remove old chunks if buffer is full
    while (_totalSize + chunk.size > capacity) {
      _removeOldest();
    }

    _chunks[chunk.offset] = chunk;
    _totalSize += chunk.size;

    if (_endOffset < chunk.endOffset) {
      _endOffset = chunk.endOffset;
    }

    if (_startOffset == 0) {
      _startOffset = chunk.offset;
    }
  }

  SmbChunk? get(int offset) {
    return _chunks[offset];
  }

  SmbChunk? getContaining(int offset) {
    for (final chunk in _chunks.values) {
      if (offset >= chunk.offset && offset < chunk.endOffset) {
        return chunk;
      }
    }
    return null;
  }

  List<SmbChunk> getRange(int startOffset, int endOffset) {
    final result = <SmbChunk>[];
    for (final chunk in _chunks.values) {
      if (chunk.offset < endOffset && chunk.endOffset > startOffset) {
        result.add(chunk);
      }
    }
    result.sort((a, b) => a.offset.compareTo(b.offset));
    return result;
  }

  void _removeOldest() {
    if (_chunks.isEmpty) return;

    final oldestOffset = _chunks.keys.reduce((a, b) => a < b ? a : b);
    final oldestChunk = _chunks[oldestOffset]!;

    _chunks.remove(oldestOffset);
    _totalSize -= oldestChunk.size;

    if (_startOffset == oldestOffset) {
      _startOffset = _chunks.keys.isEmpty
          ? 0
          : _chunks.keys.reduce((a, b) => a < b ? a : b);
    }
  }

  void clear() {
    _chunks.clear();
    _startOffset = 0;
    _endOffset = 0;
    _totalSize = 0;
  }

  int get size => _totalSize;
  int get count => _chunks.length;
  bool get isEmpty => _chunks.isEmpty;
  int get startOffset => _startOffset;
  int get endOffset => _endOffset;
}

/// Main prefetch controller for SMB streaming optimization
class PrefetchController {
  final SmbChunkReader _reader;
  final PrefetchControllerConfig _config;
  final CircularBuffer _buffer;

  int _currentPosition = 0;
  bool _isPrefetching = false;
  bool _isDisposed = false;
  Timer? _prefetchTimer;
  final Queue<Future<void>> _prefetchTasks = Queue();

  // Statistics
  int _totalPrefetched = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;

  PrefetchController({required this._reader, PrefetchControllerConfig? config})
    : _config = config ?? const PrefetchControllerConfig(),
      _buffer = CircularBuffer(config?.bufferSize ?? 5 * 1024 * 1024);

  /// Initialize the prefetch controller
  Future<bool> initialize() async {
    if (!_reader.isInitialized) {
      debugPrint('PrefetchController: Reader not initialized');
      return false;
    }

    debugPrint(
      'PrefetchController: Initialized with ${_config.bufferSize} bytes buffer',
    );
    return true;
  }

  /// Set the current playback position and trigger prefetch
  Future<void> setPosition(int position) async {
    if (_isDisposed) return;

    _currentPosition = position;
    debugPrint('PrefetchController: Position set to $position');

    // Check if we need to prefetch
    if (_shouldPrefetch()) {
      _startPrefetch();
    }
  }

  /// Read data from the current position
  Future<Uint8List?> read(int length) async {
    if (_isDisposed) return null;

    final startTime = DateTime.now();

    // First, try to get data from buffer
    final cachedData = _readFromBuffer(_currentPosition, length);
    if (cachedData != null) {
      _cacheHits++;
      _currentPosition += cachedData.length;
      debugPrint(
        'PrefetchController: Cache hit - read ${cachedData.length} bytes',
      );
      return cachedData;
    }

    _cacheMisses++;
    debugPrint('PrefetchController: Cache miss - reading from network');

    // If not in buffer, read directly from network
    final chunk = await _reader.readChunk(_currentPosition, length);
    if (chunk != null) {
      _currentPosition += chunk.size;

      // Add to buffer for future use
      _buffer.add(chunk);

      final duration = DateTime.now().difference(startTime);
      debugPrint(
        'PrefetchController: Network read ${chunk.size} bytes in ${duration.inMilliseconds}ms',
      );

      return chunk.data;
    }

    // If we get here, it means we've reached the end of file
    // Check if we're at the end of the file
    final fileSize = _reader.fileSize;
    if (fileSize != null && _currentPosition >= fileSize) {
      debugPrint(
        'PrefetchController: Reached end of file at position $_currentPosition',
      );
      return null; // End of file
    }

    // If not at end of file, return empty data to indicate temporary unavailability
    debugPrint(
      'PrefetchController: No data available at position $_currentPosition, retrying...',
    );
    return Uint8List(0); // Empty data, not null
  }

  /// Read data from a specific offset (for seeking)
  Future<Uint8List?> readAt(int offset, int length) async {
    if (_isDisposed) return null;

    // Clear buffer if seeking to a distant position
    if ((offset - _currentPosition).abs() > _config.bufferSize) {
      debugPrint('PrefetchController: Large seek detected, clearing buffer');
      _buffer.clear();
      _currentPosition = offset;
    } else {
      _currentPosition = offset;
    }

    return await read(length);
  }

  /// Seek to a new position
  Future<void> seek(int position) async {
    if (_isDisposed) return;

    debugPrint('PrefetchController: Seeking to position $position');

    // Cancel ongoing prefetch
    _cancelPrefetch();

    // Clear buffer if seeking to a distant position
    if ((position - _currentPosition).abs() > _config.bufferSize) {
      _buffer.clear();
    }

    _currentPosition = position;

    // Start prefetch from new position
    _startPrefetch();
  }

  /// Start prefetching data ahead of current position
  void _startPrefetch() {
    if (_isPrefetching || _isDisposed) return;

    _isPrefetching = true;
    _prefetchTimer?.cancel();

    _prefetchTimer = Timer(const Duration(milliseconds: 100), () {
      _performPrefetch();
    });
  }

  /// Perform the actual prefetch operation
  Future<void> _performPrefetch() async {
    if (_isDisposed) return;

    try {
      final prefetchStart = _currentPosition + _buffer.size;
      final prefetchEnd = prefetchStart + _config.prefetchSize;

      if (prefetchStart >= (_reader.fileSize ?? 0)) {
        _isPrefetching = false;
        return;
      }

      debugPrint(
        'PrefetchController: Prefetching from $prefetchStart to $prefetchEnd',
      );

      // Calculate chunk requests for prefetch
      final chunkRequests = <Map<String, int>>[];
      int currentOffset = prefetchStart;
      int chunksRequested = 0;

      while (currentOffset < prefetchEnd &&
          chunksRequested < _config.maxPrefetchChunks &&
          currentOffset < (_reader.fileSize ?? 0)) {
        const chunkSize = 256 * 1024; // 256KB default chunk size
        final remainingSize = prefetchEnd - currentOffset;
        final actualChunkSize = remainingSize < chunkSize
            ? remainingSize
            : chunkSize;

        chunkRequests.add({'offset': currentOffset, 'size': actualChunkSize});

        currentOffset += actualChunkSize;
        chunksRequested++;
      }

      // Read chunks in parallel
      final chunks = await _reader.readChunksParallel(chunkRequests);

      // Add chunks to buffer
      for (final chunk in chunks) {
        _buffer.add(chunk);
        _totalPrefetched += chunk.size;
      }

      debugPrint(
        'PrefetchController: Prefetched ${chunks.length} chunks ($_totalPrefetched bytes total)',
      );
    } catch (e) {
      debugPrint('PrefetchController: Prefetch error: $e');
    } finally {
      _isPrefetching = false;

      // Continue prefetching if needed
      if (_shouldPrefetch()) {
        _startPrefetch();
      }
    }
  }

  /// Check if prefetch is needed
  bool _shouldPrefetch() {
    if (_isDisposed || _reader.fileSize == null) return false;

    final bufferAhead = _buffer.endOffset - _currentPosition;
    return bufferAhead < _config.prefetchSize &&
        _currentPosition < _reader.fileSize! &&
        !_isPrefetching;
  }

  /// Read data from buffer
  Uint8List? _readFromBuffer(int offset, int length) {
    final chunk = _buffer.getContaining(offset);
    if (chunk == null) return null;

    final relativeOffset = offset - chunk.offset;
    final availableLength = chunk.size - relativeOffset;
    final actualLength = length < availableLength ? length : availableLength;

    return chunk.data.sublist(relativeOffset, relativeOffset + actualLength);
  }

  /// Cancel ongoing prefetch operations
  void _cancelPrefetch() {
    _isPrefetching = false;
    _prefetchTimer?.cancel();

    // Cancel pending prefetch tasks
    while (_prefetchTasks.isNotEmpty) {
      _prefetchTasks.removeFirst();
      // Note: We can't actually cancel the task, but we can stop waiting for it
    }
  }

  /// Get current position
  int get currentPosition => _currentPosition;

  /// Get buffer statistics
  Map<String, dynamic> get bufferStats {
    return {
      'bufferSize': _buffer.size,
      'bufferCount': _buffer.count,
      'startOffset': _buffer.startOffset,
      'endOffset': _buffer.endOffset,
      'currentPosition': _currentPosition,
      'isPrefetching': _isPrefetching,
      'totalPrefetched': _totalPrefetched,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'cacheHitRate': _cacheHits + _cacheMisses > 0
          ? ((_cacheHits / (_cacheHits + _cacheMisses)) * 100).toStringAsFixed(
              1,
            )
          : '0.0',
    };
  }

  /// Reset statistics
  void resetStats() {
    _totalPrefetched = 0;
    _cacheHits = 0;
    _cacheMisses = 0;
  }

  /// Clear buffer
  void clearBuffer() {
    _buffer.clear();
    debugPrint('PrefetchController: Buffer cleared');
  }

  /// Dispose resources
  Future<void> dispose() async {
    _isDisposed = true;
    _cancelPrefetch();
    _buffer.clear();
    debugPrint('PrefetchController: Disposed');
  }
}
