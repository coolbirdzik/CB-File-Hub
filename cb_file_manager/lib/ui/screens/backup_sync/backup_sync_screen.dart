import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/config/translation_helper.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/services/backup/backup_archive_service.dart';
import 'package:cb_file_manager/services/backup/cloud/cloud_backup_provider.dart';
import 'package:cb_file_manager/services/backup/cloud/cloud_backup_registry.dart';
import 'package:cb_file_manager/services/backup/cloud_backup_service.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

class BackupSyncScreen extends StatefulWidget {
  const BackupSyncScreen({super.key});

  @override
  State<BackupSyncScreen> createState() => _BackupSyncScreenState();
}

/// What a provider row is doing right now; absent from the map when idle.
enum _CloudActivity { connecting, uploading, listing, downloading }

class _BackupSyncScreenState extends State<BackupSyncScreen> {
  final _preferences = UserPreferences.instance;
  final _registry = CloudBackupRegistry.instance;
  final _cloudBackups = CloudBackupService();

  /// Set by archive and local folder operations, which block the whole screen.
  bool _busy = false;
  String? _busyMessage;

  final Map<String, CloudAccount?> _accounts = {};
  final Set<String> _loadingAccounts = {};
  final Map<String, _CloudActivity> _activity = {};
  final Map<String, CloudSyncRecord> _lastSync = {};

  /// Nothing is running anywhere, so an action that changes local data is safe.
  bool get _idle => !_busy && _activity.isEmpty;

  List<CloudBackupProvider> get _connectedProviders => _registry
      .configuredProviders
      .where((provider) => _accounts[provider.id] != null)
      .toList();

  @override
  void initState() {
    super.initState();
    for (final provider in _registry.configuredProviders) {
      _loadingAccounts.add(provider.id);
      _loadProvider(provider);
    }
  }

  Future<void> _loadProvider(CloudBackupProvider provider) async {
    CloudAccount? account;
    try {
      account = await provider.currentAccount();
    } catch (_) {
      account = null;
    }
    final record = await _registry.lastSync(provider.id);
    if (!mounted) return;
    setState(() {
      _accounts[provider.id] = account;
      if (record != null) _lastSync[provider.id] = record;
      _loadingAccounts.remove(provider.id);
    });
  }

  void _setActivity(CloudBackupProvider provider, _CloudActivity? activity) {
    if (!mounted) return;
    setState(() {
      if (activity == null) {
        _activity.remove(provider.id);
      } else {
        _activity[provider.id] = activity;
      }
    });
  }

