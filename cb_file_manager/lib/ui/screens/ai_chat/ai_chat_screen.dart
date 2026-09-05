import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../bloc/ai_agent/ai_agent.dart';
import '../../../config/languages/app_localizations.dart';
import '../../../models/ai/ai_message.dart';
import '../../../models/ai/ai_search_result.dart';
import 'components/approval_card.dart';
import '../../../services/ai/ai_chat_history_service.dart';
import '../../../services/ai/ai_provider_service.dart';
import '../../../services/ai/file_context_builder.dart';
import '../../../services/local_ai/local_ai_advisor_service.dart';
import '../../tab_manager/core/tab_data.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../../tab_manager/core/tab_paths.dart';
import 'components/chat_input_bar.dart';
import 'components/chat_message_bubble.dart';
import 'components/raw_payload_dialog.dart';
import 'components/tool_call_chip.dart';
import 'components/conversation_list_panel.dart';
import 'components/file_result_card.dart';
import 'components/model_selector_button.dart';
import 'components/shimmer_thinking_text.dart';

/// AI Chat screen that opens as a tab in the tab manager.
///
/// Provides a conversational interface for natural-language file search
/// powered by a configurable AI provider backend.
class AiChatScreen extends StatelessWidget {
  final String tabId;

  /// Initial directory path for file context building.
  final String initialPath;

  const AiChatScreen({super.key, required this.tabId, this.initialPath = ''});

  @override
  Widget build(BuildContext context) {
    // Resolve l10n before BlocProvider so AppLocalizations is accessible
    return Builder(
      builder: (ctx) {
        final l = AppLocalizations.of(ctx)!;
        return BlocProvider<AiAgentBloc>(
          create: (_) {
            final getIt = GetIt.instance;
            final bloc = AiAgentBloc(
              providerService: getIt<AiProviderService>(),
              historyService: getIt<AiChatHistoryService>(),
              localAiService: getIt.isRegistered<LocalAiAdvisorService>()
                  ? getIt<LocalAiAdvisorService>()
                  : null,
              thinkingPhrases: [
                l.aiThinking0,
                l.aiThinking1,
                l.aiThinking2,
                l.aiThinking3,
              ],
              waitingApproval: l.aiWaitingApproval,
              runningToolTemplate: l.aiRunningTool('{}'),
            );
            bloc.add(
              InitializeAiAgent(
                startFreshConversation: initialPath.isEmpty,
                workspacePath: initialPath,
              ),
            );
            if (initialPath.isNotEmpty) {
              bloc.add(UpdateCurrentPath(initialPath));
            }
            return bloc;
          },
          child: const _AiChatBody(),
        );
      },
    );
  }
}

class _AiChatBody extends StatefulWidget {
  const _AiChatBody();

  @override
  State<_AiChatBody> createState() => _AiChatBodyState();
}

class _AiChatBodyState extends State<_AiChatBody> {
  final _scrollController = ScrollController();
  final _messageListFocusNode = FocusNode();
  bool _showConversations = false;
  String? _lastConversationId;

