import 'package:equatable/equatable.dart';

/// A single file search result returned by the AI agent.
class AiSearchResult extends Equatable {
  /// Absolute file path.
  final String path;

  /// File name (extracted from path for convenience).
  final String fileName;

  /// Relevance score from 0–100 as determined by the AI.
  final int relevance;

  /// AI-generated explanation for why this file matches the query.
  final String explanation;

  /// Whether the file was verified to still exist on disk.
  final bool verified;

  const AiSearchResult({
    required this.path,
    required this.fileName,
    required this.relevance,
    required this.explanation,
    this.verified = true,
  });

  AiSearchResult copyWith({
    String? path,
    String? fileName,
    int? relevance,
    String? explanation,
    bool? verified,
  }) {
    return AiSearchResult(
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      relevance: relevance ?? this.relevance,
      explanation: explanation ?? this.explanation,
      verified: verified ?? this.verified,
    );
  }

  /// Parses a single result from the JSON object returned by the AI.
  factory AiSearchResult.fromAiJson(Map<String, dynamic> json) {
    final path = json['path'] as String? ?? '';
    final parts = path.split(RegExp(r'[/\\]'));
    return AiSearchResult(
      path: path,
      fileName: parts.isNotEmpty ? parts.last : path,
      relevance: (json['relevance'] as num?)?.toInt() ?? 0,
      explanation: json['explanation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'fileName': fileName,
        'relevance': relevance,
        'explanation': explanation,
        'verified': verified,
      };

  factory AiSearchResult.fromJson(Map<String, dynamic> json) => AiSearchResult(
        path: json['path'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        relevance: (json['relevance'] as num?)?.toInt() ?? 0,
        explanation: json['explanation'] as String? ?? '',
        verified: json['verified'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [path, fileName, relevance, explanation, verified];
}
