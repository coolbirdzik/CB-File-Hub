import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as path;
import '../models/objectbox/album.dart';
import '../models/objectbox/album_config.dart';

class AlbumFileScanner {
  static AlbumFileScanner? _instance;
  static AlbumFileScanner get instance => _instance ??= AlbumFileScanner._();

  AlbumFileScanner._();

  final Map<int, List<FileInfo>> _cachedFiles = {};
  final Map<int, DateTime> _lastScanTime = {};

  /// Scan album directories and return file list based on config
  Future<List<FileInfo>> scanAlbumFiles(Album album, AlbumConfig config) async {
    // Check cache first
    final lastScan = _lastScanTime[album.id];
    if (lastScan != null &&
        DateTime.now().difference(lastScan).inMinutes < 5 &&
        _cachedFiles.containsKey(album.id)) {
      return _cachedFiles[album.id]!;
    }

    // Scan in background if many directories
    final directories = config.directoriesList;
    if (directories.length > 3) {
      return await _scanInBackground(album, config);
    } else {
      return await _scanDirectly(album, config);
    }
  }

  /// Scan files directly in main thread (for small albums)
  Future<List<FileInfo>> _scanDirectly(Album album, AlbumConfig config) async {
    final files = <FileInfo>[];
    final directories = config.directoriesList;
    final extensions = config.fileExtensionsList;
    final excludePatterns = config.excludePatternsList;

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
            files.add(fileInfo);

            // Limit file count
            if (files.length >= config.maxFileCount) break;
          }
        }
      }

      if (files.length >= config.maxFileCount) break;
    }

    // Sort files
    _sortFiles(files, config.sortBy, config.sortAscending);

    // Cache results
    _cachedFiles[album.id] = files;
    _lastScanTime[album.id] = DateTime.now();

    return files;
  }

  /// Scan files in background isolate (for large albums)
  Future<List<FileInfo>> _scanInBackground(
      Album album, AlbumConfig config) async {
    final receivePort = ReceivePort();

    await Isolate.spawn(
      _backgroundScanner,
      {
        'sendPort': receivePort.sendPort,
        'albumId': album.id,
        'directories': config.directoriesList,
        'extensions': config.fileExtensionsList,
        'excludePatterns': config.excludePatternsList,
        'includeSubdirectories': config.includeSubdirectories,
        'maxFileCount': config.maxFileCount,
        'sortBy': config.sortBy,
        'sortAscending': config.sortAscending,
      },
    );

    final result = await receivePort.first as Map<String, dynamic>;

    if (result['success'] == true) {
      final filesData = result['files'] as List<Map<String, dynamic>>;
      final files = filesData.map((data) => FileInfo.fromMap(data)).toList();

      // Cache results
      _cachedFiles[album.id] = files;
      _lastScanTime[album.id] = DateTime.now();

      return files;
    } else {
      throw Exception('Background scan failed: ${result['error']}');
    }
  }

  /// Background isolate scanner
  static void _backgroundScanner(Map<String, dynamic> params) async {
    final sendPort = params['sendPort'] as SendPort;

    try {
      final directories = params['directories'] as List<String>;
      final extensions = params['extensions'] as List<String>;
      final excludePatterns = params['excludePatterns'] as List<String>;
      final includeSubdirectories = params['includeSubdirectories'] as bool;
      final maxFileCount = params['maxFileCount'] as int;
      final sortBy = params['sortBy'] as String;
      final sortAscending = params['sortAscending'] as bool;

      final files = <FileInfo>[];

      for (final dirPath in directories) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list(
          recursive: includeSubdirectories,
          followLinks: false,
        )) {
          if (entity is File) {
            final fileInfo =
                await _processFileStatic(entity, extensions, excludePatterns);
            if (fileInfo != null) {
              files.add(fileInfo);

              if (files.length >= maxFileCount) break;
            }
          }
        }

        if (files.length >= maxFileCount) break;
      }

      // Sort files
      _sortFilesStatic(files, sortBy, sortAscending);

      sendPort.send({
        'success': true,
        'files': files.map((f) => f.toMap()).toList(),
      });
    } catch (e) {
      sendPort.send({
        'success': false,
        'error': e.toString(),
      });
    }
  }

  /// Process a single file
  Future<FileInfo?> _processFile(
      File file, List<String> extensions, List<String> excludePatterns) async {
    return await _processFileStatic(file, extensions, excludePatterns);
  }

  /// Static version for isolate
  static Future<FileInfo?> _processFileStatic(
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

  /// Sort files based on criteria
  void _sortFiles(List<FileInfo> files, String sortBy, bool ascending) {
    _sortFilesStatic(files, sortBy, ascending);
  }

  /// Static version for isolate
  static void _sortFilesStatic(
      List<FileInfo> files, String sortBy, bool ascending) {
    switch (sortBy) {
      case 'name':
        files.sort((a, b) =>
            ascending ? a.name.compareTo(b.name) : b.name.compareTo(a.name));
        break;
      case 'date':
        files.sort((a, b) => ascending
            ? a.modifiedTime.compareTo(b.modifiedTime)
            : b.modifiedTime.compareTo(a.modifiedTime));
        break;
      case 'size':
        files.sort((a, b) =>
            ascending ? a.size.compareTo(b.size) : b.size.compareTo(a.size));
        break;
    }
  }

  /// Check if file is image
  static bool _isImageFile(String extension) {
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
  static bool _isVideoFile(String extension) {
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

  /// Clear cache for album
  void clearCache(int albumId) {
    _cachedFiles.remove(albumId);
    _lastScanTime.remove(albumId);
  }

  /// Clear all cache
  void clearAllCache() {
    _cachedFiles.clear();
    _lastScanTime.clear();
  }
}

class FileInfo {
  final String path;
  final String name;
  final int size;
  final DateTime modifiedTime;
  final bool isImage;
  final bool isVideo;

  FileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedTime,
    required this.isImage,
    required this.isVideo,
  });

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'name': name,
      'size': size,
      'modifiedTime': modifiedTime.millisecondsSinceEpoch,
      'isImage': isImage,
      'isVideo': isVideo,
    };
  }

  factory FileInfo.fromMap(Map<String, dynamic> map) {
    return FileInfo(
      path: map['path'],
      name: map['name'],
      size: map['size'],
      modifiedTime: DateTime.fromMillisecondsSinceEpoch(map['modifiedTime']),
      isImage: map['isImage'],
      isVideo: map['isVideo'],
    );
  }
}
