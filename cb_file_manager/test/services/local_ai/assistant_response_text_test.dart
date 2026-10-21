import 'package:cb_file_manager/services/ai/assistant_response_text.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/models/ai/ai_message.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/components/chat_message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'inspection announcements need continuation, completed answers do not',
    () {
      for (final text in [
        '## 🐳 **Docker Storage Location Report**\n\n'
            'Để xem chi tiết vị trí Docker trên hệ thống, tôi sẽ kiểm tra scan đang hoạt động:',
        'Tôi sẽ kiểm tra scan hiện tại.',
        'Let me inspect the current scan.',
        'To locate Docker storage, I will check the current scan:',
        'I\'ll search the scanned files.',
        '<think>Need data</think>Mình sẽ tìm Docker trong scan.',
        // Seen from Qwen3.5-4B: announced the next tool, then stopped.
        'Để tìm file theo tên chính xác hơn, tôi sẽ dùng công cụ tìm kiếm '
            'tên file thay vì nội dung trong file:',
        'Tôi sẽ sử dụng search_files.',
        'I\'ll use search_files instead.',
        'Kết quả chưa đủ. Tiếp theo là danh sách:',
      ]) {
        expect(endsWithPendingInspection(text), isTrue, reason: text);
      }
      for (final text in [
        'Xin chào!',
        'Docker chiếm 20 GB ở C:/Docker/data.vhdx.',
        'Tôi sẽ kiểm tra scan. Kết quả: Docker chiếm 20 GB.',
        'Không có scan hiện tại. Hãy chạy scan trước.',
        'Tôi sẽ kiểm tra sau khi bạn cung cấp đường dẫn.',
        'If you want, I will check the scan.',
        'I will check the scan once you share it.',
        'Tôi sẽ kiểm tra scan được không?',
        '> Tôi sẽ kiểm tra scan.',
        'Ví dụ: "Tôi sẽ kiểm tra scan".',
        '<think>Tôi sẽ kiểm tra scan.</think>Xin chào!',
      ]) {
        expect(endsWithPendingInspection(text), isFalse, reason: text);
      }
    },
  );

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
