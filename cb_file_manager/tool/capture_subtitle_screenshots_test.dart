// Opt-in production-widget captures with authored demo video/cues. This is not
// a native player recording, model benchmark or E2E runner. No user preferences,
// videos, database or model files are read. The sky illustration is original.
// flutter test --no-pub tool/capture_subtitle_screenshots_test.dart \
//   --dart-define=CB_CAPTURE_SCREENSHOTS=true
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/config/languages/vietnamese_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/local_ai/local_model_downloads.dart';
import 'package:cb_file_manager/services/local_ai/subtitle_model_catalog.dart';
import 'package:cb_file_manager/services/media/subtitle_cache.dart';
import 'package:cb_file_manager/services/media/subtitle_progress.dart';
import 'package:cb_file_manager/ui/components/video/subtitle_settings_panel.dart';
import 'package:cb_file_manager/ui/components/video/subtitle_status_overlay.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_app_bar.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_control_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Copy extends LocalizationsDelegate<AppLocalizations> {
  const _Copy();
  @override
  bool isSupported(Locale locale) => ['en', 'vi'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) async =>
      locale.languageCode == 'vi'
      ? VietnameseLocalizations()
      : EnglishLocalizations();
  @override
  bool shouldReload(_Copy old) => false;
}

const _original = '見上げると、夜空には無数の星が輝いています。';
String _caption(String language) => language == 'vi'
    ? 'Ngước nhìn lên, vô số vì sao đang tỏa sáng trên bầu trời đêm.'
    : 'Look up, and countless stars are shining in the night sky.';

SubtitleProgress _progress(String language, bool processing) =>
    SubtitleProgress(
      phase: processing ? SubtitlePhase.processing : SubtitlePhase.ready,
      stage: processing
          ? SubtitleWorkStage.translating
          : SubtitleWorkStage.idle,
      modelName: processing ? 'Hy-MT2 1.8B · Q4_K_M' : 'Whisper Small',
      sourceLanguage: 'ja',
      targetLanguage: language,
      duration: const Duration(minutes: 3, seconds: 20),
      position: const Duration(minutes: 1, seconds: 8),
      completed: const [
        SubtitleTimeRange(Duration.zero, Duration(minutes: 1, seconds: 42)),
      ],
      pending: processing
          ? const SubtitleTimeRange(
              Duration(minutes: 1, seconds: 42),
              Duration(minutes: 1, seconds: 50),
            )
          : null,
      cacheState: SubtitleCacheState.saved,
    );

void main() {
  testWidgets('Capture local subtitle player, CC menu and model settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      const window = MethodChannel('window_manager');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        window,
        (call) async => ['isMaximized', 'isFullScreen'].contains(call.method)
            ? false
            : true,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          window,
          null,
        ),
      );
      await tester.runAsync(() async {
        final fonts =
            jsonDecode(await rootBundle.loadString('FontManifest.json'))
                as List;
        for (final entry in fonts) {
          final loader = FontLoader(entry['family'] as String);
          for (final font in entry['fonts'] as List) {
            loader.addFont(rootBundle.load(font['asset'] as String));
          }
          await loader.load();
        }
        final fontPath = const String.fromEnvironment(
          'CB_SUBTITLE_JAPANESE_FONT',
          defaultValue: 'C:/Windows/Fonts/msgothic.ttc',
        );
        if (await File(fontPath).exists()) {
          final loader = FontLoader('DemoJapanese')
            ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
          await loader.load();
        }
      });
      sqfliteFfiInit();
      for (final language in ['en', 'vi']) {
        final root = await tester.runAsync(
          () => Directory.systemTemp.createTemp('subtitle-capture-'),
        );
        final db = await tester.runAsync(
          () => databaseFactoryFfi.openDatabase('${root!.path}/demo.sqlite'),
        );
        final cache = SubtitleCache(openDatabase: () async => db!);
        await tester.runAsync(() async {
          await cache.save(
            'demo-night-sky',
            await cache.revision(),
            0,
            102000,
            [LocalSubtitleCue(60000, 74000, _original, _caption(language))],
          );
        });
        // Isolated widget capture uses the test preference store.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({
          'ai_subtitles_enabled': true,
          'ai_subtitles_source': 'ja',
          'ai_subtitles_target': language,
          'ai_subtitles_bilingual': true,
          'selected_language': language,
          'local_ai_installed_models': jsonEncode(
            SubtitleModelCatalog.entries
                .where(
                  (e) =>
                      e.id == 'whisper/small' ||
                      e.purpose == LocalModelPurpose.translation,
                )
                .map(
                  (e) => InstalledLocalModel(
                    catalogId: e.id,
                    displayName: e.displayName,
                    localPath: '${root!.path}/${e.artifactFileName}',
                    sizeBytes: e.sizeBytes!,
                    installedAt: DateTime(2026, 11, 7),
                    runtimeArtifactId: e.artifactFileName,
                    purpose: e.purpose,
                  ).toJson(),
                )
                .toList(),
          ),
        });
        final prefs = await SharedPreferences.getInstance();
        final models = LocalAiAdvisorService(
          prefs: prefs,
          documentsDirectoryProvider: () async => root!,
        );
        final downloads = LocalModelDownloads(models);
        final boundaryKey = GlobalKey();
        final navigatorKey = GlobalKey<NavigatorState>();
        try {
          Future<void> mount(bool processing) async {
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundaryKey,
                child: MaterialApp(
                  navigatorKey: navigatorKey,
                  debugShowCheckedModeBanner: false,
                  theme: CbThemeBuilder.build(
                    brightness: Brightness.dark,
                    accent: Colors.lightBlue,
                  ),
                  locale: Locale(language),
                  supportedLocales: const [Locale('en'), Locale('vi')],
                  localizationsDelegates: const [
                    _Copy(),
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  home: Scaffold(
                    backgroundColor: Colors.black,
                    appBar: VideoPlayerAppBar(
                      title: 'Night sky - demo.mp4',
                      onClose: () {},
                    ),
                    body: DefaultTextStyle.merge(
                      style: const TextStyle(
                        fontFamilyFallback: ['DemoJapanese'],
                      ),
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: CustomPaint(painter: _DemoSky()),
                          ),
                          Positioned.fill(
                            child: SubtitleCaptionOverlay(
                              caption: '$_original\n${_caption(language)}',
                              controlsVisible: true,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _Controls(
                              progress: _progress(language, processing),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }

          Future<void> capture(String scene) async {
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final directory = Directory(
                  '../screenshots/features/local_subtitles/$language',
                );
                await directory.create(recursive: true);
                await File(
                  '${directory.path}/$scene.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }

          await mount(false);
          await capture('player');
          await mount(true);
          await tester.tap(find.byKey(const ValueKey('ai-subtitle-control')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.byKey(const ValueKey('ai-subtitle-status')),
            findsOneWidget,
          );
          await capture('progress');
          navigatorKey.currentState!.pop();
          await tester.pump(const Duration(milliseconds: 300));
          final dialogContext = navigatorKey.currentState!.context;
          if (!dialogContext.mounted) {
            throw StateError('Capture navigator is unmounted');
          }
          // Only UI is shown; all settings/cache data belong to this test process.
          final dialog = showDialog<void>(
            context: dialogContext,
            builder: (context) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.aiSubtitles),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: SubtitleSettingsPanel(
                    models: models,
                    downloads: downloads,
                    cache: cache,
                    onManageModels: () {},
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppLocalizations.of(context)!.close),
                ),
              ],
            ),
          );
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.runAsync(cache.stats);
          await tester.pump();
          await capture('models');
          navigatorKey.currentState!.pop();
          await tester.pump(const Duration(milliseconds: 300));
          await dialog;
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          downloads.dispose();
          await models.dispose();
          await tester.runAsync(() async {
            await db!.close();
            await root!.delete(recursive: true);
          });
        }
      }
    } finally {
      debugDisableShadows = oldShadows;
    }
  }, skip: !const bool.fromEnvironment('CB_CAPTURE_SCREENSHOTS'));
}

