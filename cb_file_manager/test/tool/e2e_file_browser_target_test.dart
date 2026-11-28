import 'dart:io';

import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../integration_test/e2e_file_browser_target.dart';
import '../support/file_browser_drag_harness.dart';

void main() {
  for (final mode in [ViewMode.details, ViewMode.list, ViewMode.grid]) {
    testWidgets(
      'semantics probe clicks an actual browser row in ${mode.name}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(1280, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey<FileBrowserDragHarnessState>();
        final folder = p.join('C:', 'semantics-target');
        final file = File(p.join(folder, 'file_0.txt'));
        await tester.pumpWidget(
          FileBrowserDragHarness(
            key: key,
            files: [
              file,
              for (var i = 1; i < 30; i++) File(p.join(folder, 'file_$i.txt')),
            ],
            destination: Directory(p.join(folder, 'sub')),
            mode: mode,
            onMove: (_, _) async {},
            onExternalDrag: (_) {},
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        // The old E2E locator finds the text, but in Details the transparent
        // interaction layer deliberately owns pointer input above that text.
        final label = find.text('file_0.txt');
        expect(label, findsOneWidget);
        if (mode == ViewMode.details) {
          expect(label.hitTestable(), findsNothing);
        }
        final viewport = await selectE2EFileBrowserItem(tester, file.path);
        expect(key.currentState!.selection.state.selectedFilePaths, {
          file.path,
        });
        expect(viewport, findsOneWidget);
        await tester.drag(viewport, const Offset(0, -100));
        await tester.pump();
        expect(viewport, findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
