import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;
import 'package:sqflite_common/sqlite_api.dart';

/// Stores display preferences per folder in the application's SQLite database.
class FolderSortManager {
  static const String _tableName = 'folder_display_preferences';
  static const String _legacyConfigFileName = '.cbfile_config.json';
  static const String _drivesPreferencePath = '#drives';

  static const String _viewModeKey = 'viewMode';
  static const String _sortOptionKey = 'sortOption';
  static const String _gridZoomLevelKey = 'gridZoomLevel';
  static const String _columnVisibilityKey = 'columnVisibility';
  static const String _showFileTagsKey = 'showFileTags';
  static const String _previewPaneVisibleKey = 'previewPaneVisible';
  static const String _previewPaneWidthKey = 'previewPaneWidth';

  static final FolderSortManager _instance = FolderSortManager._internal();

  factory FolderSortManager() => _instance;

  FolderSortManager._internal();

  final Map<String, Map<String, dynamic>> _folderConfigCache = {};
  Future<void>? _tableInitialization;

  Future<SortOption?> getFolderSortOption(String folderPath) async {
    try {
      return await _getConfigEnumValue<SortOption>(
        folderPath: folderPath,
        key: _sortOptionKey,
        values: SortOption.values,
      );
    } catch (e) {
      debugPrint('Unexpected error in getFolderSortOption: $e');
      return null;
    }
  }

  Future<bool> saveFolderSortOption(
    String folderPath,
    SortOption sortOption,
  ) async {
    try {
      return await _saveConfigValue(
        folderPath: folderPath,
        key: _sortOptionKey,
        value: sortOption.index,
      );
    } catch (e) {
      debugPrint('Unexpected error in saveFolderSortOption: $e');
      _cacheValue(folderPath, _sortOptionKey, sortOption.index);
      return false;
    }
  }

  Future<ViewMode?> getFolderViewMode(String folderPath) async {
    try {
      return await _getConfigEnumValue<ViewMode>(
        folderPath: folderPath,
        key: _viewModeKey,
        values: ViewMode.values,
      );
    } catch (e) {
      debugPrint('Unexpected error in getFolderViewMode: $e');
      return null;
    }
  }

  Future<bool> saveFolderViewMode(String folderPath, ViewMode viewMode) async {
    try {
      return await _saveConfigValue(
        folderPath: folderPath,
        key: _viewModeKey,
        value: viewMode.index,
      );
    } catch (e) {
      debugPrint('Unexpected error in saveFolderViewMode: $e');
      _cacheValue(folderPath, _viewModeKey, viewMode.index);
      return false;
    }
  }

  Future<bool> clearFolderSortOption(String folderPath) async {
    try {
      final config = await _readConfig(folderPath);
      final database = await _getDatabase();
      await database.rawUpdate(
        '''
        UPDATE $_tableName
        SET sort_option = NULL, updated_at = ?
        WHERE path = ?
        ''',
        <Object?>[_now(), _normalizePath(folderPath)],
      );
      config.remove(_sortOptionKey);
      _folderConfigCache[_normalizePath(folderPath)] = config;
      return true;
    } catch (e) {
      debugPrint('Error clearing folder sort option: $e');
      return false;
    }
  }

  Future<int?> getFolderGridZoomLevel(String folderPath) async {
    try {
      return await _getConfigInt(
        folderPath: folderPath,
        key: _gridZoomLevelKey,
      );
    } catch (e) {
      debugPrint('Unexpected error in getFolderGridZoomLevel: $e');
      return null;
    }
  }

  Future<bool> saveFolderGridZoomLevel(String folderPath, int zoomLevel) async {
    try {
      return await _saveConfigValue(
        folderPath: folderPath,
        key: _gridZoomLevelKey,
        value: zoomLevel,
      );
    } catch (e) {
      debugPrint('Unexpected error in saveFolderGridZoomLevel: $e');
      _cacheValue(folderPath, _gridZoomLevelKey, zoomLevel);
      return false;
    }
  }

