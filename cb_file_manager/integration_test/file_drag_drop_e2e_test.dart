import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:cb_file_manager/services/file_drag_drop/file_drag_drop_move_service.dart';
import 'package:cb_file_manager/services/windowing/windows_explorer_drag_drop_service.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import '../test/support/file_browser_drag_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in ViewMode.values) {
    testWidgets('hold and move two selected files in ${mode.name} on Windows', (
      tester,
    ) async {
      final root = await Directory.systemTemp.createTemp('cb_drag_move_e2e_');
      final destination = await Directory(
        p.join(root.path, 'destination'),
      ).create();
      final files = <File>[];
      for (final name in ['one.txt', 'two.txt']) {
        files.add(await File(p.join(root.path, name)).writeAsString(name));
      }
      FileDragDropMoveRejection? result;
      var moveCalls = 0;
      var externalDrags = 0;
      final key = GlobalKey<FileBrowserDragHarnessState>();
      try {
        await tester.pumpWidget(
          FileBrowserDragHarness(
            key: key,
            files: files,
            destination: destination,
            mode: mode,
            onExternalDrag: (paths) {
              externalDrags++;
              WindowsExplorerDragDropService.startFileDrag(paths);
            },
            onMove: (paths, folder) async {
              moveCalls++;
              result = await FileDragDropMoveService.move(
                sources: paths,
                destination: folder,
              );
            },
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.tapAt(tester.getCenter(find.text('one.txt').first));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tapAt(tester.getCenter(find.text('two.txt').first));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        final expected = files.map((file) => file.path).toSet();
        expect(key.currentState!.selection.state.selectedFilePaths, expected);
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('one.txt').first),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(seconds: 1));
        expect(key.currentState!.selection.state.selectedFilePaths, expected);
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.text('destination').first));
        await tester.pump();
        await gesture.up();
        for (var i = 0; i < 100 && result == null; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(externalDrags, 0);
        expect(moveCalls, 1);
        expect(result, FileDragDropMoveRejection.none);
        for (final source in files) {
          expect(await source.exists(), isFalse);
          expect(
            await File(
              p.join(destination.path, p.basename(source.path)),
            ).readAsString(),
            p.basename(source.path),
          );
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        // Only remove the newly-created, test-owned fixture directory.
        await root.delete(recursive: true);
      }
    }, skip: !Platform.isWindows);
  }
}
