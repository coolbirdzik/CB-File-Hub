import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/file_browser_drag_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in ViewMode.values) {
    testWidgets('select two, hold and drag into folder in ${mode.name}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = [
        File(p.join('C:', 'drag', 'one.txt')),
        File(p.join('C:', 'drag', 'two.txt')),
      ];
      List<String>? moved;
      String? movedTo;
      var externalDrags = 0;
      final key = GlobalKey<FileBrowserDragHarnessState>();
      await tester.pumpWidget(
        FileBrowserDragHarness(
          key: key,
          files: files,
          destination: Directory(p.join('C:', 'drag', 'destination')),
          mode: mode,
          onMove: (paths, folder) async {
            moved = paths;
            movedTo = folder;
          },
          onExternalDrag: (_) => externalDrags++,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(tester.getCenter(find.text('one.txt').first));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tapAt(tester.getCenter(find.text('two.txt').first));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 400));
      final expected = files.map((file) => file.path).toSet();
      expect(key.currentState!.selection.state.selectedFilePaths, expected);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('one.txt').first),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        key.currentState!.selection.state.selectedFilePaths,
        expected,
        reason: 'Holding the selected item must preserve both files',
      );
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('destination').first));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(
        externalDrags,
        0,
        reason: 'In-app drags must not start an OLE loop',
      );
      expect(moved, unorderedEquals(expected));
      expect(movedTo, p.join('C:', 'drag', 'destination'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}
