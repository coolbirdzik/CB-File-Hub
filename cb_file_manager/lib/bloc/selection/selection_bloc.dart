import 'package:flutter_bloc/flutter_bloc.dart';
import 'selection_event.dart';
import 'selection_state.dart';
import '../../utils/app_logger.dart';

class SelectionBloc extends Bloc<SelectionEvent, SelectionState> {
  SelectionBloc() : super(const SelectionState()) {
    on<ToggleFileSelection>(_onToggleFileSelection);
    on<ToggleFolderSelection>(_onToggleFolderSelection);
    on<ClearSelection>(_onClearSelection);
    on<ToggleSelectionMode>(_onToggleSelectionMode);
    on<SelectItemsInRect>(_onSelectItemsInRect);
    on<SelectAll>(_onSelectAll);
    on<AddTagToItem>(_onAddTagToItem);
    on<RemoveTagFromItem>(_onRemoveTagFromItem);
    on<LoadTags>(_onLoadTags);
    on<LoadAllTags>(_onLoadAllTags);
  }

  // Handler for file selection toggle
  void _onToggleFileSelection(
    ToggleFileSelection event,
    Emitter<SelectionState> emit,
  ) {
    final filePath = event.filePath;
    final shiftSelect = event.shiftSelect;
    final ctrlSelect = event.ctrlSelect;

    // Create copies of current selections to modify
    final Set<String> selectedFiles = {...state.selectedFilePaths};
    final Set<String> selectedFolders = {...state.selectedFolderPaths};

    if (!shiftSelect) {
      // SINGLE ITEM SELECTION
      final bool isAlreadySelected = selectedFiles.contains(filePath);

      if (isAlreadySelected && ctrlSelect) {
        // Ctrl+click on selected item: deselect it
        selectedFiles.remove(filePath);
      } else if (ctrlSelect) {
        // Ctrl+click on unselected item: add to selection
        selectedFiles.add(filePath);
      } else {
        // Simple click: clear other selections, select only this one
        selectedFiles.clear();
        selectedFolders.clear();
        selectedFiles.add(filePath);
      }

      // Emit new state with updated selections and last selected path
      emit(state.copyWith(
        selectedFilePaths: selectedFiles,
        selectedFolderPaths: selectedFolders,
        lastSelectedPath: filePath,
        isSelectionMode: selectedFiles.isNotEmpty || selectedFolders.isNotEmpty,
      ));
    } else if (state.lastSelectedPath != null) {
      // SHIFT+CLICK RANGE SELECTION
      // This requires knowledge of all available file/folder paths in the current view
      // Since we don't have that directly in the bloc, we'll implement this in the UI layer
      // and use SelectItemsInRect event for that purpose
    }
  }

  // Handler for folder selection toggle
  void _onToggleFolderSelection(
    ToggleFolderSelection event,
    Emitter<SelectionState> emit,
  ) {
    final folderPath = event.folderPath;
    final shiftSelect = event.shiftSelect;
    final ctrlSelect = event.ctrlSelect;

    // Create copies of current selections to modify
    final Set<String> selectedFiles = {...state.selectedFilePaths};
    final Set<String> selectedFolders = {...state.selectedFolderPaths};

    if (!shiftSelect) {
      // SINGLE ITEM SELECTION
      final bool isAlreadySelected = selectedFolders.contains(folderPath);

      if (isAlreadySelected && ctrlSelect) {
        // Ctrl+click on selected folder: deselect it
        selectedFolders.remove(folderPath);
      } else if (ctrlSelect) {
        // Ctrl+click on unselected folder: add to selection
        selectedFolders.add(folderPath);
      } else {
        // Simple click: clear other selections, select only this one
        selectedFiles.clear();
        selectedFolders.clear();
        selectedFolders.add(folderPath);
      }

      // Emit new state with updated selections and last selected path
      emit(state.copyWith(
        selectedFilePaths: selectedFiles,
        selectedFolderPaths: selectedFolders,
        lastSelectedPath: folderPath,
        isSelectionMode: selectedFiles.isNotEmpty || selectedFolders.isNotEmpty,
      ));
    } else if (state.lastSelectedPath != null) {
      // SHIFT+CLICK RANGE SELECTION
      // This requires knowledge of all available file/folder paths in the current view
      // We'll implement this through SelectItemsInRect event
    }
  }

  // Handler for clearing all selections
  void _onClearSelection(
    ClearSelection event,
    Emitter<SelectionState> emit,
  ) {
    emit(state.copyWith(
      selectedFilePaths: {},
      selectedFolderPaths: {},
      isSelectionMode: false,
      clearLastSelectedPath: true,
    ));
  }

  // Handler for toggling selection mode
  void _onToggleSelectionMode(
    ToggleSelectionMode event,
    Emitter<SelectionState> emit,
  ) {
    final bool newMode = event.forceValue ?? !state.isSelectionMode;

    // If turning off selection mode, clear selections too
    if (!newMode) {
      emit(state.copyWith(
        selectedFilePaths: {},
        selectedFolderPaths: {},
        isSelectionMode: false,
        clearLastSelectedPath: true,
      ));
    } else {
      emit(state.copyWith(isSelectionMode: true));
    }
  }

