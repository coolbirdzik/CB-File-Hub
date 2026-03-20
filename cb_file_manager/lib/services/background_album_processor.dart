import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as path;
import 'album_file_scanner.dart';
import '../utils/app_logger.dart';

class BackgroundAlbumProcessor {
  static BackgroundAlbumProcessor? _instance;
  static BackgroundAlbumProcessor get instance =>
      _instance ??= BackgroundAlbumProcessor._();

  BackgroundAlbumProcessor._();

  final Map<String, StreamSubscription> _watchers = {};
  final Map<String, Timer> _debounceTimers = {};

  /// Start monitoring directories
  Future<void> startMonitoring() async {
    AppLogger.info('Background album processor started');
  }

  /// Stop all monitoring
  Future<void> stopMonitoring() async {
    for (final subscription in _watchers.values) {
      await subscription.cancel();
    }
    _watchers.clear();

    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }

  /// Start watching a directory
  Future<void> startWatchingDirectory(
      String dirPath, Function(String) onFileAdded) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    // Cancel existing watcher if any
    await _watchers[dirPath]?.cancel();

    // Start new watcher
    _watchers[dirPath] = dir.watch(recursive: true).listen(
          (event) => _handleFileSystemEvent(dirPath, event, onFileAdded),
          onError: (error) =>
              AppLogger.error('Error watching $dirPath', error: error),
        );
  }

  /// Handle file system events
  void _handleFileSystemEvent(
      String dirPath, FileSystemEvent event, Function(String) onFileAdded) {
    if (event.type == FileSystemEvent.create ||
        event.type == FileSystemEvent.modify) {
      // Debounce to avoid processing too many events
      final key = '${dirPath}_${event.path}';
      _debounceTimers[key]?.cancel();
      _debounceTimers[key] = Timer(const Duration(milliseconds: 500), () {
        if (_isMediaFile(event.path)) {
          onFileAdded(event.path);
        }
        _debounceTimers.remove(key);
      });
    }
  }

  /// Check if file is a media file
  bool _isMediaFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    const mediaExtensions = {
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.tiff',
      '.tif',
      '.mp4',
      '.avi',
      '.mov',
      '.wmv',
      '.flv',
      '.webm',
      '.mkv',
      '.m4v'
    };
    return mediaExtensions.contains(extension);
  }

  /// Process files in background using isolate
  Future<void> processFilesInBackground(
      List<String> filePaths, int albumId) async {
    final receivePort = ReceivePort();

    await Isolate.spawn(
      _backgroundFileProcessor,
      {
        'sendPort': receivePort.sendPort,
        'filePaths': filePaths,
        // albumId is passed but not used in isolate
      },
    );

    // Wait for completion
    final result = await receivePort.first;
    AppLogger.info('Background processing completed: $result');
  }

  /// Background isolate function
  static void _backgroundFileProcessor(Map<String, dynamic> params) async {
    final sendPort = params['sendPort'] as SendPort;
    final filePaths = params['filePaths'] as List<String>;
    // albumId parameter is available but not used in this isolate

    try {
      // Process files without blocking UI
      for (final filePath in filePaths) {
        final file = File(filePath);
        if (await file.exists()) {
          // Validate file, get metadata, etc.
          // This runs in background without affecting UI
          await Future.delayed(
              const Duration(milliseconds: 10)); // Simulate work
        }
      }

      sendPort.send({'success': true, 'processedCount': filePaths.length});
    } catch (e) {
      sendPort.send({'success': false, 'error': e.toString()});
    }
  }

  /// Stop watching a directory
  Future<void> stopWatchingDirectory(String dirPath) async {
    await _watchers[dirPath]?.cancel();
    _watchers.remove(dirPath);
  }

  /// Clear cache for album when files change
  void clearAlbumCache(int albumId) {
    AlbumFileScanner.instance.clearCache(albumId);
  }

  /// Add album to monitoring (simplified)
  Future<void> addAlbumToMonitoring(
      int albumId, List<String> directories) async {
    for (final dir in directories) {
      await startWatchingDirectory(dir, (filePath) {
        // When new file detected, clear cache so it appears in next scan
        clearAlbumCache(albumId);
        AppLogger.debug(
            'New file detected in album $albumId: ${path.basename(filePath)}');
      });
    }
  }

  /// Remove album from monitoring
  Future<void> removeAlbumFromMonitoring(List<String> directories) async {
    for (final dir in directories) {
      await stopWatchingDirectory(dir);
    }
  }

  /// Refresh monitoring (restart all watchers)
  Future<void> refreshMonitoring() async {
    await stopMonitoring();
    await startMonitoring();
  }
}
