import 'package:cb_file_manager/models/database/database_provider.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'dart:async'; // Thêm import này để sử dụng Completer
import 'dart:convert'; // Added for JSON encoding/decoding
import 'dart:io'; // Added for File operations
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Database manager for centralizing access to the database
class DatabaseManager implements IDatabaseProvider {
  // Singleton instance
  static DatabaseManager? _instance;

  // Semaphore để kiểm soát việc khởi tạo đồng thời
  static final _initSemaphore = _AsyncSemaphore();

  // Database provider implementation
  late IDatabaseProvider _provider;

  // User preferences for checking if ObjectBox is enabled

  // Flag to track if cloud sync is enabled
  bool _cloudSyncEnabled = false;

  // Flag to track if the manager is initialized
  bool _isInitialized = false;

  // Private constructor
  DatabaseManager._();

  /// Get the singleton instance of the database manager
  static DatabaseManager getInstance() {
    _instance ??= DatabaseManager._();
    return _instance!;
  }

  /// Initialize the database manager
  @override
  Future<void> initialize() async {
    // Sử dụng semaphore để đảm bảo chỉ một lần khởi tạo được thực hiện
    return _initSemaphore.run(() async {
      // Check both flags inside the semaphore to prevent race between
      // concurrent callers who both passed the outer check.
      // ignore: unnecessary_null_comparison
      if (_isInitialized && _provider != null) {
        return;
      }

      try {
        // Tạo provider mà không cần khởi tạo UserPreferences
        _provider = SqliteDatabaseProvider();

        // Thêm cơ chế retry để đảm bảo database khởi động được
        int retryCount = 0;
        const maxRetries = 3;
        bool initSuccess = false;

        while (!initSuccess && retryCount < maxRetries) {
          try {
            // Initialize the provider
            await _provider.initialize();
            initSuccess = true;
          } catch (e) {
            retryCount++;

            // Nếu vẫn còn cơ hội thử lại, đợi một chút trước khi thử lại
            if (retryCount < maxRetries) {
              await Future.delayed(Duration(milliseconds: 500 * retryCount));
            } else {
              throw Exception(
                  'Failed to initialize database after $maxRetries attempts: $e');
            }
          }
        }

        _isInitialized = true;
      } catch (e) {
        _isInitialized = false;

        // Preserve retry capability for later calls after a transient failure.
        rethrow;
      }
    });
  }

  /// Check if the manager is initialized
  @override
  bool isInitialized() {
    return _isInitialized;
  }

  @override
  String? getLastErrorMessage() {
    return _provider.getLastErrorMessage();
  }

  /// Close the database connection
  @override
  Future<void> close() async {
    if (_isInitialized) {
      await _provider.close();
      _isInitialized = false;
    }
  }

  /// Đảm bảo DatabaseManager đã được khởi tạo trước khi sử dụng
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Add a tag to a file
  @override
  Future<bool> addTagToFile(String filePath, String tag) async {
    await _ensureInitialized();
    return _provider.addTagToFile(filePath, tag);
  }

  /// Remove a tag from a file
  @override
  Future<bool> removeTagFromFile(String filePath, String tag) async {
    await _ensureInitialized();
    return _provider.removeTagFromFile(filePath, tag);
  }

  /// Get all tags for a file
  @override
  Future<List<String>> getTagsForFile(String filePath) async {
    await _ensureInitialized();
    return _provider.getTagsForFile(filePath);
  }

  /// Set all tags for a file (replaces existing tags)
  @override
  Future<bool> setTagsForFile(String filePath, List<String> tags) async {
    await _ensureInitialized();
    return _provider.setTagsForFile(filePath, tags);
  }

