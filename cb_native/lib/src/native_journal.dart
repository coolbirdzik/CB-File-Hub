import 'dart:typed_data';
import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_job.dart';

class NativeJournalParents {
  const NativeJournalParents(this.journalId, this.nextUsn, this.parentIds);
  final int journalId, nextUsn;
  final List<int> parentIds;

  /// Null on unsupported platforms, unavailable libraries, lost cursors or
  /// access errors. The Dart journal reader remains the fallback.
  static Future<NativeJournalParents?> read(
    String drive,
    int id,
    int usn,
  ) async {
    final config = WireWriter()
      ..str(drive)
      ..i64(id)
      ..i64(usn);
    final job = NativeJob.start(b.jobUsnParents, config.takeBytes());
    if (job == null) return null;
    final Uint8List? out;
    try {
      out = await job.result();
    } on NativeJobException {
      return null;
    }
    if (out == null) return null;
    final r = WireReader(out);
    final journal = r.i64(), next = r.i64();
    return NativeJournalParents(
      journal,
      next,
      List.generate(r.u32(), (_) => r.i64()),
    );
  }
}
