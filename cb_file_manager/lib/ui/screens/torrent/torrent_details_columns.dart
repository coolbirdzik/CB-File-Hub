import '../../../config/languages/app_localizations.dart';
import '../../../services/torrent/torrent_entry.dart';
import '../../components/common/file_details_columns.dart';

class TorrentDetailsColumns {
  static const defaults = {
    'status',
    'progress',
    'downSpeed',
    'seeds',
    'peers',
    'eta',
    'downloaded',
    'files',
    'tracker',
    'destination',
  };
  static const _widths = {
    'status': 150.0,
    'progress': 100.0,
    'downSpeed': 120.0,
    'upSpeed': 120.0,
    'seeds': 80.0,
    'peers': 80.0,
    'eta': 140.0,
    'downloaded': 120.0,
    'uploaded': 120.0,
    'ratio': 120.0,
    'files': 100.0,
    'group': 160.0,
    'destination': 280.0,
    'hash': 340.0,
    'remaining': 120.0,
    'tracker': 280.0,
    'trackerCount': 120.0,
    'torrentCreated': 180.0,
    'createdBy': 200.0,
    'comment': 300.0,
    'private': 120.0,
    'pieceSize': 120.0,
    'pieceCount': 120.0,
    'metainfoSize': 140.0,
    'torrentFile': 300.0,
    'source': 300.0,
    'error': 300.0,
    'taskId': 180.0,
  };

  static List<FileDetailsColumn> build({
    required AppLocalizations l,
    required Map<String, TorrentEntry> entries,
    required Set<String> visible,
    required String Function(int) formatSize,
    void Function(String field)? onSort,
    String? sortField,
    bool sortAscending = true,
  }) => [
    for (final column in _widths.entries)
      FileDetailsColumn(
        id: column.key,
        label: l.torrentColumn(column.key),
        width: column.value,
        visible: visible.contains(column.key),
        onSort: onSort == null ? null : () => onSort(column.key),
        sortAscending: sortField == column.key ? sortAscending : null,
        description: const {'seeds', 'peers'}.contains(column.key)
            ? l.torrentColumn('${column.key}Hint')
            : null,
        valueOf: (path) {
          final e = entries[path];
          if (e == null) return '—';
          final hasDownload = e.status != 'library' || e.downloadDir != null;
          return switch (column.key) {
            'status' => l.torrentStatus(e.status),
            'progress' =>
              !hasDownload || e.totalBytes == 0
                  ? '—'
                  : '${(e.progress * 100).toStringAsFixed(1)}%',
            'downSpeed' =>
              hasDownload ? '${formatSize(e.downloadSpeed)}/s' : '—',
            'upSpeed' => hasDownload ? '${formatSize(e.uploadSpeed)}/s' : '—',
            'seeds' => e.status == 'active' ? '${e.seeders ?? '—'}' : '—',
            'peers' => e.status == 'active' ? '${e.connections ?? '—'}' : '—',
            'eta' => e.eta == null ? '—' : _duration(e.eta!),
            'downloaded' => hasDownload ? formatSize(e.completedBytes) : '—',
            'uploaded' =>
              e.uploadedBytes == null ? '—' : formatSize(e.uploadedBytes!),
            'ratio' => e.ratio?.toStringAsFixed(2) ?? '—',
            'files' => e.fileCount > 0 ? '${e.fileCount}' : '—',
            'group' => e.group.isEmpty ? '—' : e.group,
            'destination' => e.downloadDir ?? '—',
            'hash' => e.hash,
            'remaining' =>
              e.totalBytes > 0
                  ? formatSize(
                      (e.totalBytes - e.completedBytes).clamp(0, e.totalBytes),
                    )
                  : '—',
            'tracker' => e.trackers.isEmpty ? '—' : e.trackers.first,
            'trackerCount' =>
              e.pieceCount == null ? '—' : '${e.trackers.length}',
            'torrentCreated' => e.addedAt.toLocal().toString().split('.').first,
            'createdBy' => e.createdBy ?? '—',
            'comment' => e.comment ?? '—',
            'private' =>
              e.isPrivate == null
                  ? '—'
                  : l.torrentColumn(e.isPrivate! ? 'privateYes' : 'privateNo'),
            'pieceSize' =>
              e.pieceLength == null ? '—' : formatSize(e.pieceLength!),
            'pieceCount' => e.pieceCount == null ? '—' : '${e.pieceCount}',
            'metainfoSize' =>
              e.metainfoBytes == null ? '—' : formatSize(e.metainfoBytes!),
            'torrentFile' => e.torrentPath.isEmpty ? '—' : e.torrentPath,
            'source' =>
              e.sourceUri ?? (e.torrentPath.isEmpty ? '—' : e.torrentPath),
            'error' => e.error ?? '—',
            'taskId' => e.gid ?? '—',
            _ => '—',
          };
        },
      ),
  ];

  static String _duration(Duration duration) {
    final days = duration.inDays;
    final hours = (duration.inHours % 24).toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '${days > 0 ? '$days · ' : ''}$hours:$minutes:$seconds';
  }
}