  Future<ColumnVisibility?> getFolderColumnVisibility(String folderPath) async {
    try {
      final map = await _getConfigMap(
        folderPath: folderPath,
        key: _columnVisibilityKey,
      );
      return map == null ? null : ColumnVisibility.fromMap(map);
    } catch (e) {
      debugPrint('Unexpected error in getFolderColumnVisibility: $e');
      return null;
    }
  }

  Future<bool> saveFolderColumnVisibility(
    String folderPath,
    ColumnVisibility visibility,
  ) async {
    try {
      return await _saveConfigValue(
        folderPath: folderPath,
        key: _columnVisibilityKey,
        value: visibility.toMap(),
      );
    } catch (e) {
      debugPrint('Unexpected error in saveFolderColumnVisibility: $e');
      _cacheValue(folderPath, _columnVisibilityKey, visibility.toMap());
      return false;
    }
  }

  Future<bool?> getFolderShowFileTags(String folderPath) async {
    try {
      return await _getConfigBool(
        folderPath: folderPath,
        key: _showFileTagsKey,
      );
    } catch (e) {
      debugPrint('Unexpected error in getFolderShowFileTags: $e');
      return null;
    }
  }

  Future<bool> saveFolderShowFileTags(String folderPath, bool showTags) async {
    try {
      return await _saveConfigValue(
        folderPath: folderPath,
        key: _showFileTagsKey,
        value: showTags,
      );
    } catch (e) {
      debugPrint('Unexpected error in saveFolderShowFileTags: $e');
      _cacheValue(folderPath, _showFileTagsKey, showTags);
      return false;
    }
  }

  Future<bool?> getFolderPreviewPaneVisible(String folderPath) async {
    try {
      return await _getConfigBool(
        folderPath: folderPath,
        key: _previewPaneVisibleKey,
      );
    } catch (e) {
      debugPrint('Unexpected error in getFolderPreviewPaneVisible: $e');
      return null;
    }
  }

  Future<bool> saveFolderPreviewPaneVisible(
    String folderPath,
    bool visible,
  ) async {
    try {
      return await _saveConfigValue(
        folderPath: folderPath,
        key: _previewPaneVisibleKey,
        value: visible,
      );
    } catch (e) {
      debugPrint('Unexpected error in saveFolderPreviewPaneVisible: $e');
      _cacheValue(folderPath, _previewPaneVisibleKey, visible);
      return false;
    }
  }

  Future<double?> getFolderPreviewPaneWidth(String folderPath) async {
    try {
      return await _getConfigDouble(
        folderPath: folderPath,
        key: _previewPaneWidthKey,
      );
    } catch (e) {
      debugPrint('Unexpected error in getFolderPreviewPaneWidth: $e');
      return null;
    }
  }

  Future<bool> saveFolderPreviewPaneWidth(
    String folderPath,
    double width,
  ) async {
    try {
      return await _saveConfigValue(
        folderPath: folderPath,
        key: _previewPaneWidthKey,
        value: width,
      );
    } catch (e) {
      debugPrint('Unexpected error in saveFolderPreviewPaneWidth: $e');
      _cacheValue(folderPath, _previewPaneWidthKey, width);
      return false;
    }
  }

  Future<T?> _getConfigEnumValue<T>({
    required String folderPath,
    required String key,
    required List<T> values,
  }) async {
    final config = await _readConfig(folderPath);
    final rawIndex = config[key];
    if (rawIndex is int && rawIndex >= 0 && rawIndex < values.length) {
      return values[rawIndex];
    }
    return null;
  }

  Future<int?> _getConfigInt({
    required String folderPath,
    required String key,
  }) async {
    final config = await _readConfig(folderPath);
    final rawValue = config[key];
    return rawValue is int ? rawValue : null;
  }

  Future<bool?> _getConfigBool({
    required String folderPath,
    required String key,
  }) async {
    final config = await _readConfig(folderPath);
    final rawValue = config[key];
    return rawValue is bool ? rawValue : null;
  }

