import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/helpers/files/file_browser_options.dart';
import 'package:cb_file_manager/ui/components/common/file_browser_options_scope.dart';
import 'package:cb_file_manager/ui/components/common/file_entry_presentation.dart';
import 'package:cb_file_manager/ui/components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/file_grid_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/settings/file_browser_settings_section.dart';
import 'package:cb_file_manager/ui/widgets/file_drag_drop_item.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/file_browser_drag_harness.dart';

void main() {
  for (final mode in [
    ViewMode.grid,
    ViewMode.list,
    ViewMode.details,
    ViewMode.tiles,
    ViewMode.columns,
    ViewMode.tree,
    ViewMode.gridPreview,
  ]) {
    testWidgets(
      'checkboxes select files and folders independently in ${mode.name}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(1280, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey<FileBrowserDragHarnessState>();
        final options = ValueNotifier(
          const FileBrowserOptions(
            selectionCheckboxes: true,
            showExtensions: false,
            singleClickToOpen: true,
          ),
        );
        addTearDown(options.dispose);
        final file = File(p.join('C:', 'rectangle', 'sample.txt'));
        final folder = Directory(p.join('C:', 'rectangle', 'folder.photos'));
        await tester.pumpWidget(
          FileBrowserOptionsScope(
            options: options,
            child: FileBrowserDragHarness(
              key: key,
              files: [file],
              destination: folder,
              mode: mode,
              onMove: (_, _) async {},
              onExternalDrag: (_) {},
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('sample'), findsWidgets);
        expect(find.text('folder.photos'), findsWidgets);
        Finder checkboxFor(String path) => find.descendant(
          of: find
              .byWidgetPredicate(
                (widget) => widget is FileDragDropItem && widget.path == path,
              )
              .first,
          matching: find.byKey(const ValueKey('browser-selection-checkbox')),
        );
        final fileCheck = checkboxFor(file.path);
        final folderCheck = checkboxFor(folder.path);
        await tester.tap(fileCheck, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(key.currentState!.selection.state.selectedFilePaths, {
          file.path,
        });
        await tester.tap(folderCheck, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(key.currentState!.selection.state.selectedFolderPaths, {
          folder.path,
        });
        expect(key.currentState!.selection.state.selectedFilePaths, {
          file.path,
        });
        await tester.tap(fileCheck, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(key.currentState!.selection.state.selectedFilePaths, isEmpty);
        expect(key.currentState!.selection.state.selectedFolderPaths, {
          folder.path,
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'extension updates live and a checkbox toggles the real path without opening',
    (tester) async {
      final options = ValueNotifier(const FileBrowserOptions());
      addTearDown(options.dispose);
      final file = File('/tmp/sample.txt');
      final toggled = <(String, bool)>[];
      final opened = <String>[];
      bool selected = false;
      await tester.pumpWidget(
        MaterialApp(
          home: FileBrowserOptionsScope(
            options: options,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: StatefulBuilder(
                    builder: (context, setState) => FileGridItem(
                      file: file,
                      isSelected: selected,
                      isDesktopMode: true,
                      showFileTags: false,
                      toggleFileSelection:
                          (path, {shiftSelect = false, ctrlSelect = false}) {
                            toggled.add((path, ctrlSelect));
                            setState(() => selected = !selected);
                          },
                      toggleSelectionMode: () {},
                      onFileTap: (file, _) => opened.add(file.path),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('sample.txt'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('browser-selection-checkbox')),
        findsNothing,
      );
      options.value = const FileBrowserOptions(
        showExtensions: false,
        selectionCheckboxes: true,
        singleClickToOpen: true,
      );
      await tester.pump();
      expect(find.text('sample'), findsOneWidget);
      expect(find.text('sample.txt'), findsNothing);
      final checkbox = find.byKey(const ValueKey('browser-selection-checkbox'));
      await tester.tap(checkbox);
      await tester.pump();
      expect(toggled, [(file.path, true)]);
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(opened, isEmpty);
      await tester.tap(checkbox);
      await tester.pump();
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      await tester.tap(find.text('sample'));
      await tester.pump();
      expect(opened, [file.path]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'single click activation waits for release and preserves modifier selection',
    (tester) async {
      final options = ValueNotifier(
        const FileBrowserOptions(singleClickToOpen: true),
      );
      addTearDown(options.dispose);
      int selected = 0, opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FileBrowserOptionsScope(
            options: options,
            child: Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: OptimizedInteractionLayer(
                  fileBrowserActivation: true,
                  onTap: () => selected++,
                  onDoubleTap: () => opened++,
                ),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(OptimizedInteractionLayer));
      final drag = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
      );
      expect(opened, 0);
      await drag.moveBy(const Offset(80, 0));
      await drag.up();
      await tester.pump();
      expect(opened, 0);
      final click = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
      );
      expect(opened, 0);
      await click.up();
      await tester.pump();
      expect(opened, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(selected, 1);
      expect(opened, 1);
    },
  );

  testWidgets('folders and virtual display names retain their own identities', (
    tester,
  ) async {
    final options = ValueNotifier(
      const FileBrowserOptions(showExtensions: false),
    );
    addTearDown(options.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FileBrowserOptionsScope(
          options: options,
          child: FileEntryPresentation(
            names: const {'stored.hash': 'movie.mp4'},
            child: Builder(
              builder: (context) => Column(
                children: [
                  Text(FileEntryPresentation.nameOf(context, 'folder.photos')),
                  Text(
                    FileEntryPresentation.fileNameOf(context, 'stored.hash'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('folder.photos'), findsOneWidget);
    expect(find.text('movie'), findsOneWidget);
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      'file browser settings gate platform-specific options on $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            locale: const Locale('en'),
            home: const Scaffold(
              body: SingleChildScrollView(child: FileBrowserSettingsSection()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final isDesktop =
            platform == TargetPlatform.windows ||
            platform == TargetPlatform.macOS ||
            platform == TargetPlatform.linux;
        expect(find.text('Show file extensions'), findsOneWidget);
        expect(find.text('Item selection checkboxes'), findsOneWidget);
        expect(find.text('Allow editing file extensions'), findsOneWidget);
        expect(find.text('Show hidden items'), findsOneWidget);
        expect(
          find.text('Show Windows system items'),
          platform == TargetPlatform.windows ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Single-click to open'),
          isDesktop ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
