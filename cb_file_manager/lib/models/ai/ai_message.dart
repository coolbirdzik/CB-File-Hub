import 'package:equatable/equatable.dart';

import 'ai_search_result.dart';
import 'referenced_file.dart';

/// The role of a chat message participant.
enum AiMessageRole { user, assistant, system, tool }

String aiMessageRoleToApiString(AiMessageRole role) {
  switch (role) {
    case AiMessageRole.tool:
      return 'user'; // tool results are sent as user messages to the API
    default:
      return role.toString().split('.').last;
  }
}

/// A tool invocation record shown in the chat.
class AiToolCall {
  final String toolName;
  final String arguments;
  final String? result;
  final bool success;

  const AiToolCall({
    required this.toolName,
    required this.arguments,
    this.result,
    this.success = true,
  });

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'arguments': arguments,
        'result': result,
        'success': success,
      };

  factory AiToolCall.fromJson(Map<String, dynamic> json) => AiToolCall(
        toolName: json['toolName'] as String? ?? '',
        arguments: json['arguments'] as String? ?? '',
        result: json['result'] as String?,
        success: json['success'] as bool? ?? true,
      );
}

/// A single message in an AI chat conversation.
class AiMessage extends Equatable {
  final String id;
  final AiMessageRole role;
  final String content;
  final DateTime timestamp;

  /// Parsed search results attached to this assistant message.
  final List<AiSearchResult>? searchResults;

  /// Whether this message is still being streamed / loading.
  final bool isLoading;

  /// Error message if the AI request failed.
  final String? error;

  /// Tool calls made by the AI in this message.
  final List<AiToolCall>? toolCalls;

  /// Files referenced (dropped/dragged) into the chat by the user.
  final List<ReferencedFile>? referencedFiles;

  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.searchResults,
    this.isLoading = false,
    this.error,
    this.toolCalls,
    this.referencedFiles,
  });

  AiMessage copyWith({
    String? content,
    List<AiSearchResult>? searchResults,
    bool? isLoading,
    String? error,
    bool clearError = false,
    List<AiToolCall>? toolCalls,
    List<ReferencedFile>? referencedFiles,
  }) {
    return AiMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      searchResults: searchResults ?? this.searchResults,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      toolCalls: toolCalls ?? this.toolCalls,
      referencedFiles: referencedFiles ?? this.referencedFiles,
    );
  }

  @override
  List<Object?> get props => [
        id,
        role,
        content,
        timestamp,
        searchResults,
        isLoading,
        error,
        toolCalls,
        referencedFiles,
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.toString().split('.').last,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'searchResults': searchResults?.map((r) => r.toJson()).toList(),
        'toolCalls': toolCalls?.map((c) => c.toJson()).toList(),
        'referencedFiles': referencedFiles?.map((f) => f.toJson()).toList(),
      };

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    final roleStr = json['role'] as String? ?? 'user';
    final role = AiMessageRole.values.firstWhere(
      (r) => r.toString().split('.').last == roleStr,
      orElse: () => AiMessageRole.user,
    );
    final searchResultsJson = json['searchResults'] as List<dynamic>?;
    final toolCallsJson = json['toolCalls'] as List<dynamic>?;
    final referencedFilesJson = json['referencedFiles'] as List<dynamic>?;
    return AiMessage(
      id: json['id'] as String? ?? '',
      role: role,
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      searchResults: searchResultsJson
          ?.map((r) => AiSearchResult.fromJson(r as Map<String, dynamic>))
          .toList(),
      toolCalls: toolCallsJson
          ?.map((c) => AiToolCall.fromJson(c as Map<String, dynamic>))
          .toList(),
      referencedFiles: referencedFilesJson
          ?.map((f) => ReferencedFile.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}
