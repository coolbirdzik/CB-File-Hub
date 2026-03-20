import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';

/// Interface for database providers
abstract class IDatabaseProvider {
  /// Initialize the database
  Future<void> initialize();

  /// Check if database is initialized
  bool isInitialized();

  /// Get the last database error message, if any
  String? getLastErrorMessage();

  /// Close the database
  Future<void> close();

  /// Add a tag to a file
  Future<bool> addTagToFile(String filePath, String tag);

  /// Remove a tag from a file
  Future<bool> removeTagFromFile(String filePath, String tag);

  /// Get all tags for a file
  Future<List<String>> getTagsForFile(String filePath);

  /// Set tags for a file (replacing any existing tags)
  Future<bool> setTagsForFile(String filePath, List<String> tags);

  /// Find all files with a specific tag
  Future<List<String>> findFilesByTag(String tag);

  /// Get all unique tags in the database
  Future<Set<String>> getAllUniqueTags();

  /// Get all standalone tags stored in the database
  Future<Set<String>> getStandaloneTags();

  /// Replace all standalone tags stored in the database
  Future<bool> replaceStandaloneTags(List<String> tags);

  /// Get a string preference
  Future<String?> getStringPreference(String key, {String? defaultValue});

  /// Save a string preference
  Future<bool> saveStringPreference(String key, String value);

  /// Get an integer preference
  Future<int?> getIntPreference(String key, {int? defaultValue});

  /// Save an integer preference
  Future<bool> saveIntPreference(String key, int value);

  /// Get a double preference
  Future<double?> getDoublePreference(String key, {double? defaultValue});

  /// Save a double preference
  Future<bool> saveDoublePreference(String key, double value);

  /// Get a boolean preference
  Future<bool?> getBoolPreference(String key, {bool? defaultValue});

  /// Save a boolean preference
  Future<bool> saveBoolPreference(String key, bool value);

  /// Delete a preference
  Future<bool> deletePreference(String key);

  /// Set if cloud sync is enabled
  void setCloudSyncEnabled(bool enabled);

  /// Check if cloud sync is enabled
  bool isCloudSyncEnabled();

  /// Sync data to the cloud
  Future<bool> syncToCloud();

  /// Sync data from the cloud
  Future<bool> syncFromCloud();

  /// Get all user preferences as raw data
  Future<List<Map<String, dynamic>>> getAllPreferencesRaw();

  /// Get a page of raw user preferences
  Future<List<Map<String, dynamic>>> getPreferencesRawPage({
    required int offset,
    required int limit,
  });

  /// Get the total number of raw user preferences rows
  Future<int> getPreferencesRawCount();

  /// Get all file tags as raw data
  Future<List<Map<String, dynamic>>> getAllFileTagsRaw();

  /// Get a page of raw file tags
  Future<List<Map<String, dynamic>>> getFileTagsRawPage({
    required int offset,
    required int limit,
  });

  /// Get the total number of raw file tag rows
  Future<int> getFileTagsRawCount();

  /// Count unique files that have at least one tag.
  /// Uses a single SQL query (COUNT DISTINCT) instead of loading all file paths.
  Future<int> countUniqueTaggedFiles();
}

/// Factory for creating database providers
class DatabaseProviderFactory {
  /// Create a database provider instance based on type
  static IDatabaseProvider create(DatabaseType type) {
    switch (type) {
      case DatabaseType.sqlite:
        return SqliteDatabaseProvider();
    }
  }
}

/// Enum for database types
enum DatabaseType {
  sqlite,
}
