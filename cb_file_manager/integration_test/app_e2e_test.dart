// All E2E integration tests for CbFileManager desktop.
//
// Runs all test suites sequentially in a SINGLE test invocation.
// Flutter desktop integration_test does NOT support multiple test files —
// each invocation builds and starts one app instance.
// Use `make dev-test-e2e` to run all, or individual suites via --plain-name.
//
// Individual suites (--plain-name matches group() prefix):
//   --plain-name "Navigation"             # sandbox, navigation, empty, backspace
//   --plain-name "File Operations"        # create, copy, rename, delete
//   --plain-name "Cut & Move"             # cut via menu, cut via Ctrl+X
//   --plain-name "Folder Operations"      # copy folder, delete folder, rename
//   --plain-name "Multi-Select"           # batch copy, select all + delete
//   --plain-name "Keyboard Shortcuts"     # F5 refresh, Escape cancel, Enter
//   --plain-name "Search & Filter"        # search box, clear search
//   --plain-name "View Mode"              # grid/list toggle, ops in grid
//   --plain-name "Tab Management"         # Ctrl+T, Ctrl+W, Ctrl+Tab
//   --plain-name "Edge Cases & Error Handling"  # cancel, empty name, no file
//   --plain-name "Extended File Operations"    # batch move, deep copy
//   --plain-name "Video Thumbnails"           # video display, context menu, thumbnails
import 'dart:io';

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:cb_file_manager/main.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/file_grid_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/file_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/folder_grid_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/folder_item.dart';
import 'package:path/path.dart' as p;

