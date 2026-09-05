import 'package:equatable/equatable.dart';

/// State for the file and folder selection BLoC
class SelectionState extends Equatable {
  final Set<String> selectedFilePaths;
  final Set<String> selectedFolderPaths;
  final bool isSelectionMode;
  final String? lastSelectedPath;

  const SelectionState({
    this.selectedFilePaths = const {},
    this.selectedFolderPaths = const {},
    this.isSelectionMode = false,
    this.lastSelectedPath,
  });

  /// Total count of selected items
  int get selectedCount =>
      selectedFilePaths.length + selectedFolderPaths.length;

  /// Check if a specific path is selected
  bool isPathSelected(String path) =>
      selectedFilePaths.contains(path) || selectedFolderPaths.contains(path);

  /// Create a new state with updated properties
  SelectionState copyWith({
    Set<String>? selectedFilePaths,
    Set<String>? selectedFolderPaths,
    bool? isSelectionMode,
    String? lastSelectedPath,
    bool clearLastSelectedPath = false,
  }) {
    return SelectionState(
      selectedFilePaths: selectedFilePaths ?? this.selectedFilePaths,
      selectedFolderPaths: selectedFolderPaths ?? this.selectedFolderPaths,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      lastSelectedPath: clearLastSelectedPath
          ? null
          : lastSelectedPath ?? this.lastSelectedPath,
    );
  }

  /// Get a list of all selected paths (files and folders combined)
  List<String> get allSelectedPaths => [
    ...selectedFilePaths,
    ...selectedFolderPaths,
  ];

  @override
  List<Object?> get props => [
    selectedFilePaths,
    selectedFolderPaths,
    isSelectionMode,
    lastSelectedPath,
  ];
}
