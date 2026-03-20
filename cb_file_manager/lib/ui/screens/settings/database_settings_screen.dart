import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/utils/base_screen.dart';
import 'package:cb_file_manager/config/translation_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

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
  bool _isCloudSyncEnabled = false;
  bool _isLoading = true;
  bool _isSyncing = false;
// Add this line

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

      // Load settings
      _isCloudSyncEnabled = _databaseManager.isCloudSyncEnabled();

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

  // ignore: unused_element
  Future<void> _toggleDatabaseEnabled(bool value) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _preferences.setUsingDatabaseStorage(value);

      if (value && !_isUsingDatabase) {
        // Switch from JSON to Database - migrate the data
        final migratedCount = await TagManager.migrateFromJsonToDatabase();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Migrated $migratedCount files to SQLite database')),
          );
        }
      }

      _isUsingDatabase = value;

      // Reload statistics
      await _loadStatistics();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error toggling Database: $e');

      // Revert the change
      await _preferences.setUsingDatabaseStorage(!value);
      _isUsingDatabase = !value;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );

        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleCloudSyncEnabled(bool value) async {
    setState(() {
      _isLoading = true;
    });

    try {
      _databaseManager.setCloudSyncEnabled(value);
      await _preferences.setCloudSyncEnabled(value);
      _isCloudSyncEnabled = value;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error toggling cloud sync: $e');

      // Revert the change
      _databaseManager.setCloudSyncEnabled(!value);
      await _preferences.setCloudSyncEnabled(!value);
      _isCloudSyncEnabled = !value;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );

        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _syncToCloud() async {
    if (!_isCloudSyncEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud sync is not enabled')),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final success = await _databaseManager.syncToCloud();

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data synced to cloud successfully')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error syncing to cloud')),
          );
        }

        setState(() {
          _isSyncing = false;
        });
      }
    } catch (e) {
      debugPrint('Error syncing to cloud: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );

        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _syncFromCloud() async {
    if (!_isCloudSyncEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud sync is not enabled')),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final success = await _databaseManager.syncFromCloud();

      if (success) {
        // Reload statistics
        await _loadStatistics();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Data synced from cloud successfully')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error syncing from cloud')),
          );
        }
      }

      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    } catch (e) {
      debugPrint('Error syncing from cloud: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );

        setState(() {
          _isSyncing = false;
        });
      }
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
                _buildCloudSyncSection(),
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

  Widget _buildCloudSyncSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.cloudArrowUp, size: 24),
                const SizedBox(width: 16),
                Text(
                  context.tr.cloudSync,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: Text(context.tr.enableCloudSync),
            subtitle: Text(context.tr.cloudSyncDescription),
            value: _isCloudSyncEnabled,
            onChanged: _isUsingDatabase ? _toggleCloudSyncEnabled : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _isUsingDatabase
                  ? (_isCloudSyncEnabled
                      ? context.tr.cloudSyncEnabled
                      : context.tr.cloudSyncDisabled)
                  : context.tr.enableDatabaseForCloud,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(PhosphorIconsLight.cloudArrowUp),
                  label: Text(context.tr.syncToCloud),
                  onPressed:
                      _isCloudSyncEnabled && !_isSyncing ? _syncToCloud : null,
                ),
                ElevatedButton.icon(
                  icon: const Icon(PhosphorIconsLight.cloudArrowDown),
                  label: Text(context.tr.syncFromCloud),
                  onPressed: _isCloudSyncEnabled && !_isSyncing
                      ? _syncFromCloud
                      : null,
                ),
              ],
            ),
          ),
          _isSyncing
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : const SizedBox(height: 8),
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
                  context.tr.importExportDatabase,
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
              context.tr.backupRestoreDescription,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            title: Text(context.tr.exportDatabase),
            subtitle: Text(context.tr.exportDescription),
            leading: const Icon(PhosphorIconsLight.uploadSimple),
            onTap: () async {
              try {
                // Ask the user to choose where to save the file
                String? saveLocation = await FilePicker.platform.saveFile(
                  dialogTitle: context.tr.saveDatabaseExport,
                  fileName:
                      'cb_file_hub_db_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json',
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );

                if (saveLocation != null) {
                  final filePath = await _databaseManager.exportDatabase(
                      customPath: saveLocation);
                  if (filePath != null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr.exportSuccess + filePath),
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
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr.errorExporting + e.toString()),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              }
            },
          ),
          ListTile(
            title: Text(context.tr.importDatabase),
            subtitle: Text(context.tr.importDescription),
            leading: const Icon(PhosphorIconsLight.downloadSimple),
            onTap: () async {
              try {
                // Open file picker to select the database export file
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );

                if (result != null && result.files.single.path != null) {
                  final filePath = result.files.single.path!;

                  // Show loading indicator
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (dialogContext) => const AlertDialog(
                      content: Row(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(width: 20),
                          Text('Importing database...'),
                        ],
                      ),
                    ),
                  );

                  // Use skipFileExistenceCheck: true to allow importing tags for files
                  // that don't exist yet (e.g., network drives)
                  final success = await _databaseManager.importDatabase(
                    filePath,
                    skipFileExistenceCheck: true,
                  );

                  // Close loading dialog
                  if (mounted) {
                    Navigator.of(context).pop();
                  }

                  if (success) {
                    // Clear TagManager cache after successful import to ensure UI refreshes
                    // This fixes the issue where background shows empty after import
                    try {
                      TagManager.clearCache();
                      debugPrint(
                          'DatabaseSettingsScreen: Cleared TagManager cache after import');
                    } catch (e) {
                      debugPrint(
                          'DatabaseSettingsScreen: Error clearing cache: $e');
                    }

                    // Reload statistics after import
                    await _loadStatistics();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr.importSuccess),
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
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr.importCancelled),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr.errorImporting + e.toString()),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _showRawDataDialog(String title, String type) async {
    showDialog(
      context: context,
      builder: (context) => _RawDataDialog(
        title: title,
        type: type,
        databaseManager: _databaseManager,
      ),
    );
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
                    final data = await _loadAllRows();
                    await Clipboard.setData(
                      ClipboardData(text: _encodeJson(data)),
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('JSON copied to clipboard')),
                    );
                  },
            tooltip: 'Copy JSON',
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
            tooltip: 'View JSON',
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
            DropdownButton<int>(
              value: effectiveRowsPerPage,
              onChanged: _isPageLoading
                  ? null
                  : (value) async {
                      if (value == null) return;
                      setState(() {
                        _rowsPerPage = value;
                      });
                      await _loadPage(offset: 0);
                    },
              items: _availableRowsPerPage()
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value'),
                    ),
                  )
                  .toList(),
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
              tooltip: 'First page',
            ),
            IconButton(
              onPressed: _canGoToPreviousPage() && !_isPageLoading
                  ? () => _loadPage(
                      offset:
                          math.max(0, _currentOffset - effectiveRowsPerPage))
                  : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous page',
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
