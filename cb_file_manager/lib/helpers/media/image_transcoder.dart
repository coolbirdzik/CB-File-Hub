import 'dart:isolate';
import 'dart:typed_data';

import 'package:cb_native/cb_native.dart';
import 'package:image/image.dart' as img;

/// Shared full-resolution JPEG conversion. Both native and Dart fallback work
/// off the UI isolate; null preserves the caller's existing undecodable case.
Future<Uint8List?> transcodeJpeg(
  Uint8List bytes, {
  int quality = 95,
  bool useNative = true,
}) async {
  if (useNative) {
    final native = await NativeImage.transcode(bytes, quality: quality);
    if (native != null) return native;
  }
  return Isolate.run(() {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    } catch (_) {
      // Some decoders throw on a truncated header instead of returning null.
      return null;
    }
  });
}
