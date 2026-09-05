import 'dart:convert';
import 'dart:io';

/// Uses the GGUF's own chat template instead of assuming every model is ChatML.
class LlamaCppChatClient {
  final HttpClient httpClient;

  LlamaCppChatClient(this.httpClient);

  Stream<String> stream({
    required Uri baseUri,
    required List<Map<String, String>> messages,
    required int maxResponseTokens,
  }) async* {
    final request = await httpClient.postUrl(
      baseUri.resolve('/v1/chat/completions'),
    );
    request.headers.contentType = ContentType.json;
    request.add(
      utf8.encode(
        jsonEncode({
          'messages': messages,
          'max_tokens': maxResponseTokens,
          'stream': true,
          'cache_prompt': true,
          'chat_template_kwargs': {'enable_thinking': true},
          // Keep reasoning separate so it can be displayed in a disclosure.
          'reasoning_format': 'auto',
          'temperature': 0.6,
          'top_k': 20,
          'top_p': 0.95,
          'min_p': 0.0,
        }),
      ),
    );

    final response = await request.close();
    if (response.statusCode != 200) {
      final body = await response.transform(utf8.decoder).join();
      throw StateError(
        'Local AI server returned HTTP ${response.statusCode}: $body',
      );
    }

    var hasContent = false;
    var finished = false;
    var reasoningOpen = false;
    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      if (payload == '[DONE]') {
        finished = true;
        break;
      }
      final event = jsonDecode(payload) as Map<String, dynamic>;
      if (event['error'] != null) {
        throw StateError('Local AI generation failed: ${event['error']}');
      }
      final choices = event['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) continue;
      final choice = choices.first as Map<String, dynamic>;
      final delta = choice['delta'] as Map<String, dynamic>?;
      final content = delta?['content'] as String?;
      final reasoning = delta?['reasoning_content'] as String?;
      // Preserve the String stream contract; the bloc splits tagged reasoning
      // into message metadata before parsing tools or displaying the answer.
      if (reasoning != null && reasoning.isNotEmpty) {
        if (!reasoningOpen) {
          yield '<think>';
          reasoningOpen = true;
        }
        yield reasoning;
      }
      if (content != null && content.isNotEmpty) {
        if (reasoningOpen) {
          yield '</think>';
          reasoningOpen = false;
        }
        hasContent = hasContent || content.trim().isNotEmpty;
        yield content;
      }
      if (choice['finish_reason'] != null) {
        if (reasoningOpen) {
          yield '</think>';
          reasoningOpen = false;
        }
        finished = true;
        if (choice['finish_reason'] == 'length' && !hasContent) {
          throw StateError(
            'The local model reached its response limit without an answer.',
          );
        }
      }
    }
    if (!finished) {
      throw StateError(
        'The local model response was interrupted. Please retry.',
      );
    }
    if (!hasContent) {
      throw StateError('The local model returned no answer. Please retry.');
    }
  }
}
