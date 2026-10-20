import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_keyboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/core/desktop_shortcuts.dart';
import 'file_keyboard_shortcuts.dart';

class BrowserLikeKeyboardShortcuts {
  static KeyEventResult handleSearch({
    required bool isDesktop,
    required KeyEvent? event,
    VoidCallback? onSearch,
  }) {
    return FileKeyboardShortcuts.handleSearch(
      isDesktop: isDesktop,
      event: event,
      onSearch: onSearch,
    );
  }

  static bool isTextInputFocused() => DesktopShortcuts.isTextInputFocused;

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
    VoidCallback? onSearch,
    VoidCallback? onBack,
    VoidCallback? onForward,
  }) => FileKeyboardShortcuts.handle(
    isDesktop: isDesktop,
    event: event,
    onEscape: onEscape,
    onRefresh: onRefresh,
    onSelectAll: onSelectAll,
    onDelete: onDelete,
    onCopy: onCopy,
    onCut: onCut,
    onPaste: onPaste,
    onRename: onRename,
    onSearch: onSearch,
    onBack: onBack,
    onForward: onForward,
  );

  static KeyEventResult handle({
    required bool isDesktop,
    required TabbedFolderKeyboardController keyboardController,
    required FolderListState folderListState,
    required SelectionState selectionState,
    required String? currentFilter,
    int? gridCrossAxisCount,
    required VoidCallback onBackInTabHistory,
    VoidCallback? onForwardInTabHistory,
    VoidCallback? onNavigateToParent,
    VoidCallback? onCreateFolder,
    required void Function(String folderPath) focusFolderPath,
    required void Function(String filePath) focusFilePath,
    required void Function({
      required Set<String> folderPaths,
      required Set<String> filePaths,
      required String lastSelectedPath,
      required bool ctrlSelect,
    })
    selectRange,
    required void Function(FileSystemEntity entity) activateEntity,
    void Function(FileSystemEntity entity)? activateEntityInNewWindow,
    required void Function(bool permanent) onDelete,
    VoidCallback? onSelectAll,
    VoidCallback? onCopy,
    VoidCallback? onCut,
    VoidCallback? onPaste,
    VoidCallback? onRename,
    VoidCallback? onRefresh,
    VoidCallback? onSearch,
    void Function(int index, int crossAxisCount, double itemMainAxisExtent)?
    onScrollToIndex,
    KeyEvent? event,
  }) {
    final searchResult = handleSearch(
      isDesktop: isDesktop,
      event: event,
      onSearch: onSearch,
    );
    if (searchResult != KeyEventResult.ignored) return searchResult;
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
      onForwardInTabHistory: onForwardInTabHistory,
      onNavigateToParent: onNavigateToParent,
      onCreateFolder: onCreateFolder,
      focusFolderPath: focusFolderPath,
      focusFilePath: focusFilePath,
      selectRange: selectRange,
      activateEntity: activateEntity,
      activateEntityInNewWindow: activateEntityInNewWindow,
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
