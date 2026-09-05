import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/view_mode_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TabbedFolderKeyboardController {
  final FocusNode focusNode = FocusNode(
    debugLabel: 'tabbed-folder-list-keyboard',
  );

  /// Scroll controller attached to the active list/grid view.
  /// The screen creates this and passes it to [FileListViewBuilder].
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  String? focusedPath;
  double itemMainAxisExtent = 40.0;
  double _navigationItemExtent = 48.0;
  final Map<String, ValueNotifier<bool?>> _immediateSelectionNotifiers =
      <String, ValueNotifier<bool?>>{};
  Set<String>? _immediateSelectionPaths;
  final Set<String> _immediateSelectionTouchedPaths = <String>{};
  int _immediateSelectionGeneration = 0;

  String? _keyboardRangeAnchorPath;

  // Type-ahead search state
  String _searchBuffer = '';
  DateTime _lastTypeTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _typeAheadTimeout = Duration(milliseconds: 1000);

  void dispose() {
    _immediateSelectionGeneration++;
    focusNode.dispose();
    scrollController.dispose();
    for (final notifier in _immediateSelectionNotifiers.values) {
      notifier.dispose();
    }
    _immediateSelectionNotifiers.clear();
  }

  ValueListenable<bool?> immediateSelectionForPath(String path) {
    final immediatePaths = _immediateSelectionPaths;
    if (immediatePaths != null) {
      _immediateSelectionTouchedPaths.add(path);
    }
    return _immediateSelectionNotifiers.putIfAbsent(
      path,
      () => ValueNotifier<bool?>(immediatePaths?.contains(path)),
    );
  }

  void showImmediateSelection(
    Set<String> paths, {
    required Iterable<String> currentSelectedPaths,
  }) {
    _immediateSelectionGeneration++;
    final affectedPaths = <String>{
      ..._immediateSelectionTouchedPaths,
      ...currentSelectedPaths,
      ...paths,
    };
    _immediateSelectionPaths = Set<String>.unmodifiable(paths);
    _immediateSelectionTouchedPaths
      ..clear()
      ..addAll(affectedPaths);

    for (final path in affectedPaths) {
      final notifier = _immediateSelectionNotifiers[path];
      if (notifier != null) {
        notifier.value = paths.contains(path);
      }
    }
  }

  void clearImmediateSelection() {
    if (_immediateSelectionPaths == null) return;
    _immediateSelectionGeneration++;
    _immediateSelectionPaths = null;
    for (final path in _immediateSelectionTouchedPaths) {
      final notifier = _immediateSelectionNotifiers[path];
      if (notifier != null) notifier.value = null;
    }
    _immediateSelectionTouchedPaths.clear();
  }

  void _settleImmediateSelection(SelectionState selectionState) {
    final immediatePaths = _immediateSelectionPaths;
    if (immediatePaths == null ||
        !setEquals(immediatePaths, selectionState.allSelectedPaths.toSet())) {
      return;
    }

    final generation = ++_immediateSelectionGeneration;
    scheduleMicrotask(() {
      if (generation != _immediateSelectionGeneration) return;
      clearImmediateSelection();
    });
  }

  GlobalKey itemKeyForPath(String path) {
    return _itemKeys.putIfAbsent(
      path,
      () => GlobalKey(debugLabel: 'file-browser-item-$path'),
    );
  }

  void pruneItemKeys(Iterable<String> visiblePaths) {
    final visible = visiblePaths.toSet();
    _itemKeys.removeWhere((path, _) => !visible.contains(path));
    _immediateSelectionNotifiers.removeWhere(
      (path, _) => !visible.contains(path),
    );
    _immediateSelectionTouchedPaths.removeWhere(
      (path) => !visible.contains(path),
    );
  }

  bool hasRenderedItem(String path) {
    return _itemKeys[path]?.currentContext != null;
  }

  void ensurePathVisible(
    String path, {
    required int index,
    required int crossAxisCount,
    required double itemMainAxisExtent,
    bool forward = true,
  }) {
    _ensurePathVisible(
      path,
      forward: forward,
      index: index,
      crossAxisCount: crossAxisCount,
      itemHeight: itemMainAxisExtent,
    );
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      _ensurePathVisible(
        path,
        forward: forward,
        index: index,
        crossAxisCount: crossAxisCount,
        itemHeight: itemMainAxisExtent,
      );
    });
  }

  void _ensurePathVisible(
    String path, {
    required bool forward,
    int? index,
    int? crossAxisCount,
    double? itemHeight,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[path];
      final context = key?.currentContext;

      if (context == null) {
        // Fallback: if item is not rendered yet, we might need a manual jump
        // to bring it into the "cache area" so it gets built.
        if (index != null &&
            crossAxisCount != null &&
            itemHeight != null &&
            scrollController.hasClients) {
          final pos = scrollController.position;
          final int rowIndex = (index / crossAxisCount).floor();
          final double itemStart = rowIndex * itemHeight;
          final double itemEnd = itemStart + itemHeight;
          final double viewStart = pos.pixels;
          final double viewEnd = viewStart + pos.viewportDimension;

          if (itemEnd > viewEnd) {
            scrollController.jumpTo(
              (itemEnd - pos.viewportDimension).clamp(
                pos.minScrollExtent,
                pos.maxScrollExtent,
              ),
            );
          } else if (itemStart < viewStart) {
            scrollController.jumpTo(
              itemStart.clamp(pos.minScrollExtent, pos.maxScrollExtent),
            );
          }
        }
        return;
      }

      // Check if item is already visible to avoid unnecessary jittery scrolls
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      final ScrollableState scrollable = Scrollable.of(context);
      if (box == null) return;

      final viewport = scrollable.context.findRenderObject() as RenderBox?;
      if (viewport == null) return;

      final horizontal = scrollable.position.axis == Axis.horizontal;
      final offset = box.localToGlobal(Offset.zero, ancestor: viewport);
      final itemTop = horizontal ? offset.dx : offset.dy;
      final itemBottom =
          itemTop + (horizontal ? box.size.width : box.size.height);
      final viewportHeight = horizontal
          ? viewport.size.width
          : viewport.size.height;

      // If item is fully within [0, viewportHeight], no scroll needed
      if (itemTop >= 0 && itemBottom <= viewportHeight) {
        return;
      }

      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        alignment: forward ? 1.0 : 0.0,
        alignmentPolicy: forward
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
    // Type-ahead/highlight requests can arrive without a widget rebuild.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void clearFocus() {
    focusedPath = null;
    _keyboardRangeAnchorPath = null;
    clearImmediateSelection();
  }

  void syncFromSelection(SelectionState selectionState) {
    _settleImmediateSelection(selectionState);
    final String? lastPath = selectionState.lastSelectedPath;
    if (lastPath != null && lastPath != focusedPath) {
      focusedPath = lastPath;
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
    required void Function({
      required Set<String> folderPaths,
      required Set<String> filePaths,
      required String lastSelectedPath,
      required bool ctrlSelect,
    })
    selectRange,
    required void Function(FileSystemEntity entity) activateEntity,

    /// Shift+Enter: open the focused entity in a brand new window.
    void Function(FileSystemEntity entity)? activateEntityInNewWindow,
    required void Function(bool permanent) onDelete,
    VoidCallback? onSelectAll,
    VoidCallback? onCopy,
    VoidCallback? onCut,
    VoidCallback? onPaste,
    VoidCallback? onRename,
    VoidCallback? onRefresh,

    /// Called after focus moves to a new index so the list can scroll it into view.
    /// [index] is the flat item index, [crossAxisCount] is the grid column count
    /// (1 for list/details), [itemMainAxisExtent] is the item height (list/details)
    /// or cell height (grid).
    void Function(int index, int crossAxisCount, double itemMainAxisExtent)?
    onScrollToIndex,
    KeyEvent? event,
  }) {
    if (!isDesktop || event == null) return KeyEventResult.ignored;
    _navigationItemExtent = folderListState.viewMode == ViewMode.list
        ? itemMainAxisExtent
        : 48.0;

    final bool isKeyPress = event is KeyDownEvent || event is KeyRepeatEvent;
    if (!isKeyPress) return KeyEventResult.ignored;

    final LogicalKeyboardKey key = event.logicalKey;
    final bool isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
    final bool isShiftPressed =
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );

    // Delete key - move to trash or permanent delete
    if (key == LogicalKeyboardKey.delete) {
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
        '${key == LogicalKeyboardKey.f5 ? "F5" : "Ctrl+R"} pressed - Refresh',
      );
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

    final List<FileSystemEntity> items = _getNavigableItems(
      folderListState,
      currentFilter,
    );
    if (items.isEmpty) return KeyEventResult.ignored;

    final bool isGridLayout =
        ViewModeUtils.isGridLike(folderListState.viewMode) ||
        folderListState.viewMode == ViewMode.tiles ||
        folderListState.viewMode == ViewMode.list;
    final int crossAxisCount = isGridLayout
        ? (gridCrossAxisCount ??
                  (folderListState.viewMode == ViewMode.list
                      ? 1
                      : folderListState.gridZoomLevel))
              .clamp(1, 999)
        : 1;

    int currentIndex = -1;
    if (focusedPath != null) {
      currentIndex = items.indexWhere(
        (FileSystemEntity item) => item.path == focusedPath,
      );
    }
    if (currentIndex == -1 && selectionState.lastSelectedPath != null) {
      currentIndex = items.indexWhere(
        (FileSystemEntity item) => item.path == selectionState.lastSelectedPath,
      );
    }
    if (currentIndex == -1) {
      currentIndex = 0;
    }

    final bool hasExistingFocus =
        focusedPath != null || selectionState.lastSelectedPath != null;
    int targetIndex;

    final isColumnList = folderListState.viewMode == ViewMode.list;
    final verticalStep = isColumnList ? 1 : crossAxisCount;
    final horizontalStep = isColumnList ? crossAxisCount : 1;
    if (key == LogicalKeyboardKey.arrowDown) {
      targetIndex = currentIndex + verticalStep;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      targetIndex = currentIndex - verticalStep;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      targetIndex = currentIndex + horizontalStep;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      targetIndex = currentIndex - horizontalStep;
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!hasExistingFocus) {
        _focusItemAtIndex(
          items: items,
          index: currentIndex,
          focusFolderPath: focusFolderPath,
          focusFilePath: focusFilePath,
          onScrollToIndex: onScrollToIndex,
          crossAxisCount: crossAxisCount,
        );
        return KeyEventResult.handled;
      }
      if (isShiftPressed && activateEntityInNewWindow != null) {
        activateEntityInNewWindow(items[currentIndex]);
      } else {
        activateEntity(items[currentIndex]);
      }
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
          crossAxisCount: crossAxisCount,
          folderListState: folderListState,
          currentFilter: currentFilter,
          focusFolderPath: focusFolderPath,
          focusFilePath: focusFilePath,
          onScrollToIndex: onScrollToIndex,
        );
      }
      return KeyEventResult.ignored;
    }

    final int newIndex = targetIndex.clamp(0, items.length - 1).toInt();
    if (isShiftPressed) {
      _selectRangeToIndex(
        items: items,
        currentIndex: currentIndex,
        targetIndex: newIndex,
        selectionState: selectionState,
        selectRange: selectRange,
        ctrlSelect: isCtrlPressed,
        crossAxisCount: crossAxisCount,
      );
    } else {
      _keyboardRangeAnchorPath = null;
      _focusItemAtIndex(
        items: items,
        index: newIndex,
        focusFolderPath: focusFolderPath,
        focusFilePath: focusFilePath,
        onScrollToIndex: onScrollToIndex,
        crossAxisCount: crossAxisCount,
      );
    }
    return KeyEventResult.handled;
  }

  List<FileSystemEntity> _getNavigableItems(
    FolderListState state,
    String? currentFilter,
  ) {
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
    void Function(int index, int crossAxisCount, double itemMainAxisExtent)?
    onScrollToIndex,
    int crossAxisCount = 1,
  }) {
    if (index < 0 || index >= items.length) return;

    final previousIndex = focusedPath == null
        ? -1
        : items.indexWhere((item) => item.path == focusedPath);
    final FileSystemEntity target = items[index];
    focusedPath = target.path;
    _keyboardRangeAnchorPath = target.path;

    if (target is Directory) {
      focusFolderPath(target.path);
    } else if (target is File) {
      focusFilePath(target.path);
    }

    _ensurePathVisible(
      target.path,
      forward: previousIndex == -1 || index >= previousIndex,
      index: index,
      crossAxisCount: crossAxisCount,
      itemHeight: _navigationItemExtent,
    );
  }

  void _selectRangeToIndex({
    required List<FileSystemEntity> items,
    required int currentIndex,
    required int targetIndex,
    required SelectionState selectionState,
    required void Function({
      required Set<String> folderPaths,
      required Set<String> filePaths,
      required String lastSelectedPath,
      required bool ctrlSelect,
    })
    selectRange,
    required bool ctrlSelect,
    required int crossAxisCount,
  }) {
    if (targetIndex < 0 || targetIndex >= items.length) return;

    final String anchorPath =
        _keyboardRangeAnchorPath ??
        focusedPath ??
        selectionState.lastSelectedPath ??
        items[currentIndex].path;
    _keyboardRangeAnchorPath = anchorPath;

    int anchorIndex = items.indexWhere(
      (FileSystemEntity item) => item.path == anchorPath,
    );
    if (anchorIndex == -1) {
      anchorIndex = currentIndex;
      _keyboardRangeAnchorPath = items[currentIndex].path;
    }

    final int startIndex = anchorIndex < targetIndex
        ? anchorIndex
        : targetIndex;
    final int endIndex = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    final Set<String> folderPaths = <String>{};
    final Set<String> filePaths = <String>{};

    for (int i = startIndex; i <= endIndex; i++) {
      final FileSystemEntity item = items[i];
      if (item is Directory) {
        folderPaths.add(item.path);
      } else if (item is File) {
        filePaths.add(item.path);
      }
    }

    final target = items[targetIndex];
    focusedPath = target.path;
    selectRange(
      folderPaths: folderPaths,
      filePaths: filePaths,
      lastSelectedPath: target.path,
      ctrlSelect: ctrlSelect,
    );

    _ensurePathVisible(
      target.path,
      forward: targetIndex >= currentIndex,
      index: targetIndex,
      crossAxisCount: crossAxisCount,
      itemHeight: _navigationItemExtent,
    );
  }

  KeyEventResult _performTypeAheadSearch({
    required String char,
    required int crossAxisCount,
    required FolderListState folderListState,
    required String? currentFilter,
    required void Function(String folderPath) focusFolderPath,
    required void Function(String filePath) focusFilePath,
    void Function(int index, int crossAxisCount, double itemMainAxisExtent)?
    onScrollToIndex,
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
        onScrollToIndex: onScrollToIndex,
        crossAxisCount: crossAxisCount,
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
