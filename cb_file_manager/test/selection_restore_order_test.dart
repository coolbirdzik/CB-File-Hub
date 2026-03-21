import 'dart:collection';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SelectItemsInRect (shift) keeps lastSelectedPath by insertion order',
      () async {
    final bloc = SelectionBloc();

    final filePaths = LinkedHashSet<String>.of({
      '/a.mp4',
      '/b.mp4',
      '/c.mp4',
    });

    bloc.add(SelectItemsInRect(
      folderPaths: const <String>{},
      filePaths: filePaths,
      isShiftPressed: true,
      isCtrlPressed: false,
    ));

    final next = await bloc.stream.first;
    expect(next.selectedFilePaths,
        containsAll(<String>['/a.mp4', '/b.mp4', '/c.mp4']));
    expect(next.lastSelectedPath, equals('/c.mp4'));

    await bloc.close();
  });
}
