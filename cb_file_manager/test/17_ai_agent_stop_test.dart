import 'dart:async';

import 'package:cb_file_manager/bloc/ai_agent/ai_agent_bloc.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_event.dart';
import 'package:cb_file_manager/models/ai/ai_message.dart';
import 'package:cb_file_manager/services/ai/ai_provider_service.dart';
import 'package:cb_file_manager/services/ai/providers/ai_provider.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/components/chat_input_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('17.01 stopped generation cannot overwrite a newer response', () async {
    final provider = _ControllableProviderService();
    final bloc = AiAgentBloc(providerService: provider);

    bloc.add(const SendMessage('first'));
    await provider.firstRequestStarted.future;
    expect(bloc.state.isLoading, isTrue);

    bloc.add(const StopGeneration());
    await _waitUntil(() => !bloc.state.isLoading);

    bloc.add(const SendMessage('second'));
    await _waitUntil(
      () =>
          !bloc.state.isLoading &&
          bloc.state.messages.isNotEmpty &&
          bloc.state.messages.last.content == 'second response',
    );

    provider.completeFirstRequest();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bloc.state.messages.last.content, 'second response');
    expect(bloc.state.error, isNull);
    await bloc.close();
  });

  test('17.02 chat input exposes a stop callback while loading', () {
    var stopCount = 0;
    final input = ChatInputBar(
      onSend: (_, _) {},
      onStop: () => stopCount++,
      isLoading: true,
    );

    expect(input.isLoading, isTrue);
    expect(input.onStop, isNotNull);
    input.onStop!();
    expect(stopCount, 1);
  });

  test('17.03 approved tool remains visible while it is running', () async {
    final provider = _ToolApprovalProviderService();
    final executor = _BlockingToolExecutor();
    final bloc = AiAgentBloc(providerService: provider, toolExecutor: executor);

    bloc.add(const SendMessage('Clean junk files'));
    await _waitUntil(() => bloc.state.pendingApproval != null);
    final approvalId = bloc.state.pendingApproval!.id;

    bloc.add(ApproveAction(approvalId));
    await executor.started.future;
    await _waitUntil(
      () =>
          bloc.state.pendingApproval == null &&
          bloc.state.thinkingText != null &&
          bloc.state.currentToolCalls.length == 1 &&
          bloc.state.currentToolCalls.single.isRunning,
    );

    expect(bloc.state.currentToolCalls.single.toolName, 'clean_disk_junk');

    executor.complete();
    await _waitUntil(() => !bloc.state.isLoading);
    await bloc.close();
  });
}

class _ControllableProviderService extends AiProviderService {
  final firstRequestStarted = Completer<void>();
  final _firstRequestResult = Completer<AiChatResult>();
  var _chatCalls = 0;

  @override
  Future<AiChatResult> chat(
    List<AiMessage> messages, {
    String? systemPrompt,
    String? preferredProviderId,
    String? preferredModelName,
  }) {
    _chatCalls++;
    if (_chatCalls == 1) {
      firstRequestStarted.complete();
      return _firstRequestResult.future;
    }
    return Future.value(_result('second response'));
  }

  @override
  Future<AiStreamResult> chatStream(
    List<AiMessage> messages, {
    String? systemPrompt,
    String? preferredProviderId,
    String? preferredModelName,
  }) async {
    return AiStreamResult(
      stream: Stream<String>.value('second response'),
      providerId: 'test',
    );
  }

  void completeFirstRequest() {
    _firstRequestResult.complete(_result('stale response'));
  }

  AiChatResult _result(String content) => AiChatResult(
    response: AiChatResponse(content: content),
    providerId: 'test',
  );
}

class _ToolApprovalProviderService extends AiProviderService {
  var _chatCalls = 0;

  @override
  Future<AiChatResult> chat(
    List<AiMessage> messages, {
    String? systemPrompt,
    String? preferredProviderId,
    String? preferredModelName,
  }) async {
    _chatCalls++;
    final content = _chatCalls == 1
        ? '<tool_call>{"name":"clean_disk_junk","arguments":'
              '{"scan_id":"scan-test","categories":["dev_cache"],'
              '"permanent":false}}</tool_call>'
        : 'Cleaning finished.';
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
    return AiStreamResult(
      stream: Stream<String>.value('Cleaning finished.'),
      providerId: 'test',
    );
  }
}

class _BlockingToolExecutor extends ToolExecutor {
  final started = Completer<void>();
  final _result = Completer<ToolResult>();

  @override
  Future<ToolResult> execute(ToolCall call) {
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  void complete() {
    _result.complete(
      const ToolResult(toolName: 'clean_disk_junk', output: 'Cleaned.'),
    );
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition was not reached before timeout.');
}
