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
    final ids =
        ((data['smartAlbumIds'] as List?) ?? []).map((e) => e as int).toSet();
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
    final roots = (data['roots'] as Map?)?.map((k, v) => MapEntry(
            k.toString(), (v as List).map((e) => e.toString()).toList())) ??
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

  // Cache scanned file paths and last scan timestamp per album
  Future<List<String>> getCachedFiles(int albumId) async {
    final data = await _read();
    final cache = (data['cache'] as Map?) ?? {};
    final entry = cache['$albumId'];
    if (entry is Map) {
      final files = entry['files'];
      if (files is List) return files.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<DateTime?> getLastScanTime(int albumId) async {
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
