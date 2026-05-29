import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class FolderThumbnailService {
  static const String _customThumbnailsKey = 'folder_custom_thumbnails';
  static const String _configFileName = '.cbfile_config.json';
  static const String _folderThumbnailKey = 'folderThumbnail';
  static const String _folderAutoThumbnailKey = 'folderAutoThumbnail';
  static final FolderThumbnailService _instance =
      FolderThumbnailService._internal();
  static final StreamController<String> _thumbnailChangedController =
      StreamController<String>.broadcast();

  // In-memory cache for thumbnails with a limit to prevent memory leaks
  final Map<String, String> _thumbnailCache = {};
  // Maximum number of folder thumbnails to keep in cache
  static const int _maxCacheSize = 50;
  // List to track LRU order (most recently used at the end)
  final List<String> _cacheAccessOrder = [];

  // In-memory cache for custom thumbnail settings
  Map<String, String> _customThumbnailSettings = {};

  // Cache folder config to avoid repeated disk reads
  final Map<String, Map<String, dynamic>> _folderConfigCache = {};
  final Map<String, Map<String, dynamic>> _systemPathConfigs = {};

  // Track failed video paths to prevent infinite reload loops
  final Set<String> _failedVideoPathsCache = {};

  // Last cache cleanup timestamp
  DateTime _lastCacheCleanup = DateTime.now();

  // Singleton pattern
  factory FolderThumbnailService() {
    return _instance;
  }

  FolderThumbnailService._internal();

  // Initialize the service and load saved preferences
  Future<void> initialize() async {
    await _loadCustomThumbnailSettings();
    debugPrint('FolderThumbnailService initialized');
  }

  // Load custom thumbnail settings from SharedPreferences
  Future<void> _loadCustomThumbnailSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? settingsJson = prefs.getString(_customThumbnailsKey);

      if (settingsJson != null) {
        _customThumbnailSettings = Map<String, String>.from(settingsJson
            .split('|')
            .map((item) {
              final parts = item.split('::');
              return parts.length == 2 ? MapEntry(parts[0], parts[1]) : null;
            })
            .where((item) => item != null)
            .fold({}, (map, item) {
              map[item!.key] = item.value;
              return map;
            }));
      }
    } catch (e) {
      debugPrint('Error loading custom thumbnail settings: $e');
      _customThumbnailSettings = {};
    }
  }

  // Save custom thumbnail settings to SharedPreferences
  Future<void> _saveCustomThumbnailSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String settingsJson = _customThumbnailSettings.entries
          .map((entry) => '${entry.key}::${entry.value}')
          .join('|');

      await prefs.setString(_customThumbnailsKey, settingsJson);
    } catch (e) {
      debugPrint('Error saving custom thumbnail settings: $e');
    }
  }

  Stream<String> get onThumbnailChanged => _thumbnailChangedController.stream;

  /// Check if a video path has previously failed to load
  bool isVideoPathFailed(String videoPath) {
    return _failedVideoPathsCache.contains(videoPath);
  }

  /// Mark a video path as failed to prevent reload loops
  void markVideoPathAsFailed(String videoPath) {
    _failedVideoPathsCache.add(videoPath);
  }

  /// Clear failed video paths cache (useful for retry scenarios)
  void clearFailedVideoPaths() {
    _failedVideoPathsCache.clear();
  }

  bool _isSystemPath(String folderPath) {
    return folderPath.startsWith('#');
  }

  Future<Map<String, dynamic>> _readFolderConfig(String folderPath) async {
    if (_isSystemPath(folderPath)) {
      return _systemPathConfigs[folderPath] ?? {};
    }

    if (_folderConfigCache.containsKey(folderPath)) {
      return _folderConfigCache[folderPath] ?? {};
    }

    final configPath = path.join(folderPath, _configFileName);
    final configFile = File(configPath);
    if (!await configFile.exists()) {
      _folderConfigCache[folderPath] = {};
      return {};
    }

    try {
      final contents = await configFile.readAsString();
      final decoded = json.decode(contents);
      if (decoded is Map<String, dynamic>) {
        _folderConfigCache[folderPath] = decoded;
        return decoded;
      }
    } catch (e) {
      debugPrint('Error reading folder config: $e');
    }

    _folderConfigCache[folderPath] = {};
    return {};
  }

  Future<void> _writeFolderConfig(
      String folderPath, Map<String, dynamic> config) async {
    if (_isSystemPath(folderPath)) {
      _systemPathConfigs[folderPath] = Map<String, dynamic>.from(config);
      _folderConfigCache[folderPath] = Map<String, dynamic>.from(config);
      return;
    }

    _folderConfigCache[folderPath] = Map<String, dynamic>.from(config);

    final configPath = path.join(folderPath, _configFileName);
    final configFile = File(configPath);

    if (config.isEmpty) {
      if (await configFile.exists()) {
        try {
          await configFile.delete();
        } catch (e) {
          debugPrint('Error deleting empty config file: $e');
        }
      }
      return;
    }

    try {
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final jsonString = const JsonEncoder.withIndent('  ').convert(config);
      await configFile.writeAsString(jsonString);

      if (Platform.isWindows) {
        try {
          await Process.run('attrib', ['+H', configPath]);
        } catch (e) {
          debugPrint('Error setting hidden attribute: $e');
        }
      } else if (Platform.isAndroid) {
        try {
          final nomediaFile = File(path.join(folderPath, '.nomedia'));
          if (!await nomediaFile.exists()) {
            await nomediaFile.create();
          }
        } catch (e) {
          debugPrint('Error creating .nomedia: $e');
        }
      }
    } catch (e) {
      debugPrint('Error writing folder config: $e');
    }
  }

  void _notifyThumbnailChanged(String folderPath) {
    _thumbnailChangedController.add(folderPath);
  }

  String _normalizeThumbnailValue(String value) {
    if (value.startsWith('video::')) {
      final parts = value.split('::');
      if (parts.length >= 2) {
        return 'video::${parts[1]}';
      }
    }
    return value;
  }

  Future<String?> _validateThumbnailValue(String value) async {
    if (value.startsWith('video::')) {
      final videoPath = value.substring(7);
      if (await File(videoPath).exists()) {
        return 'video::$videoPath';
      }
      return null;
    }

    if (await File(value).exists()) {
      return value;
    }
    return null;
  }

  // Set a custom thumbnail for a folder
  Future<void> setCustomThumbnail(
    String folderPath,
    String filePath, {
    bool isVideo = false,
  }) async {
    final value = isVideo ? 'video::$filePath' : filePath;
    await _saveCustomThumbnailToConfig(folderPath, value);
    // Clear from cache to force regeneration
    _removeFromCache(folderPath);
    _notifyThumbnailChanged(folderPath);
  }

  // Clear custom thumbnail for a folder
  Future<void> clearCustomThumbnail(String folderPath) async {
    _customThumbnailSettings.remove(folderPath);
    await _saveCustomThumbnailSettings();
    await _clearCustomThumbnailInConfig(folderPath);
    // Clear from cache to force regeneration
    _removeFromCache(folderPath);
    _notifyThumbnailChanged(folderPath);
  }

  // Get custom thumbnail path for a folder (if set)
  Future<String?> getCustomThumbnailPath(String folderPath) async {
    final config = await _readFolderConfig(folderPath);
    final value = config[_folderThumbnailKey];
    if (value is String && value.isNotEmpty) {
      return _normalizeThumbnailValue(value);
    }

    final legacyValue = _customThumbnailSettings[folderPath];
    if (legacyValue != null && legacyValue.isNotEmpty) {
      final normalizedLegacy = _normalizeThumbnailValue(legacyValue);
      await _saveCustomThumbnailToConfig(folderPath, normalizedLegacy);
      _customThumbnailSettings.remove(folderPath);
      await _saveCustomThumbnailSettings();
      return normalizedLegacy;
    }

    return null;
  }

  // Check if a folder has custom thumbnail
  Future<bool> hasCustomThumbnail(String folderPath) async {
    final customValue = await getCustomThumbnailPath(folderPath);
    return customValue != null && customValue.isNotEmpty;
  }

  Future<void> _saveCustomThumbnailToConfig(
      String folderPath, String value) async {
    final config = await _readFolderConfig(folderPath);
    config[_folderThumbnailKey] = value;
    await _writeFolderConfig(folderPath, config);
  }

  Future<void> _clearCustomThumbnailInConfig(String folderPath) async {
    final config = await _readFolderConfig(folderPath);
    config.remove(_folderThumbnailKey);
    await _writeFolderConfig(folderPath, config);
  }

  // Add to cache with LRU management
  void _addToCache(String key, String value) {
    // If the key is already in cache, remove it from the access order
    if (_thumbnailCache.containsKey(key)) {
      _cacheAccessOrder.remove(key);
    } else if (_thumbnailCache.length >= _maxCacheSize) {
      // If cache is full, remove the least recently used item
      final lruKey = _cacheAccessOrder.removeAt(0);
      _thumbnailCache.remove(lruKey);
      debugPrint('FolderThumbnailService: Removed LRU cache entry: $lruKey');
    }

    // Add/update the cache and mark as most recently used
    _thumbnailCache[key] = value;
    _cacheAccessOrder.add(key);

    // Periodically check for video cache cleanup
    _performMaintenanceIfNeeded();
  }

  // Remove from cache if exists
  void _removeFromCache(String key) {
    _thumbnailCache.remove(key);
    _cacheAccessOrder.remove(key);
  }

  // Perform cache maintenance operations periodically
  void _performMaintenanceIfNeeded() {
    final now = DateTime.now();
    // Only perform cleanup once per hour
    if (now.difference(_lastCacheCleanup).inHours >= 1) {
      _lastCacheCleanup = now;
      // Trim VideoThumbnailHelper cache to prevent it from growing too large
      unawaited(VideoThumbnailHelper.trimCache());
    }
  }

  // Get thumbnail for a folder
  Future<String?> getFolderThumbnail(String folderPath) async {
    // Check if we have a cached thumbnail
    if (_thumbnailCache.containsKey(folderPath)) {
      final cachedPath = _thumbnailCache[folderPath];

      // Update the LRU order
      _cacheAccessOrder.remove(folderPath);
      _cacheAccessOrder.add(folderPath);

      return cachedPath;
    }

    // Check if there is a custom thumbnail
    final customPath = await getCustomThumbnailPath(folderPath);
    if (customPath != null) {
      final validCustom = await _validateThumbnailValue(customPath);
      if (validCustom != null) {
        _addToCache(folderPath, validCustom);
        return validCustom;
      }
      await clearCustomThumbnail(folderPath);
    }

    // Check if we already have an auto-selected thumbnail saved
    final config = await _readFolderConfig(folderPath);
    final autoValue = config[_folderAutoThumbnailKey];
    if (autoValue is String && autoValue.isNotEmpty) {
      final normalized = _normalizeThumbnailValue(autoValue);
      final validAuto = await _validateThumbnailValue(normalized);
      if (validAuto != null) {
        _addToCache(folderPath, validAuto);
        return validAuto;
      }
      config.remove(_folderAutoThumbnailKey);
      await _writeFolderConfig(folderPath, config);
    }

    // Find and generate thumbnail from folder content
    String? thumbnailPath;
    try {
      thumbnailPath = await _findFirstMediaFileInFolder(folderPath);
      debugPrint('Found media thumbnail: $thumbnailPath');
    } catch (e) {
      debugPrint('Error finding media in folder: $e');
    }

    if (thumbnailPath != null) {
      config[_folderAutoThumbnailKey] = thumbnailPath;
      await _writeFolderConfig(folderPath, config);
      _addToCache(folderPath, thumbnailPath);
    }

    return thumbnailPath;
  }

  // Find the first media file in a folder (direct implementation)
  Future<String?> _findFirstMediaFileInFolder(String folderPath) async {
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      return null;
    }

    try {
      String? firstImagePath;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }

        final basename = path.basename(entity.path);
        if (basename == _configFileName || basename == '.nomedia') {
          continue;
        }

        if (VideoThumbnailHelper.isSupportedVideoFormat(entity.path)) {
          debugPrint('Found video file: ${entity.path}');
          return 'video::${entity.path}';
        }

        if (firstImagePath == null && FileTypeUtils.isImageFile(entity.path)) {
          firstImagePath = entity.path;
        }
      }

      if (firstImagePath != null) {
        return firstImagePath;
      }
    } catch (e) {
      debugPrint('Error scanning folder: $e');
    }

    return null;
  }

  // Find the first image file in a folder (used for fallback when video thumbs fail)
  Future<String?> findFirstImageInFolder(String folderPath) async {
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      return null;
    }

    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }

        final basename = path.basename(entity.path);
        if (basename == _configFileName || basename == '.nomedia') {
          continue;
        }

        if (FileTypeUtils.isImageFile(entity.path)) {
          return entity.path;
        }
      }
    } catch (e) {
      debugPrint('Error scanning folder for images: $e');
    }

    return null;
  }

  Future<String?> setAutoThumbnail(String folderPath, String value) async {
    final config = await _readFolderConfig(folderPath);
    final customValue = config[_folderThumbnailKey];
    if (customValue is String && customValue.isNotEmpty) {
      return null;
    }

    config[_folderAutoThumbnailKey] = value;
    await _writeFolderConfig(folderPath, config);
    _addToCache(folderPath, value);
    _notifyThumbnailChanged(folderPath);
    return value;
  }

  // Get all media files in a folder for thumbnail selection
  Future<List<File>> getMediaFilesForThumbnailSelection(
      String folderPath) async {
    final directory = Directory(folderPath);
    final List<File> mediaFiles = [];

    if (!await directory.exists()) {
      return [];
    }

    try {
      final List<FileSystemEntity> entities = await directory.list().toList();

      for (final entity in entities) {
        if (entity is File) {
          // Check for supported media files using FileTypeUtils
          if (FileTypeUtils.isImageFile(entity.path) ||
              VideoThumbnailHelper.isSupportedVideoFormat(entity.path)) {
            mediaFiles.add(entity);
          }
        }
      }

      debugPrint(
          'Found ${mediaFiles.length} media files in folder $folderPath');
    } catch (e) {
      debugPrint('Error getting media files: $e');
    }

    return mediaFiles;
  }

  // Clear the in-memory cache
  void clearCache() {
    _thumbnailCache.clear();
    _cacheAccessOrder.clear();
    _folderConfigCache.clear();
    _failedVideoPathsCache.clear();
    debugPrint('FolderThumbnailService: Cache cleared');

    // Also clear the VideoThumbnailHelper cache
    unawaited(VideoThumbnailHelper.clearCache());
  }

  /// Cancel any pending folder thumbnail work for [dirPath] and drop the
  /// in-memory cache entry for that folder. Used by the tab activity manager
  /// when a tab transitions to inactive so cached folder cover thumbnails
  /// are released and any underlying video thumbnail work for the same
  /// directory is also suspended.
  ///
  /// On-disk caches and folder config files are intentionally left intact;
  /// only the in-memory bitmap reference is dropped so RAM can be reclaimed.
  void cancelForDirectory(String dirPath) {
    if (dirPath.isEmpty) return;

    final normalized = path.normalize(dirPath);
    // Drop in-memory cache for this directory and any direct child entries.
    final keysToDrop = _thumbnailCache.keys
        .where((k) =>
            path.normalize(k) == normalized ||
            path.isWithin(normalized, path.normalize(k)))
        .toList();
    for (final k in keysToDrop) {
      _removeFromCache(k);
    }

    // Drop cached folder configs as well — they are tiny but we want a
    // clean re-read after refocus so user-facing changes are visible.
    final configKeysToDrop = _folderConfigCache.keys
        .where((k) =>
            path.normalize(k) == normalized ||
            path.isWithin(normalized, path.normalize(k)))
        .toList();
    for (final k in configKeysToDrop) {
      _folderConfigCache.remove(k);
    }

    // Cascade into the underlying video thumbnail pipeline.
    VideoThumbnailHelper.cancelForDirectory(dirPath);
  }
}
