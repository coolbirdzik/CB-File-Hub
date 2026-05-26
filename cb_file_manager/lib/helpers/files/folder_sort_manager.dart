import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

/// Manages per-folder sorting preferences using JSON config files
class FolderSortManager {
  static const String _viewModeKey = 'viewMode';
  static const String _sortOptionKey = 'sortOption';
  static const String _gridZoomLevelKey = 'gridZoomLevel';
  static const String _columnVisibilityKey = 'columnVisibility';
  static const String _showFileTagsKey = 'showFileTags';
  static const String _previewPaneVisibleKey = 'previewPaneVisible';
  static const String _previewPaneWidthKey = 'previewPaneWidth';

  static final FolderSortManager _instance = FolderSortManager._internal();

  // Singleton constructor
  factory FolderSortManager() => _instance;

  FolderSortManager._internal();

  // Cache of sort options for each folder
  final Map<String, SortOption> _folderSortCache = {};
  final Map<String, ViewMode> _folderViewModeCache = {};
  final Map<String, int> _folderGridZoomCache = {};
  final Map<String, ColumnVisibility> _folderColumnVisibilityCache = {};
  final Map<String, bool> _folderShowFileTagsCache = {};
  final Map<String, bool> _folderPreviewPaneVisibleCache = {};
  final Map<String, double> _folderPreviewPaneWidthCache = {};

  // In-memory database for system paths
  final Map<String, Map<String, dynamic>> _systemPathConfigs = {};

  // Detect if a path is a system/virtual path (starts with #)
  bool _isSystemPath(String path) {
    return path.startsWith('#');
  }

  /// Get the sort option for a specific folder
  /// If a folder-specific option is found, it's returned
  /// Otherwise returns null (fallback to global preference)
  /// This method is designed to never throw exceptions to avoid blocking folder loading
  Future<SortOption?> getFolderSortOption(String folderPath) async {
    try {
      // Check cache first
      if (_folderSortCache.containsKey(folderPath)) {
        return _folderSortCache[folderPath];
      }

      SortOption? sortOption;

      // Use JSON config for all platforms and paths - NO TIMEOUT for faster loading
      try {
        sortOption = await _getMobileSortOption(folderPath);
      } catch (e) {
        debugPrint('JSON config method failed: $e');
        sortOption = null;
      }

      // Cache the result if found
      if (sortOption != null) {
        _folderSortCache[folderPath] = sortOption;
      }

      return sortOption;
    } catch (e) {
      // Ultimate safety net - never let this method throw exceptions
      debugPrint('Unexpected error in getFolderSortOption: $e');
      return null;
    }
  }

  /// Save the sort option for a specific folder
  /// This method is designed to never throw exceptions to avoid blocking folder operations
  Future<bool> saveFolderSortOption(
      String folderPath, SortOption sortOption) async {
    try {
      // Skip saving for invalid paths (URLs, protocols, etc.)
      if (folderPath.contains('://') || folderPath.isEmpty) {
        debugPrint('Skipping sort option save for invalid path: $folderPath');
        // Still cache it in memory for the session
        _folderSortCache[folderPath] = sortOption;
        return true; // Return true to avoid error messages
      }

      bool success = false;

      // Use JSON config for all platforms and paths - NO TIMEOUT for faster saving
      try {
        success = await _saveMobileSortOption(folderPath, sortOption);
        if (success) {
          debugPrint('Successfully saved sort option using JSON config');
        }
      } catch (e) {
        debugPrint('JSON save method failed: $e');
        success = false;
      }

      // Update cache if successful
      if (success) {
        _folderSortCache[folderPath] = sortOption;
      }

      return success;
    } catch (e) {
      // Ultimate safety net - never let this method throw exceptions
      debugPrint('Unexpected error in saveFolderSortOption: $e');
      // Still try to cache it in memory as a last resort
      _folderSortCache[folderPath] = sortOption;
      return false;
    }
  }

