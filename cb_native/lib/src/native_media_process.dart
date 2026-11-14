import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_job.dart';

class NativeMediaProcessResult {
  const NativeMediaProcessResult(this.exitCode, this.diagnostic);

  final int exitCode;
  final String diagnostic;
}

/// A cancellable FFmpeg subprocess with both pipes drained on Rust threads.
/// A null start means unavailable/unsupported; callers may then use Dart.
class NativeMediaProcess {
  NativeMediaProcess._(this._job, this._durationUs);

  final NativeJob _job;
  final int _durationUs;

  static NativeMediaProcess? start({
    required String executable,
    required List<String> arguments,
    required Duration duration,
  }) {
    if (duration <= Duration.zero) return null;
    final config = WireWriter()
      ..str(executable)
      ..i64(duration.inMicroseconds)
      ..strs(arguments);
    final job = NativeJob.start(b.jobFfmpegProcess, config.takeBytes());
    return job == null
        ? null
        : NativeMediaProcess._(job, duration.inMicroseconds);
  }

  void cancel() => _job.cancel();

  /// Cancellation waits for terminal state, so the caller can safely remove
  /// partial output files after this returns null (Windows file handles too).
  Future<NativeMediaProcessResult?> result({
    void Function(double)? onProgress,
  }) async {
    final bytes = await _job.result(
      onProgress: onProgress == null
          ? null
          : (progress) => onProgress(
              (progress.counters[0] / _durationUs).clamp(0.0, 1.0),
            ),
    );
    if (bytes == null) return null;
    final reader = WireReader(bytes);
    return NativeMediaProcessResult(reader.i32(), reader.str());
  }
}
