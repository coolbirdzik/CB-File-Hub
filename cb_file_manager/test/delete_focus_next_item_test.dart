import 'dart:io';

import 'package:cb_file_manager/ui/controllers/file_operations_handler.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_test/flutter_test.dart';

FolderListState _state({
  List<String> folders = const <String>[],
  List<String> files = const <String>[],
  String? currentFilter,
  List<String> filteredFiles = const <String>[],
  String? currentSearchTag,
  String? currentSearchQuery,
  List<String> searchResults = const <String>[],
}) {
  return FolderListState(
    '/',
    currentFilter: currentFilter,
    currentSearchTag: currentSearchTag,
    currentSearchQuery: currentSearchQuery,
    folders: folders.map((p) => Directory(p)).toList(),
    files: files.map((p) => File(p)).toList(),
    filteredFiles: filteredFiles.map((p) => File(p)).toList(),
    searchResults: searchResults.map((p) => File(p)).toList(),
  );
}

void main() {
  test('Delete focused item selects next item in order', () {
    final state = _state(
      folders: const <String>['/a', '/b'],
      files: const <String>['/c.mp4', '/d.mp4'],
    );

    final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
      state: state,
      pathsToDelete: const <String>{'/b'},
      anchorPath: '/b',
    );

    expect(next, equals('/c.mp4'));
  });

  test('Delete last item selects previous item', () {
    final state = _state(
      folders: const <String>['/a'],
      files: const <String>['/c.mp4', '/d.mp4'],
    );

    final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
      state: state,
      pathsToDelete: const <String>{'/d.mp4'},
      anchorPath: '/d.mp4',
    );

    expect(next, equals('/c.mp4'));
  });

  test('Delete contiguous block selects first item after block', () {
    final state = _state(
      folders: const <String>['/a', '/b'],
      files: const <String>['/c.mp4', '/d.mp4', '/e.mp4'],
    );

    final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
      state: state,
      pathsToDelete: const <String>{'/b', '/c.mp4', '/d.mp4'},
      anchorPath: '/b',
    );

    expect(next, equals('/e.mp4'));
  });

  test('Respects filtered view ordering', () {
    final state = _state(
      folders: const <String>['/a', '/b'],
      files: const <String>['/c.mp4', '/d.mp4'],
      currentFilter: 'video',
      filteredFiles: const <String>['/d.mp4', '/c.mp4'],
    );

    final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
      state: state,
      pathsToDelete: const <String>{'/d.mp4'},
      anchorPath: '/d.mp4',
    );

    expect(next, equals('/c.mp4'));
  });

  test('Respects search results ordering', () {
    final state = _state(
      folders: const <String>['/a', '/b'],
      files: const <String>['/c.mp4', '/d.mp4'],
      currentSearchQuery: 'c',
      searchResults: const <String>['/d.mp4', '/c.mp4'],
    );

    final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
      state: state,
      pathsToDelete: const <String>{'/d.mp4'},
      anchorPath: '/d.mp4',
    );

    expect(next, equals('/c.mp4'));
  });
}
