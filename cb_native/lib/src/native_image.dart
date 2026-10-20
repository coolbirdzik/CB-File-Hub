import 'dart:typed_data';

import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_job.dart';

/// How [NativeImage.thumbnail] sizes its output inside the box.
enum NativeThumbnailFit {
  /// Keep the aspect ratio and only ever shrink (the photo thumbnails).
  shrinkOnly,

  /// Keep the aspect ratio and fill the box's long side, upscaling small
  /// images (the network thumbnails).
  fit,

  /// Exactly the box size.
  stretch,
}

/// Resampling, matching the `package:image` interpolation each caller used.
enum NativeResizeFilter { linear, average, cubic }

enum NativeImageFormat { jpeg, png, bmp, gif, tiff }

class NativeThumbnail {
  const NativeThumbnail(this.width, this.height, this.bytes);

  final int width;
  final int height;

  /// The encoded image.
  final Uint8List bytes;
}

/// Image work on Rust threads. Every method returns null when the native
/// library is unavailable or cannot handle the input (an unsupported format,
/// say), so the caller can run its `package:image` code instead.
abstract final class NativeImage {
  /// Decodes [path] or [bytes] (EXIF orientation applied), resizes it into a
  /// [width] x [height] box and encodes it as [format]. [enhance] applies the
  /// network thumbnails' `adjustColor(contrast: 1.05, saturation: 1.1,
  /// brightness: 1.02)` and, at 256 px or less, their sharpen kernel.
  static Future<NativeThumbnail?> thumbnail({
    String? path,
    Uint8List? bytes,
    required int width,
    required int height,
    NativeThumbnailFit fit = NativeThumbnailFit.fit,
    NativeResizeFilter filter = NativeResizeFilter.linear,
    bool enhance = false,
    NativeImageFormat format = NativeImageFormat.png,
    int quality = 85,
    int pngLevel = 1,
  }) async {
    assert((path == null) != (bytes == null));
    if (format != NativeImageFormat.jpeg && format != NativeImageFormat.png) {
      throw ArgumentError.value(format, 'format', 'jpeg or png');
    }
    final config = WireWriter();
    if (path != null) {
      config
        ..u8(0)
        ..str(path);
    } else {
      config
        ..u8(1)
        ..u32(bytes!.length)
        ..raw(bytes);
    }
    config
      ..u32(width)
      ..u32(height)
      ..u8(fit.index)
      ..u8(filter.index)
      ..boolean(enhance)
      ..u8(format.index)
      ..u8(quality.clamp(1, 100))
      ..u8(pngLevel.clamp(0, 2));
    final out = await _run(b.jobThumbnail, config.takeBytes());
    if (out == null || out.length < 8) return null;
    final r = WireReader(out);
    final w = r.u32();
    final h = r.u32();
    return NativeThumbnail(w, h, r.rest());
  }

  /// Encodes straight (non-premultiplied) RGBA pixels.
  static Future<Uint8List?> encode(
    Uint8List rgba,
    int width,
    int height,
    NativeImageFormat format, {
    int quality = 95,
  }) {
    final config = WireWriter()
      ..u32(width)
      ..u32(height)
      ..u8(format.index)
      ..u8(quality.clamp(1, 100))
      ..raw(rgba);
    return _run(b.jobEncodeImage, config.takeBytes());
  }

  /// The editor's object eraser (`inpaintRgba`), byte-for-byte the same
  /// result as the Dart implementation.
  static Future<Uint8List?> inpaint(
    Uint8List rgba,
    Uint8List mask,
    int width,
    int height,
  ) {
    final config = WireWriter()
      ..u32(width)
      ..u32(height)
      ..raw(rgba)
      ..raw(mask);
    return _run(b.jobInpaint, config.takeBytes());
  }

  static Future<Uint8List?> _run(int kind, Uint8List config) async {
    final job = NativeJob.start(kind, config);
    if (job == null) return null;
    try {
      return await job.result();
    } on NativeJobException {
      return null;
    }
  }
}
