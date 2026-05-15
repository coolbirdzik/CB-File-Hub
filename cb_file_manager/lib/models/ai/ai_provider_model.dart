import 'package:equatable/equatable.dart';

/// The type of AI API to use for communication.
enum AiApiType { openaiCompatible, anthropic }

/// Authentication mode for an AI provider configuration.
enum AiProviderAuthMode {
  apiKey,
  codexOAuth,
}

String aiApiTypeToDbString(AiApiType type) {
  switch (type) {
    case AiApiType.openaiCompatible:
      return 'openai_compatible';
    case AiApiType.anthropic:
      return 'anthropic';
  }
}

AiApiType aiApiTypeFromDbString(String value) {
  switch (value) {
    case 'openai_compatible':
      return AiApiType.openaiCompatible;
    case 'anthropic':
      return AiApiType.anthropic;
    default:
      return AiApiType.openaiCompatible;
  }
}

String aiApiTypeDisplayName(AiApiType type) {
  switch (type) {
    case AiApiType.openaiCompatible:
      return 'OpenAI Compatible';
    case AiApiType.anthropic:
      return 'Anthropic';
  }
}

String aiProviderAuthModeToDbString(AiProviderAuthMode mode) {
  switch (mode) {
    case AiProviderAuthMode.apiKey:
      return 'api_key';
    case AiProviderAuthMode.codexOAuth:
      return 'codex_oauth';
  }
}

AiProviderAuthMode aiProviderAuthModeFromDbString(String? value) {
  switch (value) {
    case 'codex_oauth':
      return AiProviderAuthMode.codexOAuth;
    case 'api_key':
    default:
      return AiProviderAuthMode.apiKey;
  }
}

String aiProviderAuthModeDisplayName(AiProviderAuthMode mode) {
  switch (mode) {
    case AiProviderAuthMode.apiKey:
      return 'API Key';
    case AiProviderAuthMode.codexOAuth:
      return 'Codex OAuth';
  }
}

/// Configuration for a single AI provider.
///
/// Stored in the `ai_providers` SQLite table. Supports multiple providers
/// with priority-based fallback ordering.
class AiProviderConfig extends Equatable {
  final String id;
  final String name;
  final AiApiType apiType;
  final AiProviderAuthMode authMode;
  final String apiKey;
  final String endpoint;
  final String modelName;
  final double temperature;
  final int maxTokens;
  final String? systemPrompt;
  final int timeoutSeconds;
  final int maxRetries;
  final bool isEnabled;
  final int priority;
  final int createdAt;
  final int updatedAt;

  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.apiType,
    this.authMode = AiProviderAuthMode.apiKey,
    required this.apiKey,
    required this.endpoint,
    required this.modelName,
    this.temperature = 0.3,
    this.maxTokens = 4096,
    this.systemPrompt,
    this.timeoutSeconds = 30,
    this.maxRetries = 2,
    this.isEnabled = true,
    this.priority = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates an [AiProviderConfig] from a SQLite row map.
  factory AiProviderConfig.fromMap(Map<String, dynamic> map) {
    return AiProviderConfig(
      id: map['id'] as String,
      name: map['name'] as String,
      apiType: aiApiTypeFromDbString(map['api_type'] as String),
      authMode: aiProviderAuthModeFromDbString(map['auth_mode'] as String?),
      apiKey: map['api_key'] as String,
      endpoint: map['endpoint'] as String,
      modelName: map['model_name'] as String,
      temperature: (map['temperature'] as num?)?.toDouble() ?? 0.3,
      maxTokens: (map['max_tokens'] as int?) ?? 4096,
      systemPrompt: map['system_prompt'] as String?,
      timeoutSeconds: (map['timeout_seconds'] as int?) ?? 30,
      maxRetries: (map['max_retries'] as int?) ?? 2,
      isEnabled: (map['is_enabled'] as int?) == 1,
      priority: (map['priority'] as int?) ?? 0,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }

  /// Converts this config to a SQLite row map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'api_type': aiApiTypeToDbString(apiType),
      'auth_mode': aiProviderAuthModeToDbString(authMode),
      'api_key': apiKey,
      'endpoint': endpoint,
      'model_name': modelName,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'system_prompt': systemPrompt,
      'timeout_seconds': timeoutSeconds,
      'max_retries': maxRetries,
      'is_enabled': isEnabled ? 1 : 0,
      'priority': priority,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  AiProviderConfig copyWith({
    String? id,
    String? name,
    AiApiType? apiType,
    AiProviderAuthMode? authMode,
    String? apiKey,
    String? endpoint,
    String? modelName,
    double? temperature,
    int? maxTokens,
    String? systemPrompt,
    bool clearSystemPrompt = false,
    int? timeoutSeconds,
    int? maxRetries,
    bool? isEnabled,
    int? priority,
    int? createdAt,
    int? updatedAt,
  }) {
    return AiProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      apiType: apiType ?? this.apiType,
      authMode: authMode ?? this.authMode,
      apiKey: apiKey ?? this.apiKey,
      endpoint: endpoint ?? this.endpoint,
      modelName: modelName ?? this.modelName,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      systemPrompt:
          clearSystemPrompt ? null : (systemPrompt ?? this.systemPrompt),
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      maxRetries: maxRetries ?? this.maxRetries,
      isEnabled: isEnabled ?? this.isEnabled,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns the default endpoint URL for a given API type.
  static String defaultEndpoint(AiApiType apiType) {
    switch (apiType) {
      case AiApiType.openaiCompatible:
        return 'https://api.openai.com/v1';
      case AiApiType.anthropic:
        return 'https://api.anthropic.com/v1';
    }
  }

  @override
  List<Object?> get props => [
        id,
        name,
        apiType,
        authMode,
        apiKey,
        endpoint,
        modelName,
        temperature,
        maxTokens,
        systemPrompt,
        timeoutSeconds,
        maxRetries,
        isEnabled,
        priority,
        createdAt,
        updatedAt,
      ];
}

/// Available chat models grouped under a single configured provider.
class AiProviderModelCatalog extends Equatable {
  final String providerId;
  final String providerName;
  final AiApiType apiType;
  final AiProviderAuthMode authMode;
  final String defaultModelName;
  final List<String> models;

  const AiProviderModelCatalog({
    required this.providerId,
    required this.providerName,
    required this.apiType,
    required this.authMode,
    required this.defaultModelName,
    required this.models,
  });

  @override
  List<Object?> get props => [
        providerId,
        providerName,
        apiType,
        authMode,
        defaultModelName,
        models,
      ];
}
