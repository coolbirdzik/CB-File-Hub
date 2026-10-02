import 'dart:ui' as ui;
import 'dart:io';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/file_grid_item.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/widgets/file_list_view_builder.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/helpers/media/folder_thumbnail_service.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/folder_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory databaseRoot;
  setUpAll(() async {
    databaseRoot = await Directory.systemTemp.createTemp('cb_grid_resize_db_');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => databaseRoot.path);
  });
  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await databaseRoot.delete(recursive: true);
  });
  for (final (masonry, folderCount) in [
    (false, 0),
    (true, 0),
    (false, 12),
    (true, 12),
  ]) {
    testWidgets(
      '2000 videos and $folderCount folders retain thumbnails during ${masonry ? 'masonry' : 'grid'} resize',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final oldInterval =
            VisibilityDetectorController.instance.updateInterval;
        VisibilityDetectorController.instance.updateInterval = Duration.zero;
        addTearDown(
          () => VisibilityDetectorController.instance.updateInterval =
              oldInterval,
        );

        final root = Directory.systemTemp.createTempSync('cb_grid_resize_');
        final png = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
          final picture = recorder.endRecording();
          final image = await picture.toImage(128, 72);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          return bytes!.buffer.asUint8List();
        });
        final thumb = File('${root.path}/frame.png')..writeAsBytesSync(png!);
        final files = List.generate(
          2000,
          (i) => File('#network/smb/host/share/video_$i.mp4'),
        );
        final folders = List.generate(
          folderCount,
          (i) => Directory('${root.path}/folder_$i'),
        );
        await tester.runAsync(() async {
          for (final folder in folders) {
            await FolderThumbnailService().setAutoThumbnail(
              folder.path,
              thumb.path,
            );
          }
        });
        final cache = ThumbnailWidgetCache()..clearCache();
        for (final file in files) {
          cache.cacheThumbnailPath(file.path, thumb.path);
        }
        final selection = SelectionBloc();
        final width = ValueNotifier<double>(1060);
        final previewWidth = ValueNotifier<double>(360);
        final state = FolderListState(
          '#network/smb/host/share',
          files: files,
          folders: folders,
          viewMode: ViewMode.grid,
          gridZoomLevel: 8,
        );
        final bloc = _ListingStub(state);
        final drag = TabbedFolderDragSelectionController(
          folderListBloc: bloc,
          selectionBloc: selection,
        );
        addTearDown(() async {
          drag.dispose();
          await selection.close();
          width.dispose();
          previewWidth.dispose();
          cache.clearCache();
          await root.delete(recursive: true);
        });
        final columns = <int?>[];
        // Decode the fixture outside fake test time. Otherwise Windows can
        // leave FileImage's outstanding read open during directory teardown.
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.runAsync(
          () => precacheImage(
            FileImage(thumb),
            tester.element(find.byType(Scaffold)),
          ),
        );
        await tester.pump();
        final grid = FileListViewBuilder.build(
          state: state,
          selectionState: selection.state,
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
          columnVisibility: const ColumnVisibility(),
          showContextMenu: (_, _) {},
          isPreviewPaneVisible: false,
          previewPaneWidthListenable: previewWidth,
          onZoomLevelChanged: (_) {},
          onPreviewPaneWidthChanged: (_) {},
          onPreviewPaneWidthCommitted: (_) {},
          onPreviewPaneToggled: () {},
          isMasonryLayout: masonry,
          onGridCrossAxisCountChanged: columns.add,
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [AppLocalizationsDelegate()],
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<SelectionBloc>.value(value: selection),
                  BlocProvider<FolderListBloc>.value(value: bloc),
                ],
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ValueListenableBuilder<double>(
                    valueListenable: width,
                    child: grid,
                    builder: (_, w, child) =>
                        SizedBox(width: w, height: 600, child: child),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        final tiles = {
          for (final element in find.byType(FileGridItem).evaluate())
            (element.widget as FileGridItem).file.path: element.widget,
        };
        final folderThumbs = {
          for (final element in find.byType(FolderThumbnail).evaluate())
            (element.widget as FolderThumbnail).folder.path: element.widget,
        };
        expect(folderThumbs.length, folderCount);
        final thumbs = {
          for (final element in find.byType(ThumbnailLoader).evaluate())
            (element.widget as ThumbnailLoader).filePath: element.widget,
        };
        expect(tiles.length + folderCount, greaterThan(20));
        // Folder covers share one image fixture; the file thumbnails have
        // individual video paths, plus one shared folder image path.
        expect(thumbs.length, tiles.length + (folderCount > 0 ? 1 : 0));
        expect(find.byType(Image), findsWidgets);
        final notifications = columns.length;
        final thumbnailBoundary = find
            .ancestor(
              of: find.byType(ThumbnailLoader).first,
              matching: find.byType(RepaintBoundary),
            )
            .first;
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          thumbnailBoundary,
        );
        boundary.debugResetMetrics();
        final first = files.first.path;
        final before = tester.getRect(
          find.byKey(ValueKey('file-grid-item-$first')),
        );
        var recreations = 0;
        for (var i = 1; i <= 60; i++) {
          width.value = 1060 - i.toDouble();
          await tester.pump();
          for (final element in find.byType(ThumbnailLoader).evaluate()) {
            final current = element.widget as ThumbnailLoader;
            if (current.filePath == thumb.path) continue;
            if (thumbs.containsKey(current.filePath) &&
                !identical(thumbs[current.filePath], current)) {
              recreations++;
            }
          }
          for (final element in find.byType(FolderThumbnail).evaluate()) {
            final current = element.widget as FolderThumbnail;
            expect(
              identical(folderThumbs[current.folder.path], current),
              isTrue,
            );
          }
        }
        expect(
          recreations,
          0,
          reason: 'Pixel resizing must reuse existing thumbnail widgets',
        );
        expect(
          columns.length,
          notifications,
          reason: 'Columns are unchanged during this drag',
        );
        expect(
          boundary.debugSymmetricPaintCount +
              boundary.debugAsymmetricPaintCount,
          0,
          reason: 'Moving grid gutters must retain the painted thumbnail layer',
        );
        expect(
          tester.getRect(find.byKey(ValueKey('file-grid-item-$first'))).left,
          isNot(before.left),
          reason: 'Grid still lays out live as its gutter widths change',
        );
        final tile = tester.getRect(
          find.byKey(ValueKey('file-grid-item-$first')),
        );
        expect(
          drag.hitTestItem(tile.center),
          first,
          reason: 'Selection hit areas must track resized geometry',
        );
        // The old test only resized inside one column count. Cross multiple
        // boundaries repeatedly: this used to recreate every existing tile.
        for (final w in [1060.0, 928.5, 900.0, 750.0, 1100.0, 800.0, 900.0]) {
          width.value = w;
          await tester.pump();
          for (final element in find.byType(ThumbnailLoader).evaluate()) {
            final current = element.widget as ThumbnailLoader;
            if (thumbs.containsKey(current.filePath)) {
              if (current.filePath == thumb.path) continue;
              expect(
                identical(thumbs[current.filePath], current),
                isTrue,
                reason: 'Changing columns must preserve existing thumbnails',
              );
            }
          }
          for (final element in find.byType(FolderThumbnail).evaluate()) {
            final current = element.widget as FolderThumbnail;
            expect(
              identical(folderThumbs[current.folder.path], current),
              isTrue,
            );
          }
          for (final file in files.take(12)) {
            final finder = find.byKey(ValueKey('file-grid-item-${file.path}'));
            final rect = tester.getRect(finder);
            if (rect.center.dy < 600) {
              expect(
                drag.hitTestItem(rect.center),
                file.path,
                reason:
                    'Hit areas track positions even when cell constraints stay identical',
              );
            }
          }
        }
        expect(
          boundary.debugSymmetricPaintCount +
              boundary.debugAsymmetricPaintCount,
          0,
          reason: 'Column changes must reuse the painted thumbnail layer',
        );
        expect(columns.last, lessThan(columns.first!));
        final selectionCenter = tester
            .getRect(find.byKey(ValueKey('file-grid-item-$first')))
            .center;
        final stackOrigin = tester.getTopLeft(find.byKey(drag.stackKey));
        final localCenter = selectionCenter - stackOrigin;
        drag.start(localCenter - const Offset(1, 1));
        drag.update(localCenter + const Offset(1, 1));
        drag.end();
        await tester.pump();
        expect(
          selection.state.selectedFilePaths,
          contains(first),
          reason: 'Rectangle selection reads resized tile geometry',
        );
        selection.add(ClearSelection());
        await tester.pump();
        selection.add(ToggleFileSelection(first));
        await tester.pump();
        await tester.pump();
        expect(
          tester
              .widget<FileGridItem>(
                find.byKey(ValueKey('file-grid-item-$first')),
              )
              .isSelected,
          isTrue,
          reason: 'Selection must invalidate cached item contents',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          drag.hitTestItem(selectionCenter),
          isNull,
          reason: 'Detached tiles must unregister their render boxes',
        );
      },
    );
  }
}
