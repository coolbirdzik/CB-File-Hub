import 'package:flutter/material.dart';

/// Mixin providing selection mode functionality for screens with file/item selection
mixin SelectionMixin<T extends StatefulWidget> on State<T> {
  /// Current selection mode state
  bool get isSelectionMode => _isSelectionMode;
  bool _isSelectionMode = false;

  /// Set of selected item paths/IDs
  final Set<String> selectedPaths = {};

  /// Number of selected items
  int get selectedCount => selectedPaths.length;

  /// Check if an item is selected
  bool isSelected(String path) => selectedPaths.contains(path);

  /// Enter selection mode
  void enterSelectionMode() {
    if (!_isSelectionMode) {
      setState(() {
        _isSelectionMode = true;
      });
    }
  }

  /// Exit selection mode and clear selection
  void exitSelectionMode() {
    if (_isSelectionMode) {
      setState(() {
        _isSelectionMode = false;
        selectedPaths.clear();
      });
    }
  }

  /// Toggle selection mode
  void toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        selectedPaths.clear();
      }
    });
  }

  /// Toggle selection of a single item
  void toggleSelection(String path) {
    setState(() {
      if (selectedPaths.contains(path)) {
        selectedPaths.remove(path);
      } else {
        selectedPaths.add(path);
      }
    });
  }

  /// Select a single item (enter selection mode if needed)
  void selectItem(String path) {
    setState(() {
      if (!_isSelectionMode) {
        _isSelectionMode = true;
      }
      selectedPaths.add(path);
    });
  }

  /// Replace the current selection and optionally control whether the
  /// screen should be considered in multi-selection mode.
  void replaceSelection(
    Iterable<String> paths, {
    bool? selectionMode,
  }) {
    setState(() {
      selectedPaths
        ..clear()
        ..addAll(paths);
      _isSelectionMode = selectionMode ?? selectedPaths.isNotEmpty;
    });
  }

  /// Deselect a single item
  void deselectItem(String path) {
    setState(() {
      selectedPaths.remove(path);
    });
  }

  /// Select all items from a list
  void selectAll(List<String> paths) {
    setState(() {
      selectedPaths.addAll(paths);
    });
  }

  /// Clear all selections
  void clearSelection() {
    setState(() {
      selectedPaths.clear();
    });
  }

  /// Select or deselect all items
  void toggleSelectAll(List<String> allPaths) {
    setState(() {
      if (selectedPaths.length == allPaths.length) {
        selectedPaths.clear();
      } else {
        selectedPaths.addAll(allPaths);
      }
    });
  }

  /// Handle item tap in selection mode
  void onItemTapInSelectionMode(String path, VoidCallback? normalTapAction) {
    if (_isSelectionMode) {
      toggleSelection(path);
    } else if (normalTapAction != null) {
      normalTapAction();
    }
  }

  /// Handle item long press to enter selection mode
  void onItemLongPress(String path) {
    if (!_isSelectionMode) {
      selectItem(path);
    }
  }
}
