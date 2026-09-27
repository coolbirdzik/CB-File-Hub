import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Orientation and crop of the picture.
///
/// Three coordinate spaces are involved:
/// * source: pixels of the base image;
/// * oriented: the source after [flipped] (mirror) then [quarterTurns]
///   clockwise turns;
/// * output: the [crop] of the oriented image, which is what gets saved.
///
/// Markup is stored in source coordinates, so it follows every later
/// rotation, flip and crop exactly like the pixels under it.
@immutable
class EditGeometry {
  final int quarterTurns;
  final bool flipped;

  /// Crop rectangle in normalized (0..1) oriented coordinates.
  final Rect crop;

  static const Rect fullCrop = Rect.fromLTRB(0, 0, 1, 1);

  const EditGeometry({
    this.quarterTurns = 0,
    this.flipped = false,
    this.crop = fullCrop,
  });

  bool get isIdentity => quarterTurns % 4 == 0 && !flipped && crop == fullCrop;

  Size orientedSize(Size source) =>
      quarterTurns.isOdd ? Size(source.height, source.width) : source;

  /// Crop rectangle in oriented pixels.
  Rect cropRect(Size source) {
    final oriented = orientedSize(source);
    return Rect.fromLTRB(
      crop.left * oriented.width,
      crop.top * oriented.height,
      crop.right * oriented.width,
      crop.bottom * oriented.height,
    );
  }

  /// Maps source pixels to oriented pixels.
  Matrix4 orientMatrix(Size source) {
    final w = source.width;
    final h = source.height;
    final rotate = switch (quarterTurns % 4) {
      1 => _affine(0, 1, -1, 0, h, 0),
      2 => _affine(-1, 0, 0, -1, w, h),
      3 => _affine(0, -1, 1, 0, 0, w),
      _ => Matrix4.identity(),
    };
    if (flipped) rotate.multiply(_affine(-1, 0, 0, 1, w, 0));
    return rotate;
  }

  // x' = a·x + c·y + tx, y' = b·x + d·y + ty
  static Matrix4 _affine(
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty,
  ) => Matrix4(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);

  EditGeometry rotatedClockwise() => EditGeometry(
    quarterTurns: (quarterTurns + 1) % 4,
    flipped: flipped,
    crop: Rect.fromLTRB(1 - crop.bottom, crop.left, 1 - crop.top, crop.right),
  );

  EditGeometry rotatedCounterClockwise() => EditGeometry(
    quarterTurns: (quarterTurns + 3) % 4,
    flipped: flipped,
    crop: Rect.fromLTRB(crop.top, 1 - crop.right, crop.bottom, 1 - crop.left),
  );

  /// Mirrors the picture left to right as it appears on screen.
  EditGeometry flippedHorizontally() => EditGeometry(
    quarterTurns: (4 - quarterTurns % 4) % 4,
    flipped: !flipped,
    crop: Rect.fromLTRB(1 - crop.right, crop.top, 1 - crop.left, crop.bottom),
  );

  /// Mirrors the picture top to bottom as it appears on screen.
  EditGeometry flippedVertically() => EditGeometry(
    quarterTurns: (6 - quarterTurns % 4) % 4,
    flipped: !flipped,
    crop: Rect.fromLTRB(crop.left, 1 - crop.bottom, crop.right, 1 - crop.top),
  );

  EditGeometry withCrop(Rect crop) =>
      EditGeometry(quarterTurns: quarterTurns, flipped: flipped, crop: crop);

  @override
  bool operator ==(Object other) =>
      other is EditGeometry &&
      other.quarterTurns == quarterTurns &&
      other.flipped == flipped &&
      other.crop == crop;

  @override
  int get hashCode => Object.hash(quarterTurns, flipped, crop);
}

/// Tonal adjustments, each in -1..1 (vignette 0..1), 0 meaning untouched.
@immutable
class ImageAdjustments {
  final double exposure;
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;
  final double tint;
  final double vignette;

  const ImageAdjustments({
    this.exposure = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
    this.tint = 0,
    this.vignette = 0,
  });

  bool get isIdentity =>
      exposure == 0 &&
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      warmth == 0 &&
      tint == 0 &&
      vignette == 0;

  ImageAdjustments copyWith({
    double? exposure,
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    double? tint,
    double? vignette,
  }) => ImageAdjustments(
    exposure: exposure ?? this.exposure,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    warmth: warmth ?? this.warmth,
    tint: tint ?? this.tint,
    vignette: vignette ?? this.vignette,
  );

