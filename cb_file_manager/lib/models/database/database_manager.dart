import 'dart:isolate';
import 'package:cb_file_manager/helpers/core/batch_file_probe.dart';
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

  /// Clears the singleton so a later `integration_test` run can call [initialize] again (E2E only).
  static void resetSingletonForE2ETest() {
    _instance = null;
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
                'Failed to initialize database after $maxRetries attempts: $e',
              );
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

  /// Get tags for multiple files in a single DB round-trip.
  /// Much more efficient than calling [getTagsForFile] in a loop when
  /// initialising a large grid of items.
  @override
  Future<Map<String, List<String>>> getTagsForFiles(
    List<String> filePaths,
  ) async {
    if (filePaths.isEmpty) return {};
    await _ensureInitialized();
    return _provider.getTagsForFiles(filePaths);
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
    // Trim và lowercase tag để tìm kiếm chính xác hơn
    final normalizedTag = tag.trim().toLowerCase();

    if (!_isInitialized) {
      await _ensureInitialized();
    }

    try {
      // Sử dụng provider hiện tại để tìm kiếm tag
      final List<String> results = await _provider.findFilesByTag(
        normalizedTag,
      );

      return results;
    } catch (e) {
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
  Future<String?> getStringPreference(
    String key, {
    String? defaultValue,
  }) async {
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
  Future<double?> getDoublePreference(
    String key, {
    double? defaultValue,
  }) async {
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
        'version': '1.0',
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
        filePath = path.join(
          directory.path,
          'cb_file_hub_db_export_$timestamp.json',
        );
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
  Future<bool> importDatabase(
    String filePath, {
    bool skipFileExistenceCheck = false,
  }) async {
    try {
      await _ensureInitialized();
      final data = await _readTagBackupJson(filePath);
      if (data.containsKey('tags')) {
        final counts = await _importTagRows(
          _tagRows(data['tags'] as Map<String, dynamic>),
          skipFileExistenceCheck: skipFileExistenceCheck,
        );
        return counts.imported > 0;
      }
      // Legacy path -> tags exports deliberately import missing/network paths.
      Iterable<(String, String)> oldRows() sync* {
        for (final entry in data.entries) {
          if (const ['tags', 'exportDate', 'version'].contains(entry.key)) {
            continue;
          }
          if (entry.value is List) {
            for (final tag in (entry.value as List).cast<String>()) {
              yield (entry.key, tag);
            }
          }
        }
      }

      return (await _importTagRows(
            oldRows(),
            skipFileExistenceCheck: true,
          )).imported >
          0;
    } catch (e, stackTrace) {
      debugPrint('ImportDatabase error: $e\n$stackTrace');
      return false;
    }
  }

  Iterable<(String, String)> _tagRows(Map<String, dynamic> tags) sync* {
    for (final entry in tags.entries) {
      for (final file in (entry.value as List).whereType<String>()) {
        yield (file, entry.key);
      }
    }
  }

  Future<({int imported, int skipped, int failed})> _importTagRows(
    Iterable<(String, String)> rows, {
    required bool skipFileExistenceCheck,
  }) async {
    var imported = 0, skipped = 0, failed = 0;
    final iterator = rows.iterator;
    while (true) {
      final chunk = <(String, String)>[];
      while (chunk.length < 512 && iterator.moveNext()) {
        chunk.add(iterator.current);
      }
      if (chunk.isEmpty) break;
      final paths = chunk.map((r) => r.$1).toSet().toList();
      final flags = skipFileExistenceCheck
          ? List.filled(paths.length, true)
          : await probeFiles(paths);
      final exists = {
        for (var i = 0; i < paths.length; i++) paths[i]: flags[i],
      };
      final accepted = chunk.where((r) => exists[r.$1]!).toList();
      skipped += chunk.length - accepted.length;
      if (accepted.isEmpty) continue;
      final provider = _provider;
      final results = provider is SqliteDatabaseProvider
          ? await provider.addTagsToFiles(accepted)
          : await Future.wait(accepted.map((r) => addTagToFile(r.$1, r.$2)));
      imported += results.where((ok) => ok).length;
      failed += results.where((ok) => !ok).length;
    }
    return (imported: imported, skipped: skipped, failed: failed);
  }

  @override
  Future<int> countUniqueTaggedFiles() async {
    await _ensureInitialized();
    return _provider.countUniqueTaggedFiles();
  }

  // ---------------------------------------------------------------------------
  // Tag Metadata (Thumbnails)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> setTagThumbnail(
    String normalizedTag,
    String thumbnailPath,
  ) async {
    await _ensureInitialized();
    return _provider.setTagThumbnail(normalizedTag, thumbnailPath);
  }

  @override
  Future<String?> getTagThumbnail(String normalizedTag) async {
    await _ensureInitialized();
    return _provider.getTagThumbnail(normalizedTag);
  }

  @override
  Future<bool> deleteTagThumbnail(String normalizedTag) async {
    await _ensureInitialized();
    return _provider.deleteTagThumbnail(normalizedTag);
  }

  @override
  Future<Map<String, String>> getAllTagThumbnails() async {
    await _ensureInitialized();
    return _provider.getAllTagThumbnails();
  }

  // ---------------------------------------------------------------------------
  // Tag Hierarchy (Parent-Child relationships)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> setTagHierarchy(
    String parentNormalizedTag,
    String childNormalizedTag,
  ) async {
    await _ensureInitialized();
    return _provider.setTagHierarchy(parentNormalizedTag, childNormalizedTag);
  }

  @override
  Future<bool> removeTagHierarchy(
    String parentNormalizedTag,
    String childNormalizedTag,
  ) async {
    await _ensureInitialized();
    return _provider.removeTagHierarchy(
      parentNormalizedTag,
      childNormalizedTag,
    );
  }

  @override
  Future<List<String>> getChildTags(String parentNormalizedTag) async {
    await _ensureInitialized();
    return _provider.getChildTags(parentNormalizedTag);
  }

  @override
  Future<List<String>> getParentTags(String childNormalizedTag) async {
    await _ensureInitialized();
    return _provider.getParentTags(childNormalizedTag);
  }

  @override
  Future<Map<String, List<String>>> getAllTagHierarchy() async {
    await _ensureInitialized();
    return _provider.getAllTagHierarchy();
  }

  @override
  Future<bool> removeAllHierarchyForTag(String normalizedTag) async {
    await _ensureInitialized();
    return _provider.removeAllHierarchyForTag(normalizedTag);
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

  /// Export both database (tags) and preferences to a single SQLite .db file.
  /// Returns the file path on success, null on failure.
  /// The exported .db contains: file_tags + a preferences table.
  Future<String?> exportAsSqlite({
    required Map<String, Object?> preferences,
    String? customPath,
  }) async {
    try {
      await _ensureInitialized();

      // Get path of running DB
      String dbPath;
      if (_provider is SqliteDatabaseProvider) {
        dbPath = SqliteDatabaseProvider.getDatabasePathSync();
      } else {
        return null;
      }

      if (dbPath.isEmpty) {
        return null;
      }

      // Determine destination path
      String destPath;
      if (customPath != null) {
        destPath = customPath;
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        destPath = path.join(
          directory.path,
          'cb_file_hub_backup_$timestamp.db',
        );
      }

      // Copy the live DB file to destination
      final sourceFile = File(dbPath);
      await sourceFile.copy(destPath);

      // Open destination DB and write preferences table
      final dbFactory = _provider is SqliteDatabaseProvider
          ? (_provider as SqliteDatabaseProvider).getDatabaseFactory()
          : null;

      if (dbFactory != null) {
        final backupDb = await dbFactory.openDatabase(
          destPath,
          options: OpenDatabaseOptions(),
        );

        // Create preferences table if not exists
        await backupDb.execute('''
          CREATE TABLE IF NOT EXISTS preferences (
            key TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            value TEXT
          )
        ''');

        // Upsert each preference
        for (final entry in preferences.entries) {
          final key = entry.key;
          final value = entry.value;
          String? typeStr;
          String? serialized;

          if (value == null) {
            typeStr = 'null';
            serialized = null;
          } else if (value is String) {
            typeStr = 'String';
            serialized = value;
          } else if (value is int) {
            typeStr = 'int';
            serialized = value.toString();
          } else if (value is double) {
            typeStr = 'double';
            serialized = value.toString();
          } else if (value is bool) {
            typeStr = 'bool';
            serialized = value.toString();
          } else if (value is List) {
            typeStr = 'List';
            serialized = value.join('\x00'); // null-byte separator
          }

          await backupDb.execute(
            'INSERT OR REPLACE INTO preferences (key, type, value) VALUES (?, ?, ?)',
            [key, typeStr, serialized],
          );
        }

        await backupDb.close();
      }

      return destPath;
    } catch (_) {
      return null;
    }
  }

  /// Auto-detect file type and import.
  /// .db = SQLite file backup (tags + preferences)
  /// .json = JSON backup (legacy or unified)
  /// Returns a summary map on success, null on failure.
  Future<Map<String, dynamic>?> importUnified({
    required String filePath,
    required void Function(Map<String, Object?>) onRestorePreferences,
    bool skipFileExistenceCheck = false,
  }) async {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.db')) {
      return await _importSqlite(
        filePath: filePath,
        onRestorePreferences: onRestorePreferences,
        skipFileExistenceCheck: skipFileExistenceCheck,
      );
    } else {
      return await _importJson(
        filePath: filePath,
        onRestorePreferences: onRestorePreferences,
        skipFileExistenceCheck: skipFileExistenceCheck,
      );
    }
  }

  /// Import from a SQLite .db backup file.
  Future<Map<String, dynamic>?> _importSqlite({
    required String filePath,
    required void Function(Map<String, Object?>) onRestorePreferences,
    bool skipFileExistenceCheck = false,
  }) async {
    try {
      if (!_isInitialized) await initialize();

      final dbFactory = _provider is SqliteDatabaseProvider
          ? (_provider as SqliteDatabaseProvider).getDatabaseFactory()
          : null;

      if (dbFactory == null) return null;

      final importedDb = await dbFactory.openDatabase(
        filePath,
        options: OpenDatabaseOptions(readOnly: true),
      );

      int importedTagCount = 0;
      int skippedFileCount = 0;
      int failedCount = 0;
      int prefsCount = 0;

      // Restore preferences
      try {
        final prefRows = await importedDb.query('preferences');
        final prefsMap = <String, Object?>{};
        for (final row in prefRows) {
          final key = row['key'] as String;
          final typeStr = row['type'] as String?;
          final value = row['value'] as String?;

          Object? decoded;
          switch (typeStr) {
            case 'String':
              decoded = value;
              break;
            case 'int':
              decoded = value != null ? int.tryParse(value) : null;
              break;
            case 'double':
              decoded = value != null ? double.tryParse(value) : null;
              break;
            case 'bool':
              decoded = value == 'true';
              break;
            case 'List':
              decoded = value != null ? value.split('\x00') : <String>[];
              break;
            default:
              decoded = value;
          }
          prefsMap[key] = decoded;
        }
        if (prefsMap.isNotEmpty) {
          onRestorePreferences(prefsMap);
          prefsCount = prefsMap.length;
        }
      } catch (_) {}

      // Restore tags from file_tags table
      try {
        final tagRows = await importedDb.query('file_tags');
        final counts = await _importTagRows([
          for (final row in tagRows)
            if (row['file_path'] is String && row['tag'] is String)
              (row['file_path'] as String, row['tag'] as String),
        ], skipFileExistenceCheck: skipFileExistenceCheck);
        importedTagCount = counts.imported;
        skippedFileCount = counts.skipped;
        failedCount = counts.failed;
      } catch (_) {}

      await importedDb.close();

      return {
        'importedTagCount': importedTagCount,
        'skippedFileCount': skippedFileCount,
        'failedCount': failedCount,
        'preferencesCount': prefsCount,
        'format': 'sqlite',
      };
    } catch (_) {
      return null;
    }
  }

  /// Import from a JSON backup file.
  Future<Map<String, dynamic>?> _importJson({
    required String filePath,
    required void Function(Map<String, Object?>) onRestorePreferences,
    bool skipFileExistenceCheck = false,
  }) async {
    try {
      if (!_isInitialized) await initialize();

      final exportFile = File(filePath);
      if (!await exportFile.exists()) return null;

      final data = await _readTagBackupJson(filePath);
      var counts = (imported: 0, skipped: 0, failed: 0);
      if (data['database'] case final Map<String, dynamic> section) {
        if (section['tags'] case final Map<String, dynamic> tags) {
          counts = await _importTagRows(
            _tagRows(tags),
            skipFileExistenceCheck: skipFileExistenceCheck,
          );
        }
      }

      // Restore preferences
      Map<String, Object?> restoredPrefs = {};
      if (data.containsKey('preferences')) {
        final Map<String, dynamic> prefsSection = data['preferences'];
        restoredPrefs = Map<String, Object?>.from(prefsSection);
        onRestorePreferences(restoredPrefs);
      }

      return {
        'importedTagCount': counts.imported,
        'skippedFileCount': counts.skipped,
        'failedCount': counts.failed,
        'preferencesCount': restoredPrefs.length,
        'format': 'json',
      };
    } catch (e, stackTrace) {
      debugPrint('_importJson error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
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

Future<Map<String, dynamic>> _readTagBackupJson(String path) => Isolate.run(
  () => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
);
