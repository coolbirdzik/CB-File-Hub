import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/widgets/selection_rectangle_painter.dart';
import 'package:cb_file_manager/ui/widgets/value_listenable_builders.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TabbedFolderDragSelectionController {
  final FolderListBloc folderListBloc;
  final SelectionBloc selectionBloc;

  final Map<String, Rect> _itemPositions = {};

  final ValueNotifier<bool> isDragging = ValueNotifier<bool>(false);
  final ValueNotifier<Offset?> dragStartPosition = ValueNotifier<Offset?>(null);
  final ValueNotifier<Offset?> dragCurrentPosition =
      ValueNotifier<Offset?>(null);

  TabbedFolderDragSelectionController({
    required this.folderListBloc,
    required this.selectionBloc,
  });

  void dispose() {
    isDragging.dispose();
    dragStartPosition.dispose();
    dragCurrentPosition.dispose();
  }

  void clearItemPositions() {
    _itemPositions.clear();
  }

  void registerItemPosition(String path, Rect position) {
    _itemPositions[path] = position;
  }

  void start(Offset position) {
    if (isDragging.value) return;

    isDragging.value = true;
    dragStartPosition.value = position;
    dragCurrentPosition.value = position;
  }

  void update(Offset position) {
    if (!isDragging.value) return;

    dragCurrentPosition.value = position;

    if (dragStartPosition.value == null || dragCurrentPosition.value == null) {
      return;
    }

    final Rect selectionRect = Rect.fromPoints(
      dragStartPosition.value!,
      dragCurrentPosition.value!,
    );
    _selectItemsInRect(selectionRect);
  }

  void end() {
    isDragging.value = false;
    dragStartPosition.value = null;
    dragCurrentPosition.value = null;
  }

  Widget buildOverlay() {
    return ValueListenableBuilder3<bool, Offset?, Offset?>(
      valueListenable1: isDragging,
      valueListenable2: dragStartPosition,
      valueListenable3: dragCurrentPosition,
      builder: (context, dragging, startPosition, currentPosition, _) {
        if (!dragging || startPosition == null || currentPosition == null) {
          return const SizedBox.shrink();
        }

        final selectionRect = Rect.fromPoints(startPosition, currentPosition);

        return Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: SelectionRectanglePainter(
                selectionRect: selectionRect,
                fillColor: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.4),
                borderColor: Theme.of(context).primaryColor,
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectItemsInRect(Rect selectionRect) {
    if (!isDragging.value) return;

    final keyboard = HardwareKeyboard.instance;
    final bool isCtrlPressed =
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.control) ||
            keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
            keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight) ||
            keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.meta) ||
            keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.metaLeft) ||
            keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.metaRight);

    final bool isShiftPressed =
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.shift) ||
            keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
            keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);

    final folderPaths = folderListBloc.state.folders
        .whereType<Directory>()
        .map((folder) => folder.path)
        .toSet();

    final Set<String> selectedFoldersInDrag = {};
    final Set<String> selectedFilesInDrag = {};

    _itemPositions.forEach((path, itemRect) {
      if (!selectionRect.overlaps(itemRect)) return;

      if (folderPaths.contains(path)) {
        selectedFoldersInDrag.add(path);
      } else {
        selectedFilesInDrag.add(path);
      }
    });

    selectionBloc.add(SelectItemsInRect(
      folderPaths: selectedFoldersInDrag,
      filePaths: selectedFilesInDrag,
      isCtrlPressed: isCtrlPressed,
      isShiftPressed: isShiftPressed,
    ));
  }
}