  Future<double?> _getConfigDouble({
    required String folderPath,
    required String key,
  }) async {
    final config = await _readConfig(folderPath);
    final rawValue = config[key];
    return rawValue is num ? rawValue.toDouble() : null;
  }

  Future<Map<String, dynamic>?> _getConfigMap({
    required String folderPath,
    required String key,
  }) async {
    final config = await _readConfig(folderPath);
    final rawValue = config[key];
    return rawValue is Map ? Map<String, dynamic>.from(rawValue) : null;
  }

  Future<Map<String, dynamic>> _readConfig(String folderPath) async {
    final pathKey = _normalizePath(folderPath);
    final cached = _folderConfigCache[pathKey];
    if (cached != null) {
      return Map<String, dynamic>.from(cached);
    }

    final stored = await _readStoredConfig(pathKey);
    if (stored != null) {
      _folderConfigCache[pathKey] = stored;
      return Map<String, dynamic>.from(stored);
    }

    final legacy = await _readLegacyConfig(folderPath);
    if (legacy.isNotEmpty) {
      await _insertLegacyConfig(pathKey, legacy);
    }
    _folderConfigCache[pathKey] = legacy;
    return Map<String, dynamic>.from(legacy);
  }

  Future<bool> _saveConfigValue({
    required String folderPath,
    required String key,
    required Object value,
  }) async {
    await _readConfig(folderPath);
    final database = await _getDatabase();
    final column = _columnForKey(key);
    final sqlValue = _sqlValueForKey(key, value);
    await database.rawInsert(
      '''
      INSERT INTO $_tableName (path, $column, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(path) DO UPDATE SET
        $column = excluded.$column,
        updated_at = excluded.updated_at
      ''',
      <Object?>[_normalizePath(folderPath), sqlValue, _now()],
    );
    _cacheValue(folderPath, key, value);
    return true;
  }

  Future<Database> _getDatabase() async {
    final database = await DatabaseManager.getInstance().getDatabase();
    _tableInitialization ??= _createTable(database);
    try {
      await _tableInitialization;
    } catch (_) {
      _tableInitialization = null;
      rethrow;
    }
    return database;
  }

