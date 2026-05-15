import 'dart:io';

import 'package:path/path.dart' as pathlib;

import '../../helpers/core/filesystem_utils.dart';
import '../../helpers/tags/tag_manager.dart';
import '../../utils/app_logger.dart';
import 'content_reader.dart';

/// The scope of a file search for AI context building.
enum SearchScope {
  currentDirectory,
  recursive,
  taggedFiles,
  allDrives,
  videoLibrary,
  album
}

String searchScopeDisplayName(SearchScope scope) {
  switch (scope) {
    case SearchScope.currentDirectory:
      return 'Current Folder';
    case SearchScope.recursive:
      return 'Recursive Search';
    case SearchScope.taggedFiles:
      return 'Tagged Files';
    case SearchScope.allDrives:
      return 'All Drives';
    case SearchScope.videoLibrary:
      return 'Video Library';
    case SearchScope.album:
      return 'Album';
  }
}

/// A single file's metadata and optional content for AI context.
class _FileContext {
  final String path;
  final String name;
  final String extension;
  final int sizeBytes;
  final DateTime modified;
  final DateTime? created;
  final String category;
  final List<String> tags;
  final FileContent? content;

  _FileContext({
    required this.path,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.modified,
    this.created,
    required this.category,
    required this.tags,
    this.content,
  });
}

/// Builds structured file context strings for the AI to reason over.
///
/// Prioritizes metadata (name, tags, dates) and optionally reads text file
/// content. Used by [AiAgentBloc] to construct the system prompt.
class FileContextBuilder {
  final ContentReader _contentReader;

  /// Maximum number of files to include in context.
  static const int _maxFiles = 500;

  /// Callback to report progress during context building.
  final void Function(String step, int fileCount)? onProgress;

  FileContextBuilder({ContentReader? contentReader, this.onProgress})
      : _contentReader = contentReader ?? ContentReader();

  Future<String> buildContext({
    required String directoryPath,
    required SearchScope scope,
    bool includeContent = true,
  }) async {
    // If path is empty and scope is currentDirectory/recursive, auto-switch to allDrives
    final effectiveScope =
        (directoryPath.isEmpty &&
                (scope == SearchScope.currentDirectory ||
                    scope == SearchScope.recursive))
            ? SearchScope.allDrives
            : scope;

    List<_FileContext> fileContexts;

    switch (effectiveScope) {
      case SearchScope.currentDirectory:
        onProgress?.call('Scanning folder...', 0);
        fileContexts = await _scanDirectory(
          directoryPath,
          recursive: false,
          includeContent: includeContent,
        );
        break;
      case SearchScope.recursive:
        onProgress?.call('Scanning recursively...', 0);
        fileContexts = await _scanDirectory(
          directoryPath,
          recursive: true,
          includeContent: includeContent,
        );
        break;
      case SearchScope.taggedFiles:
        onProgress?.call('Loading tagged files...', 0);
        fileContexts = await _buildTaggedFilesContext(includeContent);
        break;
      case SearchScope.allDrives:
        onProgress?.call('Scanning all drives...', 0);
        fileContexts = await _scanAllDrives(includeContent);
        break;
      case SearchScope.videoLibrary:
      case SearchScope.album:
        onProgress?.call('Scanning folder...', 0);
        fileContexts = await _scanDirectory(
          directoryPath,
          recursive: false,
          includeContent: includeContent,
        );
        break;
    }

    onProgress?.call('Building context...', fileContexts.length);
    final rootLabel = directoryPath.isEmpty ? 'All Drives' : directoryPath;
    return _formatContext(fileContexts, rootLabel);
  }

  /// Builds a minimal metadata-only context for quick search.
  Future<String> buildQuickContext(String directoryPath) async {
    return buildContext(
      directoryPath: directoryPath,
      scope: SearchScope.currentDirectory,
      includeContent: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Directory scanning
  // ---------------------------------------------------------------------------

  Future<List<_FileContext>> _scanDirectory(
    String directoryPath, {
    required bool recursive,
    required bool includeContent,
  }) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];

    final entries = <FileSystemEntity>[];
    try {
      await for (final entity in dir.list(
        recursive: recursive,
        followLinks: false,
      )) {
        if (entity is File) {
          entries.add(entity);
          if (entries.length >= _maxFiles) break;
        }
      }
    } catch (e) {
      AppLogger.debug('[FileContextBuilder] Error scanning $directoryPath: $e');
    }

    // Collect text file paths for batch content reading
    final textFilePaths = <String>[];
    if (includeContent) {
      for (final entity in entries) {
        if (ContentReader.isTextFile(entity.path)) {
          textFilePaths.add(entity.path);
        }
      }
    }

    // Read text content in batch
    final contentMap = includeContent && textFilePaths.isNotEmpty
        ? await _contentReader.readFiles(textFilePaths)
        : <String, FileContent>{};

    // Build context objects
    final contexts = <_FileContext>[];
    for (final entity in entries) {
      try {
        final stat = await entity.stat();
        final name = pathlib.basename(entity.path);
        final ext = pathlib.extension(entity.path).toLowerCase();
        final tags = await TagManager.getTags(entity.path);
        final content = contentMap[entity.path];

        contexts.add(_FileContext(
          path: entity.path,
          name: name,
          extension: ext,
          sizeBytes: stat.size,
          modified: stat.modified,
          created: stat.changed != stat.modified ? stat.changed : null,
          category: _categorize(ext),
          tags: tags,
          content: content,
        ));
      } catch (e) {
        // Skip files we can't stat
        continue;
      }
    }

    return contexts;
  }

