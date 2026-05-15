import 'dart:convert';
import 'dart:io';

import '../../utils/app_logger.dart';

/// The result of reading a file's text content.
class FileContent {
  final String text;
  final int totalLength;
  final bool isTruncated;

  const FileContent({
    required this.text,
    required this.totalLength,
    required this.isTruncated,
  });

  static const empty =
      FileContent(text: '', totalLength: 0, isTruncated: false);
}

/// Reads text file content with size limits, encoding fallback, and LRU caching.
///
/// Used by [FileContextBuilder] to provide file content to the AI agent.
class ContentReader {
  /// Maximum number of cached files.
  static const int _maxCacheEntries = 50;

  /// Maximum total cached bytes.
  static const int _maxCacheBytes = 100 * 1024; // 100 KB

  /// Maximum file size to attempt reading (1 MB).
  static const int _maxFileSize = 1 * 1024 * 1024;

  /// Default character limit for content reading.
  final int maxChars;

  /// File extensions considered as text files.
  static const Set<String> textExtensions = {
    '.txt',
    '.md',
    '.json',
    '.xml',
    '.yaml',
    '.yml',
    '.csv',
    '.log',
    '.ini',
    '.cfg',
    '.conf',
    '.toml',
    '.html',
    '.htm',
    '.css',
    '.js',
    '.ts',
    '.dart',
    '.py',
    '.java',
    '.kt',
    '.swift',
    '.c',
    '.cpp',
    '.h',
    '.rs',
    '.go',
    '.rb',
    '.php',
    '.sh',
    '.bat',
    '.ps1',
    '.sql',
    '.jsx',
    '.tsx',
    '.vue',
    '.svelte',
    '.scss',
    '.sass',
    '.less',
    '.env',
    '.gitignore',
    '.dockerignore',
    '.editorconfig',
    '.properties',
    '.gradle',
    '.cmake',
    '.makefile',
  };

  /// LRU cache: path → FileContent. Ordered by most-recently-used last.
  final Map<String, FileContent> _cache = {};
  int _cacheTotalBytes = 0;

  ContentReader({this.maxChars = 2000});

  /// Returns `true` if the file extension indicates a text file.
  static bool isTextFile(String path) {
    final ext = _extensionOf(path);
    return textExtensions.contains(ext);
  }

  /// Reads the text content of a file, up to [maxChars] characters.
  ///
  /// Returns [FileContent.empty] if the file is too large, unreadable,
  /// or not a text file.
  Future<FileContent> readFile(String path) async {
    // Check cache first
    if (_cache.containsKey(path)) {
      // Move to end (most recently used)
      final cached = _cache.remove(path)!;
      _cache[path] = cached;
      return cached;
    }

    try {
      final file = File(path);
      if (!await file.exists()) return FileContent.empty;

      final stat = await file.stat();
      if (stat.size > _maxFileSize) {
        return FileContent(
          text: '',
          totalLength: stat.size,
          isTruncated: true,
        );
      }

      final content = await _readWithEncodingFallback(file);
      final totalLength = content.length;
      final truncated = totalLength > maxChars;
      final text = truncated ? content.substring(0, maxChars) : content;

      final result = FileContent(
        text: text,
        totalLength: totalLength,
        isTruncated: truncated,
      );

      _addToCache(path, result);
      return result;
    } catch (e) {
      AppLogger.debug('[ContentReader] Failed to read $path: $e');
      return FileContent.empty;
    }
  }

  /// Reads multiple files sequentially.
  Future<Map<String, FileContent>> readFiles(List<String> paths) async {
    if (paths.isEmpty) return {};

    final results = <String, FileContent>{};
    for (final path in paths) {
      results[path] = await readFile(path);
    }
    return results;
  }

  /// Clears the content cache.
  void clearCache() {
    _cache.clear();
    _cacheTotalBytes = 0;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<String> _readWithEncodingFallback(File file) async {
    return _readWithEncodingFallbackStatic(file);
  }

  static Future<String> _readWithEncodingFallbackStatic(File file) async {
    try {
      return await file.readAsString(encoding: utf8);
    } catch (_) {
      try {
        return await file.readAsString(encoding: latin1);
      } catch (_) {
        return '';
      }
    }
  }

  void _addToCache(String path, FileContent content) {
    final size = content.text.length;

    // Evict oldest entries if necessary
    while (_cache.length >= _maxCacheEntries ||
        (_cacheTotalBytes + size > _maxCacheBytes && _cache.isNotEmpty)) {
      final oldestKey = _cache.keys.first;
      final oldest = _cache.remove(oldestKey)!;
      _cacheTotalBytes -= oldest.text.length;
    }

    _cache[path] = content;
    _cacheTotalBytes += size;
  }

  static String _extensionOf(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot < 0) return '';
    return path.substring(lastDot).toLowerCase();
  }
}
