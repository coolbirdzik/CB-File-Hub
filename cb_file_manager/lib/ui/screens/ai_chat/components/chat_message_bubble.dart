import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../../models/ai/ai_message.dart';
import '../../../../services/ai/assistant_response_text.dart';
import 'referenced_file_card.dart';

/// A single chat message bubble (user or assistant).
///
/// User messages render as plain text.
/// Assistant messages render as Markdown.
class ChatMessageBubble extends StatefulWidget {
  final AiMessage message;
  final VoidCallback? onRetry;
  final ValueChanged<String>? onEdit;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onEdit,
  });

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  String get _reasoning => widget.message.role == AiMessageRole.assistant
      ? (widget.message.reasoning ??
            extractAssistantReasoning(widget.message.content))
      : '';
  String get _displayContent => widget.message.role == AiMessageRole.assistant
      ? stripAssistantReasoning(widget.message.content)
      : widget.message.content;
  final _editController = TextEditingController();
  final _editFocusNode = FocusNode();
  bool _isEditing = false;
  bool _isHovering = false;
  bool _reasoningExpanded = false;

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChatMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) _reasoningExpanded = false;
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.content != widget.message.content) {
      _isEditing = false;
      _editController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tool cards/results are rendered by the parent, without an empty bubble.
    if (_displayContent.trim().isEmpty &&
        _reasoning.isEmpty &&
        widget.message.error == null &&
        (widget.message.referencedFiles?.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }

    final isUser = widget.message.role == AiMessageRole.user;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = isUser ? colorScheme.onPrimary : colorScheme.onSurface;
    final canEdit =
        isUser && widget.onEdit != null && !widget.message.isLoading;
    final showActions = _isHovering || _isEditing;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isUser
                ? MediaQuery.of(context).size.width * 0.78
                : double.infinity,
          ),
          margin: EdgeInsets.only(left: isUser ? 48 : 0, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _isEditing ? 10 : 15,
                  vertical: _isEditing ? 10 : 11,
                ),
                decoration: BoxDecoration(
                  color: isUser
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isUser ? 18 : 6),
                    topRight: Radius.circular(isUser ? 6 : 18),
                    bottomLeft: const Radius.circular(18),
                    bottomRight: const Radius.circular(18),
                  ),
                  border: isUser
                      ? null
                      : Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
                        ),
                  boxShadow: isUser
                      ? [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.22),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_reasoning.isNotEmpty)
                      _buildReasoning(context, colorScheme),
                    if (_isEditing)
                      _buildInlineEditor(context, colorScheme)
                    else if (widget.message.error != null)
                      _buildError(context, colorScheme)
                    else ...[
                      if (isUser)
                        _buildUserMessage(context, textColor)
                      else if (_displayContent.isNotEmpty)
                        _buildMarkdown(context, textColor, colorScheme),
                      // Streaming cursor
                      if (widget.message.isLoading &&
                          (_displayContent.isNotEmpty || _reasoning.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SizedBox(
                            width: 8,
                            height: 14,
                            child: _StreamingCursor(color: colorScheme.primary),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (!widget.message.isLoading &&
                  widget.message.error == null &&
                  _displayContent.isNotEmpty)
                _MessageActions(
                  canEdit: canEdit,
                  isVisible: showActions,
                  onEdit: _startInlineEdit,
                  onCopy: () => _copyMessage(context),
                ),
              // Referenced file cards shown below the message
              if (isUser &&
                  widget.message.referencedFiles != null &&
                  widget.message.referencedFiles!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4, right: 48),
                  child: ReferencedFileCard(
                    files: widget.message.referencedFiles!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReasoning(BuildContext context, ColorScheme colorScheme) {
    final label = AppLocalizations.of(context)!.aiReasoning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          expanded: _reasoningExpanded,
          child: TextButton(
            key: const ValueKey('chat-reasoning-toggle'),
            onPressed: () =>
                setState(() => _reasoningExpanded = !_reasoningExpanded),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _reasoningExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(label),
              ],
            ),
          ),
        ),
        if (_reasoningExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4, bottom: 12),
            child: SelectableText(
              _reasoning,
              key: const ValueKey('chat-reasoning-content'),
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        if (_displayContent.isNotEmpty) const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildUserMessage(BuildContext context, Color textColor) {
    return SelectableText(
      widget.message.content,
      style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
    );
  }

  Widget _buildInlineEditor(BuildContext context, ColorScheme colorScheme) {
    final l = AppLocalizations.of(context)!;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _editController,
            focusNode: _editFocusNode,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontSize: 14,
              height: 1.35,
            ),
            cursorColor: colorScheme.onPrimary,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colorScheme.onPrimary.withValues(alpha: 0.12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _cancelInlineEdit,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onPrimary,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(l.cancel),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: _submitInlineEdit,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.onPrimary,
                  foregroundColor: colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsLight.paperPlaneRight, size: 14),
                    const SizedBox(width: 6),
                    Text(l.sendMessage),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _startInlineEdit() {
    setState(() {
      _editController.text = widget.message.content;
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
      _isEditing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocusNode.requestFocus();
    });
  }

  void _cancelInlineEdit() {
    setState(() {
      _isEditing = false;
      _editController.clear();
    });
  }

  void _submitInlineEdit() {
    final trimmed = _editController.text.trim();
    if (trimmed.isEmpty) {
      _cancelInlineEdit();
      return;
    }
    widget.onEdit?.call(trimmed);
    _cancelInlineEdit();
  }

  void _copyMessage(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _displayContent));
  }

  Widget _buildMarkdown(
    BuildContext context,
    Color textColor,
    ColorScheme colorScheme,
  ) {
    return MarkdownBody(
      data: _displayContent,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        // Body text
        p: TextStyle(color: textColor, fontSize: 14, height: 1.5),
        // Headings
        h1: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h2: TextStyle(
          color: textColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        h3: TextStyle(
          color: textColor,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        // Bold / italic
        strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        em: TextStyle(color: textColor, fontStyle: FontStyle.italic),
        // Code
        code: TextStyle(
          color: colorScheme.primary,
          backgroundColor: colorScheme.primary.withValues(alpha: 0.08),
          fontSize: 13,
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        codeblockPadding: const EdgeInsets.all(10),
        // Lists
        listBullet: TextStyle(color: textColor, fontSize: 14),
        // Links
        a: TextStyle(
          color: colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        // Block quote
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.4),
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        // Spacing
        pPadding: const EdgeInsets.only(bottom: 4),
        h1Padding: const EdgeInsets.only(bottom: 8, top: 4),
        h2Padding: const EdgeInsets.only(bottom: 6, top: 4),
        h3Padding: const EdgeInsets.only(bottom: 4, top: 2),
      ),
      onTapLink: (text, href, title) {
        if (href != null) {
          Clipboard.setData(ClipboardData(text: href));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Link copied: $href'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }

  Widget _buildError(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              PhosphorIconsLight.warningCircle,
              size: 16,
              color: colorScheme.error,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.message.error!,
                style: TextStyle(color: colorScheme.error, fontSize: 13),
              ),
            ),
          ],
        ),
        if (widget.onRetry != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              onTap: widget.onRetry,
              child: Text(
                'Retry',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageActions extends StatelessWidget {
  final bool canEdit;
  final bool isVisible;
  final VoidCallback onEdit;
  final VoidCallback onCopy;

  const _MessageActions({
    required this.canEdit,
    required this.isVisible,
    required this.onEdit,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return IgnorePointer(
      ignoring: !isVisible,
      child: AnimatedOpacity(
        opacity: isVisible ? 1 : 0,
        duration: const Duration(milliseconds: 90),
        child: Padding(
          padding: const EdgeInsets.only(top: 2, right: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canEdit)
                _UserActionButton(
                  tooltip: l.edit,
                  icon: PhosphorIconsLight.pencilSimple,
                  onPressed: onEdit,
                ),
              _UserActionButton(
                tooltip: l.copy,
                icon: PhosphorIconsLight.copy,
                onPressed: onCopy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserActionButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _UserActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<_UserActionButton> createState() => _UserActionButtonState();
}

class _UserActionButtonState extends State<_UserActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = _isHovered
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.68);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: SizedBox(
              width: 22,
              height: 22,
              child: Icon(widget.icon, size: 15, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// A blinking cursor shown at the end of a streaming message.
class _StreamingCursor extends StatefulWidget {
  final Color color;

  const _StreamingCursor({required this.color});

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 14,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _controller.value),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      },
    );
  }
}
