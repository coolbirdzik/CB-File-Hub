import 'dart:async';

import 'package:cb_file_manager/helpers/media/thumbnail_work_scheduler.dart';
import 'package:cb_file_manager/ui/utils/scroll_velocity_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ThumbnailWorkScheduler scheduler;
  setUp(() {
    ScrollVelocityNotifier.instance.reset();
    scheduler = ThumbnailWorkScheduler();
  });
  tearDown(() {
    scheduler.dispose();
    ScrollVelocityNotifier.instance.reset();
  });

  testWidgets('caps in-flight metadata reads and starts per frame', (
    tester,
  ) async {
    final completed = List.generate(6, (_) => Completer<void>());
    final started = <int>[];
    for (var i = 0; i < completed.length; i++) {
      scheduler.schedule(i, () async {
        started.add(i);
        await completed[i].future;
      });
    }
    await tester.pump();
    expect(started, [0, 1]);
    await tester.pump();
    expect(started, [0, 1]);
    completed[0].complete();
    await tester.pump();
    await tester.pump();
    expect(started, [0, 1, 2]);
    for (final done in completed.skip(1)) {
      done.complete();
    }
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(started, [0, 1, 2, 3, 4, 5]);
  });

  testWidgets('defers all reads until scrolling ends', (tester) async {
    ScrollVelocityNotifier.instance.updateVelocity(10000);
    var reads = 0;
    scheduler.schedule('tile', () async => reads++);
    await tester.pump();
    expect(reads, 0);
    ScrollVelocityNotifier.instance.reset();
    await tester.pump();
    expect(reads, 1);
  });

  testWidgets('a recycled tile cancels its pending read', (tester) async {
    var reads = 0;
    scheduler.schedule('old tile', () async => reads++);
    scheduler.cancel('old tile');
    await tester.pump();
    expect(reads, 0);
  });

  testWidgets('even a slow first tick defers reads and resumes on idle', (
    tester,
  ) async {
    ScrollVelocityNotifier.instance.updateVelocity(.1);
    expect(ScrollVelocityNotifier.instance.isScrollingFast, isFalse);
    var reads = 0;
    scheduler.schedule('tile', () async => reads++);
    await tester.pump(const Duration(milliseconds: 80));
    expect(reads, 0);
    ScrollVelocityNotifier.instance.updateVelocity(.1);
    await tester.pump(const Duration(milliseconds: 80));
    expect(reads, 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(reads, 1);
    expect(ScrollVelocityNotifier.instance.isScrolling, isFalse);
  });

  testWidgets('replaces queued work when a tile changes source', (
    tester,
  ) async {
    final sources = <String>[];
    scheduler.schedule('tile', () async => sources.add('old'));
    scheduler.schedule('tile', () async => sources.add('new'));
    await tester.pump();
    expect(sources, ['new']);
  });
}
