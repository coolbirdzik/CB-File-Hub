import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import 'edit_model.dart';
import 'inpaint.dart';

/// Where an edit sits inside a widget: the whole picture is scaled to fit
/// [size] and centred.
class EditorViewport {
  /// Source pixels → widget pixels.
  final Matrix4 sourceToView;

  /// The crop area, in widget pixels.
  final Rect frame;

  /// The whole oriented picture, in widget pixels.
  final Rect imageRect;

  /// Widget pixels per source pixel.
  final double scale;

  const EditorViewport._(
    this.sourceToView,
    this.frame,
    this.imageRect,
    this.scale,
  );

  /// Fits the cropped picture, or with [showWholeImage] the whole picture,
  /// inside [size] less [padding].
  factory EditorViewport.fit(
    Size size,
    EditState state, {
    bool showWholeImage = false,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    final source = state.sourceSize;
    final geometry = state.geometry;
    final oriented = Offset.zero & geometry.orientedSize(source);
    final crop = geometry.cropRect(source);
    final area = showWholeImage ? oriented : crop;
    final available = padding.deflateRect(Offset.zero & size);
    final scale = area.isEmpty
        ? 1.0
        : max(
            0.0001,
            min(available.width / area.width, available.height / area.height),
          );
    final origin = Offset(
      available.center.dx - area.width * scale / 2,
      available.center.dy - area.height * scale / 2,
    );
    Rect toView(Rect rect) => Rect.fromLTWH(
      origin.dx + (rect.left - area.left) * scale,
      origin.dy + (rect.top - area.top) * scale,
      rect.width * scale,
      rect.height * scale,
    );
    final matrix = Matrix4.identity()
      ..translateByVector3(Vector3(origin.dx, origin.dy, 0))
      ..scaleByVector3(Vector3(scale, scale, 1))
      ..translateByVector3(Vector3(-area.left, -area.top, 0))
      ..multiply(geometry.orientMatrix(source));
    return EditorViewport._(matrix, toView(crop), toView(oriented), scale);
  }

  Offset toSource(Offset viewPoint) {
    final inverse = Matrix4.tryInvert(sourceToView);
    if (inverse == null) return viewPoint;
    return MatrixUtils.transformPoint(inverse, viewPoint);
  }
}

/// Paints [state]: the picture with its colour, then the vignette over
/// [frame], then the markup. Everything is clipped to [clip].
void paintEdit(
  Canvas canvas,
  EditState state, {
  required Matrix4 sourceToView,
  required Rect frame,
  required Rect clip,
  FilterQuality quality = FilterQuality.medium,
  Annotation? pending,
  List<StrokeAnnotation> eraseMask = const <StrokeAnnotation>[],
}) {
  final sourceRect = Offset.zero & state.sourceSize;
  canvas.save();
  canvas.clipRect(clip);

  canvas.save();
  canvas.transform(sourceToView.storage);
  final matrix = state.colorMatrix;
  canvas.drawImage(
    state.image,
    Offset.zero,
    Paint()
      ..filterQuality = quality
      ..colorFilter = matrix == null ? null : ColorFilter.matrix(matrix),
  );
  canvas.restore();

  final vignette = state.adjustments.vignette;
  if (vignette > 0) _paintVignette(canvas, frame, vignette);

  if (state.annotations.isNotEmpty || pending != null) {
    canvas.save();
    canvas.transform(sourceToView.storage);
    // Own layer, so the markup eraser clears markup and not the picture.
    canvas.saveLayer(sourceRect, Paint());
    for (final annotation in state.annotations) {
      paintAnnotation(canvas, annotation);
    }
    if (pending != null) paintAnnotation(canvas, pending);
    canvas.restore();
    canvas.restore();
  }

  if (eraseMask.isNotEmpty) {
    canvas.save();
    canvas.transform(sourceToView.storage);
    // One translucent layer, so overlapping brush strokes do not darken.
    canvas.saveLayer(sourceRect, Paint()..color = const Color(0x8C000000));
    for (final stroke in eraseMask) {
      paintAnnotation(canvas, stroke);
    }
    canvas.restore();
    canvas.restore();
  }

  canvas.restore();
}

void _paintVignette(Canvas canvas, Rect frame, double strength) {
  canvas.save();
  canvas.translate(frame.center.dx, frame.center.dy);
  canvas.scale(frame.width / 2, frame.height / 2);
  canvas.drawRect(
    const Rect.fromLTRB(-1, -1, 1, 1),
    Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        1.45,
        <Color>[
          const Color(0x00000000),
          const Color(0x00000000),
          Color.fromRGBO(0, 0, 0, 0.9 * strength),
        ],
        const <double>[0, 0.45, 1],
      ),
  );
  canvas.restore();
}

