/// Rust-backed helpers for CB File Hub.
///
/// Every entry point degrades gracefully: when the native library was not
/// built for this platform (see hook/build.dart), [CbNative.isAvailable] is
/// false and every start / helper returns null (or false) so callers use
/// their Dart code.
library;

export 'src/native_archive.dart';
export 'src/native_content.dart';
export 'src/native_delete.dart';
export 'src/native_disk_scan.dart';
export 'src/native_fs.dart';
export 'src/native_hash.dart';
export 'src/native_image.dart';
export 'src/native_job.dart' show NativeJobException, NativeJobProgress;
export 'src/native_journal.dart';
export 'src/native_torrent.dart';
export 'src/native_ui_jobs.dart';
export 'src/native_search.dart';
