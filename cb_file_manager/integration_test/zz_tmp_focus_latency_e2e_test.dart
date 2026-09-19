// TEMPORARY diagnostic: how long does it take for a grid card to show as
// selected after a click / arrow key? Delete after the investigation.
import 'dart:io';

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/main.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/ui/components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'e2e_helpers.dart';
import 'e2e_keys.dart';
import 'e2e_sandbox_paths.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await E2ESandboxPaths.install();
  });
  tearDownAll(() async {
    await E2ESandboxPaths.uninstall();
  });

  final sample = p.join(
    Directory.current.path,
    'integration_test',
    'samples',
    'file_example_MP4_1920_18MG.mp4',
  );

  Finder cardOf(String path) => find.byKey(ValueKey('file-grid-item-$path'));

  bool isHighlighted(Finder card) {
    if (card.evaluate().isEmpty) return false;
    return find
        .descendant(of: card, matching: find.byType(Container))
        .evaluate()
        .map((e) => e.widget as Container)
        .any((c) {
          final d = c.foregroundDecoration;
          return d is BoxDecoration && (d.color != null || d.gradient != null);
        });
  }

  for (final previewVisible in [true, false]) {
    testWidgets('focus latency probe (preview=$previewVisible)', (
      WidgetTester tester,
    ) async {
      await UserPreferences.instance.init();
      await UserPreferences.instance.setViewMode(ViewMode.grid);
      await UserPreferences.instance.setPreviewPaneVisible(previewVisible);

      final dir = await Directory.systemTemp.createTemp('cb_e2e_latency_');
      final videos = <File>[];
      for (var i = 0; i < 4; i++) {
        final f = File(p.join(dir.path, 'a_video_$i.mp4'));
        File(sample).copySync(f.path);
        videos.add(f);
      }
      final texts = <File>[];
      for (var i = 0; i < 60; i++) {
        final f = File(
          p.join(dir.path, 'b_note_${i.toString().padLeft(2, '0')}.txt'),
        )..writeAsStringSync('n$i');
        texts.add(f);
      }

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      final timings = <FrameTiming>[];
      void onTimings(List<FrameTiming> t) => timings.addAll(t);

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 6)); // thumbnails settle
        SchedulerBinding.instance.addTimingsCallback(onTimings);

        String frameStats() {
          if (timings.isEmpty) return 'no frames';
          final builds = timings.map((t) => t.buildDuration.inMicroseconds);
          final rasters = timings.map((t) => t.rasterDuration.inMicroseconds);
          final maxB = builds.reduce((a, b) => a > b ? a : b) / 1000;
          final maxR = rasters.reduce((a, b) => a > b ? a : b) / 1000;
          return 'frames=${timings.length} '
              'maxBuild=${maxB.toStringAsFixed(1)}ms '
              'maxRaster=${maxR.toStringAsFixed(1)}ms';
        }

        Future<void> measureClick(String label, File target) async {
          final card = cardOf(target.path);
          final found = await pumpUntilFound(tester, card);
          if (!found) {
            final keys = find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key as ValueKey<String>).value.startsWith('file-'),
                )
                .evaluate()
                .map((e) => (e.widget.key as ValueKey<String>).value)
                .take(5)
                .toList();
            print('[LATENCY] card missing for $label; sample keys=$keys');
            return;
          }
          await tester.ensureVisible(card);
          await tester.pump(const Duration(milliseconds: 300));
          final layer = find
              .descendant(
                of: card,
                matching: find.byType(OptimizedInteractionLayer),
              )
              .first;
          final center = tester.getCenter(layer);
          timings.clear();
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await gesture.addPointer(location: center);
          final sw = Stopwatch()..start();
          await gesture.down(center);
          int? downMs;
          // Hold the button ~120ms, like a normal click.
          while (sw.elapsedMilliseconds < 120) {
            await tester.pump();
            if (downMs == null && isHighlighted(card)) {
              downMs = sw.elapsedMilliseconds;
            }
          }
          final upAt = sw.elapsedMilliseconds;
          await gesture.up();
          int? upMs;
          while (downMs == null && sw.elapsedMilliseconds < 1500) {
            await tester.pump();
            if (isHighlighted(card)) {
              upMs = sw.elapsedMilliseconds - upAt;
              break;
            }
          }
          await tester.pump(const Duration(milliseconds: 400));
          await gesture.removePointer();
          print(
            '[LATENCY] click $label: '
            '${downMs != null
                ? 'highlight ${downMs}ms after DOWN'
                : upMs != null
                ? 'highlight only after UP (+${upMs}ms after release)'
                : 'never highlighted'} '
            '| ${frameStats()}',
          );
          await tester.pump(const Duration(milliseconds: 600));
        }

        Set<String> highlightedPaths() => find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith(
                    'file-grid-item-',
                  ),
            )
            .evaluate()
            .map((e) => (e.widget.key as ValueKey<String>).value)
            .where((k) => isHighlighted(find.byKey(ValueKey(k))))
            .toSet();

        List<String> builtPaths(String ext) =>
            find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key as ValueKey<String>).value.startsWith(
                        'file-grid-item-',
                      ),
                )
                .evaluate()
                .map(
                  (e) => (e.widget.key as ValueKey<String>).value.substring(
                    'file-grid-item-'.length,
                  ),
                )
                .where((path) => path.endsWith(ext))
                .toList()
              ..sort();

        Future<void> measureArrow(String label) async {
          final before = highlightedPaths();
          timings.clear();
          final sw = Stopwatch()..start();
          await tester.sendKeyDownEvent(
            LogicalKeyboardKey.arrowRight,
            physicalKey: PhysicalKeyboardKey.arrowRight,
          );
          int? ms;
          String? now;
          while (sw.elapsedMilliseconds < 1500) {
            await tester.pump();
            final h = highlightedPaths().difference(before);
            if (h.isNotEmpty) {
              ms = sw.elapsedMilliseconds;
              now = p.basename(h.first);
              break;
            }
          }
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.arrowRight,
            physicalKey: PhysicalKeyboardKey.arrowRight,
          );
          await tester.pump(const Duration(milliseconds: 400));
          print(
            '[LATENCY] arrow $label -> $now: '
            '${ms != null ? 'highlight after ${ms}ms' : 'never highlighted'} '
            '| ${frameStats()}',
          );
          await tester.pump(const Duration(milliseconds: 600));
        }

        final builtVideoPaths = builtPaths('.mp4');
        final builtTextPaths = builtPaths('.txt');
        print(
          '[LATENCY] built videos=${builtVideoPaths.length} '
          'texts=${builtTextPaths.length}',
        );
        // Use the files created above rather than indexing only the currently
        // built sliver children. The grid lazily builds visible cards, so a
        // valid file can be absent from builtPaths() even though it will be
        // available after pumpUntilFound().
        await measureClick('text #1', texts[0]);
        await measureClick('text #2', texts[1]);
        await measureClick('video #1', videos[0]);
        await measureClick('video #2', videos[1]);
        if (previewVisible) {
          await measureClick('video before trace', videos[2]);
          await tester.pump(const Duration(seconds: 2));
          debugProfileBuildsEnabled = true;
          await binding.traceAction(() async {
            await measureClick('text after video (traced)', texts[2]);
          }, reportKey: 'timeline_video_to_text');
          debugProfileBuildsEnabled = false;
        } else {
          await measureClick('text after video', texts[2]);
        }
        await measureClick('arrow start', videos[3]);
        for (var i = 0; i < 6; i++) {
          await measureArrow('#$i');
        }
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(onTimings);
        await e2eTearDown(tester, dir);
      }
    });
  }
}
