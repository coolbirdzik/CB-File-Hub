/// Data model for a file inside an album.
class AlbumFile {
  int id = 0;
  int albumId;
  String filePath;
  int orderIndex;
  DateTime addedAt;
  String? caption;
  bool isCover;

  AlbumFile({
    required this.albumId,
    required this.filePath,
    this.orderIndex = 0,
    DateTime? addedAt,
    this.caption,
    this.isCover = false,
  }) : addedAt = addedAt ?? DateTime.now();

  factory AlbumFile.fromDatabaseMap(Map<String, Object?> map) {
    return AlbumFile(
      albumId: map['album_id'] as int? ?? 0,
      filePath: map['file_path'] as String? ?? '',
      orderIndex: map['order_index'] as int? ?? 0,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        map['added_at'] as int? ?? 0,
      ),
      caption: map['caption'] as String?,
      isCover: (map['is_cover'] as int? ?? 0) == 1,
    )..id = map['id'] as int? ?? 0;
  }

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'id': id == 0 ? null : id,
      'album_id': albumId,
      'file_path': filePath,
      'order_index': orderIndex,
      'added_at': addedAt.millisecondsSinceEpoch,
      'caption': caption,
      'is_cover': isCover ? 1 : 0,
    };
  }

  AlbumFile copyWith({
    int? albumId,
    String? filePath,
    int? orderIndex,
    DateTime? addedAt,
    String? caption,
    bool? isCover,
  }) {
    return AlbumFile(
      albumId: albumId ?? this.albumId,
      filePath: filePath ?? this.filePath,
      orderIndex: orderIndex ?? this.orderIndex,
      addedAt: addedAt ?? this.addedAt,
      caption: caption ?? this.caption,
      isCover: isCover ?? this.isCover,
    )..id = id;
  }

  @override
  String toString() {
    return 'AlbumFile{id: $id, albumId: $albumId, filePath: $filePath, '
        'orderIndex: $orderIndex, addedAt: $addedAt, '
        'caption: $caption, isCover: $isCover}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AlbumFile &&
        other.id == id &&
        other.albumId == albumId &&
        other.filePath == filePath &&
        other.orderIndex == orderIndex &&
        other.addedAt == addedAt &&
        other.caption == caption &&
        other.isCover == isCover;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      albumId,
      filePath,
      orderIndex,
      addedAt,
      caption,
      isCover,
    );
  }
}
