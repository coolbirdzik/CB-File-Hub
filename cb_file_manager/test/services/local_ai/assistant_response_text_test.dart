import 'package:cb_file_manager/services/ai/assistant_response_text.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/models/ai/ai_message.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/components/chat_message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('split reasoning tags stay hidden throughout streaming', () {
    const reasoning =
        '<think>Maybe call <tool_call>{"name":"list_all_tags","arguments":{}}</tool_call></think>';
    for (var i = 1; i <= reasoning.length; i++) {
      final partial = reasoning.substring(0, i);
      expect(stripAssistantReasoning(partial), isEmpty, reason: 'prefix $i');
      expect(ToolExecutor.parseToolCalls(partial), isEmpty);
      expect(ToolExecutor.hasToolCalls(partial), false);
    }
    expect(stripAssistantReasoning('$reasoning Xin chào'), 'Xin chào');
    expect(
      stripAssistantReasoning('Reasoning supplied by template</think>Answer'),
      'Answer',
    );
  });

  test('only the final tool call can execute', () {
    const text =
        '<think><tool_call>{"name":"delete_file","arguments":{"path":"C:/file"}}</tool_call></think>'
        '<tool_call>{"name":"list_directory","arguments":{"path":"C:/"}}</tool_call>';
    expect(ToolExecutor.parseToolCalls(text).map((call) => call.name), [
      'list_directory',
    ]);
  });

  testWidgets('settled empty messages have no bubble', (tester) async {
    for (final content in ['', '  \n']) {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatMessageBubble(
            message: AiMessage(
              id: 'empty',
              role: AiMessageRole.assistant,
              content: content,
              timestamp: DateTime(2026),
            ),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(ChatMessageBubble),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
    }
  });

  testWidgets(
    'reasoning starts collapsed, expands, and stays open during streaming',
    (tester) async {
      Widget chat(
        String reasoning, {
        bool loading = false,
        bool legacy = false,
      }) => MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: ChatMessageBubble(
            message: AiMessage(
              id: 'thinking',
              role: AiMessageRole.assistant,
              content: legacy ? '<think>$reasoning</think>Answer' : 'Answer',
              reasoning: legacy ? null : reasoning,
              isLoading: loading,
              timestamp: DateTime(2026),
            ),
          ),
        ),
      );
      await tester.pumpWidget(chat('First thought', loading: true));
      await tester.pump();
      expect(find.text('Thinking'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-reasoning-content')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('chat-reasoning-toggle')));
      await tester.pump();
      expect(find.text('First thought'), findsOneWidget);
      await tester.pumpWidget(chat('First thought, continued', loading: true));
      expect(find.text('First thought, continued'), findsOneWidget);
      await tester.pumpWidget(chat('First thought, continued'));
      expect(find.text('First thought, continued'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-reasoning-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-reasoning-content')),
        findsNothing,
      );
      await tester.pumpWidget(chat('Legacy thought', legacy: true));
      await tester.tap(find.byKey(const ValueKey('chat-reasoning-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Legacy thought'), findsOneWidget);
    },
  );
}
