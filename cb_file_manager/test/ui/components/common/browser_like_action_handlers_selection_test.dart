import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_action_handlers.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hiddenFile = File('root/hidden.txt');
  final hiddenFolder = Directory('root/hidden');
  final matchedFile = File('root/nested/match.txt');
  final matchedFolder = Directory('root/nested/match');

  Future<SelectionState> selectVisible(
    FolderListState state, {
    String? filter,
    String? tagOverride,
  }) async {
    final selection = SelectionBloc(
      initialState: SelectionState(
        selectedFilePaths: {hiddenFile.path},
        selectedFolderPaths: {hiddenFolder.path},
        isSelectionMode: true,
      ),
    );
    addTearDown(selection.close);
    final selected = selection.stream.first;
    BrowserLikeActionHandlers.selectAllVisibleFolderItems(
      selectionBloc: selection,
      state: state,
      currentFilter: filter,
      currentSearchTagOverride: tagOverride,
    );
    return selected;
  }

  FolderListState sourceState() =>
      FolderListState('root', files: [hiddenFile], folders: [hiddenFolder]);

  for (final search in ['filename', 'tag', 'tag override']) {
    for (final empty in [false, true]) {
      test('select all selects only $search results (empty: $empty)', () async {
        final state = sourceState().copyWith(
          currentSearchQuery: search == 'filename' ? 'match' : null,
          currentSearchTag: search == 'tag' ? 'work' : null,
          searchRecursive: true,
          searchResults: empty ? [] : [matchedFile, matchedFolder],
          // A search takes precedence over any previous filter results.
          filteredFiles: [hiddenFile],
        );

        final selected = await selectVisible(
          state,
          filter: 'txt',
          tagOverride: search == 'tag override' ? 'work' : null,
        );

        expect(
          selected.selectedFilePaths,
          empty ? <String>{} : {matchedFile.path},
        );
        expect(
          selected.selectedFolderPaths,
          empty ? <String>{} : {matchedFolder.path},
        );
        expect(selected.isSelectionMode, !empty);
      });
    }
  }

  for (final empty in [false, true]) {
    test('select all selects only filtered files (empty: $empty)', () async {
      final selected = await selectVisible(
        sourceState().copyWith(
          filteredFiles: empty ? [] : [matchedFile],
          searchResults: [hiddenFile, hiddenFolder],
        ),
        filter: 'txt',
      );

      expect(
        selected.selectedFilePaths,
        empty ? <String>{} : {matchedFile.path},
      );
      expect(selected.selectedFolderPaths, isEmpty);
      expect(selected.isSelectionMode, !empty);
    });
  }

  test(
    'select all without a search or filter selects directory contents',
    () async {
      final selected = await selectVisible(
        sourceState().copyWith(
          files: [hiddenFile, matchedFile],
          searchResults: [matchedFile, matchedFolder],
          filteredFiles: [matchedFile],
        ),
        filter: '',
      );

      expect(selected.selectedFilePaths, {hiddenFile.path, matchedFile.path});
      expect(selected.selectedFolderPaths, {hiddenFolder.path});
    },
  );
}
