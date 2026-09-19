import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/widgets/file_list_view_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _ListingStub implements FolderListBloc {
  _ListingStub(this.state);
  @override
  final FolderListState state;
  @override
  Stream<FolderListState> get stream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('preview resize shows ghost and badge', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('pv');
    addTearDown(() => dir.deleteSync(recursive: true));
    final selection = SelectionBloc();
    final width = ValueNotifier<double>(360);
    final committed = <double>[];
    final listing = FolderListState(dir.path, viewMode: ViewMode.list);
    final bloc = _ListingStub(listing);
    final dragSel = TabbedFolderDragSelectionController(
      folderListBloc: bloc,
      selectionBloc: selection,
    );
    addTearDown(() async {
      dragSel.dispose();
      await selection.close();
      width.dispose();
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<SelectionBloc>.value(value: selection),
                BlocProvider<FolderListBloc>.value(value: bloc),
              ],
              child: FileListViewBuilder.build(
                state: listing,
                selectionState: selection.state,
                isDesktopPlatform: true,
                onNavigateToPath: (_) {},
                onFileTap: (_, _) {},
                toggleFileSelection:
                    (p, {shiftSelect = false, ctrlSelect = false}) {},
                toggleFolderSelection:
                    (p, {shiftSelect = false, ctrlSelect = false}) {},
                clearSelection: () {},
                dragSelectionController: dragSel,
                showFileTags: false,
                showDeleteTagDialog: (_, _, _) {},
                showAddTagToFileDialog: (_, _) {},
                toggleSelectionMode: () {},
                columnVisibility: const ColumnVisibility(),
                showContextMenu: (_, _) {},
                isPreviewPaneVisible: true,
                previewPaneWidthListenable: width,
                onZoomLevelChanged: (_) {},
                onPreviewPaneWidthChanged: (w) => width.value = w,
                onPreviewPaneWidthCommitted: committed.add,
                onPreviewPaneToggled: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final handle = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeLeftRight,
    );
    expect(handle, findsOneWidget);
    final center = tester.getCenter(handle);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: center);
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(const Key('shot')),
      matchesGoldenFile('zz_tmp_hover.png'),
    );

    await mouse.down(center);
    await tester.pump();
    await mouse.moveTo(center - const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('460 px'), findsOneWidget);
    expect(width.value, 360, reason: 'pane only resizes on release');
    await expectLater(
      find.byKey(const Key('shot')),
      matchesGoldenFile('zz_tmp_drag.png'),
    );

    await mouse.moveTo(center + const Offset(400, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('280 px'), findsOneWidget);
    await expectLater(
      find.byKey(const Key('shot')),
      matchesGoldenFile('zz_tmp_limit.png'),
    );

    await mouse.moveTo(center - const Offset(100, 0));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(committed, [460]);
    expect(width.value, 460);
    expect(find.textContaining(' px'), findsNothing);
  });
}
