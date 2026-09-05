import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../bloc/ai_agent/ai_agent.dart';
import '../../../config/languages/app_localizations.dart';
import '../../../models/ai/ai_message.dart';
import 'components/approval_card.dart';
import 'components/conversation_list_panel.dart';
import '../../tab_manager/core/tab_data.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../../tab_manager/core/tab_paths.dart';
import 'components/chat_input_bar.dart';
import 'components/chat_message_bubble.dart';
import 'components/raw_payload_dialog.dart';
import 'components/tool_call_chip.dart';
import 'components/file_result_card.dart';
import 'components/model_selector_button.dart';
import 'components/shimmer_thinking_text.dart';

/// A right-side AI chat panel that sits beside the main file browser content.
///
/// The [bloc] is owned externally (by [AiPanelController]) so conversation
/// history persists across panel open/close cycles.
class AiSidePanel extends StatefulWidget {
  /// The pre-created bloc for this tab's conversation.
  final AiAgentBloc bloc;

  /// Callback when the user taps close.
  final VoidCallback onClose;

  /// Current panel width, owned by [AiPanelController].
  final double width;

  /// Called while the user drags the panel's left resize handle.
  final ValueChanged<double> onWidthChanged;

  /// Called when the user finishes dragging the panel resize handle.
  final VoidCallback onWidthChangeEnd;

  const AiSidePanel({
    super.key,
    required this.bloc,
    required this.onClose,
    required this.width,
    required this.onWidthChanged,
    required this.onWidthChangeEnd,
  });

  @override
  State<AiSidePanel> createState() => _AiSidePanelState();
}

