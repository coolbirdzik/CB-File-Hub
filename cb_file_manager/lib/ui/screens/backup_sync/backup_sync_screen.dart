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

class _BackupSyncScreenState extends State<BackupSyncScreen> {
  final _preferences = UserPreferences.instance;
  final _registry = CloudBackupRegistry.instance;
  final _cloudBackups = CloudBackupService();

  bool _busy = false;
  String? _busyMessage;

  /// Either a provider id or [CloudBackupRegistry.localFolderId].
  String _targetId = CloudBackupRegistry.localFolderId;
  CloudAccount? _account;
  bool _loadingAccount = false;

  CloudBackupProvider? get _provider => _registry.byId(_targetId);

  @override
  void initState() {
    super.initState();
    _loadSelectedTarget();
  }

  Future<void> _loadSelectedTarget() async {
    final saved = await _registry.selectedProviderId();
    if (!mounted || saved == null) return;
    setState(() => _targetId = saved);
    if (_registry.byId(saved) != null) await _refreshAccount();
  }

  Future<void> _refreshAccount() async {
    final provider = _provider;
    if (provider == null) {
      setState(() => _account = null);
      return;
    }
    setState(() => _loadingAccount = true);
    final account = await provider.currentAccount();
    if (!mounted) return;
    setState(() {
      _account = account;
      _loadingAccount = false;
    });
  }

  Future<void> _selectTarget(String id) async {
    setState(() {
      _targetId = id;
      _account = null;
    });
    await _registry.setSelectedProviderId(id);
    await _refreshAccount();
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

  Future<void> _connect() async {
    final provider = _provider;
    if (provider == null) return;
    final tr = context.tr;
    _show(tr.openingBrowserToSignIn);
    await _run(() async {
      final account = await provider.connect();
      if (!mounted) return;
      setState(() => _account = account);
      _show(tr.connectedAsAccount(account.label));
    });
  }

  Future<void> _disconnect() async {
    final provider = _provider;
    if (provider == null) return;
    await provider.disconnect();
    if (!mounted) return;
    setState(() => _account = null);
  }

  Future<void> _uploadToCloud() async {
    final provider = _provider;
    final tr = context.tr;
    if (provider == null) return;
    if (_account == null) {
      _show(tr.connectCloudFirst);
      return;
    }
    final parts = await _chooseParts(importing: false);
    if (parts == null) return;
    await _run(message: tr.uploadingBackup, () async {
      await _cloudBackups.upload(
        provider: provider,
        includeSettings: parts.contains('settings'),
        includeTags: parts.contains('tags'),
      );
      _show(tr.backupUploadedTo(provider.displayName));
    });
  }

  Future<void> _restoreFromCloud() async {
    final provider = _provider;
    final tr = context.tr;
    if (provider == null) return;
    if (_account == null) {
      _show(tr.connectCloudFirst);
      return;
    }

    List<CloudBackupFile> backups = const [];
    await _run(message: tr.loading, () async {
      backups = await provider.listBackups();
    });
    if (!mounted || backups.isEmpty) {
      if (mounted && backups.isEmpty) _show(tr.noCloudBackupsYet);
      return;
    }

    final chosen = await _pickRemoteBackup(provider, backups);
    if (chosen == null || !mounted) return;

    final parts = await _chooseParts(importing: true);
    if (parts == null) return;
    await _run(message: tr.downloadingBackup, () async {
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
    });
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
      parts.add(
        DateFormat('yyyy-MM-dd HH:mm').format(backup.modified!.toLocal()),
      );
    }
    if (backup.size != null) {
      parts.add(FormatUtils.formatFileSize(backup.size!));
    }
    return parts.join(' · ');
  }

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
            onTap: _busy ? null : _exportZip,
          ),
          ListTile(
            leading: const Icon(PhosphorIconsLight.downloadSimple),
            title: Text(context.tr.importBackupZip),
            onTap: _busy ? null : _importZip,
          ),
        ],
      ),
    );
  }

  Widget _buildCloudCard(BuildContext context) {
    final tr = context.tr;
    final provider = _provider;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(PhosphorIconsLight.cloudArrowUp),
            title: Text(tr.cloudSync),
            subtitle: Text(tr.cloudSyncDescription),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _registry.providers)
                  _buildTargetChip(
                    context,
                    id: option.id,
                    label: option.displayName,
                    icon: option.icon,
                    // A drive without a compiled-in client id cannot sign in.
                    enabled: option.isConfigured,
                  ),
                _buildTargetChip(
                  context,
                  id: CloudBackupRegistry.localFolderId,
                  label: tr.localSyncFolder,
                  icon: PhosphorIconsLight.folder,
                  enabled: true,
                ),
              ],
            ),
          ),
          if (provider == null)
            ..._buildLocalFolderActions(context, tr)
          else
            ..._buildProviderActions(context, tr, provider),
        ],
      ),
    );
  }

  Widget _buildTargetChip(
    BuildContext context, {
    required String id,
    required String label,
    required IconData icon,
    required bool enabled,
  }) {
    final selected = _targetId == id;
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: selected,
      onSelected: _busy
          ? null
          : (_) => enabled
                ? _selectTarget(id)
                : _show(context.tr.cloudProviderNotConfigured),
      // Greyed out rather than hidden, so it is clear the drive exists but the
      // build lacks its OAuth client id.
      labelStyle: enabled
          ? null
          : TextStyle(color: Theme.of(context).disabledColor),
    );
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
        onTap: _busy ? null : () => _syncLocalFolder(upload: true),
      ),
      ListTile(
        leading: const Icon(PhosphorIconsLight.cloudArrowDown),
        title: Text(tr.syncFromCloud),
        onTap: _busy ? null : () => _syncLocalFolder(upload: false),
      ),
    ];
  }

  List<Widget> _buildProviderActions(
    BuildContext context,
    AppLocalizations tr,
    CloudBackupProvider provider,
  ) {
    final connected = _account != null;
    return [
      ListTile(
        leading: Icon(provider.icon),
        title: Text(
          connected ? tr.connectedAsAccount(_account!.label) : tr.notConnected,
        ),
        subtitle: Text(tr.cloudBackupsStoredIn(provider.remoteFolderName)),
        trailing: _loadingAccount
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: _busy ? null : (connected ? _disconnect : _connect),
                child: Text(connected ? tr.disconnect : tr.connect),
              ),
      ),
      ListTile(
        leading: const Icon(PhosphorIconsLight.cloudArrowUp),
        title: Text(tr.syncToCloud),
        enabled: connected && !_busy,
        onTap: _uploadToCloud,
      ),
      ListTile(
        leading: const Icon(PhosphorIconsLight.cloudArrowDown),
        title: Text(tr.syncFromCloud),
        enabled: connected && !_busy,
        onTap: _restoreFromCloud,
      ),
    ];
  }
}
