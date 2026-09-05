import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';

/// Callback when sending a message. [text] is the user input, [referencedFiles]
/// are the paths of files dropped into the chat.
typedef OnSendMessage =
    void Function(String text, List<String> referencedFiles);

/// Input bar for the AI chat interface with send button, suggestion chips,
/// workspace indicator, and OS-level file drag-and-drop support.
class ChatInputBar extends StatefulWidget {
  final OnSendMessage onSend;
  final VoidCallback? onStop;
  final bool isLoading;

  /// Optional widget shown below the suggestion chips, before the text field.
  /// Used to display the current AI workspace context (folder / scope).
  final Widget? workspaceIndicator;

  /// Optional model picker rendered in the composer footer, left of the send
  /// button. Lives here rather than in the header so the model choice sits
  /// next to the message being composed.
  final Widget? modelSelector;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onStop,
    this.isLoading = false,
    this.workspaceIndicator,
    this.modelSelector,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final List<String> _mentionedFiles = [];
  bool _isDragging = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_isFocused != _focusNode.hasFocus) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty && _mentionedFiles.isEmpty) return;
    if (widget.isLoading) return;

    // Pass file paths separately so the agent can read text files directly
    final files = List<String>.from(_mentionedFiles);
    _mentionedFiles.clear();

    widget.onSend(text, files);
    _controller.clear();
    setState(() {});
    _focusNode.requestFocus();
  }

  void _removeMentionedFile(String path) {
    setState(() => _mentionedFiles.remove(path));
  }

  String _shortName(String path) =>
      path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).last;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final canSend =
        _controller.text.trim().isNotEmpty || _mentionedFiles.isNotEmpty;

    // Focus reads through a quieter surface shift; dragging keeps the accent
    // because it is an active drop target, not a routine text-field focus.
    final Color composerBorder = _isDragging
        ? theme.colorScheme.primary.withValues(alpha: 0.7)
        : _isFocused
        ? theme.colorScheme.outline.withValues(alpha: 0.55)
        : (isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.10));

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() {
          _isDragging = false;
          for (final f in details.files) {
            if (!_mentionedFiles.contains(f.path)) {
              _mentionedFiles.add(f.path);
            }
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Center(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Suggestion chips
                if (_controller.text.isEmpty && _mentionedFiles.isEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        _buildSuggestionChip(l.suggestRecentPhotos),
                        const SizedBox(width: 8),
                        _buildSuggestionChip(l.suggestLargeVideos),
                        const SizedBox(width: 8),
                        _buildSuggestionChip(l.suggestTaggedFiles),
                      ],
                    ),
                  ),

                // Composer card
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(
                            alpha: _isFocused ? 0.08 : 0.05,
                          )
                        : Color.alphaBlend(
                            Colors.black.withValues(
                              alpha: _isFocused ? 0.035 : 0,
                            ),
                            Colors.white.withValues(alpha: 0.72),
                          ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: composerBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.28 : 0.07,
                        ),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Workspace indicator sits inside the card, at the top
                      if (widget.workspaceIndicator != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(17),
                          ),
                          child: widget.workspaceIndicator!,
                        ),

                      // Drag-enter hint
                      if (_isDragging)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                PhosphorIconsLight.filePlus,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Drop to mention',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Mentioned file chips
                      if (_mentionedFiles.isNotEmpty)
                        _buildMentionedFilesRow(theme, isDark),

                      // Text field spans the full card width
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          decoration: InputDecoration(
                            hintText: _mentionedFiles.isEmpty
                                ? l.askAiToFindFiles
                                : '${l.askAiToFindFiles} (${_mentionedFiles.length} file${_mentionedFiles.length > 1 ? 's' : ''} attached)',
                            hintStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            // Left inset matches the model pill's text below
                            // (footer 8 + pill's own 8); right inset matches
                            // the send button's right margin.
                            contentPadding: const EdgeInsets.fromLTRB(
                              16,
                              12,
                              16,
                              6,
                            ),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 14, height: 1.4),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _handleSend(),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),

                      // Footer: model selector on the left, send on the right
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 16, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          // spaceBetween rather than a Spacer: a Spacer would
                          // split the free space with the Flexible model pill
                          // (both default to flex 1), leaving dead space that
                          // pushes the button away from the right edge.
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child:
                                  widget.modelSelector ??
                                  const SizedBox.shrink(),
                            ),
                            _SendButton(
                              isLoading: widget.isLoading,
                              enabled: canSend,
                              onPressed: widget.isLoading
                                  ? widget.onStop
                                  : _handleSend,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMentionedFilesRow(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: _mentionedFiles
            .map((path) => _buildFileChip(path, theme, isDark))
            .toList(),
      ),
    );
  }

  Widget _buildFileChip(String path, ThemeData theme, bool isDark) {
    final name = _shortName(path);
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final icon = _iconForExt(ext);

    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.09)
            : Colors.black.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: 7,
              right: 4,
              top: 4,
              bottom: 4,
            ),
            child: Icon(icon, size: 12, color: theme.colorScheme.primary),
          ),
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.85)
                    : Colors.black.withValues(alpha: 0.75),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => _removeMentionedFile(path),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
              child: Icon(
                PhosphorIconsLight.x,
                size: 10,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForExt(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return PhosphorIconsLight.image;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'wmv':
        return PhosphorIconsLight.filmStrip;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'm4a':
        return PhosphorIconsLight.musicNote;
      case 'pdf':
        return PhosphorIconsLight.filePdf;
      case 'txt':
      case 'md':
      case 'log':
        return PhosphorIconsLight.fileText;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
        return PhosphorIconsLight.fileZip;
      case 'dart':
      case 'js':
      case 'ts':
      case 'py':
      case 'java':
      case 'kt':
      case 'cpp':
      case 'c':
        return PhosphorIconsLight.fileCode;
      default:
        return PhosphorIconsLight.file;
    }
  }

  Widget _buildSuggestionChip(String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => widget.onSend(label, const []),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsLight.sparkle,
                size: 12,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular send / stop button shown inside the composer.
class _SendButton extends StatefulWidget {
  final bool isLoading;
  final bool enabled;
  final VoidCallback? onPressed;

  const _SendButton({
    required this.isLoading,
    required this.enabled,
    this.onPressed,
  });

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = widget.isLoading || widget.enabled;

    final Color bg;
    final Color fg;
    if (widget.isLoading) {
      bg = scheme.error.withValues(alpha: _hovered ? 1.0 : 0.9);
      fg = scheme.onError;
    } else if (widget.enabled) {
      bg = _hovered ? scheme.primary : scheme.primary.withValues(alpha: 0.9);
      fg = scheme.onPrimary;
    } else {
      bg = scheme.onSurface.withValues(alpha: 0.06);
      fg = scheme.onSurfaceVariant.withValues(alpha: 0.55);
    }

    return Tooltip(
      message: widget.isLoading ? 'Stop generation' : '',
      child: MouseRegion(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: active ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(
              widget.isLoading
                  ? PhosphorIconsFill.square
                  : PhosphorIconsFill.paperPlaneRight,
              size: 16,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
