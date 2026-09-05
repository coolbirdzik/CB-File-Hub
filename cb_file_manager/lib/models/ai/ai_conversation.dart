import 'dart:io';

/// A lightweight summary of a conversation (no messages loaded).
///
/// Used for the conversation list sidebar. Full messages are loaded
/// on demand via [AiChatHistoryService.loadConversation].
class AiConversationSummary {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The directory the user was browsing when the conversation started.
  final String initialPath;

  const AiConversationSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.initialPath = '',
  });

  /// Short display name for the initial path (last folder name).
  String get initialPathShort {
    if (initialPath.isEmpty) return '';
    final parts = initialPath
        .split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isNotEmpty ? parts.last : initialPath;
  }

  AiConversationSummary copyWith({
    String? title,
    DateTime? updatedAt,
    String? initialPath,
  }) {
    return AiConversationSummary(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      initialPath: initialPath ?? this.initialPath,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'initialPath': initialPath,
  };

  factory AiConversationSummary.fromJson(
    Map<String, dynamic> json,
  ) => AiConversationSummary(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Conversation',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    initialPath: json['initialPath'] as String? ?? '',
  );
}
