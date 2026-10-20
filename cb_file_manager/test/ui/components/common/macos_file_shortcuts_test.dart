import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_keyboard_shortcuts.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_keyboard_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/desktop_keyboard_test_support.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
  for (final detailed in [false, true]) {
    platformTestWidgets(
      '${detailed ? "folder" : "basic"} surface uses shared Cmd file bindings',
      (tester) async {
        final controller = TabbedFolderKeyboardController();
        addTearDown(controller.dispose);
        final actions = <String>[];
        final state = FolderListState('/files', files: [File('/files/a.txt')]);
        await tester.pumpWidget(
          MaterialApp(
            home: Focus(
              autofocus: true,
              onKeyEvent: (_, event) => detailed
                  ? BrowserLikeKeyboardShortcuts.handle(
                      isDesktop: true,
                      keyboardController: controller,
                      folderListState: state,
                      selectionState: const SelectionState(),
                      currentFilter: null,
                      onBackInTabHistory: () => actions.add('back'),
                      focusFolderPath: (_) {},
                      focusFilePath: (_) {},
                      selectRange:
                          ({
                            required folderPaths,
                            required filePaths,
                            required lastSelectedPath,
                            required ctrlSelect,
                          }) {},
                      activateEntity: (_) => actions.add('open'),
                      onDelete: (permanent) => actions.add('delete:$permanent'),
                      onCopy: () => actions.add('copy'),
                      onCut: () => actions.add('cut'),
                      onPaste: () => actions.add('paste'),
                      onRename: () => actions.add('rename'),
                      onSelectAll: () => actions.add('all'),
                      onRefresh: () => actions.add('refresh'),
                      onSearch: () => actions.add('search'),
                      event: event,
                    )
                  : BrowserLikeKeyboardShortcuts.handleBasic(
                      isDesktop: true,
                      event: event,
                      onDelete: (permanent) => actions.add('delete:$permanent'),
                      onCopy: () => actions.add('copy'),
                      onCut: () => actions.add('cut'),
                      onPaste: () => actions.add('paste'),
                      onRename: () => actions.add('rename'),
                      onSelectAll: () => actions.add('all'),
                      onRefresh: () => actions.add('refresh'),
                      onSearch: () => actions.add('search'),
                    ),
              child: const SizedBox(),
            ),
          ),
        );
        await tester.pump();
        for (final key in [
          LogicalKeyboardKey.keyC,
          LogicalKeyboardKey.keyX,
          LogicalKeyboardKey.keyV,
          LogicalKeyboardKey.keyA,
          LogicalKeyboardKey.keyR,
          LogicalKeyboardKey.keyF,
        ]) {
          await press(
            tester,
            key,
            modifiers: [LogicalKeyboardKey.metaLeft],
            repeat: true,
          );
        }
        await press(tester, LogicalKeyboardKey.enter, repeat: true);
        await press(
          tester,
          LogicalKeyboardKey.backspace,
          modifiers: [LogicalKeyboardKey.metaLeft],
          repeat: true,
        );
        await press(
          tester,
          LogicalKeyboardKey.backspace,
          modifiers: [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.altLeft],
        );
        expect(actions, [
          'copy',
          'cut',
          'paste',
          'all',
          'refresh',
          'search',
          'rename',
          'delete:false',
          'delete:true',
        ]);
        final count = actions.length;
        await press(
          tester,
          LogicalKeyboardKey.keyV,
          modifiers: [
            LogicalKeyboardKey.metaLeft,
            LogicalKeyboardKey.shiftLeft,
          ],
        );
        await press(
          tester,
          LogicalKeyboardKey.backspace,
          modifiers: [
            LogicalKeyboardKey.metaLeft,
            LogicalKeyboardKey.shiftLeft,
          ],
        );
        expect(actions, hasLength(count));
      },
    );
  }

  platformTestWidgets(
    'Finder navigation never moves list focus when a modifier command runs',
    (tester) async {
      final controller = TabbedFolderKeyboardController();
      addTearDown(controller.dispose);
      final actions = <String>[];
      final file = File('/files/a.txt');
      controller.focusedPath = file.path;
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            autofocus: true,
            onKeyEvent: (_, event) => controller.handleKeyEvent(
              isDesktop: true,
              folderListState: FolderListState('/files', files: [file]),
              selectionState: const SelectionState(),
              currentFilter: null,
              onBackInTabHistory: () => actions.add('back'),
              onForwardInTabHistory: () => actions.add('forward'),
              onNavigateToParent: () => actions.add('parent'),
              onCreateFolder: () => actions.add('new-folder'),
              focusFolderPath: (_) => fail('no focus movement'),
              focusFilePath: (_) => fail('no focus movement'),
              selectRange:
                  ({
                    required folderPaths,
                    required filePaths,
                    required lastSelectedPath,
                    required ctrlSelect,
                  }) {},
              activateEntity: (entity) {
                expect(entity.path, file.path);
                actions.add('open');
              },
              onDelete: (_) => fail('not a delete'),
              event: event,
            ),
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.bracketLeft,
        LogicalKeyboardKey.bracketRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.keyO,
      ]) {
        await press(tester, key, modifiers: [LogicalKeyboardKey.metaLeft]);
      }
      await press(
        tester,
        LogicalKeyboardKey.keyN,
        modifiers: [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft],
      );
      expect(actions, [
        'back',
        'forward',
        'parent',
        'open',
        'open',
        'new-folder',
      ]);
    },
  );

  platformTestWidgets(
    'editing keeps Cmd delete/copy/select-all in the text field; Cmd+F still searches',
    (tester) async {
      var searches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            onKeyEvent: (_, event) => BrowserLikeKeyboardShortcuts.handleBasic(
              isDesktop: true,
              event: event,
              onDelete: (_) => fail('must edit text'),
              onCopy: () => fail('must copy text'),
              onSelectAll: () => fail('must select text'),
              onRename: () => fail('must submit input'),
              onSearch: () => searches++,
            ),
            child: const Scaffold(body: TextField(autofocus: true)),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'example');
      for (final key in [
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.keyF,
      ]) {
        await press(tester, key, modifiers: [LogicalKeyboardKey.metaLeft]);
      }
      expect(searches, 1);
      expect(tester.takeException(), isNull);
    },
  );

  platformTestWidgets(
    'Windows does not treat Meta as Ctrl or Return as rename',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            autofocus: true,
            onKeyEvent: (_, event) => BrowserLikeKeyboardShortcuts.handleBasic(
              isDesktop: true,
              event: event,
              onCopy: () => calls.add('copy'),
              onRename: () => calls.add('rename'),
              onDelete: (_) => calls.add('delete'),
            ),
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      await press(
        tester,
        LogicalKeyboardKey.keyC,
        modifiers: [LogicalKeyboardKey.metaLeft],
      );
      await press(tester, LogicalKeyboardKey.enter);
      await press(
        tester,
        LogicalKeyboardKey.backspace,
        modifiers: [LogicalKeyboardKey.metaLeft],
      );
      expect(calls, isEmpty);
      await press(
        tester,
        LogicalKeyboardKey.keyC,
        modifiers: [LogicalKeyboardKey.controlLeft],
      );
      await press(tester, LogicalKeyboardKey.f2);
      expect(calls, ['copy', 'rename']);
    },
  );
}
