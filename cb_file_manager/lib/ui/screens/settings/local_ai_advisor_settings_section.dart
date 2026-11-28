import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../models/local_ai/local_ai_advisor_model.dart';
import '../../../services/local_ai/local_ai_advisor_service.dart';
import '../../../services/local_ai/local_model_downloads.dart';
import '../../tab_manager/core/tab_main_screen.dart';
import 'package:cb_file_manager/config/translation_helper.dart';
import 'settings_navigation.dart';
import '../../../services/media/subtitle_services.dart';
import '../../components/video/subtitle_settings_panel.dart';

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

  final bool compact;

  /// Limits installed models, downloads and the installer to these purposes.
  /// Null shows every purpose.
  final Set<LocalModelPurpose>? purposes;

  const LocalAiAdvisorSettingsSection({
    super.key,
    required this.buildSectionCard,
    required this.buildCompactSettingTile,
    this.compact = false,
    this.purposes,
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
  bool _serviceReady = false;
  String? _hfToken;
  List<InstalledLocalModel> _installed = [];
  InstalledLocalModel? _selectedModel;
  final _contextTokens = TextEditingController();
  int? _savedContextTokens;
  String _modelStorageDir = '';
  bool _hasCustomModelStorage = false;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final services = await SubtitleServices.load();
    if (!mounted) return;
    _service = services.models;
    _downloads = services.downloads;
    _downloads.addListener(_onDownloadsChanged);
    _serviceReady = true;
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
    if (_serviceReady) _downloads.removeListener(_onDownloadsChanged);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _contextTokens.dispose();
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
    await _service.refreshInstalledModels();
    final token = await _service.getHuggingFaceToken();
    final installed = _service.getManagedModels();
    final selected = _service.getSelectedModel();
    final maxTokens = _service.getMaxContextTokens();
    final storageDir = await _service.getModelStorageDirectory();
    final hasCustomStorage = _service.getCustomModelStorageDirectory() != null;

    if (mounted) {
      if (_savedContextTokens != maxTokens) {
        _savedContextTokens = maxTokens;
        _contextTokens.text = maxTokens.toString();
      }
      setState(() {
        _hfToken = token;
        _installed = installed;
        _selectedModel = selected;
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
      title: Platform.isAndroid || Platform.isIOS
          ? l.localAiAdvisor
          : l.aiModels,
      icon: PhosphorIconsLight.brain,
      children: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(CbSpacing.lg),
            child: Center(child: CbLoadingText()),
          )
        else ...[
          if (!widget.compact) ...[
            _buildTokenSection(context, l),
            const Divider(height: 1),
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
              SubtitleSettingsPanel(models: _service, downloads: _downloads),
              const Divider(height: 1),
            ],
          ],
          _buildInstalledModelsSection(context, l),
          if (widget.compact) ...[
            Divider(height: CbSpacing.xl, color: context.cbColors.strokeSubtle),
            CbExpander(
              title: Text(l.advancedSettings),
              flush: true,
              headerPadding: const EdgeInsets.symmetric(vertical: CbSpacing.sm),
              contentPadding: const EdgeInsets.only(top: CbSpacing.md),
              children: [
                _buildTokenSection(context, l),
                const SizedBox(height: CbSpacing.lg),
                _buildModelStorageSection(context, l),
                if (_shows(LocalModelPurpose.chat)) ...[
                  const SizedBox(height: CbSpacing.lg),
                  _buildContextWindowSection(context, l),
                ],
              ],
            ),
          ] else ...[
            const Divider(height: 1),
            _buildModelStorageSection(context, l),
            const Divider(height: 1),
            _buildContextWindowSection(context, l),
          ],
        ],
      ],
    );
  }

  Widget _buildTokenSection(BuildContext context, AppLocalizations l) {
    final token = _hfToken;
    return _buildConfigurationField(
      label: l.huggingFaceToken,
      hint: l.huggingFaceTokenHint,
      field: _buildFieldValue(
        context,
        token == null
            ? l.noTokenSet
            : '${token.length > 8 ? token.substring(0, 8) : ''}••••••••',
      ),
      actions: [
        if (token != null)
          CbButton.icon(
            icon: PhosphorIconsLight.x,
            tooltip: l.clearToken,
            onPressed: _clearToken,
            variant: widget.compact
                ? CbButtonVariant.secondary
                : CbButtonVariant.ghost,
            outlined: widget.compact,
          )
        else
          CbButton(
            icon: PhosphorIconsLight.clipboardText,
            label: l.pasteToken,
            tooltip: l.pasteToken,
            onPressed: _pasteToken,
          ),
      ],
    );
  }

  bool _shows(LocalModelPurpose purpose) =>
      widget.purposes?.contains(purpose) ?? true;

  Widget _buildInstalledModelsSection(
    BuildContext context,
    AppLocalizations l,
  ) {
    final colors = context.cbColors;
    final installed = _installed.where((m) => _shows(m.purpose)).toList();
    final downloads = _downloads.downloads
        .where((d) => _shows(d.entry.purpose))
        .toList();
    return Padding(
      padding: widget.compact
          ? EdgeInsets.zero
          : const EdgeInsets.all(CbSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: CbSpacing.sm,
        children: [
          Row(
            spacing: CbSpacing.sm,
            children: [
              Expanded(
                child: Text(l.installedModels, style: CbTypography.headingSm),
              ),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: CbButton(
                    key: const ValueKey('local-ai-install-model'),
                    onPressed: _showModelBrowser,
                    icon: PhosphorIconsLight.downloadSimple,
                    label: l.installLocalModel,
                    variant: widget.compact
                        ? CbButtonVariant.primary
                        : CbButtonVariant.secondary,
                  ),
                ),
              ),
            ],
          ),
          for (final download in downloads)
            _DownloadTile(
              download: download,
              onCancel: () => _downloads.cancel(download.entry.id),
              onRetry: () => _downloads.start(download.entry),
            ),
          if (installed.isEmpty && downloads.isEmpty)
            CbSurface(
              padding: const EdgeInsets.all(CbSpacing.md),
              child: Text(
                l.noModelsInstalled,
                style: CbTypography.body.copyWith(color: colors.textSecondary),
              ),
            ),
          for (final model in installed)
            _buildInstalledModelTile(
              context,
              l,
              model,
              isActive: _selectedModel?.catalogId == model.catalogId,
            ),
        ],
      ),
    );
  }

  Widget _buildModelStorageSection(BuildContext context, AppLocalizations l) {
    final path = _displayPath(_modelStorageDir);
    return _buildConfigurationField(
      label: l.localAiModelStorage,
      hint: l.localAiModelStorageHint,
      field: CbTooltip(
        message: path,
        child: _buildFieldValue(context, path, mono: true),
      ),
      actions: [
        if (_hasCustomModelStorage)
          CbButton.icon(
            icon: PhosphorIconsLight.arrowCounterClockwise,
            tooltip: l.localAiModelStorageReset,
            onPressed: () => _setModelStorageDirectory(null),
          ),
        CbButton(
          icon: PhosphorIconsLight.folderOpen,
          label: l.browse,
          tooltip: l.browse,
          onPressed: _pickModelStorageDirectory,
        ),
      ],
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
    void apply() {
      final parsed = int.tryParse(_contextTokens.text);
      if (parsed != null) {
        unawaited(_setMaxTokens(parsed));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.localAiInvalidTokenCount)));
      }
    }

    return _buildConfigurationField(
      label: l.localAiContextWindow,
      hint: l.localAiContextWindowHint,
      field: Semantics(
        label: l.localAiContextWindow,
        child: CbTextField(
          controller: _contextTokens,
          keyboardType: TextInputType.number,
          placeholder:
              '${LocalAiAdvisorService.minContextTokens}–${LocalAiAdvisorService.maxContextTokens}',
          suffix: Text(
            l.localAiTokensSuffix,
            style: CbTypography.bodySm.copyWith(
              color: context.cbColors.textSecondary,
            ),
          ),
          onSubmitted: (_) => apply(),
        ),
      ),
      actions: [
        CbButton(
          icon: PhosphorIconsLight.check,
          label: l.save,
          onPressed: apply,
        ),
      ],
    );
  }

  Widget _buildConfigurationField({
    required String label,
    required String hint,
    required Widget field,
    required List<CbButton> actions,
  }) => Padding(
    padding: widget.compact
        ? EdgeInsets.zero
        : const EdgeInsets.all(CbSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: CbSpacing.sm,
      children: [
        Text(label, style: CbTypography.headingSm),
        if (!widget.compact)
          Text(
            hint,
            style: CbTypography.bodySm.copyWith(
              color: context.cbColors.textSecondary,
            ),
          ),
        Row(
          spacing: CbSpacing.sm,
          children: [
            Expanded(child: field),
            if (widget.compact)
              SizedBox(
                width: CbSpacing.xxxl * 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: CbSpacing.sm,
                  children: [
                    ...actions.take(actions.length - 1),
                    if (actions.last.label != null)
                      Expanded(child: actions.last)
                    else
                      actions.last,
                  ],
                ),
              )
            else
              ...actions,
          ],
        ),
      ],
    ),
  );

  Widget _buildFieldValue(
    BuildContext context,
    String text, {
    bool mono = false,
  }) => CbSurface(
    height: CbSizes.controlMd,
    padding: const EdgeInsets.symmetric(horizontal: CbSpacing.md),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (mono ? CbTypography.mono : CbTypography.body).copyWith(
          color: context.cbColors.textSecondary,
        ),
      ),
    ),
  );

  Future<void> _setMaxTokens(int tokens) async {
    await _service.setMaxContextTokens(tokens);
    await _loadState();
    if (mounted && _savedContextTokens != null) {
      _contextTokens.text = _savedContextTokens.toString();
    }
  }

  Widget _buildInstalledModelTile(
    BuildContext context,
    AppLocalizations l,
    InstalledLocalModel model, {
    required bool isActive,
  }) {
    final colors = context.cbColors;
    final modelPath = _displayPath(model.localPath);
    final isRunnable =
        model.purpose != LocalModelPurpose.chat || model.isRunnableArtifact;
    return CbSurface(
      padding: const EdgeInsets.all(CbSpacing.md),
      selected: isActive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: CbSpacing.sm,
        children: [
          Row(
            spacing: CbSpacing.sm,
            children: [
              if (!widget.compact)
                Icon(
                  PhosphorIconsLight.brain,
                  size: CbSizes.iconLg,
                  color: isActive ? colors.accent.text : colors.icon,
                ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.displayName,
                      style: isActive
                          ? CbTypography.headingSm
                          : CbTypography.label,
                    ),
                    Text(
                      '${modelPurposeLabel(l, model.purpose)} · ${_formatBytes(model.sizeBytes)}',
                      style: CbTypography.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isActive &&
                  isRunnable &&
                  model.purpose == LocalModelPurpose.chat)
                if (widget.compact)
                  CbButton.icon(
                    icon: PhosphorIconsLight.checkCircle,
                    tooltip: l.selectActiveModel,
                    onPressed: () => _setActiveModel(model.catalogId),
                  )
                else
                  CbButton(
                    label: l.selectActiveModel,
                    variant: CbButtonVariant.ghost,
                    onPressed: () => _setActiveModel(model.catalogId),
                  ),
              if (widget.compact)
                CbButton.icon(
                  icon: PhosphorIconsLight.folderOpen,
                  tooltip: '${l.openLocation}\n$modelPath',
                  onPressed: () => _openModelLocation(modelPath),
                ),
              CbButton.icon(
                icon: PhosphorIconsLight.trash,
                tooltip: l.uninstallModel,
                onPressed: () => _uninstallModel(model.catalogId),
              ),
            ],
          ),
          if (!isRunnable) _buildIncompatibleBanner(context, l, model),
          if (!widget.compact)
            Row(
              spacing: CbSpacing.sm,
              children: [
                Expanded(
                  child: _buildFieldValue(context, modelPath, mono: true),
                ),
                CbButton(
                  onPressed: () => _openModelLocation(modelPath),
                  icon: PhosphorIconsLight.folderOpen,
                  label: l.openLocation,
                  variant: CbButtonVariant.ghost,
                ),
              ],
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
    final colors = context.cbColors;
    return CbSurface(
      color: colors.status.dangerSurface,
      padding: const EdgeInsets.all(CbSpacing.sm),
      child: Row(
        spacing: CbSpacing.sm,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIconsLight.warning,
            size: CbSizes.iconMd,
            color: colors.status.danger,
          ),
          Expanded(
            child: Column(
              spacing: CbSpacing.xs,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.localAiIncompatibleArtifact,
                  style: CbTypography.bodySm.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                CbButton(
                  onPressed: () => _reinstallCompatibleModel(model),
                  icon: PhosphorIconsLight.arrowsClockwise,
                  label: l.localAiReinstallCompatible,
                  size: CbButtonSize.sm,
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
      try {
        await _service.uninstallModel(catalogId);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr.aiModelRemoveFailed)),
          );
        }
        return;
      }
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
        purposes: widget.purposes,
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
  final Set<LocalModelPurpose>? purposes;

  const _ModelBrowserDialog({
    required this.service,
    required this.downloads,
    required this.installedIds,
    this.purposes,
  });

  @override
  State<_ModelBrowserDialog> createState() => _ModelBrowserDialogState();
}

class _ModelBrowserDialogState extends State<_ModelBrowserDialog> {
  List<HuggingFaceModelEntry>? _catalog;
  LocalModelPurpose? _purpose;
  late Set<String> _installedIds = widget.installedIds;
  StreamSubscription<HuggingFaceModelEntry>? _completed;
  StreamSubscription<void>? _registryChanged;

  @override
  void initState() {
    super.initState();
    widget.downloads.addListener(_refresh);
    _registryChanged = widget.service.onInstalledModelsChanged.listen((_) {
      if (mounted) {
        setState(
          () => _installedIds = widget.service
              .getManagedModels()
              .map((m) => m.catalogId)
              .toSet(),
        );
      }
    });
    _completed = widget.downloads.onCompleted.listen((entry) {
      if (mounted) setState(() => _installedIds = {..._installedIds, entry.id});
    });
    widget.service
        .fetchModelCatalog(forceRefresh: true, includeSubtitleModels: true)
        .then((catalog) {
          if (mounted) setState(() => _catalog = catalog);
        });
  }

  @override
  void dispose() {
    widget.downloads.removeListener(_refresh);
    _completed?.cancel();
    _registryChanged?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final allowed = widget.purposes;
    final catalog = _catalog
        ?.where((e) => allowed == null || allowed.contains(e.purpose))
        .where((e) => _purpose == null || e.purpose == _purpose)
        .toList();
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
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text(l.aiModelAll),
                  selected: _purpose == null,
                  onSelected: (_) => setState(() => _purpose = null),
                ),
                for (final purpose in LocalModelPurpose.values)
                  if ((allowed == null || allowed.contains(purpose)) &&
                      (purpose == LocalModelPurpose.chat ||
                          Platform.isWindows ||
                          Platform.isMacOS ||
                          Platform.isLinux))
                    ChoiceChip(
                      label: Text(modelPurposeLabel(l, purpose)),
                      selected: _purpose == purpose,
                      onSelected: (_) => setState(() => _purpose = purpose),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: catalog == null
                  ? const Center(child: CbLoadingText())
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
      action = progress == null
          ? CbLoadingText(text: context.tr.laDownloading)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                  ),
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
                  "${modelPurposeLabel(l, entry.purpose)} · ${entry.displayName}",
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
    final colors = context.cbColors;
    final l = AppLocalizations.of(context)!;
    final progress = download.progress;
    final failed = download.failed;

    return CbSurface(
      padding: const EdgeInsets.all(CbSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: CbSpacing.sm,
        children: [
          Row(
            spacing: CbSpacing.sm,
            children: [
              Icon(
                failed
                    ? PhosphorIconsLight.warningCircle
                    : PhosphorIconsLight.downloadSimple,
                size: CbSizes.iconLg,
                color: failed ? colors.status.danger : colors.icon,
              ),
              Expanded(
                child: Text(
                  failed
                      ? '${context.tr.laInstallFailed}: ${download.entry.displayName}'
                      : l.localModelDownloading(download.entry.displayName),
                  style: CbTypography.label,
                ),
              ),
              if (failed) CbButton(label: l.retry, onPressed: onRetry),
              CbButton.icon(
                icon: PhosphorIconsLight.x,
                tooltip: failed ? l.dismiss : l.cancel,
                onPressed: onCancel,
              ),
            ],
          ),
          if (failed)
            Text(
              download.error!,
              style: CbTypography.bodySm.copyWith(color: colors.status.danger),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            )
          else ...[
            LinearProgressIndicator(
              value: progress,
              minHeight: CbSpacing.xs,
              borderRadius: CbRadii.smAll,
            ),
            Text(
              [
                if (progress != null) '${(progress * 100).toInt()}%',
                download.totalBytes > 0
                    ? '${_formatBytes(download.downloadedBytes)} / ${_formatBytes(download.totalBytes)}'
                    : _formatBytes(download.downloadedBytes),
              ].join(' · '),
              style: CbTypography.bodySm.copyWith(color: colors.textSecondary),
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

/// Reuses the Settings model manager from a standalone video/PiP window.
/// [subtitleOnly] hides chat models, which the player never uses.
Future<void> showLocalModelManagerDialog(
  BuildContext context, {
  bool subtitleOnly = false,
}) => CbDialog.show<void>(
  context: context,
  dialog: CbDialog(
    title: context.tr.aiSubtitleManage,
    content: SizedBox(
      width: double.infinity,
      child: LocalAiAdvisorSettingsSection(
        compact: true,
        purposes: subtitleOnly
            ? const {LocalModelPurpose.speech, LocalModelPurpose.translation}
            : null,
        buildSectionCard:
            ({required title, required icon, required children}) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
        buildCompactSettingTile:
            ({
              required title,
              required subtitle,
              required icon,
              trailing,
              onTap,
            }) => ListTile(
              title: Text(title),
              subtitle: Text(subtitle),
              leading: Icon(icon),
              trailing: trailing,
              onTap: onTap,
            ),
      ),
    ),
  ),
);