  Future<ViewMode?> getFolderViewMode(String folderPath) async {
    try {
      if (_folderViewModeCache.containsKey(folderPath)) {
        return _folderViewModeCache[folderPath];
      }

      final viewMode = await _getConfigEnumValue<ViewMode>(
        folderPath: folderPath,
        key: _viewModeKey,
        values: ViewMode.values,
      );
      if (viewMode != null) {
        _folderViewModeCache[folderPath] = viewMode;
      }
      return viewMode;
    } catch (e) {
      debugPrint('Unexpected error in getFolderViewMode: $e');
      return null;
    }
  }

  Future<bool> saveFolderViewMode(String folderPath, ViewMode viewMode) async {
    try {
      if (folderPath.contains('://') || folderPath.isEmpty) {
        debugPrint('Skipping view mode save for invalid path: $folderPath');
        _folderViewModeCache[folderPath] = viewMode;
        return true;
      }

      final success = await _saveConfigValue(
        folderPath: folderPath,
        key: _viewModeKey,
        value: viewMode.index,
      );
      if (success) {
        _folderViewModeCache[folderPath] = viewMode;
      }
      return success;
    } catch (e) {
      debugPrint('Unexpected error in saveFolderViewMode: $e');
      _folderViewModeCache[folderPath] = viewMode;
      return false;
    }
  }

  /// Clear the sort option for a specific folder
  Future<bool> clearFolderSortOption(String folderPath) async {
    try {
      bool success = await _clearMobileSortOption(folderPath);

      // Remove from cache if successful
      if (success) {
        _folderSortCache.remove(folderPath);
      }

      return success;
    } catch (e) {
      debugPrint('Error clearing folder sort option: $e');
      return false;
    }
  }

  Future<int?> getFolderGridZoomLevel(String folderPath) async {
    try {
      final cached = _folderGridZoomCache[folderPath];
      if (cached != null) return cached;
      final value = await _getConfigInt(
        folderPath: folderPath,
        key: _gridZoomLevelKey,
      );
      if (value != null) {
        _folderGridZoomCache[folderPath] = value;
      }
      return value;
    } catch (e) {
      debugPrint('Unexpected error in getFolderGridZoomLevel: $e');
      return null;
    }
  }

  Future<bool> saveFolderGridZoomLevel(String folderPath, int zoomLevel) async {
    try {
      final success = await _saveConfigValue(
        folderPath: folderPath,
        key: _gridZoomLevelKey,
        value: zoomLevel,
      );
      if (success) {
        _folderGridZoomCache[folderPath] = zoomLevel;
      }
      return success;
    } catch (e) {
      debugPrint('Unexpected error in saveFolderGridZoomLevel: $e');
      _folderGridZoomCache[folderPath] = zoomLevel;
      return false;
    }
  }

  Future<ColumnVisibility?> getFolderColumnVisibility(String folderPath) async {
    try {
      final cached = _folderColumnVisibilityCache[folderPath];
      if (cached != null) return cached;
      final map = await _getConfigMap(
        folderPath: folderPath,
        key: _columnVisibilityKey,
      );
      if (map == null) return null;
      final visibility = ColumnVisibility.fromMap(map);
      _folderColumnVisibilityCache[folderPath] = visibility;
      return visibility;
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
      final success = await _saveConfigValue(
        folderPath: folderPath,
        key: _columnVisibilityKey,
        value: visibility.toMap(),
      );
      if (success) {
        _folderColumnVisibilityCache[folderPath] = visibility;
      }
      return success;
    } catch (e) {
      debugPrint('Unexpected error in saveFolderColumnVisibility: $e');
      _folderColumnVisibilityCache[folderPath] = visibility;
      return false;
    }
  }

  Future<bool?> getFolderShowFileTags(String folderPath) async {
    try {
      final cached = _folderShowFileTagsCache[folderPath];
      if (cached != null) return cached;
      final value = await _getConfigBool(
        folderPath: folderPath,
        key: _showFileTagsKey,
      );
      if (value != null) {
        _folderShowFileTagsCache[folderPath] = value;
      }
      return value;
    } catch (e) {
      debugPrint('Unexpected error in getFolderShowFileTags: $e');
      return null;
    }
  }