  /// Scans all available drives/storage locations (top-level, non-recursive).
  Future<List<_FileContext>> _scanAllDrives(bool includeContent) async {
    final locations = await getAllStorageLocations();
    final allContexts = <_FileContext>[];

    for (final dir in locations) {
      if (allContexts.length >= _maxFiles) break;
      onProgress?.call('Scanning ${dir.path}...', allContexts.length);
      final dirContexts = await _scanDirectory(
        dir.path,
        recursive: true,
        includeContent: includeContent,
      );
      allContexts.addAll(dirContexts);
    }

    // Also include tagged files
    if (allContexts.length < _maxFiles) {
      onProgress?.call('Loading tagged files...', allContexts.length);
      final taggedContexts = await _buildTaggedFilesContext(includeContent);
      final seenPaths = allContexts.map((c) => c.path).toSet();
      for (final ctx in taggedContexts) {
        if (allContexts.length >= _maxFiles) break;
        if (!seenPaths.contains(ctx.path)) {
          allContexts.add(ctx);
        }
      }
    }

    return allContexts;
  }

  Future<List<_FileContext>> _buildTaggedFilesContext(
      bool includeContent) async {
    final allTags = await TagManager.getAllUniqueTags('');
    final seenPaths = <String>{};
    final contexts = <_FileContext>[];

    for (final tag in allTags) {
      if (contexts.length >= _maxFiles) break;
      final files = await TagManager.findFilesByTagGlobally(tag);
      for (final entity in files) {
        if (contexts.length >= _maxFiles) break;
        final filePath = entity.path;
        if (seenPaths.contains(filePath)) continue;
        seenPaths.add(filePath);

        try {
          final file = File(filePath);
          if (!await file.exists()) continue;
          final stat = await file.stat();
          final name = pathlib.basename(filePath);
          final ext = pathlib.extension(filePath).toLowerCase();
          final tags = await TagManager.getTags(filePath);

          FileContent? content;
          if (includeContent && ContentReader.isTextFile(filePath)) {
            content = await _contentReader.readFile(filePath);
          }

          contexts.add(_FileContext(
            path: filePath,
            name: name,
            extension: ext,
            sizeBytes: stat.size,
            modified: stat.modified,
            created: stat.changed != stat.modified ? stat.changed : null,
            category: _categorize(ext),
            tags: tags,
            content: content,
          ));
        } catch (_) {
          continue;
        }
      }
    }

    return contexts;
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  String _formatContext(List<_FileContext> files, String rootPath) {
    if (files.isEmpty) return 'No files found in the current scope.';

    final buffer = StringBuffer();
    buffer.writeln('Total files: ${files.length}');
    buffer.writeln('Root directory: $rootPath');
    buffer.writeln('---');

    for (final file in files) {
      buffer.writeln('File: ${file.name}');
      buffer.writeln('  Path: ${file.path}');
      buffer.writeln('  Type: ${file.category} (${file.extension})');
      buffer.writeln('  Size: ${_formatSize(file.sizeBytes)}');
      buffer.writeln('  Modified: ${file.modified.toIso8601String()}');
      if (file.created != null) {
        buffer.writeln('  Created: ${file.created!.toIso8601String()}');
      }
      if (file.tags.isNotEmpty) {
        buffer.writeln('  Tags: ${file.tags.join(', ')}');
      }
      if (file.content != null && file.content!.text.isNotEmpty) {
        buffer.writeln('  Content preview (${file.content!.text.length} chars'
            '${file.content!.isTruncated ? ', truncated' : ''}):');
        buffer.writeln('  ---');
        // Indent content lines
        for (final line in file.content!.text.split('\n').take(20)) {
          buffer.writeln('  $line');
        }
        buffer.writeln('  ---');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _categorize(String ext) {
    const imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.ico', '.tiff', '.tif', '.heic', '.heif'};
    const videoExts = {'.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.ts', '.mpg', '.mpeg', '.3gp'};
    const audioExts = {'.mp3', '.wav', '.flac', '.aac', '.ogg', '.wma', '.m4a', '.opus'};
    const documentExts = {'.doc', '.docx', '.odt', '.rtf', '.pdf'};
    const spreadsheetExts = {'.xls', '.xlsx', '.ods', '.csv'};
    const presentationExts = {'.ppt', '.pptx', '.odp'};
    const archiveExts = {'.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz'};

    if (imageExts.contains(ext)) return 'Image';
    if (videoExts.contains(ext)) return 'Video';
    if (audioExts.contains(ext)) return 'Audio';
    if (documentExts.contains(ext)) return 'Document';
    if (spreadsheetExts.contains(ext)) return 'Spreadsheet';
    if (presentationExts.contains(ext)) return 'Presentation';
    if (archiveExts.contains(ext)) return 'Archive';
    if (ContentReader.isTextFile('file$ext')) return 'Text/Code';
    return 'Other';
  }
}
