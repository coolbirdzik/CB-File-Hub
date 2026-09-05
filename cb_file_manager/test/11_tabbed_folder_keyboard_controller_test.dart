import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_keyboard_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  testWidgets('11.01 Shift+arrow extends selection from the original anchor', (
    tester,
  ) async {
    final controller = TabbedFolderKeyboardController();
    addTearDown(controller.dispose);

    final files = <FileSystemEntity>[
      File(r'C:\root\a.txt'),
      File(r'C:\root\b.txt'),
      File(r'C:\root\c.txt'),
    ];
    final state = FolderListState(r'C:\root', files: files);
    SelectionState selectionState = SelectionState(
      selectedFilePaths: <String>{files.first.path},
      lastSelectedPath: files.first.path,
      isSelectionMode: true,
    );
    controller.focusedPath = files.first.path;

    final selectedRanges = <Set<String>>[];
    String? capturedLastSelectedPath;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

    KeyEventResult pressArrowDown() {
      return controller.handleKeyEvent(
        isDesktop: true,
        folderListState: state,
        selectionState: selectionState,
        currentFilter: null,
        onBackInTabHistory: () {},
        focusFolderPath: (_) => fail('Shift+arrow should select a range'),
        focusFilePath: (_) => fail('Shift+arrow should select a range'),
        selectRange:
            ({
              required Set<String> folderPaths,
              required Set<String> filePaths,
              required String lastSelectedPath,
              required bool ctrlSelect,
            }) {
              selectedRanges.add(filePaths);
              selectionState = SelectionState(
                selectedFilePaths: filePaths,
                selectedFolderPaths: folderPaths,
                lastSelectedPath: lastSelectedPath,
                isSelectionMode: filePaths.isNotEmpty || folderPaths.isNotEmpty,
              );
              capturedLastSelectedPath = lastSelectedPath;
            },
        activateEntity: (_) {},
        onDelete: (_) {},
        event: const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowDown,
          physicalKey: PhysicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
      );
    }

    expect(pressArrowDown(), KeyEventResult.handled);
    expect(pressArrowDown(), KeyEventResult.handled);

    expect(selectedRanges.last, <String>{
      files[0].path,
      files[1].path,
      files[2].path,
    });
    expect(controller.focusedPath, files[2].path);
    expect(capturedLastSelectedPath, files[2].path);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('11.02 Immediate selection settles after bloc state catches up', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = TabbedFolderKeyboardController();
    addTearDown(controller.dispose);

    const oldPath = r'C:\root\a.txt';
    const newPath = r'C:\root\b.txt';
    final oldSelection = controller.immediateSelectionForPath(oldPath);
    final newSelection = controller.immediateSelectionForPath(newPath);

    controller.showImmediateSelection(
      <String>{newPath},
      currentSelectedPaths: <String>{oldPath},
    );

    expect(oldSelection.value, isFalse);
    expect(newSelection.value, isTrue);

    controller.syncFromSelection(
      const SelectionState(
        selectedFilePaths: <String>{newPath},
        lastSelectedPath: newPath,
        isSelectionMode: true,
      ),
    );

    // Keep the existing row style for this frame, then hand control back to
    // SelectionBloc without any second overlay or visible transition.
    expect(oldSelection.value, isFalse);
    expect(newSelection.value, isTrue);
    await tester.pump();
    expect(oldSelection.value, isNull);
    expect(newSelection.value, isNull);
  });

  testWidgets('11.03 Interaction without long press reacts on pointer down', (
    tester,
  ) async {
    var tapCount = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: OptimizedInteractionLayer(
              onTap: () => tapCount++,
              onDoubleTap: () {},
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(OptimizedInteractionLayer)),
    );
    expect(tapCount, 1);

    await gesture.up();
    expect(tapCount, 1);
  });
}