  Future<bool> saveFolderShowFileTags(String folderPath, bool showTags) async {
    try {
      final success = await _saveConfigValue(
        folderPath: folderPath,
        key: _showFileTagsKey,
        value: showTags,
      );
      if (success) {
        _folderShowFileTagsCache[folderPath] = showTags;
      }
      return success;
    } catch (e) {
      debugPrint('Unexpected error in saveFolderShowFileTags: $e');
      _folderShowFileTagsCache[folderPath] = showTags;
      return false;
    }
  }

  Future<bool?> getFolderPreviewPaneVisible(String folderPath) async {
    try {
      final cached = _folderPreviewPaneVisibleCache[folderPath];
      if (cached != null) return cached;
      final value = await _getConfigBool(
        folderPath: folderPath,
        key: _previewPaneVisibleKey,
      );
      if (value != null) {
        _folderPreviewPaneVisibleCache[folderPath] = value;
      }
      return value;
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
      final success = await _saveConfigValue(
        folderPath: folderPath,
        key: _previewPaneVisibleKey,
        value: visible,
      );
      if (success) {
        _folderPreviewPaneVisibleCache[folderPath] = visible;
      }
      return success;
    } catch (e) {
      debugPrint('Unexpected error in saveFolderPreviewPaneVisible: $e');
      _folderPreviewPaneVisibleCache[folderPath] = visible;
      return false;
    }
  }

  Future<double?> getFolderPreviewPaneWidth(String folderPath) async {
    try {
      final cached = _folderPreviewPaneWidthCache[folderPath];
      if (cached != null) return cached;
      final value = await _getConfigDouble(
        folderPath: folderPath,
        key: _previewPaneWidthKey,
      );
      if (value != null) {
        _folderPreviewPaneWidthCache[folderPath] = value;
      }
      return value;
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
      final success = await _saveConfigValue(
        folderPath: folderPath,
        key: _previewPaneWidthKey,
        value: width,
      );
      if (success) {
        _folderPreviewPaneWidthCache[folderPath] = width;
      }
      return success;
    } catch (e) {
      debugPrint('Unexpected error in saveFolderPreviewPaneWidth: $e');
      _folderPreviewPaneWidthCache[folderPath] = width;
      return false;
    }
  }

