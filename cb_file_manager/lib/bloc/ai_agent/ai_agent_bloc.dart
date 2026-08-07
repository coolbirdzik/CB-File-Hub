import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/ai/ai_conversation.dart';
import '../../models/ai/ai_message.dart';
import '../../models/ai/ai_provider_model.dart';
import '../../models/ai/ai_search_result.dart';
import '../../models/ai/referenced_file.dart';
import '../../services/ai/ai_approval.dart';
import '../../services/ai/ai_chat_history_service.dart';
import '../../services/ai/ai_provider_service.dart';
import '../../services/ai/providers/ai_provider.dart';
import '../../services/ai/tool_executor.dart';
import '../../services/local_ai/local_ai_advisor_service.dart';
import '../../utils/app_logger.dart';
import 'ai_agent_event.dart';
import 'ai_agent_state.dart';

/// BLoC managing the AI chat agent and smart search functionality.
class AiAgentBloc extends Bloc<AiAgentEvent, AiAgentState> {
  final AiProviderService _providerService;
  final AiChatHistoryService? _historyService;
  final LocalAiAdvisorService? _localAiService;
  final ToolExecutor _toolExecutor;
  static const _uuid = Uuid();
  static const String _localAiProviderId = '__local_ai__';
  static const String _lastProviderIdKey = 'ai_chat_last_provider_id';
  static const String _lastModelNameKey = 'ai_chat_last_model_name';
  static const int _softContextCharLimit = 24000;
  static const int _hardContextCharLimit = 14000;
  static const int _minRecentMessagesToKeep = 8;
  static const int _maxSummaryChars = 6000;

  // Completer for pausing execution while waiting for user approval
  Completer<bool>? _approvalCompleter;
  int _generationSequence = 0;
  int? _activeGenerationId;
  StreamSubscription<String>? _activeStreamSubscription;
  Completer<void>? _activeStreamCompleter;

  AiAgentBloc({
    required AiProviderService providerService,
    AiChatHistoryService? historyService,
    LocalAiAdvisorService? localAiService,
    ToolExecutor? toolExecutor,
    String? ownerTabId,
    List<String> thinkingPhrases = const ['Thinking...'],
    String waitingApproval = 'Waiting for your approval...',
    String runningToolTemplate = 'Running {}...',
  })  : _providerService = providerService,
        _historyService = historyService,
        _localAiService = localAiService,
        _toolExecutor = toolExecutor ?? ToolExecutor(ownerTabId: ownerTabId),
        super(AiAgentState(
          thinkingPhrases: thinkingPhrases,
          waitingApproval: waitingApproval,
          runningToolTemplate: runningToolTemplate,
        )) {
    on<InitializeAiAgent>(_onInitialize);
    on<SendMessage>(_onSendMessage);
    on<StopGeneration>(_onStopGeneration);
    on<ClearChat>(_onClearChat);
    on<EditMessage>(_onEditMessage);
    on<ChangeSearchScope>(_onChangeSearchScope);
    on<QuickSearch>(_onQuickSearch);
    on<UpdateCurrentPath>(_onUpdateCurrentPath);
    on<RetryLastMessage>(_onRetryLastMessage);
    on<ProviderChanged>(_onProviderChanged);
    on<RefreshProviderModels>(_onRefreshProviderModels);
    on<SelectChatModel>(_onSelectChatModel);
    on<ApproveAction>(_onApprove);
    on<RejectAction>(_onReject);
    on<NewConversation>(_onNewConversation);
    on<SwitchConversation>(_onSwitchConversation);
    on<DeleteConversation>(_onDeleteConversation);
    on<RefreshConversations>(_onRefreshConversations);
    on<ClearError>((event, emit) {
      emit(state.copyWith(clearError: true));
    });
  }

