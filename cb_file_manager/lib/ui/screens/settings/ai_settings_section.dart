import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:get_it/get_it.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../models/ai/ai_provider_model.dart';
import '../../../services/ai/ai_provider_service.dart';
import '../../../services/ai/providers/codex_cli_provider.dart';

/// AI Settings section widget for the settings screen.
///
/// Provides provider CRUD, connection testing, and global AI settings.
class AiSettingsSection extends StatefulWidget {
  /// Section card builder from the parent settings screen.
  final Widget Function({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) buildSectionCard;

  /// Compact setting tile builder from the parent settings screen.
  final Widget Function({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
    VoidCallback? onTap,
  }) buildCompactSettingTile;

  const AiSettingsSection({
    Key? key,
    required this.buildSectionCard,
    required this.buildCompactSettingTile,
  }) : super(key: key);

  @override
  State<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends State<AiSettingsSection> {
  final AiProviderService _providerService =
      GetIt.instance<AiProviderService>();
  List<AiProviderConfig> _providers = [];
  bool _isLoading = true;

  // Connection test state per provider ID
  final Map<String, bool?> _testResults = {};
  final Set<String> _testingIds = {};

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    final providers = await _providerService.getProviders();
    if (mounted) {
      setState(() {
        _providers = providers;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return widget.buildSectionCard(
      title: l.aiSearchAgent,
      icon: PhosphorIconsLight.brain,
      children: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          // Provider list
          if (_providers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                l.noProviders,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            )
          else
            ..._providers.map((p) => _buildProviderTile(context, p)),

          // Add provider button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => _showProviderDialog(context),
              icon: const Icon(PhosphorIconsLight.plus, size: 18),
              label: Text(l.addProvider),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProviderTile(BuildContext context, AiProviderConfig provider) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final testResult = _testResults[provider.id];
    final isTesting = _testingIds.contains(provider.id);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: provider.isEnabled
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          provider.apiType == AiApiType.anthropic
              ? PhosphorIconsLight.chatCircleDots
              : PhosphorIconsLight.robot,
          size: 18,
          color: provider.isEnabled
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              provider.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              aiApiTypeDisplayName(provider.apiType),
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (provider.apiType == AiApiType.openaiCompatible) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                aiProviderAuthModeDisplayName(provider.authMode),
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (testResult != null) ...[
            const SizedBox(width: 4),
            Icon(
              testResult
                  ? PhosphorIconsLight.checkCircle
                  : PhosphorIconsLight.warningCircle,
              size: 14,
              color: testResult ? Colors.green : Colors.red,
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${l.defaultModel}: ${provider.modelName}',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTesting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(PhosphorIconsLight.plugsConnected, size: 18),
              tooltip: l.testConnection,
              onPressed: () => _testConnection(provider.id),
              visualDensity: VisualDensity.compact,
            ),
          Switch(
            value: provider.isEnabled,
            onChanged: (v) => _toggleProvider(provider.id, v),
          ),
          PopupMenuButton<String>(
            icon: const Icon(PhosphorIconsLight.dotsThreeVertical, size: 18),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    const Icon(PhosphorIconsLight.pencil, size: 16),
                    const SizedBox(width: 8),
                    Text(l.edit),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(PhosphorIconsLight.trash,
                        size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Text(l.delete,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ),
              ),
            ],
            onSelected: (action) {
              if (action == 'edit') {
                _showProviderDialog(context, existing: provider);
              } else if (action == 'delete') {
                _confirmDelete(context, provider);
              }
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _toggleProvider(String id, bool enabled) async {
    await _providerService.toggleProvider(id, enabled: enabled);
    await _loadProviders();
  }

  Future<void> _testConnection(String id) async {
    setState(() {
      _testingIds.add(id);
      _testResults.remove(id);
    });

    final ok = await _providerService.testProvider(id);

    if (mounted) {
      setState(() {
        _testingIds.remove(id);
        _testResults[id] = ok;
      });
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? l.connectionSuccess : l.aiConnectionFailed),
          backgroundColor:
              ok ? Colors.green : Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, AiProviderConfig provider) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteProvider),
        content: Text(l.deleteProviderConfirmation(provider.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.delete,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _providerService.deleteProvider(provider.id);
      await _loadProviders();
    }
  }

  // ---------------------------------------------------------------------------
  // Provider form dialog
  // ---------------------------------------------------------------------------

  Future<void> _showProviderDialog(
    BuildContext context, {
    AiProviderConfig? existing,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ProviderFormDialog(
        existing: existing,
        providerService: _providerService,
      ),
    );

    if (result == true) {
      await _loadProviders();
    }
  }
}

// =============================================================================
// Provider form dialog
// =============================================================================

class _ProviderFormDialog extends StatefulWidget {
  final AiProviderConfig? existing;
  final AiProviderService providerService;

  const _ProviderFormDialog({
    this.existing,
    required this.providerService,
  });

  @override
  State<_ProviderFormDialog> createState() => _ProviderFormDialogState();
}

class _ProviderFormDialogState extends State<_ProviderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _apiKeyController;
  late TextEditingController _endpointController;
  late TextEditingController _modelController;
  late TextEditingController _systemPromptController;

  AiApiType _apiType = AiApiType.openaiCompatible;
  AiProviderAuthMode _authMode = AiProviderAuthMode.apiKey;
  double _temperature = 0.3;
  int _maxTokens = 4096;
  int _timeoutSeconds = 30;
  int _maxRetries = 2;
  bool _showAdvanced = false;
  bool _isSaving = false;
  bool _isFetchingModels = false;
  List<String> _availableModels = [];
  String? _fetchModelsError;
  String? _selectedPresetName;

  static const List<_AiProviderPreset> _providerPresets = [
    _AiProviderPreset(
      name: 'OpenAI',
      endpoint: 'https://api.openai.com/v1',
      modelName: 'gpt-4o',
    ),
    _AiProviderPreset(
      name: 'Azure OpenAI',
      endpoint: 'https://your-resource-name.openai.azure.com/openai/v1',
      modelName: 'gpt-4o',
    ),
    _AiProviderPreset(
      name: 'Ollama',
      endpoint: 'http://localhost:11434/v1',
      modelName: 'gpt-oss:20b',
      apiKeyPlaceholder: 'ollama',
    ),
    _AiProviderPreset(
      name: 'LM Studio',
      endpoint: 'http://localhost:1234/v1',
      modelName: 'openai/gpt-oss-20b',
      apiKeyPlaceholder: 'lm-studio',
    ),
    _AiProviderPreset(
      name: 'OpenRouter',
      endpoint: 'https://openrouter.ai/api/v1',
      modelName: 'openai/gpt-4o-mini',
    ),
    _AiProviderPreset(
      name: 'Kimi',
      endpoint: 'https://api.moonshot.ai/v1',
      modelName: 'kimi-k2.6',
    ),
    _AiProviderPreset(
      name: 'Kimi for Coding',
      endpoint: 'https://api.kimi.com/coding/v1',
      modelName: 'kimi-for-coding',
    ),
    _AiProviderPreset(
      name: 'Groq',
      endpoint: 'https://api.groq.com/openai/v1',
      modelName: 'llama-3.3-70b-versatile',
    ),
    _AiProviderPreset(
      name: 'Cerebras',
      endpoint: 'https://api.cerebras.ai/v1',
      modelName: 'zai-glm-4.7',
    ),
    _AiProviderPreset(
      name: 'Chutes',
      endpoint: 'https://llm.chutes.ai/v1',
      modelName: 'zai-org/GLM-4.7-TEE',
    ),
    _AiProviderPreset(
      name: 'Together AI',
      endpoint: 'https://api.together.xyz/v1',
      modelName: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
    ),
    _AiProviderPreset(
      name: 'DeepSeek',
      endpoint: 'https://api.deepseek.com/v1',
      modelName: 'deepseek-chat',
    ),
    _AiProviderPreset(
      name: 'Mistral',
      endpoint: 'https://api.mistral.ai/v1',
      modelName: 'mistral-large-latest',
    ),
    _AiProviderPreset(
      name: 'xAI',
      endpoint: 'https://api.x.ai/v1',
      modelName: 'grok-4',
    ),
    _AiProviderPreset(
      name: 'Fireworks AI',
      endpoint: 'https://api.fireworks.ai/inference/v1',
      modelName: 'accounts/fireworks/models/llama-v3p3-70b-instruct',
    ),
    _AiProviderPreset(
      name: 'Perplexity',
      endpoint: 'https://api.perplexity.ai',
      modelName: 'sonar-pro',
    ),
    _AiProviderPreset(
      name: 'Anthropic',
      apiType: AiApiType.anthropic,
      endpoint: 'https://api.anthropic.com/v1',
      modelName: 'claude-sonnet-4-20250514',
    ),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _apiKeyController = TextEditingController(text: e?.apiKey ?? '');
    _endpointController = TextEditingController(
      text: e?.endpoint ?? AiProviderConfig.defaultEndpoint(_apiType),
    );
    _modelController = TextEditingController(text: e?.modelName ?? '');
    _systemPromptController =
        TextEditingController(text: e?.systemPrompt ?? '');
    if (e != null) {
      _apiType = e.apiType;
      _authMode = e.authMode;
      _temperature = e.temperature;
      _maxTokens = e.maxTokens;
      _timeoutSeconds = e.timeoutSeconds;
      _maxRetries = e.maxRetries;
    }
  }

  bool get _usesCodexOauth =>
      _apiType == AiApiType.openaiCompatible &&
      _authMode == AiProviderAuthMode.codexOAuth;

  List<_AiProviderPreset> get _sortedProviderPresets {
    return List<_AiProviderPreset>.of(_providerPresets)
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isEdit = widget.existing != null;
    final sortedProviderPresets = _sortedProviderPresets;

    return AlertDialog(
      title: Text(isEdit ? l.editProvider : l.addProvider),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isEdit) ...[
                  CbSelect<String>(
                    label: l.providerPreset,
                    placeholder: l.selectProviderPreset,
                    expand: true,
                    value: _selectedPresetName,
                    items: [
                      for (final preset in sortedProviderPresets)
                        CbSelectItem<String>(
                          value: preset.name,
                          label: preset.name,
                          icon: PhosphorIconsLight.robot,
                        ),
                    ],
                    onChanged: (value) {
                      final preset = sortedProviderPresets.firstWhere(
                        (preset) => preset.name == value,
                      );
                      _applyPreset(preset);
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Provider name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l.providerName,
                    hintText: 'My OpenAI',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // API Type
                Text(l.apiType,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                SegmentedButton<AiApiType>(
                  segments: [
                    ButtonSegment(
                      value: AiApiType.openaiCompatible,
                      label: Text(l.openAiCompatible,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: AiApiType.anthropic,
                      label: Text(l.anthropic,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {_apiType},
                  onSelectionChanged: (values) {
                    setState(() {
                      _apiType = values.first;
                      _selectedPresetName = null;
                      if (_apiType == AiApiType.anthropic) {
                        _authMode = AiProviderAuthMode.apiKey;
                      }
                      _endpointController.text =
                          AiProviderConfig.defaultEndpoint(_apiType);
                    });
                  },
                ),
                const SizedBox(height: 16),

                if (_apiType == AiApiType.openaiCompatible) ...[
                  Text(
                    l.authMode,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<AiProviderAuthMode>(
                    segments: [
                      ButtonSegment(
                        value: AiProviderAuthMode.apiKey,
                        label: Text(
                          l.apiKey,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      ButtonSegment(
                        value: AiProviderAuthMode.codexOAuth,
                        label: Text(
                          l.codexOauth,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    selected: {_authMode},
                    onSelectionChanged: (values) {
                      setState(() {
                        _authMode = values.first;
                        if (_usesCodexOauth) {
                          _endpointController.text =
                              AiProviderConfig.defaultEndpoint(
                            AiApiType.openaiCompatible,
                          );
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // API Key
                if (_usesCodexOauth) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.codexOauthDescription,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          CodexCliProvider.codexAuthPath() ??
                              l.codexCredentialUnavailable,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _launchCodexLogin,
                              icon: const Icon(
                                PhosphorIconsLight.signIn,
                                size: 16,
                              ),
                              label: Text(l.launchCodexLogin),
                            ),
                            OutlinedButton.icon(
                              onPressed: _checkCodexCredentials,
                              icon: const Icon(
                                PhosphorIconsLight.shieldCheck,
                                size: 16,
                              ),
                              label: Text(l.checkCredentials),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  TextFormField(
                    controller: _apiKeyController,
                    decoration: InputDecoration(
                      labelText: l.apiKey,
                      hintText: 'sk-...',
                    ),
                    obscureText: true,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // Endpoint URL
                TextFormField(
                  controller: _endpointController,
                  decoration: InputDecoration(
                    labelText: l.endpointUrl,
                  ),
                  enabled: !_usesCodexOauth,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // Model name with fetch button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _availableModels.isEmpty
                          ? TextFormField(
                              controller: _modelController,
                              decoration: InputDecoration(
                                labelText: l.defaultModel,
                                hintText: _apiType == AiApiType.anthropic
                                    ? 'claude-sonnet-4-20250514'
                                    : 'gpt-4o',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Required'
                                  : null,
                            )
                          // `FormField` keeps the select inside the same
                          // validation pass as the text fields around it now
                          // that it no longer carries its own.
                          : FormField<String>(
                              initialValue: _availableModels
                                      .contains(_modelController.text)
                                  ? _modelController.text
                                  : null,
                              validator: (v) =>
                                  v == null || v.isEmpty ? 'Required' : null,
                              builder: (field) => CbSelect<String>(
                                label: l.defaultModel,
                                placeholder: l.selectModel,
                                expand: true,
                                value: field.value,
                                errorText: field.errorText,
                                items: [
                                  for (final m in _availableModels)
                                    CbSelectItem<String>(value: m, label: m),
                                ],
                                onChanged: (value) {
                                  field.didChange(value);
                                  setState(() {
                                    _modelController.text = value;
                                  });
                                },
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _isFetchingModels
                          ? const SizedBox(
                              width: 36,
                              height: 36,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(
                                  PhosphorIconsLight.arrowsClockwise,
                                  size: 20),
                              tooltip: l.fetchModels,
                              onPressed: _fetchAvailableModels,
                            ),
                    ),
                  ],
                ),
                if (_fetchModelsError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _fetchModelsError!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Advanced settings toggle
                InkWell(
                  onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvanced
                            ? PhosphorIconsLight.caretDown
                            : PhosphorIconsLight.caretRight,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(l.advancedSettings,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),

                if (_showAdvanced) ...[
                  const SizedBox(height: 16),
                  // Temperature
                  Row(
                    children: [
                      Text(
                          '${l.temperature}: ${_temperature.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: _temperature,
                          min: 0.0,
                          max: 2.0,
                          divisions: 20,
                          onChanged: (v) => setState(() => _temperature = v),
                        ),
                      ),
                    ],
                  ),

                  // Max tokens
                  TextFormField(
                    initialValue: _maxTokens.toString(),
                    decoration: InputDecoration(labelText: l.maxTokens),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        _maxTokens = int.tryParse(v) ?? _maxTokens,
                  ),
                  const SizedBox(height: 12),

                  // Timeout
                  TextFormField(
                    initialValue: _timeoutSeconds.toString(),
                    decoration: InputDecoration(labelText: l.timeout),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        _timeoutSeconds = int.tryParse(v) ?? _timeoutSeconds,
                  ),
                  const SizedBox(height: 12),

                  // Max retries
                  TextFormField(
                    initialValue: _maxRetries.toString(),
                    decoration: InputDecoration(labelText: l.maxRetries),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        _maxRetries = int.tryParse(v) ?? _maxRetries,
                  ),
                  const SizedBox(height: 12),

                  // Custom system prompt
                  TextFormField(
                    controller: _systemPromptController,
                    decoration: InputDecoration(
                      labelText: l.systemPrompt,
                      hintText: 'Optional custom system prompt...',
                    ),
                    maxLines: 3,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(l.save),
        ),
      ],
    );
  }

  Future<void> _fetchAvailableModels() async {
    final apiKey = _apiKeyController.text.trim();
    final endpoint = _endpointController.text.trim();

    if ((!_usesCodexOauth && apiKey.isEmpty) || endpoint.isEmpty) {
      setState(() {
        _fetchModelsError = _usesCodexOauth
            ? 'Endpoint is required to fetch models'
            : 'API Key and Endpoint are required to fetch models';
      });
      return;
    }

    setState(() {
      _isFetchingModels = true;
      _fetchModelsError = null;
      _availableModels = [];
    });

    try {
      final models = await widget.providerService.fetchModels(
        apiType: _apiType,
        authMode: _authMode,
        apiKey: _usesCodexOauth ? '' : apiKey,
        endpoint: endpoint,
      );

      if (mounted) {
        setState(() {
          _isFetchingModels = false;
          _availableModels = models.toSet().toList();
          if (models.isEmpty) {
            _fetchModelsError = AppLocalizations.of(context)!.noModelsFound;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingModels = false;
          _fetchModelsError =
              AppLocalizations.of(context)!.fetchModelsError('$e');
        });
      }
    }
  }

  void _applyPreset(_AiProviderPreset preset) {
    setState(() {
      _selectedPresetName = preset.name;
      _apiType = preset.apiType;
      _authMode = AiProviderAuthMode.apiKey;
      _nameController.text = preset.name;
      _endpointController.text = preset.endpoint;
      _modelController.text = preset.modelName;
      if (_apiKeyController.text.trim().isEmpty &&
          preset.apiKeyPlaceholder != null) {
        _apiKeyController.text = preset.apiKeyPlaceholder!;
      }
      _availableModels = [];
      _fetchModelsError = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final systemPrompt = _systemPromptController.text.trim().isEmpty
          ? null
          : _systemPromptController.text.trim();

      if (widget.existing != null) {
        await widget.providerService.updateProvider(
          widget.existing!.copyWith(
            name: _nameController.text.trim(),
            apiType: _apiType,
            authMode: _authMode,
            apiKey: _usesCodexOauth ? '' : _apiKeyController.text.trim(),
            endpoint: _endpointController.text.trim(),
            modelName: _modelController.text.trim(),
            temperature: _temperature,
            maxTokens: _maxTokens,
            systemPrompt: systemPrompt,
            clearSystemPrompt: systemPrompt == null,
            timeoutSeconds: _timeoutSeconds,
            maxRetries: _maxRetries,
          ),
        );
      } else {
        await widget.providerService.addProvider(
          name: _nameController.text.trim(),
          apiType: _apiType,
          authMode: _authMode,
          apiKey: _usesCodexOauth ? '' : _apiKeyController.text.trim(),
          endpoint: _endpointController.text.trim(),
          modelName: _modelController.text.trim(),
          temperature: _temperature,
          maxTokens: _maxTokens,
          systemPrompt: systemPrompt,
          timeoutSeconds: _timeoutSeconds,
          maxRetries: _maxRetries,
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _launchCodexLogin() async {
    try {
      await Process.start(
        'cmd',
        ['/c', 'start', '', 'codex', 'login'],
        runInShell: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.codexLoginLaunched),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _checkCodexCredentials() async {
    final l = AppLocalizations.of(context)!;
    final ok = await CodexCliProvider.hasOauthCredentials();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? l.connectionSuccess : l.codexCredentialMissing),
        backgroundColor:
            ok ? Colors.green : Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _AiProviderPreset {
  final String name;
  final AiApiType apiType;
  final String endpoint;
  final String modelName;
  final String? apiKeyPlaceholder;

  const _AiProviderPreset({
    required this.name,
    this.apiType = AiApiType.openaiCompatible,
    required this.endpoint,
    required this.modelName,
    this.apiKeyPlaceholder,
  });
}