  Future<Set<String>?> _chooseParts({required bool importing}) async {
    final selected = <String>{'settings', 'tags'};
    return showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            importing ? context.tr.importBackupZip : context.tr.exportBackupZip,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: selected.contains('settings'),
                title: Text(context.tr.backupSettingsPart),
                onChanged: (value) => setState(
                  () => value == true
                      ? selected.add('settings')
                      : selected.remove('settings'),
                ),
              ),
              CheckboxListTile(
                value: selected.contains('tags'),
                title: Text(context.tr.backupTagsPart),
                onChanged: (value) => setState(
                  () => value == true
                      ? selected.add('tags')
                      : selected.remove('tags'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr.cancel),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, selected),
              child: Text(context.tr.continueText),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportZip() async {
    final tr = context.tr;
    final parts = await _chooseParts(importing: false);
    if (parts == null) return;
    final saved = await FilePicker.saveFile(
      dialogTitle: tr.exportBackupZip,
      fileName: CloudBackupService.archiveName(),
      bytes: Uint8List(0),
      type: FileType.custom,
      allowedExtensions: ['zip'],
      mimeType: 'application/zip',
    );
    if (saved == null) return;
    final path = saved.isScheme('file') ? saved.toFilePath() : saved.toString();
    await _run(() async {
      await BackupArchiveService().exportZip(
        outputPath: path,
        includeSettings: parts.contains('settings'),
        includeTags: parts.contains('tags'),
      );
      _show(tr.exportSuccess + path);
    });
  }

  Future<void> _importZip() async {
    final tr = context.tr;
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked?.path == null) return;
    final parts = await _chooseParts(importing: true);
    if (parts == null) return;
    await _run(() async {
      final result = await BackupArchiveService().importZip(
        archivePath: picked!.path!,
        importSettings: parts.contains('settings'),
        importTags: parts.contains('tags'),
        restoreSettings: _preferences.restoreAllFrom,
      );
      TagManager.clearCache();
      _show(
        '${tr.importSuccess}: ${result?['settingsCount'] ?? 0} '
        '${tr.backupSettingsPart}',
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Cloud drives (Google Drive / Dropbox / OneDrive)
  // ---------------------------------------------------------------------------

  Future<void> _connect(CloudBackupProvider provider) async {
    final tr = context.tr;
    _setActivity(provider, _CloudActivity.connecting);
    try {
      final account = await provider.connect();
      if (!mounted) return;
      setState(() => _accounts[provider.id] = account);
      _show(tr.connectedAsAccount(account.label));
    } catch (error) {
      _show('$error');
    } finally {
      _setActivity(provider, null);
    }
  }

  Future<void> _disconnect(CloudBackupProvider provider) async {
    await provider.disconnect();
    if (!mounted) return;
    setState(() => _accounts[provider.id] = null);
  }

  /// Uploads one archive to every provider in [providers] at the same time.
  Future<void> _backUp(List<CloudBackupProvider> providers) async {
    final tr = context.tr;
    if (providers.isEmpty) {
      _show(tr.connectCloudFirst);
      return;
    }
    final parts = await _chooseParts(importing: false);
    if (parts == null || !mounted) return;
    setState(() {
      for (final provider in providers) {
        _activity[provider.id] = _CloudActivity.uploading;
      }
    });

    final List<CloudUploadResult> results;
    try {
      results = await _cloudBackups.uploadToMany(
        providers: providers,
        includeSettings: parts.contains('settings'),
        includeTags: parts.contains('tags'),
        onDone: _recordUpload,
      );
    } catch (error) {
      // The archive itself could not be built, so no drive was touched.
      if (!mounted) return;
      setState(() {
        for (final provider in providers) {
          _activity.remove(provider.id);
        }
      });
      _show('$error');
      return;
    }

    if (results.length == 1) {
      final result = results.single;
      _show(
        result.succeeded
            ? tr.backupUploadedTo(result.provider.displayName)
            : '${result.error}',
      );
    } else {
      _show(
        tr.syncAllResult(
          results.where((result) => result.succeeded).length,
          results.length,
        ),
      );
    }
  }

  void _recordUpload(CloudUploadResult result) {
    final id = result.provider.id;
    final previous = _lastSync[id] ?? const CloudSyncRecord();
    final now = DateTime.now();
    final record = result.succeeded
        ? previous.succeeded(now, result.file?.name)
        : previous.failed(now, '${result.error}');
    _registry.saveLastSync(id, record);
    if (!mounted) return;
    setState(() {
      _lastSync[id] = record;
      _activity.remove(id);
    });
  }

  Future<void> _restoreFromCloud(CloudBackupProvider provider) async {
    final tr = context.tr;
    _setActivity(provider, _CloudActivity.listing);
    List<CloudBackupFile> backups;
    try {
      backups = await provider.listBackups();
    } catch (error) {
      _show('$error');
      return;
    } finally {
      _setActivity(provider, null);
    }
    if (!mounted) return;
    if (backups.isEmpty) {
      _show(tr.noCloudBackupsYet);
      return;
    }

    final chosen = await _pickRemoteBackup(provider, backups);
    if (chosen == null || !mounted) return;

    final parts = await _chooseParts(importing: true);
    if (parts == null) return;
    _setActivity(provider, _CloudActivity.downloading);
    try {
      final result = await _cloudBackups.restore(
        provider: provider,
        remote: chosen,
        importSettings: parts.contains('settings'),
        importTags: parts.contains('tags'),
      );
      TagManager.clearCache();
      _show(
        '${tr.importSuccess}: ${result?['settingsCount'] ?? 0} '
        '${tr.backupSettingsPart}',
      );
    } on CloudBackupException catch (error) {
      _show(error.message);
    } catch (error) {
      _show('${tr.errorImporting}$error');
    } finally {
      _setActivity(provider, null);
    }
  }

  Future<CloudBackupFile?> _pickRemoteBackup(
    CloudBackupProvider provider,
    List<CloudBackupFile> backups,
  ) {
    final entries = List<CloudBackupFile>.from(backups);
    return showDialog<CloudBackupFile>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr.chooseBackupToRestore),
          content: SizedBox(
            width: 420,
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.tr.noCloudBackupsYet),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return ListTile(
                        leading: const Icon(PhosphorIconsLight.fileZip),
                        title: Text(entry.name),
                        subtitle: Text(_describeBackup(context, entry)),
                        onTap: () => Navigator.pop(dialogContext, entry),
                        trailing: IconButton(
                          icon: const Icon(PhosphorIconsLight.trash),
                          tooltip: context.tr.delete,
                          onPressed: () async {
                            final confirmed = await _confirmDelete(context);
                            if (!confirmed) return;
                            try {
                              await provider.delete(entry);
                              setDialogState(() => entries.removeAt(index));
                            } on CloudBackupException catch (error) {
                              _show(error.message);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr.cancel),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final tr = context.tr;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(tr.deleteCloudBackupConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr.delete),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  String _describeBackup(BuildContext context, CloudBackupFile backup) {
    final parts = <String>[];
    if (backup.modified != null) {
      parts.add(_formatTime(backup.modified!));
    }
    if (backup.size != null) {
      parts.add(FormatUtils.formatFileSize(backup.size!));
    }
    return parts.join(' · ');
  }

  String _formatTime(DateTime time) =>
      DateFormat('yyyy-MM-dd HH:mm').format(time.toLocal());

  // ---------------------------------------------------------------------------
  // Local folder mirrored by a desktop sync client
  // ---------------------------------------------------------------------------

  Future<void> _syncLocalFolder({required bool upload}) async {
    final tr = context.tr;
    final parts = await _chooseParts(importing: !upload);
    if (parts == null) return;
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: tr.chooseCloudSyncFolder,
    );
    if (directory == null) return;
    await _run(() async {
      final cloudPath =
          '$directory${Platform.pathSeparator}cb_file_hub_cloud_backup.zip';
      if (upload) {
        await BackupArchiveService().exportZip(
          outputPath: cloudPath,
          includeSettings: parts.contains('settings'),
          includeTags: parts.contains('tags'),
        );
      } else {
        final file = File(cloudPath);
        if (!await file.exists()) {
          throw StateError(tr.cloudBackupNotFound);
        }
        await BackupArchiveService().importZip(
          archivePath: cloudPath,
          importSettings: parts.contains('settings'),
          importTags: parts.contains('tags'),
          restoreSettings: _preferences.restoreAllFrom,
        );
        TagManager.clearCache();
      }
      _show(upload ? tr.syncToCloudSuccess : tr.syncFromCloudSuccess);
    });
  }

  Future<void> _run(Future<void> Function() action, {String? message}) async {
    final tr = context.tr;
    setState(() {
      _busy = true;
      _busyMessage = message;
    });
    try {
      await action();
    } on CloudBackupException catch (error) {
      if (mounted) _show(error.message);
    } catch (error) {
      if (mounted) _show('${tr.errorImporting}$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Returns to Settings inside the same tab when this screen is hosted as the
  /// `#backup-sync` system path; falls back to popping when pushed as a route.
  void _handleBack() {
    TabManagerBloc? tabBloc;
    try {
      tabBloc = context.read<TabManagerBloc>();
    } catch (_) {
      tabBloc = null;
    }

    final activeTab = tabBloc?.state.activeTab;
    if (tabBloc != null &&
        activeTab != null &&
        isBackupSyncPath(activeTab.path)) {
      tabBloc.add(UpdateTabPath(activeTab.id, kSettingsPath));
      tabBloc.add(UpdateTabName(activeTab.id, context.tr.settings));
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header bar giống settings screen để nằm gọn trong tab
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(PhosphorIconsLight.arrowLeft),
                  onPressed: _handleBack,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr.backupAndSync,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildArchiveCard(context),
                const SizedBox(height: 16),
                _buildCloudCard(context),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        if (_busyMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _busyMessage!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(PhosphorIconsLight.archive),
            title: Text(context.tr.backupAndSync),
            subtitle: Text(context.tr.backupRestoreHint),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsLight.uploadSimple),
            title: Text(context.tr.exportBackupZip),
            onTap: _idle ? _exportZip : null,
          ),
          ListTile(
            leading: const Icon(PhosphorIconsLight.downloadSimple),
            title: Text(context.tr.importBackupZip),
            onTap: _idle ? _importZip : null,
          ),
        ],
      ),
    );
  }

  Widget _buildCloudCard(BuildContext context) {
    final tr = context.tr;
    final available = _registry.configuredProviders;
    final connected = _connectedProviders;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(PhosphorIconsLight.cloudArrowUp),
            title: Text(tr.cloudSync),
            subtitle: Text(
              available.isEmpty
                  ? tr.cloudSyncDescription
                  : '${tr.cloudSyncDescription}\n'
                        '${tr.cloudConnectedCount(connected.length, available.length)}',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: FilledButton.icon(
              icon: const Icon(PhosphorIconsLight.cloudArrowUp),
              label: Text(tr.syncAllClouds),
              onPressed: _idle && connected.isNotEmpty
                  ? () => _backUp(connected)
                  : null,
            ),
          ),
          for (final provider in _registry.providers) ...[
            const Divider(height: 1),
            _buildProviderRow(context, provider),
          ],
          const Divider(height: 1),
          ..._buildLocalFolderActions(context, tr),
        ],
      ),
    );
  }

  Widget _buildProviderRow(BuildContext context, CloudBackupProvider provider) {
    final tr = context.tr;
    final theme = Theme.of(context);
    final account = _accounts[provider.id];
    final activity = _activity[provider.id];
    final loading = _loadingAccounts.contains(provider.id);
    final rowIdle = !_busy && activity == null && !loading;
    // Every sign-in listens on the same loopback ports, so only one at a time.
    final signingIn = _activity.containsValue(_CloudActivity.connecting);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(provider.icon, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        provider.displayName,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusBadge(context, provider),
                  ],
                ),
                if (account != null)
                  Text(
                    account.label,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                ..._buildStatusLines(context, provider),
                if (activity != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                if (provider.isConfigured && !loading) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: account != null
                        ? [
                            FilledButton.tonalIcon(
                              icon: const Icon(
                                PhosphorIconsLight.cloudArrowUp,
                                size: 18,
                              ),
                              label: Text(tr.backUpNow),
                              onPressed: rowIdle
                                  ? () => _backUp([provider])
                                  : null,
                            ),
                            // Restoring rewrites local data, so it waits for
                            // every other drive to finish.
                            OutlinedButton.icon(
                              icon: const Icon(
                                PhosphorIconsLight.cloudArrowDown,
                                size: 18,
                              ),
                              label: Text(tr.restoreBackup),
                              onPressed: _idle
                                  ? () => _restoreFromCloud(provider)
                                  : null,
                            ),
                            TextButton(
                              onPressed: rowIdle
                                  ? () => _disconnect(provider)
                                  : null,
                              child: Text(tr.disconnect),
                            ),
                          ]
                        : [
                            FilledButton.tonal(
                              onPressed: rowIdle && !signingIn
                                  ? () => _connect(provider)
                                  : null,
                              child: Text(tr.connect),
                            ),
                          ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, CloudBackupProvider provider) {
    final tr = context.tr;
    final theme = Theme.of(context);
    final loading = _loadingAccounts.contains(provider.id);
    final activity = _activity[provider.id];

    final String label;
    final Color color;
    if (!provider.isConfigured) {
      label = tr.cloudStatusUnavailable;
      color = theme.disabledColor;
    } else if (loading) {
      label = tr.loading;
      color = theme.colorScheme.outline;
    } else if (_accounts[provider.id] == null) {
      label = tr.notConnected;
      color = activity == null
          ? theme.colorScheme.outline
          : theme.colorScheme.primary;
    } else if (activity == null &&
        (_lastSync[provider.id]?.lastAttemptFailed ?? false)) {
      label = tr.cloudStatusFailed;
      color = theme.colorScheme.error;
    } else {
      label = tr.cloudStatusConnected;
      color = activity == null ? Colors.green : theme.colorScheme.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading || activity != null)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  /// What the row is doing now, or else how its last backup went.
  List<Widget> _buildStatusLines(
    BuildContext context,
    CloudBackupProvider provider,
  ) {
    final tr = context.tr;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget line(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color ?? muted?.color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: muted?.copyWith(color: color),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (!provider.isConfigured) {
      return [line(PhosphorIconsLight.info, tr.cloudProviderNotConfigured)];
    }

    final primary = theme.colorScheme.primary;
    switch (_activity[provider.id]) {
      case _CloudActivity.connecting:
        return [
          line(PhosphorIconsLight.globe, tr.waitingForSignIn, color: primary),
        ];
      case _CloudActivity.uploading:
        return [
          line(
            PhosphorIconsLight.cloudArrowUp,
            tr.uploadingBackup,
            color: primary,
          ),
        ];
      case _CloudActivity.listing:
        return [
          line(PhosphorIconsLight.listBullets, tr.loading, color: primary),
        ];
      case _CloudActivity.downloading:
        return [
          line(
            PhosphorIconsLight.cloudArrowDown,
            tr.downloadingBackup,
            color: primary,
          ),
        ];
      case null:
        break;
    }
    if (_loadingAccounts.contains(provider.id)) return const [];

    final record = _lastSync[provider.id];
    final connected = _accounts[provider.id] != null;
    return [
      if (record != null && record.lastAttemptFailed)
        line(
          PhosphorIconsLight.warningCircle,
          tr.lastBackupFailedAt(_formatTime(record.failedAt!), record.error!),
          color: theme.colorScheme.error,
        ),
      if (record?.succeededAt != null)
        line(
          PhosphorIconsLight.checkCircle,
          tr.lastBackupAt(_formatTime(record!.succeededAt!)),
          color: record.lastAttemptFailed ? null : Colors.green,
        )
      else if (connected)
        line(PhosphorIconsLight.clock, tr.neverBackedUpHere),
      if (connected)
        line(
          PhosphorIconsLight.folder,
          tr.cloudBackupsStoredIn(provider.remoteFolderName),
        ),
    ];
  }

  List<Widget> _buildLocalFolderActions(
    BuildContext context,
    AppLocalizations tr,
  ) {
    return [
      ListTile(
        leading: const Icon(PhosphorIconsLight.folder),
        title: Text(tr.localSyncFolder),
        subtitle: Text(tr.localSyncFolderDescription),
      ),
      ListTile(
        leading: const Icon(PhosphorIconsLight.cloudArrowUp),
        title: Text(tr.syncToCloud),
        onTap: _idle ? () => _syncLocalFolder(upload: true) : null,
      ),
      ListTile(
        leading: const Icon(PhosphorIconsLight.cloudArrowDown),
        title: Text(tr.syncFromCloud),
        onTap: _idle ? () => _syncLocalFolder(upload: false) : null,
      ),
    ];
  }
}
