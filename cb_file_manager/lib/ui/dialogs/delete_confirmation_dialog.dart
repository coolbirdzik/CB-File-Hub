import 'dart:io';

import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// A delete confirmation dialog with keyboard support and visual focus indication
/// - Enter key confirms deletion (focused on delete button by default)
/// - Esc key cancels
/// - Tab key navigates between buttons
/// - On desktop, shows as a window-style dialog
class DeleteConfirmationDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;

  /// Optional list of paths to preview (up to 4 shown as thumbnails/icons).
  final List<String> previewPaths;

  const DeleteConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmText,
    required this.cancelText,
    this.previewPaths = const [],
  });

  @override
  State<DeleteConfirmationDialog> createState() =>
      _DeleteConfirmationDialogState();
}

class _DeleteConfirmationDialogState extends State<DeleteConfirmationDialog> {
  final FocusNode _dialogFocusNode = FocusNode();
  final FocusNode _confirmButtonFocusNode = FocusNode();
  final FocusNode _cancelButtonFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus the confirm (delete) button after dialog is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confirmButtonFocusNode.requestFocus();
    });

    // Listen to focus changes to rebuild UI
    _confirmButtonFocusNode.addListener(_onFocusChange);
    _cancelButtonFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // Rebuild when focus changes to update visual indicators
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _confirmButtonFocusNode.removeListener(_onFocusChange);
    _cancelButtonFocusNode.removeListener(_onFocusChange);
    _dialogFocusNode.dispose();
    _confirmButtonFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Enter key to confirm (when confirm button is focused)
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (_confirmButtonFocusNode.hasFocus) {
          Navigator.of(context).pop(true);
          return KeyEventResult.handled;
        } else if (_cancelButtonFocusNode.hasFocus) {
          Navigator.of(context).pop(false);
          return KeyEventResult.handled;
        }
      }
      // Escape key to cancel
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop(false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final previews = widget.previewPaths.take(4).toList();

    return Focus(
      focusNode: _dialogFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: mediaQuery.size.height * 0.72,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        PhosphorIconsLight.warningCircle,
                        color: Colors.orange.shade700,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // File preview strip
                if (previews.isNotEmpty) ...[
                  _DeletePreviewStrip(paths: previews),
                  const SizedBox(height: 12),
                ],
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      widget.message,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Focus(
                      focusNode: _cancelButtonFocusNode,
                      child: Builder(
                        builder: (context) {
                          final isFocused = _cancelButtonFocusNode.hasFocus;
                          return TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(
                              backgroundColor: isFocused
                                  ? colorScheme.primary.withValues(alpha: 0.1)
                                  : null,
                              side: isFocused
                                  ? BorderSide(
                                      color: colorScheme.primary,
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: Text(widget.cancelText),
                          );
                        },
                      ),
                    ),
                    Focus(
                      focusNode: _confirmButtonFocusNode,
                      child: Builder(
                        builder: (context) {
                          final isFocused = _confirmButtonFocusNode.hasFocus;
                          return TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              backgroundColor: isFocused
                                  ? Colors.red.withValues(alpha: 0.1)
                                  : null,
                              side: isFocused
                                  ? const BorderSide(
                                      color: Colors.red,
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: Text(
                              widget.confirmText,
                              style: TextStyle(
                                fontWeight: isFocused
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeletePreviewStrip extends StatelessWidget {
  final List<String> paths;

  const _DeletePreviewStrip({required this.paths});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = paths.length;
    // Single item: larger centered preview
    if (count == 1) {
      return Center(child: _PreviewTile(path: paths.first, size: 96));
    }
    // Multiple: row of tiles
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (final path in paths)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _PreviewTile(path: path, size: 64),
          ),
        if (paths.length == 4)
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '+more',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _PreviewTile extends StatefulWidget {
  final String path;
  final double size;

  const _PreviewTile({required this.path, required this.size});

  @override
  State<_PreviewTile> createState() => _PreviewTileState();
}

class _PreviewTileState extends State<_PreviewTile> {
  bool? _isDir;

  @override
  void initState() {
    super.initState();
    FileSystemEntity.type(widget.path, followLinks: false).then((type) {
      if (mounted) {
        setState(() {
          _isDir = type == FileSystemEntityType.directory;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext = p.extension(widget.path).toLowerCase();
    final isDir = _isDir ?? false;
    final category = FileTypeRegistry.getCategory(ext);
    final isImage = category == FileCategory.image;
    final isVideo = category == FileCategory.video;
    final fallbackIcon = isDir
        ? PhosphorIconsLight.folder
        : FileTypeRegistry.getIcon(ext);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: widget.size,
        height: widget.size,
        color: theme.colorScheme.surfaceContainerHigh,
        child: isDir
            ? Icon(
                PhosphorIconsLight.folder,
                size: widget.size * 0.55,
                color: theme.colorScheme.primary,
              )
            : ThumbnailLoader(
                key: ValueKey('del-preview-${widget.path}'),
                filePath: widget.path,
                isVideo: isVideo,
                isImage: isImage,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                isPriority: true,
                borderRadius: BorderRadius.circular(10),
                showLoadingIndicator: false,
                fallbackBuilder: () => Icon(
                  fallbackIcon,
                  size: widget.size * 0.55,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}