  /// Auto-saves the current conversation whenever messages settle (not loading).
  @override
  void onChange(Change<AiAgentState> change) {
    super.onChange(change);
    final next = change.nextState;
    if (!next.isLoading &&
        next.messages != change.currentState.messages &&
        next.messages.isNotEmpty &&
        next.conversationId != null) {
      final title = _titleFromMessages(next.messages);
      _historyService
          ?.saveConversation(next.conversationId!, title, next.messages,
              initialPath: next.currentPath)
          .then((_) {
        // Refresh conversation list so sidebar stays current
        add(const RefreshConversations());
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Event handlers
  // ---------------------------------------------------------------------------

  Future<void> _onInitialize(
    InitializeAiAgent event,
    Emitter<AiAgentState> emit,
  ) async {
    final hasProvider = await _providerService.hasConfiguredProvider;
    final summaries = await _historyService?.loadAllSummaries() ?? [];
    final modelCatalogs = hasProvider
        ? await _providerService.getEnabledProviderModelCatalogs()
        : const <AiProviderModelCatalog>[];
    final catalogs = _mergeLocalAiCatalog(modelCatalogs);
    final persisted = await _loadPersistedSelection();
    final selection = _resolveModelSelection(
      catalogs: catalogs,
      selectedProviderId: state.selectedProviderId ?? persisted.providerId,
      selectedModelName: state.selectedModelName ?? persisted.modelName,
    );

    String conversationId;
    List<AiMessage> messages;
    final normalizedWorkspacePath =
        AiChatHistoryService.normalizeWorkspacePath(event.workspacePath);
    if (normalizedWorkspacePath.isNotEmpty) {
      final matchingSummary = await _historyService
          ?.findLatestSummaryForPath(normalizedWorkspacePath);
      if (matchingSummary != null) {
        conversationId = matchingSummary.id;
        messages =
            await _historyService?.loadConversation(conversationId) ?? [];
      } else {
        // Path has no prior conversation — start fresh but keep showing
        // the conversation list so the user can switch to other paths.
        conversationId = _uuid.v4();
        messages = [];
      }
    } else if (!event.startFreshConversation && summaries.isNotEmpty) {
      conversationId = summaries.first.id;
      messages = await _historyService?.loadConversation(conversationId) ?? [];
    } else {
      conversationId = _uuid.v4();
      messages = [];
    }

    emit(state.copyWith(
      isProviderConfigured: hasProvider || catalogs.isNotEmpty,
      messages: messages,
      conversationId: conversationId,
      conversations: summaries,
      currentPath: event.workspacePath,
      providerModelCatalogs: catalogs,
      selectedProviderId: selection.providerId,
      selectedModelName: selection.modelName,
      isLoadingProviderModels: false,
    ));
  }

  Future<void> _onSendMessage(
    SendMessage event,
    Emitter<AiAgentState> emit,
  ) async {
    if (event.message.trim().isEmpty && event.referencedFiles.isEmpty) return;
    if (state.isLoading) return;

    final generationId = ++_generationSequence;
    _activeGenerationId = generationId;

    if (_isLocalAiSelected()) {
      await _onLocalAiSendMessage(event, emit, generationId);
      return;
    }

    // Build ReferencedFile objects and auto-read text files
    final referencedFiles = await _buildReferencedFiles(event.referencedFiles);

    final userMessage = AiMessage(
      id: _uuid.v4(),
      role: AiMessageRole.user,
      content: event.message,
      timestamp: DateTime.now(),
      referencedFiles: referencedFiles.isNotEmpty ? referencedFiles : null,
    );

    // Build API message content: user text + file reference info for LLM
    final apiContent = _buildApiContent(event.message, referencedFiles);

    // Conversation messages sent to the API (grows with tool results)
    final apiMessages = <AiMessage>[
      ...state.messages.where((m) => m.role != AiMessageRole.system),
      AiMessage(
        id: _uuid.v4(),
        role: AiMessageRole.user,
        content: apiContent,
        timestamp: DateTime.now(),
      ),
    ];
    // Messages shown in the UI
    final displayMessages = [...state.messages, userMessage];
    final activity = <String>[];
    final allToolCalls = <AiToolCall>[];

    emit(state.copyWith(
      messages: displayMessages,
      isLoading: true,
      clearError: true,
      thinkingText: state.thinkingPhrases.isNotEmpty
          ? state.thinkingPhrases[0]
          : 'Thinking...',
      clearToolActivity: true,
      clearCurrentToolCalls: true,
      clearApproval: true,
    ));

    try {
      final systemPrompt = _buildSystemPrompt();
      int toolRound = 0;
      // Messages shown in the UI (grows with explanation + results)
      List<AiMessage> uiMessages = List.from(displayMessages);

      // Tool-calling loop: AI responds -> if tool_call -> execute -> feed back -> repeat
      while (toolRound <= ToolExecutor.maxToolCalls) {
        toolRound++;

        activity.add('> Calling AI provider (round $toolRound)...');
        emit(state.copyWith(
          thinkingText:
              state.thinkingPhrases[toolRound % state.thinkingPhrases.length],
          toolActivity: List.of(activity),
        ));

        // Call AI (non-streaming for tool rounds, streaming for final)
        final preparedContext = _prepareContextForProvider(
          apiMessages,
          systemPrompt: systemPrompt,
          activity: activity,
        );
        // Capture raw payload for debug "View raw payload" inspection
        emit(state.copyWith(
          lastApiPayload: _buildPayloadSnapshot(
            messages: preparedContext.messages,
            systemPrompt: preparedContext.systemPrompt,
            providerId: state.selectedProviderId,
            modelName: state.selectedModelName,
            stream: false,
          ),
        ));
        final result = await _providerService.chat(
          preparedContext.messages,
          systemPrompt: preparedContext.systemPrompt,
          preferredProviderId: state.selectedProviderId,
          preferredModelName: state.selectedModelName,
        );
        _ensureGenerationActive(generationId);

        final responseText = result.response.content;

        // Check if AI wants to call tools
        if (!ToolExecutor.hasToolCalls(responseText)) {
          // No tool calls - stream this as the final answer
          await _streamFinalAnswer(
            emit,
            apiMessages: apiMessages,
            uiMessages: uiMessages,
            allToolCalls: allToolCalls,
            activity: activity,
            systemPrompt: systemPrompt,
            providerId: result.providerId,
            generationId: generationId,
          );
          return; // Done
        }

        // Parse all tool calls from the response.
        // If hasToolCalls() returned true but parsing yields nothing, the LLM
        // produced a malformed block - display the stripped content directly
        // without re-querying (to avoid infinite loops).
        final calls = ToolExecutor.parseToolCalls(responseText)
            .map(_toolExecutor.normalizeCall)
            .toList(growable: false);
        if (calls.isEmpty) {
          final displayContent =
              _stripJsonBlocks(_stripToolCallTags(responseText));
          emit(state.copyWith(
            messages: [
              ...uiMessages,
              AiMessage(
                id: _uuid.v4(),
                role: AiMessageRole.assistant,
                content: displayContent,
                timestamp: DateTime.now(),
                toolCalls:
                    allToolCalls.isNotEmpty ? List.of(allToolCalls) : null,
              ),
            ],
            isLoading: false,
            clearThinking: true,
            toolActivity: List.of(activity),
          ));
          return;
        }

        // Step 1: Extract agent's explanation text (before any tool call blocks)
        // and show it in the UI as an assistant message, added to API so LLM knows
        final explanationText = _stripToolCallTags(responseText).trim();

        // Build updated UI message list: append explanation text if any
        final List<AiMessage> updatedUiMessages;
        if (explanationText.isNotEmpty) {
          final explanationMsg = AiMessage(
            id: _uuid.v4(),
            role: AiMessageRole.assistant,
            content: explanationText,
            timestamp: DateTime.now(),
          );
          // Add to API messages so LLM knows we showed the text
          apiMessages.add(explanationMsg);
          updatedUiMessages = [...uiMessages, explanationMsg];
        } else {
          updatedUiMessages = uiMessages;
        }

        // Step 2: Collect all dangerous tool calls for a single combined approval
        final dangerousCalls = calls
            .where((c) => ToolExecutor.dangerousTools.contains(c.name))
            .toList();

        if (dangerousCalls.isNotEmpty) {
          // Show thinking text while waiting for approval
          activity.add('> Waiting for your approval...');
          emit(state.copyWith(
            messages: updatedUiMessages,
            thinkingText: state.waitingApproval,
            toolActivity: List.of(activity),
          ));

          // Build a single combined approval request
          final combinedRequest = _buildCombinedApprovalRequest(dangerousCalls);

          activity
              .add('> Approval required: ${dangerousCalls.length} action(s)');
          emit(state.copyWith(toolActivity: List.of(activity)));

          final approved = await _requestApproval(emit, combinedRequest);
          _ensureGenerationActive(generationId);

          if (!approved) {
            activity.add('  Rejected: User rejected all actions');
            emit(state.copyWith(
              toolActivity: List.of(activity),
              clearThinking: true,
            ));

            // Report blocked dangerous tools
            final rejectBuffer = StringBuffer();
            for (final call in dangerousCalls) {
              rejectBuffer.writeln(
                '<tool_result name="${call.name}">\nBlocked: User rejected.\n</tool_result>',
              );
            }
            rejectBuffer
                .writeln('STOP: User rejected all actions. Do not proceed.');
            apiMessages.add(AiMessage(
              id: _uuid.v4(),
              role: AiMessageRole.user,
              content: rejectBuffer.toString(),
              timestamp: DateTime.now(),
            ));
            // Continue loop - LLM will produce a final answer explaining the rejection
            continue;
          }

          activity.add('  Approved: All actions approved');
          emit(state.copyWith(
            toolActivity: List.of(activity),
            thinkingText: state.runningToolTemplate
                .replaceFirst('{}', dangerousCalls.first.name),
          ));
        }

        // Step 3: Execute all tool calls (dangerous ones are already approved)
        final toolResultBuffer = StringBuffer();
        for (final call in calls) {
          // Skip dangerous tools - already handled above
          if (ToolExecutor.dangerousTools.contains(call.name)) {
            activity.add('  Approved: ${call.name} (pre-approved)');
            _addRunningToolCall(allToolCalls, call);
            emit(state.copyWith(
              thinkingText:
                  state.runningToolTemplate.replaceFirst('{}', call.name),
              toolActivity: List.of(activity),
              currentToolCalls: List.of(allToolCalls),
            ));

            // Execute the dangerous tool without asking again
            final toolResult = await _toolExecutor.execute(call);
            _ensureGenerationActive(generationId);

            _completeRunningToolCall(
              allToolCalls,
              call,
              output: toolResult.output,
              success: toolResult.success,
            );

            activity.add(
                '  ${toolResult.success ? "OK" : "FAIL"}: ${_truncateOutput(toolResult.output)}');
            emit(state.copyWith(
              toolActivity: List.of(activity),
              currentToolCalls: List.of(allToolCalls),
            ));

            toolResultBuffer.writeln(
              '<tool_result name="${call.name}">\n${toolResult.output}\n</tool_result>',
            );
            continue;
          }

          activity
              .add('> Tool: ${call.name}(${_summarizeArgs(call.arguments)})');
          emit(state.copyWith(
            thinkingText:
                state.runningToolTemplate.replaceFirst('{}', call.name),
            toolActivity: List.of(activity),
            currentToolCalls: List.of(allToolCalls)
              ..add(_runningToolCall(call)),
          ));

          final toolResult = await _toolExecutor.execute(call);
          _ensureGenerationActive(generationId);

          allToolCalls.add(AiToolCall(
            toolName: call.name,
            arguments: jsonEncode(call.arguments),
            result: toolResult.output,
            success: toolResult.success,
          ));

          activity.add(
              '  ${toolResult.success ? "OK" : "FAIL"}: ${_truncateOutput(toolResult.output)}');
          emit(state.copyWith(
            toolActivity: List.of(activity),
            currentToolCalls: List.of(allToolCalls),
          ));

          toolResultBuffer.writeln(
            '<tool_result name="${call.name}">\n${toolResult.output}\n</tool_result>',
          );
        }

        // Feed tool results back to the AI
        apiMessages.add(AiMessage(
          id: _uuid.v4(),
          role: AiMessageRole.user,
          content: toolResultBuffer.toString(),
          timestamp: DateTime.now(),
        ));

        // Carry forward accumulated UI messages into next iteration
        uiMessages = updatedUiMessages;
      }

      // Max tool calls reached - ask for a final answer (streamed)
      activity.add('> Max tool calls reached, requesting final answer...');
      emit(state.copyWith(toolActivity: List.of(activity)));

      apiMessages.add(AiMessage(
        id: _uuid.v4(),
        role: AiMessageRole.user,
        content:
            'Please give your final answer now. Do not call any more tools.',
        timestamp: DateTime.now(),
      ));

      await _streamFinalAnswer(
        emit,
        apiMessages: apiMessages,
        uiMessages: uiMessages,
        allToolCalls: allToolCalls,
        activity: activity,
        systemPrompt: systemPrompt,
        providerId: null, // resolved inside helper
        generationId: generationId,
      );
    } on _GenerationStopped {
      return;
    } on AiProviderException catch (e) {
      if (_activeGenerationId != generationId) return;
      AppLogger.warning('[AiAgentBloc] Chat failed: ${e.message}');
      emit(state.copyWith(
        isLoading: false,
        error: e.message,
        clearThinking: true,
        toolActivity: List.of(activity),
      ));
    } catch (e) {
      if (_activeGenerationId != generationId) return;
      AppLogger.error('[AiAgentBloc] Unexpected error', error: e);
      emit(state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred: $e',
        clearThinking: true,
        toolActivity: List.of(activity),
      ));
    }
  }

  Future<void> _onLocalAiSendMessage(
    SendMessage event,
    Emitter<AiAgentState> emit,
    int generationId,
  ) async {
    final localService = _localAiService;
    if (localService == null) {
      emit(state.copyWith(
        error: 'Local AI service is not available.',
        isLoading: false,
        clearThinking: true,
      ));
      return;
    }

    final referencedFiles = await _buildReferencedFiles(event.referencedFiles);
    final userMessage = AiMessage(
      id: _uuid.v4(),
      role: AiMessageRole.user,
      content: event.message,
      timestamp: DateTime.now(),
      referencedFiles: referencedFiles.isNotEmpty ? referencedFiles : null,
    );

    final apiContent = _buildApiContent(event.message, referencedFiles);
    final apiMessages = <AiMessage>[
      ...state.messages.where((m) => m.role != AiMessageRole.system),
      AiMessage(
        id: _uuid.v4(),
        role: AiMessageRole.user,
        content: apiContent,
        timestamp: DateTime.now(),
      ),
    ];
    final displayMessages = [...state.messages, userMessage];
    final activity = <String>[];
    final allToolCalls = <AiToolCall>[];

    emit(state.copyWith(
      messages: displayMessages,
      isLoading: true,
      clearError: true,
      thinkingText: state.thinkingPhrases.isNotEmpty
          ? state.thinkingPhrases[0]
          : 'Thinking...',
      clearToolActivity: true,
      clearCurrentToolCalls: true,
      clearApproval: true,
      activeProviderId: _localAiProviderId,
    ));

    try {
      final systemPrompt = _buildSystemPrompt();
      var toolRound = 0;
      var uiMessages = List<AiMessage>.of(displayMessages);
      // Signatures of tool-call rounds already executed, to detect stuck loops
      // where a small local model keeps calling the same tool with the same
      // arguments without making progress.
      final seenToolSignatures = <String>{};

      while (toolRound <= ToolExecutor.maxToolCalls) {
        toolRound++;
        activity.add('> Calling Local AI (round $toolRound)...');
        emit(state.copyWith(
          thinkingText:
              state.thinkingPhrases[toolRound % state.thinkingPhrases.length],
          toolActivity: List.of(activity),
        ));

        final preparedContext = _prepareContextForProvider(
          apiMessages,
          systemPrompt: systemPrompt,
          activity: activity,
        );
        final localPrompt = _buildLocalTranscript(preparedContext.messages);
        emit(state.copyWith(
          lastApiPayload: _buildPayloadSnapshot(
            messages: preparedContext.messages,
            systemPrompt: preparedContext.systemPrompt,
            providerId: _localAiProviderId,
            modelName: state.selectedModelName,
            stream: true,
          ),
        ));

        final streamingId = _uuid.v4();
        final streamingMsg = AiMessage(
          id: streamingId,
          role: AiMessageRole.assistant,
          content: '',
          timestamp: DateTime.now(),
          toolCalls: allToolCalls.isNotEmpty ? List.of(allToolCalls) : null,
          isLoading: true,
        );
        emit(state.copyWith(
          messages: [...uiMessages, streamingMsg],
          clearThinking: true,
          toolActivity: List.of(activity),
          activeProviderId: _localAiProviderId,
        ));

        final rawBuffer = StringBuffer();
        await _consumeGenerationStream(
          generationId: generationId,
          stream: localService.sendChatMessageStream(
            message: localPrompt,
            systemPrompt: preparedContext.systemPrompt,
          ),
          onChunk: (chunk) {
            // Status messages from GGUF runtime are prefixed with [STATUS].
            if (chunk.startsWith('[STATUS]')) {
              final statusText = chunk.substring(8); // Remove "[STATUS]" prefix
              emit(state.copyWith(
                thinkingText: statusText,
                messages: [...uiMessages, streamingMsg],
                activeProviderId: _localAiProviderId,
              ));
              return;
            }

            rawBuffer.write(chunk);
            final displayText = _stripJsonBlocks(
              _stripToolCallTagsStreaming(rawBuffer.toString()),
            );
            // While the model is only emitting a tool call (no visible prose),
            // displayText is empty. Don't show an empty bubble that would flash
            // and disappear when the round resolves into a tool call; keep the
            // thinking indicator instead.
            if (displayText.isEmpty) {
              emit(state.copyWith(
                messages: uiMessages,
                activeProviderId: _localAiProviderId,
              ));
              return;
            }
            emit(state.copyWith(
              messages: [
                ...uiMessages,
                streamingMsg.copyWith(
                  content: displayText,
                  isLoading: true,
                ),
              ],
              clearThinking: true,
              activeProviderId: _localAiProviderId,
            ));
          },
        );

        final responseText = rawBuffer.toString();
        if (!ToolExecutor.hasToolCalls(responseText)) {
          final rawContent = rawBuffer.toString();
          final displayContent =
              _stripJsonBlocks(_stripToolCallTags(rawContent));
          final searchResults = _parseSearchResults(rawContent);

          if (searchResults.isNotEmpty) {
            activity.add('> Found ${searchResults.length} file(s)');
          }

          final assistantMessage = AiMessage(
            id: streamingId,
            role: AiMessageRole.assistant,
            content: displayContent.isEmpty
                ? '(The local model returned an empty response.)'
                : displayContent,
            timestamp: streamingMsg.timestamp,
            searchResults: searchResults.isNotEmpty ? searchResults : null,
            toolCalls: allToolCalls.isNotEmpty ? List.of(allToolCalls) : null,
            isLoading: false,
          );

          emit(state.copyWith(
            messages: [...uiMessages, assistantMessage],
            isLoading: false,
            results: searchResults,
            clearThinking: true,
            clearToolActivity: true,
            clearCurrentToolCalls: true,
            clearApproval: true,
            activeProviderId: _localAiProviderId,
          ));
          return;
        }

        final calls = ToolExecutor.parseToolCalls(responseText)
            .map(_toolExecutor.normalizeCall)
            .toList(growable: false);
        if (calls.isEmpty) {
          final displayContent =
              _stripJsonBlocks(_stripToolCallTags(responseText));
          emit(state.copyWith(
            messages: [
              ...uiMessages,
              AiMessage(
                id: streamingId,
                role: AiMessageRole.assistant,
                content: displayContent,
                timestamp: streamingMsg.timestamp,
                toolCalls:
                    allToolCalls.isNotEmpty ? List.of(allToolCalls) : null,
              ),
            ],
            isLoading: false,
            clearThinking: true,
            toolActivity: List.of(activity),
            activeProviderId: _localAiProviderId,
          ));
          return;
        }

        // Detect a stuck loop: if this exact set of tool calls was already
        // executed in a previous round, the model is not making progress.
        // Break out and force a final answer instead of repeating up to the
        // maxToolCalls limit (which floods the UI with duplicate tool cards).
        final roundSignature =
            calls.map((c) => '${c.name}(${jsonEncode(c.arguments)})').join('|');
        if (!seenToolSignatures.add(roundSignature)) {
          activity
              .add('> Repeated tool call detected; requesting final answer');
          emit(state.copyWith(toolActivity: List.of(activity)));
          apiMessages.add(AiMessage(
            id: _uuid.v4(),
            role: AiMessageRole.user,
            content: 'You already called these tools and received the results '
                'above. Do not call any tools again. Give your final answer now '
                'using the information you already have.',
            timestamp: DateTime.now(),
          ));
          break;
        }

        final explanationText = _stripToolCallTags(responseText).trim();
        final List<AiMessage> updatedUiMessages;
        if (explanationText.isNotEmpty) {
          final explanationMsg = AiMessage(
            id: streamingId,
            role: AiMessageRole.assistant,
            content: explanationText,
            timestamp: streamingMsg.timestamp,
          );
          apiMessages.add(explanationMsg);
          updatedUiMessages = [...uiMessages, explanationMsg];
        } else {
          updatedUiMessages = uiMessages;
        }

        final dangerousCalls = calls
            .where((c) => ToolExecutor.dangerousTools.contains(c.name))
            .toList();

        if (dangerousCalls.isNotEmpty) {
          activity.add('> Waiting for your approval...');
          emit(state.copyWith(
            messages: updatedUiMessages,
            thinkingText: state.waitingApproval,
            toolActivity: List.of(activity),
          ));

          final combinedRequest = _buildCombinedApprovalRequest(dangerousCalls);
          activity
              .add('> Approval required: ${dangerousCalls.length} action(s)');
          emit(state.copyWith(toolActivity: List.of(activity)));

          final approved = await _requestApproval(emit, combinedRequest);
          _ensureGenerationActive(generationId);
          if (!approved) {
            activity.add('  Rejected: User rejected all actions');
            emit(state.copyWith(
              toolActivity: List.of(activity),
              clearThinking: true,
            ));

            final rejectBuffer = StringBuffer();
            for (final call in dangerousCalls) {
              rejectBuffer.writeln(
                '<tool_result name="${call.name}">\nBlocked: User rejected.\n</tool_result>',
              );
            }
            rejectBuffer
                .writeln('STOP: User rejected all actions. Do not proceed.');
            apiMessages.add(AiMessage(
              id: _uuid.v4(),
              role: AiMessageRole.user,
              content: rejectBuffer.toString(),
              timestamp: DateTime.now(),
            ));
            continue;
          }

          activity.add('  Approved: All actions approved');
          emit(state.copyWith(
            toolActivity: List.of(activity),
            thinkingText: state.runningToolTemplate
                .replaceFirst('{}', dangerousCalls.first.name),
          ));
        }

        final toolResultBuffer = StringBuffer();
        for (final call in calls) {
          if (ToolExecutor.dangerousTools.contains(call.name)) {
            activity.add('  Approved: ${call.name} (pre-approved)');
            _addRunningToolCall(allToolCalls, call);
            emit(state.copyWith(
              messages: updatedUiMessages,
              thinkingText:
                  state.runningToolTemplate.replaceFirst('{}', call.name),
              toolActivity: List.of(activity),
              currentToolCalls: List.of(allToolCalls),
            ));
          } else {
            activity
                .add('> Tool: ${call.name}(${_summarizeArgs(call.arguments)})');
            emit(state.copyWith(
              messages: updatedUiMessages,
              thinkingText:
                  state.runningToolTemplate.replaceFirst('{}', call.name),
              toolActivity: List.of(activity),
              currentToolCalls: List.of(allToolCalls)
                ..add(_runningToolCall(call)),
            ));
          }

          final toolResult = await _toolExecutor.execute(call);
          _ensureGenerationActive(generationId);

          if (ToolExecutor.dangerousTools.contains(call.name)) {
            _completeRunningToolCall(
              allToolCalls,
              call,
              output: toolResult.output,
              success: toolResult.success,
            );
          } else {
            allToolCalls.add(AiToolCall(
              toolName: call.name,
              arguments: jsonEncode(call.arguments),
              result: toolResult.output,
              success: toolResult.success,
            ));
          }

          activity.add(
              '  ${toolResult.success ? "OK" : "FAIL"}: ${_truncateOutput(toolResult.output)}');
          emit(state.copyWith(
            toolActivity: List.of(activity),
            currentToolCalls: List.of(allToolCalls),
          ));

          toolResultBuffer.writeln(
            '<tool_result name="${call.name}">\n${toolResult.output}\n</tool_result>',
          );
        }

        apiMessages.add(AiMessage(
          id: _uuid.v4(),
          role: AiMessageRole.user,
          content: toolResultBuffer.toString(),
          timestamp: DateTime.now(),
        ));

        uiMessages = updatedUiMessages;
      }

      activity.add('> Max tool calls reached, requesting final answer...');
      emit(state.copyWith(toolActivity: List.of(activity)));

      apiMessages.add(AiMessage(
        id: _uuid.v4(),
        role: AiMessageRole.user,
        content:
            'Please give your final answer now. Do not call any more tools.',
        timestamp: DateTime.now(),
      ));

      final preparedContext = _prepareContextForProvider(
        apiMessages,
        systemPrompt: systemPrompt,
        activity: activity,
        aggressive: true,
      );
      final localPrompt = _buildLocalTranscript(preparedContext.messages);
      final streamingId = _uuid.v4();
      final streamingMsg = AiMessage(
        id: streamingId,
        role: AiMessageRole.assistant,
        content: '',
        timestamp: DateTime.now(),
        toolCalls: allToolCalls.isNotEmpty ? List.of(allToolCalls) : null,
        isLoading: true,
      );
      emit(state.copyWith(
        messages: [...uiMessages, streamingMsg],
        clearThinking: true,
        activeProviderId: _localAiProviderId,
      ));

      final rawBuffer = StringBuffer();
      await _consumeGenerationStream(
        generationId: generationId,
        stream: localService.sendChatMessageStream(
          message: localPrompt,
          systemPrompt: preparedContext.systemPrompt,
        ),
        onChunk: (chunk) {
          rawBuffer.write(chunk);
          final displayText = _stripJsonBlocks(
            _stripToolCallTagsStreaming(rawBuffer.toString()),
          );
          emit(state.copyWith(
            messages: [
              ...uiMessages,
              streamingMsg.copyWith(
                content: displayText,
                isLoading: true,
              ),
            ],
            activeProviderId: _localAiProviderId,
          ));
        },
      );

      final assistantMessage = AiMessage(
        id: streamingId,
        role: AiMessageRole.assistant,
        content:
            _stripJsonBlocks(_stripToolCallTags(rawBuffer.toString())).isEmpty
                ? '(The local model returned an empty response.)'
                : _stripJsonBlocks(_stripToolCallTags(rawBuffer.toString())),
        timestamp: streamingMsg.timestamp,
        toolCalls: allToolCalls.isNotEmpty ? List.of(allToolCalls) : null,
        isLoading: false,
      );

      emit(state.copyWith(
        messages: [...uiMessages, assistantMessage],
        isLoading: false,
        clearThinking: true,
        clearToolActivity: true,
        clearCurrentToolCalls: true,
        clearApproval: true,
        activeProviderId: _localAiProviderId,
      ));
    } on _GenerationStopped {
      return;
    } catch (e) {
      if (_activeGenerationId != generationId) return;
      AppLogger.error('[AiAgentBloc] Local AI inference failed', error: e);
      emit(state.copyWith(
        messages: displayMessages,
        error: 'Local AI inference failed: $e',
        isLoading: false,
        clearThinking: true,
        clearToolActivity: true,
        activeProviderId: _localAiProviderId,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Streaming final answer
  // ---------------------------------------------------------------------------

  /// Streams the final assistant response chunk-by-chunk into the UI.
  ///
  /// Uses [chatStream] so each SSE token is shown as it arrives.
  /// The in-flight message is held as the last entry in `messages`, with its
  /// `content` updated on every chunk via [copyWith]. Once the stream ends,
  /// search results are parsed and the message is finalised.
  Future<void> _streamFinalAnswer(
    Emitter<AiAgentState> emit, {
    required List<AiMessage> apiMessages,
    required List<AiMessage> uiMessages,
    required List<AiToolCall> allToolCalls,
    required List<String> activity,
    required String systemPrompt,
    required String? providerId,
    required int generationId,
  }) async {
    // Reserve a stable ID for the streaming message so UI can key on it.
    final streamingId = _uuid.v4();
    final streamingMsg = AiMessage(
      id: streamingId,
      role: AiMessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      toolCalls: allToolCalls.isNotEmpty ? List.of(allToolCalls) : null,
      isLoading: true,
    );

    // Show the empty streaming bubble immediately (clears thinking indicator).
    emit(state.copyWith(
      messages: [...uiMessages, streamingMsg],
      clearThinking: true,
      toolActivity: List.of(activity),
    ));

    final rawBuffer = StringBuffer();
    String resolvedProviderId = providerId ?? '';

    try {
      final preparedContext = _prepareContextForProvider(
        apiMessages,
        systemPrompt: systemPrompt,
        activity: activity,
        aggressive: true,
      );
      final streamResult = await _providerService.chatStream(
        preparedContext.messages,
        systemPrompt: preparedContext.systemPrompt,
        preferredProviderId: state.selectedProviderId,
        preferredModelName: state.selectedModelName,
      );
      _ensureGenerationActive(generationId);
      resolvedProviderId = streamResult.providerId;

      await _consumeGenerationStream(
        generationId: generationId,
        stream: streamResult.stream,
        onChunk: (chunk) {
          rawBuffer.write(chunk);

          // Strip tool-call artifacts before displaying; never show raw tags to user.
          final displayText = _stripJsonBlocks(
            _stripToolCallTagsStreaming(rawBuffer.toString()),
          );

          // Update the streaming message content in-place
          final updatedMsg = streamingMsg.copyWith(
            content: displayText,
            isLoading: true,
          );
          emit(state.copyWith(
            messages: [...uiMessages, updatedMsg],
          ));
        },
      );
    } on AiProviderException {
      _ensureGenerationActive(generationId);
      // If streaming fails, fall back to non-streaming
      AppLogger.warning('[AiAgentBloc] Stream failed, falling back to chat()');
      final preparedContext = _prepareContextForProvider(
        apiMessages,
        systemPrompt: systemPrompt,
        activity: activity,
        aggressive: true,
      );
      final fallback = await _providerService.chat(
        preparedContext.messages,
        systemPrompt: preparedContext.systemPrompt,
        preferredProviderId: state.selectedProviderId,
        preferredModelName: state.selectedModelName,
      );
      _ensureGenerationActive(generationId);
      rawBuffer
        ..clear()
        ..write(fallback.response.content);
      resolvedProviderId = fallback.providerId;
    }
    _ensureGenerationActive(generationId);

    // Finalise: strip tool call artifacts, parse search results
    final rawContent = rawBuffer.toString();
    final displayContent = _stripJsonBlocks(_stripToolCallTags(rawContent));
    final searchResults = _parseSearchResults(rawContent);

    if (searchResults.isNotEmpty) {
      activity.add('> Found ${searchResults.length} file(s)');
    }

    final finalMsg = AiMessage(
      id: streamingId,
      role: AiMessageRole.assistant,
      content: displayContent,
      timestamp: streamingMsg.timestamp,
      searchResults: searchResults.isNotEmpty ? searchResults : null,
      toolCalls: allToolCalls.isNotEmpty ? List.of(allToolCalls) : null,
      isLoading: false,
    );

    emit(state.copyWith(
      messages: [...uiMessages, finalMsg],
      isLoading: false,
      results: searchResults,
      activeProviderId:
          resolvedProviderId.isNotEmpty ? resolvedProviderId : null,
      clearThinking: true,
      clearCurrentToolCalls: true,
      toolActivity: List.of(activity),
    ));
  }

  // ---------------------------------------------------------------------------
  // Approval helpers
  // ---------------------------------------------------------------------------

  /// Builds a single combined approval request from multiple dangerous tool calls.
  AiApprovalRequest _buildCombinedApprovalRequest(List<ToolCall> calls) {
    final buffer = StringBuffer();

    for (final call in calls) {
      if (call.name == 'run_command') {
        final cmd = call.arguments['command'] as String? ?? '(unknown)';
        buffer.writeln('RUN COMMAND: `$cmd`');
      } else if (call.name == 'write_file') {
        final path = call.arguments['path'] as String? ?? '(unknown)';
        final fileName = path.split(Platform.pathSeparator).last;
        final exists = File(path).existsSync();
        if (exists) {
          buffer.writeln('MODIFY FILE: $fileName\n$path');
        } else {
          buffer.writeln('CREATE FILE: $fileName\n$path');
        }
      } else if (call.name == 'delete_file') {
        // Support single path or array
        final pathArg = call.arguments['path'] as String?;
        final pathsArg = call.arguments['paths'] as List?;
        final filePaths = pathsArg?.map((e) => e.toString()).toList() ??
            (pathArg != null ? [pathArg] : ['(unknown)']);
        for (final p in filePaths) {
          final fn = p.split(Platform.pathSeparator).last;
          buffer.writeln('MOVE TO RECYCLE BIN: $fn\n$p');
        }
      } else if (call.name == 'clean_disk_junk') {
        final scanId = call.arguments['scan_id'] as String? ?? '?';
        final permanent = call.arguments['permanent'] as bool? ?? false;
        final cats = call.arguments['categories'] as List?;
        final catsStr = cats != null ? cats.join(', ') : 'all scanned';
        buffer
            .writeln('CLEAN DISK JUNK: scan_id=$scanId, categories=[$catsStr]');
        buffer.writeln(
            permanent ? 'Mode: PERMANENT DELETE' : 'Mode: Move to Recycle Bin');
      }
    }

    // Derive per-call metadata once (reused for title, label, actionType)
    final bool singleCall = calls.length == 1;
    final bool firstFileExists = singleCall && calls.first.name == 'write_file'
        ? File(calls.first.arguments['path'] as String? ?? '').existsSync()
        : false;

    final String title;
    if (singleCall) {
      final name = calls.first.name;
      if (name == 'write_file') {
        title = firstFileExists
            ? 'Agent wants to modify a file'
            : 'Agent wants to create a file';
      } else if (name == 'run_command') {
        title = 'Agent wants to execute a command';
      } else if (name == 'delete_file') {
        title = 'Agent wants to move to recycle bin';
      } else if (name == 'clean_disk_junk') {
        title = 'Agent wants to clean disk junk';
      } else {
        title = 'Agent wants to perform an action';
      }
    } else {
      title = 'Agent wants to perform ${calls.length} actions';
    }

    final allDangerous = calls.every((c) =>
        c.name == 'run_command' ||
        c.name == 'delete_file' ||
        c.name == 'clean_disk_junk');

    final String confirmLabel;
    if (singleCall) {
      switch (calls.first.name) {
        case 'run_command':
          confirmLabel = 'Run';
          break;
        case 'write_file':
          confirmLabel = firstFileExists ? 'Modify' : 'Create';
          break;
        case 'delete_file':
          confirmLabel = 'Delete';
          break;
        case 'clean_disk_junk':
          confirmLabel = 'Clean';
          break;
        default:
          confirmLabel = 'Confirm';
      }
    } else {
      confirmLabel = 'Approve All';
    }

    return AiApprovalRequest(
      id: _uuid.v4(),
      title: title,
      description: buffer.toString().trim(),
      confirmLabel: confirmLabel,
      isDangerous: allDangerous,
      actionType: singleCall
          ? _actionTypeForTool(calls.first.name, fileExists: firstFileExists)
          : ApprovalActionType.generic,
    );
  }

  ApprovalActionType _actionTypeForTool(String toolName,
      {bool fileExists = false}) {
    switch (toolName) {
      case 'run_command':
        return ApprovalActionType.execute;
      case 'write_file':
        return fileExists
            ? ApprovalActionType.modifyFile
            : ApprovalActionType.createFile;
      case 'delete_file':
        return ApprovalActionType.deleteFile;
      case 'clean_disk_junk':
        return ApprovalActionType.cleanJunk;
      default:
        return ApprovalActionType.generic;
    }
  }

  // Note: rejection continuation is handled by 'continue' statement
  // which lets the loop proceed to final answer after max rounds

  /// Truncates a string to [max] chars for activity-log display.
  static String _truncateOutput(String s, [int max = 120]) =>
      s.length > max ? '${s.substring(0, max)}...' : s;

  /// Summarizes tool arguments for the activity log.
  String _summarizeArgs(Map<String, dynamic> args) {
    final parts = <String>[];
    for (final entry in args.entries) {
      final val = entry.value.toString();
      parts.add(
          '${entry.key}: ${val.length > 40 ? '${val.substring(0, 40)}...' : val}');
    }
    return parts.join(', ');
  }

  /// Known tool names - must match [ToolExecutor._knownTools].
  static const _toolNames =
      'list_directory|search_files|read_file|write_file|delete_file|'
      'get_file_info|run_command|search_by_tag|get_file_tags|'
      'list_all_tags|search_content|list_video_libraries|'
      'get_video_library_files|list_albums|get_album_files|'
      'list_disk_junk_categories|get_drive_space|scan_disk_junk|clean_disk_junk|'
      'get_pending_cleanup_review|get_current_cleaner_scan|get_current_clean_cleaner_scan|'
      'get_current_app_storage';

  /// Strips **complete** tool call blocks from text.
  /// Used for finished (non-streaming) responses.
  static String _stripToolCallTags(String text) {
    var cleaned = text;

    // Tool result blocks fed back as conversation context. The model sometimes
    // echoes these back verbatim; they must never appear in the chat bubble.
    cleaned = cleaned.replaceAll(
      RegExp(r'<tool_result\b[^>]*>[\s\S]*?</tool_result>'),
      '',
    );

    // Format 1: <tool_call>...</tool_call>
    cleaned =
        cleaned.replaceAll(RegExp(r'<tool_call>[\s\S]*?</tool_call>'), '');

    // Format 1a: Gemma/LiteRT sometimes emits sentinel tokens instead of XML.
    cleaned = cleaned.replaceAll(
      RegExp(r'<\|tool_call>[\s\S]*?<tool_call\|>'),
      '',
    );

    // Format 1b: bare Gemma call.
    cleaned = cleaned.replaceAll(
      RegExp(r'call:tool_call\s*\{[\s\S]*?\}'),
      '',
    );

    // Format 2: ```json {"name":"known_tool",...} ```
    cleaned = cleaned.replaceAll(
      RegExp(
          '```(?:json)?\\s*\\n?\\{\\s*"name"\\s*:\\s*"(?:$_toolNames)"[\\s\\S]*?\\}\\s*\\n?```'),
      '',
    );

    // Format 3: bare JSON object with known tool name - brace-balanced
    cleaned = _stripBareToolJson(cleaned);

    // Incomplete/unclosed fragments. The model can stop mid-tool-call (e.g.
    // "<tool_call> {\"name\": \"list_directory\", \"arguments\": {\"path\": \"C")
    // with no closing tag. Complete blocks are already removed above, so any
    // remaining unclosed opener means everything after it is a broken tool
    // call and must never reach the chat bubble. This runs for finalized
    // messages too, not just streaming.
    cleaned = _stripIncompleteToolFragments(cleaned);

    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return cleaned.trim();
  }

  /// Removes trailing tool-call/tool-result fragments that were never closed.
  /// Called after all complete blocks have been stripped.
  static String _stripIncompleteToolFragments(String text) {
    var cleaned = text;

    // <tool_result ...>... (no closing tag yet)
    cleaned = cleaned.replaceAll(RegExp(r'<tool_result\b[\s\S]*$'), '');

    // <tool_call>... (no closing tag yet)
    cleaned = cleaned.replaceAll(RegExp(r'<tool_call>[\s\S]*$'), '');

    // <|tool_call>... (no closing sentinel yet)
    cleaned = cleaned.replaceAll(RegExp(r'<\|tool_call>[\s\S]*$'), '');

    // bare Gemma call fragment.
    cleaned = cleaned.replaceAll(RegExp(r'call:tool_call\s*\{[\s\S]*$'), '');

    // ```json {"name":"tool" ... (no closing ```)
    cleaned = cleaned.replaceAll(
      RegExp(
          '```(?:json)?\\s*\\n?\\{\\s*"name"\\s*:\\s*"(?:$_toolNames)"[\\s\\S]*\$'),
      '',
    );

    // bare JSON incomplete {"name":"tool"... (no closing })
    cleaned = cleaned.replaceAll(
      RegExp('\\{\\s*"name"\\s*:\\s*"(?:$_toolNames)"[\\s\\S]*\$'),
      '',
    );

    return cleaned;
  }

  /// Strips tool call blocks from **in-flight streaming** text.
  /// Also strips incomplete/partial tool call fragments that haven't closed yet.
  static String _stripToolCallTagsStreaming(String text) {
    // _stripToolCallTags already removes complete blocks and unclosed
    // fragments. Streaming only needs the extra trailing-prefix guard below.
    var cleaned = _stripToolCallTags(text);

    // Trailing partial tag prefix. While streaming token by token, the opening
    // tag arrives in pieces (e.g. "<", "<tool", "<tool_ca") before it fully
    // forms. Hide any trailing fragment that is a prefix of a known tool
    // opening tag so no partial markup ever flashes in the bubble.
    cleaned = _stripTrailingPartialToolTag(cleaned);

    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return cleaned.trim();
  }

  /// Opening tags that must never appear (even partially) in the chat bubble.
  static const List<String> _toolTagPrefixes = <String>[
    '<tool_call>',
    '<tool_result',
    '<|tool_call>',
  ];

  /// If [text] ends with a fragment that is a non-empty prefix of any known
  /// tool opening tag, strips that trailing fragment. This prevents partial
  /// markup like "<tool_ca" from flashing while the stream is mid-tag.
  static String _stripTrailingPartialToolTag(String text) {
    final lastLt = text.lastIndexOf('<');
    if (lastLt < 0) return text;
    final tail = text.substring(lastLt);
    // Already-complete tags are handled by earlier passes; only cut when the
    // tail is a strict, still-incomplete prefix of a known opening tag.
    for (final tag in _toolTagPrefixes) {
      if (tag.startsWith(tail) && tail.length < tag.length) {
        return text.substring(0, lastLt);
      }
    }
    return text;
  }

  /// Strips bare JSON tool calls with proper brace-balancing (handles nested
  /// arrays/objects inside arguments).
  static String _stripBareToolJson(String text) {
    final pattern = RegExp('\\{\\s*"name"\\s*:\\s*"(?:$_toolNames)"');
    var result = text;
    // Work backwards so indices stay valid
    final matches = pattern.allMatches(result).toList().reversed;
    for (final match in matches) {
      final start = match.start;
      // Walk forward counting braces to find the balanced closing }
      int depth = 0;
      int? end;
      for (int i = start; i < result.length; i++) {
        final ch = result[i];
        if (ch == '{') depth++;
        if (ch == '}') {
          depth--;
          if (depth == 0) {
            end = i + 1;
            break;
          }
        }
      }
      if (end != null) {
        result = result.substring(0, start) + result.substring(end);
      }
    }
    return result;
  }

  void _onClearChat(
    ClearChat event,
    Emitter<AiAgentState> emit,
  ) {
    // "Clear chat" starts a fresh conversation (same as NewConversation).
    add(const NewConversation());
  }

  void _onEditMessage(
    EditMessage event,
    Emitter<AiAgentState> emit,
  ) {
    if (state.isLoading) return;

    final trimmed = event.content.trim();
    if (trimmed.isEmpty) return;

    final index = state.messages.indexWhere(
      (m) => m.id == event.messageId && m.role == AiMessageRole.user,
    );
    if (index < 0) return;

    final original = state.messages[index];
    final referencedFiles =
        original.referencedFiles?.map((f) => f.path).toList() ?? const [];

    emit(state.copyWith(
      messages: state.messages.take(index).toList(),
      results: const [],
      clearError: true,
      clearThinking: true,
      clearToolActivity: true,
      clearApproval: true,
    ));

    add(SendMessage(trimmed, referencedFiles: referencedFiles));
  }

  void _onChangeSearchScope(
    ChangeSearchScope event,
    Emitter<AiAgentState> emit,
  ) {
    emit(state.copyWith(searchScope: event.scope));
  }

  Future<void> _onQuickSearch(
    QuickSearch event,
    Emitter<AiAgentState> emit,
  ) async {
    if (event.query.trim().isEmpty) return;
    // Delegate to SendMessage which handles tool calling
    add(SendMessage('Find files matching: ${event.query}'));
  }

  void _onUpdateCurrentPath(
    UpdateCurrentPath event,
    Emitter<AiAgentState> emit,
  ) async {
    final normalizedPath =
        AiChatHistoryService.normalizeWorkspacePath(event.path);
    final previousPath =
        AiChatHistoryService.normalizeWorkspacePath(state.currentPath);

    if (normalizedPath == previousPath) {
      if (state.currentPath != event.path) {
        emit(state.copyWith(currentPath: event.path));
      }
      return;
    }

    if (normalizedPath.isEmpty) {
      emit(state.copyWith(currentPath: event.path));
      return;
    }

    final matchingSummary =
        await _historyService?.findLatestSummaryForPath(normalizedPath);
    final summaries = await _historyService?.loadAllSummaries() ?? [];

    if (matchingSummary != null) {
      if (matchingSummary.id == state.conversationId) {
        emit(state.copyWith(
          currentPath: event.path,
          conversations: summaries,
        ));
        return;
      }

      final messages =
          await _historyService?.loadConversation(matchingSummary.id) ?? [];
      emit(state.copyWith(
        currentPath: event.path,
        conversationId: matchingSummary.id,
        messages: messages,
        results: const [],
        clearError: true,
        clearThinking: true,
        clearToolActivity: true,
        clearApproval: true,
        conversations: summaries,
      ));
      return;
    }

    emit(state.copyWith(
      currentPath: event.path,
      conversationId: _uuid.v4(),
      messages: const [],
      results: const [],
      clearError: true,
      clearThinking: true,
      clearToolActivity: true,
      clearApproval: true,
      conversations: summaries,
    ));
  }

  Future<void> _onRetryLastMessage(
    RetryLastMessage event,
    Emitter<AiAgentState> emit,
  ) async {
    // Find the last user message
    final lastUserMessage = state.messages.lastWhere(
      (m) => m.role == AiMessageRole.user,
      orElse: () => AiMessage(
        id: '',
        role: AiMessageRole.user,
        content: '',
        timestamp: DateTime.now(),
      ),
    );
    if (lastUserMessage.content.isEmpty) return;

    // Remove the last assistant message (error response) if present
    final messages = [...state.messages];
    if (messages.isNotEmpty && messages.last.role == AiMessageRole.assistant) {
      messages.removeLast();
    }

    emit(state.copyWith(messages: messages, clearError: true));
    add(SendMessage(
      lastUserMessage.content,
      referencedFiles:
          lastUserMessage.referencedFiles?.map((f) => f.path).toList() ?? [],
    ));
  }

  Future<void> _onProviderChanged(
    ProviderChanged event,
    Emitter<AiAgentState> emit,
  ) async {
    final hasProvider = await _providerService.hasConfiguredProvider;
    final localCatalogs = _mergeLocalAiCatalog(const []);
    emit(state.copyWith(
      isProviderConfigured: hasProvider || localCatalogs.isNotEmpty,
      isLoadingProviderModels: hasProvider,
    ));
    add(const RefreshProviderModels());
  }

  Future<void> _onRefreshProviderModels(
    RefreshProviderModels event,
    Emitter<AiAgentState> emit,
  ) async {
    final hasProvider = await _providerService.hasConfiguredProvider;
    if (!hasProvider) {
      final localCatalogs = _mergeLocalAiCatalog(const []);
      if (localCatalogs.isEmpty) {
        emit(state.copyWith(
          isProviderConfigured: false,
          providerModelCatalogs: const [],
          clearSelectedProvider: true,
          clearSelectedModel: true,
          isLoadingProviderModels: false,
        ));
        return;
      }
      // Show local AI catalog even when no remote providers configured
      final selection = _resolveModelSelection(
        catalogs: localCatalogs,
        selectedProviderId: state.selectedProviderId,
        selectedModelName: state.selectedModelName,
      );
      emit(state.copyWith(
        isProviderConfigured: true,
        providerModelCatalogs: localCatalogs,
        selectedProviderId: selection.providerId,
        selectedModelName: selection.modelName,
        isLoadingProviderModels: false,
      ));
      return;
    }

    emit(state.copyWith(isLoadingProviderModels: true));
    final remoteCatalogs =
        await _providerService.getEnabledProviderModelCatalogs();
    final catalogs = _mergeLocalAiCatalog(remoteCatalogs);
    final selection = _resolveModelSelection(
      catalogs: catalogs,
      selectedProviderId: state.selectedProviderId,
      selectedModelName: state.selectedModelName,
    );

    emit(state.copyWith(
      isProviderConfigured: true,
      providerModelCatalogs: catalogs,
      selectedProviderId: selection.providerId,
      selectedModelName: selection.modelName,
      isLoadingProviderModels: false,
    ));
  }

  Future<void> _onSelectChatModel(
    SelectChatModel event,
    Emitter<AiAgentState> emit,
  ) async {
    final provider = state.providerModelCatalogs.firstWhere(
      (catalog) => catalog.providerId == event.providerId,
      orElse: () => const AiProviderModelCatalog(
        providerId: '',
        providerName: '',
        apiType: AiApiType.openaiCompatible,
        authMode: AiProviderAuthMode.apiKey,
        defaultModelName: '',
        models: [],
      ),
    );
    if (provider.providerId.isEmpty) return;
    if (!provider.models.contains(event.modelName)) return;

    if (event.providerId == _localAiProviderId) {
      final svc = _localAiService;
      if (svc != null) {
        for (final model in svc.getInstalledModels()) {
          if (model.displayName == event.modelName) {
            await svc.setSelectedModel(model.catalogId);
            break;
          }
        }
      }
    }

    await _persistModelSelection(event.providerId, event.modelName);

    emit(state.copyWith(
      selectedProviderId: event.providerId,
      selectedModelName: event.modelName,
    ));
  }

  void _onApprove(ApproveAction event, Emitter<AiAgentState> emit) {
    if (state.pendingApproval?.id == event.approvalId) {
      emit(state.copyWith(clearApproval: true));
      _approvalCompleter?.complete(true);
      _approvalCompleter = null;
    }
  }

  void _onReject(RejectAction event, Emitter<AiAgentState> emit) {
    if (state.pendingApproval?.id == event.approvalId) {
      emit(state.copyWith(clearApproval: true));
      _approvalCompleter?.complete(false);
      _approvalCompleter = null;
    }
  }

  void _onStopGeneration(
    StopGeneration event,
    Emitter<AiAgentState> emit,
  ) {
    if (!state.isLoading) return;

    _activeGenerationId = null;

    final stoppedToolCalls = state.currentToolCalls
        .map(
          (call) => call.isRunning
              ? AiToolCall(
                  toolName: call.toolName,
                  arguments: call.arguments,
                  result: 'Stopped by user.',
                  success: false,
                )
              : call,
        )
        .toList(growable: false);
    final messages = _finalizeStoppedMessages(
      state.messages,
      stoppedToolCalls,
    );

    final approval = _approvalCompleter;
    _approvalCompleter = null;
    if (approval != null && !approval.isCompleted) {
      approval.complete(false);
    }

    final streamCompleter = _activeStreamCompleter;
    if (streamCompleter != null && !streamCompleter.isCompleted) {
      streamCompleter.completeError(const _GenerationStopped());
    }
    unawaited(_activeStreamSubscription?.cancel());

    emit(state.copyWith(
      messages: messages,
      isLoading: false,
      clearThinking: true,
      clearApproval: true,
      clearCurrentToolCalls: true,
    ));
  }

  Future<void> _onNewConversation(
    NewConversation event,
    Emitter<AiAgentState> emit,
  ) async {
    final newId = _uuid.v4();
    final summaries = await _historyService?.loadAllSummaries() ?? [];
    emit(state.copyWith(
      conversationId: newId,
      messages: [],
      results: [],
      clearError: true,
      clearThinking: true,
      clearToolActivity: true,
      conversations: summaries,
    ));
  }

  Future<void> _onSwitchConversation(
    SwitchConversation event,
    Emitter<AiAgentState> emit,
  ) async {
    if (event.id == state.conversationId) return;
    final messages = await _historyService?.loadConversation(event.id) ?? [];
    final summaries = await _historyService?.loadAllSummaries() ?? [];
    // Restore the workspace path from the conversation summary so the
    // chat context matches the conversation the user is switching to.
    AiConversationSummary? summary;
    for (final s in summaries) {
      if (s.id == event.id) {
        summary = s;
        break;
      }
    }
    final restoredPath = summary?.initialPath ?? '';
    emit(state.copyWith(
      conversationId: event.id,
      messages: messages,
      results: [],
      clearError: true,
      clearThinking: true,
      clearToolActivity: true,
      clearApproval: true,
      conversations: summaries,
      currentPath: restoredPath,
    ));
  }

  Future<void> _onDeleteConversation(
    DeleteConversation event,
    Emitter<AiAgentState> emit,
  ) async {
    await _historyService?.deleteConversation(event.id);
    final summaries = await _historyService?.loadAllSummaries() ?? [];

    if (event.id == state.conversationId) {
      // Switch to the next most-recent conversation or start fresh
      if (summaries.isNotEmpty) {
        final nextId = summaries.first.id;
        final messages = await _historyService?.loadConversation(nextId) ?? [];
        emit(state.copyWith(
          conversationId: nextId,
          messages: messages,
          results: [],
          clearError: true,
          conversations: summaries,
        ));
      } else {
        emit(state.copyWith(
          conversationId: _uuid.v4(),
          messages: [],
          results: [],
          clearError: true,
          conversations: const [],
        ));
      }
    } else {
      emit(state.copyWith(conversations: summaries));
    }
  }

  Future<void> _onRefreshConversations(
    RefreshConversations event,
    Emitter<AiAgentState> emit,
  ) async {
    final summaries = await _historyService?.loadAllSummaries() ?? [];
    emit(state.copyWith(conversations: summaries));
  }

  /// Pauses execution and waits for user to approve or reject.
  /// Returns true if approved, false if rejected.
  Future<bool> _requestApproval(
    Emitter<AiAgentState> emit,
    AiApprovalRequest request,
  ) async {
    _approvalCompleter = Completer<bool>();
    emit(state.copyWith(pendingApproval: request));
    final approved = await _approvalCompleter!.future;
    return approved;
  }

  void _ensureGenerationActive(int generationId) {
    if (_activeGenerationId != generationId) {
      throw const _GenerationStopped();
    }
  }

  Future<void> _consumeGenerationStream({
    required int generationId,
    required Stream<String> stream,
    required void Function(String chunk) onChunk,
  }) async {
    _ensureGenerationActive(generationId);
    final completer = Completer<void>();
    late final StreamSubscription<String> subscription;

    subscription = stream.listen(
      (chunk) {
        if (_activeGenerationId != generationId || completer.isCompleted) {
          return;
        }
        try {
          onChunk(chunk);
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    _activeStreamSubscription = subscription;
    _activeStreamCompleter = completer;
    try {
      await completer.future;
      _ensureGenerationActive(generationId);
    } finally {
      if (identical(_activeStreamSubscription, subscription)) {
        _activeStreamSubscription = null;
      }
      if (identical(_activeStreamCompleter, completer)) {
        _activeStreamCompleter = null;
      }
      await subscription.cancel();
    }
  }

  AiToolCall _runningToolCall(ToolCall call) => AiToolCall(
        toolName: call.name,
        arguments: jsonEncode(call.arguments),
        isRunning: true,
      );

  void _addRunningToolCall(List<AiToolCall> calls, ToolCall call) {
    calls.add(_runningToolCall(call));
  }

  void _completeRunningToolCall(
    List<AiToolCall> calls,
    ToolCall call, {
    required String output,
    required bool success,
  }) {
    final index = calls.lastIndexWhere(
      (item) => item.isRunning && item.toolName == call.name,
    );
    final completed = AiToolCall(
      toolName: call.name,
      arguments: jsonEncode(call.arguments),
      result: output,
      success: success,
    );
    if (index < 0) {
      calls.add(completed);
    } else {
      calls[index] = completed;
    }
  }

  List<AiMessage> _finalizeStoppedMessages(
    List<AiMessage> messages,
    List<AiToolCall> toolCalls,
  ) {
    final updated = List<AiMessage>.of(messages);
    if (updated.isNotEmpty && updated.last.isLoading) {
      final partial = updated.removeLast();
      if (partial.content.trim().isNotEmpty) {
        updated.add(partial.copyWith(
          isLoading: false,
          toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
        ));
      }
    } else if (toolCalls.isNotEmpty) {
      updated.add(AiMessage(
        id: _uuid.v4(),
        role: AiMessageRole.assistant,
        content: 'Stopped by user.',
        timestamp: DateTime.now(),
        toolCalls: toolCalls,
      ));
    }
    return updated;
  }

  // ---------------------------------------------------------------------------
  // File reference handling
  // ---------------------------------------------------------------------------

  /// Builds ReferencedFile objects from dropped file paths, auto-reading text
  /// file content so it's immediately available for display and the LLM.
  Future<List<ReferencedFile>> _buildReferencedFiles(List<String> paths) async {
    final results = <ReferencedFile>[];

    for (final path in paths) {
      final file = File(path);
      final fileName =
          path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).last;
      final ext =
          fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

      if (!await file.exists()) {
        results.add(ReferencedFile(
          path: path,
          fileName: fileName,
          isTextFile: ReferencedFile.isTextExtension(ext),
          error: 'File not found',
        ));
        continue;
      }

      final isText = ReferencedFile.isTextExtension(ext);
      if (!isText) {
        results.add(ReferencedFile(
          path: path,
          fileName: fileName,
          isTextFile: false,
        ));
        continue;
      }

      // Auto-read text file content
      try {
        final stat = await file.stat();
        if (stat.size > 1024 * 1024) {
          results.add(ReferencedFile(
            path: path,
            fileName: fileName,
            isTextFile: true,
            contentLoaded: false,
            error: 'File too large (>1MB)',
          ));
          continue;
        }

        String content;
        try {
          content = await file.readAsString(encoding: utf8);
        } catch (_) {
          try {
            content = await file.readAsString(encoding: latin1);
          } catch (__) {
            results.add(ReferencedFile(
              path: path,
              fileName: fileName,
              isTextFile: true,
              contentLoaded: false,
              error: 'Cannot read (binary or unsupported encoding)',
            ));
            continue;
          }
        }

        // Truncate to 200 lines for display
        final lines = content.split('\n');
        final preview = lines.take(200).join('\n');
        final truncated = lines.length > 200;
        final displayContent = truncated
            ? '$preview\n\n... (${lines.length - 200} more lines)'
            : preview;

        results.add(ReferencedFile(
          path: path,
          fileName: fileName,
          isTextFile: true,
          content: displayContent,
          contentLoaded: true,
        ));
      } catch (e) {
        results.add(ReferencedFile(
          path: path,
          fileName: fileName,
          isTextFile: true,
          contentLoaded: false,
          error: 'Error reading: $e',
        ));
      }
    }

    return results;
  }

  /// Builds the content sent to the LLM API, including file reference info.
  String _buildApiContent(String message, List<ReferencedFile> files) {
    if (files.isEmpty) return message;

    final buffer = StringBuffer(message.trim());
    buffer.writeln('\n\n--- REFERENCED FILES ---');

    for (final f in files) {
      buffer.writeln();
      if (f.isTextFile && f.contentLoaded && f.content != null) {
        buffer.writeln('FILE: ${f.fileName}');
        buffer.writeln('PATH: ${f.path}');
        buffer.writeln('TYPE: Text file (content below)');
        buffer.writeln('--- BEGIN CONTENT ---');
        buffer.writeln(f.content);
        buffer.writeln('--- END CONTENT ---');
      } else if (f.error != null) {
        buffer.writeln('FILE: ${f.fileName}');
        buffer.writeln('PATH: ${f.path}');
        buffer.writeln('ERROR: ${f.error}');
      } else {
        final ext = f.extension;
        buffer.writeln('FILE: ${f.fileName}');
        buffer.writeln('PATH: ${f.path}');
        buffer.writeln('TYPE: .$ext (non-text file)');
        buffer.writeln('ACTION: Use get_file_info tool to get metadata');
        buffer.writeln(
            'WARNING: Do NOT attempt to read or display this file - it is binary data');
      }
    }
    buffer.writeln('--- END REFERENCED FILES ---');

    return buffer.toString();
  }

  String _buildLocalTranscript(List<AiMessage> messages) {
    final buffer = StringBuffer();
    buffer.writeln('Conversation transcript for local model inference.');
    buffer.writeln(
        'If app data is needed, respond with the exact <tool_call> JSON block described in the system prompt. The app will execute it and send back <tool_result>.');
    buffer.writeln();

    for (final message in messages) {
      late final String role;
      switch (message.role) {
        case AiMessageRole.assistant:
          role = 'assistant';
          break;
        case AiMessageRole.system:
          role = 'system';
          break;
        case AiMessageRole.tool:
          role = 'tool';
          break;
        case AiMessageRole.user:
          role = 'user';
          break;
      }
      buffer.writeln('[$role]');
      buffer.writeln(message.content);
      buffer.writeln();
    }

    buffer.writeln(
        'Continue the conversation. Use tools when the latest user request requires current app state, files, scan results, or cleanup actions.');
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Prompt builders
  // ---------------------------------------------------------------------------

  /// Derives a short conversation title from the first user message.
  static String _titleFromMessages(List<AiMessage> messages) {
    final first = messages.firstWhere(
      (m) => m.role == AiMessageRole.user,
      orElse: () => messages.first,
    );
    return AiChatHistoryService.titleFromContent(first.content);
  }

  String _buildSystemPrompt() {
    final userHome = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        'unknown';
    final pathInfo = state.currentPath.isNotEmpty
        ? 'The user is currently browsing: ${state.currentPath}\nWORKING DIRECTORY: ${state.currentPath}'
        : 'No specific directory selected.\nWORKING DIRECTORY: $userHome';

    // Build platform-specific paths info
    final platformPathsInfo = _buildPlatformPathsInfo();

    return '''$pathInfo
Platform: ${Platform.operatingSystem}
User home: $userHome

$platformPathsInfo

${ToolExecutor.toolDefinitions}

RULES:
- ALWAYS use the WORKING DIRECTORY as the default location for ALL file operations (create, delete, search, list, etc.) unless the user explicitly specifies a different path.
- When the user says "here", "this folder", "current directory" or gives a relative path, resolve it relative to WORKING DIRECTORY.
- Use tools to search. Do NOT guess file paths.
- When the user asks about tags, ALWAYS use list_all_tags first, then search_by_tag.
- When the user asks to find files by name, use search_files.
- When the user asks to find files containing text, use search_content.
- If the user is just chatting, respond normally without tools.
- Always respond in the same language as the user.

CRITICAL - TOOL EXECUTION:
- When you need to create, modify, or delete files, or run commands: CALL THE TOOL DIRECTLY. Do NOT ask the user for permission in text.
- The system has a built-in approval mechanism. When you call a dangerous tool (write_file, delete_file, run_command, clean_disk_junk), the system will AUTOMATICALLY show an approval dialog to the user BEFORE executing.
- You MUST call the tool and let the system handle approval. NEVER say things like "Do you want me to do this?" or "Should I proceed?" — just call the tool.
- If you want to explain what you're about to do, write your explanation FIRST, then call the tool in the same response.
- Example: "I'll create 3 test files in the temp directory." followed by the tool_call block.

CRITICAL - REFERENCED FILES:
- Text files: content is already provided in the message under "--- REFERENCED FILES ---". Use it directly.
- Non-text files (images, videos, audio, PDFs, etc.): You CANNOT read or display these files. Use get_file_info tool ONLY for metadata.
- NEVER attempt to read, display, or process binary files (jpg, png, gif, mp4, mp3, pdf, zip, exe, etc.)
- You are a TEXT-ONLY assistant. You cannot process images, videos, or other binary data.

RESULT FORMAT:
When you found files, include BOTH:
1. A brief explanation in natural language
2. A JSON results block listing ONLY the final matched files:

```json
[{"path": "C:\\exact\\path\\file.mp4", "relevance": 90, "explanation": "reason"}]
```

ONLY include files that actually match the user's query — NOT every file from tool outputs.
Do NOT include the JSON block if no files match.
''';
  }

  /// Builds information about CB File Hub's internal system paths and directory structure.
  String _buildPlatformPathsInfo() {
    final buffer = StringBuffer();
    buffer.writeln('CB FILE HUB SYSTEM PATHS:');
    buffer.writeln(
        'The CB File Hub application stores its internal data in the following locations:');
    buffer.writeln();

    // App cache root directory
    buffer.writeln('1. APP CACHE ROOT:');
    if (Platform.isWindows) {
      buffer.writeln('   - Location: %TEMP%\\cb_file_hub\\');
      buffer.writeln(
          '   - Example: C:\\Users\\<username>\\AppData\\Local\\Temp\\cb_file_hub\\');
    } else if (Platform.isMacOS) {
      buffer.writeln('   - Location: /var/folders/.../T/cb_file_hub/');
      buffer.writeln('   - Example: /var/folders/xx/xxxxxxxxxx/T/cb_file_hub/');
    } else if (Platform.isLinux) {
      buffer.writeln('   - Location: /tmp/cb_file_hub/');
    } else if (Platform.isAndroid) {
      buffer.writeln(
          '   - Location: /data/data/com.coolbird.cbfilehub/cache/cb_file_hub/');
    } else if (Platform.isIOS) {
      buffer.writeln('   - Location: <app_container>/tmp/cb_file_hub/');
    }
    buffer.writeln(
        '   - Purpose: Root directory for all app cache and temporary files');
    buffer.writeln();

    // Subdirectories
    buffer.writeln('2. CACHE SUBDIRECTORIES (under cb_file_hub):');
    buffer.writeln('   - video_thumbnails/: Video thumbnail cache');
    buffer.writeln('   - photo_thumbnails/: Photo thumbnail cache');
    buffer.writeln(
        '   - network_thumbnails/: Network file (SMB/FTP/WebDAV) thumbnail cache');
    buffer.writeln('   - temp_files/: Temporary downloads and SMB file cache');
    buffer.writeln();

    // Database location
    buffer.writeln('3. DATABASE AND PERSISTENT DATA:');
    if (Platform.isWindows) {
      buffer.writeln('   - Location: %USERPROFILE%\\Documents\\');
      buffer.writeln('   - Example: C:\\Users\\<username>\\Documents\\');
    } else if (Platform.isMacOS) {
      buffer.writeln('   - Location: ~/Documents/');
    } else if (Platform.isLinux) {
      buffer.writeln('   - Location: ~/Documents/');
    } else if (Platform.isAndroid) {
      buffer.writeln(
          '   - Location: /data/data/com.coolbird.cbfilehub/app_flutter/');
    } else if (Platform.isIOS) {
      buffer.writeln('   - Location: <app_container>/Documents/');
    }
    buffer.writeln('   - Files stored here:');
    buffer.writeln(
        '     * cb_file_hub.db: Main SQLite database (file metadata, tags, albums, settings)');
    buffer.writeln('     * tag_colors.json: Tag color configuration');
    buffer.writeln('     * album_auto_rules.json: Smart album rules');
    buffer.writeln('     * featured_albums.json: Featured album configuration');
    buffer.writeln('     * smart_albums.json: Smart album definitions');
    buffer.writeln(
        '     * video_library_cache.json: Video library metadata cache');
    buffer.writeln();

    // Platform-specific user directories
    buffer.writeln('4. PLATFORM-SPECIFIC USER DIRECTORIES:');
    if (Platform.isWindows) {
      buffer.writeln('   - Pictures: %USERPROFILE%\\Pictures\\');
      buffer.writeln('   - Downloads: %USERPROFILE%\\Downloads\\');
      buffer.writeln('   - Documents: %USERPROFILE%\\Documents\\');
    } else if (Platform.isMacOS) {
      buffer.writeln('   - Pictures: ~/Pictures/');
      buffer.writeln('   - Downloads: ~/Downloads/');
      buffer.writeln('   - Documents: ~/Documents/');
    } else if (Platform.isLinux) {
      buffer.writeln('   - Pictures: ~/Pictures/');
      buffer.writeln('   - Downloads: ~/Downloads/');
      buffer.writeln('   - Documents: ~/Documents/');
    } else if (Platform.isAndroid) {
      buffer.writeln('   - Pictures: /storage/emulated/0/Pictures/');
      buffer.writeln('   - Downloads: /storage/emulated/0/Download/');
      buffer.writeln('   - Camera: /storage/emulated/0/DCIM/Camera/');
      buffer.writeln('   - All Images: /storage/emulated/0/');
    } else if (Platform.isIOS) {
      buffer.writeln('   - All media: <app_container>/Documents/');
      buffer.writeln(
          '   - Note: iOS uses app sandbox, no direct access to system directories');
    }
    buffer.writeln();

    // System screens
    buffer.writeln('5. SYSTEM SCREENS (Virtual Navigation Paths):');
    buffer.writeln(
        'CB File Hub uses special paths starting with # for system screens. These are NOT file system paths.');
    buffer.writeln();
    buffer.writeln('STATIC SYSTEM SCREENS:');
    buffer.writeln('   - #home: Home screen with quick access and favorites');
    buffer.writeln('   - #tags: Tag management screen');
    buffer.writeln('   - #gallery: Gallery hub for browsing photos');
    buffer.writeln('   - #video: Video hub for browsing videos');
    buffer.writeln('   - #albums: Album management screen');
    buffer.writeln('   - #auto-rules: Smart album auto-rules configuration');
    buffer.writeln('   - #trash: Trash bin / recycle bin');
    buffer.writeln('   - #settings: Application settings');
    buffer.writeln('   - #network: Network connection management');
    buffer.writeln('   - #smb: SMB/CIFS network browser');
    buffer.writeln('   - #ftp: FTP network browser');
    buffer.writeln('   - #webdav: WebDAV network browser');
    buffer.writeln('   - #ai-chat: AI chat screen (this screen you are in)');
    buffer.writeln();
    buffer.writeln('DYNAMIC SYSTEM SCREENS (with parameters):');
    buffer.writeln(
        '   - #video-library/{id}: Video library files screen for a specific library');
    buffer.writeln(
        '     Example: #video-library/1 opens video library with ID 1');
    buffer
        .writeln('   - #album/{id}: Album detail screen for a specific album');
    buffer.writeln('     Example: #album/5 opens album with ID 5');
    buffer.writeln(
        '   - #image?path=...: Image viewer for a specific image file');
    buffer.writeln('     Example: #image?path=C:\\Pictures\\photo.jpg');
    buffer.writeln('   - #search?tag=...: Tag search results screen');
    buffer.writeln(
        '     Example: #search?tag=vacation shows all files tagged "vacation"');
    buffer.writeln(
        '   - #ai-chat?workspace=...: AI chat with specific workspace path');
    buffer.writeln('     Example: #ai-chat?workspace=C:\\Projects');
    buffer.writeln();
    buffer.writeln('NETWORK PATHS:');
    buffer.writeln('   - smb://server/share/path: SMB/CIFS network paths');
    buffer.writeln('   - ftp://server/path: FTP network paths');
    buffer.writeln('   - webdav://server/path: WebDAV network paths');
    buffer.writeln('   - #network/...: Internal network path routing');
    buffer.writeln();

    // Important notes
    buffer.writeln('IMPORTANT NOTES:');
    buffer.writeln(
        '- When users ask about "app data", "cache", or "thumbnails", they are referring to the cb_file_hub directory');
    buffer.writeln(
        '- When users ask about "database" or "tags", they are referring to files in the Documents directory');
    buffer.writeln(
        '- When users mention screens like "video library", "gallery", "albums", they are referring to system screens (# paths)');
    buffer.writeln(
        '- System screens (# paths) are virtual navigation paths, NOT file system directories');
    buffer.writeln(
        '- You CANNOT use file tools (list_directory, search_files, etc.) on system screen paths');
    buffer.writeln('- Thumbnail caches can be safely cleared to free up space');
    buffer.writeln(
        '- The database file (cb_file_hub.db) should NOT be deleted as it contains all user data');
    buffer.writeln('- Use get_file_info tool to check actual paths and sizes');
    buffer.writeln();

    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Response parsing
  // ---------------------------------------------------------------------------

  /// Strips JSON code blocks from the AI response so the chat bubble
  /// only shows the natural-language explanation.
  static String _stripJsonBlocks(String text) {
    // Remove ```json [...] ``` blocks (greedy to catch the full array)
    var cleaned = text.replaceAll(
      RegExp(r'```(?:json)?\s*\n?\[[\s\S]*\]\s*\n?```'),
      '',
    );
    // Trim leftover blank lines
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return cleaned.trim();
  }

  /// Extracts search results from the AI's response text.
  ///
  /// Looks for a JSON array in the response (possibly wrapped in a code block).
  List<AiSearchResult> _parseSearchResults(String responseText) {
    final results = <AiSearchResult>[];
    final seenPaths = <String>{};

    // 1. Try JSON blocks first
    try {
      final codeBlockMatches = RegExp(
        r'```(?:json)?\s*\n?(\[[\s\S]*\])\s*\n?```',
      ).allMatches(responseText);

      String? jsonStr;
      for (final match in codeBlockMatches) {
        final candidate = match.group(1);
        if (candidate != null &&
            (jsonStr == null || candidate.length > jsonStr.length)) {
          jsonStr = candidate;
        }
      }

      if (jsonStr == null) {
        final bareMatches = RegExp(r'\[[\s\S]*\]').allMatches(responseText);
        for (final match in bareMatches) {
          final candidate = match.group(0);
          if (candidate != null &&
              candidate.contains('"path"') &&
              (jsonStr == null || candidate.length > jsonStr.length)) {
            jsonStr = candidate;
          }
        }
      }

      if (jsonStr != null && jsonStr != '[]') {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final result = AiSearchResult.fromAiJson(item);
              if (result.path.isEmpty || seenPaths.contains(result.path)) {
                continue;
              }
              seenPaths.add(result.path);
              final exists = File(result.path).existsSync();
              results.add(result.copyWith(verified: exists));
            }
          }
        }
      }
    } catch (e) {
      AppLogger.debug('[AI Parse] JSON parse failed: $e');
    }

    // 2. Also extract file paths from plain text and tool output
    final pathPattern = RegExp(
      r'(?:^|\s|`)((?:[A-Z]:\\[^\r\n<>"|?*]+)|(?:/(?:[^\r\n<>"|?*])+))',
      multiLine: true,
    );
    for (final match in pathPattern.allMatches(responseText)) {
      final rawPath = match.group(1)?.trim();
      if (rawPath == null || rawPath.length < 4) continue;
      // Remove trailing punctuation
      var cleanPath = _cleanExtractedPath(rawPath);
      while (cleanPath.isNotEmpty &&
          '.,:;)'.contains(cleanPath[cleanPath.length - 1])) {
        cleanPath = cleanPath.substring(0, cleanPath.length - 1);
      }
      if (cleanPath.isEmpty || seenPaths.contains(cleanPath)) continue;

      // Only add if it has a file extension (looks like a file, not a directory)
      if (!cleanPath.contains('.')) continue;

      final exists = File(cleanPath).existsSync();
      if (!exists) continue; // Only add verified paths from plain text

      seenPaths.add(cleanPath);
      final parts = cleanPath.split(RegExp(r'[/\\]'));
      results.add(AiSearchResult(
        path: cleanPath,
        fileName: parts.isNotEmpty ? parts.last : cleanPath,
        relevance: 0,
        explanation: '',
        verified: true,
      ));
    }

    if (results.isNotEmpty) {
      AppLogger.debug(
        '[AI Parse] Found ${results.length} results '
        '(${results.where((r) => r.verified).length} verified)',
      );
    }

    results.sort((a, b) => b.relevance.compareTo(a.relevance));
    return results;
  }

  static String _cleanExtractedPath(String rawPath) {
    var path = rawPath.trim();

    // Tool outputs often append size metadata: C:\file.mp4  (123 MB)
    final parenIndex = path.indexOf('  (');
    if (parenIndex > 0) {
      path = path.substring(0, parenIndex).trim();
    }

    // Content-search outputs look like: C:\file.txt:12: matched text
    final lineNumberMatch = RegExp(r'^(.+?):\d+:').firstMatch(path);
    if (lineNumberMatch != null) {
      path = lineNumberMatch.group(1)!.trim();
    }

    return path.replaceAll('/', Platform.pathSeparator);
  }

  _PreparedContext _prepareContextForProvider(
    List<AiMessage> messages, {
    required String systemPrompt,
    required List<String> activity,
    bool aggressive = false,
  }) {
    final targetLimit =
        aggressive ? _hardContextCharLimit : _softContextCharLimit;
    final totalChars = _estimateContextChars(messages, systemPrompt);
    if (totalChars <= targetLimit ||
        messages.length <= _minRecentMessagesToKeep) {
      return _PreparedContext(
        messages: messages,
        systemPrompt: systemPrompt,
      );
    }

    var recentCount = messages.length > 12 ? 12 : messages.length;
    List<AiMessage> recentMessages =
        messages.sublist(messages.length - recentCount);
    List<AiMessage> olderMessages =
        messages.sublist(0, messages.length - recentCount);

    String summary = _buildCompactedSummary(olderMessages);
    String compactedPrompt = _appendCompactionSummary(systemPrompt, summary);

    while (recentCount > _minRecentMessagesToKeep &&
        _estimateContextChars(recentMessages, compactedPrompt) > targetLimit) {
      recentCount--;
      recentMessages = messages.sublist(messages.length - recentCount);
      olderMessages = messages.sublist(0, messages.length - recentCount);
      summary = _buildCompactedSummary(olderMessages);
      compactedPrompt = _appendCompactionSummary(systemPrompt, summary);
      if (olderMessages.isEmpty) {
        break;
      }
    }

    if (olderMessages.isNotEmpty) {
      final line =
          '> Context compacted: summarized ${olderMessages.length} older message(s)';
      if (activity.isEmpty || activity.last != line) {
        activity.add(line);
      }
    }

    return _PreparedContext(
      messages: recentMessages,
      systemPrompt: compactedPrompt,
    );
  }

  /// Builds a JSON-serializable snapshot of what's about to be sent to the
  /// provider. Used by the "View raw payload" debug action in the chat UI.
  Map<String, dynamic> _buildPayloadSnapshot({
    required List<AiMessage> messages,
    required String systemPrompt,
    required String? providerId,
    required String? modelName,
    required bool stream,
  }) {
    return {
      'providerId': providerId ?? '(default)',
      'modelName': modelName ?? '(default)',
      'stream': stream,
      'systemPrompt': systemPrompt,
      'messages': messages
          .map((m) => {
                'role': m.role.toString().split('.').last,
                'content': m.content,
                if (m.toolCalls != null && m.toolCalls!.isNotEmpty)
                  'toolCalls': m.toolCalls!
                      .map((tc) => {
                            'name': tc.toolName,
                            'arguments': tc.arguments,
                            'result': tc.result,
                            'success': tc.success,
                          })
                      .toList(),
              })
          .toList(),
      'capturedAt': DateTime.now().toIso8601String(),
    };
  }

  int _estimateContextChars(List<AiMessage> messages, String systemPrompt) {
    var total = systemPrompt.length;
    for (final message in messages) {
      total += message.content.length + 24;
    }
    return total;
  }

  String _buildCompactedSummary(List<AiMessage> messages) {
    if (messages.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    buffer.writeln('Conversation summary for earlier turns:');
    var usedChars = 0;

    for (final message in messages) {
      if (message.role != AiMessageRole.user &&
          message.role != AiMessageRole.assistant) {
        continue;
      }

      final role = message.role == AiMessageRole.user ? 'User' : 'Assistant';
      var content = message.content.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (content.isEmpty) {
        continue;
      }
      if (content.length > 240) {
        content = '${content.substring(0, 240)}...';
      }

      final line = '- $role: $content';
      if (usedChars + line.length > _maxSummaryChars) {
        buffer.writeln('- Earlier conversation truncated for size.');
        break;
      }
      buffer.writeln(line);
      usedChars += line.length;
    }

    return buffer.toString().trim();
  }

  String _appendCompactionSummary(String systemPrompt, String summary) {
    if (summary.isEmpty) {
      return systemPrompt;
    }
    return '$systemPrompt\n\n$summary';
  }

  _ResolvedModelSelection _resolveModelSelection({
    required List<AiProviderModelCatalog> catalogs,
    String? selectedProviderId,
    String? selectedModelName,
  }) {
    if (catalogs.isEmpty) {
      return const _ResolvedModelSelection();
    }

    if (selectedProviderId != null && selectedProviderId.isNotEmpty) {
      for (final catalog in catalogs) {
        if (catalog.providerId != selectedProviderId) continue;
        if (selectedModelName != null &&
            selectedModelName.isNotEmpty &&
            catalog.models.contains(selectedModelName)) {
          return _ResolvedModelSelection(
            providerId: selectedProviderId,
            modelName: selectedModelName,
          );
        }
        final fallbackModel = _defaultModelForCatalog(catalog);
        return _ResolvedModelSelection(
          providerId: selectedProviderId,
          modelName: fallbackModel,
        );
      }
    }

    final firstCatalog = catalogs.first;
    return _ResolvedModelSelection(
      providerId: firstCatalog.providerId,
      modelName: _defaultModelForCatalog(firstCatalog),
    );
  }

  /// Persists the last picked provider + model so the chat picker restores it
  /// on next launch. Applies to both remote and local AI selections.
  Future<void> _persistModelSelection(
    String? providerId,
    String? modelName,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (providerId != null && providerId.isNotEmpty) {
        await prefs.setString(_lastProviderIdKey, providerId);
      }
      if (modelName != null && modelName.isNotEmpty) {
        await prefs.setString(_lastModelNameKey, modelName);
      }
    } catch (e) {
      AppLogger.warning('[AiAgentBloc] Failed to persist model selection',
          error: e);
    }
  }

  /// Reads the last persisted provider + model selection (may be null).
  Future<_ResolvedModelSelection> _loadPersistedSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _ResolvedModelSelection(
        providerId: prefs.getString(_lastProviderIdKey),
        modelName: prefs.getString(_lastModelNameKey),
      );
    } catch (e) {
      AppLogger.warning('[AiAgentBloc] Failed to load model selection',
          error: e);
      return const _ResolvedModelSelection();
    }
  }

  String? _defaultModelForCatalog(AiProviderModelCatalog catalog) {
    if (catalog.defaultModelName.trim().isNotEmpty) {
      return catalog.defaultModelName.trim();
    }
    if (catalog.models.isNotEmpty) {
      return catalog.models.first;
    }
    return null;
  }

  bool _isLocalAiSelected() {
    return state.selectedProviderId == _localAiProviderId;
  }

  // ---------------------------------------------------------------------------
  // Local AI catalog helper
  // ---------------------------------------------------------------------------

  /// Returns a catalog entry for the selected local model, or null if none installed.
  AiProviderModelCatalog? _buildLocalAiCatalog() {
    final svc = _localAiService;
    if (svc == null) return null;
    final models = svc.getInstalledModels();
    if (models.isEmpty) return null;
    final selected = svc.getSelectedModel();
    final defaultModel = selected?.displayName ?? models.first.displayName;

    return AiProviderModelCatalog(
      providerId: _localAiProviderId,
      providerName: 'Local AI',
      apiType: AiApiType.openaiCompatible,
      authMode: AiProviderAuthMode.none,
      defaultModelName: defaultModel,
      models: models.map((m) => m.displayName).toList(),
    );
  }

  List<AiProviderModelCatalog> _mergeLocalAiCatalog(
    List<AiProviderModelCatalog> remote,
  ) {
    final localCatalog = _buildLocalAiCatalog();
    if (localCatalog == null) return remote;
    return [...remote, localCatalog];
  }
}

class _ResolvedModelSelection {
  final String? providerId;
  final String? modelName;

  const _ResolvedModelSelection({
    this.providerId,
    this.modelName,
  });
}

class _PreparedContext {
  final List<AiMessage> messages;
  final String systemPrompt;

  const _PreparedContext({
    required this.messages,
    required this.systemPrompt,
  });
}

class _GenerationStopped implements Exception {
  const _GenerationStopped();
}
