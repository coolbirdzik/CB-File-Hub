import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

/// Manages tag thumbnail images (file-path based).
///
/// Follows the same eager-singleton pattern as [TagColorManager].
/// Thumbnails are stored as file paths in the `tag_metadata` table and
/// cached in-memory with a simple LRU-style map (max [_maxCacheSize] entries).
class TagThumbnailManager {
  static final TagThumbnailManager instance = TagThumbnailManager._internal();

  TagThumbnailManager._internal();

  // ── In-memory cache ──────────────────────────────────────────────────────
  /// normalizedTag → thumbnailPath
  final Map<String, String> _cache = {};
  static const int _maxCacheSize = 100;
  bool _cacheLoaded = false;

  // ── Change notification ──────────────────────────────────────────────────
  final StreamController<String> _changeController =
      StreamController<String>.broadcast();

  /// Fires the normalized tag whose thumbnail was changed.
  Stream<String> get onThumbnailChanged => _changeController.stream;

  // ── Listeners (manual, like TagColorManager) ─────────────────────────────
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Initialise cache from database. Safe to call multiple times.
  Future<void> initialize() async {
    if (_cacheLoaded) return;
    try {
      final db = DatabaseManager.getInstance();
      if (!db.isInitialized()) await db.initialize();
      final all = await db.getAllTagThumbnails();
      _cache.addAll(all);
      _cacheLoaded = true;
      AppLogger.info('[TagThumbnailManager] Loaded ${_cache.length} thumbnails');
    } catch (e) {
      AppLogger.error('[TagThumbnailManager] initialize failed', error: e);
    }
  }

  /// Get the thumbnail path for [tag]. Returns `null` if none is set or the
  /// referenced file no longer exists.
  Future<String?> getThumbnail(String tag) async {
    final normalized = _normalize(tag);
    if (_cache.containsKey(normalized)) {
      final path = _cache[normalized]!;
      if (await File(path).exists()) return path;
      // File gone — remove stale entry.
      _cache.remove(normalized);
      return null;
    }

    // Cache miss — try DB.
    await initialize();
    if (_cache.containsKey(normalized)) {
      final path = _cache[normalized]!;
      if (await File(path).exists()) return path;
      _cache.remove(normalized);
    }
    return null;
  }

  /// Synchronous cache lookup (no file-exists check). Useful for UI builds
  /// where you want the path immediately and can handle stale paths gracefully.
  String? getThumbnailSync(String tag) {
    return _cache[_normalize(tag)];
  }

  /// Set or replace the thumbnail for [tag].
  Future<bool> setThumbnail(String tag, String imagePath) async {
    if (!await File(imagePath).exists()) {
      AppLogger.warning(
        '[TagThumbnailManager] setThumbnail: file does not exist',
        error: imagePath,
      );
      return false;
    }

    final normalized = _normalize(tag);
    try {
      final db = DatabaseManager.getInstance();
      final ok = await db.setTagThumbnail(normalized, imagePath);
      if (ok) {
        _cache[normalized] = imagePath;
        _evictIfNeeded();
        _changeController.add(normalized);
        _notifyListeners();
      }
      return ok;
    } catch (e) {
      AppLogger.error('[TagThumbnailManager] setThumbnail failed', error: e);
      return false;
    }
  }

  /// Remove the thumbnail for [tag].
  Future<bool> deleteThumbnail(String tag) async {
    final normalized = _normalize(tag);
    try {
      final db = DatabaseManager.getInstance();
      final ok = await db.deleteTagThumbnail(normalized);
      if (ok) {
        _cache.remove(normalized);
        _changeController.add(normalized);
        _notifyListeners();
      }
      return ok;
    } catch (e) {
      AppLogger.error('[TagThumbnailManager] deleteThumbnail failed', error: e);
      return false;
    }
  }

  /// Returns all cached thumbnails (normalizedTag → path).
  Map<String, String> getAllCached() => Map.unmodifiable(_cache);

  /// Clear the in-memory cache. Next access will reload from DB.
  void clearCache() {
    _cache.clear();
    _cacheLoaded = false;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _normalize(String tag) => tag.trim().toLowerCase();

  /// Simple eviction: remove oldest entries when cache exceeds max size.
  void _evictIfNeeded() {
    while (_cache.length > _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }
}
