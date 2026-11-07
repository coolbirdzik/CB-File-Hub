import 'dart:ui' as ui;

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/primitives/cb_slider.dart';
import 'package:cb_file_manager/services/media/subtitle_progress.dart';
import 'package:cb_file_manager/ui/components/video/subtitle_status_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    SubtitleProgress progress, {
    Size size = const Size(720, 420),
    bool controls = true,
    VoidCallback? retry,
    VoidCallback? settings,
    VoidCallback? regenerate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Colors.black)),
                  SubtitleCaptionOverlay(
                    caption: 'Hello world',
                    controlsVisible: controls,
                  ),
                  if (controls)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Row(
                        children: [
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackShape: SubtitleSeekTrackShape(progress),
                              ),
                              child: Slider(value: .25, onChanged: (_) {}),
                            ),
                          ),
                          SubtitleControlButton(
                            progress: progress,
                            onSettings: settings ?? () {},
                            onRetry: retry ?? () {},
                            onRegenerate: regenerate,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('cached subtitles explain reuse and offer clear/regenerate', (
    tester,
  ) async {
    var regenerated = false;
    await show(
      tester,
      const SubtitleProgress(
        phase: SubtitlePhase.ready,
        cacheState: SubtitleCacheState.reused,
        duration: Duration(minutes: 2),
        position: Duration.zero,
        completed: [SubtitleTimeRange(Duration.zero, Duration(minutes: 2))],
      ),
      regenerate: () => regenerated = true,
      controls: true,
    );
    expect(
      tester
          .widget<PopupMenuButton<dynamic>>(
            find.byKey(const ValueKey('ai-subtitle-control')),
          )
          .tooltip,
      contains('Using saved subtitles'),
    );
    expect(find.byKey(const ValueKey('ai-subtitle-busy')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-regenerate')));
    await tester.pumpAndSettle();
    expect(regenerated, isTrue);
  });

  testWidgets('recognized audio and output languages use English labels', (
    tester,
  ) async {
    await show(
      tester,
      const SubtitleProgress(
        phase: SubtitlePhase.processing,
        stage: SubtitleWorkStage.translating,
        sourceLanguage: 'ja',
        targetLanguage: 'vi',
        duration: Duration(minutes: 2),
        position: Duration.zero,
      ),
    );
    final details = tester.widget<PopupMenuButton<dynamic>>(
      find.byKey(const ValueKey('ai-subtitle-control')),
    );
    expect(details.tooltip, contains('Japanese → Vietnamese'));
    expect(tester.takeException(), isNull);
  });

  for (final stage in [
    SubtitleWorkStage.loadingSpeech,
    SubtitleWorkStage.recognizing,
    SubtitleWorkStage.loadingTranslation,
    SubtitleWorkStage.translating,
  ]) {
    testWidgets('$stage is available from the CC control', (tester) async {
      await show(
        tester,
        SubtitleProgress(
          phase: SubtitlePhase.processing,
          stage: stage,
          modelName: 'Whisper Small',
          duration: const Duration(minutes: 2),
          position: const Duration(seconds: 10),
          completed: const [
            SubtitleTimeRange(Duration.zero, Duration(seconds: 8)),
          ],
          pending: const SubtitleTimeRange(
            Duration(seconds: 8),
            Duration(seconds: 16),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('ai-subtitle-control')), findsOneWidget);
      expect(find.text('Whisper Small'), findsNothing);
      expect(find.byKey(const ValueKey('ai-subtitle-busy')), findsOneWidget);
      final details = tester.widget<PopupMenuButton<dynamic>>(
        find.byKey(const ValueKey('ai-subtitle-control')),
      );
      expect(details.tooltip, contains('Whisper Small'));
      expect(details.tooltip, contains('Subtitles processed to 00:08 / 02:00'));
      expect(details.tooltip, contains('Processing 00:08 – 00:16'));
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [const Size(320, 180), const Size(240, 120)]) {
    testWidgets('compact status fits $size alongside playback controls', (
      tester,
    ) async {
      await show(
        tester,
        const SubtitleProgress(
          phase: SubtitlePhase.processing,
          stage: SubtitleWorkStage.loadingTranslation,
          modelName: 'Hy-MT2 1.8B Q4_K_M',
          duration: Duration(minutes: 2),
          position: Duration(seconds: 5),
        ),
        size: size,
        controls: true,
      );
      expect(find.byKey(const ValueKey('ai-subtitle-control')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('hidden controls leave only caption text in the picture', (
    tester,
  ) async {
    await show(
      tester,
      const SubtitleProgress(
        phase: SubtitlePhase.processing,
        stage: SubtitleWorkStage.translating,
        duration: Duration(minutes: 2),
        position: Duration.zero,
      ),
      controls: false,
    );
    expect(find.byKey(const ValueKey('ai-subtitle-control')), findsNothing);
    expect(find.byKey(const ValueKey('ai-subtitle-status')), findsNothing);
    expect(find.byKey(const ValueKey('ai-subtitle-timeline')), findsNothing);
    expect(find.byKey(const ValueKey('ai-subtitle-caption')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('CC menu offers retry and subtitle settings after failure', (
    tester,
  ) async {
    var retried = false, opened = false;
    await show(
      tester,
      const SubtitleProgress(
        phase: SubtitlePhase.failed,
        duration: Duration(minutes: 2),
        position: Duration.zero,
        error: 'Model could not load',
      ),
      retry: () => retried = true,
      settings: () => opened = true,
    );
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-control')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Model could not load'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local AI subtitles'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.byKey(const ValueKey('ai-subtitle-busy')), findsNothing);
  });
  testWidgets('AI progress on the seek track preserves drag callbacks', (
    tester,
  ) async {
    double? changed;
    var started = false, ended = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 2.5,
                  trackShape: SubtitleSeekTrackShape(
                    SubtitleProgress(
                      phase: SubtitlePhase.processing,
                      stage: SubtitleWorkStage.recognizing,
                      duration: Duration(seconds: 100),
                      position: Duration(seconds: 25),
                      completed: [
                        SubtitleTimeRange(
                          Duration(seconds: 40),
                          Duration(seconds: 50),
                        ),
                      ],
                      pending: SubtitleTimeRange(
                        Duration(seconds: 50),
                        Duration(seconds: 60),
                      ),
                    ),
                  ),
                ),
                child: CbSlider(
                  value: .25,
                  onChanged: (v) => changed = v,
                  onChangeStart: (_) => started = true,
                  onChangeEnd: (_) => ended = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(Slider), const Offset(80, 0));
    expect(started, isTrue);
    expect(ended, isTrue);
    expect(changed, greaterThan(.25));
    expect(tester.takeException(), isNull);
  });
  testWidgets('AI tint uses one track and leaves played media white', (
    tester,
  ) async {
    const key = ValueKey('single-seek-track');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 48,
              child: RepaintBoundary(
                key: key,
                child: SliderTheme(
                  data: const SliderThemeData(
                    trackHeight: 2.5,
                    trackShape: SubtitleSeekTrackShape(
                      SubtitleProgress(
                        phase: SubtitlePhase.processing,
                        stage: SubtitleWorkStage.recognizing,
                        duration: Duration(seconds: 100),
                        position: Duration(seconds: 25),
                        completed: [
                          SubtitleTimeRange(
                            Duration.zero,
                            Duration(seconds: 50),
                          ),
                        ],
                        pending: SubtitleTimeRange(
                          Duration(seconds: 50),
                          Duration(seconds: 60),
                        ),
                      ),
                    ),
                  ),
                  child: CbSlider(
                    value: .25,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        return await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
      } finally {
        image.dispose();
      }
    });
    final coloredRows = <int>{};
    for (var y = 0; y < 48; y++) {
      for (var x = 0; x < 400; x++) {
        final index = (y * 400 + x) * 4;
        final r = bytes!.getUint8(index),
            g = bytes.getUint8(index + 1),
            b = bytes.getUint8(index + 2);
        if ((g > r + 50 && b > r + 30) || (r > g + 25 && g > b + 25)) {
          coloredRows.add(y);
        }
      }
    }
    expect(coloredRows, isNotEmpty);
    expect(
      coloredRows.every((y) => y >= 22 && y <= 25),
      isTrue,
      reason:
          'AI colors must stay inside the main track, with no second rail below it.',
    );
    final played = (24 * 400 + 40) * 4;
    expect(
      [
        bytes!.getUint8(played),
        bytes.getUint8(played + 1),
        bytes.getUint8(played + 2),
      ],
      [255, 255, 255],
    );
  });
  test(
    'timeline paints actual finished ranges rather than an unprocessed seek prefix',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      SubtitleTimelinePainter(
        const SubtitleProgress(
          phase: SubtitlePhase.processing,
          stage: SubtitleWorkStage.recognizing,
          duration: Duration(seconds: 100),
          position: Duration(seconds: 45),
          completed: [
            SubtitleTimeRange(Duration(seconds: 40), Duration(seconds: 50)),
          ],
          pending: SubtitleTimeRange(
            Duration(seconds: 50),
            Duration(seconds: 60),
          ),
        ),
      ).paint(canvas, const Size(100, 6));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 6);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      int channel(int x, int channel) =>
          bytes.getUint8((3 * 100 + x) * 4 + channel);
      expect(
        channel(10, 3),
        lessThan(100),
      ); // An unprocessed prefix stays neutral.
      expect(
        [channel(42, 0), channel(42, 1), channel(42, 2), channel(42, 3)],
        [97, 222, 201, 255],
      );
      expect(
        channel(55, 3),
        greaterThan(channel(10, 3)),
      ); // Pending amber is distinct.
      expect(channel(55, 3), lessThan(255));
      image.dispose();
      picture.dispose();
    },
  );
}
