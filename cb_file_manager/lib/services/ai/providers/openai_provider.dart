import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../models/ai/ai_message.dart';
import '../../../models/ai/ai_provider_model.dart';
import '../../../utils/app_logger.dart';
import 'ai_provider.dart';

/// AI provider implementation for OpenAI-compatible APIs.
///
/// Supports any endpoint that implements the `/v1/chat/completions` contract,
/// including OpenAI, OpenRouter, local Ollama, LM Studio, etc.
class OpenAiProvider extends AiProvider {
  final AiProviderConfig config;
  late final HttpClient _client;

  OpenAiProvider(this.config) {
    _client = HttpClient()
      ..connectionTimeout = Duration(seconds: config.timeoutSeconds)
      ..idleTimeout = const Duration(seconds: 120);
  }

  @override
  Future<AiChatResponse> chat(
    List<AiMessage> messages, {
    String? systemPrompt,
  }) async {
    final url = _buildUrl('/chat/completions');

    final apiMessages = <Map<String, String>>[];

    // Add system prompt as the first message
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }

    // Add conversation messages
    for (final msg in messages) {
      apiMessages.add({
        'role': aiMessageRoleToApiString(msg.role),
        'content': msg.content,
      });
    }

    final body = jsonEncode({
      'model': config.modelName,
      'messages': apiMessages,
      'temperature': config.temperature,
      'max_tokens': config.maxTokens,
    });

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final response = await _makeRequest(url, body);
        return _parseResponse(response);
      } on AiProviderException {
        if (attempt > config.maxRetries) rethrow;
        // Wait before retrying (exponential backoff)
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }

  @override
  Stream<String> chatStream(
    List<AiMessage> messages, {
    String? systemPrompt,
  }) {
    // Use a StreamController so connection + auth errors are thrown eagerly
    // before any listener subscribes, and SSE parsing happens asynchronously.
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
      final url = _buildUrl('/chat/completions');

      final apiMessages = <Map<String, String>>[];
      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        apiMessages.add({'role': 'system', 'content': systemPrompt});
      }
      for (final msg in messages) {
        apiMessages.add({
          'role': aiMessageRoleToApiString(msg.role),
          'content': msg.content,
        });
      }

      final body = jsonEncode({
        'model': config.modelName,
        'messages': apiMessages,
        'temperature': config.temperature,
        'max_tokens': config.maxTokens,
        'stream': true,
      });

      final request = await _client.postUrl(url);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      _setAuthHeader(request);
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

      // Parse SSE stream from raw bytes to avoid buffering
      final byteBuffer = <int>[];
      await for (final bytes in response) {
        byteBuffer.addAll(bytes);

        // Process all complete lines in the buffer
        while (true) {
          final nlIndex = byteBuffer.indexOf(10); // \n
          if (nlIndex == -1) break;

          final lineBytes = byteBuffer.sublist(0, nlIndex);
          byteBuffer.removeRange(0, nlIndex + 1);

          final line = utf8.decode(lineBytes).trim();
          if (line.isEmpty) continue;
          if (line == 'data: [DONE]') {
            await controller.close();
            return;
          }
          if (!line.startsWith('data: ')) continue;

          final jsonStr = line.substring(6);
          try {
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final delta = (choices[0] as Map<String, dynamic>)['delta']
                  as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                controller.add(content);
              }
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
      final url = _buildUrl('/chat/completions');
      final body = jsonEncode({
        'model': config.modelName,
        'messages': [
          {'role': 'user', 'content': 'Hello'}
        ],
        'max_tokens': 5,
      });
      final response = await _makeRequest(url, body);
      return response.containsKey('choices');
    } catch (e) {
      AppLogger.warning('[OpenAI] Connection test failed', error: e);
      return false;
    }
  }

  @override
  Future<List<String>> listModels() async {
    final url = _buildUrl('/models');
    try {
      final response = await _makeGetRequest(url);
      final data = response['data'] as List<dynamic>?;
      if (data == null) return [];
      final models = <String>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final id = item['id'] as String?;
          if (id != null) models.add(id);
        }
      }
      models.sort();
      return models;
    } catch (e) {
      AppLogger.warning('[OpenAI] Failed to list models', error: e);
      rethrow;
    }
  }

  @override
  void dispose() {
    _client.close(force: true);
  }

  Uri _buildUrl(String path) {
    var endpoint = config.endpoint;
    // Remove trailing slash
    if (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }
    // If endpoint already contains the path (e.g. /v1), use it directly
    if (endpoint.endsWith('/v1') || endpoint.endsWith('/v1/')) {
      return Uri.parse('$endpoint$path');
    }
    return Uri.parse('$endpoint$path');
  }

  Future<Map<String, dynamic>> _makeGetRequest(Uri url) async {
    try {
      final request = await _client.getUrl(url);
      _setAuthHeader(request);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final statusCode = response.statusCode;

      if (statusCode == 200) {
        return jsonDecode(responseBody) as Map<String, dynamic>;
      }

      final errorType = _classifyHttpError(statusCode);
      throw AiProviderException(
        message: 'Failed to list models: $statusCode',
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

  Future<Map<String, dynamic>> _makeRequest(Uri url, String body) async {
    try {
      final request = await _client.postUrl(url);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      _setAuthHeader(request);
      request.add(utf8.encode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final statusCode = response.statusCode;

      if (statusCode == 200) {
        return jsonDecode(responseBody) as Map<String, dynamic>;
      }

      // Classify error
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

  void _setAuthHeader(HttpClientRequest request) {
    if (_usesAzureOpenAiEndpoint) {
      request.headers.set('api-key', config.apiKey);
      return;
    }
    request.headers.set('Authorization', 'Bearer ${config.apiKey}');
  }

  bool get _usesAzureOpenAiEndpoint {
    final endpoint = config.endpoint.toLowerCase();
    return endpoint.contains('.openai.azure.com');
  }

  AiChatResponse _parseResponse(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const AiProviderException(
        message: 'No choices in response',
        type: AiProviderErrorType.badRequest,
      );
    }

    final firstChoice = choices[0] as Map<String, dynamic>;
    final message = firstChoice['message'] as Map<String, dynamic>?;
    final content = message?['content'] as String? ?? '';

    final usage = json['usage'] as Map<String, dynamic>?;

    return AiChatResponse(
      content: content,
      promptTokens: (usage?['prompt_tokens'] as int?) ?? 0,
      completionTokens: (usage?['completion_tokens'] as int?) ?? 0,
      finishReason: firstChoice['finish_reason'] as String?,
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
