import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/media/media_kit_playback.dart';
import 'package:cb_file_manager/ui/components/video/local_subtitle_overlay.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:shared_preferences/shared_preferences.dart';

class _Timeline extends mk.PlatformPlayer {
  _Timeline() : super(configuration: const mk.PlayerConfiguration()) {
    state = state.copyWith(duration: const Duration(minutes: 2));
  }
}

class _Playback extends PlaybackPlayer {
  _Playback() : super(player: mk.Player(platformPlayer: _Timeline()));
  @override
  String get subtitleSource => 'missing-subtitle-fixture.mp4';
  @override
  Future<int> subtitleAudioTrackOrdinal() async => 0;
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: const [Locale('en')],
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  setUp(
    () =>
        SharedPreferences.setMockInitialValues({'ai_subtitles_enabled': true}),
  );

  for (final local in [true, false]) {
    testWidgets(
      '${local ? 'local file' : 'URL'} uses the shared subtitle layer',
      (tester) async {
        final player = local
            ? VideoPlayer.file(
                file: File('subtitle-fixture.mp4'),
                autoPlay: false,
              )
            : VideoPlayer.url(
                streamingUrl: 'https://example.invalid/subtitle-fixture.mp4',
                fileName: 'subtitle-fixture.mp4',
                autoPlay: false,
              );
        await tester.pumpWidget(_app(player));
        await tester.pump();
        expect(find.byType(LocalSubtitleLayer), findsOneWidget);
        // Dispose before native media initialization. This checks the public
        // player's wiring, without launching a decoder or an E2E application.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('controls hide without stopping the shared AI session', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final models = LocalAiAdvisorService(prefs: prefs);
    GetIt.I.registerSingleton<LocalAiAdvisorService>(models);
    final playback = _Playback();
    addTearDown(() async {
      await playback.dispose();
      await models.dispose();
      await GetIt.I.reset();
    });
    Widget layer(bool controls) => _app(
      LocalSubtitleLayer(
        player: playback,
        controlsVisible: controls,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            if (controls)
              Align(
                alignment: Alignment.bottomCenter,
                child: LocalSubtitleControls(onSettings: () {}),
              ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(layer(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('ai-subtitle-control')), findsOneWidget);
    final sessionOwner = tester.state(find.byType(LocalSubtitleOverlay));
    final session = tester
        .widget<LocalSubtitleScope>(find.byType(LocalSubtitleScope))
        .notifier;
    expect(session, isNotNull);
    await tester.pumpWidget(layer(false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('ai-subtitle-control')), findsNothing);
    expect(tester.state(find.byType(LocalSubtitleOverlay)), same(sessionOwner));
    expect(
      tester
          .widget<LocalSubtitleScope>(find.byType(LocalSubtitleScope))
          .notifier,
      same(session),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
