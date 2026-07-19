import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalAiAdvisorService', () {
    late LocalAiAdvisorService service;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = LocalAiAdvisorService(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
    });

    test('14.01 fetches curated mobile tool-call models by default', () async {
      final catalog = await service.fetchModelCatalog();
      expect(catalog, isNotEmpty);
      expect(catalog.first.id,
          'litert-community/functiongemma-270m-ft-mobile-actions');
      expect(
          catalog.first.artifactFileName, 'mobile_actions_q8_ekv1024.litertlm');
      expect(catalog.first.compatible, isTrue);
      expect(catalog.any((entry) => entry.id.contains('gemma-4')), isFalse);
      expect(
        catalog.any((entry) =>
            entry.id == 'unsloth/Qwen3-0.6B-GGUF' && entry.compatible == true),
        isTrue,
      );
    });

    test('14.02 returns empty installed models list initially', () {
      final installed = service.getInstalledModels();
      expect(installed, isEmpty);
    });

    test('14.03 selected model is null when none installed', () {
      final selected = service.getSelectedModel();
      expect(selected, isNull);
    });

    test('14.04 returns empty advisory when no model selected', () async {
      final suggestions = await service.requestAdvisory([]);
      expect(suggestions, isEmpty);
    });

    test('14.05 persists and retrieves installed model metadata', () async {
      final model = InstalledLocalModel(
        catalogId: 'test/model',
        displayName: 'Test Model',
        localPath: '/fake/path/model.bin',
        sizeBytes: 1000000,
        installedAt: DateTime.now(),
        runtimeArtifactId: 'test_artifact',
      );

      // Manually persist via prefs for testing
      await prefs.setString(
        'local_ai_installed_models',
        '[${_modelToJsonString(model)}]',
      );

      final installed = service.getInstalledModels();
      expect(installed, hasLength(1));
      expect(installed.first.catalogId, model.catalogId);
      expect(installed.first.displayName, model.displayName);
    });

    test('14.06 selects and retrieves active model', () async {
      final model = InstalledLocalModel(
        catalogId: 'test/model-active',
        displayName: 'Active Model',
        localPath: '/fake/path/active.bin',
        sizeBytes: 2000000,
        installedAt: DateTime.now(),
      );

      await prefs.setString(
        'local_ai_installed_models',
        '[${_modelToJsonString(model)}]',
      );

      await service.setSelectedModel(model.catalogId);

      final selected = service.getSelectedModel();
      expect(selected, isNotNull);
      expect(selected!.catalogId, model.catalogId);
    });

    test('14.07 normalizes legacy mixed separators on Windows', () async {
      final model = InstalledLocalModel(
        catalogId: 'test/model-legacy-path',
        displayName: 'Legacy Path Model',
        localPath: r'C:\Users\tester\Documents/local_ai_models/model.bin',
        sizeBytes: 3000000,
        installedAt: DateTime.now(),
      );

      await prefs.setString(
        'local_ai_installed_models',
        '[${_modelToJsonString(model)}]',
      );

      final installed = service.getInstalledModels();
      expect(installed, hasLength(1));
      expect(installed.first.localPath, isNot(contains('/')));
      expect(installed.first.localPath, contains(r'\local_ai_models\'));
    });

    test('14.08 downloads model artifact and persists real file metadata',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('local_ai_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final chunks = <List<int>>[
        utf8.encode('abc'),
        utf8.encode('defg'),
        utf8.encode('hi'),
      ];
      final client = _FakeDownloadClient(chunks: chunks);
      service = LocalAiAdvisorService(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
        httpClient: client,
        documentsDirectoryProvider: () async => tempDir,
      );

      const entry = HuggingFaceModelEntry(
        id: 'test/model-download',
        displayName: 'Download Model',
        artifactFileName: 'model.safetensors',
      );
      final progressUpdates = <ModelDownloadProgress>[];

      final installed = await service.installModel(
        entry,
        onProgress: progressUpdates.add,
      );

      final installedFile = File(installed.localPath);
      expect(await installedFile.exists(), isTrue);
      expect(await installedFile.readAsString(), 'abcdefghi');
      expect(installed.sizeBytes, 9);
      expect(installed.runtimeArtifactId, 'model.safetensors');
      expect(progressUpdates, isNotEmpty);
      expect(progressUpdates.last.state, LocalModelDownloadState.completed);
      expect(progressUpdates.last.downloadedBytes, 9);

      final models = service.getInstalledModels();
      expect(models, hasLength(1));
      expect(models.first.localPath, installed.localPath);
    });

    test(
        '14.09 flags .safetensors artifacts as not runnable, allows .litertlm and .gguf',
        () {
      final safetensors = InstalledLocalModel(
        catalogId: 'legacy/model',
        displayName: 'Legacy',
        localPath: r'C:\models\model.safetensors',
        sizeBytes: 10,
        installedAt: DateTime.now(),
      );
      final litertlm = InstalledLocalModel(
        catalogId: 'litert/model',
        displayName: 'LiteRT',
        localPath: r'C:\models\functiongemma-270m.litertlm',
        sizeBytes: 10,
        installedAt: DateTime.now(),
      );
      final gguf = InstalledLocalModel(
        catalogId: 'qwen/model',
        displayName: 'Qwen GGUF',
        localPath: r'C:\models\Qwen3-0.6B-Q4_K_M.gguf',
        sizeBytes: 10,
        installedAt: DateTime.now(),
      );

      expect(safetensors.isRunnableArtifact, isFalse);
      expect(litertlm.isRunnableArtifact, isTrue);
      expect(gguf.isRunnableArtifact, isTrue);
      expect(safetensors.runtimeKind, LocalModelRuntimeKind.unsupported);
      expect(litertlm.runtimeKind, LocalModelRuntimeKind.liteRtLm);
      expect(gguf.runtimeKind, LocalModelRuntimeKind.llamaCpp);
    });

    test('14.10 context window defaults and clamps to supported range',
        () async {
      expect(service.getMaxContextTokens(),
          LocalAiAdvisorService.defaultContextTokens);

      await service.setMaxContextTokens(8192);
      expect(service.getMaxContextTokens(), 8192);

      await service.setMaxContextTokens(999999);
      expect(service.getMaxContextTokens(),
          LocalAiAdvisorService.maxContextTokens);

      await service.setMaxContextTokens(1);
      expect(service.getMaxContextTokens(),
          LocalAiAdvisorService.minContextTokens);
    });

    test('14.11 streams local chat chunks from runtime', () async {
      final model = InstalledLocalModel(
        catalogId: 'litert/model-stream',
        displayName: 'LiteRT Stream',
        localPath: r'C:\models\functiongemma-270m.litertlm',
        sizeBytes: 10,
        installedAt: DateTime.now(),
      );
      await prefs.setString(
        'local_ai_installed_models',
        '[${_modelToJsonString(model)}]',
      );
      await prefs.setString('local_ai_selected_model_id', model.catalogId);

      service = LocalAiAdvisorService(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
        chatRuntime: const _FakeChatRuntime(['Hello', ' ', 'there']),
      );

      final chunks = await service
          .sendChatMessageStream(message: 'Hi', systemPrompt: 'System')
          .toList();

      expect(chunks, ['Hello', ' ', 'there']);
      expect(await service.sendChatMessage(message: 'Hi'), 'Hello there');
    });

    test('14.12 dispatches GGUF models to ggufChatRuntime', () async {
      final ggufModel = InstalledLocalModel(
        catalogId: 'qwen/gguf',
        displayName: 'Qwen GGUF',
        localPath: r'C:\models\Qwen3-0.6B-Q4_K_M.gguf',
        sizeBytes: 10,
        installedAt: DateTime.now(),
      );
      await prefs.setString(
        'local_ai_installed_models',
        '[${_modelToJsonString(ggufModel)}]',
      );
      await prefs.setString('local_ai_selected_model_id', ggufModel.catalogId);

      service = LocalAiAdvisorService(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
        chatRuntime: const _FakeChatRuntime(['LiteRT', 'response']),
        ggufChatRuntime: const _FakeChatRuntime(['GGUF', 'response']),
      );

      final chunks = await service
          .sendChatMessageStream(message: 'Hi', systemPrompt: 'System')
          .toList();

      // Should use GGUF runtime for .gguf artifacts
      expect(chunks, ['GGUF', 'response']);
    });
  });
}

String _modelToJsonString(InstalledLocalModel model) {
  return jsonEncode(model.toJson());
}

class _FakeDownloadClient extends http.BaseClient {
  final List<List<int>> chunks;

  _FakeDownloadClient({required this.chunks});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final totalBytes = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(chunks),
      200,
      contentLength: totalBytes,
      request: request,
    );
  }
}

class _FakeChatRuntime implements LocalAiChatRuntime {
  final List<String> chunks;

  const _FakeChatRuntime(this.chunks);

  @override
  Future<String> sendMessage({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  }) async {
    return chunks.join();
  }

  @override
  Stream<String> sendMessageStream({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  }) {
    return Stream<String>.fromIterable(chunks);
  }

  @override
  Future<void> dispose() async {}
}
