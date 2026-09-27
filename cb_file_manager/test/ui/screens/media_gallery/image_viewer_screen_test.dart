import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/ui/screens/media_gallery/image_viewer_screen.dart';
import 'package:cb_file_manager/ui/components/video/thumbnail_strip.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/widgets/image_viewer_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('viewer keeps common image actions visible with thumbnails', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('cb-image-viewer-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final first = File('${root.path}${Platform.pathSeparator}first.png');
    final second = File('${root.path}${Platform.pathSeparator}second.png');
    first.writeAsBytesSync(png);
    second.writeAsBytesSync(png);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ImageViewerScreen(file: first, imageFiles: <File>[first, second]),
      ),
    );
    await tester.pump();

    expect(find.byType(ThumbnailStrip), findsOneWidget);
    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byTooltip('Rotate left'), findsOneWidget);
    expect(find.byTooltip('Rotate right'), findsOneWidget);
    expect(find.byTooltip('Edit image'), findsOneWidget);
    expect(find.byTooltip('Print (Ctrl+P)'), findsOneWidget);
    expect(find.byTooltip('Share'), findsWidgets);
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .scaleFactor,
      500,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('viewer pages with keys, runs a slideshow and hides chrome', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('cb-image-viewer-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final files = <File>[
      for (final name in <String>['a.png', 'b.png', 'c.png'])
        File('${root.path}${Platform.pathSeparator}$name')
          ..writeAsBytesSync(png),
    ];

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The loading spinner never stops in tests, so settle by time.
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ImageViewerScreen(file: files.first, imageFiles: files),
      ),
    );
    await settle();

    expect(find.text('1 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await settle();
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Play slideshow'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Pause slideshow'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause slideshow'));
    await settle();

    // Rotating animates and keeps the picture on screen.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await settle();

    // Tapping the picture hides the controls, tapping again brings them back.
    bool toolbarVisible() => tester
        .widget<ViewerChromeReveal>(
          find.ancestor(
            of: find.byTooltip('Zoom in'),
            matching: find.byType(ViewerChromeReveal),
          ),
        )
        .visible;
    expect(toolbarVisible(), isTrue);
    await tester.tapAt(const Offset(700, 450));
    await settle();
    expect(toolbarVisible(), isFalse);
    await tester.tapAt(const Offset(700, 450));
    await settle();
    expect(toolbarVisible(), isTrue);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
