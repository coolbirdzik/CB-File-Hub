import 'dart:async';
import 'dart:convert';

import 'package:cb_file_manager/bloc/ai_agent/ai_agent_bloc.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_event.dart';
import 'package:cb_file_manager/models/ai/ai_message.dart';
import 'package:cb_file_manager/models/ai/ai_provider_model.dart';
import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/ai/ai_provider_service.dart';
import 'package:cb_file_manager/services/ai/ai_chat_history_service.dart';
import 'package:cb_file_manager/services/ai/providers/ai_provider.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localProviderId = '__local_ai__';
const _remoteProviderId = 'remote';
const _remoteModel = 'gpt-oss';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late LocalAiAdvisorService service;
  late _RecordingRuntime runtime;
  late InstalledLocalModel qwen;

  setUp(() async {
    qwen = InstalledLocalModel(
      catalogId: 'test/qwen',
      displayName: 'Qwen local',
      localPath: 'test.gguf',
      sizeBytes: 1,
      installedAt: DateTime(2026),
    );
    SharedPreferences.setMockInitialValues({
      'local_ai_installed_models': jsonEncode([qwen.toJson()]),
      'local_ai_selected_model_id': qwen.catalogId,
      'ai_chat_last_provider_id': _remoteProviderId,
      'ai_chat_last_model_name': _remoteModel,
    });
    prefs = await SharedPreferences.getInstance();
    runtime = _RecordingRuntime();
    service = LocalAiAdvisorService(prefs: prefs, ggufChatRuntime: runtime);
    addTearDown(service.dispose);
  });

  AiAgentBloc createBloc(
    _RecordingProvider provider, {
    AiChatHistoryService? history,
  }) {
    final bloc = AiAgentBloc(
      providerService: provider,
      localAiService: service,
      historyService: history,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  test('Cleaner message waits for initialization and restores Qwen', () async {
    await prefs.setString('ai_chat_last_provider_id', _localProviderId);
    await prefs.setString('ai_chat_last_model_name', qwen.displayName);
    final catalogGate = Completer<void>();
    final provider = _RecordingProvider(catalogGate: catalogGate);
    final bloc = createBloc(provider);
    bloc.add(const InitializeAiAgent(workspacePath: '#cb-agent-cleaner'));
    bloc.add(const SendMessage('Suggest and select from this scan'));

    await provider.catalogRequested.future;
    // Flush queued event handlers while catalog restoration remains blocked.
    await Future<void>.delayed(Duration.zero);
    expect(provider.requests, isEmpty);
    expect(runtime.models, isEmpty);

    catalogGate.complete();
    await _waitForAnswer(bloc);
    expect(provider.requests, isEmpty);
    expect(runtime.models.single.catalogId, qwen.catalogId);
    expect(bloc.state.selectedProviderId, _localProviderId);
    expect(bloc.state.selectedModelName, qwen.displayName);
    expect(bloc.state.activeProviderId, _localProviderId);
    expect(bloc.state.messages.first.content, contains('Suggest and select'));
  });

  test(
    'each quick-review click starts a new persisted conversation after history restoration',
    () async {
      final history = AiChatHistoryService();
      const oldId = 'previous-cleaner-conversation';
      const path = '#cb-agent-cleaner';
      await history.saveConversation(oldId, 'Previous review', [
        AiMessage(
          id: 'old-message',
          role: AiMessageRole.user,
          content: 'Previous review',
          timestamp: DateTime(2026),
        ),
      ], initialPath: path);
      final gate = Completer<void>();
      final provider = _RecordingProvider(catalogGate: gate);
      final bloc = createBloc(provider, history: history);
      bloc.add(const InitializeAiAgent(workspacePath: path));
      // A click can arrive while persisted history and model choice are loading.
      bloc.add(const SendMessage('Quick review 1', startNewConversation: true));
      await provider.catalogRequested.future;
      final firstAnswer = _waitForAnswer(
        bloc,
        expectedMessage: 'Quick review 1',
      );
      gate.complete();
      await firstAnswer;
      final firstId = bloc.state.conversationId!;
      expect(firstId, isNot(oldId));
      expect(bloc.state.messages.map((m) => m.content), [
        'Quick review 1',
        'Remote answer',
      ]);
      expect(bloc.state.currentPath, path);
      expect(bloc.state.selectedModelName, _remoteModel);
      if (!bloc.state.conversations.any((c) => c.id == firstId)) {
        await bloc.stream
            .firstWhere((s) => s.conversations.any((c) => c.id == firstId))
            .timeout(const Duration(seconds: 5));
      }

      final secondAnswer = _waitForAnswer(
        bloc,
        expectedMessage: 'Quick review 2',
      );
      bloc.add(const SendMessage('Quick review 2', startNewConversation: true));
      await secondAnswer;
      final secondId = bloc.state.conversationId!;
      expect(secondId, isNot(firstId));
      expect(secondId, isNot(oldId));
      expect(bloc.state.messages.map((m) => m.content), [
        'Quick review 2',
        'Remote answer',
      ]);
      if (!bloc.state.conversations.any((c) => c.id == secondId)) {
        await bloc.stream
            .firstWhere((s) => s.conversations.any((c) => c.id == secondId))
            .timeout(const Duration(seconds: 5));
      }
      expect(
        (await history.loadAllSummaries()).map((c) => c.id),
        containsAll([oldId, firstId, secondId]),
      );
      expect(
        (await history.loadConversation(oldId)).single.content,
        'Previous review',
      );
      expect(
        (await history.loadConversation(firstId)).first.content,
        'Quick review 1',
      );

      final followupAnswer = _waitForAnswer(
        bloc,
        expectedMessage: 'Explain this recommendation',
      );
      bloc.add(const SendMessage('Explain this recommendation'));
      await followupAnswer;
      expect(bloc.state.conversationId, secondId);
      expect(bloc.state.messages, hasLength(4));
    },
  );

  test('existing Cleaner tab uses model selected in another chat', () async {
    final cleanerProvider = _RecordingProvider();
    final cleaner = createBloc(cleanerProvider);
    cleaner.add(const InitializeAiAgent(workspacePath: '#cb-agent-cleaner'));
    await _waitForInitialization(cleaner);
    expect(cleaner.state.selectedModelName, _remoteModel);

    final chat = createBloc(_RecordingProvider());
    chat.add(const InitializeAiAgent());
    await _waitForInitialization(chat);
    chat.add(
      SelectChatModel(
        providerId: _localProviderId,
        modelName: qwen.displayName,
      ),
    );
    await chat.stream
        .firstWhere((state) => state.selectedProviderId == _localProviderId)
        .timeout(const Duration(seconds: 5));

    cleaner.add(const SendMessage('Suggest and select'));
    await _waitForAnswer(cleaner);
    expect(cleanerProvider.requests, isEmpty);
    expect(runtime.models.single.catalogId, qwen.catalogId);
    expect(cleaner.state.selectedModelName, qwen.displayName);
    expect(cleaner.state.activeProviderId, _localProviderId);
  });

  test('Settings local model choice replaces stale GPT OSS choice', () async {
    final provider = _RecordingProvider();
    final cleaner = createBloc(provider);
    cleaner.add(const InitializeAiAgent());
    await _waitForInitialization(cleaner);
    expect(cleaner.state.selectedModelName, _remoteModel);

    await service.setSelectedModel(qwen.catalogId);
    expect(prefs.getString('ai_chat_last_provider_id'), _localProviderId);
    expect(prefs.getString('ai_chat_last_model_name'), qwen.displayName);
    cleaner.add(const SendMessage('Suggest and select'));
    await _waitForAnswer(cleaner);
    expect(provider.requests, isEmpty);
    expect(runtime.models.single.catalogId, qwen.catalogId);
    expect(cleaner.state.selectedModelName, qwen.displayName);
  });

  test('explicit remote choice still wins with Qwen installed', () async {
    await service.setSelectedModel(qwen.catalogId);
    final provider = _RecordingProvider();
    final bloc = createBloc(provider);
    bloc.add(const InitializeAiAgent());
    await _waitForInitialization(bloc);
    expect(bloc.state.selectedModelName, qwen.displayName);

    bloc.add(
      const SelectChatModel(
        providerId: _remoteProviderId,
        modelName: _remoteModel,
      ),
    );
    await bloc.stream
        .firstWhere((state) => state.selectedProviderId == _remoteProviderId)
        .timeout(const Duration(seconds: 5));
    bloc.add(const SendMessage('Suggest and select'));
    await _waitForAnswer(bloc);
    expect(runtime.models, isEmpty);
    expect(provider.requests.single, (_remoteProviderId, _remoteModel));
    expect(bloc.state.selectedModelName, _remoteModel);
    expect(bloc.state.activeProviderId, _remoteProviderId);
  });
}

Future<void> _waitForInitialization(AiAgentBloc bloc) => bloc.stream
    .firstWhere((state) => state.conversationId != null)
    .timeout(const Duration(seconds: 5));

Future<void> _waitForAnswer(AiAgentBloc bloc, {String? expectedMessage}) => bloc
    .stream
    .firstWhere(
      (state) =>
          !state.isLoading &&
          state.messages.isNotEmpty &&
          (expectedMessage == null ||
              state.messages.any(
                (message) =>
                    message.role == AiMessageRole.user &&
                    message.content == expectedMessage,
              )) &&
          state.messages.last.role == AiMessageRole.assistant,
    )
    .timeout(const Duration(seconds: 5));

class _RecordingProvider extends AiProviderService {
  final Completer<void>? catalogGate;
  final catalogRequested = Completer<void>();
  final requests = <(String?, String?)>[];

  _RecordingProvider({this.catalogGate});

  @override
  Future<bool> get hasConfiguredProvider async => true;

  @override
  Future<List<AiProviderModelCatalog>> getEnabledProviderModelCatalogs() async {
    if (!catalogRequested.isCompleted) catalogRequested.complete();
    await catalogGate?.future;
    return const [
      AiProviderModelCatalog(
        providerId: _remoteProviderId,
        providerName: 'Remote',
        apiType: AiApiType.openaiCompatible,
        authMode: AiProviderAuthMode.none,
        defaultModelName: _remoteModel,
        models: [_remoteModel],
      ),
    ];
  }

  @override
  Future<AiChatResult> chat(
    List<AiMessage> messages, {
    String? systemPrompt,
    String? preferredProviderId,
    String? preferredModelName,
  }) async {
    requests.add((preferredProviderId, preferredModelName));
    return AiChatResult(
      providerId: _remoteProviderId,
      response: const AiChatResponse(content: 'Remote answer'),
    );
  }
}

class _RecordingRuntime extends LocalAiChatRuntime {
  final models = <InstalledLocalModel>[];

  @override
  Stream<String> sendMessageStream({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  }) {
    models.add(model);
    return Stream.value('Local answer');
  }

  @override
  Future<String> sendMessage({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  }) async => 'Local answer';

  @override
  Future<void> dispose() async {}
}
