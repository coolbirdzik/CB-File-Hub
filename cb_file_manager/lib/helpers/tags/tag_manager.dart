import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;
import 'package:path_provider/path_provider.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:cb_file_manager/utils/app_logger.dart';

/// A utility class for managing file tags globally
///
/// Tags are stored in SQLite and can still import legacy JSON data.
class TagManager {
  // Singleton instance
  static TagManager? _instance;

  // In-memory cache to improve performance
  static final Map<String, List<String>> _tagsCache = {};

  // Global tags file name
  static const String globalTagsFilename = 'cb_file_hub_global_tags.json';

  // Path to the global tags file (initialized lazily)
  static String? _globalTagsPath;

  // Database manager for SQLite storage
  static DatabaseManager? _databaseManager;

  // Flag indicating if database storage is available
  static bool _useDatabase = false;
  static String? _lastStandaloneTagError;
  static final List<String> _standaloneTagDiagnostics = <String>[];

  // User preferences for checking if Database is enabled
  static final UserPreferences _preferences = UserPreferences.instance;

  // Thêm một StreamController để phát thông báo khi tags thay đổi
  static final StreamController<String> _tagChangeController =
      StreamController<String>.broadcast();

  // Stream công khai để lắng nghe thay đổi tag
  static Stream<String> get onTagChanged => _tagChangeController.stream;

  // Cache for tags to avoid constantly reading from files
  static final Map<String, List<String>> _tagCache = {};

  // Method to notify the app about tag changes
  void notifyTagChanged(String filePath) {
    debugPrint("TagManager: Notifying tag change for path: $filePath");
    // Fire the static stream that FileGridItem and other widgets are listening to
    _tagChangeController.add(filePath);
  }

  /// Dispose resources — only closes the static controller (shared singleton).
  /// The instance no longer owns its own controller.
  void dispose() {
    // No-op: static controller is shared and closed by the framework
  }

  // Private singleton constructor
  TagManager._();

  // Singleton instance getter
  static TagManager get instance {
    if (_instance == null) {
      _instance = TagManager._();
      initialize();
    }
    return _instance!;
  }

  static void _recordStandaloneTagDiagnostic(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _standaloneTagDiagnostics.add('[$timestamp] $message');
    if (_standaloneTagDiagnostics.length > 30) {
      _standaloneTagDiagnostics.removeRange(
        0,
        _standaloneTagDiagnostics.length - 30,
      );
    }
  }

  static String get standaloneTagDiagnostics =>
      _standaloneTagDiagnostics.join('\n');

  /// Check if a file has a specific tag
  ///
  /// This is a synchronous version that uses the cache
  bool hasTag(FileSystemEntity entity, String tagQuery) {
    if (tagQuery.isEmpty) return false;
    if (_tagsCache.containsKey(entity.path)) {
      final tags = _tagsCache[entity.path]!;
      return tags
          .any((tag) => tag.toLowerCase().contains(tagQuery.toLowerCase()));
    }
    return false;
  }

  /// Get frequently used tags (most common tags in the system)
  /// Returns a map of tags with their usage count
  Future<Map<String, int>> getPopularTags({int limit = 10}) async {
    await initialize();

    final Map<String, int> tagFrequency = {};

    if (_useDatabase && _databaseManager != null) {
      // Get all unique tags from Database
      final allUniqueTags = await _databaseManager!.getAllUniqueTags();

      // Count how many files each tag appears in
      for (final tag in allUniqueTags) {
        final files = await _databaseManager!.findFilesByTag(tag);
        tagFrequency[tag] = files.length;
      }
    } else {
      // Use original implementation for JSON file
      final tagsData = await _loadGlobalTags();

      // Count frequency of each tag
      for (final List<dynamic> tagList in tagsData.values) {
        for (final tag in tagList) {
          if (tag is String) {
            tagFrequency[tag] = (tagFrequency[tag] ?? 0) + 1;
          }
        }
      }
    }

    // Sort by frequency and take the top ones
    final sortedTags = tagFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final Map<String, int> result = {};
    for (int i = 0; i < sortedTags.length && i < limit; i++) {
      result[sortedTags[i].key] = sortedTags[i].value;
    }

    return result;
  }

