import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../models/local_ai/local_ai_advisor_model.dart';
import '../../../services/local_ai/local_ai_advisor_service.dart';
import '../../../services/local_ai/local_model_downloads.dart';
import '../../tab_manager/core/tab_main_screen.dart';
import 'package:cb_file_manager/config/translation_helper.dart';
import 'settings_navigation.dart';

/// Settings section for the Local AI Advisor.
///
/// Allows users to configure their Hugging Face token, browse models,
/// install/uninstall models, and select the active model for cleanup suggestions.
class LocalAiAdvisorSettingsSection extends StatefulWidget {
  /// Section card builder from the parent settings screen.
  final Widget Function({
    required String title,
    required IconData icon,
    required List<Widget> children,
  })
  buildSectionCard;

  /// Compact setting tile builder from the parent settings screen.
  final Widget Function({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
    VoidCallback? onTap,
  })
  buildCompactSettingTile;

  const LocalAiAdvisorSettingsSection({
    super.key,
    required this.buildSectionCard,
    required this.buildCompactSettingTile,
  });

  @override
  State<LocalAiAdvisorSettingsSection> createState() =>
      _LocalAiAdvisorSettingsSectionState();
}

class _LocalAiAdvisorSettingsSectionState
    extends State<LocalAiAdvisorSettingsSection> {
  late LocalAiAdvisorService _service;
  late LocalModelDownloads _downloads;
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _isLoading = true;
  String? _hfToken;
  List<InstalledLocalModel> _installed = [];
  InstalledLocalModel? _selectedModel;
  int _maxTokens = LocalAiAdvisorService.defaultContextTokens;
  String _modelStorageDir = '';
  bool _hasCustomModelStorage = false;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final getIt = GetIt.instance;
    _service = getIt<LocalAiAdvisorService>();
    _downloads = getIt.isRegistered<LocalModelDownloads>()
        ? getIt<LocalModelDownloads>()
        : LocalModelDownloads(_service);
    _downloads.addListener(_onDownloadsChanged);
    _subscriptions
      ..add(_service.onInstalledModelsChanged.listen((_) => _loadState()))
      ..add(_downloads.onCompleted.listen(_onModelInstalled));
    pendingLocalModelInstaller.addListener(_openPendingInstaller);
    await _loadState();
    _openPendingInstaller();
  }

  @override
  void dispose() {
    pendingLocalModelInstaller.removeListener(_openPendingInstaller);
    _downloads.removeListener(_onDownloadsChanged);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
  }

  void _onModelInstalled(HuggingFaceModelEntry entry) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.localModelReady(entry.displayName),
        ),
      ),
    );
  }

  /// Opens the installer when CB Agent's setup guide sent the user here.
  void _openPendingInstaller() {
    if (!pendingLocalModelInstaller.value || _isLoading || !mounted) return;
    pendingLocalModelInstaller.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showModelBrowser();
    });
  }

  Future<void> _loadState() async {
    final token = await _service.getHuggingFaceToken();
    final installed = _service.getInstalledModels();
    final selected = _service.getSelectedModel();
    final maxTokens = _service.getMaxContextTokens();
    final storageDir = await _service.getModelStorageDirectory();
    final hasCustomStorage = _service.getCustomModelStorageDirectory() != null;

    if (mounted) {
      setState(() {
        _hfToken = token;
        _installed = installed;
        _selectedModel = selected;
        _maxTokens = maxTokens;
        _modelStorageDir = storageDir;
        _hasCustomModelStorage = hasCustomStorage;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return widget.buildSectionCard(
      title: l.localAiAdvisor,
      icon: PhosphorIconsLight.brain,
      children: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          // HF Token section
          _buildTokenSection(context, l),
          const Divider(height: 1),

          // Installed models section
          _buildInstalledModelsSection(context, l),
          const Divider(height: 1),

          // Download location section
          _buildModelStorageSection(context, l),
          const Divider(height: 1),

          // Context window section
          _buildContextWindowSection(context, l),
        ],
      ],
    );
  }

  Widget _buildTokenSection(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.huggingFaceToken,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            l.huggingFaceTokenHint,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _hfToken != null
                        ? '${_hfToken!.substring(0, 8)}••••••••'
                        : l.noTokenSet,
                    style: TextStyle(
                      fontSize: 13,
                      color: _hfToken != null
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_hfToken != null)
                IconButton(
                  icon: const Icon(PhosphorIconsLight.x, size: 18),
                  tooltip: l.clearToken,
                  onPressed: _clearToken,
                )
              else
                FilledButton.icon(
                  onPressed: _pasteToken,
                  icon: const Icon(PhosphorIconsLight.clipboardText, size: 16),
                  label: Text(l.pasteToken),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledModelsSection(
    BuildContext context,
    AppLocalizations l,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.installedModels,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('local-ai-install-model'),
                onPressed: _showModelBrowser,
                icon: const Icon(PhosphorIconsLight.downloadSimple, size: 16),
                label: Text(l.installLocalModel),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final download in _downloads.downloads)
            _DownloadTile(
              download: download,
              onCancel: () => _downloads.cancel(download.entry.id),
              onRetry: () => _downloads.start(download.entry),
            ),
          if (_installed.isEmpty && _downloads.downloads.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  l.noModelsInstalled,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ..._installed.map(
              (model) => _buildInstalledModelTile(
                context,
                l,
                model,
                isActive: _selectedModel?.catalogId == model.catalogId,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModelStorageSection(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.localAiModelStorage,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            l.localAiModelStorageHint,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIconsLight.folder,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: _displayPath(_modelStorageDir),
                          child: Text(
                            _displayPath(_modelStorageDir),
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_hasCustomModelStorage)
                IconButton(
                  icon: const Icon(
                    PhosphorIconsLight.arrowCounterClockwise,
                    size: 18,
                  ),
                  tooltip: l.localAiModelStorageReset,
                  onPressed: () => _setModelStorageDirectory(null),
                ),
              FilledButton.icon(
                onPressed: _pickModelStorageDirectory,
                icon: const Icon(PhosphorIconsLight.folderOpen, size: 16),
                label: Text(l.browse),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickModelStorageDirectory() async {
    final l = AppLocalizations.of(context)!;
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: l.localAiModelStorage,
      initialDirectory: Directory(_modelStorageDir).existsSync()
          ? _modelStorageDir
          : null,
    );
    if (dir == null || !mounted) return;
    await _setModelStorageDirectory(dir);
  }

  Future<void> _setModelStorageDirectory(String? path) async {
    try {
      await _service.setModelStorageDirectory(path);
    } on FileSystemException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context)!.localAiModelStorageNotWritable}'
              ': ${e.path ?? path}',
            ),
          ),
        );
      }
      return;
    }

    final toMove = await _service.modelsOutsideStorage();
    if (toMove.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _MoveModelsProgressDialog(service: _service),
      );
    }
    await _loadState();
  }

  Widget _buildContextWindowSection(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    final controller = TextEditingController(text: _maxTokens.toString());
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.localAiContextWindow,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            l.localAiContextWindowHint,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    suffixText: l.localAiTokensSuffix,
                    hintText:
                        '${LocalAiAdvisorService.minContextTokens}–${LocalAiAdvisorService.maxContextTokens}',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ).flat(context, radius: 8),
                  onFieldSubmitted: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      _setMaxTokens(parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {
                  final parsed = int.tryParse(controller.text);
                  if (parsed != null) {
                    _setMaxTokens(parsed);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.localAiInvalidTokenCount)),
                    );
                  }
                },
                icon: const Icon(PhosphorIconsLight.check, size: 16),
                label: Text(l.apply),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _setMaxTokens(int tokens) async {
    await _service.setMaxContextTokens(tokens);
    await _loadState();
  }

  Widget _buildInstalledModelTile(
    BuildContext context,
    AppLocalizations l,
    InstalledLocalModel model, {
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    final modelPath = _displayPath(model.localPath);
    final isRunnable = model.isRunnableArtifact;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: CbDecorations.card(context, radius: 8, selected: isActive),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsLight.brain,
                size: 20,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(model.sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isActive && isRunnable)
                TextButton(
                  onPressed: () => _setActiveModel(model.catalogId),
                  child: Text(l.selectActiveModel),
                ),
              IconButton(
                icon: const Icon(PhosphorIconsLight.trash, size: 18),
                tooltip: l.uninstallModel,
                onPressed: () => _uninstallModel(model.catalogId),
              ),
            ],
          ),
          if (!isRunnable) _buildIncompatibleBanner(context, l, model),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.folder,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    modelPath,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _openModelLocation(modelPath),
                  icon: const Icon(PhosphorIconsLight.folderOpen, size: 14),
                  label: Text(l.openLocation),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncompatibleBanner(
    BuildContext context,
    AppLocalizations l,
    InstalledLocalModel model,
  ) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: CbDecorations.tint(
        context,
        theme.colorScheme.error,
        radius: 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIconsLight.warning,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.localAiIncompatibleArtifact,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 6),
                FilledButton.tonalIcon(
                  onPressed: () => _reinstallCompatibleModel(model),
                  icon: const Icon(
                    PhosphorIconsLight.arrowsClockwise,
                    size: 14,
                  ),
                  label: Text(l.localAiReinstallCompatible),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reinstallCompatibleModel(InstalledLocalModel model) async {
    // Remove the incompatible artifact, then install the current LiteRT-LM recommendation.
    await _service.uninstallModel(model.catalogId);
    if (!mounted) return;
    await _installModel(_service.pinnedModel);
  }

  Future<void> _pasteToken() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final token = data?.text?.trim();

    if (token == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.laNoTokenInClipboard)),
        );
      }
      return;
    }

    await _service.setHuggingFaceToken(token);
    await _loadState();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.tokenSaved)),
      );
    }
  }

  Future<void> _clearToken() async {
    await _service.clearHuggingFaceToken();
    await _loadState();
  }

  Future<void> _setActiveModel(String catalogId) async {
    await _service.setSelectedModel(catalogId);
    await _loadState();
  }

  Future<void> _uninstallModel(String catalogId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.uninstallModel),
        content: Text(context.tr.laRemoveModelConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context)!.uninstallModel),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.uninstallModel(catalogId);
      await _loadState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.modelUninstalled),
          ),
        );
      }
    }
  }

  Future<void> _showModelBrowser() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ModelBrowserDialog(
        service: _service,
        downloads: _downloads,
        installedIds: _installed.map((m) => m.catalogId).toSet(),
      ),
    );
  }

  /// Starts a background download; progress shows under Installed models.
  Future<void> _installModel(HuggingFaceModelEntry entry) async {
    _downloads.start(entry);
  }

  Future<void> _openModelLocation(String filePath) async {
    try {
      // Get parent directory
      final file = File(filePath);
      final directory = file.parent.path;

      // Open directory in app's tab system
      TabMainScreen.openPath(context, directory);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr.laOpenLocationFailed(e.toString())),
          ),
        );
      }
    }
  }

  String _displayPath(String path) {
    if (Platform.isWindows) {
      return path.replaceAll('/', r'\');
    }
    return path.replaceAll(r'\', Platform.pathSeparator);
  }
}

// =============================================================================
// Model browser dialog
// =============================================================================

/// Models to install. Downloads it starts keep running after it closes.
class _ModelBrowserDialog extends StatefulWidget {
  final LocalAiAdvisorService service;
  final LocalModelDownloads downloads;
  final Set<String> installedIds;

  const _ModelBrowserDialog({
    required this.service,
    required this.downloads,
    required this.installedIds,
  });

  @override
  State<_ModelBrowserDialog> createState() => _ModelBrowserDialogState();
}

class _ModelBrowserDialogState extends State<_ModelBrowserDialog> {
  List<HuggingFaceModelEntry>? _catalog;
  late Set<String> _installedIds = widget.installedIds;
  StreamSubscription<HuggingFaceModelEntry>? _completed;

  @override
  void initState() {
    super.initState();
    widget.downloads.addListener(_refresh);
    _completed = widget.downloads.onCompleted.listen((entry) {
      if (mounted) setState(() => _installedIds = {..._installedIds, entry.id});
    });
    widget.service.fetchModelCatalog(forceRefresh: true).then((catalog) {
      if (mounted) setState(() => _catalog = catalog);
    });
  }

  @override
  void dispose() {
    widget.downloads.removeListener(_refresh);
    _completed?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final catalog = _catalog;
    final recommendedId = widget.service.pinnedModel.id;

    return AlertDialog(
      title: Text(l.installLocalModel),
      content: SizedBox(
        width: 500,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  PhosphorIconsLight.info,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.localModelBackgroundHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: catalog == null
                  ? const Center(child: CircularProgressIndicator())
                  : catalog.isEmpty
                  ? Center(child: Text(l.noModelsFound))
                  : ListView.builder(
                      itemCount: catalog.length,
                      itemBuilder: (context, index) {
                        final entry = catalog[index];
                        return _ModelCatalogTile(
                          entry: entry,
                          isRecommended: entry.id == recommendedId,
                          isInstalled: _installedIds.contains(entry.id),
                          download: widget.downloads[entry.id],
                          onInstall: () => widget.downloads.start(entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.close),
        ),
      ],
    );
  }
}

class _ModelCatalogTile extends StatelessWidget {
  final HuggingFaceModelEntry entry;
  final bool isRecommended;
  final bool isInstalled;
  final LocalModelDownload? download;
  final VoidCallback onInstall;

  const _ModelCatalogTile({
    required this.entry,
    required this.isRecommended,
    required this.isInstalled,
    required this.download,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final download = this.download;
    final downloading = download != null && !download.failed;

    final Widget action;
    if (isInstalled) {
      action = _badge(context, l.localModelInstalledBadge);
    } else if (downloading) {
      final progress = download.progress;
      action = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, value: progress),
          ),
          const SizedBox(width: 8),
          Text(
            progress == null
                ? context.tr.laDownloading
                : '${(progress * 100).toInt()}%',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
          ),
        ],
      );
    } else if (!entry.compatible) {
      action = OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(PhosphorIconsLight.warningCircle, size: 14),
        label: Text(context.tr.laRuntimePending),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
        ),
      );
    } else {
      action = FilledButton.tonalIcon(
        key: ValueKey('local-ai-install-${entry.id}'),
        onPressed: onInstall,
        icon: const Icon(PhosphorIconsLight.downloadSimple, size: 14),
        label: Text(download?.failed == true ? l.retry : l.installModel),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              action,
            ],
          ),
          if (entry.description != null) ...[
            const SizedBox(height: 6),
            Text(
              entry.description!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (isRecommended) _badge(context, l.localModelRecommended),
              if (entry.sizeBytes != null)
                _buildChip(context, _formatBytes(entry.sizeBytes!)),
              if (entry.license != null) _buildChip(context, entry.license!),
              if (!entry.compatible)
                _buildChip(context, context.tr.laRequiresGguf),
            ],
          ),
          if (download != null && download.failed) ...[
            const SizedBox(height: 6),
            Text(
              '${context.tr.laInstallFailed}: ${download.error}',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(BuildContext context, String label) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// =============================================================================
// Background download row
// =============================================================================

/// A model downloading in the background, or one whose download failed.
class _DownloadTile extends StatelessWidget {
  final LocalModelDownload download;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  const _DownloadTile({
    required this.download,
    required this.onCancel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final progress = download.progress;
    final failed = download.failed;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: CbDecorations.card(context, radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? PhosphorIconsLight.warningCircle
                    : PhosphorIconsLight.downloadSimple,
                size: 20,
                color: failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  failed
                      ? '${context.tr.laInstallFailed}: ${download.entry.displayName}'
                      : l.localModelDownloading(download.entry.displayName),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (failed) TextButton(onPressed: onRetry, child: Text(l.retry)),
              IconButton(
                icon: const Icon(PhosphorIconsLight.x, size: 18),
                tooltip: failed ? l.dismiss : l.cancel,
                onPressed: onCancel,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (failed)
            Text(
              download.error!,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            )
          else ...[
            LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (progress != null) '${(progress * 100).toInt()}%',
                download.totalBytes > 0
                    ? '${_formatBytes(download.downloadedBytes)} / ${_formatBytes(download.totalBytes)}'
                    : _formatBytes(download.downloadedBytes),
              ].join(' · '),
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}

// =============================================================================
// Move models progress dialog
// =============================================================================

class _MoveModelsProgressDialog extends StatefulWidget {
  final LocalAiAdvisorService service;

  const _MoveModelsProgressDialog({required this.service});

  @override
  State<_MoveModelsProgressDialog> createState() =>
      _MoveModelsProgressDialogState();
}

class _MoveModelsProgressDialogState extends State<_MoveModelsProgressDialog> {
  ModelMoveProgress? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startMove();
  }

  Future<void> _startMove() async {
    try {
      await widget.service.moveInstalledModelsToStorage(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.localAiModelsMoved),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  static String _formatBytes(int bytes) {
    const gb = 1024 * 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;

    if (_error != null) {
      return AlertDialog(
        title: Text(l.localAiMoveModelsFailed),
        content: Text(_error!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.close),
          ),
        ],
      );
    }

    final progress = _progress;
    final hasTotal = progress != null && progress.totalBytes > 0;
    final percent = hasTotal ? (progress.progress * 100).toInt() : 0;

    return AlertDialog(
      title: Text(l.localAiMovingModels),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (progress?.currentModelName != null)
              Text(
                progress!.currentModelName!,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: hasTotal ? progress.progress : null,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  progress == null
                      ? '…'
                      : '$percent% · ${progress.movedModels + (progress.isComplete ? 0 : 1)}/${progress.totalModels}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (hasTotal)
                  Text(
                    '${_formatBytes(progress.movedBytes)} / ${_formatBytes(progress.totalBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
