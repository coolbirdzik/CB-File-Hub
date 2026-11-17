import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:xterm/xterm.dart';

import '../../../config/translation_helper.dart';
import '../../components/common/shared_file_context_menu.dart';

/// Clipboard handling is shared by toolbar buttons, shortcuts and the menu.
class SshTerminalView extends StatefulWidget {
  const SshTerminalView({
    super.key,
    required this.terminal,
    required this.controller,
    required this.focusNode,
    required this.readOnly,
  });

  final Terminal terminal;
  final TerminalController controller;
  final FocusNode focusNode;
  final bool readOnly;

  @override
  State<SshTerminalView> createState() => SshTerminalViewState();
}

class SshTerminalViewState extends State<SshTerminalView> {
  int _inputGeneration = 0;

  @override
  void didUpdateWidget(SshTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readOnly != widget.readOnly ||
        oldWidget.terminal != widget.terminal) {
      _inputGeneration++;
    }
  }

  Future<void> copySelection() async {
    final selection = widget.controller.selection;
    if (selection == null || selection.isCollapsed) return;
    await Clipboard.setData(
      ClipboardData(text: widget.terminal.buffer.getText(selection)),
    );
    if (mounted) widget.focusNode.requestFocus();
  }

  Future<void> pasteText() async {
    if (widget.readOnly) return;
    final generation = _inputGeneration;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || widget.readOnly || generation != _inputGeneration) return;
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    // xterm honors the remote application's bracketed-paste mode.
    widget.terminal.paste(text);
    widget.controller.clearSelection();
    widget.focusNode.requestFocus();
  }

  void _selectAll() {
    final terminal = widget.terminal;
    widget.controller.setSelection(
      terminal.buffer.createAnchor(0, 0),
      terminal.buffer.createAnchor(
        terminal.viewWidth,
        terminal.buffer.height - 1,
      ),
      mode: SelectionMode.line,
    );
    widget.focusNode.requestFocus();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed;
    final meta = keyboard.isMetaPressed;
    final shift = keyboard.isShiftPressed;
    final key = event.logicalKey;
    if (keyboard.isAltPressed) return KeyEventResult.ignored;
    final selection = widget.controller.selection;
    final hasSelection = selection != null && !selection.isCollapsed;
    if ((key == LogicalKeyboardKey.keyC &&
            (meta || (control && (shift || hasSelection)))) ||
        (key == LogicalKeyboardKey.insert && control)) {
      unawaited(copySelection());
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.keyV && (control || meta)) ||
        (key == LogicalKeyboardKey.insert && shift)) {
      unawaited(pasteText());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA && (meta || (control && shift))) {
      _selectAll();
      return KeyEventResult.handled;
    }
    // In particular, plain Ctrl+C without a selection still sends SIGINT.
    return KeyEventResult.ignored;
  }

  Future<void> _showMenu(Offset position) async {
    final tr = context.tr;
    final selection = widget.controller.selection;
    await showContextMenuPopup(
      context: context,
      globalPosition: position,
      sections: [
        ContextMenuSection(
          actions: [
            ContextMenuAction(
              id: 'copy',
              label: tr.copy,
              icon: PhosphorIconsLight.copy,
              isEnabled: selection != null && !selection.isCollapsed,
              onSelected: (_) => copySelection(),
            ),
            ContextMenuAction(
              id: 'paste',
              label: tr.pasteHere,
              icon: PhosphorIconsLight.clipboardText,
              isEnabled: !widget.readOnly,
              onSelected: (_) => pasteText(),
            ),
          ],
        ),
        ContextMenuSection(
          actions: [
            ContextMenuAction(
              id: 'select_all',
              label: tr.selectAll,
              icon: PhosphorIconsLight.checks,
              onSelected: (_) => _selectAll(),
            ),
          ],
        ),
      ],
    );
    if (!mounted) return;
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => TerminalView(
    widget.terminal,
    controller: widget.controller,
    focusNode: widget.focusNode,
    autofocus: true,
    padding: const EdgeInsets.all(12),
    readOnly: widget.readOnly,
    // Keep clipboard shortcuts scoped to this terminal instead of file actions
    // from the containing tab. Shell Ctrl+A remains available as well.
    shortcuts: const {},
    onKeyEvent: _onKeyEvent,
    onSecondaryTapUp: (details, _) => _showMenu(details.globalPosition),
  );
}
