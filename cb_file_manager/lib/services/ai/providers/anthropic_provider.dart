import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../models/ai/ai_message.dart';
import '../../../models/ai/ai_provider_model.dart';
import '../../../utils/app_logger.dart';
import 'ai_provider.dart';

/// AI provider implementation for the Anthropic Messages API.
///
/// Uses the `/v1/messages` endpoint with `x-api-key` authentication
/// and `anthropic-version` header.
class AnthropicProvider extends AiProvider {
  final AiProviderConfig config;
  late final HttpClient _client;

  static const String _anthropicVersion = '2023-06-01';

  AnthropicProvider(this.config) {
    _client = HttpClient()
      ..connectionTimeout = Duration(seconds: config.timeoutSeconds)
      ..idleTimeout = const Duration(seconds: 120);
  }

  @override
  Future<AiChatResponse> chat(
    List<AiMessage> messages, {
    String? systemPrompt,
  }) async {
    final url = _buildUrl('/messages');

    // Anthropic requires messages to alternate between user/assistant
    // and system prompt goes in a separate top-level field
    final apiMessages = <Map<String, String>>[];
    for (final msg in messages) {
      if (msg.role == AiMessageRole.system) continue; // handled separately
      apiMessages.add({
        'role': aiMessageRoleToApiString(msg.role),
        'content': msg.content,
      });
    }

    final bodyMap = <String, dynamic>{
      'model': config.modelName,
      'messages': apiMessages,
      'max_tokens': config.maxTokens,
      'temperature': config.temperature,
    };

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      bodyMap['system'] = systemPrompt;
    }