  /// Finds all files tagged with a specific tag
  @override
  Future<List<String>> findFilesByTag(String tag) async {
    debugPrint('DatabaseManager: Finding files with tag: "$tag"');

    // Trim và lowercase tag để tìm kiếm chính xác hơn
    final normalizedTag = tag.trim().toLowerCase();

    if (!_isInitialized) {
      await _ensureInitialized();
    }

    try {
      // Sử dụng provider hiện tại để tìm kiếm tag
      final List<String> results =
          await _provider.findFilesByTag(normalizedTag);

      debugPrint(
          'DatabaseManager: Found ${results.length} files with tag "$normalizedTag"');

      // In ra thông tin chi tiết về các file được tìm thấy
      for (final path in results) {
        debugPrint('DatabaseManager: Found file: $path');
      }

      return results;
    } catch (e) {
      debugPrint('DatabaseManager: Error finding files by tag: $e');
      return [];
    }
  }

  /// Get all unique tags in the database
  @override
  Future<Set<String>> getAllUniqueTags() async {
    await _ensureInitialized();
    final tags = await _provider.getAllUniqueTags();
    return tags.toSet();
  }

  /// Get all standalone tags in the database
  @override
  Future<Set<String>> getStandaloneTags() async {
    await _ensureInitialized();
    final tags = await _provider.getStandaloneTags();
    return tags.toSet();
  }

  /// Replace all standalone tags in the database
  @override
  Future<bool> replaceStandaloneTags(List<String> tags) async {
    await _ensureInitialized();
    return _provider.replaceStandaloneTags(tags);
  }

  /// Get a string preference
  @override
  Future<String?> getStringPreference(String key,
      {String? defaultValue}) async {
    await _ensureInitialized();
    return _provider.getStringPreference(key, defaultValue: defaultValue);
  }

  /// Save a string preference
  @override
  Future<bool> saveStringPreference(String key, String value) async {
    await _ensureInitialized();
    return _provider.saveStringPreference(key, value);
  }

  /// Get an int preference
  @override
  Future<int?> getIntPreference(String key, {int? defaultValue}) async {
    await _ensureInitialized();
    return _provider.getIntPreference(key, defaultValue: defaultValue);
  }

  /// Save an int preference
  @override
  Future<bool> saveIntPreference(String key, int value) async {
    await _ensureInitialized();
    return _provider.saveIntPreference(key, value);
  }

  /// Get a double preference
  @override
  Future<double?> getDoublePreference(String key,
      {double? defaultValue}) async {
    await _ensureInitialized();
    return _provider.getDoublePreference(key, defaultValue: defaultValue);
  }

  /// Save a double preference
  @override
  Future<bool> saveDoublePreference(String key, double value) async {
    await _ensureInitialized();
    return _provider.saveDoublePreference(key, value);
  }

  /// Get a bool preference
  @override
  Future<bool?> getBoolPreference(String key, {bool? defaultValue}) async {
    await _ensureInitialized();
    return _provider.getBoolPreference(key, defaultValue: defaultValue);
  }

  /// Save a bool preference
  @override
  Future<bool> saveBoolPreference(String key, bool value) async {
    await _ensureInitialized();
    return _provider.saveBoolPreference(key, value);
  }

  /// Delete a preference
  @override
  Future<bool> deletePreference(String key) async {
    await _ensureInitialized();
    return _provider.deletePreference(key);
  }

  /// Get all user preferences as raw data
  @override
  Future<List<Map<String, dynamic>>> getAllPreferencesRaw() async {
    await _ensureInitialized();
    return _provider.getAllPreferencesRaw();
  }

  /// Get a page of user preferences as raw data
  @override
  Future<List<Map<String, dynamic>>> getPreferencesRawPage({
    required int offset,
    required int limit,
  }) async {
    await _ensureInitialized();
    return _provider.getPreferencesRawPage(offset: offset, limit: limit);
  }

  /// Get the total number of raw preference rows
  @override
  Future<int> getPreferencesRawCount() async {
    await _ensureInitialized();
    return _provider.getPreferencesRawCount();
  }

  /// Get all file tags as raw data
  @override
  Future<List<Map<String, dynamic>>> getAllFileTagsRaw() async {
    await _ensureInitialized();
    return _provider.getAllFileTagsRaw();
  }

  /// Get a page of file tags as raw data
  @override
  Future<List<Map<String, dynamic>>> getFileTagsRawPage({
    required int offset,
    required int limit,
  }) async {
    await _ensureInitialized();
    return _provider.getFileTagsRawPage(offset: offset, limit: limit);
  }

