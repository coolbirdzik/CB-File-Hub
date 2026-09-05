import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../models/ai/ai_message.dart';
import '../../models/ai/ai_provider_model.dart';
import '../../models/database/sqlite_database_provider.dart';
import '../../utils/app_logger.dart';
import 'providers/ai_provider.dart';
import 'providers/anthropic_provider.dart';
import 'providers/codex_cli_provider.dart';
import 'providers/openai_provider.dart';

/// Tracks the health of a single AI provider.
class _ProviderHealth {
  int consecutiveFailures = 0;
  DateTime? lastFailureTime;

  /// A provider is considered "down" if it has had 3+ consecutive failures
  /// in the last 5 minutes.
  bool get isDown {
    if (consecutiveFailures < 3) return false;
    if (lastFailureTime == null) return false;
    return DateTime.now().difference(lastFailureTime!).inMinutes < 5;
  }

  void recordFailure() {
    consecutiveFailures++;
    lastFailureTime = DateTime.now();
  }

  void recordSuccess() {
    consecutiveFailures = 0;
    lastFailureTime = null;
  }
}

/// Result of a chat request, containing the response and the provider that succeeded.
class AiChatResult {
  final AiChatResponse response;
  final String providerId;
  AiChatResult({required this.response, required this.providerId});
}

/// Result of a streaming chat request.
class AiStreamResult {
  final Stream<String> stream;
  final String providerId;
  AiStreamResult({required this.stream, required this.providerId});
}

/// Manages AI provider configurations, instantiation, and fallback logic.
///
/// CRUD operations are backed by the `ai_providers` SQLite table,
/// accessed directly via [SqliteDatabaseProvider] (following the same
/// pattern as [NetworkCredentialsService]).
class AiProviderService {
  static const _uuid = Uuid();
  static const String _tableName = 'ai_providers';

  final SqliteDatabaseProvider _dbProvider = SqliteDatabaseProvider();

  /// Cached provider instances, keyed by config ID.
  final Map<String, AiProvider> _providerInstances = {};

  /// Health tracking per provider ID.
  final Map<String, _ProviderHealth> _healthCache = {};

  /// Stream controller for provider health status changes.
  final _healthController = StreamController<String>.broadcast();

  /// Stream emitting provider IDs whose health status changed.
  Stream<String> get onHealthChanged => _healthController.stream;

  /// In-memory cache of configs (refreshed on every CRUD operation).
  List<AiProviderConfig> _configsCache = [];
  bool _configsLoaded = false;
  bool _tableEnsured = false;

  AiProviderService();

  // ---------------------------------------------------------------------------
  // Table creation (for existing databases that predate this feature)
  // ---------------------------------------------------------------------------

  Future<Database> _getDatabase() async {
    await _dbProvider.initialize();
    final db = await _dbProvider.getDatabase();
    if (!_tableEnsured) {
      await _ensureTable(db);
      _tableEnsured = true;
    }
    return db;
  }