  @override
  void initState() {
    super.initState();
    // Scroll to bottom on initial build if the conversation already has
    // messages loaded. The BlocConsumer listener won't fire for the initial
    // state — only for subsequent state transitions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AiAgentBloc>().state;
      if (state.messages.isNotEmpty) {
        _lastConversationId = state.conversationId;
        _scrollToBottom(animated: false);
      }
    });
  }

  void _toggleConversations() {
    if (!_showConversations) {
      context.read<AiAgentBloc>().add(const RefreshConversations());
    }
    _setConversationsVisible(!_showConversations);
  }

  void _setConversationsVisible(bool visible) {
    if (_showConversations == visible) return;
    setState(() => _showConversations = visible);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageListFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (animated) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        // Second callback ensures we hit the true bottom after ListView
        // finishes laying out all items (important for large conversations).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return BlocConsumer<AiAgentBloc, AiAgentState>(
      listenWhen: (prev, curr) {
        if (prev.conversationId != curr.conversationId) return true;
        // Scroll when message count changes or during streaming
        if (prev.messages.length != curr.messages.length) return true;
        // Also scroll when approval card appears so it's visible
        if (prev.pendingApproval != curr.pendingApproval) return true;
        if (!curr.isLoading) return false;
        final prevLast = prev.messages.isNotEmpty
            ? prev.messages.last.content
            : '';
        final currLast = curr.messages.isNotEmpty
            ? curr.messages.last.content
            : '';
        return prevLast != currLast;
      },
      listener: (context, state) {
        final animate = _lastConversationId == state.conversationId;
        _lastConversationId = state.conversationId;
        _scrollToBottom(animated: animate);
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Matches the app's other side menus (see CleanerUtilitiesShell):
              // an inline column that pushes the content aside rather than an
              // overlay flying in over it. Narrow layouts give it two thirds.
              final isCompact = constraints.maxWidth < 600;
              final panelWidth = isCompact
                  ? constraints.maxWidth * 2 / 3
                  : 280.0.clamp(0.0, constraints.maxWidth);

              return Row(
                children: [
                  // Conversation history side menu
                  ClipRect(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: _showConversations ? panelWidth : 0,
                      child: OverflowBox(
                        minWidth: 0,
                        maxWidth: panelWidth,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: panelWidth,
                          child: _showConversations
                              ? ConversationListPanel(
                                  onClose: () =>
                                      _setConversationsVisible(false),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),

                  // Main chat area
                  Expanded(
                    child: Column(
                      children: [
                        // Header
                        _buildHeader(context, l, theme, state),

                        // Error banner (provider failures, bad request, etc.)
                        if (state.error != null)
                          _buildErrorBanner(context, theme, state),

                        // Messages / empty state
                        Expanded(
                          child:
                              state.messages.isEmpty &&
                                  state.pendingApproval == null
                              ? _buildEmptyState(context, l, theme, state)
                              : _buildMessageList(context, state),
                        ),

                        // Workspace indicator + Input bar
                        ChatInputBar(
                          onStop: () => context.read<AiAgentBloc>().add(
                            const StopGeneration(),
                          ),
                          onSend: (text, files) {
                            context.read<AiAgentBloc>().add(
                              SendMessage(text, referencedFiles: files),
                            );
                          },
                          isLoading: state.isLoading,
                          workspaceIndicator: _buildWorkspaceIndicator(
                            context,
                            l,
                            theme,
                            state,
                          ),
                          modelSelector: _buildModelSelector(
                            context,
                            l,
                            theme,
                            state,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildWorkspaceIndicator(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
    AiAgentState state,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final hasPath = state.currentPath.isNotEmpty;
    // Derive display label from scope
    late IconData scopeIcon;
    late String scopeLabel;
    switch (state.searchScope) {
      case SearchScope.currentDirectory:
        scopeIcon = PhosphorIconsLight.folder;
        scopeLabel = l.currentFolder;
        break;
      case SearchScope.recursive:
        scopeIcon = PhosphorIconsLight.folderOpen;
        scopeLabel = l.recursiveSearch;
        break;
      case SearchScope.taggedFiles:
        scopeIcon = PhosphorIconsLight.tag;
        scopeLabel = l.aiTaggedFiles;
        break;
      default:
        scopeIcon = PhosphorIconsLight.hardDrives;
        scopeLabel = l.allDrives;
    }

    // Calculate total context size from messages
    final contextInfo = _calcContextInfo(state.messages);

    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            scopeIcon,
            size: 12,
            color: theme.colorScheme.primary.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 5),
          Text(
            scopeLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary.withValues(alpha: 0.85),
            ),
          ),
          if (hasPath) ...[
            const SizedBox(width: 6),
            Icon(
              PhosphorIconsLight.caretRight,
              size: 10,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                state.currentPath,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),
          // Context size indicator
          if (state.messages.isNotEmpty) ...[
            const SizedBox(width: 8),
            _ContextSizeIndicator(contextInfo: contextInfo, isDark: isDark),
            const SizedBox(width: 4),
            // Debug: view raw payload sent to provider
            IconButton(
              icon: const Icon(PhosphorIconsLight.code, size: 14),
              tooltip: 'View raw payload',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () => RawPayloadDialog.show(context, state),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
    AiAgentState state,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    // Borderless, compact toolbar — the chat content below provides the
    // visual separation, so a hairline rule here only adds noise.
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            // Conversations toggle — labelled so it reads as the way back to
            // history rather than an anonymous glyph.
            _HeaderIconButton(
              icon: PhosphorIconsLight.chatsCircle,
              label: l.conversations,
              isDark: isDark,
              isActive: _showConversations,
              onPressed: _toggleConversations,
            ),
            const Spacer(),
            // New conversation button
            _HeaderIconButton(
              icon: PhosphorIconsLight.plus,
              tooltip: l.newConversation,
              isDark: isDark,
              onPressed: () {
                context.read<AiAgentBloc>().add(const NewConversation());
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Model picker rendered inside the composer footer. Returns null when there
  /// is nothing to pick from yet.
  Widget? _buildModelSelector(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
    AiAgentState state,
  ) {
    if (state.providerModelCatalogs.isEmpty && !state.isLoadingProviderModels) {
      return null;
    }
    return ModelSelectorButton(
      catalogs: state.providerModelCatalogs,
      selectedProviderId: state.selectedProviderId,
      selectedModelName: state.selectedModelName,
      isLoading: state.isLoadingProviderModels,
      compact: true,
      tooltip: l.selectModel,
      defaultLabel: l.defaultModel,
      loadingLabel: l.loadingModels,
      emptyLabel: l.noModelConfigured,
      searchHint: l.modelSearchHint,
      noMatchesLabel: l.noModelsFound,
      onSelected: (value) {
        context.read<AiAgentBloc>().add(
          SelectChatModel(
            providerId: value.providerId,
            modelName: value.modelName,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
    AiAgentState state,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.18),
                    theme.colorScheme.primary.withValues(alpha: 0.04),
                  ],
                ),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Icon(
                PhosphorIconsLight.brain,
                size: 32,
                color: theme.colorScheme.primary.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l.cbAgent,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              l.askAiToFindFiles,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.85,
                ),
              ),
              textAlign: TextAlign.center,
            ),
            if (!state.isProviderConfigured) ...[
              const SizedBox(height: 12),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _navigateToSettings(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIconsLight.warningCircle,
                              size: 16,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l.noProviderConfigured,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIconsLight.gear,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l.setupAiProvider,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              PhosphorIconsLight.arrowRight,
                              size: 12,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(
    BuildContext context,
    ThemeData theme,
    AiAgentState state,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIconsLight.warningCircle,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Provider error',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  state.error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (state.lastApiPayload != null)
            TextButton.icon(
              icon: const Icon(PhosphorIconsLight.code, size: 14),
              label: const Text('View payload'),
              onPressed: () => RawPayloadDialog.show(context, state),
            ),
          IconButton(
            icon: const Icon(PhosphorIconsLight.x, size: 14),
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            onPressed: () =>
                context.read<AiAgentBloc>().add(const ClearError()),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(BuildContext context, AiAgentState state) {
    final theme = Theme.of(context);
    final hasThinking = state.thinkingText != null;
    final hasApproval = state.pendingApproval != null;

    return Focus(
      focusNode: _messageListFocusNode,
      onKeyEvent: _handleMessageListKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _messageListFocusNode.requestFocus(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: _itemCount(state),
              itemBuilder: (context, index) {
                // Approval card at the very end (after thinking bubble)
                if (hasApproval && index == _itemCount(state) - 1) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: _buildApprovalCard(context, theme, state),
                  );
                }

                // Thinking indicator (second to last if approval exists, otherwise last)
                final thinkingIndex = hasApproval
                    ? _itemCount(state) - 2
                    : _itemCount(state) - 1;
                if (hasThinking && index == thinkingIndex) {
                  return _buildThinkingBubble(context, state);
                }

                // Message bubbles
                if (index < state.messages.length) {
                  final message = state.messages[index];
                  final isAssistant = message.role == AiMessageRole.assistant;
                  final hasResults =
                      isAssistant &&
                      message.searchResults != null &&
                      message.searchResults!.isNotEmpty;
                  final hasToolCalls =
                      isAssistant &&
                      message.toolCalls != null &&
                      message.toolCalls!.isNotEmpty;
                  final showToolLog =
                      isAssistant &&
                      !state.isLoading &&
                      index == state.messages.length - 1 &&
                      state.toolActivity.isNotEmpty;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tool calls render BEFORE the assistant message because
                      // chronologically the agent calls tools first, then writes
                      // the answer using the tool results.
                      if (hasToolCalls)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 12,
                            right: 12,
                            bottom: 4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: message.toolCalls!
                                .map((tc) => ToolCallChip(toolCall: tc))
                                .toList(),
                          ),
                        ),
                      ChatMessageBubble(
                        message: message,
                        onEdit:
                            !state.isLoading &&
                                message.role == AiMessageRole.user
                            ? (content) => context.read<AiAgentBloc>().add(
                                EditMessage(
                                  messageId: message.id,
                                  content: content,
                                ),
                              )
                            : null,
                        onRetry: message.error != null
                            ? () => context.read<AiAgentBloc>().add(
                                const RetryLastMessage(),
                              )
                            : null,
                      ),
                      // File results inline below this assistant message
                      if (hasResults)
                        _buildInlineResults(context, message.searchResults!),
                      // Tool activity log (only on the latest assistant message)
                      if (showToolLog)
                        _ToolActivityLog(activity: state.toolActivity),
                    ],
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleMessageListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_scrollController.hasClients) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.home) {
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.end) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _scrollByPage(-1);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _scrollByPage(1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollByPage(int direction) {
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final target = (position.pixels + (viewport * direction)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  int _itemCount(AiAgentState state) {
    int count = state.messages.length;
    if (state.thinkingText != null) count++;
    if (state.pendingApproval != null) count++;
    return count;
  }

  Widget _buildInlineResults(
    BuildContext context,
    List<AiSearchResult> results,
  ) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 48, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.files,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '${l.aiSearchResults} (${results.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          ...results.map(
            (result) => FileResultCard(
              result: result,
              onTap: () => _openFileInTab(context, result.path),
              onOpenFolder: () => _openFolderInTab(context, result.path),
              onOpenExternal: () => _openFileExternal(context, result.path),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingBubble(BuildContext context, AiAgentState state) {
    final theme = Theme.of(context);
    final text =
        state.thinkingText ?? AppLocalizations.of(context)!.findingFiles;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, right: 48),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.55,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ShimmerThinkingText(text: text),
            if (state.currentToolCalls.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...state.currentToolCalls.map((tc) => ToolCallChip(toolCall: tc)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalCard(
    BuildContext context,
    ThemeData theme,
    AiAgentState state,
  ) {
    final approval = state.pendingApproval!;
    return ApprovalCard(
      approval: approval,
      onApprove: () =>
          context.read<AiAgentBloc>().add(ApproveAction(approval.id)),
      onReject: () =>
          context.read<AiAgentBloc>().add(RejectAction(approval.id)),
    );
  }

  void _navigateToSettings(BuildContext context) {
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    // Check if settings tab already exists
    final existingTab = tabBloc.state.tabs.firstWhere(
      (tab) => tab.path == kSettingsPath,
      orElse: () => TabData(id: '', name: '', path: ''),
    );
    if (existingTab.id.isNotEmpty) {
      tabBloc.add(SwitchToTab(existingTab.id));
    } else {
      tabBloc.add(
        AddTab(
          path: kSettingsPath,
          name: AppLocalizations.of(context)!.settings,
          switchToTab: true,
        ),
      );
    }
  }

  /// Opens the file's parent directory in a new tab with the file highlighted.
  void _openFileInTab(BuildContext context, String filePath) {
    final file = File(filePath);
    final parentDir = file.parent.path;
    final fileName = filePath.split(Platform.pathSeparator).last;
    final dirName = parentDir.split(Platform.pathSeparator).last;

    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    tabBloc.add(
      AddTab(
        path: parentDir,
        name: dirName,
        switchToTab: true,
        highlightedFileName: fileName,
      ),
    );
  }

  /// Opens the file's parent directory in a new tab (without file highlight).
  void _openFolderInTab(BuildContext context, String filePath) {
    final file = File(filePath);
    final parentDir = file.parent.path;
    final dirName = parentDir.split(Platform.pathSeparator).last;

    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    tabBloc.add(AddTab(path: parentDir, name: dirName, switchToTab: true));
  }

  /// Opens the file with the OS default application.
  void _openFileExternal(BuildContext context, String filePath) {
    try {
      if (Platform.isWindows) {
        Process.start('explorer', [filePath], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        Process.start('open', [filePath], mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        Process.start('xdg-open', [filePath], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      debugPrint('Failed to open file: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Acrylic-style icon button used in the chat header
// ---------------------------------------------------------------------------

class _HeaderIconButton extends StatefulWidget {
  final IconData icon;

  /// When set the button renders as a labelled pill instead of a square icon.
  final String? label;
  final String? tooltip;
  final bool isDark;

  /// Keeps the hover background painted while the target is open.
  final bool isActive;
  final VoidCallback? onPressed;

  const _HeaderIconButton({
    required this.icon,
    required this.isDark,
    this.label,
    this.tooltip,
    this.isActive = false,
    this.onPressed,
  });

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bg = _pressed
        ? (widget.isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.10))
        : (_hovered || widget.isActive)
        ? (widget.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06))
        : Colors.transparent;

    final fg = widget.isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.8);

    final hasLabel = widget.label != null;

    Widget btn = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 32,
          width: hasLabel ? null : 32,
          padding: hasLabel
              ? const EdgeInsets.symmetric(horizontal: 10)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(hasLabel ? 999 : 7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: fg),
              if (hasLabel) ...[
                const SizedBox(width: 7),
                Text(
                  widget.label!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

/// Expandable tool activity log shown after the assistant response.
class _ToolActivityLog extends StatefulWidget {
  final List<String> activity;

  const _ToolActivityLog({required this.activity});

  @override
  State<_ToolActivityLog> createState() => _ToolActivityLogState();
}

class _ToolActivityLogState extends State<_ToolActivityLog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, right: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded
                        ? PhosphorIconsLight.caretDown
                        : PhosphorIconsLight.caretRight,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    PhosphorIconsLight.terminal,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tool activity',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              margin: const EdgeInsets.only(left: 8, top: 2),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.activity
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: line.startsWith('>')
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Context size helpers & indicator
// ---------------------------------------------------------------------------

class _ContextInfo {
  final int totalChars;
  final int messageCount;

  const _ContextInfo({required this.totalChars, required this.messageCount});
}

_ContextInfo _calcContextInfo(List<AiMessage> messages) {
  int totalChars = 0;
  for (final m in messages) {
    totalChars += m.content.length;
  }
  return _ContextInfo(totalChars: totalChars, messageCount: messages.length);
}

String _formatCompactSize(int chars) {
  if (chars >= 1000000) {
    return '${(chars / 1000000).toStringAsFixed(1)}M';
  }
  if (chars >= 1000) {
    return '${(chars / 1000).toStringAsFixed(1)}K';
  }
  return '$chars';
}

class _ContextSizeIndicator extends StatelessWidget {
  final _ContextInfo contextInfo;
  final bool isDark;

  const _ContextSizeIndicator({
    required this.contextInfo,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chars = contextInfo.totalChars;
    final label = _formatCompactSize(chars);

    // Color shifts toward warning as context grows
    // Soft limit is ~24K chars in the bloc
    final ratio = (chars / 24000).clamp(0.0, 1.0);
    final Color indicatorColor;
    if (ratio > 0.85) {
      indicatorColor = theme.colorScheme.error.withValues(alpha: 0.8);
    } else if (ratio > 0.6) {
      indicatorColor = Colors.orange.withValues(alpha: 0.75);
    } else {
      indicatorColor = theme.colorScheme.onSurfaceVariant.withValues(
        alpha: 0.5,
      );
    }

    return Tooltip(
      message:
          '${contextInfo.messageCount} messages · $chars chars\n'
          'Context trimming starts at ~24K chars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsLight.database, size: 10, color: indicatorColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: indicatorColor,
            ),
          ),
        ],
      ),
    );
  }
}
