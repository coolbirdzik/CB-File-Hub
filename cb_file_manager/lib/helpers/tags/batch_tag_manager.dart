import 'dart:io';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:flutter/material.dart';

/// Manages batch operations on file tags
class BatchTagManager {
  // Singleton instance
  static BatchTagManager? _instance;

  // Database manager
  static DatabaseManager? _databaseManager;

  // Static reference to UserPreferences
  static final UserPreferences _preferences = UserPreferences.instance;

  // Private constructor
  BatchTagManager._();

  /// Initialize the batch tag manager
  static Future<void> initialize() async {
    try {
      // Initialize user preferences
      await _preferences.init();

      // Initialize database manager
      _databaseManager = DatabaseManager.getInstance();
      await _databaseManager!.initialize();

      debugPrint('BatchTagManager initialized successfully');
    } catch (e) {
      debugPrint('Error initializing BatchTagManager: $e');
    }
  }

  /// Get the singleton instance
  static BatchTagManager getInstance() {
    _instance ??= BatchTagManager._();
    return _instance!;
  }

  /// Add a tag to multiple files
  Future<Map<String, bool>> addTagToFiles(
    List<String> filePaths,
    String tag,
  ) async {
    final Map<String, bool> results = {};

    if (tag.trim().isEmpty || filePaths.isEmpty) {
      return results;
    }

    try {
      // Process each file
      for (final filePath in filePaths) {
        final success = await _databaseManager!.addTagToFile(filePath, tag);
        results[filePath] = success;
      }

      return results;
    } catch (e) {
      debugPrint('Error in batch tag add: $e');

      // Fill remaining files with failure
      for (final filePath in filePaths) {
        if (!results.containsKey(filePath)) {
          results[filePath] = false;
        }
      }

      return results;
    }
  }

  /// Remove a tag from multiple files
  Future<Map<String, bool>> removeTagFromFiles(
    List<String> filePaths,
    String tag,
  ) async {
    final Map<String, bool> results = {};

    if (tag.trim().isEmpty || filePaths.isEmpty) {
      return results;
    }

    try {
      // Process each file
      for (final filePath in filePaths) {
        final success = await _databaseManager!.removeTagFromFile(
          filePath,
          tag,
        );
        results[filePath] = success;
      }

      return results;
    } catch (e) {
      debugPrint('Error in batch tag remove: $e');

      // Fill remaining files with failure
      for (final filePath in filePaths) {
        if (!results.containsKey(filePath)) {
          results[filePath] = false;
        }
      }

      return results;
    }
  }

  /// Get tags for multiple files
  Future<Map<String, List<String>>> getTagsForFiles(
    List<String> filePaths,
  ) async {
    final Map<String, List<String>> results = {};

    if (filePaths.isEmpty) {
      return results;
    }

    try {
      // Process each file
      for (final filePath in filePaths) {
        final tags = await _databaseManager!.getTagsForFile(filePath);
        results[filePath] = tags;
      }

      return results;
    } catch (e) {
      debugPrint('Error getting tags for multiple files: $e');

      // Fill remaining files with empty lists
      for (final filePath in filePaths) {
        if (!results.containsKey(filePath)) {
          results[filePath] = [];
        }
      }

      return results;
    }
  }

  /// Replace tags in multiple files with a set of new tags
  Future<Map<String, bool>> setTagsForFiles(
    Map<String, List<String>> fileTagsMap,
  ) async {
    final Map<String, bool> results = {};

    if (fileTagsMap.isEmpty) {
      return results;
    }

    try {
      // Process each file
      for (final filePath in fileTagsMap.keys) {
        final tags = fileTagsMap[filePath] ?? [];
        final success = await _databaseManager!.setTagsForFile(filePath, tags);
        results[filePath] = success;
      }

      return results;
    } catch (e) {
      debugPrint('Error setting tags for multiple files: $e');

      // Fill remaining files with failure
      for (final filePath in fileTagsMap.keys) {
        if (!results.containsKey(filePath)) {
          results[filePath] = false;
        }
      }

      return results;
    }
  }

  /// Find common tags among multiple files
  Future<List<String>> findCommonTags(List<String> filePaths) async {
    if (filePaths.isEmpty) {
      return [];
    }

    try {
      // Get tags for each file
      final Map<String, List<String>> allTags = await getTagsForFiles(
        filePaths,
      );

      if (allTags.isEmpty) {
        return [];
      }

      // Find common tags using set intersection
      Set<String>? commonTags;

      for (final tags in allTags.values) {
        if (commonTags == null) {
          // Initialize with the tags of the first file
          commonTags = Set.from(tags);
        } else {
          // Intersect with subsequent files' tags
          commonTags = commonTags.intersection(Set.from(tags));
        }

        // Short-circuit if no common tags remain
        if (commonTags.isEmpty) {
          break;
        }
      }

      return commonTags?.toList() ?? [];
    } catch (e) {
      debugPrint('Error finding common tags: $e');
      return [];
    }
  }