void paintAnnotation(Canvas canvas, Annotation annotation) {
  switch (annotation) {
    case StrokeAnnotation():
      _paintStroke(canvas, annotation);
    case ShapeAnnotation():
      _paintShape(canvas, annotation);
    case TextAnnotation():
      _paintText(canvas, annotation);
  }
}

void _paintStroke(Canvas canvas, StrokeAnnotation stroke) {
  final points = stroke.points;
  if (points.isEmpty) return;
  final paint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  switch (stroke.kind) {
    case StrokeKind.pen:
      paint.color = stroke.color;
    case StrokeKind.highlighter:
      paint
        ..color = stroke.color.withValues(alpha: 0.4)
        ..strokeCap = StrokeCap.square;
    case StrokeKind.eraser:
      paint
        ..color = const Color(0xFFFFFFFF)
        ..blendMode = BlendMode.clear;
  }

  if (points.length == 1) {
    canvas.drawCircle(
      points.first,
      stroke.width / 2,
      Paint()
        ..color = paint.color
        ..blendMode = paint.blendMode,
    );
    return;
  }
  // Curves through the midpoints keep freehand lines smooth.
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length; i++) {
    final previous = points[i - 1];
    final mid = Offset.lerp(previous, points[i], 0.5)!;
    path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  canvas.drawPath(path, paint);
}

void _paintShape(Canvas canvas, ShapeAnnotation shape) {
  final paint = Paint()
    ..isAntiAlias = true
    ..color = shape.color
    ..style = PaintingStyle.stroke
    ..strokeWidth = shape.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  switch (shape.kind) {
    case ShapeKind.line:
      canvas.drawLine(shape.start, shape.end, paint);
    case ShapeKind.arrow:
      final direction = shape.end - shape.start;
      final length = direction.distance;
      if (length < 0.5) return;
      final unit = direction / length;
      final headLength = min(length, shape.width * 4 + 8);
      final base = shape.end - unit * headLength;
      final normal = Offset(-unit.dy, unit.dx) * (headLength * 0.55);
      canvas.drawLine(shape.start, base + unit * (shape.width / 2), paint);
      canvas.drawPath(
        Path()
          ..moveTo(shape.end.dx, shape.end.dy)
          ..lineTo((base + normal).dx, (base + normal).dy)
          ..lineTo((base - normal).dx, (base - normal).dy)
          ..close(),
        Paint()
          ..isAntiAlias = true
          ..color = shape.color
          ..style = PaintingStyle.fill,
      );
    case ShapeKind.rectangle:
      canvas.drawRect(Rect.fromPoints(shape.start, shape.end), paint);
    case ShapeKind.ellipse:
      canvas.drawOval(Rect.fromPoints(shape.start, shape.end), paint);
  }
}

TextPainter _layoutText(TextAnnotation text) => TextPainter(
  text: TextSpan(
    text: text.text,
    style: TextStyle(
      color: text.color,
      fontSize: text.fontSize,
      fontWeight: FontWeight.w700,
      height: 1.15,
      shadows: <Shadow>[
        Shadow(
          color: const Color(0x66000000),
          blurRadius: text.fontSize * 0.08,
          offset: Offset(0, text.fontSize * 0.03),
        ),
      ],
    ),
  ),
  textAlign: TextAlign.center,
  textDirection: TextDirection.ltr,
)..layout();

void _paintText(Canvas canvas, TextAnnotation text) {
  final painter = _layoutText(text);
  canvas.save();
  canvas.translate(text.anchor.dx, text.anchor.dy);
  // Undo the picture's orientation at placing time, so it reads upright.
  if (text.flipped) canvas.scale(-1, 1);
  canvas.rotate(-text.quarterTurns * pi / 2);
  painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  canvas.restore();
  painter.dispose();
}

