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
  test('02.01 Delete focused item selects the item before it (left)', () {
    final state = _state(
      folders: const <String>['/a', '/b'],
      files: const <String>['/c.mp4', '/d.mp4'],
    );

    // '/b' has a neighbour on both sides; the one before it wins.
    final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
      state: state,
      pathsToDelete: const <String>{'/b'},
      anchorPath: '/b',
    );

    expect(next, equals('/a'));
  });

  test('02.01b Focus moves back across the folder/file boundary', () {
    final state = _state(
      folders: const <String>['/a', '/b'],
      files: const <String>['/c.mp4', '/d.mp4'],
    );

    final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
      state: state,
      pathsToDelete: const <String>{'/c.mp4'},
      anchorPath: '/c.mp4',
    );

    expect(next, equals('/b'));
  });

  test('02.02 Delete last item selects previous item', () {
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

  test('02.03 Delete contiguous block selects the item before the block', () {
    final state = _state(
      folders: const <String>['/a', '/b'],
      files: const <String>['/c.mp4', '/d.mp4', '/e.mp4'],
    );

    // Whichever end of the block holds focus, the survivor is the same.
    for (final anchor in const <String>['/b', '/d.mp4']) {
      final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
        state: state,
        pathsToDelete: const <String>{'/b', '/c.mp4', '/d.mp4'},
        anchorPath: anchor,
      );

      expect(next, equals('/a'), reason: 'anchor $anchor');
    }
  });

  test('02.03b Delete first item falls back to the item after it', () {
    final state = _state(
      folders: const <String>['/a', '/b'],
      files: const <String>['/c.mp4'],
    );

    final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
      state: state,
      pathsToDelete: const <String>{'/a'},
      anchorPath: '/a',
    );

    expect(next, equals('/b'));
  });

  test('02.03c Delete a leading block falls back to the item after it', () {
    final state = _state(
      folders: const <String>['/a', '/b'],
      files: const <String>['/c.mp4'],
    );

    final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
      state: state,
      pathsToDelete: const <String>{'/a', '/b'},
      anchorPath: '/b',
    );

    expect(next, equals('/c.mp4'));
  });

  test('02.04 Respects filtered view ordering', () {
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

  test('02.05 Respects search results ordering', () {
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

  test(
    '02.06 Does not choose a next focus when deleted item is not focused',
    () {
      final state = _state(
        folders: const <String>['/a', '/b'],
        files: const <String>['/c.mp4'],
      );

      final next = FileOperationsHandler.computeNextFocusPathAfterDelete(
        state: state,
        pathsToDelete: const <String>{'/b'},
        anchorPath: '/a',
      );

      expect(next, isNull);
    },
  );
}
