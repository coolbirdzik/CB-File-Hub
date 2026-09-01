import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/utils/base_screen.dart';
import 'package:cb_file_manager/config/translation_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:cb_file_manager/ui/utils/route.dart';

/// A screen for managing database settings
class DatabaseSettingsScreen extends StatefulWidget {
  const DatabaseSettingsScreen({Key? key}) : super(key: key);

  @override
  State<DatabaseSettingsScreen> createState() => _DatabaseSettingsScreenState();
}

class _DatabaseSettingsScreenState extends State<DatabaseSettingsScreen> {
  final UserPreferences _preferences = UserPreferences.instance;
  final DatabaseManager _databaseManager = DatabaseManager.getInstance();

  bool _isUsingDatabase = true;
  bool _isLoading = true;

  Set<String> _uniqueTags = {};
  Map<String, int> _popularTags = {};
  int _totalTagCount = 0;
  int _totalFileCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _loadPreferences();
      await _databaseManager.initialize();

      // Load statistics
      await _loadStatistics();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading database settings: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPreferences() async {
    try {
      await _preferences.init();

      if (mounted) {
        setState(() {
          _isUsingDatabase = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading database preferences: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading database preferences: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _loadStatistics() async {
    try {
      // Get all unique tags
      final allTags = await _databaseManager.getAllUniqueTags();
      _uniqueTags = Set.from(allTags);
      _totalTagCount = _uniqueTags.length;

      // Get popular tags (top 10)
      _popularTags = await TagManager.instance.getPopularTags(limit: 10);

      // Count total number of tagged files
      final List<Future<List<String>>> fileFutures = [];
      for (final tag in _uniqueTags.take(5)) {
        // Limit to first 5 tags to avoid too many queries
        fileFutures.add(_databaseManager.findFilesByTag(tag));
      }

      final results = await Future.wait(fileFutures);
      final Set<String> allFiles = {};
      for (final files in results) {
        allFiles.addAll(files);
      }

      _totalFileCount = allFiles.length;
    } catch (e) {
      debugPrint('Error loading database statistics: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: context.tr.databaseSettings,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 16),
                _buildDatabaseTypeSection(),
                const Divider(),
                _buildImportExportSection(),
                const Divider(),
                _buildRawDataSection(),
                const Divider(),
                _buildStatisticsSection(),
              ],
            ),
    );
  }

  Widget _buildDatabaseTypeSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.hardDrives, size: 24),
                const SizedBox(width: 16),
                Text(
                  context.tr.databaseStorage,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(
              _isUsingDatabase
                  ? PhosphorIconsLight.checkCircle
                  : PhosphorIconsLight.warning,
              color: _isUsingDatabase ? Colors.green : Colors.orange,
            ),
            title: Text(context.tr.useDatabaseStorage),
            subtitle: Text(
              _isUsingDatabase
                  ? context.tr.databaseStorageEnabled
                  : context.tr.jsonStorage,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              context.tr.databaseDescription,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildImportExportSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.arrowsDownUp, size: 24),
                const SizedBox(width: 16),
                Text(
                  context.tr.backupAndRestore,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              context.tr.backupRestoreHint,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: Text(context.tr.exportSqlite),
            subtitle: Text(context.tr.exportSqliteDesc),
            leading: const Icon(PhosphorIconsLight.database),
            onTap: _exportSqlite,
          ),
          ListTile(
            title: Text(context.tr.exportJson),
            subtitle: Text(context.tr.exportJsonDesc),
            leading: const Icon(PhosphorIconsLight.fileDoc),
            onTap: _exportPreferencesJson,
          ),
          const Divider(),
          ListTile(
            title: Text(context.tr.importBackup),
            subtitle: Text(context.tr.importBackupDesc),
            leading: const Icon(PhosphorIconsLight.downloadSimple),
            onTap: _importUnified,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _exportSqlite() async {
    try {
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final saveLocation = await FilePicker.platform.saveFile(
        dialogTitle: context.tr.saveBackup,
        fileName: 'cb_file_hub_backup_$timestamp.db',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );

      if (saveLocation == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Text(context.tr.exporting),
            ],
          ),
        ),
      );

      final prefs = _preferences.getAllSettings();
      final filePath = await _databaseManager.exportAsSqlite(
        preferences: prefs,
        customPath: saveLocation,
      );

      if (mounted) Navigator.pop(context);

      if (filePath != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Exported to: $filePath'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr.exportFailed),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr.errorExporting}$e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _exportPreferencesJson() async {
    try {
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final saveLocation = await FilePicker.platform.saveFile(
        dialogTitle: context.tr.exportPreferencesAsJson,
        fileName: 'cb_file_hub_preferences_$timestamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (saveLocation == null) return;

      final prefs = _preferences.getAllSettings();
      final jsonString = const JsonEncoder.withIndent('  ').convert(prefs);
      await io.File(saveLocation).writeAsString(jsonString);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported preferences to: $saveLocation'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr.errorExporting}$e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _importUnified() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'json'],
      );

      if (result == null || result.files.single.path == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Text(context.tr.importing),
            ],
          ),
        ),
      );

      final summary = await _databaseManager.importUnified(
        filePath: result.files.single.path!,
        skipFileExistenceCheck: true,
        onRestorePreferences: (prefs) async {
          await _preferences.restoreAllFrom(prefs);
        },
      );

      if (mounted) Navigator.pop(context);

      if (summary != null) {
        try {
          TagManager.clearCache();
        } catch (_) {}
        await _loadStatistics();

        if (mounted) {
          final tagMsg =
              context.tr.tagsImported(summary['importedTagCount'] as int);
          final prefMsg =
              context.tr.settingsRestored(summary['preferencesCount'] as int);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$tagMsg, $prefMsg.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr.importFailed),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr.errorImporting}$e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Widget _buildStatisticsSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.chartBar, size: 24),
                const SizedBox(width: 16),
                Text(
                  context.tr.databaseStatistics,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            title: Text(context.tr.totalUniqueTags),
            trailing: Text(
              '$_totalTagCount',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            title: Text(context.tr.taggedFiles),
            trailing: Text(
              '$_totalFileCount',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              context.tr.popularTags,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _popularTags.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(child: Text(context.tr.noTagsFound)),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _popularTags.entries.map((entry) {
                      return Chip(
                        label: Text(entry.key),
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.2),
                        avatar: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: Text(
                            '${entry.value}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: OutlinedButton.icon(
                icon: const Icon(PhosphorIconsLight.arrowsClockwise),
                label: Text(context.tr.refreshStatistics),
                onPressed: () async {
                  setState(() {
                    _isLoading = true;
                  });
                  await _loadStatistics();
                  setState(() {
                    _isLoading = false;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawDataSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.code, size: 24),
                const SizedBox(width: 16),
                Text(
                  context.tr.viewRawData,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              context.tr.rawDataDescription,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            title: Text(context.tr.rawDataPreferences),
            subtitle: Text(context.tr.rawDataPreferences),
            leading: const Icon(PhosphorIconsLight.gear),
            onTap: () => _showRawDataDialog(
                context.tr.rawDataPreferences, 'preferences'),
          ),
          ListTile(
            title: Text(context.tr.rawDataTags),
            subtitle: Text(context.tr.rawDataTags),
            leading: const Icon(PhosphorIconsLight.tag),
            onTap: () => _showRawDataDialog(context.tr.rawDataTags, 'tags'),
          ),
          ListTile(
            title: Text(context.tr.sharedPreferences),
            subtitle: Text(context.tr.sharedPreferencesDesc),
            leading: const Icon(PhosphorIconsLight.floppyDisk),
            onTap: _showSharedPreferencesDialog,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _showRawDataDialog(String title, String type) async {
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => _RawDataDialog(
        title: title,
        type: type,
        databaseManager: _databaseManager,
      ),
    );
  }

  void _showSharedPreferencesDialog() {
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (ctx) => _SharedPreferencesDialog(
        onDeleted: () {
          // Refresh raw data dialog if open
        },
      ),
    );
  }
}

/// Dialog for viewing SharedPreferences keys/values
class _SharedPreferencesDialog extends StatefulWidget {
  final VoidCallback? onDeleted;

  const _SharedPreferencesDialog({this.onDeleted});

  @override
  State<_SharedPreferencesDialog> createState() =>
      _SharedPreferencesDialogState();
}

class _SharedPreferencesDialogState extends State<_SharedPreferencesDialog> {
  Map<String, Object?> _prefs = {};
  bool _isLoading = true;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = Map<String, Object?>.fromEntries(
        prefs.getKeys().map((key) => MapEntry(key, prefs.get(key))),
      );
    } catch (e) {
      debugPrint('Error loading SharedPreferences: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr.clearSharedPreferencesConfirm),
        content: const Text(
          'This will delete all app settings including theme, language, '
          'and view preferences. The app may restart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(context.tr.clear),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isClearing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      widget.onDeleted?.call();
      await _loadPrefs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.sharedPreferencesCleared)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
    if (mounted) setState(() => _isClearing = false);
  }

  Future<void> _deleteKey(String key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr.deleteKeyConfirm),
        content: Text(context.tr.sharedPreferencesKeyRemoved),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(context.tr.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await _loadPrefs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.deletedKey + key)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedEntries = _prefs.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return AlertDialog(
      title: Row(
        children: [
          Text(context.tr.sharedPreferences),
          const Spacer(),
          if (_isClearing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            IconButton(
              icon: const Icon(PhosphorIconsLight.trash),
              tooltip: context.tr.clearAll,
              onPressed: _clearAll,
              color: Theme.of(context).colorScheme.error,
            ),
            IconButton(
              icon: const Icon(PhosphorIconsLight.arrowsClockwise),
              tooltip: context.tr.refresh,
              onPressed: _loadPrefs,
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.7,
        height: MediaQuery.of(context).size.height * 0.65,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _prefs.isEmpty
                ? const Center(child: Text('No preferences stored.'))
                : ListView.builder(
                    itemCount: sortedEntries.length,
                    itemBuilder: (ctx, i) {
                      final entry = sortedEntries[i];
                      return _buildPrefTile(entry.key, entry.value);
                    },
                  ),
      ),
      actions: [
        Text(
          '${_prefs.length} keys',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildPrefTile(String key, Object? value) {
    String displayValue;
    if (value == null) {
      displayValue = 'null';
    } else if (value is String) {
      displayValue = value.length > 80 ? '${value.substring(0, 80)}...' : value;
    } else if (value is List) {
      displayValue = '[${value.length} items]';
    } else {
      displayValue = value.toString();
    }

    return ListTile(
      dense: true,
      leading: Icon(
        _iconForValue(value),
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        key,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        displayValue,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(PhosphorIconsLight.copy, size: 16),
            tooltip: context.tr.copyValue,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$value'));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.tr.copied + value.toString()),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              PhosphorIconsLight.trash,
              size: 16,
              color: Theme.of(context).colorScheme.error,
            ),
            tooltip: context.tr.deleteKey,
            onPressed: () => _deleteKey(key),
          ),
        ],
      ),
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: '$key: $value'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr.copied}$key: $value'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      },
    );
  }

  IconData _iconForValue(Object? value) {
    if (value == null) return PhosphorIconsLight.minus;
    if (value is String) return PhosphorIconsLight.textT;
    if (value is int) return PhosphorIconsLight.hash;
    if (value is bool) return PhosphorIconsLight.checkSquare;
    if (value is double) return PhosphorIconsLight.percent;
    if (value is List) return PhosphorIconsLight.list;
    return PhosphorIconsLight.plugsConnected;
  }
}

/// Dialog for displaying raw data
class _RawDataDialog extends StatefulWidget {
  final String title;
  final String type;
  final DatabaseManager databaseManager;

  const _RawDataDialog({
    required this.title,
    required this.type,
    required this.databaseManager,
  });

  @override
  State<_RawDataDialog> createState() => _RawDataDialogState();
}

class _RawDataDialogState extends State<_RawDataDialog> {
  bool _isLoading = true;
  bool _isPageLoading = false;
  bool _attemptedLegacyTagMigration = false;
  int _rowsPerPage = PaginatedDataTable.defaultRowsPerPage;
  int _totalRows = 0;
  int _currentOffset = 0;
  List<Map<String, dynamic>> _pageRows = <Map<String, dynamic>>[];
  late final List<String> _columns;
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  static const Set<String> _timestampKeys = <String>{
    'timestamp',
    'createdAt',
    'created_at',
    'lastConnected',
    'last_connected',
  };

  @override
  void initState() {
    super.initState();
    _columns = _defaultColumnsForType();
    _loadData();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      if (widget.type == 'preferences') {
        _totalRows = await widget.databaseManager.getPreferencesRawCount();
      } else if (widget.type == 'tags') {
        _totalRows = await widget.databaseManager.getFileTagsRawCount();

        if (_totalRows == 0 && !_attemptedLegacyTagMigration) {
          _attemptedLegacyTagMigration = true;
          final migratedCount = await TagManager.migrateFromJsonToDatabase();
          if (migratedCount > 0) {
            _totalRows = await widget.databaseManager.getFileTagsRawCount();
          }
        }
      }

      if (_totalRows > 0) {
        final pageSize = _resolveRowsPerPage();
        final maxOffset = ((_totalRows - 1) ~/ pageSize) * pageSize;
        final targetOffset = math.min(_currentOffset, maxOffset);
        await _loadPage(offset: targetOffset, showTableLoader: false);
      } else {
        _currentOffset = 0;
        _pageRows = <Map<String, dynamic>>[];
      }
    } catch (e) {
      debugPrint('Error loading raw data: $e');
    }

    if (!mounted) {
      return;
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    // Dialog uses theme's dialogColor which has solid background
    return AlertDialog(
      title: Row(
        children: [
          Text(widget.title),
          const Spacer(),
          IconButton(
            icon: const Icon(PhosphorIconsLight.copy),
            onPressed: _totalRows == 0
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final copiedMsg = context.tr.jsonCopiedToClipboard;
                    final data = await _loadAllRows();
                    await Clipboard.setData(
                      ClipboardData(text: _encodeJson(data)),
                    );
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text(copiedMsg)),
                    );
                  },
            tooltip: context.tr.copyJson,
          ),
          IconButton(
            icon: const Icon(PhosphorIconsLight.arrowsClockwise),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(PhosphorIconsLight.bracketsCurly),
            onPressed: _totalRows == 0
                ? null
                : () async {
                    await _showJsonPreviewDialog(context);
                  },
            tooltip: context.tr.viewJson,
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _totalRows == 0
                ? Center(child: Text(context.tr.noDataFound))
                : _buildDataTable(context),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(
            '$_totalRows rows',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _encodeJson(List<Map<String, dynamic>> data) {
    // Simple JSON encoding with indentation
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Widget _buildDataTable(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveRowsPerPage = _resolveRowsPerPage();
    final visibleStart = _totalRows == 0 ? 0 : _currentOffset + 1;
    final visibleEnd = math.min(_currentOffset + _pageRows.length, _totalRows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '$visibleStart-$visibleEnd of $_totalRows',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            Text(
              'Rows per page',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            CbSelect.fromValues<int>(
              size: CbSelectSize.sm,
              values: _availableRowsPerPage(),
              value: effectiveRowsPerPage,
              labelBuilder: (value) => '$value',
              onChanged: _isPageLoading
                  ? null
                  : (value) async {
                      setState(() {
                        _rowsPerPage = value;
                      });
                      await _loadPage(offset: 0);
                    },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Stack(
            children: [
              Scrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: Scrollbar(
                    controller: _verticalScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _verticalScrollController,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width * 0.72,
                        ),
                        child: DataTable(
                          headingRowColor: WidgetStatePropertyAll(
                            colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                          ),
                          columnSpacing: 20,
                          horizontalMargin: 16,
                          dataRowMinHeight: 44,
                          dataRowMaxHeight: 64,
                          columns: _columns
                              .map(
                                (column) => DataColumn(
                                  label: Text(
                                    _humanizeColumnName(column),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          rows: _pageRows
                              .map(_buildDataRow)
                              .toList(growable: false),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_isPageLoading)
                Positioned.fill(
                  child: ColoredBox(
                    color: colorScheme.surface.withValues(alpha: 0.5),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              onPressed: _canGoToPreviousPage() && !_isPageLoading
                  ? () => _loadPage(offset: 0)
                  : null,
              icon: const Icon(Icons.first_page),
              tooltip: context.tr.firstPage,
            ),
            IconButton(
              onPressed: _canGoToPreviousPage() && !_isPageLoading
                  ? () => _loadPage(
                      offset:
                          math.max(0, _currentOffset - effectiveRowsPerPage))
                  : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: context.tr.previousPage,
            ),
            Text(
              'Page ${_currentPageNumber()} / ${_totalPages()}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            IconButton(
              onPressed: _canGoToNextPage() && !_isPageLoading
                  ? () =>
                      _loadPage(offset: _currentOffset + effectiveRowsPerPage)
                  : null,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next page',
            ),
            IconButton(
              onPressed: _canGoToNextPage() && !_isPageLoading
                  ? () => _loadPage(
                      offset: (_totalPages() - 1) * effectiveRowsPerPage)
                  : null,
              icon: const Icon(Icons.last_page),
              tooltip: 'Last page',
            ),
          ],
        ),
      ],
    );
  }

  int _resolveRowsPerPage() {
    if (_totalRows == 0) {
      return PaginatedDataTable.defaultRowsPerPage;
    }

    final rowsPerPage = _rowsPerPage.clamp(1, _totalRows);
    return rowsPerPage;
  }

  List<int> _availableRowsPerPage() {
    final options = <int>{10, 25, 50, 100};
    options.removeWhere((value) => value >= _totalRows);
    options.add(_resolveRowsPerPage());
    return options.toList()..sort();
  }

  List<String> _defaultColumnsForType() {
    switch (widget.type) {
      case 'preferences':
        return <String>[
          'key',
          'type',
          'stringValue',
          'intValue',
          'doubleValue',
          'boolValue',
          'timestamp',
        ];
      case 'tags':
        return <String>[
          'id',
          'filePath',
          'tag',
          'normalizedTag',
          'createdAt',
        ];
      default:
        return <String>[];
    }
  }

  Future<void> _loadPage({
    required int offset,
    bool showTableLoader = true,
  }) async {
    if (_totalRows == 0) {
      return;
    }

    final pageSize = _resolveRowsPerPage();
    final maxOffset = ((_totalRows - 1) ~/ pageSize) * pageSize;
    final normalizedOffset = math.max(0, math.min(offset, maxOffset));

    if (showTableLoader && mounted) {
      setState(() {
        _isPageLoading = true;
      });
    }

    try {
      final rows = widget.type == 'preferences'
          ? await widget.databaseManager.getPreferencesRawPage(
              offset: normalizedOffset,
              limit: pageSize,
            )
          : await widget.databaseManager.getFileTagsRawPage(
              offset: normalizedOffset,
              limit: pageSize,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _currentOffset = normalizedOffset;
        _pageRows = rows;
      });
    } catch (error) {
      debugPrint('Error loading raw data page: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isPageLoading = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadAllRows() {
    if (widget.type == 'preferences') {
      return widget.databaseManager.getAllPreferencesRaw();
    }

    return widget.databaseManager.getAllFileTagsRaw();
  }

  String _humanizeColumnName(String key) {
    final buffer = StringBuffer();
    for (var index = 0; index < key.length; index++) {
      final char = key[index];
      final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
      final isUnderscore = char == '_';

      if (index == 0) {
        buffer.write(char.toUpperCase());
        continue;
      }

      if (isUnderscore) {
        buffer.write(' ');
        continue;
      }

      if (isUpper) {
        buffer.write(' ');
      }

      buffer.write(char);
    }

    return buffer.toString();
  }

  String _formatCellValue(String key, dynamic value) {
    if (value == null) {
      return '';
    }

    if (_timestampKeys.contains(key) && value is int && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value).toString();
    }

    if (value is bool) {
      return value ? 'true' : 'false';
    }

    if (value is num) {
      return value.toString();
    }

    if (value is List || value is Map) {
      return jsonEncode(value);
    }

    return value.toString();
  }

  DataRow _buildDataRow(Map<String, dynamic> row) {
    return DataRow(
      cells: _columns
          .map(
            (column) => DataCell(
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: column == 'filePath' ? 420 : 220,
                ),
                child: SelectableText(
                  _formatCellValue(column, row[column]),
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  bool _canGoToPreviousPage() => _currentOffset > 0;

  bool _canGoToNextPage() =>
      _totalRows > 0 && _currentOffset + _resolveRowsPerPage() < _totalRows;

  int _currentPageNumber() {
    if (_totalRows == 0) {
      return 0;
    }
    return (_currentOffset ~/ _resolveRowsPerPage()) + 1;
  }

  int _totalPages() {
    if (_totalRows == 0) {
      return 0;
    }
    return (_totalRows / _resolveRowsPerPage()).ceil();
  }

  Future<void> _showJsonPreviewDialog(BuildContext context) async {
    final mediaQuery = MediaQuery.of(context);
    final jsonText = _encodeJson(await _loadAllRows());
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: this.context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${widget.title} JSON'),
        content: SizedBox(
          width: mediaQuery.size.width * 0.75,
          height: mediaQuery.size.height * 0.65,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
