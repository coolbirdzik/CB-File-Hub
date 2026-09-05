import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

class FolderThumbnailService {
  static const String _customThumbnailsKey = 'folder_custom_thumbnails';
  static const String _legacyConfigFileName = '.cbfile_config.json';
  static const String _legacyFolderThumbnailKey = 'folderThumbnail';
  static const String _legacyFolderAutoThumbnailKey = 'folderAutoThumbnail';
  static const String _tableName = 'folder_thumbnails';

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

  // Cache stored thumbnail rows to avoid repeated disk reads
  final Map<String, _StoredThumbnailRow> _rowCache = {};
  // Track folders we have already attempted to migrate from legacy json
  final Set<String> _migratedLegacyPaths = {};

  // Track failed video paths to prevent infinite reload loops
  final Set<String> _failedVideoPathsCache = {};

  // Last cache cleanup timestamp
  DateTime _lastCacheCleanup = DateTime.now();

  Future<void>? _tableInitialization;

  // Singleton pattern
  factory FolderThumbnailService() {
    return _instance;
  }

  FolderThumbnailService._internal();

  // Initialize the service and migrate any legacy SharedPreferences entries
  Future<void> initialize() async {
    await _migrateSharedPreferencesIfNeeded();
    debugPrint('FolderThumbnailService initialized');
  }

