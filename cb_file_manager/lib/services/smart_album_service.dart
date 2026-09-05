import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Lightweight registry to mark which albums are dynamic (rule-based)
class SmartAlbumService {
  static const String _fileName = 'smart_albums.json';
  static SmartAlbumService? _instance;

  static SmartAlbumService get instance {
    _instance ??= SmartAlbumService._();
    return _instance!;
  }

  SmartAlbumService._();

  // ── In-memory scan result cache ─────────────────────────────────────────────
  // Persists scan results across AlbumDetailScreen lifecycle (widget dispose/recreate).
  // When the user navigates away and back, a NEW AlbumDetailScreen is created but
  // SmartAlbumService is a singleton — this cache survives.
  // TTL: 10 minutes. After that, a fresh scan is preferred for freshness.
  static const int _maxMemoryCachedAlbums = 3;
  static const int _maxMemoryCachedFilesPerAlbum = 5000;

  static final Map<int, List<String>> _scanResultCache = {};
  static final Map<int, DateTime> _scanResultTimestamp = {};
  static final List<int> _scanResultLru = [];

  static const Duration _scanCacheTtl = Duration(minutes: 10);

  void _touchScanCache(int albumId) {
    _scanResultLru.remove(albumId);
    _scanResultLru.add(albumId);
    while (_scanResultLru.length > _maxMemoryCachedAlbums) {
      final oldest = _scanResultLru.removeAt(0);
      _scanResultCache.remove(oldest);
      _scanResultTimestamp.remove(oldest);
    }
  }

  void _removeScanCache(int albumId) {
    _scanResultCache.remove(albumId);
    _scanResultTimestamp.remove(albumId);
    _scanResultLru.remove(albumId);
  }

  void _storeScanMemoryCache(int albumId, List<String> files) {
    if (files.length > _maxMemoryCachedFilesPerAlbum) {
      _removeScanCache(albumId);
      return;
    }
    _scanResultCache[albumId] = List<String>.from(files, growable: false);
    _scanResultTimestamp[albumId] = DateTime.now();
    _touchScanCache(albumId);
  }

  Future<String> _getFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_fileName';
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final path = await _getFilePath();
      final f = File(path);
      if (!await f.exists()) {
        return {
          'smartAlbumIds': <int>[],
          'roots': <String, List<String>>{},
          'cache': <String, Map<String, dynamic>>{},
        };
      }
      final content = await f.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return {
        'smartAlbumIds': <int>[],
        'roots': <String, List<String>>{},
        'cache': <String, Map<String, dynamic>>{},
      };
    }
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final path = await _getFilePath();
    final f = File(path);
    await f.writeAsString(jsonEncode(data));
  }

  Future<List<int>> getSmartAlbumIds() async {
    final data = await _read();
    final list = (data['smartAlbumIds'] as List?) ?? [];
    return list.map((e) => e as int).toList();
  }

  Future<bool> isSmartAlbum(int albumId) async {
    final ids = await getSmartAlbumIds();
    return ids.contains(albumId);
  }

  Future<void> setSmartAlbum(int albumId, bool smart) async {
    final data = await _read();
    final ids = ((data['smartAlbumIds'] as List?) ?? [])
        .map((e) => e as int)
        .toSet();
    if (smart) {
      ids.add(albumId);
    } else {
      ids.remove(albumId);
    }
    data['smartAlbumIds'] = ids.toList();
    await _write(data);
  }

  // Scan roots per album (directories to scan for smart rules)
  Future<List<String>> getScanRoots(int albumId) async {
    final data = await _read();
    final roots = (data['roots'] as Map?) ?? {};
    final list = roots['$albumId'];
    if (list is List) {
      return list.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<void> setScanRoots(int albumId, List<String> directories) async {
    final data = await _read();
    final roots =
        (data['roots'] as Map?)?.map(
          (k, v) => MapEntry(
            k.toString(),
            (v as List).map((e) => e.toString()).toList(),
          ),
        ) ??
        {};
    roots['$albumId'] = directories.toSet().toList();
    data['roots'] = roots;
    await _write(data);
  }

  Future<void> addScanRoots(int albumId, List<String> directories) async {
    final current = await getScanRoots(albumId);
    final updated = {...current, ...directories}.toList();
    await setScanRoots(albumId, updated);
  }

  Future<void> removeScanRoots(int albumId, List<String> directories) async {
    final current = await getScanRoots(albumId);
    final updated = current.where((d) => !directories.contains(d)).toList();
    await setScanRoots(albumId, updated);
  }

  // Cache scanned file paths and last scan timestamp per album.
  // Reads from in-memory cache first (instant), falls back to disk JSON cache.
  Future<List<String>> getCachedFiles(int albumId) async {
    // Fast path: in-memory cache (survives widget dispose/recreate).
    final cached = _scanResultCache[albumId];
    final timestamp = _scanResultTimestamp[albumId];
    if (cached != null && timestamp != null) {
      if (DateTime.now().difference(timestamp) < _scanCacheTtl) {
        _touchScanCache(albumId);
        return List<String>.from(cached);
      }
      // Expired — remove.
      _removeScanCache(albumId);
    }

    // Slow path: read from disk JSON.
    final data = await _read();
    final cache = (data['cache'] as Map?) ?? {};
    final entry = cache['$albumId'];
    if (entry is Map) {
      final files = entry['files'];
      if (files is List) {
        final result = files.map((e) => e.toString()).toList();
        // Promote to in-memory cache.
        _storeScanMemoryCache(albumId, result);
        return result;
      }
    }
    return [];
  }

  Future<DateTime?> getLastScanTime(int albumId) async {
    // Check in-memory first.
    final timestamp = _scanResultTimestamp[albumId];
    if (timestamp != null) {
      _touchScanCache(albumId);
      return timestamp;
    }

    final data = await _read();
    final cache = (data['cache'] as Map?) ?? {};
    final entry = cache['$albumId'];
    if (entry is Map) {
      final ts = entry['lastScan'];
      if (ts is String) {
        try {
          return DateTime.parse(ts);
        } catch (_) {}
      }
    }
    return null;
  }

  Future<void> setCachedFiles(int albumId, List<String> files) async {
    // Update in-memory cache immediately.
    _storeScanMemoryCache(albumId, files);

    // Persist to disk JSON for cross-session survival.
    final data = await _read();
    final cache =
        (data['cache'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? {};
    cache['$albumId'] = {
      'files': files,
      'lastScan': DateTime.now().toIso8601String(),
    };
    data['cache'] = cache;
    await _write(data);
  }
}
