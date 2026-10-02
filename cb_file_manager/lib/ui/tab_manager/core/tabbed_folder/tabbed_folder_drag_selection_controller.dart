import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/widgets/selection_rectangle_painter.dart';
import 'package:cb_file_manager/ui/widgets/value_listenable_builders.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TabbedFolderDragSelectionController {
  final FolderListBloc? folderListBloc;
  final SelectionBloc selectionBloc;

  /// Optional classifier for virtual collections whose items are not backed
  /// by a [FolderListBloc]. Paths omitted from this iterable are treated as
  /// files, matching the regular file-browser behavior.
  final Iterable<String> Function()? folderPaths;

  final Map<String, Rect> _itemPositions = {};
  final Map<String, RenderBox> _itemRenderBoxes = {};

  final ValueNotifier<bool> isDragging = ValueNotifier<bool>(false);
  final ValueNotifier<Offset?> dragStartPosition = ValueNotifier<Offset?>(null);
  final ValueNotifier<Offset?> dragCurrentPosition = ValueNotifier<Offset?>(
    null,
  );

  /// Key assigned to the Stack that wraps the grid/list/details view.
  /// Used to convert the local-coordinate selectionRect into global
  /// coordinates so it can be compared with _itemPositions (global coords).
  final GlobalKey stackKey = GlobalKey();

  // Snapshot of selection state taken at the moment a Ctrl+drag starts.
  // Prevents per-frame toggle flickering by computing the delta against
  // this fixed baseline rather than the live selection state.
  Set<String> _preCtrlDragFiles = const {};
  Set<String> _preCtrlDragFolders = const {};

  // Auto-clear item positions whenever the folder state changes (navigation,
  // new files created, refresh, etc.) so that stale rects cannot ghost-select
  // items that have moved or been added/removed.
  // Nullable so dispose() is safe even if the bloc is closed before the
  // controller is disposed (order of disposal in the screen's dispose()).
  StreamSubscription<FolderListState>? _folderListSub;

  TabbedFolderDragSelectionController({
    this.folderListBloc,
    required this.selectionBloc,
    this.folderPaths,
  }) {
    _folderListSub = folderListBloc?.stream.listen((_) {
      // Don't clear during an active drag — items are being hit-tested now.
      if (!isDragging.value) {
        clearItemPositions();
      }
    });
  }

  void dispose() {
    _folderListSub?.cancel();
    _folderListSub = null;
    _itemRenderBoxes.clear();
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

  /// Grid tiles register once. Read their final bounds only during selection,
  /// rather than scheduling a measurement for every tile on every resize frame.
  void registerItemRenderBox(String path, RenderBox box) {
    _itemRenderBoxes[path] = box;
  }

  void unregisterItemRenderBox(String path, RenderBox box) {
    if (identical(_itemRenderBoxes[path], box)) _itemRenderBoxes.remove(path);
  }

  Iterable<MapEntry<String, Rect>> get _currentItemPositions sync* {
    for (final entry in _itemPositions.entries) {
      if (!_itemRenderBoxes.containsKey(entry.key)) yield entry;
    }
    for (final entry in _itemRenderBoxes.entries) {
      final box = entry.value;
      if (box.attached && box.hasSize) {
        yield MapEntry(entry.key, box.localToGlobal(Offset.zero) & box.size);
      }
    }
  }

  String? hitTestItem(Offset globalPosition, {Set<String>? allowedPaths}) {
    final entries = _currentItemPositions.toList(growable: false).reversed;
    for (final entry in entries) {
      if (allowedPaths != null && !allowedPaths.contains(entry.key)) {
        continue;
      }
      if (entry.value.contains(globalPosition)) {
        return entry.key;
      }
    }
    return null;
  }

  void start(Offset position) {
    if (isDragging.value) return;

    // Snapshot the current selection so Ctrl+drag can compute a stable delta
    // against this baseline on every pan-update frame.
    final keyboard = HardwareKeyboard.instance;
    final bool isCtrlPressed =
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.control) ||
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight) ||
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.meta) ||
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.metaLeft) ||
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.metaRight);

    if (isCtrlPressed) {
      _preCtrlDragFiles = Set.of(selectionBloc.state.selectedFilePaths);
      _preCtrlDragFolders = Set.of(selectionBloc.state.selectedFolderPaths);
    } else {
      _preCtrlDragFiles = const {};
      _preCtrlDragFolders = const {};
    }

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
    // Clear Ctrl-drag snapshot
    _preCtrlDragFiles = const {};
    _preCtrlDragFolders = const {};
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
                fillColor: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.4),
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

    // Convert the selectionRect from the Stack's local coordinate space to
    // global screen coordinates, matching how item positions are registered
    // (via RenderBox.localToGlobal).
    final RenderBox? stackBox =
        stackKey.currentContext?.findRenderObject() as RenderBox?;
    final Rect globalSelectionRect = stackBox != null
        ? selectionRect.shift(stackBox.localToGlobal(Offset.zero))
        : selectionRect;

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

    final configuredFolderPaths = folderPaths?.call();
    final knownFolderPaths = configuredFolderPaths != null
        ? configuredFolderPaths.toSet()
        : folderListBloc?.state.folders
                  .whereType<Directory>()
                  .map((folder) => folder.path)
                  .toSet() ??
              const <String>{};

    final Set<String> selectedFoldersInDrag = {};
    final Set<String> selectedFilesInDrag = {};

    for (final entry in _currentItemPositions) {
      final path = entry.key;
      if (!globalSelectionRect.overlaps(entry.value)) continue;

      if (knownFolderPaths.contains(path)) {
        selectedFoldersInDrag.add(path);
      } else {
        selectedFilesInDrag.add(path);
      }
    }

    selectionBloc.add(
      SelectItemsInRect(
        folderPaths: selectedFoldersInDrag,
        filePaths: selectedFilesInDrag,
        isCtrlPressed: isCtrlPressed,
        isShiftPressed: isShiftPressed,
        // Pass the pre-drag snapshot so the bloc can compute a stable toggle
        // delta instead of re-toggling against the live state each frame.
        preCtrlDragFiles: _preCtrlDragFiles,
        preCtrlDragFolders: _preCtrlDragFolders,
      ),
    );
  }
}
