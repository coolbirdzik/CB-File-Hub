import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:cb_file_manager/helpers/core/app_path_helper.dart';

// ---------------------------------------------------------------------------
// Top-level isolate functions (required by compute())
// ---------------------------------------------------------------------------

/// Decode, resize and encode a photo thumbnail inside an isolate.
Future<String?> _generatePhotoThumbnailIsolate(
  Map<String, dynamic> args,
) async {
  final String sourcePath = args['sourcePath'] as String;
  final String destPath = args['destPath'] as String;
  final int maxSize = args['maxSize'] as int;
  final int quality = args['quality'] as int;
  try {
    final bytes = await File(sourcePath).readAsBytes();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    int w = decoded.width;
    int h = decoded.height;
    if (w > maxSize || h > maxSize) {
      if (w >= h) {
        h = (h * maxSize / w).round();
        w = maxSize;
      } else {
        w = (w * maxSize / h).round();
        h = maxSize;
      }
    }

    final resized = img.copyResize(
      decoded,
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
    final jpg = img.encodeJpg(resized, quality: quality);
    await File(destPath).writeAsBytes(jpg);
    return destPath;
  } catch (_) {
    return null;
  }
}

/// Persist the index map to disk inside an isolate.
Future<void> _savePhotoIndexIsolate(Map<String, dynamic> args) async {
  final String filePath = args['filePath'] as String;
  final Map<String, String> cacheData = Map<String, String>.from(
    args['cacheData'] as Map,
  );
  try {
    await File(filePath).writeAsString(jsonEncode(cacheData));
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// PhotoThumbnailHelper
// ---------------------------------------------------------------------------

/// Caches downscaled JPEG thumbnails for local image files using the same
/// two-layer approach as [VideoThumbnailHelper]:
///
///   Layer 1 — `_inMemoryCache`: fast `Map<String,String>` (LRU, max 150)
///   Layer 2 — `_fileCache`:     `LinkedHashMap` backed by disk index JSON
///   Layer 3 — Disk scan:        looks for `photo_thumb_<md5>.jpg` in cache dir
///
/// Thumbnails are written to `<AppCacheDir>/cb_file_hub/photo_thumbnails/`.
/// The index is stored at `<TempDir>/photo_cache_index.json`.
class PhotoThumbnailHelper {
  PhotoThumbnailHelper._();

  // -- Cache stores ----------------------------------------------------------
  static final LinkedHashMap<String, String> _fileCache =
      LinkedHashMap<String, String>();
  static final Map<String, String> _inMemoryCache = {};
  static const int _maxCacheSize = 150;

  // -- Disk index ------------------------------------------------------------
  static String? _cacheIndexFilePath;
  static bool _cacheInitialized = false;
  static bool _initializing = false;
  static Completer<void> _initCompleter = Completer<void>();

  // -- Throttled save --------------------------------------------------------
  static Timer? _saveCacheTimer;
  static const Duration _saveCacheThrottle = Duration(seconds: 10);

  // -- Generation ------------------------------------------------------------
  static const int thumbnailMaxSize = 512;
  static const int thumbnailQuality = 85;

  /// In-flight generation keys — prevents duplicate concurrent generation.
  static final Set<String> _generating = {};

  // ---------------------------------------------------------------------------
  // Key helpers
  // ---------------------------------------------------------------------------

  /// Normalise a source path to a stable cache key.
  static String _cacheKey(String imagePath) {
    if (Platform.isWindows) return imagePath.toLowerCase();
    return imagePath;
  }

  /// Deterministic filename based on the normalised path MD5.
  static String _cacheFilename(String imagePath) {
    final bytes = utf8.encode(_cacheKey(imagePath));
    final digest = md5.convert(bytes);
    return 'photo_thumb_$digest.jpg';
  }

  // ---------------------------------------------------------------------------
  // Init / load / save
  // ---------------------------------------------------------------------------

  /// Must be called once at app start (or lazily on first use).
  static Future<void> initializeCache() async {
    if (_cacheInitialized) return;
    if (_initializing) return _initCompleter.future;

    _initializing = true;
    _initCompleter = Completer<void>();

    try {
      await _loadCacheFromDisk();
      _cacheInitialized = true;
      _initCompleter.complete();
    } catch (e) {
      _initCompleter.completeError(e);
      _cacheInitialized = false;
    } finally {
      _initializing = false;
    }
  }

  static Future<String> _getCacheIndexPath() async {
    if (_cacheIndexFilePath != null) return _cacheIndexFilePath!;
    final tempDir = await getTemporaryDirectory();
    _cacheIndexFilePath = path.join(tempDir.path, 'photo_cache_index.json');
    return _cacheIndexFilePath!;
  }

  static Future<void> _loadCacheFromDisk() async {
    _fileCache.clear();
    final indexPath = await _getCacheIndexPath();
    final indexFile = File(indexPath);
    if (!await indexFile.exists()) return;

    try {
      final json = await indexFile.readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      for (final e in data.entries) {
        if (e.value is String) {
          _fileCache[e.key] = e.value as String;
        }
      }
    } catch (_) {
      try {
        await indexFile.delete();
      } catch (_) {}
    }
  }

  static void _saveCacheToDiskThrottled() {
    if (_saveCacheTimer?.isActive ?? false) _saveCacheTimer!.cancel();
    _saveCacheTimer = Timer(_saveCacheThrottle, _saveCacheToDiskActual);
  }

  static Future<void> _saveCacheToDiskActual() async {
    try {
      final indexPath = await _getCacheIndexPath();
      await compute(_savePhotoIndexIsolate, {
        'filePath': indexPath,
        'cacheData': Map<String, String>.from(_fileCache),
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Internal LRU helpers
  // ---------------------------------------------------------------------------

  static void _addToMemory(String key, String thumbPath) {
    if (_inMemoryCache.length >= _maxCacheSize) {
      _inMemoryCache.remove(_inMemoryCache.keys.first);
    }
    _inMemoryCache[key] = thumbPath;
  }

  static void _addToFileCache(String key, String thumbPath) {
    if (_fileCache.length >= _maxCacheSize) {
      _fileCache.remove(_fileCache.keys.first);
    }
    _fileCache[key] = thumbPath;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Synchronous memory-only cache check — no I/O, no await.
  ///
  /// Returns the cached thumbnail path if it is currently in the hot
  /// in-memory LRU, otherwise `null`.  Use this inside gesture handlers
  /// or other synchronous contexts where blocking on I/O is undesirable.
  static String? getFromMemoryCache(String imagePath) {
    final key = _cacheKey(imagePath);
    return _inMemoryCache[key];
  }

  /// Return a cached thumbnail path, or `null` on a cache miss.
  ///
  /// Check order: memory → file-index → disk scan by expected filename.
  static Future<String?> getFromCache(String imagePath) async {
    if (!_cacheInitialized) {
      if (_initializing) {
        await _initCompleter.future;
      } else {
        await initializeCache();
      }
    }

    final key = _cacheKey(imagePath);

    // 1. Memory cache (fastest)
    if (_inMemoryCache.containsKey(key)) {
      final p = _inMemoryCache[key]!;
      if (await File(p).exists()) return p;
      _inMemoryCache.remove(key);
    }

    // 2. File-index cache
    if (_fileCache.containsKey(key)) {
      final p = _fileCache[key]!;
      try {
        final f = File(p);
        if (await f.exists() && await f.length() > 0) {
          _addToMemory(key, p);
          return p;
        }
      } catch (_) {}
      _fileCache.remove(key);
    }

    // 3. Disk scan — the thumbnail file may exist even if the index was lost
    try {
      final cacheDir = await AppPathHelper.getPhotoCacheDir();
      final candidate = path.join(cacheDir.path, _cacheFilename(imagePath));
      final f = File(candidate);
      if (await f.exists() && await f.length() > 0) {
        _addToFileCache(key, candidate);
        _addToMemory(key, candidate);
        return candidate;
      }
    } catch (_) {}

    return null;
  }

  /// Maximum number of thumbnail-generation isolates running concurrently.
  /// Keeping this low (4 on desktop, 2 on mobile) prevents CPU starvation
  /// of the raster thread, which is the compositor.
  static int _activeGenerations = 0;
  static const int _maxConcurrentGenerations = 4;

  /// Generate a thumbnail for [imagePath], persist it to disk, update both
  /// cache layers and return the JPEG path.  Returns `null` on failure.
  ///
  /// Concurrent calls for the same file are collapsed — only one generation
  /// runs at a time; duplicates wait or return null.
  static Future<String?> generateThumbnail(
    String imagePath, {
    int maxSize = thumbnailMaxSize,
  }) async {
    if (!_cacheInitialized) await initializeCache();

    // Fast path: already cached
    final cached = await getFromCache(imagePath);
    if (cached != null) return cached;

    final key = _cacheKey(imagePath);

    // Deduplicate concurrent generation requests for the same file
    if (_generating.contains(key)) return null;

    // Throttle total concurrent isolates to avoid CPU starvation of the
    // raster/compositor threads during scroll.
    if (_activeGenerations >= _maxConcurrentGenerations) return null;

    _generating.add(key);
    _activeGenerations++;

    try {
      final cacheDir = await AppPathHelper.getPhotoCacheDir();
      final destPath = path.join(cacheDir.path, _cacheFilename(imagePath));

      final result = await compute(_generatePhotoThumbnailIsolate, {
        'sourcePath': imagePath,
        'destPath': destPath,
        'maxSize': maxSize,
        'quality': thumbnailQuality,
      });

      if (result != null) {
        _addToFileCache(key, result);
        _addToMemory(key, result);
        _saveCacheToDiskThrottled();
        return result;
      }
    } catch (_) {
      // Generation failed
    } finally {
      _generating.remove(key);
      _activeGenerations--;
    }

    return null;
  }

  /// Wipe in-memory caches without deleting disk files.
  static void clearMemoryCache() {
    _inMemoryCache.clear();
    _fileCache.clear();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle / cleanup
  // ---------------------------------------------------------------------------

  static DateTime _lastCleanupTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Remove disk thumbnails that haven't been accessed in [maxAgeHours].
  /// Mirrors [VideoThumbnailHelper._cleanupOldTempFiles].
  /// Safe to call on app start or periodically — throttled to once per hour.
  static Future<void> cleanupOldEntries({int maxAgeHours = 24}) async {
    final now = DateTime.now();
    if (now.difference(_lastCleanupTime).inHours < 1) return;
    _lastCleanupTime = now;

    try {
      final cacheDir = await AppPathHelper.getPhotoCacheDir();
      final liveValues = {..._fileCache.values, ..._inMemoryCache.values};

      await for (final entity in cacheDir.list(
        recursive: false,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (!path.basename(entity.path).startsWith('photo_thumb_')) continue;
        // Keep entries that are still referenced in memory.
        if (liveValues.contains(entity.path)) continue;
        try {
          final stat = await entity.stat();
          if (now.difference(stat.modified).inHours > maxAgeHours) {
            await entity.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Evict the given [paths] from all cache layers (memory + disk index).
  /// Call this when a tab or context is closed so transient entries are freed.
  static Future<void> evictForPaths(Iterable<String> paths) async {
    for (final p in paths) {
      final key = _cacheKey(p);
      _inMemoryCache.remove(key);
      _fileCache.remove(key);
    }
    _saveCacheToDiskThrottled();
  }
}
