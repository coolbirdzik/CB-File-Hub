import '../../../models/ai/ai_message.dart';

/// Response from an AI chat completion request.
class AiChatResponse {
  final String content;
  final int promptTokens;
  final int completionTokens;
  final String? finishReason;

  const AiChatResponse({
    required this.content,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.finishReason,
  });
}

/// Error categories for AI provider failures.
enum AiProviderErrorType {
  /// Authentication failure (401/403).
  auth,

  /// Rate limit exceeded (429).
  rateLimit,

  /// Server error (5xx).
  server,

  /// Network / timeout error.
  network,

  /// Request was malformed or model rejected it.
  badRequest,

  /// Unknown or unclassifiable error.
  unknown,
}

/// Exception thrown by AI providers with categorized error type.
class AiProviderException implements Exception {
  final String message;
  final AiProviderErrorType type;
  final int? statusCode;

  const AiProviderException({
    required this.message,
    required this.type,
    this.statusCode,
  });

  @override
  String toString() => 'AiProviderException($type): $message';
}

/// Abstract interface for AI chat providers.
///
/// Implementations must handle HTTP communication with a specific API
/// (OpenAI-compatible or Anthropic) and translate responses to [AiChatResponse].
abstract class AiProvider {
  /// Sends a list of messages to the AI and returns the full response.
  ///
  /// The [systemPrompt] is prepended as a system message if provided.
  /// Throws [AiProviderException] on failure.
  Future<AiChatResponse> chat(
    List<AiMessage> messages, {
    String? systemPrompt,
  });

  /// Sends a list of messages to the AI and returns a stream of text deltas.
  ///
  /// Each string emitted is a partial content chunk. Concatenate them all
  /// to get the full response. The stream closes when the response is complete.
  /// Throws [AiProviderException] on connection/auth failure before streaming.
  Stream<String> chatStream(
    List<AiMessage> messages, {
    String? systemPrompt,
  });

  /// Tests whether the provider is reachable and the API key is valid.
  ///
  /// Returns `true` if the connection is healthy.
  Future<bool> testConnection();

  /// Fetches the list of available models from the provider.
  ///
  /// Returns a list of model ID strings. May throw [AiProviderException].
  Future<List<String>> listModels();

  /// Releases any resources held by this provider.
  void dispose();
}