  /// Colour matrix for everything except the vignette, which is painted.
  List<double> get matrix {
    var m = ColorMatrices.identity;
    if (exposure != 0) {
      m = ColorMatrices.concat(
        ColorMatrices.scale(pow(2, exposure).toDouble()),
        m,
      );
    }
    if (brightness != 0) {
      m = ColorMatrices.concat(ColorMatrices.offset(brightness * 90), m);
    }
    if (contrast != 0) {
      m = ColorMatrices.concat(ColorMatrices.contrast(1 + contrast * 0.8), m);
    }
    if (saturation != 0) {
      m = ColorMatrices.concat(ColorMatrices.saturation(1 + saturation), m);
    }
    if (warmth != 0 || tint != 0) {
      m = ColorMatrices.concat(ColorMatrices.temperature(warmth, tint), m);
    }
    return m;
  }

  @override
  bool operator ==(Object other) =>
      other is ImageAdjustments &&
      other.exposure == exposure &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.warmth == warmth &&
      other.tint == tint &&
      other.vignette == vignette;

  @override
  int get hashCode => Object.hash(
    exposure,
    brightness,
    contrast,
    saturation,
    warmth,
    tint,
    vignette,
  );
}

/// 4×5 colour matrices, as taken by [ColorFilter.matrix].
class ColorMatrices {
  const ColorMatrices._();

  static const List<double> identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static const double _lr = 0.2126;
  static const double _lg = 0.7152;
  static const double _lb = 0.0722;

