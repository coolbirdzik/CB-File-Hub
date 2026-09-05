import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_advanced_menu.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_app_bar.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_control_buttons.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/video_player_full_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('video player chrome keeps a valid Windows AX tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var tick = 0;
    var showChrome = true;
    late StateSetter updateChrome;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateChrome = setState;
            return Scaffold(
              appBar: showChrome
                  ? const VideoPlayerAppBar(title: 'semantics-fixture.mp4')
                  : null,
              backgroundColor: Colors.black,
              body: Builder(
                builder: (context) {
                  if (!showChrome) return const SizedBox.expand();
                  final even = tick.isEven;
                  return Column(
                    children: <Widget>[
                      Slider(
                        value: (tick % 100).toDouble(),
                        min: 0,
                        max: 100,
                        onChanged: (_) {},
                      ),
                      Row(
                        children: <Widget>[
                          VideoPlayerControlButton(
                            icon: PhosphorIconsLight.skipBack,
                            onPressed: () {},
                            tooltip: 'Rewind 10s',
                          ),
                          VideoPlayerControlButton(
                            icon: even
                                ? PhosphorIconsLight.speakerHigh
                                : PhosphorIconsLight.speakerSlash,
                            onPressed: () {},
                            tooltip: even ? 'Mute' : 'Unmute',
                          ),
                          VideoPlayerControlButton(
                            icon: PhosphorIconsLight.cornersOut,
                            onPressed: () {},
                            tooltip: 'Enter fullscreen',
                          ),
                          VideoPlayerAdvancedMenu(
                            playbackSpeed: even ? 1.0 : 1.25,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 40; i++) {
      updateChrome(() => tick++);
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Real playback auto-hides both the app bar and bottom controls. Exercise
    // the same removal/reinsertion of all tooltip traversal anchors.
    for (var i = 0; i < 8; i++) {
      updateChrome(() => showChrome = false);
      await tester.pump(const Duration(milliseconds: 100));
      updateChrome(() {
        tick++;
        showChrome = true;
      });
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Three window-caption tooltips plus four bottom-control tooltips must
    // retain at least seven separate OverlayPortal traversal anchors during
    // rebuilds. Flutter may expose an additional anchor for the popup menu.
    expect(_tooltipTraversalParents(tester).length, greaterThanOrEqualTo(7));

    final maximizeLabel = find.byTooltip('Restore').evaluate().isNotEmpty
        ? 'Restore'
        : 'Maximize';

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    for (final label in <String>[
      'Rewind 10s',
      tick.isEven ? 'Mute' : 'Unmute',
      'Enter fullscreen',
      'Advanced Controls',
      'Minimize',
      maximizeLabel,
      'Close',
    ]) {
      await mouse.moveTo(tester.getCenter(find.byTooltip(label)));
      await tester.pump(const Duration(milliseconds: 850));
    }
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    await mouse.removePointer();

    handle.dispose();
  });

  testWidgets('real local video playback keeps a valid Windows AX tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final sample = File(
      p.join(
        Directory.current.path,
        'integration_test',
        'samples',
        'file_example_MP4_1920_18MG.mp4',
      ),
    );
    expect(sample.existsSync(), isTrue, reason: sample.path);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('vi'), Locale('en')],
        home: VideoPlayerFullScreen(file: sample),
      ),
    );

    // Wait for media_kit to open the real MP4 and begin advancing position.
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(VideoPlayerFullScreen), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 300));
    // Real desktop chrome has three caption portals plus seek, mute, volume,
    // advanced-menu, and fullscreen portals. None may be lost to merging.
    expect(_tooltipTraversalParents(tester).length, greaterThanOrEqualTo(8));

    for (var i = 0; i < 6; i++) {
      await mouse.moveTo(Offset(300 + i * 20, 240));
      await tester.pump(const Duration(milliseconds: 300));
      // Let the running player's three-second timer remove the app bar and
      // controls, then show them again on the next pointer move.
      await tester.pump(const Duration(seconds: 4));
    }
    await mouse.removePointer();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    handle.dispose();
  });
}

Set<Object> _tooltipTraversalParents(WidgetTester tester) {
  final root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  expect(root, isNotNull);

  final traversalParents = <Object>{};
  void collect(SemanticsNode node) {
    final identifier = node.getSemanticsData().traversalParentIdentifier;
    if (identifier != null) traversalParents.add(identifier);
    node.visitChildren((child) {
      collect(child);
      return true;
    });
  }

  collect(root!);
  return traversalParents;
}
