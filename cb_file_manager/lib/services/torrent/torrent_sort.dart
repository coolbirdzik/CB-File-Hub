/// Whitelisted index expressions. Numeric properties sort by their raw value,
/// including ratios/durations, and unknown values stay last in either direction.
class TorrentSort {
  final String field;
  final bool ascending;
  const TorrentSort(this.field, {this.ascending = true});

  static const _hasDownload =
      "(status <> 'library' OR download_dir IS NOT NULL)";
  static const expressions = <String, String>{
    'status': 'status',
    'progress':
        'CASE WHEN $_hasDownload AND total_bytes > 0 '
        'THEN MIN(1.0, MAX(0.0, completed_bytes * 1.0 / total_bytes)) END',
    'downSpeed': 'CASE WHEN $_hasDownload THEN download_speed END',
    'upSpeed': 'CASE WHEN $_hasDownload THEN upload_speed END',
    'seeds': "CASE WHEN status = 'active' THEN seeders END",
    'peers': "CASE WHEN status = 'active' THEN connections END",
    'eta':
        "CASE WHEN status = 'active' AND download_speed > 0 AND total_bytes > 0 "
        'THEN (MAX(0, total_bytes - completed_bytes) + download_speed - 1) / download_speed END',
    'downloaded': 'CASE WHEN $_hasDownload THEN completed_bytes END',
    'uploaded': 'uploaded_bytes',
    'ratio':
        'CASE WHEN completed_bytes > 0 THEN uploaded_bytes * 1.0 / completed_bytes END',
    'files': 'CASE WHEN file_count > 0 THEN file_count END',
    'group': "NULLIF(lower(group_name), '')",
    'destination': "NULLIF(lower(download_dir), '')",
    'hash': 'hash',
    'remaining':
        'CASE WHEN total_bytes > 0 THEN MAX(0, MIN(total_bytes, total_bytes - completed_bytes)) END',
    'tracker': "NULLIF(sort_tracker, '')",
    'trackerCount':
        'CASE WHEN piece_count IS NOT NULL THEN sort_tracker_count END',
    'torrentCreated': 'torrent_created_at',
    'createdBy': "NULLIF(lower(created_by), '')",
    'comment': "NULLIF(lower(comment), '')",
    'private': 'is_private',
    'pieceSize': 'piece_length',
    'pieceCount': 'piece_count',
    'metainfoSize': 'metainfo_bytes',
    'torrentFile': "NULLIF(lower(torrent_path), '')",
    'source': "NULLIF(lower(COALESCE(source_uri, torrent_path)), '')",
    'error': "NULLIF(lower(error), '')",
    'taskId': "NULLIF(lower(gid), '')",
  };

  String get orderBy {
    final expression = expressions[field];
    if (expression == null) throw ArgumentError.value(field, 'field');
    return '($expression) IS NULL ASC, ($expression) ${ascending ? 'ASC' : 'DESC'}, '
        'COALESCE(sort_name, lower(name)) ASC';
  }
}
