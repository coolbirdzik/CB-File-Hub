import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Disk-persisted cache for video library file lists.
/// Each library is stored as a separate JSON file so we don't load
/// all libraries' file lists into memory at once.
///
/// Cache invalidation:
/// - invalidateLibrary(libraryId) → re-scan on next open
/// - clearAll() → wipe all cached library file lists
class VideoLibraryCacheService {
  static const String _cacheDirName = 'video_library_cache';
  static VideoLibraryCacheService? _instance;

  static VideoLibraryCacheService get instance {
    _instance ??= VideoLibraryCacheService._();
    return _instance!;
  }

  VideoLibraryCacheService._();

  String? _cacheDirPath;

  Future<Directory> get _cacheDir async {
    if (_cacheDirPath != null) return Directory(_cacheDirPath!);
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/$_cacheDirName');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    _cacheDirPath = cacheDir.path;
    return cacheDir;
  }

  String _cacheFileName(int libraryId) => 'library_$libraryId.json';

  Future<File> _cacheFile(int libraryId) async {
    final dir = await _cacheDir;
    return File('${dir.path}/${_cacheFileName(libraryId)}');
  }

  /// Load cached file paths for a library. Returns null if no cache exists.
  /// Paths are validated — only existing files are returned.
  ///
  /// File existence checks are batched in parallel for performance
  /// (up to [_existsParallelism] concurrent checks).
  static const int _existsParallelism = 50;

  Future<List<String>?> loadCachedFiles(int libraryId) async {
    try {
      final file = await _cacheFile(libraryId);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final paths = (data['files'] as List?)?.cast<String>() ?? [];

      if (paths.isEmpty) return <String>[];

      // Validate file existence in parallel batches for performance.
      // Sequential checks on 5000+ files are extremely slow, especially
      // across multiple drives.
      final validPaths = <String>[];
      for (int i = 0; i < paths.length; i += _existsParallelism) {
        final batch = paths.skip(i).take(_existsParallelism).toList();
        final results = await Future.wait(batch.map((p) => File(p).exists()));
        for (int j = 0; j < batch.length; j++) {
          if (results[j]) {
            validPaths.add(batch[j]);
          }
        }
      }
      return validPaths;
    } catch (e) {
      debugPrint(
        'VideoLibraryCache: failed to load cache for library $libraryId: $e',
      );
      return null;
    }
  }

  /// Save the file list for a library to disk cache.
  Future<void> saveFiles(int libraryId, List<String> filePaths) async {
    try {
      final file = await _cacheFile(libraryId);
      final data = {
        'libraryId': libraryId,
        'savedAt': DateTime.now().toIso8601String(),
        'files': filePaths,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint(
        'VideoLibraryCache: failed to save cache for library $libraryId: $e',
      );
    }
  }

  /// Invalidate (delete) the cache for a specific library.
  /// Call this after files are deleted or moved so the next open
  /// forces a re-scan from disk.
  Future<void> invalidateLibrary(int libraryId) async {
    try {
      final file = await _cacheFile(libraryId);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint(
        'VideoLibraryCache: failed to invalidate library $libraryId: $e',
      );
    }
  }

  /// Clear all cached library file lists.
  Future<void> clearAll() async {
    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('VideoLibraryCache: failed to clear cache: $e');
    }
  }

  /// Get the cache directory for stats/cleanup purposes.
  Future<Directory> getCacheDirectory() => _cacheDir;

  /// Get the total number of cached libraries.
  Future<int> getCachedLibraryCount() async {
    try {
      final dir = await _cacheDir;
      if (!await dir.exists()) return 0;
      final files = await dir.list().toList();
      return files
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .length;
    } catch (_) {
      return 0;
    }
  }
}
