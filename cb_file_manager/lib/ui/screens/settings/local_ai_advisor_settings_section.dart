import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../models/local_ai/local_ai_advisor_model.dart';
import '../../../services/local_ai/local_ai_advisor_service.dart';
import '../../tab_manager/core/tab_main_screen.dart';

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
  bool _isLoading = true;
  String? _hfToken;
  List<HuggingFaceModelEntry> _catalog = [];
  List<InstalledLocalModel> _installed = [];
  InstalledLocalModel? _selectedModel;
  int _maxTokens = LocalAiAdvisorService.defaultContextTokens;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    _service = GetIt.instance<LocalAiAdvisorService>();
    await _loadState();
  }

  Future<void> _loadState() async {
    final token = await _service.getHuggingFaceToken();
    final installed = _service.getInstalledModels();
    final selected = _service.getSelectedModel();
    final maxTokens = _service.getMaxContextTokens();

    if (mounted) {
      setState(() {
        _hfToken = token;
        _installed = installed;
        _selectedModel = selected;
        _maxTokens = maxTokens;
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

          // Context window section
          _buildContextWindowSection(context, l),
          const Divider(height: 1),

          // Browse models button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: OutlinedButton.icon(
              onPressed: _showModelBrowser,
              icon: const Icon(PhosphorIconsLight.magnifyingGlass, size: 18),
              label: Text(l.browseModels),
            ),
          ),
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
          Text(
            l.installedModels,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          if (_installed.isEmpty)
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
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
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: isActive
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : null,
      ),
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
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
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
          const SnackBar(content: Text('No token found in clipboard')),
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
        content: const Text('Remove this model from your device?'),
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
    final catalog = await _service.fetchModelCatalog(forceRefresh: true);

    if (!mounted) return;

    setState(() {
      _catalog = catalog;
    });

    await showDialog(
      context: context,
      builder: (ctx) => _ModelBrowserDialog(
        catalog: _catalog,
        installed: _installed,
        onInstall: _installModel,
      ),
    );

    // Refresh installed list after dialog closes
    await _loadState();
  }

  Future<void> _installModel(HuggingFaceModelEntry entry) async {
    if (!mounted) return;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InstallProgressDialog(service: _service, entry: entry),
    ).then((_) async {
      // Refresh state after dialog closes
      if (mounted) {
        await _loadState();
      }
    });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open location: $e')));
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

class _ModelBrowserDialog extends StatelessWidget {
  final List<HuggingFaceModelEntry> catalog;
  final List<InstalledLocalModel> installed;
  final Future<void> Function(HuggingFaceModelEntry) onInstall;

  const _ModelBrowserDialog({
    required this.catalog,
    required this.installed,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final installedIds = installed.map((m) => m.catalogId).toSet();

    return AlertDialog(
      title: Text(l.browseModels),
      content: SizedBox(
        width: 500,
        height: 400,
        child: catalog.isEmpty
            ? Center(child: Text(l.noModelsFound))
            : ListView.builder(
                itemCount: catalog.length,
                itemBuilder: (context, index) {
                  final entry = catalog[index];
                  final isInstalled = installedIds.contains(entry.id);
                  return _ModelCatalogTile(
                    entry: entry,
                    isInstalled: isInstalled,
                    onInstall: isInstalled || !entry.compatible
                        ? null
                        : () => onInstall(entry),
                  );
                },
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
  final bool isInstalled;
  final VoidCallback? onInstall;

  const _ModelCatalogTile({
    required this.entry,
    required this.isInstalled,
    this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;

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
              if (isInstalled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Installed',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (!entry.compatible)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(PhosphorIconsLight.warningCircle, size: 14),
                  label: const Text('Runtime pending'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: onInstall,
                  icon: const Icon(PhosphorIconsLight.download, size: 14),
                  label: Text(l.installModel),
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
            children: [
              if (entry.sizeBytes != null)
                _buildChip(
                  context,
                  '${(entry.sizeBytes! / (1024 * 1024)).toStringAsFixed(0)} MB',
                ),
              if (entry.license != null) _buildChip(context, entry.license!),
              if (!entry.compatible) _buildChip(context, 'Requires GGUF'),
            ],
          ),
        ],
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
// Install progress dialog
// =============================================================================

class _InstallProgressDialog extends StatefulWidget {
  final LocalAiAdvisorService service;
  final HuggingFaceModelEntry entry;

  const _InstallProgressDialog({required this.service, required this.entry});

  @override
  State<_InstallProgressDialog> createState() => _InstallProgressDialogState();
}

class _InstallProgressDialogState extends State<_InstallProgressDialog> {
  ModelDownloadProgress? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startInstall();
  }

  Future<void> _startInstall() async {
    try {
      await widget.service.installModel(
        widget.entry,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
            });

            // Auto-close when completed
            if (progress.state == LocalModelDownloadState.completed) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.modelInstalled,
                      ),
                    ),
                  );
                  Navigator.of(context).pop();
                }
              });
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;

    if (_error != null) {
      return AlertDialog(
        title: const Text('Installation Failed'),
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
    final downloaded = progress != null
        ? (progress.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)
        : '0';
    final total = hasTotal
        ? (progress.totalBytes / (1024 * 1024)).toStringAsFixed(1)
        : '0';

    return AlertDialog(
      title: Text(l.modelInstalling),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.entry.displayName,
              style: const TextStyle(fontWeight: FontWeight.w600),
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
                  hasTotal ? '$percent%' : 'Downloading...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  hasTotal ? '$downloaded MB / $total MB' : '$downloaded MB',
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
