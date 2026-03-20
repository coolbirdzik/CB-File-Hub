import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/objectbox/album.dart';
import '../models/objectbox/album_config.dart';
import 'album_file_scanner.dart';
import '../utils/app_logger.dart';

class LazyAlbumScanner {
  static LazyAlbumScanner? _instance;
  static LazyAlbumScanner get instance => _instance ??= LazyAlbumScanner._();

  LazyAlbumScanner._();

  final Map<int, StreamController<List<FileInfo>>> _albumStreams = {};
  final Map<int, List<FileInfo>> _loadedFiles = {};
  final Map<int, bool> _isScanning = {};
  final Map<int, Timer> _scanTimers = {};

  /// Get lazy stream of album files - returns immediately with cached files
  /// and continues loading more files in background
  Stream<List<FileInfo>> getLazyAlbumFiles(Album album, AlbumConfig config) {
    final albumId = album.id;

    // Create stream if not exists
    if (!_albumStreams.containsKey(albumId)) {
      _albumStreams[albumId] = StreamController<List<FileInfo>>.broadcast();
      _loadedFiles[albumId] = [];
    }

    // Return cached files immediately if available
    if (_loadedFiles[albumId]!.isNotEmpty) {
      _albumStreams[albumId]!.add(List.from(_loadedFiles[albumId]!));
    }

    // Start lazy scanning if not already scanning
    if (_isScanning[albumId] != true) {
      _startLazyScanning(album, config);
    }

    return _albumStreams[albumId]!.stream;
  }

  /// Start lazy scanning - load files in small batches
  void _startLazyScanning(Album album, AlbumConfig config) async {
    final albumId = album.id;
    _isScanning[albumId] = true;

    try {
      final directories = config.directoriesList;
      final extensions = config.fileExtensionsList;
      final excludePatterns = config.excludePatternsList;

      // Clear previous results
      _loadedFiles[albumId] = [];

      int totalProcessed = 0;
      const delayBetweenBatches =
          Duration(milliseconds: 10); // Very small delay

      for (final dirPath in directories) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list(
          recursive: config.includeSubdirectories,
          followLinks: false,
        )) {
          if (entity is File) {
            final fileInfo =
                await _processFile(entity, extensions, excludePatterns);
            if (fileInfo != null) {
              totalProcessed++;

              // Add file immediately - show in UI right away
              _addSingleFileToAlbum(albumId, fileInfo, config);

              // Yield control to UI thread every file to keep UI responsive
              await Future.delayed(delayBetweenBatches);

              // Check if we should stop (max file limit)
              if (totalProcessed >= config.maxFileCount) break;
            }
          }
        }

        if (totalProcessed >= config.maxFileCount) break;
      }

      // Mark scanning as complete
      _isScanning[albumId] = false;

      // Update config with final stats
      config.updateScanStats(_loadedFiles[albumId]!.length);
    } catch (e) {
      _isScanning[albumId] = false;
      AppLogger.error('Lazy scanning error for album ${album.name}', error: e);
    }
  }

  /// Add single file to album and notify listeners immediately
  void _addSingleFileToAlbum(
      int albumId, FileInfo fileInfo, AlbumConfig config) {
    // Add to loaded files immediately - no sorting to be faster
    _loadedFiles[albumId]!.add(fileInfo);

    // Notify listeners with updated list immediately
    if (_albumStreams.containsKey(albumId)) {
      _albumStreams[albumId]!.add(List.from(_loadedFiles[albumId]!));
    }
  }

  /// Process a single file
  Future<FileInfo?> _processFile(
      File file, List<String> extensions, List<String> excludePatterns) async {
    final fileName = path.basename(file.path);
    final extension = path.extension(file.path).toLowerCase();

    // Check extension
    if (extensions.isNotEmpty && !extensions.contains(extension)) {
      return null;
    }

    // Check exclude patterns
    for (final pattern in excludePatterns) {
      if (pattern.isNotEmpty) {
        try {
          final regex = RegExp(pattern, caseSensitive: false);
          if (regex.hasMatch(fileName)) {
            return null;
          }
        } catch (e) {
          // Invalid regex, skip
        }
      }
    }

    try {
      final stat = await file.stat();
      return FileInfo(
        path: file.path,
        name: fileName,
        size: stat.size,
        modifiedTime: stat.modified,
        isImage: _isImageFile(extension),
        isVideo: _isVideoFile(extension),
      );
    } catch (e) {
      return null;
    }
  }

  /// Check if file is image
  bool _isImageFile(String extension) {
    const imageExtensions = {
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.tiff',
      '.tif'
    };
    return imageExtensions.contains(extension);
  }

  /// Check if file is video
  bool _isVideoFile(String extension) {
    const videoExtensions = {
      '.mp4',
      '.avi',
      '.mov',
      '.wmv',
      '.flv',
      '.webm',
      '.mkv',
      '.m4v'
    };
    return videoExtensions.contains(extension);
  }

  /// Get immediate files (cached only, no scanning)
  List<FileInfo> getImmediateFiles(int albumId) {
    return List.from(_loadedFiles[albumId] ?? []);
  }

  /// Check if album is currently scanning
  bool isScanning(int albumId) {
    return _isScanning[albumId] == true;
  }

  /// Get scan progress (0.0 to 1.0)
  double getScanProgress(int albumId, AlbumConfig config) {
    final loaded = _loadedFiles[albumId]?.length ?? 0;
    final max = config.maxFileCount;
    return (loaded / max).clamp(0.0, 1.0);
  }

  /// Force refresh album (clear cache and restart scanning)
  void refreshAlbum(int albumId) {
    // Stop current scanning
    _isScanning[albumId] = false;
    _scanTimers[albumId]?.cancel();

    // Clear cache
    _loadedFiles[albumId] = [];

    // Notify listeners with empty list
    if (_albumStreams.containsKey(albumId)) {
      _albumStreams[albumId]!.add([]);
    }
  }

  /// Stop scanning for album
  void stopScanning(int albumId) {
    _isScanning[albumId] = false;
    _scanTimers[albumId]?.cancel();
  }

  /// Dispose album stream
  void disposeAlbum(int albumId) {
    _albumStreams[albumId]?.close();
    _albumStreams.remove(albumId);
    _loadedFiles.remove(albumId);
    _isScanning.remove(albumId);
    _scanTimers[albumId]?.cancel();
    _scanTimers.remove(albumId);
  }

  /// Dispose all resources
  void dispose() {
    for (final controller in _albumStreams.values) {
      controller.close();
    }
    _albumStreams.clear();
    _loadedFiles.clear();
    _isScanning.clear();

    for (final timer in _scanTimers.values) {
      timer.cancel();
    }
    _scanTimers.clear();
  }
}
