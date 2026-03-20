import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TabbedFolderKeyboardController {
  final FocusNode focusNode =
      FocusNode(debugLabel: 'tabbed-folder-list-keyboard');

  String? focusedPath;

  // Type-ahead search state
  String _searchBuffer = '';
  DateTime _lastTypeTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _typeAheadTimeout = Duration(milliseconds: 1000);

  void dispose() {
    focusNode.dispose();
  }

  void clearFocus() {
    focusedPath = null;
  }

  void syncFromSelection(SelectionState selectionState) {
    final String? lastPath = selectionState.lastSelectedPath;
    if (lastPath != null && lastPath != focusedPath) {
      focusedPath = lastPath;
      return;
    }

    if (lastPath == null &&
        selectionState.selectedFilePaths.isEmpty &&
        selectionState.selectedFolderPaths.isEmpty) {
      focusedPath = null;
    }
  }

  KeyEventResult handleKeyEvent({
    required bool isDesktop,
    required FolderListState folderListState,
    required SelectionState selectionState,
    required String? currentFilter,
    int? gridCrossAxisCount,
    required VoidCallback onBackInTabHistory,
    required void Function(String folderPath) focusFolderPath,
    required void Function(String filePath) focusFilePath,
    required void Function(FileSystemEntity entity) activateEntity,
    required void Function(bool permanent) onDelete,
    VoidCallback? onSelectAll,
    VoidCallback? onCopy,
    VoidCallback? onCut,
    VoidCallback? onPaste,
    VoidCallback? onRename,
    VoidCallback? onRefresh,
    KeyEvent? event,
  }) {
    if (!isDesktop || event == null) return KeyEventResult.ignored;

    final bool isKeyPress = event is KeyDownEvent || event is KeyRepeatEvent;
    if (!isKeyPress) return KeyEventResult.ignored;

    final LogicalKeyboardKey key = event.logicalKey;
    final bool isCtrlPressed = HardwareKeyboard.instance.isControlPressed;

    // Delete key - move to trash or permanent delete
    if (key == LogicalKeyboardKey.delete) {
      // Check shift key state from both event and hardware keyboard for reliability
      final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.shiftLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.shiftRight);

      debugPrint('Delete key pressed - Shift: $isShiftPressed');

      onDelete(isShiftPressed);
      return KeyEventResult.handled;
    }

    // Ctrl+A - Select all
    if (isCtrlPressed &&
        key == LogicalKeyboardKey.keyA &&
        onSelectAll != null) {
      debugPrint('Ctrl+A pressed - Select all');
      onSelectAll();
      return KeyEventResult.handled;
    }

    // Ctrl+C - Copy
    if (isCtrlPressed && key == LogicalKeyboardKey.keyC && onCopy != null) {
      debugPrint('Ctrl+C pressed - Copy');
      onCopy();
      return KeyEventResult.handled;
    }

    // Ctrl+X - Cut
    if (isCtrlPressed && key == LogicalKeyboardKey.keyX && onCut != null) {
      debugPrint('Ctrl+X pressed - Cut');
      onCut();
      return KeyEventResult.handled;
    }

    // Ctrl+V - Paste
    if (isCtrlPressed && key == LogicalKeyboardKey.keyV && onPaste != null) {
      debugPrint('Ctrl+V pressed - Paste');
      onPaste();
      return KeyEventResult.handled;
    }

    // F2 - Rename
    if (key == LogicalKeyboardKey.f2 && onRename != null) {
      debugPrint('F2 pressed - Rename');
      onRename();
      return KeyEventResult.handled;
    }

    // F5 or Ctrl+R - Refresh
    if ((key == LogicalKeyboardKey.f5 ||
            (isCtrlPressed && key == LogicalKeyboardKey.keyR)) &&
        onRefresh != null) {
      debugPrint(
          '${key == LogicalKeyboardKey.f5 ? "F5" : "Ctrl+R"} pressed - Refresh');
      onRefresh();
      return KeyEventResult.handled;
    }

    // Backspace - Navigate back
    if (key == LogicalKeyboardKey.backspace) {
      final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
      if (focusedWidget is EditableText) {
        return KeyEventResult.ignored;
      }

      onBackInTabHistory();
      return KeyEventResult.handled;
    }

    final List<FileSystemEntity> items =
        _getNavigableItems(folderListState, currentFilter);
    if (items.isEmpty) return KeyEventResult.ignored;

    final bool isGridLayout = folderListState.viewMode == ViewMode.grid ||
        folderListState.viewMode == ViewMode.gridPreview;
    final int crossAxisCount = isGridLayout
        ? (gridCrossAxisCount ?? folderListState.gridZoomLevel).clamp(1, 999)
        : 1;

    int currentIndex = -1;
    if (focusedPath != null) {
      currentIndex =
          items.indexWhere((FileSystemEntity item) => item.path == focusedPath);
    }
    if (currentIndex == -1 && selectionState.lastSelectedPath != null) {
      currentIndex = items.indexWhere((FileSystemEntity item) =>
          item.path == selectionState.lastSelectedPath);
    }
    if (currentIndex == -1) {
      currentIndex = 0;
    }

    final bool hasExistingFocus =
        focusedPath != null || selectionState.lastSelectedPath != null;
    int targetIndex;

    if (key == LogicalKeyboardKey.arrowDown) {
      targetIndex = currentIndex + crossAxisCount;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      targetIndex = currentIndex - crossAxisCount;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      targetIndex = currentIndex + 1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      targetIndex = currentIndex - 1;
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!hasExistingFocus) {
        _focusItemAtIndex(
          items: items,
          index: currentIndex,
          focusFolderPath: focusFolderPath,
          focusFilePath: focusFilePath,
        );
        return KeyEventResult.handled;
      }
      activateEntity(items[currentIndex]);
      return KeyEventResult.handled;
    } else {
      // Type-ahead search support
      if (event.character != null &&
          event.character!.isNotEmpty &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isAltPressed &&
          !HardwareKeyboard.instance.isMetaPressed) {
        return _performTypeAheadSearch(
          char: event.character!,
          folderListState: folderListState,
          currentFilter: currentFilter,
          focusFolderPath: focusFolderPath,
          focusFilePath: focusFilePath,
        );
      }
      return KeyEventResult.ignored;
    }

    final int newIndex = targetIndex.clamp(0, items.length - 1).toInt();
    _focusItemAtIndex(
      items: items,
      index: newIndex,
      focusFolderPath: focusFolderPath,
      focusFilePath: focusFilePath,
    );
    return KeyEventResult.handled;
  }

  List<FileSystemEntity> _getNavigableItems(
      FolderListState state, String? currentFilter) {
    if (state.currentSearchTag != null || state.currentSearchQuery != null) {
      return List<FileSystemEntity>.from(state.searchResults);
    }

    if (currentFilter != null && currentFilter.isNotEmpty) {
      return List<FileSystemEntity>.from(state.filteredFiles);
    }

    return [
      ...state.folders.whereType<FileSystemEntity>(),
      ...state.files.whereType<FileSystemEntity>(),
    ];
  }

  void _focusItemAtIndex({
    required List<FileSystemEntity> items,
    required int index,
    required void Function(String folderPath) focusFolderPath,
    required void Function(String filePath) focusFilePath,
  }) {
    if (index < 0 || index >= items.length) return;

    final FileSystemEntity target = items[index];
    focusedPath = target.path;

    if (target is Directory) {
      focusFolderPath(target.path);
    } else if (target is File) {
      focusFilePath(target.path);
    }
  }

  KeyEventResult _performTypeAheadSearch({
    required String char,
    required FolderListState folderListState,
    required String? currentFilter,
    required void Function(String folderPath) focusFolderPath,
    required void Function(String filePath) focusFilePath,
  }) {
    final now = DateTime.now();
    final bool isTimeout = now.difference(_lastTypeTime) > _typeAheadTimeout;
    _lastTypeTime = now;

    final items = _getNavigableItems(folderListState, currentFilter);
    if (items.isEmpty) return KeyEventResult.ignored;

    // Calculate current index
    int currentIndex = -1;
    if (focusedPath != null) {
      currentIndex = items.indexWhere((item) => item.path == focusedPath);
    }
    // If no focus, start from beginning (essentially index -1)

    if (isTimeout) {
      _searchBuffer = char;
    } else {
      if (_searchBuffer.length == 1 && _searchBuffer == char) {
        // Repeated single char -> Keep buffer as is to trigger cycling logic
      } else {
        _searchBuffer += char;
      }
    }

    final searchLower = _searchBuffer.toLowerCase();
    int matchIndex = -1;

    if (_searchBuffer.length == 1 && _searchBuffer == char && !isTimeout) {
      // Cycling mode: find next match after currentIndex
      for (int i = 1; i <= items.length; i++) {
        // Start searching from next item, wrap around
        int idx = (currentIndex + i) % items.length;
        final name = _getItemName(items[idx]).toLowerCase();
        if (name.startsWith(searchLower)) {
          matchIndex = idx;
          break;
        }
      }
    } else {
      // Standard prefix match
      matchIndex = items.indexWhere((item) {
        final name = _getItemName(item).toLowerCase();
        return name.startsWith(searchLower);
      });
    }

    if (matchIndex != -1) {
      _focusItemAtIndex(
        items: items,
        index: matchIndex,
        focusFolderPath: focusFolderPath,
        focusFilePath: focusFilePath,
      );
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _getItemName(FileSystemEntity item) {
    // Robust name extraction handling mixed separators
    return item.path.split(RegExp(r'[/\\]')).last;
  }
}
