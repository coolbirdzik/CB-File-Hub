import 'package:equatable/equatable.dart';

/// Base class for all selection events
abstract class SelectionEvent extends Equatable {
  const SelectionEvent();

  @override
  List<Object?> get props => [];
}

/// Event to toggle selection for a file path
class ToggleFileSelection extends SelectionEvent {
  final String filePath;
  final bool shiftSelect;
  final bool ctrlSelect;

  const ToggleFileSelection(
    this.filePath, {
    this.shiftSelect = false,
    this.ctrlSelect = false,
  });

  @override
  List<Object?> get props => [filePath, shiftSelect, ctrlSelect];
}

/// Event to toggle selection for a folder path
class ToggleFolderSelection extends SelectionEvent {
  final String folderPath;
  final bool shiftSelect;
  final bool ctrlSelect;

  const ToggleFolderSelection(
    this.folderPath, {
    this.shiftSelect = false,
    this.ctrlSelect = false,
  });

  @override
  List<Object?> get props => [folderPath, shiftSelect, ctrlSelect];
}

/// Event to clear all selections
class ClearSelection extends SelectionEvent {}

/// Event to toggle selection mode (on/off)
class ToggleSelectionMode extends SelectionEvent {
  final bool? forceValue;

  const ToggleSelectionMode({this.forceValue});

  @override
  List<Object?> get props => [forceValue];
}

/// Event to select multiple items using a rectangle (drag selection)
class SelectItemsInRect extends SelectionEvent {
  final Set<String> folderPaths;
  final Set<String> filePaths;
  final bool isCtrlPressed;
  final bool isShiftPressed;
  final String? lastSelectedPath;

  /// Snapshot of selected files taken at the moment the Ctrl+drag started.
  /// The bloc uses this to compute a stable toggle delta instead of
  /// toggling against the live state on every pan-update frame.
  final Set<String> preCtrlDragFiles;
  final Set<String> preCtrlDragFolders;

  const SelectItemsInRect({
    required this.folderPaths,
    required this.filePaths,
    this.isCtrlPressed = false,
    this.isShiftPressed = false,
    this.lastSelectedPath,
    this.preCtrlDragFiles = const {},
    this.preCtrlDragFolders = const {},
  });

  @override
  List<Object?> get props => [
        folderPaths,
        filePaths,
        isCtrlPressed,
        isShiftPressed,
        lastSelectedPath,
      ];
}

/// Event to select all files and folders in the current view
class SelectAll extends SelectionEvent {
  final List<String> allFilePaths;
  final List<String> allFolderPaths;

  const SelectAll({
    required this.allFilePaths,
    required this.allFolderPaths,
  });

  @override
  List<Object?> get props => [allFilePaths, allFolderPaths];
}

class AddTagToItem extends SelectionEvent {
  final String filePath;
  final String tag;

  const AddTagToItem(this.filePath, this.tag);

  @override
  List<Object?> get props => [filePath, tag];
}

class RemoveTagFromItem extends SelectionEvent {
  final String filePath;
  final String tag;

  const RemoveTagFromItem(this.filePath, this.tag);

  @override
  List<Object?> get props => [filePath, tag];
}

class LoadTags extends SelectionEvent {
  final String filePath;

  const LoadTags(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class LoadAllTags extends SelectionEvent {
  const LoadAllTags();
}
