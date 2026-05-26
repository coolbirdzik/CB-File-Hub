import 'package:equatable/equatable.dart';

import '../../models/ai/ai_conversation.dart';
import '../../models/ai/ai_message.dart';
import '../../models/ai/ai_provider_model.dart';
import '../../models/ai/ai_search_result.dart';
import '../../services/ai/ai_approval.dart';
import '../../services/ai/file_context_builder.dart';

/// State for the AI agent BLoC.
class AiAgentState extends Equatable {
  final List<AiMessage> messages;
  final bool isLoading;
  final String? error;
  final List<AiSearchResult> results;
  final SearchScope searchScope;
  final String? activeProviderId;
  final String? selectedProviderId;
  final String? selectedModelName;
  final bool isProviderConfigured;
  final String currentPath;
  final String? thinkingText;
  final List<String> toolActivity;

  /// In-flight tool calls for the current streaming response. Each call is
  /// added when the agent starts the tool and updated when result arrives.
  /// UI renders these as collapsible chips inside the thinking bubble.
  final List<AiToolCall> currentToolCalls;

  /// Last raw API payload sent to the provider, for debug "View raw payload"
  /// inspection. Captured by the bloc before each chat/streamChat call.
  final Map<String, dynamic>? lastApiPayload;

  final List<AiProviderModelCatalog>? _providerModelCatalogs;
  final bool? _isLoadingProviderModels;

  /// Localized strings for thinking indicators (resolved from AppLocalizations
  /// at the UI layer and passed into the bloc).
  final List<String> thinkingPhrases;

  /// Localized string for "waiting for approval" indicator.
  final String waitingApproval;

  /// Localized string template for "running X tool" indicator.
  /// Use `String.replaceFirst('{}', toolName)` to fill in the tool name.
  final String runningToolTemplate;

  /// A pending action requiring user approval before the AI proceeds.
  final AiApprovalRequest? pendingApproval;

  /// The ID of the currently active conversation.
  final String? conversationId;

  /// Summaries of all persisted conversations (sorted by most-recently-updated).
  final List<AiConversationSummary> conversations;

  List<AiProviderModelCatalog> get providerModelCatalogs =>
      _providerModelCatalogs ?? const <AiProviderModelCatalog>[];

  bool get isLoadingProviderModels => _isLoadingProviderModels ?? false;

  const AiAgentState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.results = const [],
    this.searchScope = SearchScope.allDrives,
    this.activeProviderId,
    this.selectedProviderId,
    this.selectedModelName,
    this.isProviderConfigured = false,
    this.currentPath = '',
    this.thinkingText,
    this.toolActivity = const [],
    this.currentToolCalls = const [],
    this.lastApiPayload,
    List<AiProviderModelCatalog>? providerModelCatalogs,
    bool? isLoadingProviderModels,
    this.thinkingPhrases = const ['Thinking...'],
    this.waitingApproval = 'Waiting for your approval...',
    this.runningToolTemplate = 'Running {}...',
    this.pendingApproval,
    this.conversationId,
    this.conversations = const [],
  })  : _providerModelCatalogs = providerModelCatalogs,
        _isLoadingProviderModels = isLoadingProviderModels;

  AiAgentState copyWith({
    List<AiMessage>? messages,
    bool? isLoading,
    String? error,
    bool clearError = false,
    List<AiSearchResult>? results,
    SearchScope? searchScope,
    String? activeProviderId,
    String? selectedProviderId,
    String? selectedModelName,
    bool clearSelectedProvider = false,
    bool clearSelectedModel = false,
    bool? isProviderConfigured,
    String? currentPath,
    String? thinkingText,
    bool clearThinking = false,
    List<String>? toolActivity,
    bool clearToolActivity = false,
    List<AiToolCall>? currentToolCalls,
    bool clearCurrentToolCalls = false,
    Map<String, dynamic>? lastApiPayload,
    bool clearLastApiPayload = false,
    List<AiProviderModelCatalog>? providerModelCatalogs,
    bool? isLoadingProviderModels,
    List<String>? thinkingPhrases,
    String? waitingApproval,
    String? runningToolTemplate,
    AiApprovalRequest? pendingApproval,
    bool clearApproval = false,
    String? conversationId,
    bool clearConversationId = false,
    List<AiConversationSummary>? conversations,
  }) {
    return AiAgentState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      results: results ?? this.results,
      searchScope: searchScope ?? this.searchScope,
      activeProviderId: activeProviderId ?? this.activeProviderId,
      selectedProviderId: clearSelectedProvider
          ? null
          : (selectedProviderId ?? this.selectedProviderId),
      selectedModelName: clearSelectedModel
          ? null
          : (selectedModelName ?? this.selectedModelName),
      isProviderConfigured: isProviderConfigured ?? this.isProviderConfigured,
      currentPath: currentPath ?? this.currentPath,
      thinkingText: clearThinking ? null : (thinkingText ?? this.thinkingText),
      toolActivity:
          clearToolActivity ? const [] : (toolActivity ?? this.toolActivity),
      currentToolCalls: clearCurrentToolCalls
          ? const []
          : (currentToolCalls ?? this.currentToolCalls),
      lastApiPayload: clearLastApiPayload
          ? null
          : (lastApiPayload ?? this.lastApiPayload),
      providerModelCatalogs:
          providerModelCatalogs ?? this.providerModelCatalogs,
      isLoadingProviderModels:
          isLoadingProviderModels ?? this.isLoadingProviderModels,
      thinkingPhrases: thinkingPhrases ?? this.thinkingPhrases,
      waitingApproval: waitingApproval ?? this.waitingApproval,
      runningToolTemplate: runningToolTemplate ?? this.runningToolTemplate,
      pendingApproval:
          clearApproval ? null : (pendingApproval ?? this.pendingApproval),
      conversationId:
          clearConversationId ? null : (conversationId ?? this.conversationId),
      conversations: conversations ?? this.conversations,
    );
  }

  @override
  List<Object?> get props => [
        messages,
        isLoading,
        error,
        results,
        searchScope,
        activeProviderId,
        selectedProviderId,
        selectedModelName,
        isProviderConfigured,
        currentPath,
        thinkingText,
        toolActivity,
        currentToolCalls,
        lastApiPayload,
        providerModelCatalogs,
        isLoadingProviderModels,
        thinkingPhrases,
        waitingApproval,
        runningToolTemplate,
        pendingApproval,
        conversationId,
        conversations,
      ];
}
