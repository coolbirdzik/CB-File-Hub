import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cb_file_manager/ui/screens/media_gallery/image_editor/edit_model.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/image_editor/edit_renderer.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/image_editor/image_editor_screen.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/image_editor/inpaint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Future<ui.Image> _solidImage(int width, int height, Color color) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  return recorder.endRecording().toImage(width, height);
}

void _expectGeometry(EditGeometry actual, EditGeometry expected) {
  expect(actual.quarterTurns, expected.quarterTurns);
  expect(actual.flipped, expected.flipped);
  expect(actual.crop.left, closeTo(expected.crop.left, 1e-9));
  expect(actual.crop.top, closeTo(expected.crop.top, 1e-9));
  expect(actual.crop.right, closeTo(expected.crop.right, 1e-9));
  expect(actual.crop.bottom, closeTo(expected.crop.bottom, 1e-9));
}

Offset _map(Matrix4 matrix, Offset point) =>
    MatrixUtils.transformPoint(matrix, point);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditGeometry', () {
    const source = Size(200, 100);

    test('orient matrix maps the source onto the oriented box', () {
      for (var turns = 0; turns < 4; turns++) {
        for (final flipped in <bool>[false, true]) {
          final geometry = EditGeometry(quarterTurns: turns, flipped: flipped);
          final oriented = geometry.orientedSize(source);
          final matrix = geometry.orientMatrix(source);
          final corners = <Offset>[
            Offset.zero,
            const Offset(200, 0),
            const Offset(0, 100),
            const Offset(200, 100),
          ].map((corner) => _map(matrix, corner));
          for (final corner in corners) {
            expect(corner.dx, inInclusiveRange(-1e-9, oriented.width + 1e-9));
            expect(corner.dy, inInclusiveRange(-1e-9, oriented.height + 1e-9));
          }
        }
      }
    });

    test('a clockwise turn moves the top-left corner to the top-right', () {
      final matrix = const EditGeometry(quarterTurns: 1).orientMatrix(source);
      expect(_map(matrix, Offset.zero), const Offset(100, 0));
    });

    test('the crop follows rotations and flips', () {
      const crop = Rect.fromLTRB(0.1, 0.2, 0.5, 0.6);
      const geometry = EditGeometry(crop: crop);
      _expectGeometry(
        geometry
            .rotatedClockwise()
            .rotatedClockwise()
            .rotatedClockwise()
            .rotatedClockwise(),
        geometry,
      );
      _expectGeometry(
        geometry.rotatedClockwise().rotatedCounterClockwise(),
        geometry,
      );
      _expectGeometry(
        geometry.flippedHorizontally().flippedHorizontally(),
        geometry,
      );
      _expectGeometry(
        geometry.flippedVertically().flippedVertically(),
        geometry,
      );
      _expectGeometry(
        geometry.flippedHorizontally(),
        const EditGeometry(
          flipped: true,
          crop: Rect.fromLTRB(0.5, 0.2, 0.9, 0.6),
        ),
      );
    });

    test('a vertical flip mirrors the picture top to bottom', () {
      final flipped = const EditGeometry().flippedVertically();
      final matrix = flipped.orientMatrix(source);
      expect(_map(matrix, const Offset(10, 0)), const Offset(10, 100));
    });
  });

  group('ColorMatrices', () {
    test('identity is neutral and adjustments start untouched', () {
      expect(
        ColorMatrices.concat(ColorMatrices.identity, ColorMatrices.sepia),
        ColorMatrices.sepia,
      );
      expect(const ImageAdjustments().isIdentity, isTrue);
    });

    test('an unedited state has no colour matrix', () async {
      final image = await _solidImage(4, 4, Colors.red);
      expect(EditState(image: image).colorMatrix, isNull);
      expect(EditState(image: image, filterId: 'mono').colorMatrix, isNotNull);
    });
  });

  test('inpaint fills a hole from its surroundings', () {
    const width = 9, height = 9;
    final rgba = Uint8List(width * height * 4);
    final mask = Uint8List(width * height);
    for (var i = 0; i < width * height; i++) {
      rgba
        ..[i * 4] = 40
        ..[i * 4 + 1] = 120
        ..[i * 4 + 2] = 200
        ..[i * 4 + 3] = 255;
    }
    for (var y = 3; y <= 5; y++) {
      for (var x = 3; x <= 5; x++) {
        final i = y * width + x;
        mask[i] = 1;
        rgba
          ..[i * 4] = 255
          ..[i * 4 + 1] = 0
          ..[i * 4 + 2] = 0;
      }
    }
    final out = inpaintRgba(rgba, mask, width, height);
    final center = (4 * width + 4) * 4;
    expect(out[center], closeTo(40, 2));
    expect(out[center + 1], closeTo(120, 2));
    expect(out[center + 2], closeTo(200, 2));
    expect(rgba[center], 255, reason: 'input is left untouched');
  });

  testWidgets('export applies crop and rotation and encodes', (tester) async {
    await tester.runAsync(() async {
      final image = await _solidImage(200, 100, Colors.blue);
      final state = EditState(
        image: image,
        geometry: const EditGeometry(
          crop: Rect.fromLTRB(0, 0, 0.5, 1),
        ).rotatedClockwise(),
        filterId: 'mono',
      );
      final rendered = await renderEdit(state);
      expect(rendered.width, 100);
      expect(rendered.height, 100);

      final jpg = await encodeImage(rendered, '.jpg');
      final decoded = img.decodeJpg(jpg)!;
      expect(decoded.width, 100);
      final pixel = decoded.getPixel(50, 50);
      // Mono: the channels come out equal.
      expect((pixel.r - pixel.b).abs(), lessThan(6));
      expect(encodedExtension('.webp'), '.png');
    });
  });

  testWidgets('erasing replaces the painted area', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 60, 60),
        Paint()..color = const Color(0xFF00C800),
      );
      canvas.drawCircle(
        const Offset(30, 30),
        4,
        Paint()..color = const Color(0xFFFF0000),
      );
      final image = await recorder.endRecording().toImage(60, 60);

      final erased = await eraseArea(image, const <StrokeAnnotation>[
        StrokeAnnotation(
          points: <Offset>[Offset(30, 30)],
          color: Colors.white,
          width: 14,
        ),
      ]);
      final data = await erased.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      final bytes = data!.buffer.asUint8List();
      final center = (30 * 60 + 30) * 4;
      expect(bytes[center], lessThan(20), reason: 'red dot is gone');
      expect(bytes[center + 1], closeTo(200, 20));
    });
  });

  testWidgets('editor switches tools, draws markup and undoes it', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('cb-image-editor-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final file = File('${root.path}${Platform.pathSeparator}photo.png')
      ..writeAsBytesSync(
        img.encodePng(
          img.Image(width: 160, height: 90)..clear(img.ColorRgb8(30, 90, 160)),
        ),
      );

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var closed = false;
    final key = GlobalKey<ImageEditorScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageEditorScreen(
            key: key,
            file: file,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    for (var i = 0; i < 20 && key.currentState!.state == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(key.currentState!.state, isNotNull);

    // Crop tools rotate the picture.
    await tester.tap(find.byTooltip('Rotate right'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(key.currentState!.state!.geometry.quarterTurns, 1);

    await tester.tap(find.text('Filters'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Warm'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(key.currentState!.state!.filterId, 'warm');

    await tester.tap(find.text('Markup'));
    await tester.pump(const Duration(milliseconds: 400));
    final canvas = tester.getCenter(find.byType(InteractiveViewer));
    final gesture = await tester.startGesture(canvas);
    await gesture.moveBy(const Offset(40, 10));
    await gesture.moveBy(const Offset(40, 10));
    await gesture.up();
    await tester.pump();
    expect(key.currentState!.state!.annotations, hasLength(1));

    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(key.currentState!.state!.annotations, isEmpty);
    await tester.tap(find.byTooltip('Redo (Ctrl+Y)'));
    await tester.pump();
    expect(key.currentState!.state!.annotations, hasLength(1));

    // Unsaved edits ask before closing.
    await tester.tap(find.byTooltip('Close editor (Esc)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