  /// Get the total number of raw file tag rows
  @override
  Future<int> getFileTagsRawCount() async {
    await _ensureInitialized();
    return _provider.getFileTagsRawCount();
  }

  /// Set whether cloud sync is enabled
  @override
  void setCloudSyncEnabled(bool enabled) {
    _cloudSyncEnabled = enabled;
    if (_isInitialized) {
      _provider.setCloudSyncEnabled(enabled);
    }
  }

  /// Check if cloud sync is enabled
  @override
  bool isCloudSyncEnabled() {
    return _cloudSyncEnabled;
  }

  /// Sync data to the cloud
  @override
  Future<bool> syncToCloud() async {
    await _ensureInitialized();
    if (!_cloudSyncEnabled) return false;
    return _provider.syncToCloud();
  }

  /// Sync data from the cloud
  @override
  Future<bool> syncFromCloud() async {
    await _ensureInitialized();
    if (!_cloudSyncEnabled) return false;
    return _provider.syncFromCloud();
  }

  /// Export database data to a JSON file
  Future<String?> exportDatabase({String? customPath}) async {
    try {
      await _ensureInitialized();

      debugPrint('ExportDatabase: Starting export...');

      // Get all tags in the system
      final Map<String, List<String>> tagsData = {};
      final uniqueTags = await getAllUniqueTags();
      debugPrint('ExportDatabase: Found ${uniqueTags.length} unique tags');

      // For each tag, get all files with that tag
      for (final tag in uniqueTags) {
        final files = await findFilesByTag(tag);
        debugPrint('ExportDatabase: Tag "$tag" has ${files.length} files');
        tagsData[tag] = files;
      }

      // Count total entries
      int totalEntries = 0;
      for (final files in tagsData.values) {
        totalEntries += files.length;
      }
      debugPrint('ExportDatabase: Total tag entries to export: $totalEntries');

      // Create a data structure to export
      final Map<String, dynamic> exportData = {
        'tags': tagsData,
        'exportDate': DateTime.now().toIso8601String(),
        'version': '1.0'
      };

      // Convert to JSON
      final jsonString = jsonEncode(exportData);
      debugPrint('ExportDatabase: JSON string length: ${jsonString.length}');

      String filePath;

      if (customPath != null) {
        // Use the provided custom path
        filePath = customPath;
      } else {
        // Generate a path in the application documents directory
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        filePath =
            path.join(directory.path, 'cb_file_hub_db_export_$timestamp.json');
      }

      final file = File(filePath);
      await file.writeAsString(jsonString);

      debugPrint('ExportDatabase: Exported to $filePath');
      return filePath;
    } catch (e, stackTrace) {
      debugPrint('ExportDatabase error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Import database data from a JSON file
  Future<bool> importDatabase(String filePath,
      {bool skipFileExistenceCheck = false}) async {
    try {
      debugPrint('ImportDatabase: Starting import from $filePath');

      // Ensure database is initialized first
      if (!_isInitialized) {
        debugPrint(
            'ImportDatabase: Database not initialized, initializing now...');
        await initialize();
      }

      debugPrint(
          'ImportDatabase: Database is initialized, isInitialized=$_isInitialized');

      // Read from file
      final exportFile = File(filePath);
      if (!await exportFile.exists()) {
        debugPrint('ImportDatabase: Export file not found at $filePath');
        return false;
      }

      final jsonString = await exportFile.readAsString();
      debugPrint(
          'ImportDatabase: Read ${jsonString.length} characters from file');

      // Parse JSON
      final Map<String, dynamic> importData = jsonDecode(jsonString);
      debugPrint(
          'ImportDatabase: Parsed JSON, keys: ${importData.keys.toList()}');

      int importedTagCount = 0;
      int skippedFileCount = 0;
      int failedCount = 0;

      // Import tags
      if (importData.containsKey('tags')) {
        final Map<String, dynamic> tagsData = importData['tags'];
        debugPrint('ImportDatabase: Found ${tagsData.length} tags to import');

        // Process each tag
        for (final tag in tagsData.keys) {
          final List<dynamic> files = tagsData[tag];
          debugPrint(
              'ImportDatabase: Processing tag "$tag" with ${files.length} files');

          // Add the tag to each file
          for (final filePathEntry in files) {
            if (filePathEntry is String) {
              try {
                if (skipFileExistenceCheck) {
                  // Skip file existence check - import tags regardless of file presence
                  // This is useful for network drives or files that will be added later
                  final success = await addTagToFile(filePathEntry, tag);
                  if (success) {
                    importedTagCount++;
                  } else {
                    failedCount++;
                  }
                } else {
                  // Check if file exists before adding tag
                  final fileExists = File(filePathEntry).existsSync();
                  if (fileExists) {
                    final success = await addTagToFile(filePathEntry, tag);
                    if (success) {
                      importedTagCount++;
                    } else {
                      failedCount++;
                    }
                  } else {
                    skippedFileCount++;
                    debugPrint(
                        'ImportDatabase: Skipping file (not exists): $filePathEntry');
                  }
                }
              } catch (e) {
                debugPrint(
                    'ImportDatabase: Error adding tag "$tag" to file "$filePathEntry": $e');
                failedCount++;
              }
            }
          }
        }

        debugPrint(
            'ImportDatabase: Summary - imported: $importedTagCount, skipped: $skippedFileCount, failed: $failedCount');
      } else {
        debugPrint('ImportDatabase: No "tags" key found in import file');
        // Try to import as the old format where key is file path and value is list of tags
        debugPrint(
            'ImportDatabase: Checking for old format (file path -> tags list)...');

        for (final key in importData.keys) {
          if (key == 'tags' || key == 'exportDate' || key == 'version') {
            continue;
          }

          final value = importData[key];
          if (value is List) {
            final filePath = key;
            final tags = value.cast<String>();
            debugPrint(
                'ImportDatabase: Old format - file: $filePath, tags: $tags');

            for (final tag in tags) {
              try {
                final success = await addTagToFile(filePath, tag);
                if (success) {
                  importedTagCount++;
                }
              } catch (e) {
                debugPrint(
                    'ImportDatabase: Error adding tag "$tag" to file "$filePath": $e');
              }
            }
          }
        }

        debugPrint(
            'ImportDatabase: Old format import complete, imported: $importedTagCount');
      }

      // Note: TagManager cache clearing should be handled by the caller after successful import
      // to ensure UI properly refreshes with new data
      if (importedTagCount > 0) {
        debugPrint(
            'ImportDatabase: Import completed successfully with $importedTagCount tags');
        debugPrint(
            'ImportDatabase: Caller should clear TagManager cache to refresh UI');
      }

      return importedTagCount > 0;
    } catch (e, stackTrace) {
      debugPrint('ImportDatabase error: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  @override
  Future<int> countUniqueTaggedFiles() async {
    await _ensureInitialized();
    return _provider.countUniqueTaggedFiles();
  }

  /// Returns the shared SQLite database instance.
  Future<Database> getDatabase() async {
    if (!_isInitialized) {
      await _ensureInitialized();
    }

    if (_provider is SqliteDatabaseProvider) {
      return (_provider as SqliteDatabaseProvider).getDatabase();
    }

    throw StateError('Active database provider does not expose SQLite access');
  }
}

/// Helper class để đảm bảo các hoạt động bất đồng bộ chỉ thực hiện một lần
class _AsyncSemaphore {
  bool _running = false;
  final List<Completer<void>> _queue = [];

  Future<T> run<T>(Future<T> Function() task) async {
    // Nếu đang chạy, đợi trong hàng đợi
    if (_running) {
      final completer = Completer<void>();
      _queue.add(completer);
      await completer.future;
    }

    _running = true;

    try {
      return await task();
    } finally {
      _running = false;
      // Xử lý các task trong hàng đợi
      while (_queue.isNotEmpty) {
        final completer = _queue.removeAt(0);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }
  }
}
