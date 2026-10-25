import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/helpers/media/folder_thumbnail_service.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/folder_thumbnail.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/widgets/file_list_view_builder.dart';
import 'package:cb_file_manager/ui/widgets/lazy_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' as rendering show ScrollCacheExtent;
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
  late Directory root;
  late File frame;
  late File video;
  late List<File> videos;
  late File staleVideo;

  setUp(() {
    final previous = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(
      () => VisibilityDetectorController.instance.updateInterval = previous,
    );
  });

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_thumb_scroll_');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(128, 72);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    frame = await File(
      '${root.path}/frame.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    video = await File('${root.path}/video.mp4').writeAsString('fixture');
    videos = [
      for (var i = 0; i < 100; i++)
        await File('${root.path}/video_$i.mp4').writeAsString('fixture'),
    ];
    staleVideo = await File('${root.path}/stale.mp4').writeAsString('fixture');
    // Seed the same disk index used by the app, then warm it through the real
    // validating cache API. No generation or platform decoder is mocked.
    await File('${root.path}/thumbnail_cache_index.json').writeAsString(
      jsonEncode({
        VideoThumbnailHelper.getNormalizedPath(video.path): frame.path,
        for (final file in videos)
          VideoThumbnailHelper.getNormalizedPath(file.path): frame.path,
        VideoThumbnailHelper.getNormalizedPath(staleVideo.path):
            '${root.path}/removed_frame.png',
      }),
    );
    await VideoThumbnailHelper.initializeCache();
    expect(await VideoThumbnailHelper.getFromCache(video.path), frame.path);
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  Future<void> warmDecodedFrame(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold));
      await precacheImage(FileImage(frame), context);
      await precacheImage(
        ResizeImage(
          FileImage(frame),
          width: 512,
          allowUpscaling: false,
          policy: ResizeImagePolicy.fit,
        ),
        context,
      );
    });
    await tester.pump();
  }

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 160, height: 120, child: child)),
  );

  testWidgets('warm local video appears on its first frame after recycling', (
    tester,
  ) async {
    await warmDecodedFrame(tester);
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(
        host(
          LazyVideoThumbnail(
            videoPath: video.path,
            placeholderOnly: true,
            fallbackBuilder: () => const SizedBox(key: Key('video-fallback')),
          ),
        ),
      );
      expect(find.byKey(const Key('video-fallback')), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a removed cached video frame falls back without a build error', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        LazyVideoThumbnail(
          videoPath: staleVideo.path,
          placeholderOnly: true,
          fallbackBuilder: () => const SizedBox(key: Key('stale-fallback')),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('stale-fallback')), findsOneWidget);
    expect(
      VideoThumbnailHelper.peekCachedThumbnailPath(staleVideo.path),
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final isVideo in [false, true]) {
    testWidgets(
      'warm ${isVideo ? 'video' : 'image'} folder cover survives grid eviction',
      (tester) async {
        await warmDecodedFrame(tester);
        final folder = await tester.runAsync(
          () => Directory('${root.path}/folder_$isVideo').create(),
        );
        await tester.runAsync(
          () => FolderThumbnailService().setAutoThumbnail(
            folder!.path,
            isVideo ? 'video::${video.path}' : frame.path,
          ),
        );
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final firstKey = Key('folder-$isVideo');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GridView.builder(
                controller: controller,
                scrollCacheExtent: const rendering.ScrollCacheExtent.pixels(0),
                addAutomaticKeepAlives: false,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 160,
                ),
                itemCount: 100,
                itemBuilder: (_, index) => index == 0
                    ? FolderThumbnail(key: firstKey, folder: folder!)
                    : const SizedBox(),
              ),
            ),
          ),
        );
        // Even the first mount can restore the service's warm cover.
        expect(
          find.descendant(
            of: find.byKey(firstKey),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );
        final original = tester.state(find.byKey(firstKey));
        controller.jumpTo(5000);
        await tester.pump();
        expect(
          original.mounted,
          isFalse,
          reason: 'Actually evict the grid tile',
        );
        controller.jumpTo(0);
        await tester.pump();
        // No runAsync, settling, or extra frame before this assertion: a warm
        // cover must be in the very first returned frame, without a placeholder.
        expect(
          find.descendant(
            of: find.byKey(firstKey),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final masonry in [false, true]) {
    testWidgets(
      'app ${masonry ? 'masonry' : 'grid'} restores local video and folder frames on scroll back',
      (tester) async {
        await warmDecodedFrame(tester);
        final folder = await tester.runAsync(
          () => Directory('${root.path}/app_folder_$masonry').create(),
        );
        await tester.runAsync(
          () => FolderThumbnailService().setAutoThumbnail(
            folder!.path,
            'video::${video.path}',
          ),
        );
        final state = FolderListState(
          root.path,
          files: videos,
          folders: [folder!],
          viewMode: ViewMode.grid,
          gridZoomLevel: 8,
        );
        final bloc = _ListingStub(state);
        final selection = SelectionBloc();
        final controller = ScrollController();
        final previewWidth = ValueNotifier<double>(360);
        final drag = TabbedFolderDragSelectionController(
          folderListBloc: bloc,
          selectionBloc: selection,
        );
        addTearDown(() async {
          controller.dispose();
          previewWidth.dispose();
          drag.dispose();
          await selection.close();
        });
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
          scrollController: controller,
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
                child: grid,
              ),
            ),
          ),
        );
        final folderFinder = find.byType(FolderThumbnail).first;
        final folderState = tester.state(folderFinder);
        void expectFrames() {
          for (final key in [
            'folder-grid-item-${folder.path}',
            'file-grid-item-${videos.first.path}',
          ]) {
            final raw = find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(RawImage),
            );
            expect(raw, findsOneWidget, reason: key);
            expect(tester.widget<RawImage>(raw).image, isNotNull, reason: key);
          }
        }

        expectFrames();
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pump();
        expect(folderState.mounted, isFalse);
        controller.jumpTo(0);
        await tester.pump();
        expectFrames();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