    final body = jsonEncode(bodyMap);

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final response = await _makeRequest(url, body);
        return _parseResponse(response);
      } on AiProviderException {
        if (attempt > config.maxRetries) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }

  @override
  Stream<String> chatStream(
    List<AiMessage> messages, {
    String? systemPrompt,
  }) {
    final controller = StreamController<String>();
    _startStream(controller, messages, systemPrompt: systemPrompt);
    return controller.stream;
  }

  Future<void> _startStream(
    StreamController<String> controller,
    List<AiMessage> messages, {
    String? systemPrompt,
  }) async {
    try {
      final url = _buildUrl('/messages');

      final apiMessages = <Map<String, String>>[];
      for (final msg in messages) {
        if (msg.role == AiMessageRole.system) continue;
        apiMessages.add({
          'role': aiMessageRoleToApiString(msg.role),
          'content': msg.content,
        });
      }

      final bodyMap = <String, dynamic>{
        'model': config.modelName,
        'messages': apiMessages,
        'max_tokens': config.maxTokens,
        'temperature': config.temperature,
        'stream': true,
      };

      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        bodyMap['system'] = systemPrompt;
      }

      final body = jsonEncode(bodyMap);

      final request = await _client.postUrl(url);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('x-api-key', config.apiKey);
      request.headers.set('anthropic-version', _anthropicVersion);
      request.headers.set('Accept', 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');
      request.persistentConnection = false;
      request.add(utf8.encode(body));
      final response = await request.close();

      if (response.statusCode != 200) {
        final errorBody = await response.transform(utf8.decoder).join();
        final errorType = _classifyHttpError(response.statusCode);
        String errorMessage;
        try {
          final errorJson = jsonDecode(errorBody) as Map<String, dynamic>;
          final error = errorJson['error'];
          errorMessage = error is Map
              ? (error['message'] as String? ?? errorBody)
              : errorBody;
        } catch (_) {
          errorMessage = errorBody;
        }
        controller.addError(AiProviderException(
          message: errorMessage,
          type: errorType,
          statusCode: response.statusCode,
        ));
        await controller.close();
        return;
      }

      // Parse Anthropic SSE stream from raw bytes
      final byteBuffer = <int>[];
      await for (final bytes in response) {
        byteBuffer.addAll(bytes);

        while (true) {
          final nlIndex = byteBuffer.indexOf(10); // \n
          if (nlIndex == -1) break;

          final lineBytes = byteBuffer.sublist(0, nlIndex);
          byteBuffer.removeRange(0, nlIndex + 1);

          final line = utf8.decode(lineBytes).trim();
          if (line.isEmpty) continue;
          if (!line.startsWith('data: ')) continue;

          final jsonStr = line.substring(6);
          try {
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            final eventType = json['type'] as String?;

            if (eventType == 'content_block_delta') {
              final delta = json['delta'] as Map<String, dynamic>?;
              if (delta != null && delta['type'] == 'text_delta') {
                final text = delta['text'] as String?;
                if (text != null && text.isNotEmpty) {
                  controller.add(text);
                }
              }
            } else if (eventType == 'message_stop') {
              await controller.close();
              return;
            }
          } catch (_) {
            // Skip malformed SSE lines
          }
        }
      }
      await controller.close();
    } on AiProviderException catch (e) {
      controller.addError(e);
      await controller.close();
    } on SocketException catch (e) {
      controller.addError(AiProviderException(
        message: 'Network error: ${e.message}',
        type: AiProviderErrorType.network,
      ));
      await controller.close();
    } on TimeoutException catch (_) {
      controller.addError(AiProviderException(
        message: 'Request timed out after ${config.timeoutSeconds}s',
        type: AiProviderErrorType.network,
      ));
      await controller.close();
    } catch (e) {
      controller.addError(AiProviderException(
        message: 'Stream error: $e',
        type: AiProviderErrorType.unknown,
      ));
      await controller.close();
    }
  }

  @override
  Future<bool> testConnection() async {
    try {
      final url = _buildUrl('/messages');
      final body = jsonEncode({
        'model': config.modelName,
        'messages': [
          {'role': 'user', 'content': 'Hello'}
        ],
        'max_tokens': 5,
      });
      final response = await _makeRequest(url, body);
      return response.containsKey('content');
    } catch (e) {
      AppLogger.warning('[Anthropic] Connection test failed', error: e);
      return false;
    }
  }

  @override
  Future<List<String>> listModels() async {
    // Anthropic does not expose a public /v1/models endpoint.
    // Return known models as of 2025.
    return [
      'claude-sonnet-4-20250514',
      'claude-opus-4-20250514',
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
      'claude-3-opus-20240229',
      'claude-3-haiku-20240307',
    ];
  }

  @override
  void dispose() {
    _client.close(force: true);
  }

  Uri _buildUrl(String path) {
    var endpoint = config.endpoint;
    if (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }
    if (endpoint.endsWith('/v1')) {
      return Uri.parse('$endpoint$path');
    }
    return Uri.parse('$endpoint/v1$path');
  }

  Future<Map<String, dynamic>> _makeRequest(Uri url, String body) async {
    try {
      final request = await _client.postUrl(url);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('x-api-key', config.apiKey);
      request.headers.set('anthropic-version', _anthropicVersion);
      request.add(utf8.encode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final statusCode = response.statusCode;

      if (statusCode == 200) {
        return jsonDecode(responseBody) as Map<String, dynamic>;
      }

      final errorType = _classifyHttpError(statusCode);
      String errorMessage;
      try {
        final errorJson = jsonDecode(responseBody) as Map<String, dynamic>;
        final error = errorJson['error'];
        errorMessage = error is Map
            ? (error['message'] as String? ?? responseBody)
            : responseBody;
      } catch (_) {
        errorMessage = responseBody;
      }

      throw AiProviderException(
        message: errorMessage,
        type: errorType,
        statusCode: statusCode,
      );
    } on AiProviderException {
      rethrow;
    } on SocketException catch (e) {
      throw AiProviderException(
        message: 'Network error: ${e.message}',
        type: AiProviderErrorType.network,
      );
    } on HttpException catch (e) {
      throw AiProviderException(
        message: 'HTTP error: ${e.message}',
        type: AiProviderErrorType.network,
      );
    } on TimeoutException catch (_) {
      throw AiProviderException(
        message: 'Request timed out after ${config.timeoutSeconds}s',
        type: AiProviderErrorType.network,
      );
    } catch (e) {
      throw AiProviderException(
        message: 'Unexpected error: $e',
        type: AiProviderErrorType.unknown,
      );
    }
  }

  AiChatResponse _parseResponse(Map<String, dynamic> json) {
    final content = json['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      throw const AiProviderException(
        message: 'No content in response',
        type: AiProviderErrorType.badRequest,
      );
    }

    // Anthropic returns content as an array of blocks
    final textBlocks = content
        .where((block) => (block as Map<String, dynamic>)['type'] == 'text')
        .map((block) => (block as Map<String, dynamic>)['text'] as String)
        .join('\n');

    final usage = json['usage'] as Map<String, dynamic>?;

    return AiChatResponse(
      content: textBlocks,
      promptTokens: (usage?['input_tokens'] as int?) ?? 0,
      completionTokens: (usage?['output_tokens'] as int?) ?? 0,
      finishReason: json['stop_reason'] as String?,
    );
  }

  AiProviderErrorType _classifyHttpError(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return AiProviderErrorType.auth;
    } else if (statusCode == 429) {
      return AiProviderErrorType.rateLimit;
    } else if (statusCode >= 500) {
      return AiProviderErrorType.server;
    } else if (statusCode >= 400) {
      return AiProviderErrorType.badRequest;
    }
    return AiProviderErrorType.unknown;
  }
}
