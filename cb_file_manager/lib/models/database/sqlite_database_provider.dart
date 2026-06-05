import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

import 'database_provider.dart';

/// Shared SQLite provider for the application data store.
class SqliteDatabaseProvider implements IDatabaseProvider {
  static const String _databaseFileName = 'cb_file_hub.sqlite';
  static Database? _sharedDatabase;
  static Future<Database>? _openingDatabase;

  /// Returns the path to the SQLite database file (sync, usable after first open).
  static String getDatabasePathSync() {
    // This is only valid after the database has been opened at least once.
    // For backup purposes, call this after DatabaseManager is initialized.
    final db = _sharedDatabase;
    if (db != null) {
      return db.path;
    }
    // Fallback: reconstruct path (only works if app documents dir is stable)
    // This won't work on web. Returns empty string on web.
    return '';
  }

  Database? _database;
  bool _isCloudSyncEnabled = false;
  bool _isInitialized = false;
  String? _lastErrorMessage;

  @override
  String? getLastErrorMessage() => _lastErrorMessage;

  @override
  Future<void> initialize() async {
    if (_isInitialized && _database != null) {
      return;
    }

    _database = await getDatabase();
    _isInitialized = true;
  }

  Future<Database> getDatabase() async {
    if (_database != null) {
      return _database!;
    }

    if (_sharedDatabase != null) {
      _database = _sharedDatabase;
      return _database!;
    }

    if (_openingDatabase != null) {
      final database = await _openingDatabase!;
      _database = database;
      return database;
    }

    _openingDatabase = _openSharedDatabase();

    try {
      final database = await _openingDatabase!;
      _sharedDatabase = database;
      _database = database;
      return database;
    } catch (error) {
      _sharedDatabase = null;
      _database = null;
      rethrow;
    } finally {
      _openingDatabase = null;
    }
  }

  Future<Database> _openSharedDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final databaseDirectory =
        Directory(path.join(documentsDirectory.path, 'CBFileHub_v2'));

    if (!await databaseDirectory.exists()) {
      await databaseDirectory.create(recursive: true);
    }

    final databasePath = path.join(databaseDirectory.path, _databaseFileName);
    final databaseFactory = _resolveDatabaseFactory();
    AppLogger.info(
      '[SQLite] Opening database',
      error:
          'path=$databasePath platform=${Platform.operatingSystem} factory=${databaseFactory.runtimeType}',
    );

