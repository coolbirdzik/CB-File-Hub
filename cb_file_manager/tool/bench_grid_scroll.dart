// Profiles the real application shell and grid. The driver only scrolls;
// it never selects, opens, renames, moves or deletes source files.
// Build with: flutter build windows --profile -t tool/bench_grid_scroll.dart
// Run with CB_STARTUP_TABS pointing at the folder and CB_SECONDARY_WINDOW=1:
//   cb_file_hub.exe <folder> <output.json>
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cb_file_manager/main.dart' as app;
import 'package:cb_file_manager/ui/screens/folder_list/components/file_grid_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/folder_grid_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/folder_thumbnail.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/widgets/lazy_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage: cb_file_hub.exe <folder> <output.json>');
    exit(64);
  }
  final folder = p.normalize(p.absolute(args[0]));
  final output = File(args[1]).absolute;
  if (p.isWithin(folder, output.path)) {
    throw ArgumentError('Benchmark output must be outside the source folder.');
  }
  app.main(const []);
  unawaited(_profile(folder, output));
}

(ScrollPosition, FolderListState)? _findGrid(String folder) {
  (ScrollPosition, FolderListState)? result;
  void visit(Element element) {
    if (result != null) return;
    final widget = element.widget;
    final itemPath = switch (widget) {
      FileGridItem() => widget.file.path,
      FolderGridItem() => widget.folder.path,
      _ => null,
    };
    if (itemPath != null && p.equals(p.dirname(itemPath), folder)) {
      final scroll = Scrollable.maybeOf(element);
      if (scroll != null && scroll.position.hasContentDimensions) {
        result = (scroll.position, element.read<FolderListBloc>().state);
        return;
      }
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return result;
}

void _setBenchmarkZoom(String folder, int zoom) {
  FolderListBloc? bloc;
  void visit(Element element) {
    if (bloc != null) return;
    final itemPath = switch (element.widget) {
      FileGridItem widget => widget.file.path,
      FolderGridItem widget => widget.folder.path,
      _ => null,
    };
    if (itemPath != null && p.equals(p.dirname(itemPath), folder)) {
      bloc = element.read<FolderListBloc>();
      return;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  final found = bloc;
  if (found == null) throw StateError('Grid not found for zoom override');
  // Benchmark-only state: do not persist a different folder preference.
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  found.emit(found.state.copyWith(gridZoomLevel: zoom));
}

Map<String, int> _mountedThumbnails() {
  final counts = <String, int>{'video': 0, 'folder': 0};
  void visit(Element element) {
    if (element.widget is LazyVideoThumbnail) {
      counts['video'] = counts['video']! + 1;
    } else if (element.widget is FolderThumbnail) {
      counts['folder'] = counts['folder']! + 1;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return counts;
}

Map<String, num> _distribution(List<int> micros) {
  micros.sort();
  double percentile(double fraction) =>
      micros[(fraction * (micros.length - 1)).round()] / 1000;
  return {
    'p50_ms': percentile(.5),
    'p95_ms': percentile(.95),
    'p99_ms': percentile(.99),
    'max_ms': micros.last / 1000,
  };
}

Future<void> _profile(String folder, File output) async {
  final results = <Map<String, dynamic>>[];
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    (ScrollPosition, FolderListState)? grid;
    while (grid == null || grid.$1.maxScrollExtent <= 0 || grid.$2.isLoading) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Production grid did not become ready for $folder');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      grid = _findGrid(folder);
    }
    await windowManager.ensureInitialized();
    await windowManager.setTitle('CB grid scroll profile');
    await windowManager.setSize(const Size(1280, 900));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
    await windowManager.focus();
    await Future<void>.delayed(const Duration(seconds: 2));
    final zoom = int.tryParse(Platform.environment['CB_BENCH_ZOOM'] ?? '');
    if (zoom != null) {
      _setBenchmarkZoom(folder, zoom);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final position = _findGrid(folder)!.$1;
    final state = _findGrid(folder)!.$2;
    final scrollExtent = position.maxScrollExtent;
    final viewport = position.viewportDimension;
    final samples = <FrameTiming>[];
    bool capture = false;
    final offsetSteps = <double>[];
    final motionGaps = <int>[];
    bool motionActive = false;
    Duration? lastMotionStamp;
    var previousOffset = position.pixels;
    SchedulerBinding.instance.addPersistentFrameCallback((stamp) {
      if (!capture || !motionActive) return;
      final delta = (position.pixels - previousOffset).abs();
      if (delta > .001) {
        offsetSteps.add(delta);
        final previous = lastMotionStamp;
        if (previous != null) {
          final gap = (stamp - previous).inMicroseconds;
          if (gap > 0) motionGaps.add(gap);
        }
        lastMotionStamp = stamp;
      }
      previousOffset = position.pixels;
    });
    void timings(List<FrameTiming> batch) {
      if (capture) samples.addAll(batch);
    }

    SchedulerBinding.instance.addTimingsCallback(timings);
    for (var round = 0; round < 8; round++) {
      final wheel = round >= 4;
      await windowManager.focus();
      final focused = await windowManager.isFocused();
      samples.clear();
      offsetSteps.clear();
      motionGaps.clear();
      previousOffset = position.pixels;
      capture = true;
      final mountedBefore = _mountedThumbnails();
      final rssBefore = ProcessInfo.currentRss;
      if (wheel) {
        final scrollContext = position.context.storageContext;
        if (!scrollContext.mounted) throw StateError('Grid was detached');
        final box = scrollContext.findRenderObject() as RenderBox;
        final point = box.localToGlobal(box.size.center(Offset.zero));
        for (final direction in [1.0, -1.0]) {
          previousOffset = position.pixels;
          lastMotionStamp = null;
          motionActive = true;
          for (var tick = 0; tick < 80; tick++) {
            GestureBinding.instance.handlePointerEvent(
              PointerScrollEvent(
                kind: ui.PointerDeviceKind.mouse,
                position: point,
                scrollDelta: Offset(0, direction * 160),
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
          motionActive = false;
        }
      } else {
        for (final target in [position.maxScrollExtent, 0.0]) {
          previousOffset = position.pixels;
          lastMotionStamp = null;
          motionActive = true;
          await position.animateTo(
            target,
            duration: const Duration(seconds: 5),
            curve: Curves.linear,
          );
          motionActive = false;
        }
      }
      // FrameTiming batches are delivered after rasterization. Flush the final
      // batch before ending this round; idle time creates almost no extra frames.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      capture = false;
      final currentState = _findGrid(folder)?.$2;
      if (currentState == null ||
          currentState.gridZoomLevel != state.gridZoomLevel ||
          currentState.files.length != state.files.length ||
          currentState.folders.length != state.folders.length ||
          (position.maxScrollExtent - scrollExtent).abs() > .01 ||
          (position.viewportDimension - viewport).abs() > .01) {
        throw StateError('Grid geometry changed during benchmark');
      }
      if (samples.isEmpty) throw StateError('No native FrameTiming samples');
      if (offsetSteps.isEmpty) throw StateError('Grid did not scroll');
      offsetSteps.sort();
      results.add({
        'round': round,
        'input': wheel ? 'wheel' : 'linear',
        'focused': focused,
        'zoom': currentState.gridZoomLevel,
        'scroll_extent': position.maxScrollExtent,
        'phase': round == 0 ? 'initial' : 'warm',
        'frames': samples.length,
        'scroll_updates': offsetSteps.length,
        if (motionGaps.isNotEmpty)
          'motion_update_hz':
              motionGaps.length * 1000000 / motionGaps.reduce((a, b) => a + b),
        if (motionGaps.isNotEmpty)
          'motion_frame_gap': _distribution(motionGaps),
        'scroll_step_p95_px':
            offsetSteps[(.95 * (offsetSteps.length - 1)).round()],
        'build': _distribution([
          for (final frame in samples) frame.buildDuration.inMicroseconds,
        ]),
        'raster': _distribution([
          for (final frame in samples) frame.rasterDuration.inMicroseconds,
        ]),
        'over_16_7_ms': samples
            .where(
              (frame) =>
                  math.max(
                    frame.buildDuration.inMicroseconds,
                    frame.rasterDuration.inMicroseconds,
                  ) >
                  16667,
            )
            .length,
        'mounted_before': mountedBefore,
        'mounted_after': _mountedThumbnails(),
        'rss_before_mb': rssBefore / 1048576,
        'rss_after_mb': ProcessInfo.currentRss / 1048576,
        'decoded_cache_mb':
            PaintingBinding.instance.imageCache.currentSizeBytes / 1048576,
        'live_images': PaintingBinding.instance.imageCache.liveImageCount,
      });
      await output.parent.create(recursive: true);
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'mode': 'profile',
          'renderer': Platform.environment['CB_WINDOWS_RENDERER'] ?? 'default',
          'refresh_hz': WidgetsBinding
              .instance
              .platformDispatcher
              .views
              .first
              .display
              .refreshRate,
          'folder': folder,
          'files': state.files.length,
          'folders': state.folders.length,
          'zoom': state.gridZoomLevel,
          'viewport': position.viewportDimension,
          'scroll_extent': position.maxScrollExtent,
          'rounds': results,
        }),
      );
    }
    SchedulerBinding.instance.removeTimingsCallback(timings);
    exit(0);
  } catch (error, stack) {
    await output.parent.create(recursive: true);
    await output.writeAsString(
      jsonEncode({'error': '$error', 'stack': '$stack'}),
    );
    exit(1);
  }
}
