import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_ai/local_ai_advisor_model.dart';
import '../../services/disk_cleaner/cleaner_models.dart';
import '../../utils/app_logger.dart';
import 'gguf_llama_cpp_runtime.dart';

/// Manages local AI advisor state: HF token storage, model catalog caching,
/// model downloads, and on-device advisory inference.
///
/// Keeps token in secure storage, catalog and installed-model metadata in
/// SharedPreferences, and delegates inference to a runtime adapter.
class LocalAiAdvisorService {
  static const String _hfTokenKey = 'local_ai_hf_token';
  static const String _catalogCacheKey = 'local_ai_catalog_cache';
  static const String _installedModelsKey = 'local_ai_installed_models';
  static const String _selectedModelIdKey = 'local_ai_selected_model_id';
  static const String _maxTokensKey = 'local_ai_max_tokens';

  /// Allowed range for the configurable context window (in tokens).
  ///
  /// Current LiteRT-LM local models support large context windows. We default
  /// to a comfortable middle ground so typical prompts (system prompt + file
  /// context) fit without exhausting memory on lower-end machines.
  static const int minContextTokens = 1024;
  static const int maxContextTokens = 32768;
  static const int defaultContextTokens = 4096;

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;
  final http.Client _httpClient;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final LocalAiChatRuntime _chatRuntime;
  final LocalAiChatRuntime _ggufChatRuntime;

  static const List<HuggingFaceModelEntry> _curatedModels = [
    HuggingFaceModelEntry(
      id: 'litert-community/functiongemma-270m-ft-mobile-actions',
      displayName: 'FunctionGemma 270M Mobile Actions',
      description:
          'Very small LiteRT-LM model tuned for mobile action/function calling. Best used as a local tool router.',
      sizeBytes: 289 * 1024 * 1024,
      license: 'Gemma',
      compatible: true,
      artifactFileName: 'mobile_actions_q8_ekv1024.litertlm',
    ),
    HuggingFaceModelEntry(
      id: 'unsloth/Qwen3-0.6B-GGUF',
      displayName: 'Qwen3 0.6B GGUF Q4_K_M',
      description:
          'Lightweight Qwen3 tool-use/chat model. Runs via llama.cpp on CPU.',
      sizeBytes: 396705472,
      license: 'Apache 2.0',
      compatible: true,
      artifactFileName: 'Qwen3-0.6B-Q4_K_M.gguf',
    ),
    HuggingFaceModelEntry(
      id: 'ggml-org/Qwen3-1.7B-GGUF',
      displayName: 'Qwen3 1.7B GGUF Q4_K_M',
      description:
          'Better agent/tool-call quality than 0.6B while still lightweight when quantized. Runs via llama.cpp on CPU.',
      sizeBytes: 1282439264,
      license: 'Apache 2.0',
      compatible: true,
      artifactFileName: 'Qwen3-1.7B-Q4_K_M.gguf',
    ),
  ];

