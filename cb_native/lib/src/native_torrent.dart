import 'dart:typed_data';
import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_job.dart';

class NativeTorrentMetainfo {
  const NativeTorrentMetainfo({
    required this.hash,
    required this.name,
    required this.totalBytes,
    required this.fileCount,
    required this.category,
    required this.trackers,
    this.comment,
    this.createdBy,
    this.creationDate,
    required this.isPrivate,
    required this.pieceLength,
    required this.pieceCount,
  });
  final String hash, name, category;
  final int totalBytes, fileCount, pieceLength, pieceCount;
  final List<String> trackers;
  final String? comment, createdBy;
  final int? creationDate;
  final bool isPrivate;

  /// Null means unavailable or unsupported. Callers retain Dart validation as
  /// fallback, including precise FormatExceptions for malformed metainfo.
  static Future<NativeTorrentMetainfo?> parse(Uint8List bytes) async {
    final job = NativeJob.start(b.jobTorrentMetainfo, bytes);
    if (job == null) return null;
    final Uint8List? out;
    try {
      out = await job.result();
    } on NativeJobException {
      return null;
    }
    if (out == null) return null;
    final r = WireReader(out);
    final hash = r.str(), name = r.str();
    final total = r.i64(), count = r.u32();
    final category = r.str();
    final trackers = List.generate(r.u32(), (_) => r.str());
    return NativeTorrentMetainfo(
      hash: hash,
      name: name,
      totalBytes: total,
      fileCount: count,
      category: category,
      trackers: trackers,
      comment: r.boolean() ? r.str() : null,
      createdBy: r.boolean() ? r.str() : null,
      creationDate: r.boolean() ? r.i64() : null,
      isPrivate: r.boolean(),
      pieceLength: r.i64(),
      pieceCount: r.i64(),
    );
  }
}
