import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/widgets/lazy_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' as rendering show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  const native = MethodChannel('fc_native_video_thumbnail');
  final prefs = UserPreferences.instance;
  final generated = <String>[];
  late Directory root;
  late List<String> paths;
  late List<int> frame;
  Completer<void>? blockDecoder;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_viewport_');
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProvider, (_) async => root.path);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(8, 8);
    frame = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    paths = [
      for (var i = 0; i < 100; i++)
        (await File('${root.path}/video_$i.mp4').writeAsString('fixture')).path,
    ];
    messenger.setMockMethodCallHandler(native, (call) async {
      final args = call.arguments as Map;
      generated.add(
        VideoThumbnailHelper.getNormalizedPath(args['srcFile'] as String),
      );
      await blockDecoder?.future;
      final output = File(args['destFile'] as String);
      await output.writeAsBytes(frame);
      return output.path;
    });
    await prefs.init();
    await prefs.setMaxThumbnailConcurrency(1);
    await VideoThumbnailHelper.initializeCache();
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(pathProvider, null);
    await root.delete(recursive: true);
  });

  setUp(() async {
    generated.clear();
    blockDecoder = null;
    await prefs.setVideoThumbnailViewportOnly(true);
    VideoThumbnailHelper.updateDisplayIndexMap(paths);
    await VideoThumbnailHelper.clearCache();
    final previous = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(
      () => VisibilityDetectorController.instance.updateInterval = previous,
    );
  });

  Future<void> drain(WidgetTester tester, {int rounds = 200}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await drain(tester, rounds: 3);
    // Flush the helper's production cache-index save throttle.
    await tester.pump(const Duration(seconds: 11));
    await drain(tester, rounds: 3);
  }

  Widget listing({bool hidden = false}) => MaterialApp(
    home: Scaffold(
      body: Offstage(
        offstage: hidden,
        child: SizedBox(
          height: 200,
          child: ListView.builder(
            controller: ScrollController(initialScrollOffset: 5000),
            scrollCacheExtent: const rendering.ScrollCacheExtent.pixels(1000),
            itemExtent: 100,
            itemCount: paths.length,
            itemBuilder: (context, i) => LazyVideoThumbnail(
              key: ValueKey(paths[i]),
              videoPath: paths[i],
              fallbackBuilder: () => const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );

  test('new preference defaults on and persists both choices', () async {
    VideoThumbnailHelper.clearDisplayIndexMap();
    await DatabaseManager.getInstance().deletePreference(
      'video_thumbnail_viewport_only',
    );
    expect(await prefs.getVideoThumbnailViewportOnly(), isTrue);
    expect(await prefs.setVideoThumbnailViewportOnly(false), isTrue);
    expect(
      await DatabaseManager.getInstance().getBoolPreference(
        'video_thumbnail_viewport_only',
      ),
      isFalse,
    );
    expect(await prefs.getVideoThumbnailViewportOnly(), isFalse);
    await prefs.setVideoThumbnailViewportOnly(true);
    expect(await prefs.getVideoThumbnailViewportOnly(), isTrue);
  });

  testWidgets('bulk preload stays idle until a viewport appears', (
    tester,
  ) async {
    await tester.runAsync(
      () => VideoThumbnailHelper.optimizedBatchPreload(paths),
    );
    await drain(tester, rounds: 3);
    expect(generated, isEmpty);
    await tester.pumpWidget(listing());
    VisibilityDetectorController.instance.notifyNow();
    await drain(tester);
    final normalized = paths
        .map(VideoThumbnailHelper.getNormalizedPath)
        .toList();
    expect(generated, containsAll(normalized.sublist(50, 52)));
    expect(generated.every(normalized.sublist(46, 56).contains), isTrue);
    expect(generated.toSet().length, generated.length);
    await finish(tester);
  }, skip: !Platform.isWindows);

  testWidgets('hiding a tab cancels queued extraction', (tester) async {
    blockDecoder = Completer<void>();
    await tester.pumpWidget(listing());
    for (var i = 0; i < 40 && generated.isEmpty; i++) {
      await drain(tester, rounds: 1);
    }
    expect(generated, hasLength(1));
    await tester.pumpWidget(listing(hidden: true));
    await tester.pump();
    blockDecoder!.complete();
    await drain(tester);
    expect(generated, hasLength(1));
    await finish(tester);
  }, skip: !Platform.isWindows);

  testWidgets('turning the preference off restores full-list preload', (
    tester,
  ) async {
    await tester.runAsync(
      () => VideoThumbnailHelper.optimizedBatchPreload(paths.take(12).toList()),
    );
    await tester.runAsync(() => prefs.setVideoThumbnailViewportOnly(false));
    await tester.pump(const Duration(milliseconds: 350));
    await drain(tester);
    expect(
      generated.toSet(),
      paths.take(12).map(VideoThumbnailHelper.getNormalizedPath).toSet(),
    );
    await tester.runAsync(() => prefs.setVideoThumbnailViewportOnly(true));
  }, skip: !Platform.isWindows);

  testWidgets('enabling viewport mode stops bulk work and delayed stages', (
    tester,
  ) async {
    blockDecoder = Completer<void>();
    await tester.runAsync(
      () => VideoThumbnailHelper.optimizedBatchPreload(paths),
    );
    await tester.runAsync(() => prefs.setVideoThumbnailViewportOnly(false));
    for (var i = 0; i < 40 && generated.isEmpty; i++) {
      await drain(tester, rounds: 1);
    }
    expect(generated, hasLength(1));
    await tester.runAsync(() => prefs.setVideoThumbnailViewportOnly(true));
    blockDecoder!.complete();
    await drain(tester);
    expect(generated, hasLength(1));
    await finish(tester);
  }, skip: !Platform.isWindows);
}
