import 'dart:convert';
import 'dart:io';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_bloc.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_event.dart';
import 'package:cb_file_manager/models/ai/ai_message.dart';
import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/ai/ai_provider_service.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/local_ai/llama_cpp_chat_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<AiAgentBloc> createBloc(
    _ConversationRuntime runtime,
    _RecordingTools tools,
  ) async {
    final model = InstalledLocalModel(
      catalogId: 'test/qwen',
      displayName: 'Qwen3',
      localPath: 'test.gguf',
      sizeBytes: 1,
      installedAt: DateTime(2026),
    );
    SharedPreferences.setMockInitialValues({
      'local_ai_installed_models': jsonEncode([model.toJson()]),
      'local_ai_selected_model_id': model.catalogId,
    });
    final service = LocalAiAdvisorService(
      secureStorage: const FlutterSecureStorage(),
      prefs: await SharedPreferences.getInstance(),
      ggufChatRuntime: runtime,
    );
    final bloc = AiAgentBloc(
      providerService: _NoRemoteProvider(),
      localAiService: service,
      toolExecutor: tools,
    );
    addTearDown(service.dispose);
    addTearDown(bloc.close);
    bloc.add(const InitializeAiAgent());
    await _waitUntil(() => bloc.state.selectedProviderId == '__local_ai__');
    return bloc;
  }

  test(
    'local tool rounds preserve assistant role without empty explanations',
    () async {
      final runtime = _ConversationRuntime([
        [
          '<think>Inspect requested directory</think>',
          '<tool_call>{"name":"list_directory","arguments":{"path":"C:/"}}</tool_call>',
        ],
        ['There are no files.'],
      ]);
      final tools = _RecordingTools();
      final bloc = await createBloc(runtime, tools);
      bloc.add(const SendMessage('List C:/'));
      await _waitUntil(
        () => runtime.requests.length == 2 && !bloc.state.isLoading,
      );
      expect(tools.calls.map((call) => call.name), ['list_directory']);
      final secondRequest = runtime.requests[1];
      expect(secondRequest.map((turn) => turn['role']), [
        'user',
        'assistant',
        'user',
      ]);
      expect(secondRequest[1]['content'], startsWith('<tool_call>'));
      expect(secondRequest[2]['content'], contains('<tool_result'));
      final assistants = bloc.state.messages.where(
        (m) => m.role == AiMessageRole.assistant,
      );
      expect(assistants, hasLength(2));
      expect(assistants.first.content, isEmpty);
      expect(assistants.first.reasoning, 'Inspect requested directory');
      expect(assistants.last.content, 'There are no files.');
      expect(assistants.last.toolCalls, hasLength(1));
    },
  );

  test('reasoning-only tool suggestions never execute', () async {
    final runtime = _ConversationRuntime([
      [
        '<think><tool_call>{"name":"list_all_tags","arguments":{}}</tool_call></think>',
        'Xin chào!',
      ],
    ]);
    final tools = _RecordingTools();
    final bloc = await createBloc(runtime, tools);
    bloc.add(const SendMessage('Alo'));
    await _waitUntil(
      () => runtime.requests.isNotEmpty && !bloc.state.isLoading,
    );
    expect(tools.calls, isEmpty);
    expect(bloc.state.messages.last.content, 'Xin chào!');
    expect(bloc.state.messages.last.reasoning, contains('list_all_tags'));
    expect(
      AiMessage.fromJson(bloc.state.messages.last.toJson()).reasoning,
      bloc.state.messages.last.reasoning,
    );
  });

  final liveUrl = Platform.environment['CB_LOCAL_CHAT_TEST_URL'];
  test(
    'live Qwen can still request a directory tool',
    () async {
      final runtime = _ConversationRuntime([], liveUrl: liveUrl);
      final tools = _RecordingTools();
      final bloc = await createBloc(runtime, tools);
      bloc.add(
        const SendMessage(
          'Liệt kê các file trong thư mục C:/ bằng công cụ list_directory.',
        ),
      );
      await _waitUntil(
        () => runtime.requests.isNotEmpty && !bloc.state.isLoading,
      );
      expect(bloc.state.error, isNull);
      expect(tools.calls.map((call) => call.name), contains('list_directory'));
      expect(bloc.state.messages.last.content.trim(), isNotEmpty);
      print('Live Qwen tool result: ${bloc.state.messages.last.content}');
    },
    skip: liveUrl == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'live Qwen greeting and correction stay conversational',
    () async {
      final runtime = _ConversationRuntime([], liveUrl: liveUrl);
      final tools = _RecordingTools();
      final bloc = await createBloc(runtime, tools);
      for (final message in ['Alo', 'gì vậy', 'có kêu làm gì đâu']) {
        final previousRequests = runtime.requests.length;
        bloc.add(SendMessage(message));
        await _waitUntil(
          () =>
              runtime.requests.length > previousRequests &&
              !bloc.state.isLoading,
        );
        expect(bloc.state.error, isNull);
        expect(bloc.state.messages.last.content.trim(), isNotEmpty);
        expect(bloc.state.messages.last.content, isNot(contains('<think>')));
        expect(
          tools.calls,
          isEmpty,
          reason: 'No file operation was requested: $message',
        );
        expect(bloc.state.messages.last.reasoning, isNotEmpty);
        print(
          'Live Qwen: $message -> ${bloc.state.messages.last.content}; reasoning saved: ${bloc.state.messages.last.reasoning!.length} chars',
        );
      }
    },
    skip: liveUrl == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _NoRemoteProvider extends AiProviderService {
  @override
  Future<bool> get hasConfiguredProvider async => false;
}

class _RecordingTools extends ToolExecutor {
  final calls = <ToolCall>[];
  @override
  Future<ToolResult> execute(ToolCall call) async {
    calls.add(call);
    return ToolResult(toolName: call.name, output: 'No files found.');
  }
}

class _ConversationRuntime extends LocalAiChatRuntime
    implements LocalAiConversationRuntime {
  final List<List<String>> responses;
  final String? liveUrl;
  final requests = <List<Map<String, String>>>[];
  final http = _RealHttpOverrides().createHttpClient(null);
  _ConversationRuntime(this.responses, {this.liveUrl});
  @override
  Stream<String> sendConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
  }) {
    requests.add(messages);
    if (liveUrl != null) {
      return LlamaCppChatClient(http).stream(
        baseUri: Uri.parse(liveUrl!),
        messages: [
          {'role': 'system', 'content': systemPrompt!},
          ...messages,
        ],
        maxResponseTokens: 2048,
      );
    }
    return Stream.fromIterable(responses[requests.length - 1]);
  }

  @override
  Future<String> sendMessage({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  }) => throw UnimplementedError();
  @override
  Stream<String> sendMessageStream({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  }) => throw StateError('Conversation roles were flattened');
  @override
  Future<void> dispose() async {
    http.close(force: true);
  }
}

class _RealHttpOverrides extends HttpOverrides {}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 50));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Chat did not settle before timeout.');
}