  Future<void> _migrateSharedPreferencesIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_customThumbnailsKey);
      if (settingsJson == null || settingsJson.isEmpty) {
        return;
      }

      for (final item in settingsJson.split('|')) {
        final parts = item.split('::');
        if (parts.length != 2) continue;
        final folderPath = parts[0];
        final value = parts[1];
        if (folderPath.isEmpty || value.isEmpty) continue;
        await _writeRow(
          folderPath,
          customThumbnail: _normalizeThumbnailValue(value),
        );
      }

      await prefs.remove(_customThumbnailsKey);
    } catch (e) {
      debugPrint('Error migrating legacy SharedPreferences thumbnails: $e');
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

  String _normalizePath(String folderPath) {
    final trimmed = folderPath.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    if (_isSystemPath(trimmed) || trimmed.contains('://')) {
      return trimmed;
    }
    final normalized = path.normalize(trimmed);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Future<Database> _getDatabase() async {
    final database = await DatabaseManager.getInstance().getDatabase();
    _tableInitialization ??= _ensureTable(database);
    try {
      await _tableInitialization;
    } catch (_) {
      _tableInitialization = null;
      rethrow;
    }
    return database;
  }

  Future<void> _ensureTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        path TEXT PRIMARY KEY,
        custom_thumbnail TEXT,
        auto_thumbnail TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<_StoredThumbnailRow> _readRow(String folderPath) async {
    final pathKey = _normalizePath(folderPath);
    final cached = _rowCache[pathKey];
    if (cached != null) {
      return cached;
    }

    final database = await _getDatabase();
    final rows = await database.query(
      _tableName,
      where: 'path = ?',
      whereArgs: <Object?>[pathKey],
      limit: 1,
    );

    var row = rows.isEmpty
        ? const _StoredThumbnailRow(custom: null, auto: null)
        : _StoredThumbnailRow(
            custom: rows.first['custom_thumbnail'] as String?,
            auto: rows.first['auto_thumbnail'] as String?,
          );

    if (row.isEmpty && !_isSystemPath(folderPath)) {
      final migrated = await _migrateLegacyConfig(folderPath, pathKey);
      if (migrated != null) {
        row = migrated;
      }
    }

    _rowCache[pathKey] = row;
    return row;
  }

  Future<_StoredThumbnailRow?> _migrateLegacyConfig(
    String folderPath,
    String pathKey,
  ) async {
    if (_migratedLegacyPaths.contains(pathKey)) {
      return null;
    }
    _migratedLegacyPaths.add(pathKey);

    if (folderPath.isEmpty ||
        _isSystemPath(folderPath) ||
        folderPath.contains('://')) {
      return null;
    }

    final configFile = File(path.join(folderPath, _legacyConfigFileName));
    if (!await configFile.exists()) {
      return null;
    }

    String? customValue;
    String? autoValue;
    try {
      final decoded = json.decode(await configFile.readAsString());
      if (decoded is Map) {
        final raw = decoded[_legacyFolderThumbnailKey];
        if (raw is String && raw.isNotEmpty) {
          customValue = _normalizeThumbnailValue(raw);
        }
        final rawAuto = decoded[_legacyFolderAutoThumbnailKey];
        if (rawAuto is String && rawAuto.isNotEmpty) {
          autoValue = _normalizeThumbnailValue(rawAuto);
        }
      }
    } catch (e) {
      debugPrint('Error reading legacy folder thumbnail config: $e');
    }

    // Always remove the legacy file after attempting migration so the
    // hidden `.cbfile_config.json` artifact stops appearing in user folders.
    try {
      await configFile.delete();
    } catch (e) {
      debugPrint('Error deleting legacy folder thumbnail config: $e');
    }

    if (customValue == null && autoValue == null) {
      return null;
    }

    final migrated = _StoredThumbnailRow(custom: customValue, auto: autoValue);
    await _persistRow(pathKey, migrated);
    return migrated;
  }

  Future<void> _writeRow(
    String folderPath, {
    String? customThumbnail,
    String? autoThumbnail,
    bool clearCustom = false,
    bool clearAuto = false,
  }) async {
    final pathKey = _normalizePath(folderPath);
    final current = await _readRow(folderPath);
    final next = _StoredThumbnailRow(
      custom: clearCustom ? null : (customThumbnail ?? current.custom),
      auto: clearAuto ? null : (autoThumbnail ?? current.auto),
    );
    await _persistRow(pathKey, next);
    _rowCache[pathKey] = next;
  }

  Future<void> _persistRow(String pathKey, _StoredThumbnailRow row) async {
    final database = await _getDatabase();
    if (row.isEmpty) {
      await database.delete(
        _tableName,
        where: 'path = ?',
        whereArgs: <Object?>[pathKey],
      );
      return;
    }

    await database.insert(_tableName, <String, Object?>{
      'path': pathKey,
      'custom_thumbnail': row.custom,
      'auto_thumbnail': row.auto,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    await _writeRow(folderPath, customThumbnail: value);
    // Clear from cache to force regeneration
    _removeFromCache(folderPath);
    _notifyThumbnailChanged(folderPath);
  }

  // Clear custom thumbnail for a folder
  Future<void> clearCustomThumbnail(String folderPath) async {
    await _writeRow(folderPath, clearCustom: true);
    // Clear from cache to force regeneration
    _removeFromCache(folderPath);
    _notifyThumbnailChanged(folderPath);
  }

  // Get custom thumbnail path for a folder (if set)
  Future<String?> getCustomThumbnailPath(String folderPath) async {
    final row = await _readRow(folderPath);
    final value = row.custom;
    if (value != null && value.isNotEmpty) {
      return _normalizeThumbnailValue(value);
    }
    return null;
  }

  // Check if a folder has custom thumbnail
  Future<bool> hasCustomThumbnail(String folderPath) async {
    final customValue = await getCustomThumbnailPath(folderPath);
    return customValue != null && customValue.isNotEmpty;
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

    final row = await _readRow(folderPath);

    // Check if there is a custom thumbnail
    final customRaw = row.custom;
    if (customRaw != null && customRaw.isNotEmpty) {
      final normalized = _normalizeThumbnailValue(customRaw);
      final validCustom = await _validateThumbnailValue(normalized);
      if (validCustom != null) {
        _addToCache(folderPath, validCustom);
        return validCustom;
      }
      await clearCustomThumbnail(folderPath);
    }

    // Check if we already have an auto-selected thumbnail saved
    final autoRaw = row.auto;
    if (autoRaw != null && autoRaw.isNotEmpty) {
      final normalized = _normalizeThumbnailValue(autoRaw);
      final validAuto = await _validateThumbnailValue(normalized);
      if (validAuto != null) {
        _addToCache(folderPath, validAuto);
        return validAuto;
      }
      await _writeRow(folderPath, clearAuto: true);
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
      await _writeRow(folderPath, autoThumbnail: thumbnailPath);
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
        if (basename == _legacyConfigFileName || basename == '.nomedia') {
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
        if (basename == _legacyConfigFileName || basename == '.nomedia') {
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
    final row = await _readRow(folderPath);
    if (row.custom != null && row.custom!.isNotEmpty) {
      return null;
    }

    await _writeRow(folderPath, autoThumbnail: value);
    _addToCache(folderPath, value);
    _notifyThumbnailChanged(folderPath);
    return value;
  }

  // Get all media files in a folder for thumbnail selection
  Future<List<File>> getMediaFilesForThumbnailSelection(
    String folderPath,
  ) async {
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
        'Found ${mediaFiles.length} media files in folder $folderPath',
      );
    } catch (e) {
      debugPrint('Error getting media files: $e');
    }

    return mediaFiles;
  }

  // Clear the in-memory cache
  void clearCache() {
    _thumbnailCache.clear();
    _cacheAccessOrder.clear();
    _rowCache.clear();
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
  /// On-disk caches and persisted thumbnail rows are intentionally left
  /// intact; only the in-memory bitmap reference is dropped so RAM can be
  /// reclaimed.
  void cancelForDirectory(String dirPath) {
    if (dirPath.isEmpty) return;

    final normalized = path.normalize(dirPath);
    // Drop in-memory cache for this directory and any direct child entries.
    final keysToDrop = _thumbnailCache.keys
        .where(
          (k) =>
              path.normalize(k) == normalized ||
              path.isWithin(normalized, path.normalize(k)),
        )
        .toList();
    for (final k in keysToDrop) {
      _removeFromCache(k);
    }

    // Drop cached rows as well so a clean re-read after refocus reflects
    // any user-facing changes made while the tab was inactive.
    final rowKeysToDrop = _rowCache.keys
        .where(
          (k) =>
              path.normalize(k) == normalized ||
              path.isWithin(normalized, path.normalize(k)),
        )
        .toList();
    for (final k in rowKeysToDrop) {
      _rowCache.remove(k);
    }

    // Cascade into the underlying video thumbnail pipeline.
    VideoThumbnailHelper.cancelForDirectory(dirPath);
  }
}

class _StoredThumbnailRow {
  const _StoredThumbnailRow({required this.custom, required this.auto});

  final String? custom;
  final String? auto;

  bool get isEmpty =>
      (custom == null || custom!.isEmpty) && (auto == null || auto!.isEmpty);
}