/// Renders the finished edit at full resolution.
Future<ui.Image> renderEdit(EditState state) {
  final source = state.sourceSize;
  final crop = state.geometry.cropRect(source);
  final left = crop.left.round();
  final top = crop.top.round();
  final width = max(1, crop.right.round() - left);
  final height = max(1, crop.bottom.round() - top);
  final output = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, output);
  final matrix = Matrix4.identity()
    ..translateByVector3(Vector3(-left.toDouble(), -top.toDouble(), 0))
    ..multiply(state.geometry.orientMatrix(source));
  paintEdit(
    canvas,
    state,
    sourceToView: matrix,
    frame: output,
    clip: output,
    quality: FilterQuality.high,
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

/// Encodes [image] in the format of [extension] (with the dot).
///
/// PNG is encoded by the engine; the rest by `package:image` in an isolate.
/// Formats it cannot write come out as PNG, so check [encodedExtension].
Future<Uint8List> encodeImage(ui.Image image, String extension) async {
  final ext = encodedExtension(extension);
  if (ext == '.png') {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final rgba = data!.buffer.asUint8List();
  return _encodeInIsolate(rgba, image.width, image.height, ext);
}

// Kept apart from the callers so the isolate closure captures only bytes
// and numbers, never a ui.Image.
Future<Uint8List> _encodeInIsolate(
  Uint8List rgba,
  int width,
  int height,
  String ext,
) {
  return Isolate.run(() {
    final decoded = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return switch (ext) {
      '.jpg' || '.jpeg' => img.encodeJpg(decoded, quality: 95),
      '.bmp' => img.encodeBmp(decoded),
      '.gif' => img.encodeGif(decoded),
      '.tif' || '.tiff' => img.encodeTiff(decoded),
      _ => img.encodePng(decoded),
    };
  });
}

Future<Uint8List> _inpaintInIsolate(
  Uint8List pixels,
  Uint8List mask,
  int width,
  int height,
) => Isolate.run(() => inpaintRgba(pixels, mask, width, height));

String encodedExtension(String extension) {
  final ext = extension.toLowerCase();
  const writable = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.bmp',
    '.gif',
    '.tif',
    '.tiff',
  };
  return writable.contains(ext) ? ext : '.png';
}

/// Removes what [strokes] cover from [image], filling it in from the
/// surroundings. Only the area around the strokes is read back and processed.
Future<ui.Image> eraseArea(
  ui.Image image,
  List<StrokeAnnotation> strokes,
) async {
  if (strokes.isEmpty) return image;
  final imageRect = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  var bounds = strokes.first.bounds;
  var widest = 0.0;
  for (final stroke in strokes) {
    bounds = bounds.expandToInclude(stroke.bounds);
    widest = max(widest, stroke.width);
  }
  // Keep a ring of real pixels around the hole to fill it from.
  final region = bounds.inflate(max(12.0, widest)).intersect(imageRect);
  if (region.isEmpty) return image;
  final left = region.left.floor();
  final top = region.top.floor();
  final width = region.right.ceil() - left;
  final height = region.bottom.ceil() - top;
  final area = Rect.fromLTWH(
    left.toDouble(),
    top.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );
  final target = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  final pixels = await _readPixels(
    width,
    height,
    (canvas) => canvas.drawImageRect(image, area, target, Paint()),
  );
  final maskPixels = await _readPixels(width, height, (canvas) {
    canvas.translate(-area.left, -area.top);
    for (final stroke in strokes) {
      paintAnnotation(
        canvas,
        StrokeAnnotation(
          points: stroke.points,
          color: const Color(0xFFFFFFFF),
          width: stroke.width,
        ),
      );
    }
  });
  final mask = Uint8List(width * height);
  for (var i = 0; i < mask.length; i++) {
    mask[i] = maskPixels[i * 4 + 3] > 24 ? 1 : 0;
  }

  final filled = await _inpaintInIsolate(pixels, mask, width, height);
  final patch = await _imageFromPixels(filled, width, height);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, imageRect);
  canvas.drawImage(image, Offset.zero, Paint());
  canvas.drawImage(patch, area.topLeft, Paint());
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(image.width, image.height);
  } finally {
    picture.dispose();
    patch.dispose();
  }
}

Future<Uint8List> _readPixels(
  int width,
  int height,
  void Function(Canvas canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  draw(
    Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble())),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _imageFromPixels(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// A small copy of [image] for filter previews.
Future<ui.Image> createPreview(ui.Image image, {double maxSide = 180}) {
  final scale = min(1.0, maxSide / max(image.width, image.height));
  final width = max(1, (image.width * scale).round());
  final height = max(1, (image.height * scale).round());
  final target = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final recorder = ui.PictureRecorder();
  Canvas(recorder, target).drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    target,
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}
