import 'dart:async';

import 'package:cb_file_manager/ui/utils/app_busy_cursor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(AppBusyCursor.resetForTest);

  MouseRegion? busyRegion(WidgetTester tester) {
    final regions = tester
        .widgetList<MouseRegion>(find.byType(MouseRegion))
        .where((r) => r.cursor == SystemMouseCursors.progress);
    return regions.isEmpty ? null : regions.first;
  }

  Future<void> pumpOverlay(WidgetTester tester) {
    return tester.pumpWidget(
      const MaterialApp(home: AppBusyCursorOverlay(child: SizedBox.expand())),
    );
  }

  testWidgets('no busy cursor while idle', (tester) async {
    await pumpOverlay(tester);
    expect(busyRegion(tester), isNull);
  });

  testWidgets('pulse shows the busy cursor, then releases it', (tester) async {
    await pumpOverlay(tester);

    AppBusyCursor.pulse(const Duration(milliseconds: 300));
    await tester.pump();
    final region = busyRegion(tester);
    expect(region, isNotNull);
    // Non-opaque so hover and taps still reach the widgets underneath.
    expect(region!.opaque, isFalse);

    await tester.pump(const Duration(milliseconds: 400));
    expect(busyRegion(tester), isNull);
  });

  testWidgets('scope keeps the cursor until the work completes', (
    tester,
  ) async {
    await pumpOverlay(tester);

    final completer = Completer<void>();
    final done = AppBusyCursor.run(() => completer.future);

    await tester.pump();
    expect(busyRegion(tester), isNotNull);

    // Well past the minimum hold: the open itself is still running.
    await tester.pump(AppBusyCursor.minimumHold + const Duration(seconds: 1));
    expect(busyRegion(tester), isNotNull);

    completer.complete();
    await done;
    await tester.pump();
    expect(busyRegion(tester), isNull);
  });

  testWidgets('nested scopes only release on the last end', (tester) async {
    await pumpOverlay(tester);

    AppBusyCursor.begin();
    AppBusyCursor.begin();
    await tester.pump();
    expect(busyRegion(tester), isNotNull);

    AppBusyCursor.end();
    await tester.pump();
    expect(busyRegion(tester), isNotNull);

    AppBusyCursor.end();
    await tester.pump();
    expect(busyRegion(tester), isNull);
  });

  testWidgets(
    'busy cursor overrides the item cursor under a stationary pointer',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppBusyCursorOverlay(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: SizedBox.expand(key: ValueKey('row')),
            ),
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(
        location: tester.getCenter(find.byKey(const ValueKey('row'))),
      );
      addTearDown(() => gesture.removePointer());
      await tester.pump();

      MouseCursor? activeCursor() =>
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

      expect(activeCursor(), SystemMouseCursors.click);

      // No pointer movement: the cursor must still flip on the next frame.
      AppBusyCursor.pulse(const Duration(milliseconds: 300));
      await tester.pump();
      expect(activeCursor(), SystemMouseCursors.progress);

      await tester.pump(const Duration(milliseconds: 400));
      expect(activeCursor(), SystemMouseCursors.click);
    },
  );

  testWidgets('toggling the busy cursor never remounts the app subtree', (
    tester,
  ) async {
    _MountProbeState.mounts = 0;
    await tester.pumpWidget(
      const MaterialApp(home: AppBusyCursorOverlay(child: _MountProbe())),
    );
    expect(_MountProbeState.mounts, 1);

    AppBusyCursor.pulse(const Duration(milliseconds: 300));
    await tester.pump();
    expect(busyRegion(tester), isNotNull);
    expect(_MountProbeState.mounts, 1);

    await tester.pump(const Duration(milliseconds: 400));
    expect(busyRegion(tester), isNull);
    expect(_MountProbeState.mounts, 1);
  });

  testWidgets('overlay contributes no semantics nodes in either state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    int countNodes() {
      final root = tester
          .binding
          .renderViews
          .first
          .owner
          ?.semanticsOwner
          ?.rootSemanticsNode;
      if (root == null) return 0;
      var total = 0;
      void walk(SemanticsNode node) {
        total++;
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }

      walk(root);
      return total;
    }

    await tester.pumpWidget(
      const MaterialApp(home: Center(child: Text('item'))),
    );
    final int baseline = countNodes();
    expect(baseline, greaterThan(0));

    await tester.pumpWidget(
      const MaterialApp(
        home: AppBusyCursorOverlay(child: Center(child: Text('item'))),
      ),
    );
    expect(countNodes(), baseline);

    // The engine's AXTree flood comes from nodes appearing/disappearing between
    // updates, so the busy state must not add or drop any either.
    AppBusyCursor.pulse(const Duration(milliseconds: 300));
    await tester.pump();
    expect(busyRegion(tester), isNotNull);
    expect(countNodes(), baseline);

    await tester.pump(const Duration(milliseconds: 400));
    expect(countNodes(), baseline);

    handle.dispose();
  });
}

/// Counts how often it is mounted, so a reparented overlay is caught.
class _MountProbe extends StatefulWidget {
  const _MountProbe();

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  static int mounts = 0;

  @override
  void initState() {
    super.initState();
    mounts++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