  Future<void> _ensureTable(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableName (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          api_type TEXT NOT NULL,
          auth_mode TEXT NOT NULL DEFAULT 'api_key',
          api_key TEXT NOT NULL,
          endpoint TEXT NOT NULL,
          model_name TEXT NOT NULL,
          temperature REAL DEFAULT 0.3,
          max_tokens INTEGER DEFAULT 4096,
          system_prompt TEXT,
          timeout_seconds INTEGER DEFAULT 30,
          max_retries INTEGER DEFAULT 2,
          is_enabled INTEGER DEFAULT 1,
          priority INTEGER DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    } catch (e) {
      AppLogger.debug('[AI] Table already exists or creation skipped: $e');
    }

    try {
      await db.execute(
        "ALTER TABLE $_tableName ADD COLUMN auth_mode TEXT NOT NULL DEFAULT 'api_key'",
      );
    } catch (_) {
      // Column already exists.
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  /// Returns all configured providers, sorted by priority (ascending).
  Future<List<AiProviderConfig>> getProviders() async {
    if (!_configsLoaded) {
      await _refreshCache();
    }
    return List.unmodifiable(_configsCache);
  }

  /// Returns only enabled providers, sorted by priority.
  Future<List<AiProviderConfig>> getEnabledProviders() async {
    final all = await getProviders();
    return all.where((p) => p.isEnabled).toList();
  }

  /// Returns available models grouped by enabled provider.
  ///
  /// Each provider includes its configured default model even if remote model
  /// discovery fails.
  Future<List<AiProviderModelCatalog>> getEnabledProviderModelCatalogs() async {
    final providers = await getEnabledProviders();
    final catalogs = await Future.wait(
      providers.map((config) async {
        List<String> models = const <String>[];
        try {
          models = await fetchModels(
            apiType: config.apiType,
            authMode: config.authMode,
            apiKey: config.apiKey,
            endpoint: config.endpoint,
          );
        } catch (e) {
          AppLogger.warning(
            '[AI] Failed to fetch models for ${config.name}',
            error: e,
          );
        }

        final mergedModels = <String>{
          ...models.where((m) => m.trim().isNotEmpty),
        };
        if (config.modelName.trim().isNotEmpty) {
          mergedModels.add(config.modelName.trim());
        }

        final sortedModels = mergedModels.toList()..sort();
        return AiProviderModelCatalog(
          providerId: config.id,
          providerName: config.name,
          apiType: config.apiType,
          authMode: config.authMode,
          defaultModelName: config.modelName,
          models: sortedModels,
        );
      }),
    );

    return catalogs;
  }

  /// Returns a single provider config by ID, or `null` if not found.
  Future<AiProviderConfig?> getProvider(String id) async {
    final all = await getProviders();
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Adds a new provider configuration and returns it.
  Future<AiProviderConfig> addProvider({
    required String name,
    required AiApiType apiType,
    AiProviderAuthMode authMode = AiProviderAuthMode.apiKey,
    required String apiKey,
    required String endpoint,
    required String modelName,
    double temperature = 0.3,
    int maxTokens = 4096,
    String? systemPrompt,
    int timeoutSeconds = 30,
    int maxRetries = 2,
    int priority = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final config = AiProviderConfig(
      id: _uuid.v4(),
      name: name,
      apiType: apiType,
      authMode: authMode,
      apiKey: apiKey,
      endpoint: endpoint,
      modelName: modelName,
      temperature: temperature,
      maxTokens: maxTokens,
      systemPrompt: systemPrompt,
      timeoutSeconds: timeoutSeconds,
      maxRetries: maxRetries,
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );

    final db = await _getDatabase();
    await db.insert(
      _tableName,
      config.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _refreshCache();
    AppLogger.info('[AI] Provider added: ${config.name} (${config.id})');
    return config;
  }

  /// Updates an existing provider configuration.
  Future<void> updateProvider(AiProviderConfig config) async {
    final updated = config.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final db = await _getDatabase();
    await db.update(
      _tableName,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [config.id],
    );
    // Dispose old instance so a fresh one is created on next use
    _disposeProvider(config.id);
    await _refreshCache();
    AppLogger.info('[AI] Provider updated: ${config.name} (${config.id})');
  }

  /// Deletes a provider configuration by ID.
  Future<void> deleteProvider(String id) async {
    _disposeProvider(id);
    final db = await _getDatabase();
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
    _healthCache.remove(id);
    await _refreshCache();
    AppLogger.info('[AI] Provider deleted: $id');
  }

  /// Toggles a provider's enabled state.
  Future<void> toggleProvider(String id, {required bool enabled}) async {
    final config = await getProvider(id);
    if (config == null) return;
    await updateProvider(config.copyWith(isEnabled: enabled));
  }

  // ---------------------------------------------------------------------------
  // Chat with fallback
  // ---------------------------------------------------------------------------

  /// Sends a chat request using the highest-priority healthy provider,
  /// falling back to the next provider on failure.
  ///
  /// Returns the response along with the ID of the provider that succeeded.
  /// Throws [AiProviderException] if all providers fail.
  Future<AiChatResult> chat(
    List<AiMessage> messages, {
    String? systemPrompt,
    String? preferredProviderId,
    String? preferredModelName,
  }) async {
    final providers = await _resolveProvidersForRequest(
      preferredProviderId: preferredProviderId,
    );
    if (providers.isEmpty) {
      throw const AiProviderException(
        message: 'No AI providers configured',
        type: AiProviderErrorType.unknown,
      );
    }

    AiProviderException? lastError;

    for (final config in providers) {
      final effectiveModelName = config.id == preferredProviderId
          ? preferredModelName
          : null;
      final health = _healthCache.putIfAbsent(
        config.id,
        () => _ProviderHealth(),
      );
      if (health.isDown) {
        AppLogger.debug(
          '[AI] Skipping down provider: ${config.name} (${config.id})',
        );
        continue;
      }

      try {
        final requestConfig = _buildRequestConfig(
          config,
          modelNameOverride: effectiveModelName,
        );
        final useTemporaryProvider =
            requestConfig.modelName != config.modelName;
        final provider = useTemporaryProvider
            ? _createProvider(requestConfig)
            : _getOrCreateProvider(config);
        try {
          final response = await provider.chat(
            messages,
            systemPrompt: systemPrompt,
          );
          health.recordSuccess();
          return AiChatResult(response: response, providerId: config.id);
        } finally {
          if (useTemporaryProvider) {
            provider.dispose();
          }
        }
      } on AiProviderException catch (e) {
        lastError = e;
        health.recordFailure();
        _healthController.add(config.id);

        AppLogger.warning(
          '[AI] Provider ${config.name} failed (${e.type}): ${e.message}',
        );

        // Don't retry on auth errors — mark provider as needing attention
        if (e.type == AiProviderErrorType.auth) {
          continue;
        }
      }
    }

    throw lastError ??
        const AiProviderException(
          message: 'All providers are unavailable',
          type: AiProviderErrorType.unknown,
        );
  }

  /// Streaming chat: returns the provider ID and a text-delta stream.
  ///
  /// Picks the first healthy enabled provider; does NOT do fallback
  /// mid-stream (the stream must be consumed from one provider).
  Future<AiStreamResult> chatStream(
    List<AiMessage> messages, {
    String? systemPrompt,
    String? preferredProviderId,
    String? preferredModelName,
  }) async {
    final providers = await _resolveProvidersForRequest(
      preferredProviderId: preferredProviderId,
    );
    if (providers.isEmpty) {
      throw const AiProviderException(
        message: 'No AI providers configured',
        type: AiProviderErrorType.unknown,
      );
    }

    AiProviderException? lastError;

    for (final config in providers) {
      final effectiveModelName = config.id == preferredProviderId
          ? preferredModelName
          : null;
      final health = _healthCache.putIfAbsent(
        config.id,
        () => _ProviderHealth(),
      );
      if (health.isDown) continue;

      try {
        final requestConfig = _buildRequestConfig(
          config,
          modelNameOverride: effectiveModelName,
        );
        final useTemporaryProvider =
            requestConfig.modelName != config.modelName;
        final provider = useTemporaryProvider
            ? _createProvider(requestConfig)
            : _getOrCreateProvider(config);
        // Attempt to start the stream (throws before yielding on auth/network errors)
        final rawStream = provider.chatStream(
          messages,
          systemPrompt: systemPrompt,
        );
        final stream = useTemporaryProvider
            ? _streamWithDispose(rawStream, provider)
            : rawStream;
        return AiStreamResult(stream: stream, providerId: config.id);
      } on AiProviderException catch (e) {
        lastError = e;
        health.recordFailure();
        _healthController.add(config.id);
        AppLogger.warning(
          '[AI] Stream provider ${config.name} failed (${e.type}): ${e.message}',
        );
      }
    }

    throw lastError ??
        const AiProviderException(
          message: 'All providers are unavailable',
          type: AiProviderErrorType.unknown,
        );
  }

  /// Tests the connection for a specific provider config.
  Future<bool> testProvider(String id) async {
    final config = await getProvider(id);
    if (config == null) return false;

    try {
      final provider = _getOrCreateProvider(config);
      final ok = await provider.testConnection();
      final health = _healthCache.putIfAbsent(id, () => _ProviderHealth());
      if (ok) {
        health.recordSuccess();
      } else {
        health.recordFailure();
      }
      _healthController.add(id);
      return ok;
    } catch (e) {
      AppLogger.warning('[AI] Test connection failed for $id', error: e);
      return false;
    }
  }

  /// Fetches available models from a provider using temporary credentials.
  ///
  /// This is used by the settings dialog to populate the model dropdown
  /// before the provider is saved.
  Future<List<String>> fetchModels({
    required AiApiType apiType,
    AiProviderAuthMode authMode = AiProviderAuthMode.apiKey,
    required String apiKey,
    required String endpoint,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempConfig = AiProviderConfig(
      id: 'temp_fetch',
      name: 'temp',
      apiType: apiType,
      authMode: authMode,
      apiKey: apiKey,
      endpoint: endpoint,
      modelName: '',
      createdAt: now,
      updatedAt: now,
    );

    AiProvider provider;
    switch (apiType) {
      case AiApiType.openaiCompatible:
        provider = authMode == AiProviderAuthMode.codexOAuth
            ? CodexCliProvider(tempConfig)
            : OpenAiProvider(tempConfig);
        break;
      case AiApiType.anthropic:
        provider = AnthropicProvider(tempConfig);
        break;
    }

    try {
      return await provider.listModels();
    } finally {
      provider.dispose();
    }
  }

  /// Returns `true` if at least one provider is configured and enabled.
  Future<bool> get hasConfiguredProvider async {
    final providers = await getEnabledProviders();
    return providers.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  AiProvider _getOrCreateProvider(AiProviderConfig config) {
    return _providerInstances.putIfAbsent(config.id, () {
      return _createProvider(config);
    });
  }

  AiProvider _createProvider(AiProviderConfig config) {
    switch (config.apiType) {
      case AiApiType.openaiCompatible:
        return config.authMode == AiProviderAuthMode.codexOAuth
            ? CodexCliProvider(config)
            : OpenAiProvider(config);
      case AiApiType.anthropic:
        return AnthropicProvider(config);
    }
  }

  AiProviderConfig _buildRequestConfig(
    AiProviderConfig config, {
    String? modelNameOverride,
  }) {
    final trimmedOverride = modelNameOverride?.trim();
    if (trimmedOverride == null ||
        trimmedOverride.isEmpty ||
        trimmedOverride == config.modelName) {
      return config;
    }
    return config.copyWith(modelName: trimmedOverride);
  }

  Future<List<AiProviderConfig>> _resolveProvidersForRequest({
    String? preferredProviderId,
  }) async {
    final providers = await getEnabledProviders();
    if (preferredProviderId == null || preferredProviderId.isEmpty) {
      return providers;
    }

    final selected = providers
        .where((p) => p.id == preferredProviderId)
        .toList();
    return selected;
  }

  Stream<String> _streamWithDispose(
    Stream<String> stream,
    AiProvider provider,
  ) async* {
    try {
      yield* stream;
    } finally {
      provider.dispose();
    }
  }

  void _disposeProvider(String id) {
    _providerInstances[id]?.dispose();
    _providerInstances.remove(id);
  }

  Future<void> _refreshCache() async {
    final db = await _getDatabase();
    final rows = await db.query(_tableName, orderBy: 'priority ASC');
    _configsCache = rows.map((r) => AiProviderConfig.fromMap(r)).toList();
    _configsLoaded = true;
  }

  /// Disposes all provider instances. Call on app shutdown.
  void dispose() {
    for (final provider in _providerInstances.values) {
      provider.dispose();
    }
    _providerInstances.clear();
    _healthController.close();
  }
}
