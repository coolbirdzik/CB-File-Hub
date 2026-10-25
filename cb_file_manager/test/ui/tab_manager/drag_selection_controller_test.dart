import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:cb_file_manager/ui/widgets/selection_geometry_item.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingSelectionBloc extends SelectionBloc {
  int rectangleEvents = 0;

  @override
  void onEvent(SelectionEvent event) {
    if (event is SelectItemsInRect) rectangleEvents++;
    super.onEvent(event);
  }
}

void main() {
  late _CountingSelectionBloc selection;
  late TabbedFolderDragSelectionController controller;

  setUp(() {
    selection = _CountingSelectionBloc();
    controller = TabbedFolderDragSelectionController(
      selectionBloc: selection,
      folderPaths: () => ['folder'],
    );
    controller.registerItemPosition(
      'file',
      const Rect.fromLTWH(10, 10, 20, 20),
    );
    controller.registerItemPosition(
      'folder',
      const Rect.fromLTWH(50, 10, 20, 20),
    );
  });

  tearDown(() async {
    controller.dispose();
    await selection.close();
  });

  testWidgets('registers nested folder kinds and removes detached rows', (
    tester,
  ) async {
    controller.clearItemPositions();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SelectionGeometryItem(
            path: 'nested-folder',
            isFolder: true,
            controller: controller,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    );
    controller.start(Offset.zero);
    controller.update(const Offset(20, 20));
    controller.end();
    await tester.pump();
    expect(selection.state.selectedFolderPaths, {'nested-folder'});
    expect(selection.state.selectedFilePaths, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.hitTestItem(const Offset(20, 20)), isNull);
  });

  testWidgets('coalesces moves and skips unchanged selections', (tester) async {
    controller.start(Offset.zero);
    for (var i = 0; i < 100; i++) {
      controller.update(Offset(20 + i / 100, 20));
    }
    expect(selection.rectangleEvents, 0);
    await tester.pump();
    expect(selection.rectangleEvents, 1);
    expect(selection.state.selectedFilePaths, {'file'});
    controller.update(const Offset(25, 25));
    await tester.pump();
    expect(selection.rectangleEvents, 1);
    controller.update(const Offset(60, 25));
    controller.end();
    await tester.pump();
    expect(selection.rectangleEvents, 2);
    expect(selection.state.selectedFolderPaths, {'folder'});
    expect(selection.state.selectedFilePaths, {'file'});
  });

  testWidgets('Ctrl drag stays stable with an empty starting selection', (
    tester,
  ) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    controller.start(Offset.zero);
    controller.update(const Offset(20, 20));
    await tester.pump();
    expect(selection.state.selectedFilePaths, {'file'});
    controller.update(const Offset(21, 21));
    await tester.pump();
    expect(selection.state.selectedFilePaths, {'file'});
    controller.update(const Offset(5, 5));
    await tester.pump();
    expect(selection.state.selectedFilePaths, isEmpty);
    controller.end();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('Ctrl drag toggles against the starting selection', (
    tester,
  ) async {
    selection.add(
      const SelectItemsInRect(filePaths: {'file'}, folderPaths: {}),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    controller.start(Offset.zero);
    controller.update(const Offset(60, 20));
    await tester.pump();
    expect(selection.state.selectedFilePaths, isEmpty);
    expect(selection.state.selectedFolderPaths, {'folder'});
    controller.update(const Offset(5, 5));
    await tester.pump();
    expect(selection.state.selectedFilePaths, {'file'});
    expect(selection.state.selectedFolderPaths, isEmpty);
    controller.end();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('Shift drag retracts to the starting selection', (tester) async {
    selection.add(
      const SelectItemsInRect(filePaths: {}, folderPaths: {'folder'}),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    controller.start(Offset.zero);
    controller.update(const Offset(20, 20));
    await tester.pump();
    expect(selection.state.selectedFilePaths, {'file'});
    expect(selection.state.selectedFolderPaths, {'folder'});
    controller.update(const Offset(5, 5));
    controller.end();
    await tester.pump();
    expect(selection.state.selectedFilePaths, isEmpty);
    expect(selection.state.selectedFolderPaths, {'folder'});
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });
}
