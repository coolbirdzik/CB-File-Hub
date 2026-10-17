import 'package:cb_file_manager/bloc/ai_agent/ai_agent_bloc.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_event.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_state.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/models/ai/ai_message.dart';
import 'package:cb_file_manager/models/ai/referenced_file.dart';
import 'package:cb_file_manager/services/ai/ai_provider_service.dart';
import 'package:cb_file_manager/services/ai/providers/ai_provider.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/ai_side_panel.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/components/chat_message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

AiMessage _message(
  String id,
  AiMessageRole role,
  String content, {
  String? error,
  List<ReferencedFile>? files,
}) => AiMessage(
  id: id,
  role: role,
  content: content,
  error: error,
  referencedFiles: files,
  timestamp: DateTime(2026),
);

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('vi'),
  supportedLocales: const [Locale('en'), Locale('vi')],
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final targetId in ['question', 'failed-answer']) {
    test(
      'retry $targetId replaces its turn and preserves attachments and history',
      () async {
        final provider = _Provider();
        final bloc = _SeededBloc(
          provider,
          AiAgentState(
            messages: [
              _message('earlier', AiMessageRole.user, 'Earlier question'),
              _message(
                'earlier-answer',
                AiMessageRole.assistant,
                'Earlier answer',
              ),
              _message(
                'question',
                AiMessageRole.user,
                'Inspect this scan',
                files: const [
                  ReferencedFile(
                    path: 'missing-scan.txt',
                    fileName: 'missing-scan.txt',
                    isTextFile: true,
                  ),
                ],
              ),
              _message(
                'partial',
                AiMessageRole.assistant,
                'Old partial response',
              ),
              _message(
                'failed-answer',
                AiMessageRole.assistant,
                '',
                error: 'Connection closed',
              ),
              _message('later', AiMessageRole.user, 'Later question'),
              _message('later-answer', AiMessageRole.assistant, 'Later answer'),
            ],
            error: 'Connection closed',
          ),
        );
        addTearDown(bloc.close);
        final done = bloc.stream.firstWhere(
          (s) =>
              !s.isLoading &&
              s.messages.isNotEmpty &&
              s.messages.last.content == 'Retried answer',
        );
        bloc.add(RetryLastMessage(messageId: targetId));
        await done.timeout(const Duration(seconds: 5));

        expect(provider.requests, hasLength(1));
        expect(
          provider.requests.single.where((m) => m.role == AiMessageRole.user),
          hasLength(2),
        );
        expect(
          provider.requests.single.last.content,
          contains('Inspect this scan'),
        );
        expect(
          provider.requests.single.last.content,
          contains('missing-scan.txt'),
        );
        expect(bloc.state.messages.map((m) => m.content), [
          'Earlier question',
          'Earlier answer',
          'Inspect this scan',
          'Retried answer',
        ]);
        expect(
          bloc.state.messages[2].referencedFiles!.single.path,
          'missing-scan.txt',
        );
        expect(bloc.state.error, isNull);
      },
    );
  }

  test('default retry does not duplicate the latest user message', () async {
    final provider = _Provider();
    final bloc = _SeededBloc(
      provider,
      AiAgentState(
        messages: [
          _message('question', AiMessageRole.user, 'Inspect the scan'),
          _message('partial', AiMessageRole.assistant, 'Checking...'),
          _message(
            'failed',
            AiMessageRole.assistant,
            '',
            error: 'Connection closed',
          ),
        ],
      ),
    );
    addTearDown(bloc.close);
    final done = bloc.stream.firstWhere(
      (s) =>
          !s.isLoading &&
          s.messages.isNotEmpty &&
          s.messages.last.content == 'Retried answer',
    );
    bloc.add(const RetryLastMessage());
    await done.timeout(const Duration(seconds: 5));
    expect(
      provider.requests.single.where((m) => m.role == AiMessageRole.user),
      hasLength(1),
    );
    expect(bloc.state.messages, hasLength(2));
  });

  test(
    'retry is ignored during generation or for an unknown message',
    () async {
      final provider = _Provider();
      final initial = AiAgentState(
        messages: [_message('question', AiMessageRole.user, 'Inspect')],
        isLoading: true,
      );
      final bloc = _SeededBloc(provider, initial);
      addTearDown(bloc.close);
      bloc.add(const RetryLastMessage());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, initial);
      expect(provider.requests, isEmpty);
      bloc.publish(initial.copyWith(isLoading: false));
      bloc.add(const RetryLastMessage(messageId: 'unknown'));
      await Future<void>.delayed(Duration.zero);
      expect(provider.requests, isEmpty);
      expect(bloc.state.messages, initial.messages);
    },
  );

  test('retry preserves a turn containing only attached files', () async {
    final provider = _Provider();
    final bloc = _SeededBloc(
      provider,
      AiAgentState(
        messages: [
          _message(
            'file',
            AiMessageRole.user,
            '',
            files: const [
              ReferencedFile(
                path: 'scan-only.txt',
                fileName: 'scan-only.txt',
                isTextFile: true,
              ),
            ],
          ),
          _message(
            'failed',
            AiMessageRole.assistant,
            '',
            error: 'Connection closed',
          ),
        ],
      ),
    );
    addTearDown(bloc.close);
    final done = bloc.stream.firstWhere(
      (s) =>
          !s.isLoading &&
          s.messages.isNotEmpty &&
          s.messages.last.content == 'Retried answer',
    );
    bloc.add(const RetryLastMessage());
    await done.timeout(const Duration(seconds: 5));
    expect(provider.requests, hasLength(1));
    expect(
      bloc.state.messages.first.referencedFiles!.single.path,
      'scan-only.txt',
    );
  });

  testWidgets('settled assistant exposes a localized Retry button', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(
        ChatMessageBubble(
          message: _message(
            'answer',
            AiMessageRole.assistant,
            'Previous answer',
          ),
          onRetry: () => retries++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Thử lại'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-message-retry')));
    expect(retries, 1);
  });

  testWidgets('error bubble exposes Retry without hover', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(
        ChatMessageBubble(
          message: _message(
            'failed',
            AiMessageRole.assistant,
            '',
            error: 'Connection closed',
          ),
          onRetry: () => retries++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thử lại'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-error-retry')));
    expect(retries, 1);
  });

  testWidgets('panel error banner retries when no assistant bubble exists', (
    tester,
  ) async {
    final provider = _Provider();
    final bloc = _SeededBloc(
      provider,
      AiAgentState(
        messages: [
          _message('question', AiMessageRole.user, 'Inspect the scan'),
        ],
        error: 'Connection closed before headers',
      ),
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 380,
          child: AiSidePanel(
            bloc: bloc,
            onClose: () {},
            width: 380,
            onWidthChanged: (_) {},
            onWidthChangeEnd: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-banner-retry')));
    // A rapid second click must still target the displayed user turn.
    await tester.tap(find.byKey(const ValueKey('chat-banner-retry')));
    await tester.pumpAndSettle();
    expect(provider.requests, hasLength(1));
    expect(
      bloc.state.messages.where((m) => m.role == AiMessageRole.user),
      hasLength(1),
    );
    expect(bloc.state.messages.last.content, 'Retried answer');
    expect(find.byKey(const ValueKey('chat-banner-retry')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _SeededBloc extends AiAgentBloc {
  _SeededBloc(AiProviderService provider, AiAgentState initial)
    : super(providerService: provider) {
    emit(initial);
  }
  void publish(AiAgentState next) => emit(next);
}

class _Provider extends AiProviderService {
  final requests = <List<AiMessage>>[];
  @override
  Future<AiChatResult> chat(
    List<AiMessage> messages, {
    String? systemPrompt,
    String? preferredProviderId,
    String? preferredModelName,
  }) async {
    requests.add(List.of(messages));
    return AiChatResult(
      providerId: 'test',
      response: const AiChatResponse(content: 'Retried answer'),
    );
  }
}
