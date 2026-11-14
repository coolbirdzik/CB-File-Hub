import 'dart:ui' show PointerDeviceKind;

import 'package:cb_file_manager/ui/components/video/video_player/video_player_advanced_menu.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_context_menu_region.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_control_buttons.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_desktop_toolbar.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  for (final width in [320.0, 480.0, 640.0, 960.0]) {
    testWidgets('cut and menu stay visible exactly once at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var cuts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: VideoPlayerDesktopToolbar(
                  playPause: const SizedBox(width: 56, height: 48),
                  seekControl: Slider(value: 1, max: 10, onChanged: (_) {}),
                  position: const Text('00:01'),
                  duration: const Text('10:00'),
                  cut: VideoPlayerControlButton(
                    icon: PhosphorIconsLight.scissors,
                    tooltip: 'Lossless cut',
                    onPressed: () => cuts++,
                  ),
                  menu: VideoPlayerAdvancedMenu(onLosslessCut: () => cuts++),
                  volume: const SizedBox(width: 130),
                  subtitles: const SizedBox(width: 40),
                  playlist: const SizedBox(width: 40),
                  fullscreen: const SizedBox(width: 40),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Lossless cut'), findsOneWidget);
      expect(find.byTooltip('Advanced Controls'), findsOneWidget);
      await tester.tap(find.byTooltip('Lossless cut'));
      expect(cuts, 1);
      await tester.tap(find.byTooltip('Advanced Controls'));
      await tester.pumpAndSettle();
      expect(find.text('Lossless cut'), findsOneWidget);
      await tester.tap(find.text('Lossless cut'));
      await tester.pumpAndSettle();
      expect(cuts, 2);
      expect(tester.takeException(), isNull);
    });
  }

  Future<void> pumpRegion(
    WidgetTester tester,
    VideoPlayerAdvancedMenu menu, {
    bool Function()? isCurrent,
    VoidCallback? onControl,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Stack(
              children: [
                Positioned.fill(
                  child: VideoPlayerContextMenuRegion(
                    onRequested: (position) =>
                        menu.showAt(context, position, isCurrent: isCurrent),
                    child: const ColoredBox(
                      key: ValueKey('video'),
                      color: Colors.black,
                    ),
                  ),
                ),
                if (onControl != null)
                  Positioned(
                    left: 20,
                    top: 20,
                    child: TextButton(
                      onPressed: onControl,
                      child: const Text('Control'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('right-click opens the shared menu and cut dispatches once', (
    tester,
  ) async {
    var cuts = 0;
    await pumpRegion(
      tester,
      VideoPlayerAdvancedMenu(onPlayPause: () {}, onLosslessCut: () => cuts++),
    );
    await tester.tapAt(
      const Offset(240, 120),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Lossless cut'), findsOneWidget);
    await tester.tap(find.text('Lossless cut'));
    await tester.pumpAndSettle();
    expect(cuts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch long press opens the menu without triggering playback', (
    tester,
  ) async {
    var plays = 0;
    await pumpRegion(
      tester,
      VideoPlayerAdvancedMenu(onPlayPause: () => plays++),
    );
    await tester.longPressAt(const Offset(240, 120));
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    expect(plays, 0);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(plays, 1);
  });

  testWidgets('dismissal and a stale source do not execute cut', (
    tester,
  ) async {
    var cuts = 0;
    await pumpRegion(
      tester,
      VideoPlayerAdvancedMenu(onLosslessCut: () => cuts++),
      isCurrent: () => false,
    );
    await tester.longPressAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lossless cut'));
    await tester.pumpAndSettle();
    expect(cuts, 0);
    await tester.longPressAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 550));
    await tester.pumpAndSettle();
    expect(find.text('Lossless cut'), findsNothing);
    expect(cuts, 0);
  });

  testWidgets('loading cut stays discoverable and disabled', (tester) async {
    var cuts = 0;
    await pumpRegion(
      tester,
      VideoPlayerAdvancedMenu(
        onLosslessCut: () => cuts++,
        losslessCutEnabled: false,
      ),
    );
    await tester.longPressAt(const Offset(240, 100));
    await tester.pumpAndSettle();
    expect(find.text('Lossless cut'), findsOneWidget);
    final entry = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Lossless cut'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    expect(entry.enabled, isFalse);
    await tester.tap(find.text('Lossless cut'));
    await tester.pumpAndSettle();
    expect(cuts, 0);
  });

  testWidgets('controls above the video keep their own taps', (tester) async {
    var controls = 0;
    await pumpRegion(
      tester,
      const VideoPlayerAdvancedMenu(),
      onControl: () => controls++,
    );
    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
    expect(controls, 1);
    expect(find.text('Take Screenshot'), findsNothing);
  });
}