  Future<void> _createTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
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
  }

  Future<Map<String, dynamic>?> _readStoredConfig(String pathKey) async {
    final database = await _getDatabase();
    final rows = await database.query(
      _tableName,
      where: 'path = ?',
      whereArgs: <Object?>[pathKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final config = <String, dynamic>{};
    _copyIntColumn(row, 'view_mode', config, _viewModeKey);
    _copyIntColumn(row, 'sort_option', config, _sortOptionKey);
    _copyIntColumn(row, 'grid_zoom_level', config, _gridZoomLevelKey);
    _copyBoolColumn(row, 'show_file_tags', config, _showFileTagsKey);
    _copyBoolColumn(
      row,
      'preview_pane_visible',
      config,
      _previewPaneVisibleKey,
    );
    final width = row['preview_pane_width'];
    if (width is num) {
      config[_previewPaneWidthKey] = width.toDouble();
    }
    final columnJson = row['column_visibility_json'];
    if (columnJson is String && columnJson.isNotEmpty) {
      final decoded = json.decode(columnJson);
      if (decoded is Map) {
        config[_columnVisibilityKey] = Map<String, dynamic>.from(decoded);
      }
    }
    return config;
  }

  Future<Map<String, dynamic>> _readLegacyConfig(String folderPath) async {
    if (folderPath.isEmpty ||
        folderPath.startsWith('#') ||
        folderPath.contains('://')) {
      return <String, dynamic>{};
    }

    final configFile = File(pathlib.join(folderPath, _legacyConfigFileName));
    if (!await configFile.exists()) {
      return <String, dynamic>{};
    }

    try {
      final decoded = json.decode(await configFile.readAsString());
      if (decoded is! Map) {
        return <String, dynamic>{};
      }
      final source = Map<String, dynamic>.from(decoded);
      final config = <String, dynamic>{};
      _copyLegacyInt(source, config, _viewModeKey);
      _copyLegacyInt(source, config, _sortOptionKey);
      _copyLegacyInt(source, config, _gridZoomLevelKey);
      _copyLegacyBool(source, config, _showFileTagsKey);
      _copyLegacyBool(source, config, _previewPaneVisibleKey);
      final width = source[_previewPaneWidthKey];
      if (width is num) {
        config[_previewPaneWidthKey] = width.toDouble();
      }
      final columnVisibility = source[_columnVisibilityKey];
      if (columnVisibility is Map) {
        config[_columnVisibilityKey] = Map<String, dynamic>.from(
          columnVisibility,
        );
      }
      return config;
    } catch (e) {
      debugPrint('Error reading legacy folder preferences: $e');
      return <String, dynamic>{};
    }
  }

  Future<void> _insertLegacyConfig(
    String pathKey,
    Map<String, dynamic> config,
  ) async {
    final database = await _getDatabase();
    await database.rawInsert(
      '''
      INSERT OR IGNORE INTO $_tableName (
        path,
        view_mode,
        sort_option,
        grid_zoom_level,
        column_visibility_json,
        show_file_tags,
        preview_pane_visible,
        preview_pane_width,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        pathKey,
        config[_viewModeKey],
        config[_sortOptionKey],
        config[_gridZoomLevelKey],
        config[_columnVisibilityKey] == null
            ? null
            : json.encode(config[_columnVisibilityKey]),
        _boolToInt(config[_showFileTagsKey]),
        _boolToInt(config[_previewPaneVisibleKey]),
        config[_previewPaneWidthKey],
        _now(),
      ],
    );
  }

  String _normalizePath(String folderPath) {
    final trimmed = folderPath.trim();
    if (trimmed.isEmpty) {
      return _drivesPreferencePath;
    }
    if (trimmed.startsWith('#') || trimmed.contains('://')) {
      return trimmed;
    }
    final normalized = pathlib.normalize(trimmed);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _columnForKey(String key) {
    switch (key) {
      case _viewModeKey:
        return 'view_mode';
      case _sortOptionKey:
        return 'sort_option';
      case _gridZoomLevelKey:
        return 'grid_zoom_level';
      case _columnVisibilityKey:
        return 'column_visibility_json';
      case _showFileTagsKey:
        return 'show_file_tags';
      case _previewPaneVisibleKey:
        return 'preview_pane_visible';
      case _previewPaneWidthKey:
        return 'preview_pane_width';
      default:
        throw ArgumentError.value(key, 'key', 'Unknown folder preference key');
    }
  }

  Object? _sqlValueForKey(String key, Object value) {
    switch (key) {
      case _columnVisibilityKey:
        return json.encode(value);
      case _showFileTagsKey:
      case _previewPaneVisibleKey:
        return value == true ? 1 : 0;
      default:
        return value;
    }
  }

  void _cacheValue(String folderPath, String key, Object value) {
    final pathKey = _normalizePath(folderPath);
    final config = Map<String, dynamic>.from(
      _folderConfigCache[pathKey] ?? <String, dynamic>{},
    );
    config[key] = value;
    _folderConfigCache[pathKey] = config;
  }

  void _copyIntColumn(
    Map<String, Object?> row,
    String column,
    Map<String, dynamic> config,
    String key,
  ) {
    final value = row[column];
    if (value is int) {
      config[key] = value;
    }
  }

  void _copyBoolColumn(
    Map<String, Object?> row,
    String column,
    Map<String, dynamic> config,
    String key,
  ) {
    final value = row[column];
    if (value is int) {
      config[key] = value == 1;
    }
  }

  void _copyLegacyInt(
    Map<String, dynamic> source,
    Map<String, dynamic> config,
    String key,
  ) {
    final value = source[key];
    if (value is int) {
      config[key] = value;
    }
  }

  void _copyLegacyBool(
    Map<String, dynamic> source,
    Map<String, dynamic> config,
    String key,
  ) {
    final value = source[key];
    if (value is bool) {
      config[key] = value;
    }
  }

  int? _boolToInt(Object? value) {
    return value is bool ? (value ? 1 : 0) : null;
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;
}