  /// Returns tags that match a query string
  Future<List<String>> searchTags(String query) async {
    if (query.isEmpty) return [];

    final allTags = await getAllUniqueTags("");
    return allTags
        .where((tag) => tag.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  /// Initialize the global tags system by determining the storage path
  static Future<void> initialize() async {
    try {
      AppLogger.debug('[TagManager] initialize start');
      _recordStandaloneTagDiagnostic('initialize:start');
      await _preferences.init();
      _databaseManager = DatabaseManager.getInstance();
      if (!_databaseManager!.isInitialized()) {
        await _databaseManager!.initialize();
      }
      _useDatabase = true;
      _recordStandaloneTagDiagnostic('initialize:success useDatabase=true');
      AppLogger.info('[TagManager] initialize success',
          error: 'useDatabase=true');
    } catch (error) {
      _recordStandaloneTagDiagnostic('initialize:fallback error=$error');
      AppLogger.error('[TagManager] initialize fallback', error: error);
      debugPrint('TagManager initialization fallback: $error');
      _useDatabase = false;

      final appDir = await getApplicationDocumentsDirectory();
      final cbFileHubDir = Directory('${appDir.path}/cb_file_hub');
      if (!await cbFileHubDir.exists()) {
        await cbFileHubDir.create(recursive: true);
      }
      _globalTagsPath = '${cbFileHubDir.path}/$globalTagsFilename';
    }
  }

  /// Gets the path to the global tags file
  static Future<String> _getGlobalTagsFilePath() async {
    await initialize();
    return _globalTagsPath!;
  }

  /// Load all tags from the global tags file
  static Future<Map<String, dynamic>> _loadGlobalTags() async {
    final tagsFilePath = await _getGlobalTagsFilePath();
    final file = File(tagsFilePath);

    // If the new path doesn't exist, try to find and migrate from legacy locations
    if (!await file.exists()) {
      try {
        final migrated = await _tryMigrateFromLegacyLocations(tagsFilePath);
        if (!migrated) {
          return {};
        }
      } catch (_) {
        return {};
      }
    }

    try {
      final content = await file.readAsString();
      return json.decode(content);
    } catch (e) {
      return {};
    }
  }

  /// Attempt to migrate tags file from legacy locations to the current path.
  /// Returns true if a legacy file was found and migrated.
  static Future<bool> _tryMigrateFromLegacyLocations(String targetPath) async {
    try {
      // Known legacy locations to check
      final List<String> candidates = [];

      // 1) Home directory fallback used by older builds on some platforms
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        candidates.add('$home/$globalTagsFilename');
        candidates.add('$home/cb_file_hub/$globalTagsFilename');
      }

      // 2) App documents directory without the "cb_file_hub" subfolder (older layout)
      try {
        final appDir = await getApplicationDocumentsDirectory();
        candidates.add('${appDir.path}/$globalTagsFilename');
      } catch (_) {}

      // Find the first existing legacy file
      String? legacyPath;
      for (final path in candidates) {
        if (await File(path).exists()) {
          legacyPath = path;
          break;
        }
      }

      if (legacyPath == null) return false;

      // Ensure target directory exists
      final targetDir = File(targetPath).parent;
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // Try rename (move); if it fails (e.g., cross-device), fallback to copy
      try {
        await File(legacyPath).rename(targetPath);
      } catch (_) {
        final data = await File(legacyPath).readAsBytes();
        await File(targetPath).writeAsBytes(data);
      }

      debugPrint('TagManager: Migrated legacy tags file from $legacyPath');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Save all tags to the global tags file
  static Future<bool> _saveGlobalTags(Map<String, dynamic> tagsData) async {
    final tagsFilePath = await _getGlobalTagsFilePath();
    final file = File(tagsFilePath);

    try {
      await file.writeAsString(json.encode(tagsData));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Gets all tags for a file
  ///
  /// Returns an empty list if no tags are found
  static Future<List<String>> getTags(String filePath) async {
    if (_tagsCache.containsKey(filePath)) {
      return List.from(_tagsCache[filePath]!);
    }

    await initialize();

    try {
      if (_useDatabase && _databaseManager != null) {
        // Use Database to get tags
        final tags = await _databaseManager!.getTagsForFile(filePath);
        _tagsCache[filePath] = tags;
        return tags;
      } else {
        // Use original implementation for JSON file
        final tagsData = await _loadGlobalTags();

        // Use the absolute file path as the key in the global tags file
        if (tagsData.containsKey(filePath)) {
          final tags = List<String>.from(tagsData[filePath]);
          _tagsCache[filePath] = tags;
          return tags;
        }

        _tagsCache[filePath] = [];
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  /// Gets tags for multiple files at once (batch loading for performance)
  ///
  /// This method is much more efficient than calling getTags() for each file
  /// because it only reads the global tags file once.
  ///
  /// Returns a map of file paths to their tags
  static Future<Map<String, List<String>>> getTagsForFiles(
      List<String> filePaths) async {
    if (filePaths.isEmpty) return {};

    final stopwatch = Stopwatch()..start();
    final result = <String, List<String>>{};
    final uncachedPaths = <String>[];

    // First, get all cached tags
    for (final path in filePaths) {
      if (_tagsCache.containsKey(path)) {
        final tags = _tagsCache[path]!;
        if (tags.isNotEmpty) {
          result[path] = List.from(tags);
        }
      } else {
        uncachedPaths.add(path);
      }
    }

    AppLogger.perf(
        '⏱️ [PERF] TagManager.getTagsForFiles: ${result.length} cached, ${uncachedPaths.length} uncached');

    if (uncachedPaths.isEmpty) {
      AppLogger.perf(
          '⏱️ [PERF] TagManager.getTagsForFiles (all cached) took: ${stopwatch.elapsedMilliseconds}ms');
      return result;
    }

    await initialize();

    try {
      if (_useDatabase && _databaseManager != null) {
        // Use Database - still need to query one by one, but database is fast
        for (final path in uncachedPaths) {
          final tags = await _databaseManager!.getTagsForFile(path);
          _tagsCache[path] = tags;
          if (tags.isNotEmpty) {
            result[path] = tags;
          }
        }
      } else {
        // Use JSON file - load once and get all tags
        final tagsData = await _loadGlobalTags();

        for (final path in uncachedPaths) {
          if (tagsData.containsKey(path)) {
            final tags = List<String>.from(tagsData[path]);
            _tagsCache[path] = tags;
            if (tags.isNotEmpty) {
              result[path] = tags;
            }
          } else {
            _tagsCache[path] = [];
          }
        }
      }
    } catch (e) {
      debugPrint('Error in getTagsForFiles: $e');
    }

    AppLogger.perf(
        '⏱️ [PERF] TagManager.getTagsForFiles for ${filePaths.length} files took: ${stopwatch.elapsedMilliseconds}ms');
    return result;
  }

  /// List to keep track of recently used tags with timestamps
  static List<Map<String, dynamic>> _recentTags = [];
  static const int maxRecentTags = 40;

  /// Add a tag to recent tags list
  static void addToRecentTags(String tag) {
    // Remove tag if it already exists in recent tags
    _recentTags.removeWhere((item) => item['tag'] == tag);

    // Add tag to the beginning of the list with current timestamp
    _recentTags.insert(
        0, {'tag': tag, 'timestamp': DateTime.now().millisecondsSinceEpoch});

    // Limit the list size
    if (_recentTags.length > maxRecentTags) {
      _recentTags = _recentTags.sublist(0, maxRecentTags);
    }

    // Save recent tags to shared preferences for persistence
    _saveRecentTags();
  }

  /// Save recent tags to database
  static Future<void> _saveRecentTags() async {
    try {
      await initialize();
      if (_useDatabase && _databaseManager != null) {
        final jsonString = json.encode(_recentTags);
        await _databaseManager!.saveStringPreference('recent_tags', jsonString);
      } else {
        // Fallback to SharedPreferences for JSON mode
        final prefs = await SharedPreferences.getInstance();
        final jsonString = json.encode(_recentTags);
        await prefs.setString('recent_tags', jsonString);
      }
    } catch (e) {
      // Silently ignore errors when saving recent tags
    }
  }

  /// Load recent tags from database
  static Future<void> _loadRecentTags() async {
    try {
      await initialize();
      String? jsonString;

      if (_useDatabase && _databaseManager != null) {
        jsonString = await _databaseManager!.getStringPreference('recent_tags');
      } else {
        // Fallback to SharedPreferences for JSON mode
        final prefs = await SharedPreferences.getInstance();
        jsonString = prefs.getString('recent_tags');
      }

      if (jsonString != null) {
        final List<dynamic> decoded = json.decode(jsonString);
        _recentTags =
            decoded.map((item) => Map<String, dynamic>.from(item)).toList();
      }
    } catch (e) {
      _recentTags = [];
    }
  }

  /// Get recently added tags
  /// Returns a list of the most recently added tags
  static Future<List<String>> getRecentTags({int limit = 20}) async {
    await initialize();

    // Load recent tags if not already loaded
    if (_recentTags.isEmpty) {
      await _loadRecentTags();
    }

    // Extract tag names from the list
    final List<String> recentTagNames =
        _recentTags.map((item) => item['tag'] as String).toList();

    // Filter out tags that no longer exist in the database
    // so that deleted tags don't reappear in the recent list
    final Set<String> validTags = await getAllUniqueTags('');

    final List<String> filteredRecent =
        recentTagNames.where((tag) => validTags.contains(tag)).toList();

    // Take only up to the limit
    final List<String> result = filteredRecent.take(limit).toList();

    // If we don't have enough stored recent tags, supplement with popular tags
    if (result.length < limit) {
      // Get popular tags excluding the ones we already have
      final popularTags =
          await TagManager.instance.getPopularTags(limit: limit * 2);

      for (final entry in popularTags.entries) {
        if (result.length >= limit) break;
        if (!result.contains(entry.key)) {
          result.add(entry.key);
        }
      }
    }

    return result;
  }

  /// Static wrapper for instance method
  static Future<bool> addTag(String filePath, String tag) async {
    try {
      await initialize();

      // Add to recent tags - use static method directly
      if (tag.trim().isNotEmpty) {
        addToRecentTags(tag.trim());
      }

      if (_useDatabase && _databaseManager != null) {
        return await _databaseManager!.addTagToFile(filePath, tag);
      } else {
        Map<String, dynamic> tagsData = await _loadGlobalTags();

        // Get existing tags or create new list
        final tags = List<String>.from(tagsData[filePath] ?? []);
        if (!tags.contains(tag)) {
          tags.add(tag);
          tagsData[filePath] = tags;
          final success = await _saveGlobalTags(tagsData);

          if (success) {
            _tagsCache[filePath] = tags;
          }

          // Thông báo thay đổi qua Stream
          _tagChangeController.add(filePath);

          return success;
        }
        return true;
      }
    } catch (e) {
      return false;
    }
  }

  /// Static wrapper for instance method
  static Future<bool> removeTag(String filePath, String tag) async {
    try {
      await initialize();

      if (_useDatabase && _databaseManager != null) {
        return await _databaseManager!.removeTagFromFile(filePath, tag);
      } else {
        Map<String, dynamic> tagsData = await _loadGlobalTags();
        if (!tagsData.containsKey(filePath)) return true;

        final tags = List<String>.from(tagsData[filePath]);
        if (tags.contains(tag)) {
          tags.remove(tag);

          if (tags.isEmpty) {
            tagsData.remove(filePath);
          } else {
            tagsData[filePath] = tags;
          }

          final success = await _saveGlobalTags(tagsData);
          if (success) {
            if (tags.isEmpty) {
              _tagsCache.remove(filePath);
            } else {
              _tagsCache[filePath] = tags;
            }
          }

          // Thông báo thay đổi qua Stream
          _tagChangeController.add(filePath);

          return success;
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error removing tag from $filePath: $e');
      return false;
    }
  }

  /// Add tags to multiple files using static method
  static Future<bool> addTagToFiles(List<String> filePaths, String tag) async {
    bool success = true;
    for (final path in filePaths) {
      if (!await TagManager.addTag(path, tag)) {
        success = false;
      }
    }
    return success;
  }

  /// Remove tags from multiple files using static method
  static Future<bool> removeTagFromFiles(
      List<String> filePaths, String tag) async {
    bool success = true;
    for (final path in filePaths) {
      if (!await TagManager.removeTag(path, tag)) {
        success = false;
      }
    }
    return success;
  }

  /// Set the full set of tags for a file (replaces existing tags)
  ///
  /// Returns true if successful, false otherwise
  static Future<bool> setTags(String filePath, List<String> tags) async {
    try {
      AppLogger.info('[TagManager] setTags START',
          error: 'filePath=$filePath incomingTags=$tags');
      debugPrint(
          '[TagManager] setTags START filePath=$filePath incomingTags=$tags');
      await initialize();

      // First validate tags (remove empty ones)
      final validTags = tags.where((tag) => tag.trim().isNotEmpty).toList();
      AppLogger.debug('[TagManager] setTags normalized',
          error:
              'filePath=$filePath validTags=$validTags useDatabase=$_useDatabase');
      debugPrint(
          '[TagManager] setTags normalized filePath=$filePath validTags=$validTags useDatabase=$_useDatabase');

      if (_useDatabase && _databaseManager != null) {
        // Use Database to set tags
        final success =
            await _databaseManager!.setTagsForFile(filePath, validTags);
        AppLogger.info('[TagManager] setTags database result',
            error: 'filePath=$filePath success=$success');
        debugPrint(
            '[TagManager] setTags database result filePath=$filePath success=$success');

        if (success) {
          // Update cache
          if (validTags.isEmpty) {
            _tagsCache.remove(filePath);
          } else {
            _tagsCache[filePath] = validTags;
          }
        }

        // Thông báo thay đổi qua Stream
        _tagChangeController.add(filePath);

        return success;
      } else {
        // Use original implementation for JSON file
        Map<String, dynamic> tagsData = await _loadGlobalTags();

        if (validTags.isEmpty) {
          // Remove entry if no tags
          if (tagsData.containsKey(filePath)) {
            tagsData.remove(filePath);
          }
        } else {
          tagsData[filePath] = validTags;
        }

        final success = await _saveGlobalTags(tagsData);
        AppLogger.info('[TagManager] setTags json result',
            error: 'filePath=$filePath success=$success');
        debugPrint(
            '[TagManager] setTags json result filePath=$filePath success=$success');

        if (success) {
          // Update cache
          if (validTags.isEmpty) {
            _tagsCache.remove(filePath);
          } else {
            _tagsCache[filePath] = validTags;
          }
        }

        // Thông báo thay đổi qua Stream
        _tagChangeController.add(filePath);

        return success;
      }
    } catch (e) {
      AppLogger.error('[TagManager] setTags ERROR',
          error: 'filePath=$filePath error=$e');
      debugPrint('[TagManager] setTags ERROR filePath=$filePath error=$e');
      return false;
    }
  }

  /// Gets all unique tags across all files
  ///
  /// Returns a set of unique tags
  static Future<Set<String>> getAllUniqueTags(String directoryPath) async {
    // Note: directoryPath parameter is kept for backward compatibility
    // but is no longer used since tags are global

    final Set<String> allTags = {};

    try {
      await initialize();

      if (_useDatabase && _databaseManager != null) {
        // Use Database to get all unique tags
        allTags.addAll(await _databaseManager!.getAllUniqueTags());
      } else {
        // Use original implementation for JSON file
        final tagsData = await _loadGlobalTags();

        for (final tags in tagsData.values) {
          if (tags is List) {
            for (final tag in tags) {
              if (tag is String) {
                allTags.add(tag);
              }
            }
          }
        }
      }

      // Standalone tags are global tags too and should be visible anywhere
      // the app asks for the full tag catalog.
      allTags.addAll(await getStandaloneTags());

      return allTags;
    } catch (e) {
      debugPrint('Error getting all tags: $e');
      return allTags;
    }
  }

  /// Finds all files with a specific tag
  ///
  /// Returns a list of files with the tag (no longer includes directories)
  static Future<List<FileSystemEntity>> findFilesByTag(
      String directoryPath, String tag) async {
    final List<FileSystemEntity> results = [];
    final Set<String> addedPaths =
        {}; // Thêm Set để theo dõi file đã được thêm vào
    final String normalizedTag = tag.toLowerCase().trim();

    if (normalizedTag.isEmpty) {
      debugPrint('Tag is empty, returning empty results');
      return results;
    }

    try {
      await initialize();
      debugPrint(
          'Finding files with tag: "$normalizedTag" in directory: "$directoryPath"');

      // Normalize directory path
      String normalizedDirPath = directoryPath;
      if (!normalizedDirPath.endsWith(Platform.pathSeparator)) {
        normalizedDirPath += Platform.pathSeparator;
      }

      debugPrint('Normalized directory path: $normalizedDirPath');

      // Step 1: First search current directory (faster)
      if (_useDatabase && _databaseManager != null) {
        // Use Database to find files by tag
        final filePaths = await _databaseManager!.findFilesByTag(normalizedTag);
        debugPrint(
            'Found ${filePaths.length} file paths with tag: "$normalizedTag"');

        // Only get paths belonging to current directory
        for (final path in filePaths) {
          if ((path.startsWith(normalizedDirPath) ||
                  path.startsWith(directoryPath)) &&
              !addedPaths.contains(path)) {
            try {
              // Only check for files, not directories
              final file = File(path);
              final isFile = await file.exists();

              if (isFile) {
                // It's a file
                results.add(file);
                addedPaths.add(path); // Đánh dấu path đã được thêm vào
                debugPrint('Added file to results: $path');
              }
            } catch (e) {
              debugPrint('Error checking entity type for $path: $e');
            }
          }
        }
      } else {
        // Use original implementation for JSON file
        final tagsData = await _loadGlobalTags();
        debugPrint('Loaded ${tagsData.length} entries with tags');

        // For each path in the global tags data
        for (final entityPath in tagsData.keys) {
          if (addedPaths.contains(entityPath)) continue; // Bỏ qua nếu đã thêm

          final tags = List<String>.from(tagsData[entityPath] ?? []);

          // Check if file has the matching tag
          final hasMatchingTag = tags.any((fileTag) {
            return fileTag.toLowerCase() == normalizedTag ||
                fileTag.toLowerCase().contains(normalizedTag);
          });

          // Only process if file has matching tag
          if (hasMatchingTag) {
            // Check if path is in the current directory
            if (entityPath.startsWith(normalizedDirPath) ||
                entityPath.startsWith(directoryPath)) {
              try {
                // Only check for files, not directories
                final file = File(entityPath);
                final isFile = await file.exists();

                if (isFile) {
                  // It's a file
                  results.add(file);
                  addedPaths.add(entityPath); // Đánh dấu path đã được thêm vào
                  debugPrint('Added file to results: $entityPath');
                }
              } catch (e) {
                debugPrint('Error checking entity type for $entityPath: $e');
              }
            }
          }
        }
      }

      // Step 2: Search in subdirectories (lazy approach)
      // Get immediate subdirectories from the current directory
      final directory = Directory(directoryPath);
      if (await directory.exists()) {
        try {
          // Get all subdirectories in the current directory
          final List<Directory> subdirectories = await directory
              .list()
              .where((entity) => entity is Directory)
              .map((entity) => entity as Directory)
              .toList();

          // Search in each subdirectory (first level only for laziness)
          for (final subdir in subdirectories) {
            // Get all files in the subdirectory (non-recursive)
            try {
              final subdirEntities = await subdir.list().toList();

              // Check tags for each file in the subdirectory
              for (final entity in subdirEntities) {
                if (entity is File && !addedPaths.contains(entity.path)) {
                  final fileTags = await getTags(entity.path);
                  if (fileTags.any((fileTag) =>
                      fileTag.toLowerCase() == normalizedTag ||
                      fileTag.toLowerCase().contains(normalizedTag))) {
                    results.add(entity);
                    addedPaths
                        .add(entity.path); // Đánh dấu path đã được thêm vào
                  }
                }
              }
            } catch (e) {
              debugPrint(
                  'Error listing files in subdirectory ${subdir.path}: $e');
            }
          }
        } catch (e) {
          debugPrint('Error searching in subdirectories: $e');
        }
      }

      debugPrint('Found ${results.length} files with tag: "$normalizedTag"');
      return results;
    } catch (e) {
      debugPrint('Error finding files by tag: $e');
      return results;
    }
  }

  /// Find files with a specific tag anywhere in the file system
  ///
  /// Returns a list of files with the tag (no longer includes directories)
  static Future<List<FileSystemEntity>> findFilesByTagGlobally(
      String tag) async {
    final List<FileSystemEntity> results = [];
    final Set<String> addedPaths = {}; // Theo dõi file đã được thêm
    final String normalizedTag = tag.toLowerCase().trim();

    if (normalizedTag.isEmpty) {
      debugPrint('Tag is empty, returning empty results');
      return results;
    }

    try {
      await initialize();
      debugPrint('Finding files with tag: "$normalizedTag" globally');

      // Xóa cache để đảm bảo dữ liệu mới nhất
      clearCache();

      if (_useDatabase && _databaseManager != null) {
        // Use Database to find files by tag - QUAN TRỌNG: Tìm kiếm chính xác dựa trên tag
        final filePaths = await _databaseManager!.findFilesByTag(normalizedTag);
        debugPrint(
            'Found ${filePaths.length} file paths with tag: "$normalizedTag"');

        // Convert paths to FileSystemEntity objects - only include files, not directories
        for (final path in filePaths) {
          if (addedPaths.contains(path)) continue; // Bỏ qua nếu đã thêm

          try {
            // Check if it's a file
            final file = File(path);
            final isFile = await file.exists();

            if (isFile) {
              // It's a file
              results.add(file);
              addedPaths.add(path); // Đánh dấu path đã được thêm
              debugPrint('Added file to results: $path');
            }
          } catch (e) {
            debugPrint('Error checking entity type for $path: $e');
          }
        }
      } else {
        // Use original implementation for JSON file
        final tagsData = await _loadGlobalTags();
        debugPrint('Loaded ${tagsData.length} entries with tags from JSON');

        // For each path in the global tags data
        for (final entityPath in tagsData.keys) {
          if (addedPaths.contains(entityPath)) continue;

          try {
            final tags = tagsData[entityPath];
            if (tags is! List) continue;

            final tagsList = List<String>.from(tags);

            // Check if file has the matching tag
            final hasMatchingTag = tagsList.any((fileTag) {
              return fileTag.toLowerCase() == normalizedTag ||
                  fileTag.toLowerCase().contains(normalizedTag);
            });

            if (hasMatchingTag) {
              // Check if it's a file
              final file = File(entityPath);
              final isFile = await file.exists();

              if (isFile) {
                // It's a file
                results.add(file);
                addedPaths.add(entityPath);
                debugPrint('Added file to results from JSON: $entityPath');
              }
            }
          } catch (e) {
            debugPrint('Error checking entity in JSON for $entityPath: $e');
          }
        }
      }

      debugPrint(
          'Found ${results.length} files with tag: "$normalizedTag" globally');
      return results;
    } catch (e) {
      debugPrint('Error finding files by tag globally: $e');
      return results;
    }
  }

  /// Clears the tags cache to free memory
  static void clearCache() {
    debugPrint("Clearing all tag caches...");

    // Clear all caches - make sure to clear all possible caches
    _tagsCache.clear();
    _tagCache.clear();

    // Clear global tags path to force reload
    _globalTagsPath = null;

    // Force re-initialize database connection
    if (_useDatabase && _databaseManager != null) {
      try {
        // Chỉ log, không block luồng
        debugPrint("Resetting database connection...");
      } catch (e) {
        debugPrint("Error resetting database: $e");
      }
    }

    // Debugging output
    debugPrint("Tag caches cleared completely!");
  }

  /// Migrate from directory-based tags to global tags
  ///
  /// This function scans all .tags files in the specified root directory
  /// and its subdirectories, and migrates the tags to the global tags file.
  static Future<int> migrateToGlobalTags(String rootDirectory) async {
    int migratedFileCount = 0;

    try {
      await initialize();

      final rootDir = Directory(rootDirectory);
      if (!await rootDir.exists()) {
        return 0;
      }

      // Load the current global tags data
      Map<String, dynamic> globalTags = await _loadGlobalTags();

      // Find all .tags files
      await for (final entity in rootDir.list(recursive: true)) {
        if (entity is File && pathlib.basename(entity.path) == '.tags') {
          try {
            final content = await entity.readAsString();
            final Map<String, dynamic> localTagsJson = json.decode(content);
            final String dirPath = entity.parent.path;

            // Process each file in the local tags file
            for (final fileName in localTagsJson.keys) {
              if (localTagsJson[fileName] is List) {
                final tags = List<String>.from(localTagsJson[fileName]);
                if (tags.isNotEmpty) {
                  final filePath = pathlib.join(dirPath, fileName);
                  final file = File(filePath);

                  // Only migrate if the file exists
                  if (await file.exists()) {
                    if (_useDatabase && _databaseManager != null) {
                      // Save to Database
                      await _databaseManager!.setTagsForFile(filePath, tags);
                    } else {
                      // Save to JSON file
                      globalTags[filePath] = tags;
                    }
                    migratedFileCount++;
                  }
                }
              }
            }

            // Delete the old .tags file after migration
            await entity.delete();
          } catch (e) {
            debugPrint('Error migrating tags from ${entity.path}: $e');
          }
        }
      }

      // Save the updated global tags if using JSON storage
      if (!_useDatabase) {
        await _saveGlobalTags(globalTags);
      }

      return migratedFileCount;
    } catch (e) {
      debugPrint('Error during tags migration: $e');
      return migratedFileCount;
    }
  }

  /// Migrate from JSON file storage to Database
  ///
  /// This function loads all tags from the global JSON file
  /// and migrates them to the Database.
  static Future<int> migrateFromJsonToDatabase() async {
    int migratedFileCount = 0;

    try {
      await initialize();

      if (!_useDatabase || _databaseManager == null) {
        throw Exception('SQLite storage is not available');
      }

      // Load all tags from the JSON file
      final tagsData = await _loadGlobalTags();

      // Migrate each file's tags to SQLite
      for (final filePath in tagsData.keys) {
        final tags = List<String>.from(tagsData[filePath]);
        if (tags.isNotEmpty) {
          final success =
              await _databaseManager!.setTagsForFile(filePath, tags);
          if (success) {
            migratedFileCount++;
          }
        }
      }

      debugPrint('Migrated $migratedFileCount files to SQLite database');
      return migratedFileCount;
    } catch (e) {
      debugPrint('Error migrating from JSON to SQLite: $e');
      return migratedFileCount;
    }
  }

  /// Deletes a tag from all files in the system
  static Future<void> deleteTagGlobally(String tag) async {
    final instance = TagManager.instance;

    try {
      // Find all files with this tag
      final filePaths =
          await instance._findFilesByTagInternal(tag.toLowerCase().trim());

      // Remove tag from each file
      for (final path in filePaths) {
        await removeTag(path, tag);
      }

      // Also remove from standalone tags if present
      await removeStandaloneTag(tag);

      // Clear cache to ensure fresh data
      clearCache();

      // Notify about the change through the global notification
      instance.notifyTagChanged("global:tag_deleted");
      // Also notify through the static stream if anyone is still using it
      _tagChangeController.add("global:tag_deleted");
    } catch (e) {
      debugPrint('Error deleting tag globally: $e');
      rethrow;
    }
  }

  static Set<String> _decodeStandaloneTagsJson(String? encodedTags) {
    if (encodedTags == null || encodedTags.isEmpty) {
      return <String>{};
    }

    try {
      final decoded = jsonDecode(encodedTags);
      if (decoded is List) {
        return decoded.cast<String>().toSet();
      }
    } catch (e) {
      debugPrint('Error parsing standalone tags: $e');
    }

    return <String>{};
  }

  static Future<Set<String>> _loadStandaloneTagsFromDatabase() async {
    if (!_useDatabase || _databaseManager == null) {
      return <String>{};
    }

    return await _databaseManager!.getStandaloneTags();
  }

  static Future<Set<String>> _loadLegacyStandaloneTags() async {
    final legacyTags = <String>{};

    if (_useDatabase && _databaseManager != null) {
      final encodedTags =
          await _databaseManager!.getStringPreference('standalone_tags');
      legacyTags.addAll(_decodeStandaloneTagsJson(encodedTags));
    }

    final prefs = await SharedPreferences.getInstance();
    legacyTags
        .addAll(_decodeStandaloneTagsJson(prefs.getString('standalone_tags')));
    return legacyTags;
  }

  static Future<bool> _persistStandaloneTags(Set<String> standaloneTags) async {
    try {
      if (_useDatabase && _databaseManager != null) {
        print(
            '[SEED_DIRECT] persist db count=${standaloneTags.length} useDatabase=$_useDatabase');
        _recordStandaloneTagDiagnostic(
          'persist:database count=${standaloneTags.length}',
        );
        AppLogger.debug(
          '[TagManager] Persisting standalone tags to database',
          error: 'count=${standaloneTags.length}',
        );
        final savedToDatabase = await _databaseManager!
            .replaceStandaloneTags(standaloneTags.toList());
        if (savedToDatabase) {
          print(
              '[SEED_DIRECT] persist db success count=${standaloneTags.length}');
          _lastStandaloneTagError = null;
          _recordStandaloneTagDiagnostic(
            'persist:database success count=${standaloneTags.length}',
          );
          AppLogger.info(
            '[TagManager] Persisted standalone tags to database',
            error: 'count=${standaloneTags.length}',
          );
          await _databaseManager!.deletePreference('standalone_tags');
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('standalone_tags');
          return true;
        }
        _lastStandaloneTagError = _databaseManager!.getLastErrorMessage() ??
            'replaceStandaloneTags returned false';
        print('[SEED_DIRECT] persist db failed error=$_lastStandaloneTagError');
        _recordStandaloneTagDiagnostic(
          'persist:database failed error=$_lastStandaloneTagError',
        );
        AppLogger.error(
          '[TagManager] Failed to persist standalone tags to database',
          error: _lastStandaloneTagError,
        );
        return false;
      }

      final encodedTags = jsonEncode(standaloneTags.toList());
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString('standalone_tags', encodedTags);
      print('[SEED_DIRECT] persist shared_preferences saved=$saved');
      _lastStandaloneTagError =
          saved ? null : 'SharedPreferences.setString returned false';
      _recordStandaloneTagDiagnostic(
        'persist:shared_preferences saved=$saved count=${standaloneTags.length}',
      );
      AppLogger.warning(
        '[TagManager] Persisted standalone tags using SharedPreferences fallback',
        error: 'count=${standaloneTags.length} saved=$saved',
      );
      return saved;
    } catch (e) {
      print('[SEED_DIRECT] persist exception=$e');
      _lastStandaloneTagError = e.toString();
      _recordStandaloneTagDiagnostic('persist:exception error=$e');
      AppLogger.error(
        '[TagManager] Exception while persisting standalone tags',
        error: e,
      );
      debugPrint('Error persisting standalone tags: $e');
      return false;
    }
  }

  static String? get lastStandaloneTagError => _lastStandaloneTagError;

  static Future<Set<String>> _getStandaloneTagsFromActiveStorage() async {
    if (_useDatabase && _databaseManager != null) {
      _recordStandaloneTagDiagnostic('load:backend=database');
      final sqliteTags = await _loadStandaloneTagsFromDatabase();
      final legacyTags = await _loadLegacyStandaloneTags();
      final mergedTags = <String>{...sqliteTags, ...legacyTags};
      _recordStandaloneTagDiagnostic(
        'load:counts sqlite=${sqliteTags.length} legacy=${legacyTags.length} merged=${mergedTags.length}',
      );

      if (mergedTags.isEmpty) {
        return <String>{};
      }

      if (legacyTags.isNotEmpty &&
          legacyTags.difference(sqliteTags).isNotEmpty) {
        await _persistStandaloneTags(mergedTags);
      }

      return mergedTags;
    }

    _recordStandaloneTagDiagnostic('load:backend=shared_preferences');
    return await _loadLegacyStandaloneTags();
  }

  /// Batch-add multiple standalone tags at once (1 read + 1 write, much faster than calling addStandaloneTag N times)
  static Future<int> addMultipleStandaloneTags(List<String> tags) async {
    try {
      await initialize();

      final standaloneTags = <String>{...await getStandaloneTags()};

      final before = standaloneTags.length;
      standaloneTags.addAll(tags);
      _recordStandaloneTagDiagnostic(
        'addMultiple:incoming=${tags.length} before=$before after=${standaloneTags.length}',
      );
      AppLogger.debug(
        '[TagManager] addMultipleStandaloneTags',
        error:
            'incoming=${tags.length} before=$before after=${standaloneTags.length}',
      );
      final saved = await _persistStandaloneTags(standaloneTags);
      if (!saved) {
        _recordStandaloneTagDiagnostic(
          'addMultiple:failed error=$_lastStandaloneTagError',
        );
        return 0;
      }

      _tagChangeController.add('global:standalone_tags_bulk_added');
      _recordStandaloneTagDiagnostic(
        'addMultiple:success added=${standaloneTags.length - before}',
      );
      return standaloneTags.length - before;
    } catch (e) {
      debugPrint('Error adding multiple standalone tags: $e');
      return 0;
    }
  }

  /// Saves a standalone tag (created but not yet assigned to any file)
  static Future<bool> addStandaloneTag(String tag) async {
    try {
      await initialize();

      final standaloneTags = await getStandaloneTags();
      standaloneTags.add(tag);
      final saved = await _persistStandaloneTags(standaloneTags);
      if (!saved) {
        return false;
      }

      // Notify about standalone tag change
      _tagChangeController.add('global:standalone_tag_added:$tag');
      return true;
    } catch (e) {
      debugPrint('Error adding standalone tag: $e');
      return false;
    }
  }

  /// Gets all standalone tags from the active storage backend
  static Future<Set<String>> getStandaloneTags() async {
    try {
      await initialize();
      return await _getStandaloneTagsFromActiveStorage();
    } catch (e) {
      debugPrint('Error getting standalone tags: $e');
    }
    return <String>{};
  }

  /// Removes a standalone tag from the active storage backend
  static Future<void> removeStandaloneTag(String tag) async {
    try {
      await initialize();
      final standaloneTags = await getStandaloneTags();
      standaloneTags.remove(tag);
      await _persistStandaloneTags(standaloneTags);
      _tagChangeController.add('global:standalone_tag_removed:$tag');
    } catch (e) {
      debugPrint('Error removing standalone tag: $e');
    }
  }

  /// Renames a standalone tag in the active storage backend
  static Future<void> _renameStandaloneTag(String oldTag, String newTag) async {
    try {
      await initialize();
      final standaloneTags = await getStandaloneTags();
      if (!standaloneTags.contains(oldTag)) {
        return;
      }

      standaloneTags.remove(oldTag);
      standaloneTags.add(newTag);
      await _persistStandaloneTags(standaloneTags);
    } catch (e) {
      debugPrint('Error renaming standalone tag: $e');
    }
  }

  /// Renames a tag across all files in the system
  static Future<bool> renameTag(String oldTag, String newTag) async {
    final instance = TagManager.instance;

    if (oldTag.isEmpty || newTag.isEmpty) {
      return false;
    }

    if (oldTag.toLowerCase() == newTag.toLowerCase()) {
      return true;
    }

    try {
      // First, rename standalone tag
      await _renameStandaloneTag(oldTag, newTag);

      // Update file-based tags — separate paths for SQLite and JSON
      try {
        if (_useDatabase && _databaseManager != null) {
          // SQLite path: query database directly, independent of JSON file
          final filesWithTag = await instance
              ._findFilesByTagInternal(oldTag.toLowerCase().trim());
          debugPrint(
              'TagManager.renameTag: Found ${filesWithTag.length} files with tag "$oldTag" in SQLite');

          for (final path in filesWithTag) {
            final currentTags = await getTags(path);
            final updatedTags = currentTags.map((t) {
              if (t.toLowerCase() == oldTag.toLowerCase()) {
                return newTag;
              }
              return t;
            }).toList();
            await _databaseManager!.setTagsForFile(path, updatedTags);
          }
        } else {
          // JSON file path
          final tagsData = await _loadGlobalTags();
          if (tagsData.isNotEmpty) {
            final filesWithTag = <String>[];

            for (final entry in tagsData.entries) {
              final tags = List<String>.from(entry.value);
              if (tags.any((t) => t.toLowerCase() == oldTag.toLowerCase())) {
                filesWithTag.add(entry.key);
              }
            }

            for (final path in filesWithTag) {
              final currentTags = List<String>.from(tagsData[path] ?? []);
              final updatedTags = currentTags.map((t) {
                if (t.toLowerCase() == oldTag.toLowerCase()) {
                  return newTag;
                }
                return t;
              }).toList();
              tagsData[path] = updatedTags;
            }

            await _saveGlobalTags(tagsData);
          }
        }
      } catch (e2) {
        debugPrint('Error updating file tags (non-fatal): $e2');
      }

      clearCache();

      // Notify about the change
      instance.notifyTagChanged("global:tag_renamed:$oldTag:$newTag");
      _tagChangeController.add("global:tag_renamed:$oldTag:$newTag");

      return true;
    } catch (e) {
      debugPrint('Error renaming tag: $e');
      return false;
    }
  }

  /// Find all files that have a specific tag (internal implementation)
  Future<List<String>> _findFilesByTagInternal(String tag) async {
    try {
      // If using Database
      if (_useDatabase && _databaseManager != null) {
        // Query the database for files with this tag
        final tagLowercase = tag.toLowerCase().trim();
        final results = await _databaseManager!.findFilesByTag(tagLowercase);
        return results;
      } else {
        // Use the file search implementation without Database
        return await _searchByTag(tag);
      }
    } catch (e) {
      debugPrint('Error finding files by tag: $e');
      return [];
    }
  }

  /// Search files by tag without using Database
  Future<List<String>> _searchByTag(String tag) async {
    final List<String> results = [];

    // This is a simple implementation to search all files in the system
    // In a real app, you'd use a more efficient approach
    try {
      // Use the tags cache to find files with this tag
      if (_tagCache.isNotEmpty) {
        final normalizedTag = tag.toLowerCase().trim();

        _tagCache.forEach((filePath, tags) {
          if (tags.map((t) => t.toLowerCase().trim()).contains(normalizedTag)) {
            results.add(filePath);
          }
        });
      }
    } catch (e) {
      debugPrint('Error searching for tag: $e');
    }

    return results;
  }
}