  LocalAiAdvisorService({
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    Future<Directory> Function()? documentsDirectoryProvider,
    LocalAiChatRuntime? chatRuntime,
    LocalAiChatRuntime? ggufChatRuntime,
    required SharedPreferences prefs,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _prefs = prefs,
        _httpClient = httpClient ?? http.Client(),
        _chatRuntime = chatRuntime ?? const GemmaLiteRtLocalAiChatRuntime(),
        _ggufChatRuntime = ggufChatRuntime ?? GgufLlamaCppLocalAiChatRuntime(),
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  /// The recommended model that can run in the current LiteRT-LM runtime.
  HuggingFaceModelEntry get pinnedModel =>
      _curatedModels.firstWhere((model) => model.compatible);

  /// Returns the catalog entry matching [catalogId], or the pinned entry's
  /// match, falling back to null when unknown.
  HuggingFaceModelEntry? catalogEntryFor(String catalogId) {
    for (final entry in _curatedModels) {
      if (entry.id == catalogId) return entry;
    }
    for (final entry in _getCachedCatalog()) {
      if (entry.id == catalogId) return entry;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // HF Token management (secure storage)
  // ---------------------------------------------------------------------------

  /// Returns the stored Hugging Face token, or null if none is set.
  Future<String?> getHuggingFaceToken() async {
    try {
      return await _secureStorage.read(key: _hfTokenKey);
    } catch (e) {
      AppLogger.warning('[LocalAI] Failed to read HF token', error: e);
      return null;
    }
  }

  /// Stores the Hugging Face token securely.
  Future<void> setHuggingFaceToken(String token) async {
    try {
      await _secureStorage.write(key: _hfTokenKey, value: token);
      AppLogger.info('[LocalAI] HF token stored securely');
    } catch (e) {
      AppLogger.error('[LocalAI] Failed to store HF token', error: e);
      rethrow;
    }
  }

  /// Clears the stored Hugging Face token.
  Future<void> clearHuggingFaceToken() async {
    try {
      await _secureStorage.delete(key: _hfTokenKey);
      AppLogger.info('[LocalAI] HF token cleared');
    } catch (e) {
      AppLogger.warning('[LocalAI] Failed to clear HF token', error: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Model catalog (cached in SharedPreferences)
  // ---------------------------------------------------------------------------

  /// Fetches the model catalog from Hugging Face API, or returns cached results.
  ///
  /// Always includes curated mobile/tool-call recommendations at the top.
  /// For public models, API token is optional.
  Future<List<HuggingFaceModelEntry>> fetchModelCatalog({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _getCachedCatalog();
      if (cached.isNotEmpty) {
        return _mergeCuratedCatalog(cached);
      }
    }

    final token = await getHuggingFaceToken();
    // Token is optional for public models - we can still browse and download

    try {
      final fetched = await _fetchFromHuggingFace(token);
      await _cacheCatalog(fetched);
      return _mergeCuratedCatalog(fetched);
    } catch (e) {
      AppLogger.error('[LocalAI] Failed to fetch HF catalog', error: e);
      // Fall back to cached + curated recommendations.
      final cached = _getCachedCatalog();
      return _mergeCuratedCatalog(cached);
    }
  }

  Future<List<HuggingFaceModelEntry>> _fetchFromHuggingFace(
      String? token) async {
    // Stub: In a real implementation, query https://huggingface.co/api/models
    // with filters for compatible mobile/local agent artifacts.
    // Token is optional for public models - pass it in Authorization header if available.
    //
    // For now, return an empty list so curated recommendations are stable.
    AppLogger.debug('[LocalAI] HF API fetch stub (returns empty)');
    return [];
  }

  List<HuggingFaceModelEntry> _mergeCuratedCatalog(
    List<HuggingFaceModelEntry> entries,
  ) {
    final curatedIds = _curatedModels.map((entry) => entry.id).toSet();
    return [
      ..._curatedModels,
      ...entries.where((entry) => !curatedIds.contains(entry.id)),
    ];
  }

  List<HuggingFaceModelEntry> _getCachedCatalog() {
    final json = _prefs.getString(_catalogCacheKey);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => HuggingFaceModelEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.warning('[LocalAI] Failed to parse cached catalog', error: e);
      return [];
    }
  }

  Future<void> _cacheCatalog(List<HuggingFaceModelEntry> entries) async {
    try {
      final json = jsonEncode(entries.map((e) => e.toJson()).toList());
      await _prefs.setString(_catalogCacheKey, json);
    } catch (e) {
      AppLogger.warning('[LocalAI] Failed to cache catalog', error: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Installed models (persisted in SharedPreferences)
  // ---------------------------------------------------------------------------

  /// Returns the list of locally installed models.
  List<InstalledLocalModel> getInstalledModels() {
    final json = _prefs.getString(_installedModelsKey);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => _normalizeInstalledModelPath(
                InstalledLocalModel.fromJson(e as Map<String, dynamic>),
              ))
          .toList();
    } catch (e) {
      AppLogger.warning('[LocalAI] Failed to parse installed models', error: e);
      return [];
    }
  }

  InstalledLocalModel _normalizeInstalledModelPath(InstalledLocalModel model) {
    final normalizedPath = _normalizeLocalPath(model.localPath);
    if (normalizedPath == model.localPath) return model;

    return InstalledLocalModel(
      catalogId: model.catalogId,
      displayName: model.displayName,
      localPath: normalizedPath,
      sizeBytes: model.sizeBytes,
      installedAt: model.installedAt,
      runtimeArtifactId: model.runtimeArtifactId,
    );
  }

  String _normalizeLocalPath(String path) {
    if (Platform.isWindows) {
      return path.replaceAll('/', r'\');
    }
    return path.replaceAll(r'\', Platform.pathSeparator);
  }

  /// Returns the currently selected (active) model, or null.
  InstalledLocalModel? getSelectedModel() {
    final id = _prefs.getString(_selectedModelIdKey);
    if (id == null) return null;
    return getInstalledModels()
        .cast<InstalledLocalModel?>()
        .firstWhere((m) => m?.catalogId == id, orElse: () => null);
  }

  /// Marks a model as the active model for inference.
  Future<void> setSelectedModel(String catalogId) async {
    await _prefs.setString(_selectedModelIdKey, catalogId);
    AppLogger.info('[LocalAI] Selected model: $catalogId');
  }

  /// Downloads and installs a model artifact from Hugging Face.
  ///
  /// HF token is only required for private/gated models.
  Future<InstalledLocalModel> installModel(
    HuggingFaceModelEntry entry, {
    required void Function(ModelDownloadProgress) onProgress,
  }) async {
    AppLogger.info('[LocalAI] Installing model: ${entry.id}');

    final dir = await _documentsDirectoryProvider();
    final modelDir = Directory(_normalizeLocalPath(
      '${dir.path}${Platform.pathSeparator}local_ai_models'
      '${Platform.pathSeparator}${entry.id.replaceAll('/', '_')}',
    ));
    await modelDir.create(recursive: true);

    final modelPath = _normalizeLocalPath(
      '${modelDir.path}${Platform.pathSeparator}${entry.artifactFileName}',
    );
    final tempPath = '$modelPath.part';

    final token = await getHuggingFaceToken();
    final uri = _artifactUri(entry);
    final request = http.Request('GET', uri)
      ..followRedirects = true
      ..headers['Accept'] = 'application/octet-stream';
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw HttpException(
        'Hugging Face download failed (${response.statusCode}) for $uri',
        uri: uri,
      );
    }

    final totalBytes = response.contentLength ?? entry.sizeBytes ?? 0;
    var downloadedBytes = 0;
    final tempFile = File(tempPath);
    final sink = tempFile.openWrite();

    onProgress(ModelDownloadProgress(
      catalogId: entry.id,
      downloadedBytes: 0,
      totalBytes: totalBytes,
      state: LocalModelDownloadState.downloading,
    ));

    try {
      await for (final chunk in response.stream) {
        downloadedBytes += chunk.length;
        sink.add(chunk);
        onProgress(ModelDownloadProgress(
          catalogId: entry.id,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
          state: LocalModelDownloadState.downloading,
        ));
      }
    } catch (_) {
      await sink.close();
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }

    await sink.close();

    final modelFile = File(modelPath);
    if (await modelFile.exists()) {
      await modelFile.delete();
    }
    await tempFile.rename(modelPath);

    final installedSize = await File(modelPath).length();

    final installed = InstalledLocalModel(
      catalogId: entry.id,
      displayName: entry.displayName,
      localPath: modelPath,
      sizeBytes: installedSize,
      installedAt: DateTime.now(),
      runtimeArtifactId: entry.artifactFileName,
    );

    final current = getInstalledModels();
    current.add(installed);
    await _saveInstalledModels(current);

    // Auto-select if this is the first model
    if (getSelectedModel() == null) {
      await setSelectedModel(entry.id);
    }

    onProgress(ModelDownloadProgress(
      catalogId: entry.id,
      downloadedBytes: installedSize,
      totalBytes: totalBytes > 0 ? totalBytes : installedSize,
      state: LocalModelDownloadState.completed,
    ));

    AppLogger.info('[LocalAI] Model installed: ${entry.id}');
    return installed;
  }

  Uri _artifactUri(HuggingFaceModelEntry entry) {
    return Uri.https(
      'huggingface.co',
      '/${entry.id}/resolve/main/${entry.artifactFileName}',
      const {'download': 'true'},
    );
  }

  /// Uninstalls a model (removes local files and metadata).
  Future<void> uninstallModel(String catalogId) async {
    final models = getInstalledModels();
    final target = models.cast<InstalledLocalModel?>().firstWhere(
          (m) => m?.catalogId == catalogId,
          orElse: () => null,
        );

    if (target == null) {
      AppLogger.warning('[LocalAI] Model not found for uninstall: $catalogId');
      return;
    }

    // Remove file (stub)
    try {
      final file = File(target.localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      AppLogger.warning('[LocalAI] Failed to delete model file', error: e);
    }

    // Remove from metadata
    models.removeWhere((m) => m.catalogId == catalogId);
    await _saveInstalledModels(models);

    // Clear selection if this was the active model
    if (getSelectedModel()?.catalogId == catalogId) {
      await _prefs.remove(_selectedModelIdKey);
    }

    AppLogger.info('[LocalAI] Model uninstalled: $catalogId');
  }

  Future<void> _saveInstalledModels(List<InstalledLocalModel> models) async {
    try {
      final json = jsonEncode(models.map((m) => m.toJson()).toList());
      await _prefs.setString(_installedModelsKey, json);
    } catch (e) {
      AppLogger.error('[LocalAI] Failed to save installed models', error: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Advisory inference (runtime adapter boundary)
  // ---------------------------------------------------------------------------

  /// Requests cleanup suggestions for the given junk items.
  ///
  /// Returns a list of advisory suggestions. Each suggestion is validated
  /// against the Disk Cleaner safety rules before it can affect the UI.
  ///
  /// If no model is installed or the runtime is unavailable, returns an empty list.
  Future<List<AdvisorSuggestion>> requestAdvisory(
    List<JunkItem> items,
  ) async {
    final model = getSelectedModel();
    if (model == null) {
      AppLogger.debug('[LocalAI] No model selected; skipping advisory');
      return [];
    }

    AppLogger.info(
        '[LocalAI] Requesting advisory for ${items.length} item(s) with model ${model.catalogId}');

    // Stub: In a real implementation, serialize items to JSON, invoke the
    // runtime adapter (for example a LiteRT-LM binding), parse structured output,
    // and validate every suggested path against CleanerPathSafety.
    //
    // For now, return an empty list (no-op advisory).
    return [];
  }

  /// Sends a chat message to the selected local model.
  Future<String> sendChatMessage({
    required String message,
    String? systemPrompt,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in sendChatMessageStream(
      message: message,
      systemPrompt: systemPrompt,
    )) {
      buffer.write(chunk);
    }
    return buffer.toString().trim();
  }

  /// Streams a chat response from the selected local model.
  Stream<String> sendChatMessageStream({
    required String message,
    String? systemPrompt,
  }) async* {
    final model = getSelectedModel();
    if (model == null) {
      throw StateError('No local AI model is selected.');
    }

    final runtime = model.runtimeKind == LocalModelRuntimeKind.llamaCpp
        ? _ggufChatRuntime
        : _chatRuntime;

    yield* runtime.sendMessageStream(
      model: model,
      message: message,
      systemPrompt: systemPrompt,
      maxTokens: getMaxContextTokens(),
    );
  }

  /// Returns the configured context window (in tokens), clamped to the
  /// supported range. Falls back to [defaultContextTokens] when unset.
  int getMaxContextTokens() {
    final stored = _prefs.getInt(_maxTokensKey) ?? defaultContextTokens;
    return stored.clamp(minContextTokens, maxContextTokens);
  }

  /// Persists the desired context window (in tokens), clamped to range.
  Future<void> setMaxContextTokens(int tokens) async {
    final clamped = tokens.clamp(minContextTokens, maxContextTokens);
    await _prefs.setInt(_maxTokensKey, clamped);
    AppLogger.info('[LocalAI] Context window set to $clamped tokens');
  }

  /// Releases both chat runtimes. Must be called on app shutdown so any
  /// spawned llama-server.exe child process is terminated instead of leaking.
  Future<void> dispose() async {
    await _ggufChatRuntime.dispose();
    await _chatRuntime.dispose();
  }
}

/// Local chat runtime backed by Flutter Gemma + LiteRT-LM.
class GemmaLiteRtLocalAiChatRuntime implements LocalAiChatRuntime {
  static Future<void>? _initialization;

  const GemmaLiteRtLocalAiChatRuntime();

  @override
  Future<void> dispose() async {
    // LiteRT-LM models are loaded and closed per request, so there is no
    // long-lived resource to release here.
  }

  @override
  Future<String> sendMessage({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in sendMessageStream(
      model: model,
      message: message,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
    )) {
      buffer.write(chunk);
    }
    return buffer.toString().trim();
  }

  @override
  Stream<String> sendMessageStream({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  }) async* {
    final file = File(model.localPath);
    if (!await file.exists()) {
      throw FileSystemException('Local model file not found', model.localPath);
    }
    if (!model.localPath.toLowerCase().endsWith('.litertlm')) {
      throw UnsupportedError(
        'The installed model artifact is ${model.runtimeArtifactId ?? model.localPath}. '
        'Local CB Agent chat requires a .litertlm model artifact.',
      );
    }

    await _ensureInitialized();
    await gemma.FlutterGemma.installModel(
      modelType: gemma.ModelType.gemma4,
      fileType: gemma.ModelFileType.litertlm,
    ).fromFile(model.localPath).install();

    final inferenceModel = await gemma.FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      maxConcurrentSessions: 1,
    );

    try {
      final chat = await inferenceModel.createChat(
        temperature: 0.3,
        topK: 64,
        topP: 0.95,
        modelType: gemma.ModelType.gemma4,
        systemInstruction: systemPrompt,
        supportsFunctionCalls: false,
      );
      await chat.addQueryChunk(gemma.Message.text(
        text: message,
        isUser: true,
      ));
      await for (final response in chat.generateChatResponseAsync()) {
        final text = _responseToText(response);
        if (text.isNotEmpty) yield text;
      }
    } finally {
      await inferenceModel.close();
    }
  }

  static Future<void> _ensureInitialized() {
    return _initialization ??= gemma.FlutterGemma.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
    );
  }

  String _responseToText(gemma.ModelResponse response) {
    if (response is gemma.TextResponse) {
      return response.token;
    }
    if (response is gemma.ThinkingResponse) {
      return response.content;
    }
    if (response is gemma.FunctionCallResponse) {
      return jsonEncode({'name': response.name, 'arguments': response.args});
    }
    if (response is gemma.ParallelFunctionCallResponse) {
      return jsonEncode(response.calls
          .map((call) => {'name': call.name, 'arguments': call.args})
          .toList());
    }
    return '';
  }
}
