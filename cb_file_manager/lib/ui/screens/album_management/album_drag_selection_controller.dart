import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/widgets/selection_rectangle_painter.dart';
import 'package:cb_file_manager/ui/widgets/value_listenable_builders.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A self-contained drag-selection controller for screens that show only
/// files (no sub-folders), such as [AlbumDetailScreen].
///
/// Mirrors the logic of [TabbedFolderDragSelectionController] but does not
/// depend on [FolderListBloc] — item-path classification is not needed
/// because albums contain only files.
class AlbumDragSelectionController {
  final SelectionBloc selectionBloc;

  // ── Registered item bounding-boxes (global coordinates) ───────────────────
  final Map<String, Rect> _itemPositions = {};

  // ── Drag state ─────────────────────────────────────────────────────────────
  final ValueNotifier<bool> isDragging = ValueNotifier<bool>(false);
  final ValueNotifier<Offset?> dragStartPosition = ValueNotifier<Offset?>(null);
  final ValueNotifier<Offset?> dragCurrentPosition = ValueNotifier<Offset?>(
    null,
  );

  /// [GlobalKey] that must be assigned to the [Stack] wrapping the grid so
  /// that local drag coordinates can be converted to global screen coords.
  final GlobalKey stackKey = GlobalKey();

  // Snapshot of selection taken at the start of a Ctrl+drag to avoid
  // per-frame toggle flickering.
  Set<String> _preCtrlDragFiles = const {};

  AlbumDragSelectionController({required this.selectionBloc});

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void dispose() {
    isDragging.dispose();
    dragStartPosition.dispose();
    dragCurrentPosition.dispose();
  }

  void clearItemPositions() => _itemPositions.clear();

  void registerItemPosition(String path, Rect globalRect) {
    _itemPositions[path] = globalRect;
  }

  void start(Offset localPosition) {
    if (isDragging.value) return;

    final keyboard = HardwareKeyboard.instance;
    final bool isCtrl = _isCtrlPressed(keyboard);

    _preCtrlDragFiles = isCtrl
        ? Set.of(selectionBloc.state.selectedFilePaths)
        : const {};

    isDragging.value = true;
    dragStartPosition.value = localPosition;
    dragCurrentPosition.value = localPosition;
  }

  void update(Offset localPosition) {
    if (!isDragging.value) return;
    dragCurrentPosition.value = localPosition;
    if (dragStartPosition.value == null) return;

    final selectionRect = Rect.fromPoints(
      dragStartPosition.value!,
      localPosition,
    );
    _selectItemsInRect(selectionRect);
  }

  void end() {
    isDragging.value = false;
    dragStartPosition.value = null;
    dragCurrentPosition.value = null;
    _preCtrlDragFiles = const {};
  }

  /// Renders the blue rubber-band rectangle overlay.
  Widget buildOverlay() {
    return ValueListenableBuilder3<bool, Offset?, Offset?>(
      valueListenable1: isDragging,
      valueListenable2: dragStartPosition,
      valueListenable3: dragCurrentPosition,
      builder: (context, dragging, startPos, curPos, _) {
        if (!dragging || startPos == null || curPos == null) {
          return const SizedBox.shrink();
        }
        final rect = Rect.fromPoints(startPos, curPos);
        return Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: SelectionRectanglePainter(
                selectionRect: rect,
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

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _selectItemsInRect(Rect localRect) {
    if (!isDragging.value) return;

    // Convert local Stack coordinates → global screen coordinates.
    final RenderBox? stackBox =
        stackKey.currentContext?.findRenderObject() as RenderBox?;
    final Rect globalRect = stackBox != null
        ? localRect.shift(stackBox.localToGlobal(Offset.zero))
        : localRect;

    final keyboard = HardwareKeyboard.instance;
    final bool isCtrl = _isCtrlPressed(keyboard);
    final bool isShift = _isShiftPressed(keyboard);

    final Set<String> selected = {};
    _itemPositions.forEach((path, itemRect) {
      if (globalRect.overlaps(itemRect)) selected.add(path);
    });

    selectionBloc.add(
      SelectItemsInRect(
        folderPaths: const {}, // albums have no sub-folders
        filePaths: selected,
        isCtrlPressed: isCtrl,
        isShiftPressed: isShift,
        preCtrlDragFiles: _preCtrlDragFiles,
        preCtrlDragFolders: const {},
      ),
    );
  }

  static bool _isCtrlPressed(HardwareKeyboard kb) {
    final keys = kb.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.control) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.meta) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  static bool _isShiftPressed(HardwareKeyboard kb) {
    final keys = kb.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shift) ||
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }
}
