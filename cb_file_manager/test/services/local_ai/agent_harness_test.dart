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
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_agent_review.dart';
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
    // Live runs: match the window llama-server was started with (-c).
    final window = int.tryParse(
      Platform.environment['CB_LOCAL_CHAT_TEST_CTX'] ?? '',
    );
    if (window != null) await prefs.setInt('local_ai_max_tokens', window);
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

  test('a small local window gets small tool pages and older results are '
      'shortened so every request fits', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_ai_max_tokens', 4096);
    for (var i = 0; i < 300; i++) {
      await File(
        p.join(sandbox.path, 'quarterly-report-${'x' * 40}-$i.txt'),
      ).writeAsString('x');
    }
    final runtime = _Runtime([
      for (final pattern in ['report', 'quarterly', 'txt', 'x'])
        call('list_directory', {'pattern': pattern, 'limit': 100}),
      'Done',
    ]);
    final bloc = await local(runtime);
    bloc.add(const SendMessage('List the reports'));
    await until(() => runtime.requests.length == 5 && !bloc.state.isLoading);
    expect(bloc.state.error, isNull);
    // The bloc's own estimate: ~4 characters a token for the system prompt,
    // ~2.8 for messages, with a quarter of the window left for the answer.
    for (var i = 0; i < runtime.requests.length; i++) {
      final messageChars = runtime.requests[i].fold<int>(
        0,
        (sum, m) => sum + m['content']!.length + 24,
      );
      final tokens = runtime.systemPrompts[i]!.length / 4 + messageChars / 2.8;
      expect(tokens, lessThanOrEqualTo(3072), reason: 'request $i');
    }
    final last = runtime.requests.last.map((m) => m['content']!).join('\n');
    // Earlier pages collapse to a marker; the newest result survives.
    expect(last, contains('earlier result omitted to fit the model context'));
    // Tool output is JSON inside the block, not an escaped string.
    expect(last, contains('"output":{"ok":true'));
  });

  for (final (label, first) in [
    (
      'an announced tool step ending on a colon',
      'Để tìm file theo tên chính xác hơn, tôi sẽ dùng công cụ tìm kiếm tên '
          'file thay vì nội dung trong file:',
    ),
    (
      'a reply cut off at the length limit',
      'Mình cần xem danh sách file trước khi trả lời'
          '${LlamaCppChatClient.lengthLimitMarker}',
    ),
  ]) {
    test('$label continues the turn instead of ending it', () async {
      final runtime = _Runtime([
        first,
        call('search_files', {'query': 'report'}),
        'Đã tìm thấy report.txt.',
      ]);
      final bloc = await local(runtime);
      bloc.add(const SendMessage('Tìm file report'));
      await until(() => runtime.requests.length == 3 && !bloc.state.isLoading);
      expect(bloc.state.error, isNull);
      expect(tools.calls.map((c) => c.name), ['search_files']);
      expect(bloc.state.messages.last.content, 'Đã tìm thấy report.txt.');
      // The unfinished reply is never shown as the answer.
      expect(
        bloc.state.messages.map((m) => m.content),
        isNot(contains(startsWith('Để tìm file theo tên'))),
      );
    });
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

  test(
    'remote inspection announcements continue without executing prose',
    () async {
      final provider = _Remote([
        'Để xem vị trí Docker, tôi sẽ kiểm tra scan đang hoạt động:',
        call('get_context', {}),
        'The working directory is available.',
      ]);
      final bloc = AiAgentBloc(providerService: provider, toolExecutor: tools);
      addTearDown(bloc.close);
      bloc.add(const SendMessage('Check the working context'));
      await until(() => provider.requests.length == 3 && !bloc.state.isLoading);
      expect(bloc.state.error, isNull);
      expect(tools.calls.map((call) => call.name), ['get_context']);
      expect(provider.requests[1].last.content, contains('only announced'));
      expect(
        bloc.state.messages.last.content,
        'The working directory is available.',
      );
    },
  );

  test('remote repeated inspection promises have a bounded failure', () async {
    final provider = _Remote(List.filled(3, 'I will check the current scan:'));
    final bloc = AiAgentBloc(providerService: provider, toolExecutor: tools);
    addTearDown(bloc.close);
    bloc.add(const SendMessage('Check the scan'));
    await until(() => provider.requests.length == 3 && !bloc.state.isLoading);
    expect(tools.calls, isEmpty);
    expect(bloc.state.error, contains('did not carry it out'));
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

  for (final useLocal in [false, true]) {
    test(
      '48 unknown Cleaner groups limit AI to 24 and explain the rest from metadata (${useLocal ? 'local' : 'remote'})',
      () async {
        const owner = 'batch-speed-harness';
        final cleaner = DiskCleanerService.instance;
        tools = _Tools(tags, ownerTabId: owner);
        final root = DiskTreeNode(
          name: 'C:',
          fullPath: r'C:\',
          children: List.generate(
            48,
            (i) => DiskTreeNode(
              name: 'data.unknown',
              fullPath: 'C:\\scope$i\\data.unknown',
              isFile: true,
              sizeBytes: 48 - i,
            ),
          ),
        );
        var focuses = 0;
        var acceptedGroups = 0;
        void publish() => cleaner.publishCleanerScanContext(
          ownerTabId: owner,
          root: root,
          reviewItem: (_, _) {
            focuses++;
            publish();
            return true;
          },
          reviewGroup: (_, _) {
            acceptedGroups++;
            return true;
          },
        );
        publish();
        addTearDown(() => cleaner.clearCleanerScanContext(owner));
        late _Runtime runtime;
        late _Remote provider;
        final requestedBatches = <List<String>>[];
        String respond() {
          final prompt = useLocal
              ? runtime.requests.last.last['content']!
              : provider.requests.last.single.content;
          expect(prompt.length, lessThan(8000));
          final evidence =
              jsonDecode(
                    prompt.substring(
                      prompt.indexOf('\nEvidence: ') + '\nEvidence: '.length,
                    ),
                  )
                  as List;
          final ids = evidence
              .map((data) => data['group_id'] as String)
              .toList();
          requestedBatches.add(ids);
          return jsonEncode({
            'assessments': [
              for (final id in ids)
                {
                  'group_id': id,
                  'decision': 'KEEP',
                  'reason': 'Unknown ownership; keep user data.',
                },
            ],
          });
        }

        runtime = _Runtime([], respond: respond);
        provider = _Remote([], respond: respond);
        final bloc = useLocal
            ? await local(runtime)
            : AiAgentBloc(providerService: provider, toolExecutor: tools);
        if (!useLocal) addTearDown(bloc.close);
        bloc.add(
          const SendMessage('Review all', reviewEntireCleanerScan: true),
        );
        await until(() => requestedBatches.isNotEmpty && !bloc.state.isLoading);
        expect(bloc.state.error, isNull);
        expect(requestedBatches, hasLength(3));
        expect(requestedBatches.every((batch) => batch.length == 8), isTrue);
        expect(
          requestedBatches.expand((batch) => batch).toSet(),
          hasLength(24),
        );
        expect(focuses, 4); // One metadata batch and three AI batches.
        expect(acceptedGroups, 48);
        final review = cleaner.fullCleanerReview(owner)!;
        expect(review.isComplete, isTrue);
        expect(review.groups.where((g) => g.analysis!.fromScan), hasLength(24));
        expect(
          review.groups.where((g) => !g.analysis!.fromScan).map((g) => g.scope),
          List.generate(24, (i) => 'C:\\scope$i'),
        );
        expect(
          review.groups.every((g) => !g.analysis!.selectForCleanup),
          isTrue,
        );
        expect(tools.calls, isEmpty);
      },
    );

    test(
      'full Cleaner review Stop blocks late tools and Retry resumes pending items '
      '(${useLocal ? 'local' : 'remote'})',
      () async {
        const owner = 'stop-review-harness';
        final cleaner = DiskCleanerService.instance;
        tools = _Tools(tags, ownerTabId: owner);
        final files = List.generate(
          9,
          (i) => DiskTreeNode(
            name: 'data.unknown',
            fullPath: 'C:\\scope$i\\data.unknown',
            isFile: true,
            sizeBytes: 9 - i,
          ),
        );
        final first = files.first;
        final second = files.last;
        final root = DiskTreeNode(
          name: 'C:',
          fullPath: r'C:\',
          children: files,
        );
        final assessed = <String>[];
        final focused = <String>[];
        void publish() => cleaner.publishCleanerScanContext(
          ownerTabId: owner,
          root: root,
          reviewItem: (node, analysis) {
            if (analysis == null) focused.add(node.fullPath);
            if (analysis != null) assessed.add(node.fullPath);
            publish();
            return true;
          },
          reviewGroup: (group, analysis) {
            assessed.addAll(group.nodes.map((n) => n.fullPath));
            publish();
            return true;
          },
        );
        publish();
        addTearDown(() => cleaner.clearCleanerScanContext(owner));
        final waiting = Completer<void>();
        final gate = Completer<void>();
        var round = 0;
        Future<String> respond() async {
          final group = cleaner
              .fullCleanerReview(owner)!
              .groups
              .firstWhere((g) => g.analysis == null);
          round++;
          if (round == 2) {
            waiting.complete();
            await gate.future;
          }
          return jsonEncode({
            'group_id': group.id,
            'decision': 'KEEP',
            'reason': 'No evidence that these personal files are disposable.',
          });
        }

        final bloc = useLocal
            ? await local(_Runtime([], asyncRespond: respond))
            : AiAgentBloc(
                providerService: _Remote([], asyncRespond: respond),
                toolExecutor: tools,
              );
        if (!useLocal) addTearDown(bloc.close);
        bloc.add(
          const SendMessage('Review all', reviewEntireCleanerScan: true),
        );
        await until(() => waiting.isCompleted);
        bloc.add(const StopGeneration());
        await until(() => !bloc.state.isLoading);
        final review = cleaner.fullCleanerReview(owner)!;
        expect(review.reviewed, 8);
        expect(review.next, same(second));
        expect(tools.calls, isEmpty);
        expect(focused, [first.fullPath, second.fullPath]);
        final original = bloc.state.messages.firstWhere(
          (m) => m.role == AiMessageRole.user,
        );
        expect(
          AiMessage.fromJson(original.toJson()).reviewEntireCleanerScan,
          isTrue,
        );
        gate.complete();
        bloc.add(const RetryLastMessage());
        await until(() => round >= 3 && !bloc.state.isLoading);
        expect(bloc.state.error, isNull);
        expect(cleaner.fullCleanerReview(owner), same(review));
        expect(review.isComplete, isTrue);
        expect(assessed, files.map((n) => n.fullPath));
        expect(tools.calls, isEmpty);
        expect(focused, [first.fullPath, second.fullPath, second.fullPath]);
      },
    );

    test('quick Cleaner overview replaces early summaries with metadata advice '
        '(${useLocal ? 'local' : 'remote'})', () async {
      const owner = 'full-review-harness';
      final cleaner = DiskCleanerService.instance;
      tools = _Tools(tags, ownerTabId: owner);
      final files = List.generate(
        25,
        (i) => DiskTreeNode(
          name: 'file$i.txt',
          fullPath: 'C:\\Data\\file$i.txt',
          isFile: true,
          sizeBytes: i + 1,
        ),
      );
      final folder = DiskTreeNode(
        name: 'Data',
        fullPath: r'C:\Data',
        children: files,
      );
      final root = DiskTreeNode(
        name: 'C:',
        fullPath: r'C:\',
        children: [
          folder,
          ...List.generate(
            12,
            (i) => DiskTreeNode(name: 'Other$i', fullPath: 'C:\\Other$i'),
          ),
        ],
      );
      final assessed = <String>[];
      void publish() => cleaner.publishCleanerScanContext(
        ownerTabId: owner,
        root: root,
        reviewItem: (node, analysis) {
          if (analysis != null) assessed.add(node.fullPath);
          publish();
          return true;
        },
        reviewGroup: (group, analysis) {
          assessed.addAll(group.nodes.map((n) => n.fullPath));
          publish();
          return true;
        },
      );
      publish();
      addTearDown(() => cleaner.clearCleanerScanContext(owner));
      var round = 0;
      String respond() {
        round++;
        // Unsupported final answers get conservative scan advice, without
        // repeated model requests or claiming the AI reviewed the data.
        if (round <= 3) return 'Review finished.';
        final review = cleaner.fullCleanerReview(owner)!;
        return jsonEncode({
          'assessments': [
            for (final group in review.groups.where((g) => g.analysis == null))
              {
                'group_id': group.id,
                'decision': 'KEEP',
                'reason':
                    'Personal data without evidence that it is disposable.',
              },
          ],
        });
      }

      final runtime = _Runtime([], respond: respond);
      final provider = _Remote([], respond: respond);
      final bloc = useLocal
          ? await local(runtime)
          : AiAgentBloc(providerService: provider, toolExecutor: tools);
      if (!useLocal) addTearDown(bloc.close);
      bloc.add(
        const SendMessage(
          'Review the entire Cleaner scan',
          reviewEntireCleanerScan: true,
        ),
      );
      await until(() => round > 0 && !bloc.state.isLoading);
      expect(bloc.state.error, isNull);
      expect(
        assessed,
        unorderedEquals([
          folder.fullPath,
          ...files.map((f) => f.fullPath),
          ...root.children.skip(1).map((n) => n.fullPath),
        ]),
      );
      expect(cleaner.fullCleanerReview(owner)!.remaining, 0);
      expect(round, 1);
      expect(
        bloc.state.messages.last.content,
        contains('Quick overview ready'),
      );
      expect(
        bloc.state.messages.last.content,
        contains('0 with AI recommendations'),
      );
      expect(
        cleaner
            .fullCleanerReview(owner)!
            .groups
            .every(
              (g) => g.analysis!.fromScan && !g.analysis!.selectForCleanup,
            ),
        isTrue,
      );
      expect(
        tools.calls.every((c) => !ToolExecutor.dangerousTools.contains(c.name)),
        isTrue,
      );
    });

    test('quick Cleaner overview explains known folders without calling AI '
        '(${useLocal ? 'local' : 'remote'})', () async {
      const owner = 'stalled-review-harness';
      final cleaner = DiskCleanerService.instance;
      tools = _Tools(tags, ownerTabId: owner);
      cleaner.publishCleanerScanContext(
        ownerTabId: owner,
        root: DiskTreeNode(
          name: 'C:',
          fullPath: r'C:\',
          children: [DiskTreeNode(name: 'data', fullPath: r'C:\data')],
        ),
        reviewItem: (_, _) => true,
        reviewGroup: (_, _) => true,
      );
      addTearDown(() => cleaner.clearCleanerScanContext(owner));
      var round = 0;
      String respond() {
        round++;
        return 'Done.';
      }

      final bloc = useLocal
          ? await local(_Runtime([], respond: respond))
          : AiAgentBloc(
              providerService: _Remote([], respond: respond),
              toolExecutor: tools,
            );
      if (!useLocal) addTearDown(bloc.close);
      bloc.add(const SendMessage('Review all', reviewEntireCleanerScan: true));
      await until(
        () => bloc.state.messages.length >= 2 && !bloc.state.isLoading,
      );
      expect(round, 0);
      expect(bloc.state.error, isNull);
      final review = cleaner.fullCleanerReview(owner)!;
      expect(review.remaining, 0);
      expect(review.reviewed, 1);
      expect(review.isComplete, isTrue);
      expect(review.groups.single.usedFallback, isFalse);
      expect(review.groups.single.analysis!.fromScan, isTrue);
      expect(
        review.groups.single.analysis!.decision,
        CleanerItemDecision.review,
      );
      expect(review.groups.single.analysis!.selectForCleanup, isFalse);
      expect(
        bloc.state.messages.last.content,
        contains('Quick overview ready'),
      );
      expect(tools.calls, isEmpty);
    });
  }

  test(
    'malformed eight-group AI batch uses metadata without recursive retries',
    () async {
      const owner = 'split-batch-review';
      final cleaner = DiskCleanerService.instance;
      tools = _Tools(tags, ownerTabId: owner);
      cleaner.publishCleanerScanContext(
        ownerTabId: owner,
        root: DiskTreeNode(
          name: 'C:',
          fullPath: r'C:\',
          children: List.generate(
            8,
            (i) => DiskTreeNode(
              name: 'data.unknown',
              fullPath: 'C:\\scope$i\\data.unknown',
              isFile: true,
              sizeBytes: 8 - i,
            ),
          ),
        ),
        reviewItem: (_, _) => true,
        reviewGroup: (_, _) => true,
      );
      addTearDown(() => cleaner.clearCleanerScanContext(owner));
      late _Remote provider;
      provider = _Remote(
        [],
        respond: () {
          final prompt = provider.requests.last.single.content;
          final evidence = jsonDecode(prompt.split('Evidence: ').last) as List;
          if (evidence.length > 1) return 'Invalid batch response.';
          return jsonEncode({
            'group_id': evidence.single['group_id'],
            'decision': 'KEEP',
            'reason': 'User data.',
          });
        },
      );
      final bloc = AiAgentBloc(providerService: provider, toolExecutor: tools);
      addTearDown(bloc.close);
      bloc.add(const SendMessage('Review all', reviewEntireCleanerScan: true));
      await until(() => provider.requests.isNotEmpty && !bloc.state.isLoading);
      expect(bloc.state.error, isNull);
      final review = cleaner.fullCleanerReview(owner)!;
      expect(review.reviewed, 8);
      expect(review.unresolvedItems, 0);
      expect(provider.requests.length, 1);
      expect(
        review.groups.every(
          (g) => g.analysis!.fromScan && !g.analysis!.selectForCleanup,
        ),
        isTrue,
      );
      expect(tools.calls, isEmpty);
    },
  );

  test(
    '598142-entry Cleaner scan preserves 8 reviews and labels the rest as metadata advice',
    () async {
      const owner = 'large-review-harness';
      final cleaner = DiskCleanerService.instance;
      tools = _Tools(tags, ownerTabId: owner);
      final files = List.generate(
        598141,
        (i) => DiskTreeNode(
          name: 'file$i.txt',
          fullPath: i < 7
              ? 'E:\\prior$i.txt'
              : 'E:\\reco\\ShinodaYu\\file$i.txt',
          isFile: true,
          sizeBytes: 1,
        ),
      );
      final folder = DiskTreeNode(
        name: 'ShinodaYu',
        fullPath: r'E:\reco\ShinodaYu',
        children: files.skip(7).toList(),
      );
      final root = DiskTreeNode(
        name: 'E:',
        fullPath: r'E:\',
        children: [...files.take(7), folder],
      );
      var acceptedGroups = 0;
      void publish() => cleaner.publishCleanerScanContext(
        ownerTabId: owner,
        root: root,
        reviewItem: (_, _) {
          publish();
          return true;
        },
        reviewGroup: (group, analysis) {
          acceptedGroups++;
          expect(analysis.decision, CleanerItemDecision.review);
          expect(analysis.selectForCleanup, isFalse);
          publish();
          return true;
        },
      );
      publish();
      addTearDown(() => cleaner.clearCleanerScanContext(owner));
      final review = cleaner.beginFullCleanerReview(owner);
      await review.prepareGroups(checkActive: () {});
      final previousGroups = review.groups.take(2).toList();
      const previousAnalysis = CleanerItemAnalysis(
        decision: CleanerItemDecision.review,
        reason: 'Previously accepted AI recommendation; retain user data.',
      );
      cleaner.inspectFullReviewGroups(
        ownerTabId: owner,
        review: review,
        groups: previousGroups,
      );
      for (final group in previousGroups) {
        cleaner.applyFullReviewGroup(
          ownerTabId: owner,
          review: review,
          group: group,
          analysis: previousAnalysis,
        );
      }
      expect(review.reviewed, 8);
      acceptedGroups = 0;
      var rounds = 0;
      final remote = _Remote(
        [],
        respond: () {
          rounds++;
          return 'I will continue inspecting.';
        },
      );
      final bloc = AiAgentBloc(providerService: remote, toolExecutor: tools);
      addTearDown(bloc.close);
      final elapsed = Stopwatch()..start();
      bloc.add(const SendMessage('Review all', reviewEntireCleanerScan: true));
      await until(() => rounds > 0 && !bloc.state.isLoading);
      expect(bloc.state.error, isNull);
      expect(review.reviewed, 598142);
      expect(review.remaining, 0);
      expect(review.isComplete, isTrue);
      expect(acceptedGroups, 1);
      expect(rounds, 1);
      expect(review.groups.last.nodes, hasLength(598134));
      expect(review.groups.last.analysis!.fromScan, isTrue);
      expect(
        previousGroups.every((g) => identical(g.analysis, previousAnalysis)),
        isTrue,
      );
      expect(files.every((file) => !file.isSelectedForDeletion), isTrue);
      expect(tools.calls, isEmpty);
      expect(
        remote.requests.every(
          (r) => r.length == 1 && r.single.content.length < 8000,
        ),
        isTrue,
      );
      expect(
        bloc.state.messages.last.content,
        contains('1 groups explained from scan metadata'),
      );
      expect(
        bloc.state.messages.last.content,
        contains('2 with AI recommendations'),
      );
      print(
        'CLEANER 598142 elapsed_ms=${elapsed.elapsedMilliseconds} requests=$rounds',
      );
    },
  );

  test(
    'local response-budget exhaustion explains all groups from metadata without splitting',
    () async {
      const owner = 'empty-local-review';
      final cleaner = DiskCleanerService.instance;
      tools = _Tools(tags, ownerTabId: owner);
      final root = DiskTreeNode(
        name: 'C:',
        fullPath: r'C:\',
        children: List.generate(
          9,
          (i) => DiskTreeNode(
            name: 'data.unknown',
            fullPath: 'C:\\scope$i\\data.unknown',
            isFile: true,
            sizeBytes: 9 - i,
          ),
        ),
      );
      void publish() => cleaner.publishCleanerScanContext(
        ownerTabId: owner,
        root: root,
        reviewItem: (_, _) {
          publish();
          return true;
        },
        reviewGroup: (_, _) {
          publish();
          return true;
        },
      );
      publish();
      addTearDown(() => cleaner.clearCleanerScanContext(owner));
      var requests = 0;
      final runtime = _Runtime(
        [],
        asyncRespond: () async {
          if (++requests <= 2) {
            throw LocalAiMissingAnswerException('Response budget exhausted');
          }
          final group = cleaner
              .fullCleanerReview(owner)!
              .groups
              .firstWhere((g) => g.analysis == null);
          return jsonEncode({
            'group_id': group.id,
            'decision': 'KEEP',
            'reason': 'User data.',
          });
        },
      );
      final bloc = await local(runtime);
      bloc.add(const SendMessage('Review all', reviewEntireCleanerScan: true));
      await until(() => requests > 0 && !bloc.state.isLoading);
      expect(requests, 2); // One bounded attempt per batch, without splitting.
      expect(bloc.state.error, isNull);
      final review = cleaner.fullCleanerReview(owner)!;
      expect(review.isComplete, isTrue);
      expect(review.groups.first.usedFallback, isFalse);
      expect(review.groups.last.usedFallback, isFalse);
      expect(review.groups.first.analysis!.selectForCleanup, isFalse);
      expect(review.groups.every((g) => g.analysis!.fromScan), isTrue);
    },
  );

  final liveUrl = Platform.environment['CB_LOCAL_CHAT_TEST_URL'];
  test(
    'live local model full Cleaner groups',
    () async {
      const owner = 'live-group-review';
      final cleaner = DiskCleanerService.instance;
      tools = _Tools(tags, ownerTabId: owner);
      final cache = DiskTreeNode(
        name: 'cache.tmp',
        fullPath: r'C:\Temp\cache.tmp',
        isFile: true,
        sizeBytes: 10000,
        junkCategoryId: 'windows_temp',
      );
      final personal = DiskTreeNode(
        name: 'photo.jpg',
        fullPath: r'C:\Data\photo.jpg',
        isFile: true,
        sizeBytes: 100000000,
      );
      final paging = DiskTreeNode(
        name: 'pagefile.sys',
        fullPath: r'C:\pagefile.sys',
        isFile: true,
        sizeBytes: 1000000000,
      );
      final root = DiskTreeNode(
        name: 'C:',
        fullPath: r'C:\',
        children: [cache, personal, paging],
      );
      void publish() => cleaner.publishCleanerScanContext(
        ownerTabId: owner,
        root: root,
        reviewItem: (_, _) {
          publish();
          return true;
        },
        reviewGroup: (group, analysis) {
          for (final node in group.nodes) {
            node.isSelectedForDeletion = analysis.selectForCleanup;
          }
          publish();
          return true;
        },
      );
      publish();
      addTearDown(() => cleaner.clearCleanerScanContext(owner));
      final runtime = _Runtime([], liveUrl: liveUrl);
      final bloc = await local(runtime);
      final elapsed = Stopwatch()..start();
      bloc.add(
        const SendMessage(
          'Phân tích toàn bộ',
          reviewEntireCleanerScan: true,
          cleanerReviewLanguageCode: 'vi',
        ),
      );
      await until(
        () => bloc.state.messages.length >= 2 && !bloc.state.isLoading,
        timeout: const Duration(seconds: 150),
      );
      expect(bloc.state.error, isNull);
      final review = cleaner.fullCleanerReview(owner)!;
      expect(review.isComplete, isTrue);
      expect(review.groups.where((g) => g.usedFallback), isEmpty);
      expect(
        review.groups.every((g) => g.analysis!.reason != 'a concrete reason'),
        isTrue,
      );
      expect(personal.isSelectedForDeletion, isFalse);
      expect(paging.isSelectedForDeletion, isFalse);
      print(
        'LIVE CLEANER elapsed_ms=${elapsed.elapsedMilliseconds}, groups=${review.groups.length}, requests=${runtime.requests.length}, '
        'decisions=${review.groups.map((g) => g.analysis!.decision.name).toList()}',
      );
      print(
        'LIVE CLEANER reasons=${review.groups.map((g) => g.analysis!.reason).toList()}',
      );
    },
    skip: liveUrl == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  for (final scenario in ['files', 'tags', 'read', 'manage', 'content']) {
    test(
      'live local model common workflow: $scenario',
      () async {
        if (scenario == 'content') {
          // Enough look-alike documents that one search page is large.
          for (var i = 0; i < 150; i++) {
            await File(p.join(sandbox.path, 'notes', 'meeting-$i.md'))
                .create(recursive: true)
                .then(
                  (file) => file.writeAsString(
                    'Meeting $i: invoice review, budget and vendor follow-up. '
                    'Invoice drafts are pending approval.',
                  ),
                );
          }
        }
        final runtime = _Runtime([], liveUrl: liveUrl);
        final bloc = await local(runtime);
        final prompt = switch (scenario) {
          'files' => 'Tìm file report.txt trong thư mục hiện tại.',
          'tags' => 'Trong thư mục hiện tại có file nào gắn tag Work?',
          'read' => 'Đọc report.txt và cho tôi biết số hóa đơn.',
          'content' =>
            'Trong thư mục này, file nào có ghi số hóa đơn INV-2048? Tìm theo '
                'nội dung file.',
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
        await until(
          () => runtime.requests.isNotEmpty && !bloc.state.isLoading,
          timeout: const Duration(seconds: 150),
        );
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
          case 'content':
            expect(names, contains('search_content'));
            expect(bloc.state.messages.last.content, contains('report.txt'));
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
  _Tools(MemoryAgentTags tags, {super.ownerTabId}) : super(tagStore: tags);
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
  final String Function()? respond;
  final Future<String> Function()? asyncRespond;
  _Remote(this.responses, {this.respond, this.asyncRespond});
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
    final content = asyncRespond != null
        ? await asyncRespond!()
        : respond?.call() ?? responses[requests.length - 1];
    return AiChatResult(
      response: AiChatResponse(content: content),
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
    implements LocalAiConversationRuntime, LocalAiDirectConversationRuntime {
  final List<String> responses;
  final String? liveUrl;
  final requests = <List<Map<String, String>>>[];
  final systemPrompts = <String?>[];
  final http = _RealHttp().createHttpClient(null);
  final String Function()? respond;
  final Future<String> Function()? asyncRespond;
  _Runtime(this.responses, {this.liveUrl, this.respond, this.asyncRespond});
  @override
  Stream<String> sendConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
  }) => _streamConversation(
    model: model,
    messages: messages,
    systemPrompt: systemPrompt,
    maxTokens: maxTokens,
  );

  @override
  Stream<String> sendDirectConversationStream({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
  }) => _streamConversation(
    model: model,
    messages: messages,
    systemPrompt: systemPrompt,
    maxTokens: maxTokens,
    direct: true,
  );

  Stream<String> _streamConversation({
    required InstalledLocalModel model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
    bool direct = false,
  }) {
    requests.add(List.of(messages));
    systemPrompts.add(systemPrompt);
    if (liveUrl != null) {
      return LlamaCppChatClient(http).stream(
        baseUri: Uri.parse(liveUrl!),
        messages: [
          {'role': 'system', 'content': systemPrompt!},
          ...messages,
        ],
        maxResponseTokens: 2048,
        catalogId: model.catalogId,
        enableThinking: direct ? false : null,
      );
    }
    if (asyncRespond != null) return Stream.fromFuture(asyncRespond!());
    final text = respond?.call() ?? responses[requests.length - 1];
    // Like LlamaCppChatClient: the cut-off marker follows the text.
    const marker = LlamaCppChatClient.lengthLimitMarker;
    if (text.endsWith(marker)) {
      return Stream.fromIterable([
        text.substring(0, text.length - marker.length),
        marker,
      ]);
    }
    return Stream.value(text);
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

Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Agent did not settle.');
}
