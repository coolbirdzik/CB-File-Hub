import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File photo;
  const paths = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_thumbnail_loading_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => root.path);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 64);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    photo = await File(
      '${root.path}/photo.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    await root.delete(recursive: true);
  });

  setUp(() {
    final previous = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(
      () => VisibilityDetectorController.instance.updateInterval = previous,
    );
  });

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 100, height: 100, child: child)),
    ),
  );

  test(
    'missing folders always release their thumbnail listing token',
    () async {
      final bloc = FileNavigationBloc();
      final failed = bloc.stream.firstWhere(
        (s) => !s.isLoading && s.error != null,
      );
      bloc.add(FileNavigationLoad('${root.path}/missing'));
      await failed.timeout(const Duration(seconds: 10));
      await bloc.close();
      expect(ThumbnailLoader.isListingReady, isTrue);
    },
  );

  testWidgets('a local photo waits for its decoded frame and reports once', (
    tester,
  ) async {
    var ready = 0;
    Widget thumbnail() => ThumbnailLoader(
      filePath: photo.path,
      isImage: true,
      isVideo: false,
      width: 100,
      height: 100,
      onThumbnailLoaded: () => ready++,
    );
    await tester.pumpWidget(host(thumbnail()));
    expect(find.byType(RawImage), findsNothing);
    expect(find.byType(ThumbnailPlaceholder), findsOneWidget);
    expect(ready, 0);
    // FileImage's codec completes off the fake test clock; let I/O run, then
    // pump its scheduled frame rather than awaiting that frame inside runAsync.
    for (var i = 0; i < 40 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(find.byType(ThumbnailPlaceholder), findsNothing);
    expect(ready, 1);
    await tester.pumpWidget(host(thumbnail()));
    await tester.pump();
    expect(ready, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed photo shows an error instead of a waiting/blank tile', (
    tester,
  ) async {
    var ready = false;
    await tester.pumpWidget(
      host(
        ThumbnailLoader(
          filePath: '${root.path}/missing.png',
          isImage: true,
          isVideo: false,
          width: 100,
          height: 100,
          showLoadingIndicator: false,
          onThumbnailLoaded: () => ready = true,
        ),
      ),
    );
    expect(
      tester
          .widget<ThumbnailPlaceholder>(find.byType(ThumbnailPlaceholder))
          .visible,
      isFalse,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    expect(
      tester
          .widget<ThumbnailPlaceholder>(find.byType(ThumbnailPlaceholder))
          .failed,
      isTrue,
    );
    expect(ready, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'photo and video placeholders fit tiny columns without spinners',
    (tester) async {
      for (final video in [false, true]) {
        await tester.pumpWidget(
          host(
            Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: ThumbnailPlaceholder(isVideo: video),
              ),
            ),
          ),
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final video in [false, true]) {
    testWidgets(
      'network ${video ? 'video' : 'photo'} failure reaches every matching tile',
      (tester) async {
        ThumbnailLoader.debugNetworkThumbnailGenerator = (_, _) async => null;
        addTearDown(
          () => ThumbnailLoader.debugNetworkThumbnailGenerator = null,
        );
        final source = '#network/smb/server/share/failed_$video';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  for (var i = 0; i < 2; i++)
                    Expanded(
                      child: SizedBox(
                        height: 100,
                        child: ThumbnailLoader(
                          filePath: source,
                          isImage: !video,
                          isVideo: video,
                          width: 100,
                          height: 100,
                          fallbackBuilder: () => const SizedBox.expand(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump();
        await tester.pump();
        final placeholders = tester.widgetList<ThumbnailPlaceholder>(
          find.byType(ThumbnailPlaceholder),
        );
        expect(placeholders, hasLength(2));
        expect(placeholders.every((placeholder) => placeholder.failed), isTrue);
        expect(ThumbnailLoader.pendingThumbnailCount, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'network queue starts outside build, drains and bounds concurrency',
    (tester) async {
      final release = Completer<void>();
      var running = 0;
      var maximum = 0;
      var starts = 0;
      var ready = 0;
      ThumbnailLoader.debugNetworkThumbnailGenerator = (path, size) async {
        starts++;
        running++;
        if (running > maximum) maximum = running;
        await release.future;
        running--;
        return photo.path;
      };
      addTearDown(() {
        ThumbnailLoader.debugNetworkThumbnailGenerator = null;
        if (!release.isCompleted) release.complete();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 240,
                child: GridView.count(
                  crossAxisCount: 3,
                  children: List.generate(
                    6,
                    (index) => ThumbnailLoader(
                      filePath: '#network/smb/server/share/photo_$index.png',
                      isImage: true,
                      isVideo: false,
                      width: 120,
                      height: 120,
                      onThumbnailLoaded: () => ready++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(starts, 0, reason: 'No I/O from build');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(starts, greaterThan(0));
      expect(starts, lessThanOrEqualTo(4));
      expect(ready, 0, reason: 'Queued generation has not completed');
      release.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(starts, 6);
      expect(maximum, lessThanOrEqualTo(4));
      for (var i = 0; i < 40 && ready < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(ready, 6);
      expect(ThumbnailLoader.pendingThumbnailCount, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}
