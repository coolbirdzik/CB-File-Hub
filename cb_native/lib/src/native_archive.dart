import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_job.dart';

/// Formats [NativeArchive] handles, in the order of the app's
/// `ArchiveFormat` enum (RAR is not one of them).
enum NativeArchiveFormat {
  zip,
  tar,
  tarGz,
  tarBz2,
  tarXz,
  gzip,
  bzip2,
  sevenZip,
}

class NativeArchiveEntry {
  const NativeArchiveEntry({
    required this.name,
    required this.size,
    required this.compressedSize,
    required this.isDirectory,
    required this.modified,
  });

  /// With `/` separators.
  final String name;
  final int size;

  /// 0 when the format does not record it per entry.
  final int compressedSize;
  final bool isDirectory;

  /// Local time, or null when the archive has none.
  final DateTime? modified;
}

/// Archive listing and extraction on a Rust thread.
abstract final class NativeArchive {
  /// Lists [path]. Returns null when the library is unavailable or the
  /// format is [NativeArchiveFormat.gzip] / [NativeArchiveFormat.bzip2]
  /// (single streams with nothing to list). Throws [NativeJobException] when
  /// the archive cannot be read.
  static Future<List<NativeArchiveEntry>?> list(
    String path,
    NativeArchiveFormat format,
  ) async {
    if (format == NativeArchiveFormat.gzip ||
        format == NativeArchiveFormat.bzip2) {
      return null;
    }
    final config = WireWriter()
      ..str(path)
      ..u8(format.index);
    final job = NativeJob.start(b.jobArchiveList, config.takeBytes());
    if (job == null) return null;
    final out = await job.result();
    if (out == null) return null;
    final entries = <NativeArchiveEntry>[];
    final r = WireReader(out);
    while (!r.isDone) {
      final name = r.str();
      final size = r.i64();
      final compressed = r.i64();
      final isDirectory = r.boolean();
      final timeKind = r.u8();
      final time = r.i64();
      entries.add(
        NativeArchiveEntry(
          name: name,
          size: size,
          compressedSize: compressed,
          isDirectory: isDirectory,
          modified: _time(timeKind, time),
        ),
      );
    }
    return entries;
  }

  static DateTime? _time(int kind, int ms) {
    switch (kind) {
      case 1:
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      case 2:
        // A zone-less wall-clock time (zip): read the fields as local time.
        final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
        return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
      default:
        return null;
    }
  }

  /// Extracts [path] into [destination], or only [entry] (by its `/` name,
  /// written flat under its base name like `7z e`). [onProgress] receives
  /// bytes done and total while it runs. Returns false when the library is
  /// unavailable or the extraction was cancelled through [shouldContinue].
  /// Throws [NativeJobException] when it fails.
  static Future<bool> extract({
    required String path,
    required NativeArchiveFormat format,
    required String destination,
    String? entry,
    void Function(int done, int total)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    final config = WireWriter()
      ..str(path)
      ..u8(format.index)
      ..str(destination)
      ..boolean(entry != null)
      ..str(entry ?? '');
    final job = NativeJob.start(b.jobArchiveExtract, config.takeBytes());
    if (job == null) return false;
    final out = await job.result(
      shouldContinue: shouldContinue,
      onProgress: onProgress == null
          ? null
          : (progress) =>
                onProgress(progress.counters[0], progress.counters[1]),
    );
    return out != null;
  }
}
