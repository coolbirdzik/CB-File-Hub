import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';

/// Callback when sending a message. [text] is the user input, [referencedFiles]
/// are the paths of files dropped into the chat.
typedef OnSendMessage = void Function(String text, List<String> referencedFiles);

/// Input bar for the AI chat interface with send button, suggestion chips,
/// workspace indicator, and OS-level file drag-and-drop support.
class ChatInputBar extends StatefulWidget {
  final OnSendMessage onSend;
  final bool isLoading;

  /// Optional widget shown below the suggestion chips, before the text field.
  /// Used to display the current AI workspace context (folder / scope).
  final Widget? workspaceIndicator;

  const ChatInputBar({
    Key? key,
    required this.onSend,
    this.isLoading = false,
    this.workspaceIndicator,
  }) : super(key: key);

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final List<String> _mentionedFiles = [];
  bool _isDragging = false;

  @override
  void dispose() {
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          border: _isDragging
              ? Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                  width: 1.5,
                )
              : const Border(),
          borderRadius: BorderRadius.circular(8),
          color: _isDragging
              ? theme.colorScheme.primary.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Suggestion chips
            if (_controller.text.isEmpty && _mentionedFiles.isEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

            // Workspace indicator (below suggestion chips)
            if (widget.workspaceIndicator != null) widget.workspaceIndicator!,

            // Drag-enter hint
            if (_isDragging)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

            // Mentioned file chips
            if (_mentionedFiles.isNotEmpty)
              _buildMentionedFilesRow(theme, isDark),

            // Input field row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: _mentionedFiles.isEmpty
                            ? l.askAiToFindFiles
                            : '${l.askAiToFindFiles} (${_mentionedFiles.length} file${_mentionedFiles.length > 1 ? 's' : ''} attached)',
                        hintStyle: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 14),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSend(),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: widget.isLoading ? null : _handleSend,
                    icon: widget.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            PhosphorIconsLight.paperPlaneRight,
                            color: (_controller.text.trim().isNotEmpty ||
                                    _mentionedFiles.isNotEmpty)
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                    style: IconButton.styleFrom(
                      backgroundColor: (_controller.text.trim().isNotEmpty ||
                              _mentionedFiles.isNotEmpty)
                          ? theme.colorScheme.primary.withValues(alpha: 0.1)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMentionedFilesRow(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
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
            padding:
                const EdgeInsets.only(left: 7, right: 4, top: 4, bottom: 4),
            child: Icon(
              icon,
              size: 12,
              color: theme.colorScheme.primary,
            ),
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
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        widget.onSend(label, const []);
      },
      visualDensity: VisualDensity.compact,
    );
  }
}
