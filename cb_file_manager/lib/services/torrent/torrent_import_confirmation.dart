import 'torrent_entry.dart';

typedef TorrentMergeConfirmation = Future<bool> Function(TorrentEntry existing);

/// The user declined a duplicate merge; no import error or download is implied.
class TorrentImportCancelled implements Exception {
  const TorrentImportCancelled();
}