  /// Get sorting option from cbfile_config.json file
  Future<SortOption?> _getMobileSortOption(String folderPath) async {
    try {
      // For system paths, use in-memory database
      if (_isSystemPath(folderPath)) {
        final config = _systemPathConfigs[folderPath];
        if (config != null && config.containsKey(_sortOptionKey)) {
          int sortIndex = config[_sortOptionKey];
          if (sortIndex >= 0 && sortIndex < SortOption.values.length) {
            return SortOption.values[sortIndex];
          }
        }
        return null;
      }

      // Normal path - use file-based approach
      final configPath = pathlib.join(folderPath, '.cbfile_config.json');
      final configFile = File(configPath);

      if (!await configFile.exists()) {
        return null;
      }

      final contents = await configFile.readAsString();
      final Map<String, dynamic> config = json.decode(contents);

      if (config.containsKey(_sortOptionKey)) {
        int sortIndex = config[_sortOptionKey];
        if (sortIndex >= 0 && sortIndex < SortOption.values.length) {
          return SortOption.values[sortIndex];
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error reading sort option: $e');
      return null;
    }
  }

  /// Save sorting option to cbfile_config.json file
  Future<bool> _saveMobileSortOption(
      String folderPath, SortOption sortOption) async {
    try {
      return await _saveConfigValue(
        folderPath: folderPath,
        key: _sortOptionKey,
        value: sortOption.index,
      );
    } catch (e) {
      debugPrint('Error saving sort option: $e');
      return false;
    }
  }

  Future<T?> _getConfigEnumValue<T>({
    required String folderPath,
    required String key,
    required List<T> values,
  }) async {
    try {
      final config = await _readConfig(folderPath);
      final rawIndex = config[key];
      if (rawIndex is int && rawIndex >= 0 && rawIndex < values.length) {
        return values[rawIndex];
      }
      return null;
    } catch (e) {
      debugPrint('Error reading $key: $e');
      return null;
    }
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
    if (rawValue is double) return rawValue;
    if (rawValue is int) return rawValue.toDouble();
    return null;
  }

  Future<Map<String, dynamic>?> _getConfigMap({
    required String folderPath,
    required String key,
  }) async {
    final config = await _readConfig(folderPath);
    final rawValue = config[key];
    if (rawValue is Map) {
      return Map<String, dynamic>.from(rawValue);
    }
    return null;
  }

  Future<Map<String, dynamic>> _readConfig(String folderPath) async {
    if (_isSystemPath(folderPath)) {
      return Map<String, dynamic>.from(_systemPathConfigs[folderPath] ?? {});
    }

    final configPath = pathlib.join(folderPath, '.cbfile_config.json');
    final configFile = File(configPath);
    if (!await configFile.exists()) {
      return <String, dynamic>{};
    }

    final contents = await configFile.readAsString();
    if (contents.isEmpty) {
      return <String, dynamic>{};
    }
    return Map<String, dynamic>.from(json.decode(contents) as Map);
  }

  Future<bool> _saveConfigValue({
    required String folderPath,
    required String key,
    required Object value,
  }) async {
    if (folderPath.contains('://') || folderPath.isEmpty) {
      debugPrint('Skipping config save for invalid path: $folderPath');
      return true;
    }

    if (_isSystemPath(folderPath)) {
      final config = Map<String, dynamic>.from(
        _systemPathConfigs[folderPath] ?? {},
      );
      config[key] = value;
      _systemPathConfigs[folderPath] = config;
      debugPrint('Saved $key for system path in memory: $folderPath');
      return true;
    }

    final configPath = pathlib.join(folderPath, '.cbfile_config.json');
    final configFile = File(configPath);
    final config = await _readConfig(folderPath);
    config[key] = value;

    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    if (await configFile.exists()) {
      try {
        await configFile.delete();
      } catch (e) {
        debugPrint('Warning: Failed to delete existing config file: $e');
      }
    }

    final jsonString = const JsonEncoder.withIndent('  ').convert(config);
    await configFile.writeAsString(jsonString);
    debugPrint('Successfully saved config file: $jsonString');

    if (Platform.isWindows) {
      try {
        final result = await Process.run('attrib', ['+H', configPath]);
        debugPrint(
            'Set hidden attribute on config file (exit code: ${result.exitCode})');
      } catch (e) {
        debugPrint('Error making config file hidden: $e');
      }
    } else if (Platform.isAndroid) {
      try {
        final nomediaFile = File(pathlib.join(folderPath, '.nomedia'));
        if (!await nomediaFile.exists()) {
          await nomediaFile.create();
        }
      } catch (e) {
        debugPrint('Error creating .nomedia file: $e');
      }
    }

    return true;
  }

  /// Clear mobile sort settings
  Future<bool> _clearMobileSortOption(String folderPath) async {
    try {
      // For system paths, use in-memory database
      if (_isSystemPath(folderPath)) {
        _systemPathConfigs.remove(folderPath);
        debugPrint(
            'Cleared sort option for system path from memory: $folderPath');
        return true;
      }

      // Normal path - use file-based approach
      final configPath = pathlib.join(folderPath, '.cbfile_config.json');
      final configFile = File(configPath);

      if (!await configFile.exists()) {
        return true; // Nothing to clear
      }

      Map<String, dynamic> config = {};

      // Load existing config
      final contents = await configFile.readAsString();
      config = json.decode(contents);

      // Remove sort option
      config.remove(_sortOptionKey);

      // If config is now empty, delete the file
      if (config.isEmpty) {
        await configFile.delete();
      } else {
        // Otherwise, write back the updated config
        await configFile.writeAsString(json.encode(config));
      }

      return true;
    } catch (e) {
      debugPrint('Error clearing sort settings: $e');
      return false;
    }
  }
}
