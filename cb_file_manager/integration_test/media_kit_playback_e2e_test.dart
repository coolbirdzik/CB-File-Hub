import 'dart:io';
import 'dart:ui' as ui;

import 'package:cb_file_manager/services/media/media_kit_playback.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player.dart'
    as app;
import 'package:cb_file_manager/ui/components/video/video_player/video_player_fast_seek.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mk;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      condition(),
      isTrue,
      reason: 'media_kit did not reach the expected state',
    );
  }

  final sample = File(
    '${Directory.current.path}/integration_test/samples/file_example_MP4_1920_18MG.mp4',
  ).absolute;

  Future<void> exercise(WidgetTester tester, String source) async {
    debugPrint('media_kit test platform: $defaultTargetPlatform');
    final player = PlaybackPlayer();
    final errors = <String>[];
    final subscription = player.stream.error.listen(errors.add);
    final video = PlaybackVideoController(player);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlaybackVideo(controller: video)),
      ),
    );
    await player.open(PlaybackMedia(source), play: false);
    await player.setVolume(23);
    await player.seek(const Duration(seconds: 2));
    try {
      await waitFor(
        tester,
        () =>
            player.state.duration > Duration.zero &&
            player.state.position.inMilliseconds >= 1800,
      );
      await waitFor(
        tester,
        () => !player.state.playing && player.state.volume == 23,
      );
      expect(errors, isEmpty);
      await player.play();
      await waitFor(
        tester,
        () =>
            player.state.playing && player.state.position.inMilliseconds > 2500,
      );
      await player.pause();
      await waitFor(tester, () => !player.state.playing);
      await player.seek(const Duration(seconds: 5));
      await waitFor(
        tester,
        () => (player.state.position.inMilliseconds - 5000).abs() < 500,
      );
      final png = await player.screenshot();
      expect(png, isNotNull);
      final codec = await ui.instantiateImageCodec(png!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(100));
      expect(frame.image.height, greaterThan(100));
      final pixels = await frame.image.toByteData();
      expect(pixels, isNotNull);
      // Reject a black/constant frame: snapshots must contain decoded video.
      expect(pixels!.buffer.asUint8List().toSet().length, greaterThan(16));
      frame.image.dispose();
      codec.dispose();
      // Reuse this player for another source without creating a second window.
      await player.open(PlaybackMedia(sample.path), play: true);
      await waitFor(
        tester,
        () =>
            player.state.playing && player.state.position.inMilliseconds > 500,
      );
      expect(errors, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await player.dispose();
      await subscription.cancel();
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets(
    'media_kit local playback, paused preview, seek, volume, snapshot and reuse',
    (tester) async {
      expect(sample.existsSync(), isTrue);
      await exercise(tester, sample.path);
    },
  );

  testWidgets('media_kit contain fit resizes without replacing the player', (
    tester,
  ) async {
    final player = PlaybackPlayer();
    final video = PlaybackVideoController(player);
    const viewportKey = ValueKey('video-fit-viewport');
    Future<void> mount(Size size) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            key: viewportKey,
            width: size.width,
            height: size.height,
            child: PlaybackVideo(controller: video),
          ),
        ),
      ),
    );
    try {
      await mount(const Size(300, 500));
      await player.open(PlaybackMedia(sample.path), play: false);
      await waitFor(
        tester,
        () =>
            player.state.width != null &&
            find.byType(Texture).evaluate().isNotEmpty,
      );
      for (final size in [const Size(300, 500), const Size(600, 350)]) {
        await mount(size);
        await tester.pump(const Duration(milliseconds: 300));
        final bounds = tester.getRect(find.byKey(viewportKey));
        final texture = tester.getRect(find.byType(Texture));
        expect(texture.width, closeTo(size.width, 1));
        expect(texture.height, closeTo(size.width * 9 / 16, 1));
        expect(texture.center.dx, closeTo(bounds.center.dx, 1));
        expect(texture.center.dy, closeTo(bounds.center.dy, 1));
        expect(
          tester.widget<mk.Video>(find.byType(mk.Video)).controller,
          same(video.controller),
        );
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await player.dispose();
    }
  });

  testWidgets(
    'media_kit streams and seeks through a real Windows SMB share',
    (tester) async {
      await exercise(tester, const String.fromEnvironment('CB_E2E_SMB_URL'));
    },
    skip:
        !Platform.isWindows ||
        const String.fromEnvironment('CB_E2E_SMB_URL').isEmpty,
  );

  testWidgets(
    'media_kit survives repeated disposal while its texture is mounted',
    (tester) async {
      for (var iteration = 0; iteration < 12; iteration++) {
        final player = PlaybackPlayer();
        final errors = <String>[];
        final subscription = player.stream.error.listen(errors.add);
        await tester.pumpWidget(
          MaterialApp(
            home: PlaybackVideo(
              key: ValueKey(iteration),
              controller: PlaybackVideoController(player),
            ),
          ),
        );
        await player.open(PlaybackMedia(sample.path));
        try {
          await waitFor(
            tester,
            () => player.state.position.inMilliseconds > 300,
          );
          await player.seek(const Duration(seconds: 5));
          await tester.pump(const Duration(milliseconds: 30));
          expect(errors, isEmpty);
          // Native disposal can race a pending raster callback during navigation,
          // closing the player, or replacing its controller.
          await player.dispose();
          await tester.pump(const Duration(milliseconds: 30));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await player.dispose();
          await subscription.cancel();
        }
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'main player retains media_kit through buffering and source changes',
    (tester) async {
      final errors = <String>[];
      Widget host(Widget player) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: Scaffold(body: player),
      );
      await tester.pumpWidget(
        host(app.VideoPlayer.file(file: sample, onError: errors.add)),
      );
      await waitFor(tester, () => find.byType(mk.Video).evaluate().isNotEmpty);
      final first = tester
          .widget<mk.Video>(find.byType(mk.Video))
          .controller
          .player;
      await waitFor(tester, () => first.state.position.inMilliseconds > 500);
      expect(
        tester.widget<mk.Video>(find.byType(mk.Video)).controller.player,
        same(first),
      );
      await tester.pumpWidget(
        host(
          app.VideoPlayer.url(
            streamingUrl: sample.uri.toString(),
            fileName: sample.uri.pathSegments.last,
            onError: errors.add,
          ),
        ),
      );
      await waitFor(tester, () => find.byType(mk.Video).evaluate().isNotEmpty);
      final second = tester
          .widget<mk.Video>(find.byType(mk.Video))
          .controller
          .player;
      expect(second, isNot(same(first)));
      await waitFor(tester, () => second.state.position.inMilliseconds > 500);
      expect(errors, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets('rapid seek drags resume playback after pointer release', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: app.VideoPlayer.url(
            streamingUrl: sample.uri.toString(),
            fileName: 'rapid-seek.mp4',
          ),
        ),
      ),
    );
    try {
      await waitFor(tester, () => find.byType(mk.Video).evaluate().isNotEmpty);
      final controller = tester
          .widget<mk.Video>(find.byType(mk.Video))
          .controller
          .player;
      await waitFor(tester, () => controller.state.playing);
      final sliderFinder = find.byWidgetPredicate(
        (widget) => widget is Slider && widget.max > 1000,
      );
      await waitFor(tester, () => sliderFinder.evaluate().isNotEmpty);
      final bounds = tester.getRect(sliderFinder);
      final firstPoint = Offset(
        bounds.left + bounds.width * 0.3,
        bounds.center.dy,
      );
      final first = await tester.startGesture(firstPoint);
      await first.moveBy(const Offset(25, 0));
      await waitFor(tester, () => !controller.state.playing);
      await tester.pump(const Duration(seconds: 1));
      await first.up();
      // Re-grab before media_kit's next state poll acknowledges the resume. This
      // must not mistake the first drag's temporary pause for a user pause.
      final second = await tester.startGesture(firstPoint);
      await second.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(seconds: 2));
      await second.up();
      await waitFor(tester, () => controller.state.playing);
      final releasedAt = controller.state.position;
      await waitFor(
        tester,
        () =>
            controller.state.position >
            releasedAt + const Duration(milliseconds: 300),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    }
  }, skip: !Platform.isWindows);

  testWidgets('streamed video stays visible while seeking and controls auto-hide', (
    tester,
  ) async {
    final surfaceKey = GlobalKey();
    final errors = <String>[];
    const smbSource = String.fromEnvironment('CB_E2E_SMB_URL');
    final video = smbSource.isEmpty
        ? app.VideoPlayer.url(
            streamingUrl: sample.uri.toString(),
            fileName: 'seek-fixture.mp4',
            onError: errors.add,
          )
        : app.VideoPlayer.smb(
            smbMrl: smbSource,
            fileName: 'seek-fixture.mp4',
            onError: errors.add,
          );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: Scaffold(
          body: RepaintBoundary(key: surfaceKey, child: video),
        ),
      ),
    );
    try {
      await waitFor(tester, () => find.byType(mk.Video).evaluate().isNotEmpty);
      final controller = tester
          .widget<mk.Video>(find.byType(mk.Video))
          .controller
          .player;
      await waitFor(
        tester,
        () => controller.state.position.inMilliseconds > 500,
      );
      final playback = tester
          .widget<PlaybackVideo>(find.byType(PlaybackVideo))
          .controller
          .player;
      Future<void> checkVisibleFrame(String label) async {
        debugPrint(
          'Checking $label: ${controller.state.playing}, '
          '${controller.state.position}, size=${controller.state.videoParams}',
        );
        final boundary =
            surfaceKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        expect(
          boundary.size.width,
          greaterThan(100),
          reason: 'Video surface collapsed at $label',
        );
        expect(
          boundary.size.height,
          greaterThan(100),
          reason: 'Video surface collapsed at $label',
        );
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final pixels = (await image.toByteData())!.buffer.asUint8List();
          var visible = 0;
          var count = 0;
          // Sample only the middle half; controls and loading spinners must not
          // make a black video surface look like a successful decoded picture.
          for (var y = image.height ~/ 4; y < image.height * 3 ~/ 4; y += 7) {
            for (var x = image.width ~/ 4; x < image.width * 3 ~/ 4; x += 7) {
              final offset = (y * image.width + x) * 4;
              if (pixels[offset] + pixels[offset + 1] + pixels[offset + 2] >
                  45) {
                visible++;
              }
              count++;
            }
          }
          expect(
            visible / count,
            greaterThan(0.1),
            reason: 'Black Flutter video surface at $label',
          );
          debugPrint('Visible video pixels at $label: ${visible / count}');
        } finally {
          image.dispose();
        }
      }

      await tester.pump(const Duration(milliseconds: 400));
      await checkVisibleFrame('before-seek');
      await tester.pump(const Duration(seconds: 4));
      await checkVisibleFrame('controls-hidden-before-seek');
      await tester.tap(find.byKey(surfaceKey));
      await tester.pump(const Duration(milliseconds: 350));
      final sliderFinder = find.byWidgetPredicate(
        (widget) => widget is Slider && widget.max > 1000,
      );
      expect(sliderFinder, findsOneWidget);
      for (final fraction in [0.75, 0.2, 0.6]) {
        final paused = fraction == 0.2;
        if (paused) {
          await playback.pause();
          await waitFor(tester, () => !controller.state.playing);
        }
        final slider = tester.widget<Slider>(sliderFinder);
        final bounds = tester.getRect(sliderFinder);
        final start =
            bounds.left + 24 + (bounds.width - 48) * slider.value / slider.max;
        final end = bounds.left + 24 + (bounds.width - 48) * fraction;
        final gesture = await tester.startGesture(
          Offset(start, bounds.center.dy),
        );
        for (var step = 1; step <= 18; step++) {
          await gesture.moveTo(
            Offset(start + (end - start) * step / 18, bounds.center.dy),
          );
          await tester.pump(const Duration(milliseconds: 25));
          if (step == 9 || step == 18) {
            // Keep the pointer down: a release-only seek must fail here.
            final requested = tester.widget<Slider>(sliderFinder).value;
            await waitFor(
              tester,
              () =>
                  (controller.state.position.inMilliseconds - requested).abs() <
                  1500,
            );
            await waitFor(tester, () => !controller.state.playing);
            // Allow the last throttled preview to land, then hold still.
            // The picture must stay at this position until another move
            // or release, even if playback was active before the drag.
            await tester.pump(const Duration(milliseconds: 300));
            final heldPosition = controller.state.position;
            await tester.pump(const Duration(seconds: 1));
            expect(controller.state.playing, isFalse);
            expect(
              (controller.state.position - heldPosition).inMilliseconds.abs(),
              lessThan(100),
              reason: 'Video advanced while holding the seek thumb still',
            );
            await checkVisibleFrame('drag-$fraction-step-$step');
          }
        }
        await gesture.up();
        final target = controller.state.duration.inMilliseconds * fraction;
        debugPrint(
          'Seek requested: $target; current: ${controller.state.position}',
        );
        await waitFor(
          tester,
          () =>
              controller.state.playing == !paused &&
              (controller.state.position.inMilliseconds - target).abs() <
                  2000 + controller.state.duration.inMilliseconds * 0.02,
        );
        await tester.pump(const Duration(milliseconds: 700));
        await checkVisibleFrame('seek-${(fraction * 100).round()}');
        expect(
          tester.widget<mk.Video>(find.byType(mk.Video)).controller.player,
          same(controller),
        );
        if (paused) {
          await playback.play();
          await waitFor(tester, () => controller.state.playing);
        }
        await tester.pump(const Duration(seconds: 4));
        await checkVisibleFrame('controls-hidden-after-seek');
        await tester.tap(find.byKey(surfaceKey));
        await tester.pump(const Duration(milliseconds: 350));
      }
      // Hold real keyboard events: previews must move before key-up, and
      // releasing must restore the state from before the hold.
      for (final scenario in [
        (key: LogicalKeyboardKey.arrowRight, paused: false, ticks: 4),
        (key: LogicalKeyboardKey.arrowLeft, paused: false, ticks: 20),
        (key: LogicalKeyboardKey.arrowLeft, paused: true, ticks: 20),
      ]) {
        await controller.seek(const Duration(seconds: 10));
        if (scenario.paused) {
          await playback.pause();
        } else {
          await playback.play();
        }
        await waitFor(
          tester,
          () =>
              controller.state.playing == !scenario.paused &&
              (controller.state.position.inSeconds - 10).abs() <= 1,
        );
        final playerFocus = Focus.of(tester.element(find.byType(mk.Video)))
            .ancestors
            .firstWhere(
              (node) => node.canRequestFocus && node.onKeyEvent != null,
            );
        playerFocus.requestFocus();
        await tester.pump();
        expect(playerFocus.hasPrimaryFocus, isTrue);
        final before = controller.state.position;
        await tester.sendKeyDownEvent(scenario.key);
        try {
          await tester.pump();
          expect(
            tester
                .widget<FastSeekIndicator>(find.byType(FastSeekIndicator))
                .isFastSeeking,
            isTrue,
          );
          for (var tick = 0; tick < scenario.ticks; tick++) {
            await tester.sendKeyRepeatEvent(scenario.key);
            await tester.pump(const Duration(milliseconds: 100));
          }
          await waitFor(
            tester,
            () =>
                !controller.state.playing &&
                (scenario.key == LogicalKeyboardKey.arrowRight
                    ? controller.state.position >
                          before + const Duration(seconds: 8)
                    : controller.state.position <
                          before - const Duration(seconds: 8)),
          );
          await checkVisibleFrame('held-arrow-${scenario.key.keyLabel}');
        } finally {
          await tester.sendKeyUpEvent(scenario.key);
        }
        await waitFor(
          tester,
          () => controller.state.playing == !scenario.paused,
        );
        if (!scenario.paused) {
          final releasedAt = controller.state.position;
          await waitFor(tester, () => controller.state.position > releasedAt);
        }
      }
      expect(errors, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    }
  }, skip: !Platform.isWindows);
}