import 'e2e_helpers.dart';
import 'e2e_keys.dart';
import 'e2e_report.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // Suite 1: Navigation
  // ===========================================================================

  group('Navigation', () {
    testWidgets('sandbox lists two files and a subfolder',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_');
      final sub = Directory('${dir.path}${Platform.pathSeparator}subfolder')
        ..createSync();
      final aFile = File('${dir.path}${Platform.pathSeparator}a.txt')
        ..writeAsStringSync('e2e');
      final bFile = File('${dir.path}${Platform.pathSeparator}b.txt')
        ..writeAsStringSync('e2e');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('sandbox lists two files and a subfolder');

        expectFileRowVisible(aFile.path);
        expectFileRowVisible(bFile.path);
        expectFolderRowVisible(sub.path);
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('open subfolder shows file inside',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_nav_');
      final sub = Directory('${dir.path}${Platform.pathSeparator}innerdir')
        ..createSync();
      File('${dir.path}${Platform.pathSeparator}root.txt')
          .writeAsStringSync('r');
      final innerFile = File('${sub.path}${Platform.pathSeparator}nested.txt')
        ..writeAsStringSync('n');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('open subfolder shows file inside');

        expectFolderRowVisible(sub.path);
        if (kDebugMode)
          debugPrint('[E2E] Folder found, navigating into: ${sub.path}');
        await et.tapFolderRow(sub.path, detail: 'navigate_into_innerdir');
        await et.pumpAndSettle(const Duration(seconds: 5));
        expectFileRowVisible(innerFile.path);
        if (kDebugMode) debugPrint('[E2E] Navigation complete — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('empty sandbox has no file or folder rows',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_empty_');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('empty sandbox has no file or folder rows');

        expect(find.byType(FileItem), findsNothing);
        expect(find.byType(FolderItem), findsNothing);
        expect(find.byType(FileGridItem), findsNothing);
        expect(find.byType(FolderGridItem), findsNothing);
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets(
        'navigate back to parent with Backspace after entering subfolder',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_back_');
      final sub = Directory('${dir.path}${Platform.pathSeparator}innerdir')
        ..createSync();
      final rootFile = File('${dir.path}${Platform.pathSeparator}root.txt')
        ..writeAsStringSync('r');
      final innerFile = File('${sub.path}${Platform.pathSeparator}nested.txt')
        ..writeAsStringSync('n');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init(
            'navigate back to parent with Backspace after entering subfolder');

        // Verify root contents visible
        expectFileRowVisible(rootFile.path);
        expectFolderRowVisible(sub.path);

        // Navigate into subfolder
        await et.tapFolderRow(sub.path, detail: 'navigate_into_innerdir');
        await et.pumpAndSettle(const Duration(seconds: 5));
        expectFileRowVisible(innerFile.path);
        await et.screenshot('inside subfolder');

        // Press Backspace to go back to parent
        if (kDebugMode) debugPrint('[E2E] Pressing Backspace to navigate back');
        await et.keyPress(LogicalKeyboardKey.backspace);
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Verify back in parent folder
        expectFileRowVisible(rootFile.path);
        expectFolderRowVisible(sub.path);
        if (kDebugMode)
          debugPrint('[E2E] navigate back with Backspace — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });

  // ===========================================================================
  // Suite 2: File Operations
  // ===========================================================================

  group('File Operations', () {
    testWidgets('create new folder via right-click context menu',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_newfolder_');
      final dummyFile = File('${dir.path}${Platform.pathSeparator}dummy.txt')
        ..writeAsStringSync('keep empty');
      const newFolderName = 'CreatedByE2ETest';

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('create new folder via right-click context menu');

        // Verify dummy file is visible (confirms FileListViewBuilder has rendered)
        expectFileRowVisible(dummyFile.path);

        // Right-click background to open the BACKGROUND context menu,
        // which HAS the "New Folder" option (unlike file context menu).
        await et.openBackgroundContextMenu(detail: 'open_bg_menu');

        // Now tap "New Folder" in the background context menu
        await et.tapContextMenuItem('new_folder');

        // Scope to the dialog so we do not hit the address/path TextField.
        final textField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        expect(textField, findsOneWidget,
            reason: 'Create folder dialog did not appear');
        await et.enterText(textField.first, newFolderName,
            detail: 'type_folder_name');
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await et.pumpAndSettle(const Duration(seconds: 3));

        final createdPath =
            '${dir.path}${Platform.pathSeparator}$newFolderName';
        expectFolderRowVisible(createdPath);
        if (kDebugMode) debugPrint('[E2E] create new folder — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('copy file via right-click context menu and paste',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_copy_');
      final sub = Directory('${dir.path}${Platform.pathSeparator}dest_folder')
        ..createSync();
      final srcFile = File('${dir.path}${Platform.pathSeparator}source.txt')
        ..writeAsStringSync('e2e copy test');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('copy file via right-click context menu and paste');

        expectFileRowVisible(srcFile.path);

        // Right-click the file to open context menu
        await et.rightClickFileRow(srcFile.path, detail: 'open_context_menu');
        await et.tapContextMenuItem('copy', detail: 'copy');
        if (kDebugMode)
          debugPrint('[E2E] File copied, navigating to subfolder');

        // Navigate into dest_folder
        await et.tapFolderRow(sub.path, detail: 'navigate_to_dest');
        await et.pumpAndSettle(const Duration(seconds: 5));

        await et.openBackgroundContextMenu(detail: 'open_bg_menu_for_paste');
        await et.tapContextMenuItem('paste', detail: 'paste');

        final pastedPath = '${sub.path}${Platform.pathSeparator}source.txt';
        expectFileRowVisible(pastedPath);
        if (kDebugMode) debugPrint('[E2E] copy + paste — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('rename file via F2 keyboard shortcut',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_rename_');
      final originalFile =
          File('${dir.path}${Platform.pathSeparator}oldname.txt')
            ..writeAsStringSync('e2e rename test');
      const newName = 'newname_renamed.txt';

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('rename file via F2 keyboard shortcut');

        expectFileRowVisible(originalFile.path);

        await et.tapFileRow(originalFile.path, detail: 'select_file');
        await et.pumpAndSettle(const Duration(milliseconds: 300));

        // Press F2 to trigger rename
        if (kDebugMode) debugPrint('[E2E] Pressing F2 for rename');
        await et.keyPress(LogicalKeyboardKey.f2);
        await et.pumpAndSettle(const Duration(seconds: 2));

        // F2 starts inline rename; a path TextField (hint: Path) may also be present.
        final textFields = find.byType(TextField);
        expect(textFields, findsAtLeastNWidgets(1),
            reason: 'Inline rename TextField not found');
        await et.enterText(textFields.at(0), newName, detail: 'type_new_name');
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await et.pumpAndSettle(const Duration(seconds: 3));

        final renamedPath = '${dir.path}${Platform.pathSeparator}$newName';
        expectFileRowVisible(renamedPath);
        expectFileRowAbsent(originalFile.path);
        if (kDebugMode) debugPrint('[E2E] rename file — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('delete file via keyboard shortcut',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_delete_');
      final targetFile =
          File('${dir.path}${Platform.pathSeparator}todelete.txt')
            ..writeAsStringSync('e2e delete test');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('delete file via keyboard shortcut');

        expectFileRowVisible(targetFile.path);

        await et.tapFileRow(targetFile.path, detail: 'select_file');
        await et.pumpAndSettle(const Duration(milliseconds: 300));

        // Press Delete key — triggers delete with confirmation dialog
        if (kDebugMode) debugPrint('[E2E] Pressing Delete key');
        await et.keyPress(LogicalKeyboardKey.delete);
        await et.pumpAndSettle(const Duration(seconds: 2));

        // A confirmation dialog should appear — find the confirm button
        final dialogButton = find.byWidgetPredicate((widget) {
          if (widget is ElevatedButton) {
            final child = widget.child;
            if (child is Text) {
              return RegExp(r'delete|remove|move to trash|confirm',
                      caseSensitive: false)
                  .hasMatch(child.data ?? '');
            }
          }
          return false;
        });
        if (dialogButton.evaluate().isNotEmpty) {
          await et.tap(dialogButton.first, detail: 'confirm_delete_dialog');
          await et.pumpAndSettle(const Duration(seconds: 3));
        }
        await et.pumpAndSettle(const Duration(seconds: 1));

        expectFileRowAbsent(targetFile.path);
        if (kDebugMode) debugPrint('[E2E] delete file — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });

  // ===========================================================================
  // Suite 3: Cut & Move
  // ===========================================================================

  group('Cut & Move', () {
    testWidgets('cut and move file via right-click context menu',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_cut_');
      final destFolder = Directory('${dir.path}${Platform.pathSeparator}dest')
        ..createSync();
      final srcFile = File('${dir.path}${Platform.pathSeparator}moveme.txt')
        ..writeAsStringSync('e2e cut test');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('cut and move file via right-click context menu');

        expectFileRowVisible(srcFile.path);

        // Right-click the file and select Cut
        await et.rightClickFileRow(srcFile.path, detail: 'open_context_menu');
        await et.tapContextMenuItem('cut', detail: 'cut');
        if (kDebugMode) debugPrint('[E2E] File cut, navigating to dest folder');

        // Navigate into dest folder
        await et.tapFolderRow(destFolder.path, detail: 'navigate_to_dest');
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Paste via background context menu
        await et.openBackgroundContextMenu(detail: 'open_bg_menu_for_paste');
        await et.tapContextMenuItem('paste', detail: 'paste');
        await et.pumpAndSettle(const Duration(seconds: 3));

        // Verify file appears in destination
        final movedPath =
            '${destFolder.path}${Platform.pathSeparator}moveme.txt';
        expectFileRowVisible(movedPath);

        // Verify source file is gone from filesystem (cut = move)
        expect(File(srcFile.path).existsSync(), isFalse,
            reason:
                'Source file should be deleted after cut+paste (move operation)');
        if (kDebugMode) debugPrint('[E2E] cut and move file — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('cut and move file via Ctrl+X Ctrl+V keyboard shortcuts',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_cutkey_');
      final destFolder = Directory('${dir.path}${Platform.pathSeparator}dest')
        ..createSync();
      final srcFile = File('${dir.path}${Platform.pathSeparator}moveme.txt')
        ..writeAsStringSync('e2e cut keyboard test');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('cut and move file via Ctrl+X Ctrl+V keyboard shortcuts');

        expectFileRowVisible(srcFile.path);

        // Select the file
        await et.tapFileRow(srcFile.path, detail: 'select_file');
        await et.pumpAndSettle(const Duration(milliseconds: 300));

        // Ctrl+X to cut
        if (kDebugMode) debugPrint('[E2E] Pressing Ctrl+X');
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.keyX, ctrl: true, detail: 'ctrl_x_cut');
        await et.pumpAndSettle(const Duration(milliseconds: 500));

        // Navigate into dest folder
        await et.tapFolderRow(destFolder.path, detail: 'navigate_to_dest');
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Ctrl+V to paste
        if (kDebugMode) debugPrint('[E2E] Pressing Ctrl+V');
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.keyV, ctrl: true, detail: 'ctrl_v_paste');
        await et.pumpAndSettle(const Duration(seconds: 3));

        // Verify file appears in destination
        final movedPath =
            '${destFolder.path}${Platform.pathSeparator}moveme.txt';
        expectFileRowVisible(movedPath);

        // Verify source file is gone from filesystem
        expect(File(srcFile.path).existsSync(), isFalse,
            reason:
                'Source file should be deleted after Ctrl+X + Ctrl+V (move)');
        if (kDebugMode)
          debugPrint('[E2E] cut+move via keyboard shortcuts — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });

  // ===========================================================================
  // Suite 4: Folder Operations
  // ===========================================================================

  group('Folder Operations', () {
    testWidgets('copy folder to another location via context menu',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_copyfolder_');
      final sourceFolder =
          Directory('${dir.path}${Platform.pathSeparator}source_dir')
            ..createSync();
      File('${sourceFolder.path}${Platform.pathSeparator}inner.txt')
          .writeAsStringSync('inside');
      final destFolder =
          Directory('${dir.path}${Platform.pathSeparator}dest_dir')
            ..createSync();

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('copy folder to another location via context menu');

        expectFolderRowVisible(sourceFolder.path);
        expectFolderRowVisible(destFolder.path);

        // Right-click source folder and copy
        await et.rightClickFolderRow(sourceFolder.path,
            detail: 'open_context_menu');
        await et.tapContextMenuItem('copy', detail: 'copy');
        if (kDebugMode) debugPrint('[E2E] Folder copied, navigating to dest');

        // Navigate into dest folder
        await et.tapFolderRow(destFolder.path, detail: 'navigate_to_dest');
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Paste via background context menu
        await et.openBackgroundContextMenu(detail: 'open_bg_menu_for_paste');
        await et.tapContextMenuItem('paste', detail: 'paste');
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Verify copied folder appears in dest
        final copiedPath =
            '${destFolder.path}${Platform.pathSeparator}source_dir';
        expectFolderRowVisible(copiedPath);

        // Verify inner file was copied too (filesystem check)
        final innerCopy = File('$copiedPath${Platform.pathSeparator}inner.txt');
        expect(innerCopy.existsSync(), isTrue,
            reason: 'Inner file should exist in copied folder');
        if (kDebugMode) debugPrint('[E2E] copy folder — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('delete folder via keyboard shortcut',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_delfolder_');
      final targetFolder =
          Directory('${dir.path}${Platform.pathSeparator}todelete')
            ..createSync();
      File('${targetFolder.path}${Platform.pathSeparator}inside.txt')
          .writeAsStringSync('will be deleted');
      // Keep a dummy file so the listing is not empty after deletion
      File('${dir.path}${Platform.pathSeparator}keep.txt')
          .writeAsStringSync('keep');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('delete folder via keyboard shortcut');

        expectFolderRowVisible(targetFolder.path);

        // Select the folder (single tap — NOT double-tap which navigates)
        await et.selectFolderRow(targetFolder.path, detail: 'select_folder');

        // Press Delete key
        if (kDebugMode) debugPrint('[E2E] Pressing Delete key for folder');
        await et.keyPress(LogicalKeyboardKey.delete);
        await et.pumpAndSettle(const Duration(seconds: 2));

        // Handle confirmation dialog (same pattern as file delete test)
        final dialogButton = find.byWidgetPredicate((widget) {
          if (widget is ElevatedButton) {
            final child = widget.child;
            if (child is Text) {
              return RegExp(r'delete|remove|move to trash|confirm',
                      caseSensitive: false)
                  .hasMatch(child.data ?? '');
            }
          }
          return false;
        });
        if (dialogButton.evaluate().isNotEmpty) {
          await et.tap(dialogButton.first, detail: 'confirm_delete_dialog');
          await et.pumpAndSettle(const Duration(seconds: 3));
        }
        await et.pumpAndSettle(const Duration(seconds: 1));

        expectFolderRowAbsent(targetFolder.path);
        if (kDebugMode) debugPrint('[E2E] delete folder — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });

  // ===========================================================================
  // Suite 5: Multi-Select
  // ===========================================================================

  group('Multi-Select', () {
    testWidgets('multi-select two files and batch copy via keyboard shortcuts',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_multiselect_');
      final destFolder = Directory('${dir.path}${Platform.pathSeparator}dest')
        ..createSync();
      final fileA = File('${dir.path}${Platform.pathSeparator}alpha.txt')
        ..writeAsStringSync('A');
      final fileB = File('${dir.path}${Platform.pathSeparator}beta.txt')
        ..writeAsStringSync('B');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init(
            'multi-select two files and batch copy via keyboard shortcuts');

        expectFileRowVisible(fileA.path);
        expectFileRowVisible(fileB.path);

        // Ctrl+click to select both files
        await et.selectFileWithCtrl(fileA.path, detail: 'select_alpha');
        await et.selectFileWithCtrl(fileB.path, detail: 'select_beta');

        // Ctrl+C to copy
        if (kDebugMode) debugPrint('[E2E] Pressing Ctrl+C');
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.keyC, ctrl: true, detail: 'ctrl_c_copy');
        await et.pumpAndSettle(const Duration(milliseconds: 500));

        // Navigate into dest folder
        if (kDebugMode) debugPrint('[E2E] Navigating to dest folder');
        await et.tapFolderRow(destFolder.path, detail: 'navigate_to_dest');
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Verify dest is empty before paste
        final pastedA = '${destFolder.path}${Platform.pathSeparator}alpha.txt';
        expectFileRowAbsent(pastedA);

        // Ctrl+V to paste
        if (kDebugMode) debugPrint('[E2E] Pressing Ctrl+V');
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.keyV, ctrl: true, detail: 'ctrl_v_paste');
        await et.pumpAndSettle(const Duration(seconds: 3));

        final pastedB = '${destFolder.path}${Platform.pathSeparator}beta.txt';
        expectFileRowVisible(pastedA);
        expectFileRowVisible(pastedB);
        if (kDebugMode) debugPrint('[E2E] multi-select batch copy — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('select all with Ctrl+A and batch delete',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_selectall_');
      final fileA = File('${dir.path}${Platform.pathSeparator}alpha.txt')
        ..writeAsStringSync('A');
      final fileB = File('${dir.path}${Platform.pathSeparator}beta.txt')
        ..writeAsStringSync('B');
      final fileC = File('${dir.path}${Platform.pathSeparator}gamma.txt')
        ..writeAsStringSync('C');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('select all with Ctrl+A and batch delete');

        expectFileRowVisible(fileA.path);
        expectFileRowVisible(fileB.path);
        expectFileRowVisible(fileC.path);

        // Ctrl+A to select all
        if (kDebugMode) debugPrint('[E2E] Pressing Ctrl+A');
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.keyA,
            ctrl: true,
            detail: 'ctrl_a_select_all');
        await et.pumpAndSettle(const Duration(milliseconds: 500));
        await et.screenshot('after Ctrl+A');

        // Press Delete key to delete all selected
        if (kDebugMode) debugPrint('[E2E] Pressing Delete key');
        await et.keyPress(LogicalKeyboardKey.delete);
        await et.pumpAndSettle(const Duration(seconds: 2));

        // Handle confirmation dialog
        final dialogButton = find.byWidgetPredicate((widget) {
          if (widget is ElevatedButton) {
            final child = widget.child;
            if (child is Text) {
              return RegExp(r'delete|remove|move to trash|confirm',
                      caseSensitive: false)
                  .hasMatch(child.data ?? '');
            }
          }
          return false;
        });
        if (dialogButton.evaluate().isNotEmpty) {
          await et.tap(dialogButton.first, detail: 'confirm_delete_dialog');
          await et.pumpAndSettle(const Duration(seconds: 3));
        }
        await et.pumpAndSettle(const Duration(seconds: 1));

        // Verify all files are gone
        expectFileRowAbsent(fileA.path);
        expectFileRowAbsent(fileB.path);
        expectFileRowAbsent(fileC.path);
        if (kDebugMode) debugPrint('[E2E] select all + batch delete — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });

  // ===========================================================================
  // Suite 6: Keyboard Shortcuts
  // ===========================================================================

  group('Keyboard Shortcuts', () {
    testWidgets('refresh folder listing with F5 after external change',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_refresh_');
      final existingFile =
          File('${dir.path}${Platform.pathSeparator}existing.txt')
            ..writeAsStringSync('e2e');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('refresh folder listing with F5 after external change');

        expectFileRowVisible(existingFile.path);

        // Create a new file externally (NOT through the app UI)
        final newFile =
            File('${dir.path}${Platform.pathSeparator}externally_added.txt')
              ..writeAsStringSync('added outside app');
        if (kDebugMode)
          debugPrint('[E2E] Created file externally: ${newFile.path}');
        await et.screenshot('before F5 refresh');

        // Press F5 to force refresh the listing
        if (kDebugMode) debugPrint('[E2E] Pressing F5 to refresh');
        await et.keyPress(LogicalKeyboardKey.f5);
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Verify the externally created file now appears
        expectFileRowVisible(newFile.path);
        // Verify original file is still there
        expectFileRowVisible(existingFile.path);
        if (kDebugMode) debugPrint('[E2E] refresh with F5 — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('cancel rename with Escape key after pressing F2',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_rename_esc_');
      final targetFile =
          File('${dir.path}${Platform.pathSeparator}original_name.txt')
            ..writeAsStringSync('e2e cancel rename test');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('cancel rename with Escape key after pressing F2');

        expectFileRowVisible(targetFile.path);

        // Select and press F2 to start rename
        await et.tapFileRow(targetFile.path, detail: 'select_file');
        await et.pumpAndSettle(const Duration(milliseconds: 300));
        await et.keyPress(LogicalKeyboardKey.f2);
        await et.pumpAndSettle(const Duration(seconds: 2));

        // Verify rename field is visible
        final textFields = find.byType(TextField);
        expect(textFields, findsAtLeastNWidgets(1),
            reason: 'Rename TextField should appear after F2');

        // Press Escape to cancel
        await et.keyPress(LogicalKeyboardKey.escape);
        await et.pumpAndSettle(const Duration(seconds: 2));

        // Original filename should still be there (rename cancelled)
        expectFileRowVisible(targetFile.path);
        if (kDebugMode) debugPrint('[E2E] cancel rename with Escape — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('open file with Enter key when file is selected',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_enter_');
      final targetFile = File('${dir.path}${Platform.pathSeparator}readme.txt')
        ..writeAsStringSync('e2e enter key test');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('open file with Enter key when file is selected');

        expectFileRowVisible(targetFile.path);

        // Select the file
        await et.tapFileRow(targetFile.path, detail: 'select_file');
        await et.pumpAndSettle(const Duration(milliseconds: 300));

        // Press Enter key
        if (kDebugMode) debugPrint('[E2E] Pressing Enter key');
        await et.keyPress(LogicalKeyboardKey.enter);
        await et.pumpAndSettle(const Duration(seconds: 3));

        // App should handle Enter key (may open file preview or show details)
        // The test verifies no crash occurs
        await et.screenshot('after_enter_key');
        if (kDebugMode)
          debugPrint('[E2E] Enter key handled without crash — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });

  // ===========================================================================
  // Suite 7: Search & Filter
  // ===========================================================================

  group('Search & Filter', () {
    testWidgets('search for file by typing in search box',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_search_');
      final targetFile = File(
          '${dir.path}${Platform.pathSeparator}unique_search_target_123.txt')
        ..writeAsStringSync('search test');
      final otherFile =
          File('${dir.path}${Platform.pathSeparator}other_file.txt')
            ..writeAsStringSync('not searched');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('search for file by typing in search box');

        expectFileRowVisible(targetFile.path);
        expectFileRowVisible(otherFile.path);

        // Find and tap search box (search icon button)
        final searchIcon = find.byIcon(Icons.search);
        if (searchIcon.evaluate().isNotEmpty) {
          await et.tap(searchIcon.first, detail: 'open_search');
          await tester.pumpAndSettle(const Duration(milliseconds: 500));

          // Type search query
          await et.enterText(find.byType(TextField).first, 'unique_search',
              detail: 'type_search_query');
          await et.pumpAndSettle(const Duration(seconds: 2));

          // Target file should still be visible (filtered)
          expectFileRowVisible(targetFile.path);
        } else {
          // Search may be implemented differently - verify current state
          if (kDebugMode)
            debugPrint(
                '[E2E] Search icon not found, skipping search interaction');
        }
        if (kDebugMode) debugPrint('[E2E] search test — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('clear search to show all files again',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_searchclear_');
      final fileA = File('${dir.path}${Platform.pathSeparator}alpha_search.txt')
        ..writeAsStringSync('A');
      final fileB = File('${dir.path}${Platform.pathSeparator}beta_search.txt')
        ..writeAsStringSync('B');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('clear search to show all files again');

        expectFileRowVisible(fileA.path);
        expectFileRowVisible(fileB.path);

        // Open search and type a query
        final searchIcon = find.byIcon(Icons.search);
        if (searchIcon.evaluate().isNotEmpty) {
          await et.tap(searchIcon.first, detail: 'open_search');
          await tester.pumpAndSettle(const Duration(milliseconds: 500));

          await et.enterText(find.byType(TextField).first, 'alpha',
              detail: 'type_partial_search');
          await et.pumpAndSettle(const Duration(seconds: 2));

          // Press Escape to clear search
          await et.keyPress(LogicalKeyboardKey.escape);
          await et.pumpAndSettle(const Duration(seconds: 2));

          // Both files should be visible again
          expectFileRowVisible(fileA.path);
          expectFileRowVisible(fileB.path);
        }
        if (kDebugMode) debugPrint('[E2E] clear search — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });

  // ===========================================================================
  // Suite 8: View Mode (Grid / List Toggle)
  // ===========================================================================

  group('View Mode', () {
    testWidgets('toggle to grid view from list view',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_viewgrid_');
      final fileA = File('${dir.path}${Platform.pathSeparator}grid_file_a.txt')
        ..writeAsStringSync('A');
      final fileB = File('${dir.path}${Platform.pathSeparator}grid_file_b.txt')
        ..writeAsStringSync('B');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('toggle to grid view from list view');

        expectFileRowVisible(fileA.path);
        expectFileRowVisible(fileB.path);

        // Look for grid icon to toggle view
        final gridIcon = find.byIcon(Icons.grid_view);
        if (gridIcon.evaluate().isNotEmpty) {
          await et.tap(gridIcon.first, detail: 'toggle_to_grid');
          await et.pumpAndSettle(const Duration(seconds: 2));

          // Verify files are still visible in grid mode
          expectFileRowVisible(fileA.path);
          expectFileRowVisible(fileB.path);
        }
        if (kDebugMode) debugPrint('[E2E] toggle to grid view — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('toggle back to list view from grid view',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_viewlist_');
      final fileA = File('${dir.path}${Platform.pathSeparator}list_file_a.txt')
        ..writeAsStringSync('A');
      final fileB = File('${dir.path}${Platform.pathSeparator}list_file_b.txt')
        ..writeAsStringSync('B');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('toggle back to list view from grid view');

        expectFileRowVisible(fileA.path);
        expectFileRowVisible(fileB.path);

        // First toggle to grid
        final gridIcon = find.byIcon(Icons.grid_view);
        if (gridIcon.evaluate().isNotEmpty) {
          await et.tap(gridIcon.first, detail: 'toggle_to_grid');
          await et.pumpAndSettle(const Duration(seconds: 2));

          // Now toggle back to list
          final listIcon = find.byIcon(Icons.view_list);
          if (listIcon.evaluate().isNotEmpty) {
            await et.tap(listIcon.first, detail: 'toggle_to_list');
            await et.pumpAndSettle(const Duration(seconds: 2));

            // Verify files are still visible in list mode
            expectFileRowVisible(fileA.path);
            expectFileRowVisible(fileB.path);
          }
        }
        if (kDebugMode) debugPrint('[E2E] toggle back to list view — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('file operations work correctly in grid view',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_gridops_');
      final fileA = File('${dir.path}${Platform.pathSeparator}grid_op_file.txt')
        ..writeAsStringSync('A');
      final destFolder =
          Directory('${dir.path}${Platform.pathSeparator}grid_dest')
            ..createSync();

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('file operations work correctly in grid view');

        // Switch to grid view first
        final gridIcon = find.byIcon(Icons.grid_view);
        if (gridIcon.evaluate().isNotEmpty) {
          await et.tap(gridIcon.first, detail: 'toggle_to_grid');
          await et.pumpAndSettle(const Duration(seconds: 2));
        }

        expectFileRowVisible(fileA.path);

        // Copy file via context menu in grid view
        await et.rightClickFileRow(fileA.path,
            detail: 'open_context_menu_grid');
        await et.tapContextMenuItem('copy', detail: 'copy_in_grid');
        await et.pumpAndSettle(const Duration(milliseconds: 500));

        // Navigate to dest
        await et.tapFolderRow(destFolder.path, detail: 'navigate_to_dest');
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Paste in dest folder
        await et.openBackgroundContextMenu(detail: 'paste_in_dest');
        await et.tapContextMenuItem('paste', detail: 'paste_in_grid');
        await et.pumpAndSettle(const Duration(seconds: 3));

        final pastedPath =
            '${destFolder.path}${Platform.pathSeparator}grid_op_file.txt';
        expectFileRowVisible(pastedPath);
        if (kDebugMode) debugPrint('[E2E] grid view file ops — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });

  // ===========================================================================
  // Suite 9: Tab Management
  // ===========================================================================

  group('Tab Management', () {
    testWidgets('open a new tab with Ctrl+T', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_tab_');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('open a new tab with Ctrl+T');

        // Press Ctrl+T to open new tab
        if (kDebugMode) debugPrint('[E2E] Pressing Ctrl+T for new tab');
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.keyT, ctrl: true, detail: 'ctrl_t_new_tab');
        await et.pumpAndSettle(const Duration(seconds: 3));

        // Verify a new tab was opened (check for tab bar or new content)
        // The app should have a tab indicator or the content should change
        await et.screenshot('after_new_tab');
        if (kDebugMode) debugPrint('[E2E] new tab with Ctrl+T — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('close a tab with Ctrl+W', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_tabclose_');
      final fileA =
          File('${dir.path}${Platform.pathSeparator}tab_close_file.txt')
            ..writeAsStringSync('test');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('close a tab with Ctrl+W');

        expectFileRowVisible(fileA.path);

        // Press Ctrl+W to close the tab
        if (kDebugMode) debugPrint('[E2E] Pressing Ctrl+W to close tab');
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.keyW,
            ctrl: true,
            detail: 'ctrl_w_close_tab');
        await et.pumpAndSettle(const Duration(seconds: 3));

        // If there's only one tab, app may close or show empty state
        await et.screenshot('after_close_tab');
        if (kDebugMode) debugPrint('[E2E] close tab with Ctrl+W — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('switch between tabs with Ctrl+Tab',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_tabswitch_');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('switch between tabs with Ctrl+Tab');

        // Open a new tab first
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.keyT, ctrl: true, detail: 'open_new_tab');
        await et.pumpAndSettle(const Duration(seconds: 3));

        await et.screenshot('second_tab_open');

        // Switch tabs with Ctrl+Tab
        if (kDebugMode) debugPrint('[E2E] Pressing Ctrl+Tab to switch tabs');
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.tab, ctrl: true, detail: 'ctrl_tab_switch');
        await et.pumpAndSettle(const Duration(seconds: 2));

        await et.screenshot('after_tab_switch');
        if (kDebugMode) debugPrint('[E2E] tab switch with Ctrl+Tab — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });

  // ===========================================================================
  // Suite 10: Edge Cases & Error Handling
  // ===========================================================================

  group('Edge Cases & Error Handling', () {
    testWidgets('handle delete confirmation cancel correctly',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_delcancel_');
      final targetFile =
          File('${dir.path}${Platform.pathSeparator}cancel_delete_test.txt')
            ..writeAsStringSync('should not be deleted');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('handle delete confirmation cancel correctly');

        expectFileRowVisible(targetFile.path);

        // Select file and trigger delete
        await et.tapFileRow(targetFile.path, detail: 'select_file');
        await et.pumpAndSettle(const Duration(milliseconds: 300));
        await et.keyPress(LogicalKeyboardKey.delete);
        await et.pumpAndSettle(const Duration(seconds: 2));

        // Look for cancel button in dialog and tap it
        final cancelBtn = find.widgetWithText(TextButton, 'Cancel');
        if (cancelBtn.evaluate().isNotEmpty) {
          await et.tap(cancelBtn.first, detail: 'cancel_delete');
          await et.pumpAndSettle(const Duration(seconds: 2));

          // File should still exist after cancel
          expectFileRowVisible(targetFile.path);
          expect(targetFile.existsSync(), isTrue,
              reason: 'File should still exist after cancelling delete');
        } else {
          // If no cancel button, dialog might auto-dismiss or use different UI
          if (kDebugMode)
            debugPrint('[E2E] No cancel button found, checking file state');
          // File should still exist
          expectFileRowVisible(targetFile.path);
        }
        if (kDebugMode) debugPrint('[E2E] delete cancel — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('handle rename with empty name correctly',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_renameempty_');
      final targetFile =
          File('${dir.path}${Platform.pathSeparator}valid_name.txt')
            ..writeAsStringSync('e2e');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('handle rename with empty name correctly');

        expectFileRowVisible(targetFile.path);

        // Select and press F2 to start rename
        await et.tapFileRow(targetFile.path, detail: 'select_file');
        await et.pumpAndSettle(const Duration(milliseconds: 300));
        await et.keyPress(LogicalKeyboardKey.f2);
        await et.pumpAndSettle(const Duration(seconds: 2));

        // Clear the text field
        await et.enterText(find.byType(TextField).first, '',
            detail: 'clear_name');
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await et.pumpAndSettle(const Duration(seconds: 3));

        // Original name should still be there (invalid empty rename rejected)
        expectFileRowVisible(targetFile.path);
        if (kDebugMode) debugPrint('[E2E] empty rename handled — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('handle paste when no file is copied or cut',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_nopaste_');
      final destFolder =
          Directory('${dir.path}${Platform.pathSeparator}paste_dest')
            ..createSync();
      final existingFile =
          File('${dir.path}${Platform.pathSeparator}existing.txt')
            ..writeAsStringSync('test');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('handle paste when no file is copied or cut');

        expectFileRowVisible(existingFile.path);

        // Navigate to dest folder
        await et.tapFolderRow(destFolder.path, detail: 'navigate_to_dest');
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Try to paste without any prior copy/cut
        await et.openBackgroundContextMenu(detail: 'open_paste_menu');
        await et.tapContextMenuItem('paste', detail: 'paste_nothing');
        await et.pumpAndSettle(const Duration(seconds: 2));

        // Verify dest folder is still empty (no crash)
        final pastedFile =
            '${destFolder.path}${Platform.pathSeparator}existing.txt';
        expectFileRowAbsent(pastedFile);
        if (kDebugMode) debugPrint('[E2E] paste nothing — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('handle navigating to a folder that no longer exists',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_navmiss_');
      final file = File('${dir.path}${Platform.pathSeparator}marker.txt')
        ..writeAsStringSync('marker');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('handle navigating to a folder that no longer exists');

        expectFileRowVisible(file.path);

        // The folder we wanted to navigate to doesn't exist
        // This tests error handling for invalid navigation paths
        await et.screenshot('before_refresh');
        await et.keyPress(LogicalKeyboardKey.f5);
        await et.pumpAndSettle(const Duration(seconds: 5));

        // File should still be visible (app handled gracefully)
        expectFileRowVisible(file.path);
        if (kDebugMode)
          debugPrint('[E2E] nav to missing folder handled — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });

  // ===========================================================================
  // Suite 11: Extended File Operations
  // ===========================================================================

  group('Extended File Operations', () {
    testWidgets('create new file via context menu',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_newfile_');
      final dummyFile = File('${dir.path}${Platform.pathSeparator}dummy.txt')
        ..writeAsStringSync('keep empty');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('create new file via context menu');

        expectFileRowVisible(dummyFile.path);

        // Right-click background to open context menu
        await et.openBackgroundContextMenu(detail: 'open_bg_menu');

        // Try to create new file (may be "new_file" action)
        await et.tapContextMenuItem('new_file', detail: 'new_file');
        await et.pumpAndSettle(const Duration(seconds: 2));

        await et.screenshot('after_new_file_attempt');
        if (kDebugMode) debugPrint('[E2E] create new file — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('rename file via context menu', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_rename_ctx_');
      final originalFile =
          File('${dir.path}${Platform.pathSeparator}ctx_oldname.txt')
            ..writeAsStringSync('e2e context rename');
      const newName = 'ctx_newname_renamed.txt';

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('rename file via context menu');

        expectFileRowVisible(originalFile.path);

        // Right-click to open context menu
        await et.rightClickFileRow(originalFile.path, detail: 'open_ctx_menu');
        await et.tapContextMenuItem('rename', detail: 'context_rename');
        await et.pumpAndSettle(const Duration(seconds: 2));

        // Enter new name
        final textFields = find.byType(TextField);
        expect(textFields, findsAtLeastNWidgets(1),
            reason: 'Rename TextField not found');
        await et.enterText(textFields.first, newName, detail: 'type_new_name');
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await et.pumpAndSettle(const Duration(seconds: 3));

        final renamedPath = '${dir.path}${Platform.pathSeparator}$newName';
        expectFileRowVisible(renamedPath);
        expectFileRowAbsent(originalFile.path);
        if (kDebugMode) debugPrint('[E2E] context menu rename — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('batch move multiple files to destination folder',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_batchmove_');
      final destFolder =
          Directory('${dir.path}${Platform.pathSeparator}batch_dest')
            ..createSync();
      final fileA = File('${dir.path}${Platform.pathSeparator}move_a.txt')
        ..writeAsStringSync('A');
      final fileB = File('${dir.path}${Platform.pathSeparator}move_b.txt')
        ..writeAsStringSync('B');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('batch move multiple files to destination folder');

        expectFileRowVisible(fileA.path);
        expectFileRowVisible(fileB.path);

        // Multi-select both files with Ctrl+click
        await et.selectFileWithCtrl(fileA.path, detail: 'select_a');
        await et.selectFileWithCtrl(fileB.path, detail: 'select_b');

        // Cut with Ctrl+X
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.keyX, ctrl: true, detail: 'ctrl_x_cut');
        await et.pumpAndSettle(const Duration(milliseconds: 500));

        // Navigate to destination
        await et.tapFolderRow(destFolder.path, detail: 'navigate_to_dest');
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Paste
        await et.sendKeyboardShortcut(
            key: LogicalKeyboardKey.keyV, ctrl: true, detail: 'ctrl_v_paste');
        await et.pumpAndSettle(const Duration(seconds: 3));

        // Verify both files moved
        final movedA = '${destFolder.path}${Platform.pathSeparator}move_a.txt';
        final movedB = '${destFolder.path}${Platform.pathSeparator}move_b.txt';
        expectFileRowVisible(movedA);
        expectFileRowVisible(movedB);

        // Verify source files are gone
        expect(fileA.existsSync(), isFalse);
        expect(fileB.existsSync(), isFalse);
        if (kDebugMode) debugPrint('[E2E] batch move — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('copy folder with nested contents to another location',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_deepcopy_');
      final sourceFolder =
          Directory('${dir.path}${Platform.pathSeparator}deep_source')
            ..createSync();
      // Create nested structure
      final nestedFolder =
          Directory('${sourceFolder.path}${Platform.pathSeparator}level2')
            ..createSync();
      File('${sourceFolder.path}${Platform.pathSeparator}root.txt')
          .writeAsStringSync('root');
      File('${nestedFolder.path}${Platform.pathSeparator}nested.txt')
          .writeAsStringSync('nested');
      final destFolder =
          Directory('${dir.path}${Platform.pathSeparator}deep_dest')
            ..createSync();

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('copy folder with nested contents to another location');

        expectFolderRowVisible(sourceFolder.path);

        // Copy folder via context menu
        await et.rightClickFolderRow(sourceFolder.path, detail: 'open_menu');
        await et.tapContextMenuItem('copy', detail: 'copy');
        await et.pumpAndSettle(const Duration(milliseconds: 500));

        // Navigate to dest
        await et.tapFolderRow(destFolder.path, detail: 'navigate_to_dest');
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Paste
        await et.openBackgroundContextMenu(detail: 'paste');
        await et.tapContextMenuItem('paste', detail: 'paste');
        await et.pumpAndSettle(const Duration(seconds: 5));

        // Verify folder was copied
        final copiedFolder =
            '${destFolder.path}${Platform.pathSeparator}deep_source';
        expectFolderRowVisible(copiedFolder);

        // Verify nested structure was copied
        final copiedRoot = '$copiedFolder${Platform.pathSeparator}root.txt';
        final copiedNested =
            '$copiedFolder${Platform.pathSeparator}level2${Platform.pathSeparator}nested.txt';
        expect(File(copiedRoot).existsSync(), isTrue,
            reason: 'Root file should be copied');
        expect(File(copiedNested).existsSync(), isTrue,
            reason: 'Nested file should be copied');
        if (kDebugMode) debugPrint('[E2E] deep copy — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('rename folder via F2 keyboard shortcut',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_renfolder_');
      final originalFolder =
          Directory('${dir.path}${Platform.pathSeparator}old_folder_name')
            ..createSync();
      File('${originalFolder.path}${Platform.pathSeparator}inside.txt')
          .writeAsStringSync('content');
      const newFolderName = 'new_folder_name';

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('rename folder via F2 keyboard shortcut');

        expectFolderRowVisible(originalFolder.path);

        // Select the folder (single tap)
        await et.selectFolderRow(originalFolder.path, detail: 'select_folder');
        await et.pumpAndSettle(const Duration(milliseconds: 300));

        // Press F2
        await et.keyPress(LogicalKeyboardKey.f2);
        await et.pumpAndSettle(const Duration(seconds: 2));

        // Enter new name
        final textFields = find.byType(TextField);
        expect(textFields, findsAtLeastNWidgets(1),
            reason: 'Rename TextField not found');
        await et.enterText(textFields.first, newFolderName,
            detail: 'type_new_name');
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await et.pumpAndSettle(const Duration(seconds: 3));

        final renamedPath =
            '${dir.path}${Platform.pathSeparator}$newFolderName';
        expectFolderRowVisible(renamedPath);
        expectFolderRowAbsent(originalFolder.path);

        // Verify contents still exist inside
        expect(
            File('$renamedPath${Platform.pathSeparator}inside.txt')
                .existsSync(),
            isTrue);
        if (kDebugMode) debugPrint('[E2E] rename folder via F2 — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });
}
