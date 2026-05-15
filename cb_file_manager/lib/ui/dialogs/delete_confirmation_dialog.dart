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
                                      color: colorScheme.primary, width: 2)
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
                                  ? const BorderSide(color: Colors.red, width: 2)
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
