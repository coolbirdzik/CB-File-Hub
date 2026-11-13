import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:cb_file_manager/ui/tab_manager/components/drive_avatar.dart';
import 'package:cb_file_manager/ui/components/common/file_entry_presentation.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/widgets/file_tree_view.dart';
import 'package:cb_file_manager/ui/widgets/miller_columns_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  late Directory root;
  late SelectionBloc selection;
  late TabbedFolderDragSelectionController drag;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cb-drive-hierarchy-');
    await Directory('${root.path}/Documents').create();
    selection = SelectionBloc();
    drag = TabbedFolderDragSelectionController(selectionBloc: selection);
  });
  tearDown(() async {
    drag.dispose();
    await selection.close();
    await root.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CbThemeBuilder.build(
          brightness: Brightness.light,
          accent: Colors.teal,
        ),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: BlocProvider.value(
          value: selection,
          child: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> waitForChildren(WidgetTester tester) async {
    for (var i = 0; i < 30 && find.text('Documents').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Documents'), findsOneWidget);
  }

  testWidgets('drive tree loads real children and routes root context menu', (
    tester,
  ) async {
    FileSystemEntity? menuEntity;
    await mount(
      tester,
      FileTreeView(
        state: FolderListState('#drives', folders: [root]),
        selectionState: const SelectionState(),
        isDesktopPlatform: true,
        onNavigateToPath: (_) {},
        onFileTap: (_, _) {},
        toggleFileSelection: (_, {shiftSelect = false, ctrlSelect = false}) {},
        toggleFolderSelection:
            (_, {shiftSelect = false, ctrlSelect = false}) {},
        clearSelection: () {},
        showContextMenu: (_, _) => fail('generic root menu'),
        onEntityContextMenu: (entity, _) => menuEntity = entity,
      ),
    );
    final caret = find.byIcon(PhosphorIconsLight.caretRight).first;
    await tester.tap(caret);
    await tester.pump();
    await waitForChildren(tester);
    final rootRow = find.text(root.path.split(Platform.pathSeparator).last);
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(tester.getCenter(rootRow));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(menuEntity?.path, root.path);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'drive columns browse children and retain drive-specific context actions',
    (tester) async {
      FileSystemEntity? menuEntity;
      await mount(
        tester,
        FileEntryPresentation(
          names: {root.path: 'Backup drive'},
          child: MillerColumnsView(
            state: FolderListState('#drives', folders: [root]),
            selectionState: const SelectionState(),
            isDesktopPlatform: true,
            onNavigateToPath: (_) {},
            onFileTap: (_, _) {},
            toggleFileSelection:
                (_, {shiftSelect = false, ctrlSelect = false}) {},
            toggleFolderSelection:
                (_, {shiftSelect = false, ctrlSelect = false}) {},
            clearSelection: () {},
            dragSelectionController: drag,
            showFileTags: false,
            showDeleteTagDialog: (_, _, _) {},
            showAddTagToFileDialog: (_, _) {},
            toggleSelectionMode: () {},
            showContextMenu: (_, _) => fail('generic root menu'),
            onEntityContextMenu: (entity, _) => menuEntity = entity,
          ),
        ),
      );
      final row = find.byKey(ValueKey('miller-folder-${root.path}'));
      expect(find.text('Backup drive'), findsOneWidget);
      await tester.tap(row);
      await tester.pump();
      await waitForChildren(tester);
      expect(find.text('Backup drive'), findsOneWidget);
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.down(tester.getCenter(row));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(menuEntity?.path, root.path);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'columns show labelled and unlabelled roots without changing their paths',
    (tester) async {
      FileSystemEntity? menuEntity;
      await mount(
        tester,
        FileEntryPresentation(
          names: const {
            'C:\\': 'C:\\ (Windows)',
            '\\\\wsl.localhost\\Debian\\': 'Debian',
          },
          leadingBuilder: (_, path, size) =>
              path == '\\\\wsl.localhost\\Debian\\'
              ? DriveAvatar(
                  drive: const DriveInfo(
                    path: '\\\\wsl.localhost\\Debian\\',
                    displayName: 'Debian',
                    kind: DriveKind.wsl,
                  ),
                  size: size,
                )
              : null,
          child: MillerColumnsView(
            state: FolderListState(
              '#drives',
              folders: [
                Directory('C:\\'),
                Directory('D:\\'),
                Directory('/'),
                Directory('\\\\wsl.localhost\\Debian\\'),
              ],
            ),
            selectionState: const SelectionState(),
            isDesktopPlatform: true,
            onNavigateToPath: (_) {},
            onFileTap: (_, _) {},
            toggleFileSelection:
                (_, {shiftSelect = false, ctrlSelect = false}) {},
            toggleFolderSelection:
                (_, {shiftSelect = false, ctrlSelect = false}) {},
            clearSelection: () {},
            dragSelectionController: drag,
            showFileTags: false,
            showDeleteTagDialog: (_, _, _) {},
            showAddTagToFileDialog: (_, _) {},
            toggleSelectionMode: () {},
            showContextMenu: (_, _) => fail('generic root menu'),
            onEntityContextMenu: (entity, _) => menuEntity = entity,
          ),
        ),
      );
      expect(find.text('C:\\ (Windows)'), findsOneWidget);
      expect(find.text('D:\\'), findsOneWidget);
      expect(find.text('/'), findsOneWidget);
      expect(find.text('Debian'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsLight.linuxLogo), findsOneWidget);
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.down(tester.getCenter(find.text('C:\\ (Windows)')));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(menuEntity?.path, 'C:\\');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
