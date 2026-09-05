import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_bloc.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_event.dart';
import 'package:cb_file_manager/models/ai/ai_message.dart';
import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/ai/ai_provider_service.dart';
import 'package:cb_file_manager/services/ai/providers/ai_provider.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/services/local_ai/llama_cpp_chat_client.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'agent_common_tools_test.dart' show MemoryAgentTags;

String call(String name, Map<String, dynamic> args) =>
    '<tool_call>${jsonEncode({'name': name, 'arguments': args})}</tool_call>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late MemoryAgentTags tags;
  late _Tools tools;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('cb-agent-harness-');
    tags = MemoryAgentTags();
    tools = _Tools(tags);
    await File(
      p.join(sandbox.path, 'report.txt'),
    ).writeAsString('Invoice number: INV-2048\nReviewed');
    await File(p.join(sandbox.path, 'photo.txt')).writeAsString('photo notes');
    tags.values[p.join(sandbox.path, 'report.txt')] = ['Work'];
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  Future<AiAgentBloc> local(_Runtime runtime) async {
    final prefs = await SharedPreferences.getInstance();
    final model = InstalledLocalModel(
      catalogId:
          Platform.environment['CB_LOCAL_CHAT_TEST_MODEL'] ?? 'test/qwen',
      displayName: 'Qwen3',
      localPath: 'test.gguf',
      sizeBytes: 1,
      installedAt: DateTime(2026),
    );
    await prefs.setString(
      'local_ai_installed_models',
      jsonEncode([model.toJson()]),
    );
    await prefs.setString('local_ai_selected_model_id', model.catalogId);
    final service = LocalAiAdvisorService(
      secureStorage: const FlutterSecureStorage(),
      prefs: prefs,
      ggufChatRuntime: runtime,
    );
    final bloc = AiAgentBloc(
      providerService: _Remote([]),
      localAiService: service,
      toolExecutor: tools,
    );
    addTearDown(service.dispose);
    addTearDown(bloc.close);
    bloc.add(InitializeAiAgent(workspacePath: sandbox.path));
    await until(() => bloc.state.selectedProviderId == '__local_ai__');
    return bloc;
  }

  test('unknown tool and invalid args are repaired before execution', () async {
    final runtime = _Runtime([
      call('find_duplicate_files', {}),
      call('list_directory', {'limit': 'thirty'}),
      call('list_directory', {'path': '.', 'limit': 1}),
      'I found report.txt.',
    ]);
    final bloc = await local(runtime);
    bloc.add(const SendMessage('Show files here'));
    await until(() => runtime.requests.length == 4 && !bloc.state.isLoading);
    expect(tools.calls.map((c) => c.name), ['list_directory']);
    expect(runtime.requests[1].last['content'], contains('Unknown tool'));
    expect(runtime.requests[2].last['content'], contains('must be int'));
    expect(bloc.state.error, isNull);
  });

  test(
    'approval contains resolved destinations; rejection cannot be bypassed',
    () async {
      final runtime = _Runtime([
        call('move_file', {
          'source': 'report.txt',
          'destination': 'renamed.txt',
        }),
        call('run_command', {'command': 'echo bypass'}),
      ]);
      final bloc = await local(runtime);
      bloc.add(const SendMessage('Rename report.txt to renamed.txt'));
      await until(() => bloc.state.pendingApproval != null);
      expect(
        bloc.state.pendingApproval!.description,
        contains(p.join(sandbox.path, 'renamed.txt')),
      );
      expect(tools.calls, isEmpty);
      bloc.add(RejectAction(bloc.state.pendingApproval!.id));
      await until(() => !bloc.state.isLoading);
      expect(tools.calls, isEmpty);
      expect(await File(p.join(sandbox.path, 'report.txt')).exists(), true);
      expect(await File(p.join(sandbox.path, 'renamed.txt')).exists(), false);
    },
  );

  test(
    'approved move executes once and tool evidence survives next user turn',
    () async {
      final runtime = _Runtime([
        call('move_file', {
          'source': 'report.txt',
          'destination': 'renamed.txt',
        }),
        'Renamed.',
        'It is renamed.txt.',
      ]);
      final bloc = await local(runtime);
      bloc.add(const SendMessage('Rename report.txt to renamed.txt'));
      await until(() => bloc.state.pendingApproval != null);
      bloc.add(ApproveAction(bloc.state.pendingApproval!.id));
      await until(() => !bloc.state.isLoading);
      expect(tools.calls, hasLength(1));
      expect(await File(p.join(sandbox.path, 'renamed.txt')).exists(), true);
      bloc.add(const SendMessage('What changed?'));
      await until(() => runtime.requests.length == 3 && !bloc.state.isLoading);
      final history = runtime.requests.last.map((m) => m['content']).join('\n');
      expect(history, contains('move_file'));
      expect(history, contains('renamed.txt'));
      expect(history, contains('"ok":true'));
    },
  );

  test(
    'repeated read calls stop; remote uses its first final answer',
    () async {
      final provider = _Remote([
        call('get_context', {}),
        call('get_context', {}),
      ]);
      final bloc = AiAgentBloc(providerService: provider, toolExecutor: tools);
      addTearDown(bloc.close);
      bloc.add(const SendMessage('Show context'));
      await until(() => provider.requests.length == 2 && !bloc.state.isLoading);
      expect(tools.calls.map((c) => c.name), ['get_context']);
      final answerProvider = _Remote(['Final response']);
      final answerBloc = AiAgentBloc(providerService: answerProvider);
      addTearDown(answerBloc.close);
      answerBloc.add(const SendMessage('Hello'));
      await until(
        () => answerProvider.requests.isNotEmpty && !answerBloc.state.isLoading,
      );
      expect(answerProvider.streamCalls, 0);
      expect(answerBloc.state.messages.last.content, 'Final response');
    },
  );

  test('fake approval notation is repaired into a real approved call', () async {
    final runtime = _Runtime([
      '[approval]\ncopy_file(source:"report.txt", destination:"backup.txt")\n[/approval]',
      call('copy_file', {'source': 'report.txt', 'destination': 'backup.txt'}),
      'Copied.',
    ]);
    final bloc = await local(runtime);
    bloc.add(const SendMessage('Copy report.txt to backup.txt'));
    await until(() => bloc.state.pendingApproval != null);
    expect(runtime.requests, hasLength(2));
    expect(tools.calls, isEmpty);
    bloc.add(ApproveAction(bloc.state.pendingApproval!.id));
    await until(() => !bloc.state.isLoading);
    expect(tools.calls.map((tool) => tool.name), ['copy_file']);
    expect(await File(p.join(sandbox.path, 'backup.txt')).exists(), true);
  });

  test('a failed operation stops the remaining calls in its batch', () async {
    final runtime = _Runtime([
      '${call('copy_file', {'source': 'missing.txt', 'destination': 'copy.txt'})}${call('write_file', {'path': 'should-not-exist.txt', 'content': 'x'})}',
      'The source does not exist; no files changed.',
    ]);
    final bloc = await local(runtime);
    bloc.add(const SendMessage('Organize the files'));
    await until(() => bloc.state.pendingApproval != null);
    bloc.add(ApproveAction(bloc.state.pendingApproval!.id));
    await until(() => !bloc.state.isLoading);
    expect(tools.calls.map((tool) => tool.name), ['copy_file']);
    expect(
      await File(p.join(sandbox.path, 'should-not-exist.txt')).exists(),
      false,
    );
    expect(runtime.requests.last.last['content'], contains('Remaining calls'));
  });

  test('a successful mutation is never repeated in the same turn', () async {
    final write = call('write_file', {
      'path': 'append.txt',
      'content': 'once',
      'append': true,
    });
    final runtime = _Runtime([write, write, 'Written once.']);
    final bloc = await local(runtime);
    bloc.add(const SendMessage('Write once'));
    await until(() => bloc.state.pendingApproval != null);
    bloc.add(ApproveAction(bloc.state.pendingApproval!.id));
    await until(() => !bloc.state.isLoading);
    expect(tools.calls, hasLength(1));
    expect(
      await File(p.join(sandbox.path, 'append.txt')).readAsString(),
      'once',
    );
  });

  final liveUrl = Platform.environment['CB_LOCAL_CHAT_TEST_URL'];
  for (final scenario in ['files', 'tags', 'read', 'manage']) {
    test(
      'live local model common workflow: $scenario',
      () async {
        final runtime = _Runtime([], liveUrl: liveUrl);
        final bloc = await local(runtime);
        final prompt = switch (scenario) {
          'files' => 'Tìm file report.txt trong thư mục hiện tại.',
          'tags' => 'Trong thư mục hiện tại có file nào gắn tag Work?',
          'read' => 'Đọc report.txt và cho tôi biết số hóa đơn.',
          _ => 'Copy report.txt thành backup.txt ngay trong thư mục này.',
        };
        final approved = <String>{};
        final subscription = bloc.stream.listen((state) {
          final approval = state.pendingApproval;
          if (approval != null && approved.add(approval.id)) {
            // Test-only approval: targets must resolve inside our own sandbox.
            expect(approval.description, contains(sandbox.path));
            bloc.add(ApproveAction(approval.id));
          }
        });
        addTearDown(subscription.cancel);
        bloc.add(SendMessage(prompt));
        await until(() => runtime.requests.isNotEmpty && !bloc.state.isLoading);
        expect(bloc.state.error, isNull);
        final names = tools.calls.map((c) => c.name).toList();
        print(
          'LIVE $scenario calls=$names; answer=${bloc.state.messages.last.content}',
        );
        switch (scenario) {
          case 'files':
            expect(names, contains(anyOf('search_files', 'list_directory')));
            expect(bloc.state.messages.last.content, contains('report.txt'));
          case 'tags':
            expect(names, contains('search_by_tag'));
            expect(bloc.state.messages.last.content, contains('report.txt'));
          case 'read':
            expect(names, contains('read_file'));
            expect(bloc.state.messages.last.content, contains('INV-2048'));
          case 'manage':
            expect(names, contains('copy_file'));
            expect(
              await File(p.join(sandbox.path, 'backup.txt')).readAsString(),
              contains('INV-2048'),
            );
        }
      },
      skip: liveUrl == null,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

class _Tools extends ToolExecutor {
  final calls = <ToolCall>[];
  _Tools(MemoryAgentTags tags) : super(tagStore: tags);
  @override
  Future<ToolResult> execute(ToolCall call) async {
    calls.add(call);
    return super.execute(call);
  }
}

class _Remote extends AiProviderService {
  final List<String> responses;
  final requests = <List<AiMessage>>[];
  int streamCalls = 0;
  _Remote(this.responses);
  @override
  Future<bool> get hasConfiguredProvider async => false;
  @override
  Future<AiChatResult> chat(
    List<AiMessage> messages, {
    String? systemPrompt,
    String? preferredProviderId,
    String? preferredModelName,
  }) async {
    requests.add(List.of(messages));
    return AiChatResult(
      response: AiChatResponse(content: responses[requests.length - 1]),
      providerId: 'test',
    );
  }

  @override
  Future<AiStreamResult> chatStream(
    List<AiMessage> messages, {
    String? systemPrompt,
    String? preferredProviderId,
    String? preferredModelName,
  }) async {
    streamCalls++;
    return AiStreamResult(stream: Stream.value('Stopped.'), providerId: 'test');
  }
}

class _Runtime extends LocalAiChatRuntime
    implements LocalAiConversationRuntime {
  final List<String> responses;
  final String? liveUrl;
  final requests = <List<Map<String, String>>>[];
  final http = _RealHttp().createHttpClient(null);
  _Runtime(this.responses, {this.liveUrl});
  @override
  Stream<String> sendConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
  }) {
    requests.add(List.of(messages));
    if (liveUrl != null) {
      return LlamaCppChatClient(http).stream(
        baseUri: Uri.parse(liveUrl!),
        messages: [
          {'role': 'system', 'content': systemPrompt!},
          ...messages,
        ],
        maxResponseTokens: 2048,
        catalogId: model.catalogId,
      );
    }
    return Stream.value(responses[requests.length - 1]);
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
  }) => throw UnimplementedError();
  @override
  Future<void> dispose() async {
    http.close(force: true);
  }
}

class _RealHttp extends HttpOverrides {}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 150));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Agent did not settle.');
}
