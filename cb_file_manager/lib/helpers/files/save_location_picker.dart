import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A destination the user chose in the save dialog, plus the scratch path that
/// the export should actually be written to.
///
/// Call [commit] once the scratch file holds the finished export, or [discard]
/// when the export failed or was abandoned. Exactly one of the two should run.
class PickedSaveLocation {
  PickedSaveLocation._(this.path) : scratchPath = '$path.cbpart';

  /// Where the finished file belongs — show this to the user after [commit].
  final String path;

  /// Where to write while the export is still in progress.
  final String scratchPath;

  /// Moves the scratch file onto [path] and returns [path].
  Future<String> commit() async {
    final destination = File(path);
    if (await destination.exists()) {
      await destination.delete();
    }
    final scratch = File(scratchPath);
    try {
      await scratch.rename(path);
    } on FileSystemException {
      // A rename inside one directory should not fail, but Windows can hold a
      // transient lock (indexer, antivirus). Copying still gets the finished
      // export to the user rather than throwing away work that succeeded.
      await scratch.copy(path);
      await _deleteQuietly(scratch);
    }
    return path;
  }

  /// Removes the scratch file and the empty placeholder the picker left.
  ///
  /// The placeholder is only deleted while it is still zero bytes, so this can
  /// never destroy a file that something else has written in the meantime.
  Future<void> discard() async {
    await _deleteQuietly(File(scratchPath));
    final destination = File(path);
    try {
      if (await destination.exists() && await destination.length() == 0) {
        await destination.delete();
      }
    } catch (_) {
      // Best effort — cleanup must never mask the failure that triggered it.
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort.
    }
  }
}

/// Asks the user where to save a file and returns a [PickedSaveLocation], or
/// null if they cancelled.
///
/// file_picker 12 dropped the path-only save dialog: [FilePicker.saveFile] now
/// takes the payload up front, writes it itself and returns a [Uri]. Callers
/// that only produce their bytes *after* the dialog closes — a streamed remote
/// download, an export written by a service — therefore have to ask with an
/// empty payload, which drops a zero-byte file on the destination.
///
/// Writing through [PickedSaveLocation.scratchPath] keeps that placeholder from
/// being mistaken for the export: the destination only ever ends up holding a
/// complete file, and a failed export cleans the placeholder away instead of
/// leaving an empty file where there was none before.
///
/// One caveat is inherent to the picker: it truncates the destination the
/// moment the user confirms an overwrite, so an existing file of the same name
/// is already gone before the export runs.
///
/// Exports that have their bytes in hand should skip this and call
/// [FilePicker.saveFile] directly.
Future<PickedSaveLocation?> pickSaveLocation({
  required String fileName,
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: Uint8List(0),
    dialogTitle: dialogTitle,
    type: type,
    allowedExtensions: allowedExtensions,
  );
  if (uri == null) return null;
  return PickedSaveLocation._(
    uri.isScheme('file') ? uri.toFilePath() : uri.toString(),
  );
}