class _Controls extends StatelessWidget {
  final SubtitleProgress progress;
  const _Controls({required this.progress});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Color(0xB3000000)],
      ),
    ),
    child: Row(
      children: [
        VideoPlayerControlButton(
          icon: PhosphorIconsLight.play,
          onPressed: () {},
          size: 40,
          padding: 10,
        ),
        const SizedBox(width: 8),
        const Text(
          '01:08',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              trackShape: SubtitleSeekTrackShape(progress),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: CbSlider(
              value: 68,
              min: 0,
              max: 200,
              activeColor: Colors.white,
              inactiveColor: Colors.white24,
              onChanged: (_) {},
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          '03:20',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(width: 12),
        VideoPlayerControlButton(
          icon: PhosphorIconsLight.speakerHigh,
          onPressed: () {},
        ),
        SizedBox(
          width: 80,
          child: VideoPlayerVolumeSlider(value: 70, onChanged: (_) {}),
        ),
        SubtitleControlButton(
          progress: progress,
          onSettings: () {},
          onRetry: () {},
          onRegenerate: () {},
        ),
        VideoPlayerControlButton(
          icon: PhosphorIconsLight.dotsThree,
          onPressed: () {},
        ),
        VideoPlayerControlButton(
          icon: PhosphorIconsLight.cornersOut,
          onPressed: () {},
        ),
      ],
    ),
  );
}

/// Original procedural artwork used as the demo video's still frame.
class _DemoSky extends CustomPainter {
  const _DemoSky();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF020711), Color(0xFF101D36), Color(0xFF03060D)],
        ).createShader(Offset.zero & size),
    );
    final random = math.Random(82);
    for (var i = 0; i < 240; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .4 + random.nextDouble() * 1.2,
        Paint()
          ..color = Colors.white.withValues(
            alpha: .12 + random.nextDouble() * .65,
          ),
      );
    }
    final center = Offset(size.width * .63, size.height * .50);
    final radius = size.height * .38;
    canvas.drawCircle(
      center,
      radius + 12,
      Paint()
        ..color = const Color(0xFF378FC8).withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.65, -.6),
          radius: 1.15,
          colors: const [
            Color(0xFF58BDDD),
            Color(0xFF1D638D),
            Color(0xFF0B2548),
            Color(0xFF010811),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
    for (var i = 0; i < 14; i++) {
      final path = Path();
      final y = center.dy - radius + i * radius / 6;
      path.moveTo(center.dx - radius, y);
      path.cubicTo(
        center.dx - radius * .25,
        y - 70,
        center.dx + radius * .4,
        y + 70,
        center.dx + radius,
        y - 10,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: .06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (10 + i % 4 * 5).toDouble(),
      );
    }
    canvas.restore();
    final title = TextPainter(
      text: const TextSpan(
        text: 'NIGHT SKY\nAn orbital notebook',
        style: TextStyle(
          color: Color(0xFFCEDEEE),
          fontFamily: 'Inter',
          fontSize: 22,
          height: 1.7,
          letterSpacing: 3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, Offset(size.width * .075, size.height * .18));
    final note = TextPainter(
      text: const TextSpan(
        text: 'DEMO VIDEO',
        style: TextStyle(
          color: Colors.white38,
          fontFamily: 'Inter',
          fontSize: 11,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    note.paint(canvas, Offset(size.width * .075, size.height * .18 + 98));
  }

  @override
  bool shouldRepaint(_DemoSky old) => false;
}
