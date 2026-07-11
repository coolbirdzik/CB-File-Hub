import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolExecutor.parseToolCalls', () {
    test('15.01 parses Gemma sentinel tool call and aliases cleaner scan name',
        () {
      const text =
          '<|tool_call>call:tool_call{name: "get_current_clean_cleaner_scan", "max_items": 20, "include_selected":true}<tool_call|>';

      expect(ToolExecutor.hasToolCalls(text), isTrue);

      final calls = ToolExecutor.parseToolCalls(text);

      expect(calls, hasLength(1));
      expect(calls.first.name, 'get_current_cleaner_scan');
      expect(calls.first.arguments['max_items'], 20);
      expect(calls.first.arguments['include_selected'], isTrue);
    });
  });
}
