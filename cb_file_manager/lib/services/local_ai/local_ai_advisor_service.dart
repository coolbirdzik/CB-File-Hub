import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_ai/local_ai_advisor_model.dart';
import '../../services/disk_cleaner/cleaner_models.dart';
import '../../utils/app_logger.dart';
import 'gguf_llama_cpp_runtime.dart';
import 'litert_lm_runtime.dart';

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
  static const String _modelStorageDirKey = 'local_ai_model_storage_dir';
  static const String _chatGuideShownKey = 'local_ai_chat_guide_shown';

  final _installedModelsController = StreamController<void>.broadcast();

  /// Fires after a model is installed, uninstalled or moved, so open chats can
  /// offer it without being recreated.
  Stream<void> get onInstalledModelsChanged =>
      _installedModelsController.stream;

  /// Allowed range for the configurable context window (in tokens).
  ///
  /// Current LiteRT-LM local models support large context windows. We default
  /// to a comfortable middle ground so typical prompts (system prompt + file
  /// context) fit without exhausting memory on lower-end machines.
  static const int minContextTokens = 1024;
  static const int maxContextTokens = 32768;

  /// The agent's system prompt alone is ~2,000 tokens and one tool page up
  /// to ~3,500, so 4,096 overflowed after the first search. Qwen3.5-4B needs
  /// ~400 MB more at 16K than at 4K; 8K is a safe middle for every catalog
  /// model.
  static const int defaultContextTokens = 8192;

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;
  final http.Client _httpClient;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final LocalAiChatRuntime _chatRuntime;
  final LocalAiChatRuntime _ggufChatRuntime;

  static const List<HuggingFaceModelEntry> _curatedModels = [
    HuggingFaceModelEntry(
      id: 'unsloth/Qwen3.5-4B-GGUF',
      displayName: 'Qwen3.5 4B · Q4_K_M',
      description:
          'Recommended for file tools and Vietnamese chat. '
          'Thinking enabled; needs more memory than 2B. Text only in this app.',
      sizeBytes: 2740937888,
      license: 'Apache 2.0',
      artifactFileName: 'Qwen3.5-4B-Q4_K_M.gguf',
    ),
    HuggingFaceModelEntry(
      id: 'unsloth/Qwen3.5-2B-GGUF',
      displayName: 'Qwen3.5 2B · Q4_K_M',
      description:
          'Compact, direct-answer option for simple file tasks. Download: 1.28 GB. '
          'Tag lookup and multi-step tool requests can be less reliable than 4B.',
      sizeBytes: 1280835840,
      license: 'Apache 2.0',
      artifactFileName: 'Qwen3.5-2B-Q4_K_M.gguf',
    ),
    HuggingFaceModelEntry(
      id: 'unsloth/Qwen3-4B-Instruct-2507-GGUF',
      displayName: 'Qwen3 4B Instruct 2507 · Q4_K_M',
      description:
          'Direct answers without a thinking phase. A multilingual option for '
          'instruction following and file tools when you prefer less waiting.',
      sizeBytes: 2497281120,
      license: 'Apache 2.0',
      artifactFileName: 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    ),
    HuggingFaceModelEntry(
      id: 'unsloth/Qwen3-0.6B-GGUF',
      displayName: 'Qwen3 0.6B GGUF Q4_K_M',
      description:
          'Smallest Qwen download for basic chat. Complex tool workflows are '
          'better suited to the recommended 4B model.',
      sizeBytes: 396705472,
      license: 'Apache 2.0',
      compatible: true,
      artifactFileName: 'Qwen3-0.6B-Q4_K_M.gguf',
    ),
    HuggingFaceModelEntry(
      id: 'ggml-org/Qwen3-1.7B-GGUF',
      displayName: 'Qwen3 1.7B GGUF Q4_K_M',
      description:
          'Previous lightweight Qwen option with thinking and multilingual chat. '
          'Qwen3.5 2B offers direct answers at a similar download size; choose 4B for tools.',
      sizeBytes: 1282439264,
      license: 'Apache 2.0',
      compatible: true,
      artifactFileName: 'Qwen3-1.7B-Q4_K_M.gguf',
    ),
    // LiteRT-LM bundles run on the GPU on phones (OpenCL / Metal) and are the
    // only kind iOS can run. Sizes verified against HF on 2026-10-23.
    HuggingFaceModelEntry(
      id: 'litert-community/gemma-4-E2B-it-litert-lm',
      displayName: 'Gemma 4 E2B',
      description:
          'Recommended on phones: fast on the GPU, follows file tools well and '
          'speaks Vietnamese. Needs about 2 GB of free memory.',
      sizeBytes: 2588147712,
      license: 'Apache 2.0',
      artifactFileName: 'gemma-4-E2B-it.litertlm',
    ),
    HuggingFaceModelEntry(
      id: 'litert-community/gemma-4-E4B-it-litert-lm',
      displayName: 'Gemma 4 E4B',
      description:
          'Stronger Gemma 4 for multi-step tasks; slower, for phones with 8 GB '
          'of RAM or more.',
      sizeBytes: 3659530240,
      license: 'Apache 2.0',
      artifactFileName: 'gemma-4-E4B-it.litertlm',
    ),
    HuggingFaceModelEntry(
      id: 'litert-community/Qwen3-1.7B',
      displayName: 'Qwen3 1.7B',
      description:
          'Light LiteRT-LM model for older phones. Simple searches work; '
          'multi-step tool requests are less reliable than Gemma 4.',
      sizeBytes: 977184032,
      license: 'Apache 2.0',
      artifactFileName: 'Qwen3-1.7B_dynamic_wi4b32_afp32.litertlm',
    ),
    HuggingFaceModelEntry(
      id: 'litert-community/Qwen3.5-0.8B',
      displayName: 'Qwen3.5 0.8B',
      description:
          'Smallest download for basic chat on low-memory phones. Not suited '
          'to file tool workflows.',
      sizeBytes: 964566992,
      license: 'Apache 2.0',
      artifactFileName: 'Qwen3.5-0.8B_int8.litertlm',
    ),
    // Artifact names/sizes verified against HF on 2026-09-06. Selection notes:
    // docs/research/2026-09-06-small-local-agent-models.md (workspace root).
  ];

  LocalAiAdvisorService({
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    Future<Directory> Function()? documentsDirectoryProvider,
    LocalAiChatRuntime? chatRuntime,
    LocalAiChatRuntime? ggufChatRuntime,
    required this._prefs,
  }) : _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           ),
       _httpClient = httpClient ?? http.Client(),
       _chatRuntime = chatRuntime ?? LiteRtLmLocalAiChatRuntime(),
       _ggufChatRuntime = ggufChatRuntime ?? GgufLlamaCppLocalAiChatRuntime(),
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  /// Models offered on this platform. iOS cannot start llama-server, so it
  /// gets LiteRT-LM bundles only; Android lists them before its CPU-only GGUF.
  static List<HuggingFaceModelEntry> get _curatedCatalog {
    if (!(Platform.isAndroid || Platform.isIOS)) return _curatedModels;
    bool liteRt(HuggingFaceModelEntry e) =>
        e.artifactFileName.endsWith('.litertlm');
    return [
      ..._curatedModels.where(liteRt),
      if (Platform.isAndroid) ..._curatedModels.where((e) => !liteRt(e)),
    ];
  }

  /// Windows uses bundled llama.cpp; LiteRT-LM (GPU) everywhere else.
  HuggingFaceModelEntry get pinnedModel => _curatedCatalog.firstWhere(
    (model) =>
        model.compatible &&
        model.artifactFileName.endsWith(
          Platform.isWindows ? '.gguf' : '.litertlm',
        ),
  );

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
  /// Always includes curated local agent recommendations at the top.
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
    String? token,
  ) async {
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
      ..._curatedCatalog,
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
          .map(
            (e) => _normalizeInstalledModelPath(
              InstalledLocalModel.fromJson(e as Map<String, dynamic>),
            ),
          )
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
    // Normalize based on the path's own shape rather than the host OS so
    // legacy metadata written on a different platform (and tests running on a
    // non-Windows CI) resolve deterministically. A drive-letter prefix or any
    // backslash marks a Windows path.
    final looksWindows =
        RegExp(r'^[A-Za-z]:').hasMatch(path) || path.contains(r'\');
    if (Platform.isWindows || looksWindows) {
      return path.replaceAll('/', r'\');
    }
    return path.replaceAll(r'\', '/');
  }

  /// Returns the currently selected (active) model, or null.
  InstalledLocalModel? getSelectedModel() {
    final id = _prefs.getString(_selectedModelIdKey);
    if (id == null) return null;
    return getInstalledModels().cast<InstalledLocalModel?>().firstWhere(
      (m) => m?.catalogId == id,
      orElse: () => null,
    );
  }

  /// Whether CB Agent has already shown its local-model setup guide.
  bool get chatGuideShown => _prefs.getBool(_chatGuideShownKey) ?? false;

  Future<void> markChatGuideShown() => _prefs.setBool(_chatGuideShownKey, true);

  /// Marks a model as the active model for inference.
  Future<void> setSelectedModel(String catalogId) async {
    await _prefs.setString(_selectedModelIdKey, catalogId);
    final model = getSelectedModel();
    if (model != null) {
      // Settings and the chat picker must restore the same explicit choice.
      await _prefs.setString('ai_chat_last_provider_id', '__local_ai__');
      await _prefs.setString('ai_chat_last_model_name', model.displayName);
    }
    AppLogger.info('[LocalAI] Selected model: $catalogId');
  }

  /// The folder the user picked for new model downloads, or null when the
  /// default location is used.
  String? getCustomModelStorageDirectory() {
    final stored = _prefs.getString(_modelStorageDirKey);
    if (stored == null || stored.trim().isEmpty) return null;
    return _normalizeLocalPath(stored);
  }

  /// Folder that new downloads are saved into: the user's choice, otherwise
  /// `<Documents>/local_ai_models`. Installed models keep their own path.
  Future<String> getModelStorageDirectory() async {
    final custom = getCustomModelStorageDirectory();
    if (custom != null) return custom;
    final dir = await _documentsDirectoryProvider();
    return _normalizeLocalPath(
      '${dir.path}${Platform.pathSeparator}local_ai_models',
    );
  }

  /// Sets the folder for new model downloads; null restores the default.
  ///
  /// Throws a [FileSystemException] when the folder cannot be written, so a
  /// read-only or sandboxed pick fails here instead of mid-download.
  Future<void> setModelStorageDirectory(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs.remove(_modelStorageDirKey);
      AppLogger.info('[LocalAI] Model storage reset to default');
      return;
    }

    final normalized = _normalizeLocalPath(path.trim());
    final dir = Directory(normalized);
    await dir.create(recursive: true);
    final probe = File(
      '${dir.path}${Platform.pathSeparator}.cb_write_test_${DateTime.now().microsecondsSinceEpoch}',
    );
    await probe.writeAsString('');
    await probe.delete();

    await _prefs.setString(_modelStorageDirKey, normalized);
    AppLogger.info('[LocalAI] Model storage set to $normalized');
  }

  /// Installed models whose file exists but lies outside the current storage
  /// folder, i.e. the ones [moveInstalledModelsToStorage] would move.
  Future<List<InstalledLocalModel>> modelsOutsideStorage() async {
    final storageDir = await getModelStorageDirectory();
    final result = <InstalledLocalModel>[];
    for (final model in getInstalledModels()) {
      if (_samePath(model.localPath, _storagePathFor(storageDir, model))) {
        continue;
      }
      if (await File(model.localPath).exists()) result.add(model);
    }
    return result;
  }

  /// Moves every installed model into the current storage folder and updates
  /// its metadata as soon as it lands, so a failure part-way leaves each model
  /// usable at exactly one recorded path.
  ///
  /// A same-volume move is a rename; across volumes the file is copied with
  /// progress and the original deleted afterwards.
  Future<void> moveInstalledModelsToStorage({
    required void Function(ModelMoveProgress) onProgress,
  }) async {
    final storageDir = await getModelStorageDirectory();
    final pending = await modelsOutsideStorage();
    final sizes = <String, int>{
      for (final model in pending)
        model.catalogId: await File(model.localPath).length(),
    };
    final totalBytes = sizes.values.fold<int>(0, (sum, size) => sum + size);
    var movedBytes = 0;

    void report(int movedModels, String? currentName, int bytes) {
      onProgress(
        ModelMoveProgress(
          currentModelName: currentName,
          movedModels: movedModels,
          totalModels: pending.length,
          movedBytes: bytes,
          totalBytes: totalBytes,
        ),
      );
    }

    if (pending.isEmpty) {
      report(0, null, 0);
      return;
    }

    // llama-server keeps the GGUF open, which blocks rename/delete on Windows.
    for (final runtime in [_ggufChatRuntime, _chatRuntime]) {
      if (runtime is LocalAiModelFileHolder) {
        await (runtime as LocalAiModelFileHolder).releaseModelFiles();
      }
    }

    for (var i = 0; i < pending.length; i++) {
      final model = pending[i];
      final destination = _storagePathFor(storageDir, model);
      final baseBytes = movedBytes;
      report(i, model.displayName, baseBytes);

      AppLogger.info('[LocalAI] Moving ${model.catalogId} to $destination');
      await _moveModelFile(
        model.localPath,
        destination,
        onBytes: (bytes) => report(i, model.displayName, baseBytes + bytes),
      );
      movedBytes += sizes[model.catalogId]!;

      final models = getInstalledModels();
      final index = models.indexWhere((m) => m.catalogId == model.catalogId);
      if (index >= 0) {
        models[index] = InstalledLocalModel(
          catalogId: model.catalogId,
          displayName: model.displayName,
          localPath: destination,
          sizeBytes: model.sizeBytes,
          installedAt: model.installedAt,
          runtimeArtifactId: model.runtimeArtifactId,
        );
        await _saveInstalledModels(models);
      }
      await _deleteIfEmpty(File(model.localPath).parent);
    }

    report(pending.length, null, movedBytes);
    AppLogger.info('[LocalAI] Moved ${pending.length} model(s) to $storageDir');
  }

  String _storagePathFor(String storageDir, InstalledLocalModel model) {
    final fileName = model.localPath.split(RegExp(r'[\\/]')).last;
    return _normalizeLocalPath(
      '$storageDir${Platform.pathSeparator}'
      '${model.catalogId.replaceAll('/', '_')}'
      '${Platform.pathSeparator}$fileName',
    );
  }

  bool _samePath(String a, String b) {
    final left = _normalizeLocalPath(a);
    final right = _normalizeLocalPath(b);
    return Platform.isWindows
        ? left.toLowerCase() == right.toLowerCase()
        : left == right;
  }

  Future<void> _moveModelFile(
    String sourcePath,
    String destinationPath, {
    required void Function(int bytes) onBytes,
  }) async {
    final source = File(sourcePath);
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    if (await destination.exists()) {
      await destination.delete();
    }

    try {
      await source.rename(destinationPath);
      onBytes(await destination.length());
      return;
    } on FileSystemException {
      // Different volume (or a transient lock): fall back to copy + delete.
    }

    final temp = File('$destinationPath.part');
    final sink = temp.openWrite();
    var copied = 0;
    var lastReported = 0;
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        copied += chunk.length;
        // Per-chunk callbacks would rebuild the dialog thousands of times.
        if (copied - lastReported >= 8 * 1024 * 1024) {
          lastReported = copied;
          onBytes(copied);
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
    await temp.rename(destinationPath);
    onBytes(copied);

    try {
      await source.delete();
    } catch (e) {
      // The copy is complete and becomes the recorded path; a leftover
      // original only costs disk space.
      AppLogger.warning(
        '[LocalAI] Moved model but could not delete $sourcePath',
        error: e,
      );
    }
  }

  Future<void> _deleteIfEmpty(Directory dir) async {
    try {
      if (await dir.exists() && await dir.list().isEmpty) {
        await dir.delete();
      }
    } catch (_) {
      // Best effort: an empty leftover folder is harmless.
    }
  }

  /// Downloads and installs a model artifact from Hugging Face.
  ///
  /// HF token is only required for private/gated models.
  ///
  /// When [isCancelled] turns true the partial download is deleted and
  /// [LocalModelDownloadCancelled] is thrown.
  Future<InstalledLocalModel> installModel(
    HuggingFaceModelEntry entry, {
    required void Function(ModelDownloadProgress) onProgress,
    bool Function()? isCancelled,
  }) async {
    AppLogger.info('[LocalAI] Installing model: ${entry.id}');

    final storageDir = await getModelStorageDirectory();
    final modelDir = Directory(
      _normalizeLocalPath(
        '$storageDir${Platform.pathSeparator}${entry.id.replaceAll('/', '_')}',
      ),
    );
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

    onProgress(
      ModelDownloadProgress(
        catalogId: entry.id,
        downloadedBytes: 0,
        totalBytes: totalBytes,
        state: LocalModelDownloadState.downloading,
      ),
    );

    try {
      await for (final chunk in response.stream) {
        if (isCancelled?.call() ?? false) {
          throw const LocalModelDownloadCancelled();
        }
        downloadedBytes += chunk.length;
        sink.add(chunk);
        onProgress(
          ModelDownloadProgress(
            catalogId: entry.id,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            state: LocalModelDownloadState.downloading,
          ),
        );
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

    onProgress(
      ModelDownloadProgress(
        catalogId: entry.id,
        downloadedBytes: installedSize,
        totalBytes: totalBytes > 0 ? totalBytes : installedSize,
        state: LocalModelDownloadState.completed,
      ),
    );

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
      _installedModelsController.add(null);
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
  Future<List<AdvisorSuggestion>> requestAdvisory(List<JunkItem> items) async {
    final model = getSelectedModel();
    if (model == null) {
      AppLogger.debug('[LocalAI] No model selected; skipping advisory');
      return [];
    }

    AppLogger.info(
      '[LocalAI] Requesting advisory for ${items.length} item(s) with model ${model.catalogId}',
    );

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
    List<Map<String, String>>? messages,
    bool directResponse = false,
  }) async* {
    final model = getSelectedModel();
    if (model == null) {
      throw StateError('No local AI model is selected.');
    }

    final runtime = model.runtimeKind == LocalModelRuntimeKind.llamaCpp
        ? _ggufChatRuntime
        : _chatRuntime;

    if (directResponse &&
        messages != null &&
        runtime is LocalAiDirectConversationRuntime) {
      yield* (runtime as LocalAiDirectConversationRuntime)
          .sendDirectConversationStream(
            model: model,
            messages: messages,
            systemPrompt: systemPrompt,
            maxTokens: getMaxContextTokens(),
          );
      return;
    }
    if (messages != null && runtime is LocalAiConversationRuntime) {
      yield* (runtime as LocalAiConversationRuntime).sendConversationStream(
        model: model,
        messages: messages,
        systemPrompt: systemPrompt,
        maxTokens: getMaxContextTokens(),
      );
      return;
    }

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
    await _installedModelsController.close();
    await _ggufChatRuntime.dispose();
    await _chatRuntime.dispose();
  }
}

/// Thrown by [LocalAiAdvisorService.installModel] when its download is
/// cancelled.
class LocalModelDownloadCancelled implements Exception {
  const LocalModelDownloadCancelled();

  @override
  String toString() => 'Model download cancelled.';
}
