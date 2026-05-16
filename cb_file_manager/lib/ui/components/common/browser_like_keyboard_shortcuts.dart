import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_keyboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BrowserLikeKeyboardShortcuts {
  static bool isTextInputFocused() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return false;
    }
    return focusedContext.widget is EditableText ||
        focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static KeyEventResult handleBasic({
    required bool isDesktop,
    required KeyEvent? event,
    VoidCallback? onEscape,
    VoidCallback? onRefresh,
    VoidCallback? onSelectAll,
    void Function(bool permanent)? onDelete,
    VoidCallback? onCopy,
    VoidCallback? onCut,
    VoidCallback? onPaste,
    VoidCallback? onRename,
  }) {
    if (!isDesktop || event == null || isTextInputFocused()) {
      return KeyEventResult.ignored;
    }

    final bool isKeyPress = event is KeyDownEvent || event is KeyRepeatEvent;
    if (!isKeyPress) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.escape && onEscape != null) {
      onEscape();
      return KeyEventResult.handled;
    }

    if ((key == LogicalKeyboardKey.f5 ||
            (isCtrl && key == LogicalKeyboardKey.keyR)) &&
        onRefresh != null) {
      onRefresh();
      return KeyEventResult.handled;
    }

    if (isCtrl && key == LogicalKeyboardKey.keyA && onSelectAll != null) {
      onSelectAll();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete && onDelete != null) {
      onDelete(isShift);
      return KeyEventResult.handled;
    }

    if (isCtrl && key == LogicalKeyboardKey.keyC && onCopy != null) {
      onCopy();
      return KeyEventResult.handled;
    }

    if (isCtrl && key == LogicalKeyboardKey.keyX && onCut != null) {
      onCut();
      return KeyEventResult.handled;
    }

    if (isCtrl && key == LogicalKeyboardKey.keyV && onPaste != null) {
      onPaste();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.f2 && onRename != null) {
      onRename();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  static KeyEventResult handle({
    required bool isDesktop,
    required TabbedFolderKeyboardController keyboardController,
    required FolderListState folderListState,
    required SelectionState selectionState,
    required String? currentFilter,
    int? gridCrossAxisCount,
    required VoidCallback onBackInTabHistory,
    required void Function(String folderPath) focusFolderPath,
    required void Function(String filePath) focusFilePath,
    required void Function({
      required Set<String> folderPaths,
      required Set<String> filePaths,
      required String lastSelectedPath,
      required bool ctrlSelect,
    }) selectRange,
    required void Function(FileSystemEntity entity) activateEntity,
    required void Function(bool permanent) onDelete,
    VoidCallback? onSelectAll,
    VoidCallback? onCopy,
    VoidCallback? onCut,
    VoidCallback? onPaste,
    VoidCallback? onRename,
    VoidCallback? onRefresh,
    void Function(int index, int crossAxisCount, double itemMainAxisExtent)?
        onScrollToIndex,
    KeyEvent? event,
  }) {
    if (!isDesktop || event == null || isTextInputFocused()) {
      return KeyEventResult.ignored;
    }

    return keyboardController.handleKeyEvent(
      isDesktop: isDesktop,
      folderListState: folderListState,
      selectionState: selectionState,
      currentFilter: currentFilter,
      gridCrossAxisCount: gridCrossAxisCount,
      onBackInTabHistory: onBackInTabHistory,
      focusFolderPath: focusFolderPath,
      focusFilePath: focusFilePath,
      selectRange: selectRange,
      activateEntity: activateEntity,
      onDelete: onDelete,
      onSelectAll: onSelectAll,
      onCopy: onCopy,
      onCut: onCut,
      onPaste: onPaste,
      onRename: onRename,
      onRefresh: onRefresh,
      onScrollToIndex: onScrollToIndex,
      event: event,
    );
  }
}