class _AiSidePanelState extends State<AiSidePanel> {
  // Expose bloc via getter for convenience
  AiAgentBloc get _bloc => widget.bloc;
  final _scrollController = ScrollController();
  final _messageListFocusNode = FocusNode();
  bool _showConversations = false;
  double _convPanelWidth = 220;
  double? _panelResizeStartWidth;
  double _panelResizeTotalDx = 0;
  String? _lastConversationId;
  static const _convPanelMinWidth = 160.0;
  static const _convPanelMaxWidth = 320.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = _bloc.state;
      if (s.messages.isNotEmpty) {
        // Bloc already has messages loaded (e.g. re-opening panel) —
        // the BlocConsumer listener won't fire because there's no state
        // transition, so we must scroll explicitly.
        _lastConversationId = s.conversationId;
        _scrollToBottom(animated: false);
        // Don't auto-show conversation list — user is mid-conversation.
      } else if (s.currentPath.isNotEmpty && s.conversations.isEmpty) {
        // Path has no prior conversations — show the list so user can
        // see existing conversations from other paths or start fresh.
        setState(() => _showConversations = true);
      } else if (s.conversations.isNotEmpty) {
        // There are saved conversations (from other paths) — show the list.
        setState(() => _showConversations = true);
      }
      // else: no path, no messages, no conversations → leave list hidden
      //       (user can open it via the header button).
    });
  }

  @override
  void dispose() {
    // Do NOT close the bloc here — it's owned by AiPanelController
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
          duration: const Duration(milliseconds: 200),
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

  void _toggleConversations() {
    if (!_showConversations) {
      _bloc.add(const RefreshConversations());
    }
    setState(() => _showConversations = !_showConversations);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;

    return BlocProvider.value(
      value: _bloc,
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                // Conversation list panel (animated slide-in from left, resizable)
                ClipRect(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    width: _showConversations ? _convPanelWidth : 0,
                    child: OverflowBox(
                      maxWidth: _convPanelMaxWidth,
                      minWidth: 0,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: _convPanelWidth,
                        child: _showConversations
                            ? Stack(
                                children: [
                                  ConversationListPanel(
                                    onClose: () => setState(
                                      () => _showConversations = false,
                                    ),
                                  ),
                                  // Drag handle on the right edge
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.resizeColumn,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onHorizontalDragUpdate: (details) {
                                          setState(() {
                                            _convPanelWidth =
                                                (_convPanelWidth +
                                                        details.delta.dx)
                                                    .clamp(
                                                      _convPanelMinWidth,
                                                      _convPanelMaxWidth,
                                                    );
                                          });
                                        },
                                        child: const SizedBox(width: 4),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),

                // Main panel content
                Expanded(
                  child: BlocConsumer<AiAgentBloc, AiAgentState>(
                    listenWhen: (prev, curr) {
                      if (prev.conversationId != curr.conversationId) {
                        return true;
                      }
                      if (prev.messages.length != curr.messages.length) {
                        return true;
                      }
                      if (prev.pendingApproval != curr.pendingApproval) {
                        return true;
                      }
                      // Auto-scroll while streaming tokens — track last message
                      // content changes so user follows the generated answer.
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
                      final animate =
                          _lastConversationId == state.conversationId;
                      _lastConversationId = state.conversationId;
                      _scrollToBottom(animated: animate);
                    },
                    builder: (context, state) {
                      return Column(
                        children: [
                          // Header
                          _buildHeader(context, l, theme, state),
                          const Divider(height: 1),

                          // Error banner (provider failures)
                          if (state.error != null)
                            _buildErrorBanner(context, theme, state),

                          // Messages
                          Expanded(
                            child:
                                state.messages.isEmpty &&
                                    state.pendingApproval == null
                                ? _buildEmptyState(context, l, theme, state)
                                : _buildMessages(context, state),
                          ),

                          // Workspace indicator + Input
                          ChatInputBar(
                            onStop: () => _bloc.add(const StopGeneration()),
                            onSend: (text, files) => _bloc.add(
                              SendMessage(text, referencedFiles: files),
                            ),
                            isLoading: state.isLoading,
                            workspaceIndicator: _buildWorkspaceIndicator(
                              context,
                              theme,
                              state,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            _AiPanelResizeHandle(
              onDragStart: (_) => _startPanelResize(),
              onDragUpdate: _updatePanelResize,
              onDragEnd: (_) => _endPanelResize(),
            ),
          ],
        ),
      ),
    );
  }

  void _startPanelResize() {
    _panelResizeStartWidth = widget.width;
    _panelResizeTotalDx = 0;
  }

  void _updatePanelResize(DragUpdateDetails details) {
    _panelResizeStartWidth ??= widget.width;
    _panelResizeTotalDx += details.delta.dx;
    widget.onWidthChanged(_panelResizeStartWidth! - _panelResizeTotalDx);
  }

  void _endPanelResize() {
    _panelResizeStartWidth = null;
    _panelResizeTotalDx = 0;
    widget.onWidthChangeEnd();
  }

  Widget _buildWorkspaceIndicator(
    BuildContext context,
    ThemeData theme,
    AiAgentState state,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final path = state.currentPath;
    // Show just the last folder segment for compactness
    final folderName = path.isNotEmpty
        ? path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).last
        : null;

    // Calculate total context size from messages
    int totalChars = 0;
    for (final m in state.messages) {
      totalChars += m.content.length;
    }

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            folderName != null
                ? PhosphorIconsLight.folderOpen
                : PhosphorIconsLight.hardDrives,
            size: 11,
            color: theme.colorScheme.primary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              folderName ?? 'All Drives',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (path.isNotEmpty)
            Tooltip(
              message: path,
              child: Icon(
                PhosphorIconsLight.info,
                size: 11,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
              ),
            ),
          // Context size indicator
          if (state.messages.isNotEmpty) ...[
            const SizedBox(width: 6),
            _buildContextBadge(theme, totalChars, state.messages.length),
            const SizedBox(width: 2),
            // Debug: view raw payload sent to provider
            IconButton(
              icon: const Icon(PhosphorIconsLight.code, size: 12),
              tooltip: 'View raw payload',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: () => RawPayloadDialog.show(context, state),
            ),
          ],
        ],
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
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
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
            size: 14,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Provider error',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  state.error!,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (state.lastApiPayload != null)
            IconButton(
              icon: const Icon(PhosphorIconsLight.code, size: 12),
              tooltip: 'View payload',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: () => RawPayloadDialog.show(context, state),
            ),
          IconButton(
            icon: const Icon(PhosphorIconsLight.x, size: 12),
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            onPressed: () => _bloc.add(const ClearError()),
          ),
        ],
      ),
    );
  }

  Widget _buildContextBadge(ThemeData theme, int totalChars, int messageCount) {
    final label = totalChars >= 1000
        ? '${(totalChars / 1000).toStringAsFixed(1)}K'
        : '$totalChars';
    // Color shifts toward warning as context grows (~24K soft limit)
    final ratio = (totalChars / 24000).clamp(0.0, 1.0);
    final Color color;
    if (ratio > 0.85) {
      color = theme.colorScheme.error.withValues(alpha: 0.8);
    } else if (ratio > 0.6) {
      color = Colors.orange.withValues(alpha: 0.75);
    } else {
      color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    }

    return Tooltip(
      message:
          '$messageCount messages · $totalChars chars\n'
          'Context trimming starts at ~24K chars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsLight.database, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
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
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          _PanelHeaderIconButton(
            icon: _showConversations
                ? PhosphorIconsLight.sidebarSimple
                : PhosphorIconsLight.chatsCircle,
            tooltip: l.conversations,
            isDark: isDark,
            onPressed: _toggleConversations,
          ),
          const SizedBox(width: 4),
          Icon(
            PhosphorIconsLight.sparkle,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l.cbAgent,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          if (state.providerModelCatalogs.isNotEmpty ||
              state.isLoadingProviderModels) ...[
            ModelSelectorButton(
              catalogs: state.providerModelCatalogs,
              selectedProviderId: state.selectedProviderId,
              selectedModelName: state.selectedModelName,
              isLoading: state.isLoadingProviderModels,
              tooltip: l.selectModel,
              defaultLabel: l.defaultModel,
              loadingLabel: l.loadingModels,
              emptyLabel: l.noModelConfigured,
              searchHint: l.modelSearchHint,
              noMatchesLabel: l.noModelsFound,
              compact: true,
              onSelected: (value) {
                _bloc.add(
                  SelectChatModel(
                    providerId: value.providerId,
                    modelName: value.modelName,
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
          ],
          _PanelHeaderIconButton(
            icon: PhosphorIconsLight.x,
            tooltip: l.cancel,
            onPressed: widget.onClose,
            isDark: isDark,
          ),
        ],
      ),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsLight.sparkle,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              l.askAiToFindFiles,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (!state.isProviderConfigured) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => _navigateToSettings(context),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIconsLight.gear,
                        size: 12,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l.setupAiProvider,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessages(BuildContext context, AiAgentState state) {
    final theme = Theme.of(context);
    final hasThinking = state.thinkingText != null;
    final hasApproval = state.pendingApproval != null;

    // Calculate item count: messages + thinking bubble + approval card
    final itemCount =
        state.messages.length + (hasThinking ? 1 : 0) + (hasApproval ? 1 : 0);

    return Focus(
      focusNode: _messageListFocusNode,
      onKeyEvent: _handleMessageListKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _messageListFocusNode.requestFocus(),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            // Approval card at the very end (after thinking bubble)
            if (hasApproval && index == itemCount - 1) {
              return Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: _buildApprovalCard(context, theme, state),
              );
            }

            // Thinking bubble (second to last if approval exists, otherwise last)
            final thinkingIndex = hasApproval ? itemCount - 2 : itemCount - 1;
            if (hasThinking && index == thinkingIndex) {
              return _buildThinking(context, state);
            }

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

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tool calls render BEFORE the assistant message
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
                        !state.isLoading && message.role == AiMessageRole.user
                        ? (content) => _bloc.add(
                            EditMessage(
                              messageId: message.id,
                              content: content,
                            ),
                          )
                        : null,
                  ),
                  if (hasResults)
                    ...message.searchResults!.map(
                      (r) => FileResultCard(
                        result: r,
                        onTap: () => _openFileInTab(context, r.path),
                        onOpenFolder: () => _openFolderInTab(context, r.path),
                        onOpenExternal: () =>
                            _openFileExternal(context, r.path),
                      ),
                    ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
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

  Widget _buildApprovalCard(
    BuildContext context,
    ThemeData theme,
    AiAgentState state,
  ) {
    final approval = state.pendingApproval!;
    return ApprovalCard(
      approval: approval,
      onApprove: () => _bloc.add(ApproveAction(approval.id)),
      onReject: () => _bloc.add(RejectAction(approval.id)),
    );
  }

  Widget _buildThinking(BuildContext context, AiAgentState state) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ShimmerThinkingText(text: state.thinkingText ?? 'Thinking...'),
            if (state.currentToolCalls.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...state.currentToolCalls.map((tc) => ToolCallChip(toolCall: tc)),
            ],
          ],
        ),
      ),
    );
  }

  /// Navigate the current active tab to the file's parent folder with highlight.
  void _openFileInTab(BuildContext context, String filePath) {
    final file = File(filePath);
    final parentDir = file.parent.path;
    final fileName = filePath.split(Platform.pathSeparator).last;
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    final activeTab = tabBloc.state.activeTab;
    if (activeTab != null && !activeTab.path.startsWith('#')) {
      // Navigate the current tab directly
      tabBloc.add(UpdateTabPath(activeTab.id, parentDir));
      // Also update name and highlight
      tabBloc.add(
        UpdateTabName(
          activeTab.id,
          parentDir.split(Platform.pathSeparator).last,
        ),
      );
      // Add new tab for highlight (since UpdateTabPath doesn't support highlight)
      // Use AddTab only if the tab is a system screen
    } else {
      // No suitable active tab — open a new one
      tabBloc.add(
        AddTab(
          path: parentDir,
          name: parentDir.split(Platform.pathSeparator).last,
          switchToTab: true,
          highlightedFileName: fileName,
        ),
      );
    }
  }

  /// Navigate the current active tab to the file's parent folder.
  void _openFolderInTab(BuildContext context, String filePath) {
    final file = File(filePath);
    final parentDir = file.parent.path;
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    final activeTab = tabBloc.state.activeTab;
    if (activeTab != null && !activeTab.path.startsWith('#')) {
      tabBloc.add(UpdateTabPath(activeTab.id, parentDir));
      tabBloc.add(
        UpdateTabName(
          activeTab.id,
          parentDir.split(Platform.pathSeparator).last,
        ),
      );
    } else {
      tabBloc.add(
        AddTab(
          path: parentDir,
          name: parentDir.split(Platform.pathSeparator).last,
          switchToTab: true,
        ),
      );
    }
  }

  void _openFileExternal(BuildContext context, String filePath) {
    try {
      if (Platform.isWindows) {
        Process.start('explorer', [filePath], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        Process.start('open', [filePath], mode: ProcessStartMode.detached);
      } else {
        Process.start('xdg-open', [filePath], mode: ProcessStartMode.detached);
      }
    } catch (_) {}
  }

  void _navigateToSettings(BuildContext context) {
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    // Switch to existing settings tab if already open, otherwise add it
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
}

class _AiPanelResizeHandle extends StatelessWidget {
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  const _AiPanelResizeHandle({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: onDragStart,
          onHorizontalDragUpdate: onDragUpdate,
          onHorizontalDragEnd: onDragEnd,
          child: SizedBox(
            width: 10,
            child: Center(
              child: Container(
                width: 3,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.75,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelHeaderIconButton extends StatefulWidget {
  final IconData icon;
  final String? tooltip;
  final bool isDark;
  final VoidCallback? onPressed;

  const _PanelHeaderIconButton({
    required this.icon,
    required this.isDark,
    this.tooltip,
    this.onPressed,
  });

  @override
  State<_PanelHeaderIconButton> createState() => _PanelHeaderIconButtonState();
}

class _PanelHeaderIconButtonState extends State<_PanelHeaderIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bg = _pressed
        ? (widget.isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.10))
        : _hovered
        ? (widget.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06))
        : Colors.transparent;

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
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Icon(
              widget.icon,
              size: 17,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
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
