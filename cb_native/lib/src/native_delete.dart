import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_job.dart';

class NativeDeleteResult {
  const NativeDeleteResult(this.path, this.errorCode, this.error);
  final String path;
  final int errorCode;
  final String error;
  bool get succeeded => errorCode == 0;
}

abstract final class NativeDelete {
  /// Deletes only the supplied targets on up to eight Rust threads.
  /// Null means no job started, so Dart may fall back. Once a job starts,
  /// failures are reported per path or thrown; destructive work is never
  /// silently replayed via a fallback after partial completion.
  static Future<List<NativeDeleteResult>?> permanently(
    List<String> paths, {
    int concurrency = 8,
    void Function(NativeJobProgress progress)? onProgress,
    void Function(NativeDeleteResult result)? onResult,
  }) async {
    final targets = List<String>.unmodifiable(paths);
    final config = WireWriter()
      ..strs(targets)
      ..u32(concurrency.clamp(1, 8));
    final job = NativeJob.start(b.jobPermanentDelete, config.takeBytes());
    if (job == null) return null;
    final results = <NativeDeleteResult>[];
    final output = await job.result(
      onProgress: onProgress,
      onOutput: (chunk) {
        final r = WireReader(chunk);
        while (!r.isDone) {
          final result = NativeDeleteResult(targets[r.u32()], r.i64(), r.str());
          results.add(result);
          onResult?.call(result);
        }
      },
    );
    if (output == null) {
      throw const NativeJobException('Permanent deletion was interrupted');
    }
    return results;
  }
}
