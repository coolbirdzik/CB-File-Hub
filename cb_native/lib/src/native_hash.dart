import 'dart:typed_data';

import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_job.dart';

abstract final class NativeHash {
  /// The SHA-256 digest of the file at [path], hashed on a Rust thread with
  /// the CPU's SHA instructions when it has them. Returns null when the
  /// library is unavailable or [shouldContinue] turned false. Throws
  /// [NativeJobException] when the file cannot be read.
  static Future<Uint8List?> sha256File(
    String path, {
    bool Function()? shouldContinue,
    void Function(int hashed, int total)? onProgress,
  }) async {
    final config = WireWriter()
      ..str(path)
      ..u8(0);
    final job = NativeJob.start(b.jobHashFile, config.takeBytes());
    if (job == null) return null;
    return job.result(
      shouldContinue: shouldContinue,
      onProgress: onProgress == null
          ? null
          : (progress) =>
                onProgress(progress.counters[0], progress.counters[1]),
    );
  }
}
