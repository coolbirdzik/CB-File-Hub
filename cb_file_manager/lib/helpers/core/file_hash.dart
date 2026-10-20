import 'dart:io';

import 'package:cb_native/cb_native.dart';
import 'package:crypto/crypto.dart';

/// SHA-256 of the file at [path].
///
/// Hashed on a Rust thread with the CPU's SHA instructions when
/// package:cb_native is built, several times faster than streaming the file
/// through `package:crypto`, which stays the fallback (and raises the precise
/// [FileSystemException] when the file cannot be read).
Future<Digest> sha256OfFile(String path) async {
  try {
    final native = await NativeHash.sha256File(path);
    if (native != null) return Digest(native);
  } on NativeJobException {
    // Read again below for Dart's error.
  }
  return sha256.bind(File(path).openRead()).first;
}
