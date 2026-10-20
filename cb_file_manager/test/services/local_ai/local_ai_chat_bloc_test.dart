import 'dart:convert';
import 'dart:io';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_bloc.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_event.dart';
import 'package:cb_file_manager/models/ai/ai_message.dart';
import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/ai/ai_provider_service.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/services/ai/cleaner_review_run.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_agent_review.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
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

  for (final providerFails in [false, true]) {
    test('quick Cleaner review bounds model calls across 1531 groups '
        '(providerFails: $providerFails)', () async {
      const owner = 'quick-cleaner-bloc-test';
      final cleaner = DiskCleanerService.instance;
      final files = List.generate(
        1531,
        (i) => DiskTreeNode(
          name: 'data.bin',
          fullPath: 'C:\\Data\\app$i\\data.bin',
          isFile: true,
          sizeBytes: i + 1,
        ),
      );
      files.first.isSelectedForDeletion = true; // User's existing selection.
      final root = DiskTreeNode(name: 'C:', fullPath: r'C:\', children: files);
      cleaner.publishCleanerScanContext(
        ownerTabId: owner,
        root: root,
        reviewItem: (_, _) => true,
        reviewGroup: (_, analysis) {
          expect(analysis.selectForCleanup, isFalse);
          return true;
        },
      );
      addTearDown(() => cleaner.clearCleanerScanContext(owner));
      final runtime = _ConversationRuntime(
        providerFails
            ? []
            : [
                [
                  '{"assessments":[{"group_id":"group_1530","decision":"KEEP","reason":"Application data."}]}',
                ],
                ['Not valid JSON'],
                ['Not valid JSON'],
                ['Not valid JSON'],
              ],
      );
      final tools = _RecordingTools(ownerTabId: owner);
      final bloc = await createBloc(runtime, tools);
      bloc.add(
        const SendMessage('Quick review', reviewEntireCleanerScan: true),
      );
      await _waitUntil(
        () => bloc.state.messages.isNotEmpty && !bloc.state.isLoading,
      );
      final review = cleaner.fullCleanerReview(owner)!;
      expect(review.groups, hasLength(1531));
      expect(review.isComplete, isTrue);
      expect(review.unresolvedItems, 0);
      expect(
        runtime.requests.length,
        inInclusiveRange(1, CleanerReviewRun.maxAiBatches),
      );
      if (providerFails) expect(runtime.requests, hasLength(1));
      final sentIds = <String>[];
      for (final request in runtime.requests) {
        final prompt = request.single['content']!;
        final evidence = jsonDecode(prompt.split('Evidence: ').last) as List;
        sentIds.addAll(evidence.map((e) => e['group_id'] as String));
      }
      expect(sentIds.length, lessThanOrEqualTo(CleanerReviewRun.maxAiGroups));
      expect(
        sentIds.toSet().length,
        sentIds.length,
        reason: 'No automatic retries',
      );
      expect(
        sentIds.first,
        'group_1530',
        reason: 'Largest unclear data gets AI time first',
      );
      expect(files.first.isSelectedForDeletion, isTrue);
      expect(
        files.skip(1).every((file) => !file.isSelectedForDeletion),
        isTrue,
      );
      expect(review.groups.every((g) => !g.analysis!.selectForCleanup), isTrue);
      if (!providerFails) {
        expect(review.groups.last.analysis!.fromScan, isFalse);
        expect(review.groups.last.analysis!.decision, CleanerItemDecision.keep);
      }
      expect(bloc.state.error, isNull);
      expect(
        bloc.state.messages.last.content,
        contains('Quick overview ready'),
      );
      expect(tools.calls, isEmpty);
    });
  }

  test('full AI review assesses every group, largest first, and resumes '
      'after Stop', () async {
    const owner = 'full-cleaner-bloc-test';
    final cleaner = DiskCleanerService.instance;
    final files = List.generate(
      60,
      (i) => DiskTreeNode(
        name: 'data.bin',
        fullPath: 'C:\\Data\\app$i\\data.bin',
        isFile: true,
        sizeBytes: i + 1,
      ),
    );
    final root = DiskTreeNode(name: 'C:', fullPath: r'C:\', children: files);
    cleaner.publishCleanerScanContext(
      ownerTabId: owner,
      root: root,
      reviewItem: (_, _) => true,
      reviewGroup: (_, _) => true,
    );
    addTearDown(() => cleaner.clearCleanerScanContext(owner));

    List<String> idsOf(List<Map<String, String>> request) {
      final prompt = request.single['content']!;
      final evidence = jsonDecode(prompt.split('Evidence: ').last) as List;
      return [for (final e in evidence) e['group_id'] as String];
    }

    AiAgentBloc? bloc;
    var stopOnRequest = 2;
    final runtime = _ConversationRuntime(
      [],
      respond: (messages) {
        final runtimeRequests = idsOf(messages);
        if (stopOnRequest > 0 && --stopOnRequest == 0) {
          bloc!.add(const StopGeneration());
        }
        return [
          jsonEncode({
            'assessments': [
              for (final id in runtimeRequests)
                {'group_id': id, 'decision': 'KEEP', 'reason': 'App data.'},
            ],
          }),
        ];
      },
    );
    final tools = _RecordingTools(ownerTabId: owner);
    bloc = await createBloc(runtime, tools);
    const request = SendMessage(
      'Full review',
      reviewEntireCleanerScan: true,
      cleanerReviewAllGroups: true,
    );

    bloc.add(request);
    await _waitUntil(() => runtime.requests.length >= 2);
    await _waitUntil(() => !bloc!.state.isLoading);
    final review = cleaner.fullCleanerReview(owner)!;
    expect(review.isComplete, isFalse, reason: 'Stopped mid-way');
    final firstRun = runtime.requests.map(idsOf).toList();
    expect(firstRun.first.first, 'group_59', reason: 'Largest group first');

    bloc.add(request);
    await _waitUntil(
      () => bloc!.state.messages.last.content.contains('AI review ready'),
    );
    expect(identical(cleaner.fullCleanerReview(owner), review), isTrue);
    expect(review.isComplete, isTrue);
    final resumed = runtime.requests.skip(firstRun.length).map(idsOf);
    expect(
      resumed.expand((ids) => ids).toSet().intersection(firstRun.first.toSet()),
      isEmpty,
      reason: 'Groups assessed before Stop are not sent again',
    );
    expect(
      runtime.requests.length,
      greaterThan(CleanerReviewRun.maxAiBatches),
      reason: 'No quick-review batch cap',
    );
    expect(
      review.groups.every(
        (g) =>
            !g.analysis!.fromScan &&
            g.analysis!.decision == CleanerItemDecision.keep &&
            !g.analysis!.selectForCleanup,
      ),
      isTrue,
    );
    expect(files.every((file) => !file.isSelectedForDeletion), isTrue);
    expect(tools.calls, isEmpty);
  });

  test('recognized Cleaner data needs no model calls', () async {
    const owner = 'quick-known-cleaner-test';
    final cleaner = DiskCleanerService.instance;
    final root = DiskTreeNode(
      name: 'C:',
      fullPath: r'C:\',
      children: [
        DiskTreeNode(
          name: 'cache.tmp',
          fullPath: r'C:\Temp\cache.tmp',
          isFile: true,
          junkCategoryId: 'windows_temp',
        ),
        DiskTreeNode(
          name: 'photo.jpg',
          fullPath: r'C:\Data\photo.jpg',
          isFile: true,
        ),
        DiskTreeNode(
          name: 'pagefile.sys',
          fullPath: r'C:\pagefile.sys',
          isFile: true,
        ),
      ],
    );
    cleaner.publishCleanerScanContext(
      ownerTabId: owner,
      root: root,
      reviewItem: (_, _) => true,
      reviewGroup: (_, _) => true,
    );
    addTearDown(() => cleaner.clearCleanerScanContext(owner));
    final runtime = _ConversationRuntime([]);
    final bloc = await createBloc(runtime, _RecordingTools(ownerTabId: owner));
    bloc.add(
      const SendMessage(
        'Xem nhanh',
        reviewEntireCleanerScan: true,
        cleanerReviewLanguageCode: 'vi',
      ),
    );
    await _waitUntil(
      () => bloc.state.messages.isNotEmpty && !bloc.state.isLoading,
    );
    expect(runtime.requests, isEmpty);
    final review = cleaner.fullCleanerReview(owner)!;
    expect(review.isComplete, isTrue);
    expect(review.groups.map((g) => g.analysis!.decision), [
      CleanerItemDecision.clean,
      CleanerItemDecision.review,
      CleanerItemDecision.keep,
    ]);
    expect(review.groups.every((g) => g.analysis!.fromScan), isTrue);
    expect(review.groups.every((g) => !g.analysis!.selectForCleanup), isTrue);
    expect(
      bloc.state.messages.last.content,
      contains('3 nhóm từ dữ liệu quét, 0 nhóm có gợi ý AI'),
    );
  });

  final liveUrl = Platform.environment['CB_LOCAL_CHAT_TEST_URL'];
  test('Docker inspection announcement continues into a real scan tool', () async {
    final runtime = _ConversationRuntime([
      [
        '## 🐳 **Docker Storage Location Report**\n\n'
            'Để xem chi tiết vị trí Docker trên hệ thống, tôi sẽ kiểm tra scan đang hoạt động:',
      ],
      [
        '<tool_call>{"name":"get_current_cleaner_scan","arguments":{}}</tool_call>',
      ],
      ['Docker storage is at C:/Docker/data.vhdx.'],
    ]);
    final tools = _RecordingTools();
    final bloc = await createBloc(runtime, tools);
    bloc.add(
      const SendMessage('Docker đang chiếm dung lượng ở đâu trong scan?'),
    );
    await _waitUntil(
      () => runtime.requests.length == 3 && !bloc.state.isLoading,
    );
    expect(bloc.state.error, isNull);
    expect(tools.calls.map((call) => call.name), ['get_current_cleaner_scan']);
    expect(runtime.requests[1].last['content'], contains('only announced'));
    expect(runtime.requests[2].last['content'], contains('<tool_result'));
    expect(bloc.state.messages.last.content, contains('C:/Docker/data.vhdx'));
    expect(
      bloc.state.messages.last.toolCalls!.single.toolName,
      'get_current_cleaner_scan',
    );
    expect(
      bloc.state.messages.where((m) => m.content.contains('tôi sẽ kiểm tra')),
      isEmpty,
    );
  });

  test('a promise after tool evidence also continues inspection', () async {
    final runtime = _ConversationRuntime([
      [
        '<tool_call>{"name":"get_current_cleaner_scan","arguments":{}}</tool_call>',
      ],
      ['Tôi sẽ kiểm tra thêm thư mục Docker:'],
      [
        '<tool_call>{"name":"explore_cleaner_scan","arguments":{"path":"C:/Docker","depth":1,"limit":12}}</tool_call>',
      ],
      ['Docker data is in its virtual disk.'],
    ]);
    final tools = _RecordingTools();
    final bloc = await createBloc(runtime, tools);
    bloc.add(const SendMessage('Inspect Docker storage'));
    await _waitUntil(
      () => runtime.requests.length == 4 && !bloc.state.isLoading,
    );
    expect(bloc.state.error, isNull);
    expect(tools.calls.map((call) => call.name), [
      'get_current_cleaner_scan',
      'explore_cleaner_scan',
    ]);
    expect(
      bloc.state.messages.last.content,
      'Docker data is in its virtual disk.',
    );
  });

  test(
    'repeated promises stop with an error instead of claiming completion',
    () async {
      final runtime = _ConversationRuntime(
        List.generate(3, (_) => ['Tôi sẽ kiểm tra scan:']),
      );
      final tools = _RecordingTools();
      final bloc = await createBloc(runtime, tools);
      bloc.add(const SendMessage('Inspect the scan'));
      await _waitUntil(
        () => runtime.requests.length == 3 && !bloc.state.isLoading,
      );
      expect(tools.calls, isEmpty);
      expect(bloc.state.error, contains('did not carry it out'));
      expect(bloc.state.messages.last.isLoading, isFalse);
      expect(bloc.state.messages.last.error, isNotNull);
    },
  );

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
  _RecordingTools({super.ownerTabId});
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

  /// Answers a request from its messages instead of [responses].
  final List<String> Function(List<Map<String, String>> messages)? respond;
  final requests = <List<Map<String, String>>>[];
  final http = _RealHttpOverrides().createHttpClient(null);
  _ConversationRuntime(this.responses, {this.liveUrl, this.respond});
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
    if (respond != null) return Stream.fromIterable(respond!(messages));
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
