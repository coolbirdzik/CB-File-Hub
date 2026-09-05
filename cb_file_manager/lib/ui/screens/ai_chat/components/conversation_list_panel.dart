import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../bloc/ai_agent/ai_agent.dart';
import '../../../../config/languages/app_localizations.dart';
import '../../../../design_system/primitives/cb_tooltip.dart';
import '../../../../models/ai/ai_conversation.dart';

/// Side drawer listing saved conversations.
///
/// Deliberately flat: a solid theme surface, one hairline edge, no blur,
/// shadow or gradient. Slides in over the chat from the left; the caller
/// decides its width (a fixed column on desktop, two thirds on narrow
/// layouts).
class ConversationListPanel extends StatelessWidget {
  final VoidCallback onClose;

  const ConversationListPanel({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return BlocBuilder<AiAgentBloc, AiAgentState>(
      buildWhen: (prev, curr) =>
          prev.conversations != curr.conversations ||
          prev.conversationId != curr.conversationId,
      builder: (context, state) {
        return DecoratedBox(
          decoration: BoxDecoration(
            // Same surface the app's other side menus use.
            color: scheme.surfaceContainerLow,
            border: Border(right: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Column(
            children: [
              // Header — same height as the chat header so the two align.
              SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.conversations,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      _FlatIconButton(
                        icon: PhosphorIconsLight.plus,
                        tooltip: l.newConversation,
                        onPressed: () {
                          context.read<AiAgentBloc>().add(
                            const NewConversation(),
                          );
                          onClose();
                        },
                      ),
                      _FlatIconButton(
                        icon: PhosphorIconsLight.x,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
              ),

              Divider(height: 1, thickness: 1, color: scheme.outlineVariant),

              // Conversation list
              Expanded(
                child: state.conversations.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l.noConversations,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
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
                            onTap: () {
                              if (conv.id != state.conversationId) {
                                context.read<AiAgentBloc>().add(
                                  SwitchConversation(conv.id),
                                );
                              }
                              onClose();
                            },
                            onDelete: () {
                              context.read<AiAgentBloc>().add(
                                DeleteConversation(conv.id),
                              );
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
// Flat icon button — hover tint only, no ripple or elevation
// ---------------------------------------------------------------------------

class _FlatIconButton extends StatefulWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  const _FlatIconButton({required this.icon, this.tooltip, this.onPressed});

  @override
  State<_FlatIconButton> createState() => _FlatIconButtonState();
}

class _FlatIconButtonState extends State<_FlatIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget btn = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hovered
                ? scheme.onSurface.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(widget.icon, size: 16, color: scheme.onSurfaceVariant),
        ),
      ),
    );

    if (widget.tooltip != null) {
      btn = CbTooltip(message: widget.tooltip!, child: btn);
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
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.isActive,
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
    final scheme = Theme.of(context).colorScheme;

    // Selection styling mirrors the app's navigation tiles: a rounded
    // secondaryContainer fill, no border or accent bar.
    final foreground = widget.isActive
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    final Color bg;
    if (widget.isActive) {
      bg = scheme.secondaryContainer;
    } else if (_hovered) {
      bg = scheme.onSurface.withValues(alpha: 0.05);
    } else {
      bg = Colors.transparent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
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
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(widget.conversation),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.isActive
                              ? foreground.withValues(alpha: 0.75)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Reserve the slot so titles don't reflow on hover.
                SizedBox(
                  width: 24,
                  child: _hovered
                      ? _DeleteButton(
                          tooltip: l.deleteConversation,
                          onPressed: widget.onDelete,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _subtitle(AiConversationSummary conv) {
    final date = _relativeDate(conv.updatedAt);
    if (conv.initialPath.isEmpty) return date;
    return '${conv.initialPathShort} · $date';
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
  final VoidCallback onPressed;

  const _DeleteButton({required this.tooltip, required this.onPressed});

  @override
  State<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<_DeleteButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CbTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(
              PhosphorIconsLight.trash,
              size: 14,
              color: _hovered ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