  /// The matrix applying [inner] first, then [outer].
  static List<double> concat(List<double> outer, List<double> inner) {
    final result = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var value = col == 4 ? outer[row * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          value += outer[row * 5 + k] * inner[k * 5 + col];
        }
        result[row * 5 + col] = value;
      }
    }
    return result;
  }

  static List<double> lerp(List<double> a, List<double> b, double t) => [
    for (var i = 0; i < 20; i++) a[i] + (b[i] - a[i]) * t,
  ];

  static List<double> scale(double s) => <double>[
    s, 0, 0, 0, 0, //
    0, s, 0, 0, 0, //
    0, 0, s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static List<double> offset(double o) => <double>[
    1, 0, 0, 0, o, //
    0, 1, 0, 0, o, //
    0, 0, 1, 0, o, //
    0, 0, 0, 1, 0, //
  ];

  /// Contrast around mid grey.
  static List<double> contrast(double c) {
    final t = 127.5 * (1 - c);
    return <double>[
      c, 0, 0, 0, t, //
      0, c, 0, 0, t, //
      0, 0, c, 0, t, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> saturation(double s) {
    final r = (1 - s) * _lr;
    final g = (1 - s) * _lg;
    final b = (1 - s) * _lb;
    return <double>[
      r + s, g, b, 0, 0, //
      r, g + s, b, 0, 0, //
      r, g, b + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Warm/cool (blue ↔ amber) and tint (green ↔ magenta) shifts.
  static List<double> temperature(double warmth, double tint) => <double>[
    1 + warmth * 0.12, 0, 0, 0, warmth * 12, //
    0, 1 - tint * 0.1 + warmth * 0.02, 0, 0, 0, //
    0, 0, 1 - warmth * 0.14, 0, -warmth * 12, //
    0, 0, 0, 1, 0, //
  ];

  static const List<double> sepia = <double>[
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// A one-tap look, blended in by the filter strength.
@immutable
class ImageFilterPreset {
  final String id;
  final String name;
  final List<double> matrix;

  const ImageFilterPreset(this.id, this.name, this.matrix);

  static final List<ImageFilterPreset> all = <ImageFilterPreset>[
    const ImageFilterPreset('none', 'Original', ColorMatrices.identity),
    ImageFilterPreset(
      'vivid',
      'Vivid',
      ColorMatrices.concat(
        ColorMatrices.contrast(1.12),
        ColorMatrices.saturation(1.45),
      ),
    ),
    ImageFilterPreset(
      'warm',
      'Warm',
      ColorMatrices.concat(
        ColorMatrices.saturation(1.1),
        ColorMatrices.temperature(0.8, -0.1),
      ),
    ),
    ImageFilterPreset(
      'cool',
      'Cool',
      ColorMatrices.concat(
        ColorMatrices.contrast(1.05),
        ColorMatrices.temperature(-0.8, 0.1),
      ),
    ),
    ImageFilterPreset(
      'fade',
      'Fade',
      ColorMatrices.concat(
        ColorMatrices.offset(18),
        ColorMatrices.concat(
          ColorMatrices.contrast(0.78),
          ColorMatrices.saturation(0.75),
        ),
      ),
    ),
    ImageFilterPreset(
      'dramatic',
      'Dramatic',
      ColorMatrices.concat(
        ColorMatrices.contrast(1.4),
        ColorMatrices.concat(
          ColorMatrices.saturation(0.85),
          ColorMatrices.offset(-8),
        ),
      ),
    ),
    ImageFilterPreset('mono', 'Mono', ColorMatrices.saturation(0)),
    ImageFilterPreset(
      'noir',
      'Noir',
      ColorMatrices.concat(
        ColorMatrices.contrast(1.45),
        ColorMatrices.saturation(0),
      ),
    ),
    const ImageFilterPreset('sepia', 'Sepia', ColorMatrices.sepia),
    ImageFilterPreset(
      'vintage',
      'Vintage',
      ColorMatrices.concat(
        ColorMatrices.offset(12),
        ColorMatrices.concat(
          ColorMatrices.contrast(0.85),
          ColorMatrices.lerp(ColorMatrices.identity, ColorMatrices.sepia, 0.55),
        ),
      ),
    ),
    ImageFilterPreset(
      'film',
      'Film',
      ColorMatrices.concat(
        ColorMatrices.temperature(0.25, 0.2),
        ColorMatrices.concat(
          ColorMatrices.contrast(1.1),
          ColorMatrices.saturation(0.8),
        ),
      ),
    ),
  ];

  static ImageFilterPreset byId(String id) =>
      all.firstWhere((preset) => preset.id == id, orElse: () => all.first);
}

enum StrokeKind { pen, highlighter, eraser }

enum ShapeKind { line, arrow, rectangle, ellipse }

/// Something drawn on top of the picture, in source pixel coordinates.
@immutable
sealed class Annotation {
  const Annotation();
}

@immutable
class StrokeAnnotation extends Annotation {
  final List<Offset> points;
  final Color color;
  final double width;
  final StrokeKind kind;

  const StrokeAnnotation({
    required this.points,
    required this.color,
    required this.width,
    this.kind = StrokeKind.pen,
  });

  StrokeAnnotation withPoint(Offset point) => StrokeAnnotation(
    points: <Offset>[...points, point],
    color: color,
    width: width,
    kind: kind,
  );

  Rect get bounds {
    var rect = Rect.fromLTRB(
      points.first.dx,
      points.first.dy,
      points.first.dx,
      points.first.dy,
    );
    for (final point in points) {
      rect = rect.expandToInclude(Rect.fromLTWH(point.dx, point.dy, 0, 0));
    }
    return rect.inflate(width / 2 + 1);
  }
}

@immutable
class ShapeAnnotation extends Annotation {
  final ShapeKind kind;
  final Offset start;
  final Offset end;
  final Color color;
  final double width;

  const ShapeAnnotation({
    required this.kind,
    required this.start,
    required this.end,
    required this.color,
    required this.width,
  });

  ShapeAnnotation withEnd(Offset end) => ShapeAnnotation(
    kind: kind,
    start: start,
    end: end,
    color: color,
    width: width,
  );
}

@immutable
class TextAnnotation extends Annotation {
  final Offset anchor;
  final String text;
  final Color color;
  final double fontSize;

  /// Orientation when the text was placed, so it reads upright on screen.
  final int quarterTurns;
  final bool flipped;

  const TextAnnotation({
    required this.anchor,
    required this.text,
    required this.color,
    required this.fontSize,
    required this.quarterTurns,
    required this.flipped,
  });
}

/// Everything about one edit, kept immutable so undo is a list of states.
@immutable
class EditState {
  /// The pixels being edited. Erasing replaces it; nothing else does.
  final ui.Image image;
  final EditGeometry geometry;
  final ImageAdjustments adjustments;
  final String filterId;
  final double filterStrength;
  final List<Annotation> annotations;

  const EditState({
    required this.image,
    this.geometry = const EditGeometry(),
    this.adjustments = const ImageAdjustments(),
    this.filterId = 'none',
    this.filterStrength = 1,
    this.annotations = const <Annotation>[],
  });

  Size get sourceSize => Size(image.width.toDouble(), image.height.toDouble());

  /// Filter then adjustments, as one colour matrix; null when untouched.
  List<double>? get colorMatrix {
    final preset = ImageFilterPreset.byId(filterId);
    var matrix = preset.id == 'none'
        ? ColorMatrices.identity
        : ColorMatrices.lerp(
            ColorMatrices.identity,
            preset.matrix,
            filterStrength,
          );
    matrix = ColorMatrices.concat(adjustments.matrix, matrix);
    for (var i = 0; i < 20; i++) {
      if ((matrix[i] - ColorMatrices.identity[i]).abs() > 1e-6) return matrix;
    }
    return null;
  }

  EditState copyWith({
    ui.Image? image,
    EditGeometry? geometry,
    ImageAdjustments? adjustments,
    String? filterId,
    double? filterStrength,
    List<Annotation>? annotations,
  }) => EditState(
    image: image ?? this.image,
    geometry: geometry ?? this.geometry,
    adjustments: adjustments ?? this.adjustments,
    filterId: filterId ?? this.filterId,
    filterStrength: filterStrength ?? this.filterStrength,
    annotations: annotations ?? this.annotations,
  );
}
