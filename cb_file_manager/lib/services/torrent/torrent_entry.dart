import 'dart:convert';

class TorrentEntry {
  final String hash;
  final String name;
  final String torrentPath;
  final String? sourceUri;
  final List<String> sourceUris;
  final String category;
  final String group;
  final int totalBytes;
  final int fileCount;
  final String status;
  final String? downloadDir;
  final String? gid;
  final int completedBytes;
  final int downloadSpeed;
  final int uploadSpeed;
  final int? uploadedBytes;
  final int? seeders;
  final int? connections;
  final String? error;
  final List<String> trackers;
  final String? comment;
  final String? createdBy;
  final DateTime? torrentCreatedAt;
  final bool? isPrivate;
  final int? pieceLength;
  final int? pieceCount;
  final int? metainfoBytes;

  /// When this torrent first joined this library; imports and merges retain it.
  final DateTime addedAt;
  final DateTime modifiedAt;

  TorrentEntry.fromMap(Map<String, Object?> row)
    : hash = row['hash'] as String,
      name = row['name'] as String,
      torrentPath = row['torrent_path'] as String,
      sourceUri = row['source_uri'] as String?,
      sourceUris = row['source_uris'] == null
          ? [if (row['source_uri'] is String) row['source_uri'] as String]
          : List<String>.from(jsonDecode(row['source_uris'] as String) as List),
      category = row['category'] as String,
      group = row['group_name'] as String,
      totalBytes = row['total_bytes'] as int,
      fileCount = row['file_count'] as int,
      status = row['status'] as String,
      downloadDir = row['download_dir'] as String?,
      gid = row['gid'] as String?,
      completedBytes = row['completed_bytes'] as int,
      downloadSpeed = row['download_speed'] as int,
      uploadSpeed = row['upload_speed'] as int? ?? 0,
      uploadedBytes = row['uploaded_bytes'] as int?,
      seeders = row['seeders'] as int?,
      connections = row['connections'] as int?,
      error = row['error'] as String?,
      trackers = row['trackers'] == null
          ? const []
          : List<String>.from(jsonDecode(row['trackers'] as String) as List),
      comment = row['comment'] as String?,
      createdBy = row['created_by'] as String?,
      torrentCreatedAt = row['torrent_created_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row['torrent_created_at'] as int,
            ),
      isPrivate = row['is_private'] == null ? null : row['is_private'] == 1,
      pieceLength = row['piece_length'] as int?,
      pieceCount = row['piece_count'] as int?,
      metainfoBytes = row['metainfo_bytes'] as int?,
      addedAt = DateTime.fromMillisecondsSinceEpoch(
        row['added_at'] as int? ?? 0,
      ),
      modifiedAt = DateTime.fromMillisecondsSinceEpoch(
        row['modified_at'] as int? ?? row['added_at'] as int? ?? 0,
      );

  double get progress =>
      totalBytes == 0 ? 0 : (completedBytes / totalBytes).clamp(0, 1);

  Duration? get eta => status == 'active' && downloadSpeed > 0 && totalBytes > 0
      ? Duration(
          seconds:
              ((totalBytes - completedBytes).clamp(0, totalBytes) /
                      downloadSpeed)
                  .ceil(),
        )
      : null;

  double? get ratio => uploadedBytes != null && completedBytes > 0
      ? uploadedBytes! / completedBytes
      : null;
}

class TorrentPage {
  final List<TorrentEntry> entries;
  final int total;
  const TorrentPage(this.entries, this.total);
}

class TorrentScanProgress {
  final bool running;
  final int visited;
  final int imported;
  final int duplicates;
  final int failed;
  final String currentPath;

  /// Bounded error sample; [failed] retains the complete failure count.
  final List<String> errors;
  final bool cancelled;
  const TorrentScanProgress({
    this.running = false,
    this.visited = 0,
    this.imported = 0,
    this.duplicates = 0,
    this.failed = 0,
    this.currentPath = '',
    this.errors = const [],
    this.cancelled = false,
  });
}

/// Exact source files shown to the user before cleaning existing originals.
class TorrentMoveSource {
  final String path;
  final String destination;
  final String hash;
  final int modified;
  final int size;
  const TorrentMoveSource({
    required this.path,
    required this.destination,
    required this.hash,
    required this.modified,
    required this.size,
  });
}

class TorrentMovePlan {
  final String destination;
  final String previousMode;
  final String? previousDirectory;
  final List<TorrentMoveSource> sources;
  TorrentMovePlan({
    required this.destination,
    required this.previousMode,
    required this.previousDirectory,
    required List<TorrentMoveSource> sources,
  }) : sources = List.unmodifiable(sources);
}