  /// Add a tag to all files in a directory (recursive)
  Future<int> tagDirectory(
    String directoryPath,
    String tag, {
    bool recursive = true,
  }) async {
    if (tag.trim().isEmpty) {
      return 0;
    }

    int count = 0;

    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return 0;
      }

      // Get all entities in the directory
      final List<FileSystemEntity> entities = await directory
          .list(recursive: recursive)
          .where((entity) => entity is File)
          .toList();

      // Process files in batches to avoid overwhelming the database
      const int batchSize = 50;
      for (int i = 0; i < entities.length; i += batchSize) {
        final int end = (i + batchSize < entities.length)
            ? i + batchSize
            : entities.length;
        final batch = entities.sublist(i, end);

        // Add tag to batch of files
        final batchResults = await addTagToFiles(
          batch.map((entity) => entity.path).toList(),
          tag,
        );

        // Count successes
        count += batchResults.values.where((success) => success).length;
      }

      return count;
    } catch (e) {
      debugPrint('Error tagging directory: $e');
      return count;
    }
  }

  /// Copy all tags from one file to another
  Future<bool> copyTags(String sourceFilePath, String targetFilePath) async {
    try {
      // Get tags from source file
      final tags = await _databaseManager!.getTagsForFile(sourceFilePath);

      // Set tags on target file
      return await _databaseManager!.setTagsForFile(targetFilePath, tags);
    } catch (e) {
      debugPrint('Error copying tags: $e');
      return false;
    }
  }

  /// Copy all tags from one file to multiple files
  Future<Map<String, bool>> copyTagsToMultipleFiles(
    String sourceFilePath,
    List<String> targetFilePaths,
  ) async {
    final Map<String, bool> results = {};

    if (targetFilePaths.isEmpty) {
      return results;
    }

    try {
      // Get tags from source file
      final tags = await _databaseManager!.getTagsForFile(sourceFilePath);

      // Set tags on each target file
      for (final targetPath in targetFilePaths) {
        final success = await _databaseManager!.setTagsForFile(
          targetPath,
          tags,
        );
        results[targetPath] = success;
      }

      return results;
    } catch (e) {
      debugPrint('Error copying tags to multiple files: $e');

      // Fill remaining files with failure
      for (final filePath in targetFilePaths) {
        if (!results.containsKey(filePath)) {
          results[filePath] = false;
        }
      }

      return results;
    }
  }

  /// Apply a tag operation on multiple files
  /// Operation can be 'add', 'remove', or 'set'
  Future<Map<String, bool>> applyTagOperation(
    List<String> filePaths,
    List<String> tags,
    String operation,
  ) async {
    final Map<String, bool> results = {};

    if (filePaths.isEmpty || tags.isEmpty) {
      return results;
    }

    try {
      switch (operation.toLowerCase()) {
        case 'add':
          // Add each tag to all files
          for (final tag in tags) {
            if (tag.trim().isNotEmpty) {
              final addResults = await addTagToFiles(filePaths, tag);

              // Update results
              for (final filePath in addResults.keys) {
                final success = addResults[filePath] ?? false;
                results[filePath] = results[filePath] ?? true && success;
              }
            }
          }
          break;

        case 'remove':
          // Remove each tag from all files
          for (final tag in tags) {
            if (tag.trim().isNotEmpty) {
              final removeResults = await removeTagFromFiles(filePaths, tag);

              // Update results
              for (final filePath in removeResults.keys) {
                final success = removeResults[filePath] ?? false;
                results[filePath] = results[filePath] ?? true && success;
              }
            }
          }
          break;

        case 'set':
          // Set the same tags for all files
          final Map<String, List<String>> fileTagsMap = {};

          for (final filePath in filePaths) {
            fileTagsMap[filePath] = tags;
          }

          final setResults = await setTagsForFiles(fileTagsMap);
          results.addAll(setResults);
          break;

        default:
          debugPrint('Invalid tag operation: $operation');
          for (final filePath in filePaths) {
            results[filePath] = false;
          }
      }

      return results;
    } catch (e) {
      debugPrint('Error applying tag operation: $e');

      // Fill remaining files with failure
      for (final filePath in filePaths) {
        if (!results.containsKey(filePath)) {
          results[filePath] = false;
        }
      }

      return results;
    }
  }

  /// Add tags to multiple files
  static Future<bool> addTagsToFiles(List<String> filePaths, String tag) async {
    bool success = true;
    for (final path in filePaths) {
      if (!await TagManager.addTag(path, tag)) {
        success = false;
      }
    }
    return success;
  }

  /// Remove a tag from multiple files - static helper method
  static Future<bool> removeTagFromFilesStatic(
    List<String> filePaths,
    String tag,
  ) async {
    bool success = true;
    for (final path in filePaths) {
      if (!await TagManager.removeTag(path, tag)) {
        success = false;
      }
    }
    return success;
  }
}