    return databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) async {
          await _configureDatabase(db);
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _onUpgrade(db, oldVersion, newVersion);
        },
      ),
    );
  }

  DatabaseFactory _resolveDatabaseFactory() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }

    return sqflite.databaseFactory;
  }

  /// Returns the DatabaseFactory used by this provider.
  /// Exposed for backup/restore operations.
  DatabaseFactory getDatabaseFactory() => _resolveDatabaseFactory();

  Future<void> _configureDatabase(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');

    try {
      await db.rawQuery('PRAGMA journal_mode = WAL');
      await db.rawQuery('PRAGMA synchronous = NORMAL');
      AppLogger.info('[SQLite] Database pragmas configured');
    } catch (error, stackTrace) {
      AppLogger.warning(
        '[SQLite] Failed to apply optional pragmas',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS file_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        tag TEXT NOT NULL,
        normalized_tag TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(file_path, normalized_tag) ON CONFLICT REPLACE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_file_tags_file_path ON file_tags(file_path)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_file_tags_normalized_tag ON file_tags(normalized_tag)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS standalone_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tag TEXT NOT NULL,
        normalized_tag TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_standalone_tags_normalized_tag ON standalone_tags(normalized_tag)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS preferences (
        key TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        string_value TEXT,
        int_value INTEGER,
        double_value REAL,
        bool_value INTEGER,
        timestamp INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS folder_display_preferences (
        path TEXT PRIMARY KEY,
        view_mode INTEGER,
        sort_option INTEGER,
        grid_zoom_level INTEGER,
        column_visibility_json TEXT,
        show_file_tags INTEGER,
        preview_pane_visible INTEGER,
        preview_pane_width REAL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS folder_thumbnails (
        path TEXT PRIMARY KEY,
        custom_thumbnail TEXT,
        auto_thumbnail TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS albums (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        cover_image_path TEXT,
        created_at INTEGER NOT NULL,
        modified_at INTEGER NOT NULL,
        color_theme TEXT,
        is_system_album INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS album_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        album_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL,
        caption TEXT,
        is_cover INTEGER NOT NULL DEFAULT 0,
        UNIQUE(album_id, file_path) ON CONFLICT IGNORE,
        FOREIGN KEY(album_id) REFERENCES albums(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_album_files_album_id ON album_files(album_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS album_configs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        album_id INTEGER NOT NULL UNIQUE,
        include_subdirectories INTEGER NOT NULL DEFAULT 1,
        file_extensions TEXT NOT NULL,
        auto_refresh INTEGER NOT NULL DEFAULT 1,
        max_file_count INTEGER NOT NULL DEFAULT 10000,
        sort_by TEXT NOT NULL,
        sort_ascending INTEGER NOT NULL DEFAULT 0,
        exclude_patterns TEXT NOT NULL,
        enable_auto_rules INTEGER NOT NULL DEFAULT 1,
        directories TEXT NOT NULL,
        last_scan_time INTEGER,
        file_count INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(album_id) REFERENCES albums(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_libraries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        cover_image_path TEXT,
        created_at INTEGER NOT NULL,
        modified_at INTEGER NOT NULL,
        color_theme TEXT,
        is_system_library INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_library_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        video_library_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        caption TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        UNIQUE(video_library_id, file_path) ON CONFLICT IGNORE,
        FOREIGN KEY(video_library_id) REFERENCES video_libraries(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_library_configs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        video_library_id INTEGER NOT NULL UNIQUE,
        include_subdirectories INTEGER NOT NULL DEFAULT 1,
        file_extensions TEXT NOT NULL,
        auto_refresh INTEGER NOT NULL DEFAULT 1,
        max_file_count INTEGER NOT NULL DEFAULT 10000,
        sort_by TEXT NOT NULL,
        sort_ascending INTEGER NOT NULL DEFAULT 0,
        exclude_patterns TEXT NOT NULL,
        enable_auto_rules INTEGER NOT NULL DEFAULT 1,
        directories TEXT NOT NULL,
        last_scan_time INTEGER,
        file_count INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(video_library_id) REFERENCES video_libraries(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS network_credentials (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_type TEXT NOT NULL,
        host TEXT NOT NULL,
        normalized_host TEXT NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        port INTEGER,
        domain TEXT,
        additional_options TEXT,
        last_connected INTEGER NOT NULL,
        UNIQUE(service_type, normalized_host, username) ON CONFLICT REPLACE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_network_credentials_lookup
      ON network_credentials(service_type, normalized_host)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_providers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        api_type TEXT NOT NULL,
        api_key TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        model_name TEXT NOT NULL,
        temperature REAL DEFAULT 0.3,
        max_tokens INTEGER DEFAULT 4096,
        system_prompt TEXT,
        timeout_seconds INTEGER DEFAULT 30,
        max_retries INTEGER DEFAULT 2,
        is_enabled INTEGER DEFAULT 1,
        priority INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Tag metadata (thumbnails) — added in schema v2
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tag_metadata (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        normalized_tag TEXT NOT NULL UNIQUE,
        thumbnail_path TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tag_metadata_normalized_tag ON tag_metadata(normalized_tag)',
    );

    // Tag hierarchy (parent-child relationships) — added in schema v2
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tag_hierarchy (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_normalized_tag TEXT NOT NULL,
        child_normalized_tag TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(parent_normalized_tag, child_normalized_tag)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tag_hierarchy_parent ON tag_hierarchy(parent_normalized_tag)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tag_hierarchy_child ON tag_hierarchy(child_normalized_tag)',
    );
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  String _normalizeTag(String tag) => tag.trim().toLowerCase();

  /// Runs incremental migrations when an existing database is opened with a
  /// higher [version] than it was originally created with.
  Future<void> _onUpgrade(
      DatabaseExecutor db, int oldVersion, int newVersion) async {
    AppLogger.info('[SQLite] Upgrading database',
        error: 'oldVersion=$oldVersion newVersion=$newVersion');

    if (oldVersion < 2) {
      // v2: tag_metadata (thumbnails) and tag_hierarchy (parent-child)
      // Drop first in case partially-created tables exist from development.
      await db.execute('DROP TABLE IF EXISTS tag_metadata');
      await db.execute('DROP TABLE IF EXISTS tag_hierarchy');

      await db.execute('''
        CREATE TABLE tag_metadata (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          normalized_tag TEXT NOT NULL UNIQUE,
          thumbnail_path TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tag_metadata_normalized_tag ON tag_metadata(normalized_tag)',
      );

      await db.execute('''
        CREATE TABLE tag_hierarchy (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          parent_normalized_tag TEXT NOT NULL,
          child_normalized_tag TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          UNIQUE(parent_normalized_tag, child_normalized_tag)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tag_hierarchy_parent ON tag_hierarchy(parent_normalized_tag)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tag_hierarchy_child ON tag_hierarchy(child_normalized_tag)',
      );
    }

    if (oldVersion == 2) {
      // v3: Fix broken v2 migration — recreate tag_metadata and tag_hierarchy
      // with correct schema. These tables are new in v2 and may have been
      // created without the correct columns.
      await db.execute('DROP TABLE IF EXISTS tag_metadata');
      await db.execute('DROP TABLE IF EXISTS tag_hierarchy');

      await db.execute('''
        CREATE TABLE tag_metadata (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          normalized_tag TEXT NOT NULL UNIQUE,
          thumbnail_path TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tag_metadata_normalized_tag ON tag_metadata(normalized_tag)',
      );

      await db.execute('''
        CREATE TABLE tag_hierarchy (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          parent_normalized_tag TEXT NOT NULL,
          child_normalized_tag TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          UNIQUE(parent_normalized_tag, child_normalized_tag)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tag_hierarchy_parent ON tag_hierarchy(parent_normalized_tag)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tag_hierarchy_child ON tag_hierarchy(child_normalized_tag)',
      );
    }

    AppLogger.info('[SQLite] Database upgrade complete',
        error: 'newVersion=$newVersion');
  }

  Future<Map<String, Object?>?> _getPreferenceRow(String key) async {
    final database = await getDatabase();
    final rows = await database.query(
      'preferences',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<bool> _savePreference(
    String key, {
    required String type,
    String? stringValue,
    int? intValue,
    double? doubleValue,
    bool? boolValue,
  }) async {
    try {
      final database = await getDatabase();
      await database.insert(
        'preferences',
        <String, Object?>{
          'key': key,
          'type': type,
          'string_value': stringValue,
          'int_value': intValue,
          'double_value': doubleValue,
          'bool_value': boolValue == null ? null : (boolValue ? 1 : 0),
          'timestamp': _now(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (error) {
      debugPrint('Error saving preference "$key": $error');
      return false;
    }
  }

  @override
  bool isInitialized() {
    return _isInitialized;
  }

  @override
  Future<void> close() async {
    _database = null;
    _isInitialized = false;
  }

  static Future<void> closeSharedDatabase() async {
    if (_sharedDatabase != null) {
      await _sharedDatabase!.close();
      _sharedDatabase = null;
    }
  }

  @override
  Future<bool> addTagToFile(String filePath, String tag) async {
    final trimmedTag = tag.trim();
    if (trimmedTag.isEmpty) {
      return true;
    }

    try {
      final database = await getDatabase();
      await database.insert(
        'file_tags',
        <String, Object?>{
          'file_path': filePath,
          'tag': trimmedTag,
          'normalized_tag': _normalizeTag(trimmedTag),
          'created_at': _now(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (error) {
      debugPrint('Error adding tag to file: $error');
      return false;
    }
  }

  @override
  Future<bool> removeTagFromFile(String filePath, String tag) async {
    try {
      final database = await getDatabase();
      await database.delete(
        'file_tags',
        where: 'file_path = ? AND normalized_tag = ?',
        whereArgs: [filePath, _normalizeTag(tag)],
      );
      return true;
    } catch (error) {
      debugPrint('Error removing tag from file: $error');
      return false;
    }
  }

  @override
  Future<List<String>> getTagsForFile(String filePath) async {
    try {
      final database = await getDatabase();
      final rows = await database.query(
        'file_tags',
        columns: <String>['tag'],
        where: 'file_path = ?',
        whereArgs: [filePath],
        orderBy: 'created_at ASC, id ASC',
      );
      return rows
          .map((row) => row['tag'])
          .whereType<String>()
          .toList(growable: false);
    } catch (error) {
      debugPrint('Error getting tags for file: $error');
      return <String>[];
    }
  }

  @override
  Future<bool> setTagsForFile(String filePath, List<String> tags) async {
    final uniqueTags = <String, String>{};
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      uniqueTags[_normalizeTag(trimmed)] = trimmed;
    }
    debugPrint(
        '[SQLite] setTagsForFile START filePath=$filePath incomingTags=$tags uniqueTags=${uniqueTags.values.toList()}');
    AppLogger.info('[SQLite] setTagsForFile START',
        error:
            'filePath=$filePath incomingTags=$tags uniqueTags=${uniqueTags.values.toList()}');

    try {
      final database = await getDatabase();
      await database.transaction((txn) async {
        AppLogger.debug('[SQLite] setTagsForFile deleting existing tags',
            error: 'filePath=$filePath');
        debugPrint(
            '[SQLite] setTagsForFile deleting existing tags filePath=$filePath');
        await txn.delete(
          'file_tags',
          where: 'file_path = ?',
          whereArgs: [filePath],
        );

        for (final entry in uniqueTags.entries) {
          AppLogger.debug('[SQLite] setTagsForFile inserting tag',
              error:
                  'filePath=$filePath tag=${entry.value} normalized=${entry.key}');
          debugPrint(
              '[SQLite] setTagsForFile inserting filePath=$filePath tag=${entry.value} normalized=${entry.key}');
          await txn.insert(
            'file_tags',
            <String, Object?>{
              'file_path': filePath,
              'tag': entry.value,
              'normalized_tag': entry.key,
              'created_at': _now(),
            },
          );
        }
      });
      AppLogger.info('[SQLite] setTagsForFile DONE',
          error: 'filePath=$filePath');
      debugPrint('[SQLite] setTagsForFile DONE filePath=$filePath');
      return true;
    } catch (error) {
      AppLogger.error('[SQLite] setTagsForFile ERROR',
          error: 'filePath=$filePath error=$error');
      debugPrint(
          '[SQLite] setTagsForFile ERROR filePath=$filePath error=$error');
      return false;
    }
  }

  @override
  Future<List<String>> findFilesByTag(String tag) async {
    final normalizedTag = _normalizeTag(tag);
    if (normalizedTag.isEmpty) {
      return <String>[];
    }

    try {
      final database = await getDatabase();
      final rows = await database.rawQuery(
        '''
        SELECT DISTINCT file_path
        FROM file_tags
        WHERE normalized_tag LIKE ?
        ORDER BY file_path COLLATE NOCASE ASC
        ''',
        <Object?>['%$normalizedTag%'],
      );

      return rows
          .map((row) => row['file_path'])
          .whereType<String>()
          .toList(growable: false);
    } catch (error) {
      debugPrint('Error finding files by tag: $error');
      return <String>[];
    }
  }

  @override
  Future<Set<String>> getAllUniqueTags() async {
    try {
      final database = await getDatabase();
      final rows = await database.rawQuery(
        '''
        SELECT tag
        FROM file_tags
        GROUP BY normalized_tag
        ORDER BY tag COLLATE NOCASE ASC
        ''',
      );
      return rows.map((row) => row['tag']).whereType<String>().toSet();
    } catch (error) {
      debugPrint('Error getting all unique tags: $error');
      return <String>{};
    }
  }

  @override
  Future<Set<String>> getStandaloneTags() async {
    try {
      final database = await getDatabase();
      await _createSchema(database);
      AppLogger.debug('[SQLite] Reading standalone tags');
      final rows = await database.query(
        'standalone_tags',
        columns: <String>['tag'],
        orderBy: 'tag COLLATE NOCASE ASC',
      );
      AppLogger.debug('[SQLite] Loaded standalone tags count=${rows.length}');
      return rows.map((row) => row['tag']).whereType<String>().toSet();
    } catch (error) {
      _lastErrorMessage = error.toString();
      AppLogger.error('[SQLite] Failed to read standalone tags', error: error);
      debugPrint('Error getting standalone tags: $error');
      return <String>{};
    }
  }

  @override
  Future<bool> replaceStandaloneTags(List<String> tags) async {
    final uniqueTags = <String, String>{};
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      uniqueTags[_normalizeTag(trimmed)] = trimmed;
    }

    try {
      final database = await getDatabase();
      await _createSchema(database);
      AppLogger.info(
        '[SQLite] Replacing standalone tags',
        error:
            'incoming=${tags.length} unique=${uniqueTags.length} sample=${uniqueTags.values.take(3).join(", ")}',
      );
      await database.transaction((txn) async {
        await txn.delete('standalone_tags');

        for (final entry in uniqueTags.entries) {
          await txn.insert(
            'standalone_tags',
            <String, Object?>{
              'tag': entry.value,
              'normalized_tag': entry.key,
              'created_at': _now(),
            },
          );
        }
      });
      final verifyRows = await database.rawQuery(
        'SELECT COUNT(*) AS count FROM standalone_tags',
      );
      final savedCount = (verifyRows.first['count'] as int?) ?? 0;
      AppLogger.info('[SQLite] Replaced standalone tags successfully',
          error: 'savedCount=$savedCount');
      _lastErrorMessage = null;
      return true;
    } catch (error) {
      _lastErrorMessage = error.toString();
      AppLogger.error('[SQLite] Failed to replace standalone tags',
          error: error);
      debugPrint('Error replacing standalone tags: $error');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Tag Metadata (Thumbnails)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> setTagThumbnail(
      String normalizedTag, String thumbnailPath) async {
    try {
      final database = await getDatabase();
      await database.insert(
        'tag_metadata',
        <String, Object?>{
          'normalized_tag': normalizedTag,
          'thumbnail_path': thumbnailPath,
          'created_at': _now(),
          'updated_at': _now(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (error) {
      debugPrint('Error setting tag thumbnail: $error');
      return false;
    }
  }

  @override
  Future<String?> getTagThumbnail(String normalizedTag) async {
    try {
      final database = await getDatabase();
      final rows = await database.query(
        'tag_metadata',
        columns: <String>['thumbnail_path'],
        where: 'normalized_tag = ?',
        whereArgs: [normalizedTag],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['thumbnail_path'] as String?;
    } catch (error) {
      debugPrint('Error getting tag thumbnail: $error');
      return null;
    }
  }

  @override
  Future<bool> deleteTagThumbnail(String normalizedTag) async {
    try {
      final database = await getDatabase();
      await database.delete(
        'tag_metadata',
        where: 'normalized_tag = ?',
        whereArgs: [normalizedTag],
      );
      return true;
    } catch (error) {
      debugPrint('Error deleting tag thumbnail: $error');
      return false;
    }
  }

  @override
  Future<Map<String, String>> getAllTagThumbnails() async {
    try {
      final database = await getDatabase();
      final rows = await database.query(
        'tag_metadata',
        columns: <String>['normalized_tag', 'thumbnail_path'],
      );
      final result = <String, String>{};
      for (final row in rows) {
        final tag = row['normalized_tag'] as String?;
        final path = row['thumbnail_path'] as String?;
        if (tag != null && path != null) {
          result[tag] = path;
        }
      }
      return result;
    } catch (error) {
      debugPrint('Error getting all tag thumbnails: $error');
      return <String, String>{};
    }
  }

  // ---------------------------------------------------------------------------
  // Tag Hierarchy (Parent-Child relationships)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> setTagHierarchy(
      String parentNormalizedTag, String childNormalizedTag) async {
    try {
      final database = await getDatabase();
      await database.insert(
        'tag_hierarchy',
        <String, Object?>{
          'parent_normalized_tag': parentNormalizedTag,
          'child_normalized_tag': childNormalizedTag,
          'created_at': _now(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return true;
    } catch (error) {
      debugPrint('Error setting tag hierarchy: $error');
      return false;
    }
  }

  @override
  Future<bool> removeTagHierarchy(
      String parentNormalizedTag, String childNormalizedTag) async {
    try {
      final database = await getDatabase();
      await database.delete(
        'tag_hierarchy',
        where: 'parent_normalized_tag = ? AND child_normalized_tag = ?',
        whereArgs: [parentNormalizedTag, childNormalizedTag],
      );
      return true;
    } catch (error) {
      debugPrint('Error removing tag hierarchy: $error');
      return false;
    }
  }

  @override
  Future<List<String>> getChildTags(String parentNormalizedTag) async {
    try {
      final database = await getDatabase();
      final rows = await database.query(
        'tag_hierarchy',
        columns: <String>['child_normalized_tag'],
        where: 'parent_normalized_tag = ?',
        whereArgs: [parentNormalizedTag],
      );
      return rows
          .map((row) => row['child_normalized_tag'])
          .whereType<String>()
          .toList(growable: false);
    } catch (error) {
      debugPrint('Error getting child tags: $error');
      return <String>[];
    }
  }

  @override
  Future<List<String>> getParentTags(String childNormalizedTag) async {
    try {
      final database = await getDatabase();
      final rows = await database.query(
        'tag_hierarchy',
        columns: <String>['parent_normalized_tag'],
        where: 'child_normalized_tag = ?',
        whereArgs: [childNormalizedTag],
      );
      return rows
          .map((row) => row['parent_normalized_tag'])
          .whereType<String>()
          .toList(growable: false);
    } catch (error) {
      debugPrint('Error getting parent tags: $error');
      return <String>[];
    }
  }

  @override
  Future<Map<String, List<String>>> getAllTagHierarchy() async {
    try {
      final database = await getDatabase();
      final rows = await database.query(
        'tag_hierarchy',
        columns: <String>['parent_normalized_tag', 'child_normalized_tag'],
        orderBy: 'parent_normalized_tag ASC',
      );
      final result = <String, List<String>>{};
      for (final row in rows) {
        final parent = row['parent_normalized_tag'] as String?;
        final child = row['child_normalized_tag'] as String?;
        if (parent != null && child != null) {
          result.putIfAbsent(parent, () => <String>[]).add(child);
        }
      }
      return result;
    } catch (error) {
      debugPrint('Error getting all tag hierarchy: $error');
      return <String, List<String>>{};
    }
  }

  @override
  Future<bool> removeAllHierarchyForTag(String normalizedTag) async {
    try {
      final database = await getDatabase();
      await database.transaction((txn) async {
        await txn.delete(
          'tag_hierarchy',
          where: 'parent_normalized_tag = ? OR child_normalized_tag = ?',
          whereArgs: [normalizedTag, normalizedTag],
        );
      });
      return true;
    } catch (error) {
      debugPrint('Error removing all hierarchy for tag: $error');
      return false;
    }
  }

  @override
  Future<String?> getStringPreference(
    String key, {
    String? defaultValue,
  }) async {
    final row = await _getPreferenceRow(key);
    if (row == null || row['type'] != 'string') {
      return defaultValue;
    }
    return row['string_value'] as String? ?? defaultValue;
  }

  @override
  Future<bool> saveStringPreference(String key, String value) {
    return _savePreference(
      key,
      type: 'string',
      stringValue: value,
    );
  }

  @override
  Future<int?> getIntPreference(String key, {int? defaultValue}) async {
    final row = await _getPreferenceRow(key);
    if (row == null || row['type'] != 'integer') {
      return defaultValue;
    }
    return row['int_value'] as int? ?? defaultValue;
  }

  @override
  Future<bool> saveIntPreference(String key, int value) {
    return _savePreference(
      key,
      type: 'integer',
      intValue: value,
    );
  }

  @override
  Future<double?> getDoublePreference(
    String key, {
    double? defaultValue,
  }) async {
    final row = await _getPreferenceRow(key);
    if (row == null || row['type'] != 'double') {
      return defaultValue;
    }

    final value = row['double_value'];
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return defaultValue;
  }

  @override
  Future<bool> saveDoublePreference(String key, double value) {
    return _savePreference(
      key,
      type: 'double',
      doubleValue: value,
    );
  }

  @override
  Future<bool?> getBoolPreference(String key, {bool? defaultValue}) async {
    final row = await _getPreferenceRow(key);
    if (row == null || row['type'] != 'boolean') {
      return defaultValue;
    }

    final value = row['bool_value'];
    if (value is int) {
      return value == 1;
    }
    return defaultValue;
  }

  @override
  Future<bool> saveBoolPreference(String key, bool value) {
    return _savePreference(
      key,
      type: 'boolean',
      boolValue: value,
    );
  }

  @override
  Future<bool> deletePreference(String key) async {
    try {
      final database = await getDatabase();
      await database.delete(
        'preferences',
        where: 'key = ?',
        whereArgs: [key],
      );
      return true;
    } catch (error) {
      debugPrint('Error deleting preference "$key": $error');
      return false;
    }
  }

  @override
  void setCloudSyncEnabled(bool enabled) {
    _isCloudSyncEnabled = enabled;
  }

  @override
  bool isCloudSyncEnabled() {
    return _isCloudSyncEnabled;
  }

  @override
  Future<bool> syncToCloud() async {
    if (!_isCloudSyncEnabled) {
      return false;
    }

    await Future<void>.delayed(const Duration(seconds: 1));
    return true;
  }

  @override
  Future<bool> syncFromCloud() async {
    if (!_isCloudSyncEnabled) {
      return false;
    }

    await Future<void>.delayed(const Duration(seconds: 1));
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllPreferencesRaw() async {
    try {
      final database = await getDatabase();
      final rows = await database.query(
        'preferences',
        orderBy: 'key COLLATE NOCASE ASC',
      );
      return rows
          .map((row) => <String, dynamic>{
                'key': row['key'],
                'type': row['type'],
                'stringValue': row['string_value'],
                'intValue': row['int_value'],
                'doubleValue': row['double_value'],
                'boolValue': row['bool_value'],
                'timestamp': row['timestamp'],
              })
          .toList(growable: false);
    } catch (error) {
      debugPrint('Error loading raw preferences: $error');
      return <Map<String, dynamic>>[];
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getPreferencesRawPage({
    required int offset,
    required int limit,
  }) async {
    try {
      final database = await getDatabase();
      final rows = await database.query(
        'preferences',
        orderBy: 'key COLLATE NOCASE ASC',
        offset: offset,
        limit: limit,
      );
      return rows
          .map((row) => <String, dynamic>{
                'key': row['key'],
                'type': row['type'],
                'stringValue': row['string_value'],
                'intValue': row['int_value'],
                'doubleValue': row['double_value'],
                'boolValue': row['bool_value'],
                'timestamp': row['timestamp'],
              })
          .toList(growable: false);
    } catch (error) {
      debugPrint('Error loading raw preferences page: $error');
      return <Map<String, dynamic>>[];
    }
  }

  @override
  Future<int> getPreferencesRawCount() async {
    try {
      final database = await getDatabase();
      final result =
          await database.rawQuery('SELECT COUNT(*) AS count FROM preferences');
      return (result.first['count'] as int?) ?? 0;
    } catch (error) {
      debugPrint('Error counting raw preferences: $error');
      return 0;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAllFileTagsRaw() async {
    try {
      final database = await getDatabase();
      final rows = await database.query(
        'file_tags',
        orderBy: 'file_path COLLATE NOCASE ASC, tag COLLATE NOCASE ASC',
      );
      return rows
          .map((row) => <String, dynamic>{
                'id': row['id'],
                'filePath': row['file_path'],
                'tag': row['tag'],
                'normalizedTag': row['normalized_tag'],
                'createdAt': row['created_at'],
              })
          .toList(growable: false);
    } catch (error) {
      debugPrint('Error loading raw file tags: $error');
      return <Map<String, dynamic>>[];
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getFileTagsRawPage({
    required int offset,
    required int limit,
  }) async {
    try {
      final database = await getDatabase();
      final rows = await database.query(
        'file_tags',
        orderBy: 'file_path COLLATE NOCASE ASC, tag COLLATE NOCASE ASC',
        offset: offset,
        limit: limit,
      );
      return rows
          .map((row) => <String, dynamic>{
                'id': row['id'],
                'filePath': row['file_path'],
                'tag': row['tag'],
                'normalizedTag': row['normalized_tag'],
                'createdAt': row['created_at'],
              })
          .toList(growable: false);
    } catch (error) {
      debugPrint('Error loading raw file tags page: $error');
      return <Map<String, dynamic>>[];
    }
  }

  @override
  Future<int> getFileTagsRawCount() async {
    try {
      final database = await getDatabase();
      final result =
          await database.rawQuery('SELECT COUNT(*) AS count FROM file_tags');
      return (result.first['count'] as int?) ?? 0;
    } catch (error) {
      debugPrint('Error counting raw file tags: $error');
      return 0;
    }
  }

  @override
  Future<int> countUniqueTaggedFiles() async {
    try {
      final database = await getDatabase();
      // Single query — COUNT DISTINCT is O(n) with an index scan, not O(n²)
      final result = await database.rawQuery(
        'SELECT COUNT(DISTINCT file_path) AS count FROM file_tags',
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (error) {
      debugPrint('Error counting unique tagged files: $error');
      return 0;
    }
  }
}
