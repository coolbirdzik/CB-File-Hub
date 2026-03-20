import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';

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

  const DeleteConfirmationDialog({
    Key? key,
    required this.title,
    required this.message,
    required this.confirmText,
    required this.cancelText,
  }) : super(key: key);

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

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

    // On desktop, use window-style dialog
    if (DeleteConfirmationDialog._isDesktop) {
      return Focus(
        focusNode: _dialogFocusNode,
        onKeyEvent: _handleKeyEvent,
        child: Dialog(
          alignment: Alignment.center,
          child: _DesktopConfirmationWindow(
            title: widget.title,
            message: widget.message,
            confirmText: widget.confirmText,
            cancelText: widget.cancelText,
            confirmButtonFocusNode: _confirmButtonFocusNode,
            cancelButtonFocusNode: _cancelButtonFocusNode,
            onConfirm: () => Navigator.of(context).pop(true),
            onCancel: () => Navigator.of(context).pop(false),
          ),
        ),
      );
    }

    // On mobile, use standard AlertDialog
    return Focus(
      focusNode: _dialogFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: AlertDialog(
        title: Text(widget.title),
        content: Text(widget.message),
        actions: [
          // Cancel button
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
                        ? BorderSide(color: colorScheme.primary, width: 2)
                        : null,
                  ),
                  child: Text(widget.cancelText),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Confirm (Delete) button - auto-focused
          Focus(
            focusNode: _confirmButtonFocusNode,
            child: Builder(
              builder: (context) {
                final isFocused = _confirmButtonFocusNode.hasFocus;
                return TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    backgroundColor:
                        isFocused ? Colors.red.withValues(alpha: 0.1) : null,
                    side: isFocused
                        ? const BorderSide(color: Colors.red, width: 2)
                        : null,
                  ),
                  child: Text(
                    widget.confirmText,
                    style: TextStyle(
                      fontWeight:
                          isFocused ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop-style window for delete confirmation
class _DesktopConfirmationWindow extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final FocusNode confirmButtonFocusNode;
  final FocusNode cancelButtonFocusNode;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _DesktopConfirmationWindow({
    required this.title,
    required this.message,
    required this.confirmText,
    required this.cancelText,
    required this.confirmButtonFocusNode,
    required this.cancelButtonFocusNode,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Material(
      elevation: 0,
      borderRadius: BorderRadius.circular(16.0),
      child: Container(
        width: 450,
        constraints: const BoxConstraints(
          maxWidth: 500,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar
            _WindowTitleBar(
              title: title,
              onClose: onCancel,
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Warning icon and message
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        PhosphorIconsLight.warning,
                        size: 32,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          message,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Cancel button
                      Focus(
                        focusNode: cancelButtonFocusNode,
                        child: Builder(
                          builder: (context) {
                            final isFocused = cancelButtonFocusNode.hasFocus;
                            return TextButton(
                              onPressed: onCancel,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                backgroundColor: isFocused
                                    ? colorScheme.primary.withValues(alpha: 0.1)
                                    : null,
                                side: isFocused
                                    ? BorderSide(
                                        color: colorScheme.primary, width: 2)
                                    : BorderSide(
                                        color: colorScheme.outline
                                            .withValues(alpha: 0.3),
                                        width: 1),
                              ),
                              child: Text(
                                cancelText,
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
                      const SizedBox(width: 12),
                      // Confirm (Delete) button
                      Focus(
                        focusNode: confirmButtonFocusNode,
                        child: Builder(
                          builder: (context) {
                            final isFocused = confirmButtonFocusNode.hasFocus;
                            return ElevatedButton(
                              onPressed: onConfirm,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                side: isFocused
                                    ? const BorderSide(
                                        color: Colors.red, width: 2)
                                    : null,
                              ),
                              child: Text(
                                confirmText,
                                style: TextStyle(
                                  fontWeight: isFocused
                                      ? FontWeight.bold
                                      : FontWeight.w600,
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
          ],
        ),
      ),
    );
  }
}

class _WindowTitleBar extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _WindowTitleBar({
    required this.title,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Close button
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(16.0),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: Icon(
                PhosphorIconsLight.x,
                size: 16,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
