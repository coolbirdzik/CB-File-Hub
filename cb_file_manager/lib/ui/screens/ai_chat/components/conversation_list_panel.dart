import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../bloc/ai_agent/ai_agent.dart';
import '../../../../config/languages/app_localizations.dart';
import '../../../../models/ai/ai_conversation.dart';

/// Side panel listing saved conversations, styled with acrylic/frosted-glass
/// to match the desktop Fluent design system.
///
/// Displayed as the left column inside the chat screen when toggled.
class ConversationListPanel extends StatelessWidget {
  final VoidCallback onClose;

  const ConversationListPanel({Key? key, required this.onClose})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return BlocBuilder<AiAgentBloc, AiAgentState>(
      buildWhen: (prev, curr) =>
          prev.conversations != curr.conversations ||
          prev.conversationId != curr.conversationId,
      builder: (context, state) {
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          width: 260,
          decoration: BoxDecoration(
            // Subtle tint — the native window acrylic shows through since
            // the scaffold background is transparent.
            color: isDark
                ? Colors.black.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.22),
            border: Border(
              right: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.07),
              ),
            ),
          ),
          child: Column(
            children: [
              // Header
              SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.conversations,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      _AcrylicIconButton(
                        icon: PhosphorIconsLight.plus,
                        tooltip: l.newConversation,
                        isDark: isDark,
                        onPressed: () {
                          context
                              .read<AiAgentBloc>()
                              .add(const NewConversation());
                          onClose();
                        },
                      ),
                      const SizedBox(width: 2),
                      _AcrylicIconButton(
                        icon: PhosphorIconsLight.x,
                        size: 15,
                        isDark: isDark,
                        onPressed: onClose,
                      ),
                      const SizedBox(width: 2),
                    ],
                  ),
                ),
              ),

              Container(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.06),
              ),

              // Conversation list
              Expanded(
                child: state.conversations.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l.noConversations,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.65),
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: state.conversations.length,
                        itemBuilder: (context, index) {
                          final conv = state.conversations[index];
                          return _ConversationTile(
                            conversation: conv,
                            isActive: conv.id == state.conversationId,
                            isDark: isDark,
                            onTap: () {
                              if (conv.id != state.conversationId) {
                                context
                                    .read<AiAgentBloc>()
                                    .add(SwitchConversation(conv.id));
                              }
                              onClose();
                            },
                            onDelete: () {
                              context
                                  .read<AiAgentBloc>()
                                  .add(DeleteConversation(conv.id));
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Acrylic-style icon button (no ripple, subtle hover)
// ---------------------------------------------------------------------------

class _AcrylicIconButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final String? tooltip;
  final bool isDark;
  final VoidCallback? onPressed;

  const _AcrylicIconButton({
    required this.icon,
    required this.isDark,
    this.size = 17,
    this.tooltip,
    this.onPressed,
  });

  @override
  State<_AcrylicIconButton> createState() => _AcrylicIconButtonState();
}

class _AcrylicIconButtonState extends State<_AcrylicIconButton> {
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Center(
            child: Icon(
              widget.icon,
              size: widget.size,
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

// ---------------------------------------------------------------------------
// Conversation tile
// ---------------------------------------------------------------------------

class _ConversationTile extends StatefulWidget {
  final AiConversationSummary conversation;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.isActive,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final Color bg;
    if (widget.isActive) {
      bg = theme.colorScheme.primary
          .withValues(alpha: widget.isDark ? 0.22 : 0.13);
    } else if (_hovered) {
      bg = widget.isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.04);
    } else {
      bg = Colors.transparent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.isActive
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.22),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIconsLight.chatCircle,
                size: 15,
                color: widget.isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.65),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.isActive
                            ? FontWeight.w500
                            : FontWeight.normal,
                        color: widget.isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        if (widget.conversation.initialPath.isNotEmpty) ...[
                          Icon(
                            PhosphorIconsLight.folder,
                            size: 10,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.45),
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              widget.conversation.initialPathShort,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _relativeDate(widget.conversation.updatedAt),
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_hovered || widget.isActive)
                _DeleteButton(
                  tooltip: l.deleteConversation,
                  isDark: widget.isDark,
                  onPressed: widget.onDelete,
                )
              else
                const SizedBox(width: 24),
            ],
          ),
        ),
      ),
    );
  }

  static String _relativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ---------------------------------------------------------------------------
// Delete button with hover-reveal red tint
// ---------------------------------------------------------------------------

class _DeleteButton extends StatefulWidget {
  final String tooltip;
  final bool isDark;
  final VoidCallback onPressed;

  const _DeleteButton({
    required this.tooltip,
    required this.isDark,
    required this.onPressed,
  });

  @override
  State<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<_DeleteButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _hovered
                  ? theme.colorScheme.error.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Icon(
                PhosphorIconsLight.trash,
                size: 13,
                color: _hovered
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
