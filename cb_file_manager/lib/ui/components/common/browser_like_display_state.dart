import 'dart:io';

import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

class BrowserLikeDisplayState {
  static FolderListState? resolveSearchOrFilterDisplayState({
    required FolderListState state,
    String? currentFilter,
    String? currentSearchTagOverride,
  }) {
    final hasSearch =
        state.currentSearchQuery != null ||
        state.currentSearchTag != null ||
        currentSearchTagOverride != null;
    if (hasSearch && state.searchResults.isNotEmpty) {
      final folders = state.searchResults.whereType<Directory>().toList();
      final files = state.searchResults.whereType<File>().toList();
      return state.copyWith(folders: folders, files: files);
    }

    final hasFilter = currentFilter != null && currentFilter.isNotEmpty;
    if (hasFilter && state.filteredFiles.isNotEmpty) {
      return state.copyWith(
        folders: const <FileSystemEntity>[],
        files: state.filteredFiles.whereType<File>().toList(),
      );
    }

    return null;
  }
}
