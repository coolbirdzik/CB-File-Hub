import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/local_ai/llama_cpp_chat_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cb_file_manager/services/ai/assistant_response_text.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';

void main() {
  for (final profile in [
    ('unsloth/Qwen3.5-2B-GGUF', 0.7, 20, 0.8, false),
    ('unsloth/Qwen3.5-4B-GGUF', 1.0, 20, 0.95, true),
    ('unsloth/Qwen3-4B-Instruct-2507-GGUF', 0.7, 20, 0.8, false),
  ]) {
    test('uses publisher generation settings for ${profile.$1}', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final http = HttpClient();
      addTearDown(() async {
        http.close(force: true);
        await server.close(force: true);
      });
      final served = server.first.then((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['temperature'], profile.$2);
        expect(body['top_k'], profile.$3);
        expect(body['top_p'], profile.$4);
        expect(body['chat_template_kwargs']?['enable_thinking'], profile.$5);
        if (profile.$1.contains('Qwen3.5')) {
          expect(body['presence_penalty'], 1.5);
        }
        request.response.write(
          'data: {"choices":[{"delta":{"content":"OK"},"finish_reason":"stop"}]}\n\n',
        );
        await request.response.close();
      });
      expect(
        await LlamaCppChatClient(http)
            .stream(
              baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
              messages: [
                {'role': 'user', 'content': 'Hi'},
              ],
              maxResponseTokens: 100,
              catalogId: profile.$1,
            )
            .join(),
        'OK',
      );
      await served;
    });
  }

  test('chat template receives roles; reasoning never reaches content', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = HttpClient();
    addTearDown(() async {
      http.close(force: true);
      await server.close(force: true);
    });
    final served = server.first.then((request) async {
      expect(request.uri.path, '/v1/chat/completions');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body['messages'], [
        {'role': 'system', 'content': 'System'},
        {'role': 'user', 'content': 'Alo'},
        {'role': 'assistant', 'content': 'Xin chào'},
        {'role': 'user', 'content': 'gì vậy'},
      ]);
      expect(body['chat_template_kwargs']['enable_thinking'], true);
      expect(body['max_tokens'], 100);
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      for (final delta in [
        {
          'reasoning_content':
              '<tool_call>{"name":"list_all_tags","arguments":{}}</tool_call>',
        },
        {'content': 'Xin '},
        {'content': 'chào!'},
      ]) {
        request.response.write(
          'data: ${jsonEncode({
            'choices': [
              {'delta': delta},
            ],
          })}\n\n',
        );
      }
      request.response.write(
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
      );
      await request.response.close();
    });
    final result = await LlamaCppChatClient(http)
        .stream(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          messages: [
            {'role': 'system', 'content': 'System'},
            {'role': 'user', 'content': 'Alo'},
            {'role': 'assistant', 'content': 'Xin chào'},
            {'role': 'user', 'content': 'gì vậy'},
          ],
          maxResponseTokens: 100,
        )
        .join();
    await served;
    expect(stripAssistantReasoning(result), 'Xin chào!');
    expect(extractAssistantReasoning(result), contains('list_all_tags'));
    expect(ToolExecutor.parseToolCalls(result), isEmpty);
  });

  for (final entry in {
    'empty answer':
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
    'reasoning exhausted budget':
        'data: {"choices":[{"delta":{"reasoning_content":"thinking"},"finish_reason":"length"}]}\n\n',
    'server error': 'data: {"error":{"message":"generation failed"}}\n\n',
    'disconnected stream':
        'data: {"choices":[{"delta":{"content":"Partial"}}]}\n\n',
  }.entries) {
    test('${entry.key} surfaces an error instead of empty success', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final http = HttpClient();
      addTearDown(() async {
        http.close(force: true);
        await server.close(force: true);
      });
      final served = server.first.then((request) async {
        await request.drain<void>();
        request.response.write(entry.value);
        await request.response.close();
      });
      await expectLater(
        LlamaCppChatClient(http)
            .stream(
              baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
              messages: [
                {'role': 'user', 'content': 'Hi'},
              ],
              maxResponseTokens: 100,
            )
            .toList(),
        throwsStateError,
      );
      await served;
    });
  }
}
