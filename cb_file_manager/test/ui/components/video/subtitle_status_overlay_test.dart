import 'dart:ui' as ui;

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/media/subtitle_progress.dart';
import 'package:cb_file_manager/ui/components/video/subtitle_status_overlay.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    SubtitleProgress progress, {
    Size size = const Size(720, 420),
    bool controls = true,
    String caption = 'Hello world',
    VoidCallback? retry,
    VoidCallback? settings,
    ValueChanged<bool>? onEnabledChanged,
    VoidCallback? regenerate,
    VoidCallback? export,
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
                    caption: caption,
                    controlsVisible: controls,
                    progress: progress,
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
                            onEnabledChanged: onEnabledChanged ?? (_) {},
                            onSettings: settings ?? () {},
                            onRetry: retry ?? () {},
                            onRegenerate: regenerate,
                            onExport: export,
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
            find.byKey(const ValueKey('ai-subtitle-settings-control')),
          )
          .tooltip,
      contains('Using saved subtitles'),
    );
    expect(find.byKey(const ValueKey('ai-subtitle-busy')), findsNothing);
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('ai-subtitle-settings-control')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-regenerate')));
    await tester.pumpAndSettle();
    expect(regenerated, isTrue);
  });

  testWidgets('CC toggles directly and progress is the settings trigger', (
    tester,
  ) async {
    final toggles = <bool>[];
    var settingsOpened = 0;
    const progress = SubtitleProgress(
      phase: SubtitlePhase.ready,
      duration: Duration(minutes: 2),
      position: Duration.zero,
      completed: [SubtitleTimeRange(Duration.zero, Duration(minutes: 1))],
    );
    final cc = find.byKey(const ValueKey('ai-subtitle-control'));
    final settings = find.byKey(const ValueKey('ai-subtitle-settings-control'));
    final popover = find.byKey(const ValueKey('ai-subtitle-status'));
    await show(
      tester,
      progress,
      onEnabledChanged: toggles.add,
      settings: () => settingsOpened++,
    );
    expect(
      find.descendant(of: settings, matching: find.text('50%')),
      findsOneWidget,
    );
    await tester.tap(cc);
    await tester.pumpAndSettle();
    expect(toggles, [false]);
    expect(popover, findsNothing);
    expect(settingsOpened, 0);
    await tester.tap(find.text('50%'));
    await tester.pumpAndSettle();
    expect(popover, findsOneWidget);
    expect(toggles, [false]);
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-settings')));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);

    await show(
      tester,
      const SubtitleProgress(
        phase: SubtitlePhase.off,
        duration: Duration.zero,
        position: Duration.zero,
      ),
      onEnabledChanged: toggles.add,
      settings: () => settingsOpened++,
    );
    expect(find.text('50%'), findsNothing);
    await tester.tap(settings);
    expect(settingsOpened, 2);
    await tester.tap(cc);
    expect(toggles, [false, true]);
    expect(popover, findsNothing);
  });

  testWidgets('finished subtitles can be exported as SRT on request', (
    tester,
  ) async {
    var exported = 0;
    const progress = SubtitleProgress(
      phase: SubtitlePhase.ready,
      duration: Duration(minutes: 2),
      position: Duration.zero,
      completed: [SubtitleTimeRange(Duration.zero, Duration(seconds: 40))],
    );
    await show(tester, progress, export: () => exported++);
    await tester.tap(
      find.byKey(const ValueKey('ai-subtitle-settings-control')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-export')));
    await tester.pumpAndSettle();
    expect(exported, 1);
    await show(
      tester,
      const SubtitleProgress(
        phase: SubtitlePhase.processing,
        duration: Duration(minutes: 2),
        position: Duration.zero,
        completed: [],
      ),
      export: () => exported++,
    );
    await tester.tap(
      find.byKey(const ValueKey('ai-subtitle-settings-control')),
    );
    // The busy spinner never settles; give the menu its opening time.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('ai-subtitle-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-subtitle-export')), findsNothing);
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
      find.byKey(const ValueKey('ai-subtitle-settings-control')),
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
        find.byKey(const ValueKey('ai-subtitle-settings-control')),
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
  testWidgets('the icon popover opens without overflow in a PiP window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await show(
      tester,
      const SubtitleProgress(
        phase: SubtitlePhase.failed,
        modelName: 'Whisper Large v3 Turbo · Q5_0',
        sourceLanguage: 'ja',
        targetLanguage: 'vi',
        duration: Duration(minutes: 2),
        position: Duration.zero,
        completed: [SubtitleTimeRange(Duration.zero, Duration(seconds: 30))],
        error:
            'Speech model could not be loaded because the file is missing '
            'or was moved to another folder.',
      ),
      size: const Size(320, 180),
      regenerate: () {},
      export: () {},
    );
    await tester.tap(
      find.byKey(const ValueKey('ai-subtitle-settings-control')),
    );
    await tester.pumpAndSettle();
    for (final key in [
      'ai-subtitle-settings',
      'ai-subtitle-retry',
      'ai-subtitle-export',
      'ai-subtitle-regenerate',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('Generating subtitles…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading appears in the subtitle area with controls hidden', (
    tester,
  ) async {
    await show(
      tester,
      const SubtitleProgress(
        phase: SubtitlePhase.loading,
        stage: SubtitleWorkStage.loadingSpeech,
        duration: Duration.zero,
        position: Duration.zero,
      ),
      controls: false,
      caption: '',
    );
    expect(find.byKey(const ValueKey('ai-subtitle-control')), findsNothing);
    expect(find.text('Loading speech model'), findsOneWidget);
  });

  for (final size in [const Size(720, 420), const Size(240, 120)]) {
    testWidgets('system status is distinct from dialogue at $size', (
      tester,
    ) async {
      const progress = SubtitleProgress(
        phase: SubtitlePhase.loading,
        stage: SubtitleWorkStage.unloadingModels,
        duration: Duration(minutes: 2),
        position: Duration.zero,
      );
      final status = find.byKey(const ValueKey('ai-subtitle-system-status'));
      final caption = find.byKey(const ValueKey('ai-subtitle-caption'));
      await show(tester, progress, size: size, caption: '');
      expect(status, findsOneWidget);
      expect(caption, findsNothing);
      expect(
        find.descendant(of: status, matching: find.byType(CbLoadingText)),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final statusText = tester.widget<Text>(
        find.text('Unloading previous models'),
      );
      final surface = tester.widget<CbSurface>(status);
      final colors = CbColorTokens.of(Brightness.dark, Colors.blue);
      expect(surface.radius, CbRadii.sm);
      expect(surface.color, colors.surfaceOverlay);
      expect(surface.level, CbSurfaceLevel.flat);
      final loading = tester.widget<CbLoadingText>(
        find.descendant(of: status, matching: find.byType(CbLoadingText)),
      );
      expect(loading.baseColor, colors.textSecondary);
      expect(loading.highlightColor, isNot(loading.baseColor));
      expect(statusText.style!.fontFamily, CbTypography.uiFamily);
      expect(statusText.style!.fontWeight, CbTypography.regular);
      final decoration =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: status,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.border, isNull);
      expect(tester.getSize(status).width, lessThan(size.width));
      expect(tester.takeException(), isNull);

      await show(tester, progress, size: size);
      expect(status, findsNothing);
      expect(caption, findsOneWidget);
      final dialogue = tester.widget<Text>(caption);
      expect(dialogue.style!.color, Colors.white);
      expect(
        dialogue.style!.fontSize,
        greaterThan(statusText.style!.fontSize!),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('caption and CC reflect each current subtitle work stage', (
    tester,
  ) async {
    for (final (stage, phase, label) in [
      (
        SubtitleWorkStage.unloadingModels,
        SubtitlePhase.loading,
        'Unloading previous models',
      ),
      (
        SubtitleWorkStage.readingCache,
        SubtitlePhase.loading,
        'Checking saved subtitles',
      ),
      (
        SubtitleWorkStage.loadingSpeech,
        SubtitlePhase.loading,
        'Loading speech model',
      ),
      (
        SubtitleWorkStage.recognizing,
        SubtitlePhase.processing,
        'Recognizing audio',
      ),
      (
        SubtitleWorkStage.loadingTranslation,
        SubtitlePhase.processing,
        'Loading translation model',
      ),
      (
        SubtitleWorkStage.translating,
        SubtitlePhase.processing,
        'Translating subtitles',
      ),
      (
        SubtitleWorkStage.idle,
        SubtitlePhase.loading,
        'Loading subtitle model…',
      ),
    ]) {
      await show(
        tester,
        SubtitleProgress(
          phase: phase,
          stage: stage,
          duration: const Duration(minutes: 2),
          position: Duration.zero,
        ),
        caption: '',
      );
      expect(find.text(label), findsOneWidget);
      expect(find.text('Generating subtitles…'), findsNothing);
      expect(
        tester
            .widget<PopupMenuButton<dynamic>>(
              find.byKey(const ValueKey('ai-subtitle-settings-control')),
            )
            .tooltip,
        contains(label),
      );
    }
  });

  testWidgets('CC counts finished ranges and shows wait text only in gaps', (
    tester,
  ) async {
    SubtitleProgress progressAt(int seconds) => SubtitleProgress(
      phase: SubtitlePhase.processing,
      duration: const Duration(seconds: 100),
      position: Duration(seconds: seconds),
      completed: const [
        SubtitleTimeRange(Duration.zero, Duration(seconds: 5)),
        SubtitleTimeRange(Duration(seconds: 40), Duration(seconds: 60)),
      ],
      pending: const SubtitleTimeRange(
        Duration(seconds: 60),
        Duration(seconds: 68),
      ),
    );

    await show(tester, progressAt(60), caption: '');
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('Generating subtitles…'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-subtitle-system-status')),
      findsOneWidget,
    );

    await show(tester, progressAt(45), caption: '');
    expect(find.text('25%'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-subtitle-caption')), findsNothing);
    expect(
      find.byKey(const ValueKey('ai-subtitle-system-status')),
      findsNothing,
    );
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
    await tester.tap(
      find.byKey(const ValueKey('ai-subtitle-settings-control')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Model could not load'), findsOneWidget);
    // Actions are icon-only; their labels live in tooltips.
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-retry')));
    expect(retried, isTrue);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ai-subtitle-settings-control')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-settings')));
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
