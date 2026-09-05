import 'dart:ui';

import 'package:cb_file_manager/ui/components/video/video_player/video_player_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('desktop title drag area fills the complete video toolbar', (
    tester,
  ) async {
    var dragCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'startDragging') {
            dragCalls++;
          }
          if (call.method == 'isMaximized' || call.method == 'isFullScreen') {
            return false;
          }
          return true;
        });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: VideoPlayerAppBar(
            title: 'sample.mp4',
            showWindowControls: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final dragArea = find.byType(DragToMoveArea);
    expect(dragArea, findsOneWidget);
    expect(tester.getSize(dragArea).height, kToolbarHeight);

    final bounds = tester.getRect(dragArea);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(Offset(bounds.center.dx, bounds.top + 2));
    await gesture.moveBy(const Offset(48, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(dragCalls, 1);
  });
}