  // Handler for rectangle/drag selection or shift-select
  void _onSelectItemsInRect(
    SelectItemsInRect event,
    Emitter<SelectionState> emit,
  ) {
    if (event.isShiftPressed) {
      // SHIFT+CLICK RANGE SELECTION
      // With Shift selection, we want to:
      // 1. If Ctrl is also pressed, toggle the selection within the range
      // 2. If Ctrl is not pressed, replace the current selection with this range

      // Create new sets based on whether CTRL is pressed
      final Set<String> newSelectedFiles = event.isCtrlPressed
          ? {
              ...state.selectedFilePaths
            } // Keep existing selections if CTRL is pressed
          : {}; // Clear selections if CTRL is not pressed

      final Set<String> newSelectedFolders = event.isCtrlPressed
          ? {
              ...state.selectedFolderPaths
            } // Keep existing selections if CTRL is pressed
          : {}; // Clear selections if CTRL is not pressed

      // Add all files in the selection range
      newSelectedFiles.addAll(event.filePaths);

      // Add all folders in the selection range
      newSelectedFolders.addAll(event.folderPaths);

      // Save the explicit endpoint when available. Range selection from the
      // keyboard can end on either a file or folder, independent of set order.
      final lastSelectedPath = event.lastSelectedPath ??
          (event.filePaths.isNotEmpty
              ? event.filePaths.last
              : (event.folderPaths.isNotEmpty ? event.folderPaths.last : null));

      emit(state.copyWith(
        selectedFilePaths: newSelectedFiles,
        selectedFolderPaths: newSelectedFolders,
        lastSelectedPath: lastSelectedPath ?? state.lastSelectedPath,
        isSelectionMode:
            newSelectedFiles.isNotEmpty || newSelectedFolders.isNotEmpty,
      ));
    } else {
      // Handle CTRL or no modifier keys (regular drag selection)
      final Set<String> newSelectedFiles;
      final Set<String> newSelectedFolders;

      if (event.isCtrlPressed) {
        // With Ctrl+drag: toggle items relative to the pre-drag snapshot so
        // that each item's final state is determined once (at drag-start) and
        // doesn't flicker as the mouse moves over the same item each frame.
        //
        // If a pre-drag snapshot was provided (rubber-band drag), use it as
        // the baseline. Otherwise fall back to the live state (Ctrl+click).
        final baseFiles = event.preCtrlDragFiles.isNotEmpty ||
                event.preCtrlDragFolders.isNotEmpty
            ? event.preCtrlDragFiles
            : state.selectedFilePaths;
        final baseFolders = event.preCtrlDragFiles.isNotEmpty ||
                event.preCtrlDragFolders.isNotEmpty
            ? event.preCtrlDragFolders
            : state.selectedFolderPaths;

        // Start from the snapshot, then apply toggle for items currently in rect.
        newSelectedFiles = Set.of(baseFiles);
        newSelectedFolders = Set.of(baseFolders);

        for (final filePath in event.filePaths) {
          if (baseFiles.contains(filePath)) {
            newSelectedFiles.remove(filePath);
          } else {
            newSelectedFiles.add(filePath);
          }
        }

        for (final folderPath in event.folderPaths) {
          if (baseFolders.contains(folderPath)) {
            newSelectedFolders.remove(folderPath);
          } else {
            newSelectedFolders.add(folderPath);
          }
        }
      } else {
        // Without Ctrl: clear selection and select only items in rect
        newSelectedFiles = {...event.filePaths};
        newSelectedFolders = {...event.folderPaths};
      }

      emit(state.copyWith(
        selectedFilePaths: newSelectedFiles,
        selectedFolderPaths: newSelectedFolders,
        isSelectionMode:
            newSelectedFiles.isNotEmpty || newSelectedFolders.isNotEmpty,
      ));
    }
  }

  // Handler for selecting all items
  void _onSelectAll(
    SelectAll event,
    Emitter<SelectionState> emit,
  ) {
    emit(state.copyWith(
      selectedFilePaths: event.allFilePaths.toSet(),
      selectedFolderPaths: event.allFolderPaths.toSet(),
      isSelectionMode:
          event.allFilePaths.isNotEmpty || event.allFolderPaths.isNotEmpty,
    ));
  }

  // Handler for adding a tag to a file or folder
  void _onAddTagToItem(
    AddTagToItem event,
    Emitter<SelectionState> emit,
  ) {
    // Here you would typically call a service to save the tag in a database
    // For this implementation, we're just updating the UI
    // This is a placeholder - in a real app, this would save to a database
    AppLogger.debug('Added tag ${event.tag} to item ${event.filePath}');

    // In a real implementation, you would:
    // 1. Call a service to save the tag
    // 2. Update the state if necessary
    // 3. Emit a new state
  }

  // Handler for removing a tag from a file or folder
  void _onRemoveTagFromItem(
    RemoveTagFromItem event,
    Emitter<SelectionState> emit,
  ) {
    // Here you would typically call a service to remove the tag in a database
    // For this implementation, we're just updating the UI
    // This is a placeholder - in a real app, this would save to a database
    AppLogger.debug('Removed tag ${event.tag} from item ${event.filePath}');

    // In a real implementation, you would:
    // 1. Call a service to remove the tag
    // 2. Update the state if necessary
    // 3. Emit a new state
  }

  // Handler for loading tags for a specific file or folder
  void _onLoadTags(
    LoadTags event,
    Emitter<SelectionState> emit,
  ) {
    // Here you would typically call a service to load tags from a database
    // For this implementation, we're just printing
    AppLogger.debug('Loading tags for item ${event.filePath}');

    // In a real implementation, you would:
    // 1. Call a service to load tags
    // 2. Update the state with the loaded tags
    // 3. Emit a new state
  }

  // Handler for loading all available tags
  void _onLoadAllTags(
    LoadAllTags event,
    Emitter<SelectionState> emit,
  ) {
    // Here you would typically call a service to load all tags from a database
    // For this implementation, we're just printing
    AppLogger.debug('Loading all available tags');

    // In a real implementation, you would:
    // 1. Call a service to load all tags
    // 2. Update the state with the loaded tags
    // 3. Emit a new state
  }
}
