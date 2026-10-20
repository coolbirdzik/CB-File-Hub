import 'dart:async';

import 'package:cb_file_manager/ui/tab_manager/desktop/tab_drag_overlay_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _moveOverlay(BuildContext context, String title) =>
    Positioned(top: 0, left: 0, child: Text(title));

void main() {
  late TabDragOverlayController controller;
  late GlobalKey<NavigatorState> navigator;

  setUp(() {
    controller = TabDragOverlayController();
    navigator = GlobalKey<NavigatorState>();
  });

  tearDown(() => controller.dispose());

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(navigatorKey: navigator, home: const SizedBox()),
  );

  testWidgets('ending a drag cancels pending window discovery', (tester) async {
    await mount(tester);
    final discovery = Completer<String>();
    final showing = controller.show(
      overlay: navigator.currentState!.overlay!,
      load: () => discovery.future,
      builder: _moveOverlay,
    );
    controller.remove();
    discovery.complete('Move tab to window');
    await showing;
    await tester.pump();
    expect(find.text('Move tab to window'), findsNothing);
  });

  testWidgets('an older drag cannot overwrite the current drag', (
    tester,
  ) async {
    await mount(tester);
    final discovery = Completer<String>();
    final oldDrag = controller.show(
      overlay: navigator.currentState!.overlay!,
      load: () => discovery.future,
      builder: _moveOverlay,
    );
    await controller.show(
      overlay: navigator.currentState!.overlay!,
      load: () async => 'Current drag',
      builder: _moveOverlay,
    );
    discovery.complete('Move tab to window');
    await oldDrag;
    await tester.pump();
    expect(find.text('Move tab to window'), findsNothing);
    expect(find.text('Current drag'), findsOneWidget);
    controller.remove();
    await tester.pump();
    expect(find.text('Current drag'), findsNothing);
  });

  testWidgets('a live drag shows its targets and removes them at the end', (
    tester,
  ) async {
    await mount(tester);
    await controller.show(
      overlay: navigator.currentState!.overlay!,
      load: () async => 'Move tab to window',
      builder: _moveOverlay,
    );
    await tester.pump();
    expect(find.text('Move tab to window'), findsOneWidget);
    controller.remove();
    await tester.pump();
    expect(find.text('Move tab to window'), findsNothing);
  });

  testWidgets('disposing the tab screen cancels pending discovery', (
    tester,
  ) async {
    await mount(tester);
    final discovery = Completer<String>();
    final showing = controller.show(
      overlay: navigator.currentState!.overlay!,
      load: () => discovery.future,
      builder: _moveOverlay,
    );
    controller.dispose();
    discovery.complete('Move tab to window');
    await showing;
    await tester.pump();
    expect(find.text('Move tab to window'), findsNothing);
  });
}
