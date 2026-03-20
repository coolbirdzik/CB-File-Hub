/// Data model for a file inside a video library.
class VideoLibraryFile {
  int id = 0;
  int videoLibraryId;
  String filePath;
  DateTime addedAt;
  String? caption;
  int orderIndex;

  VideoLibraryFile({
    required this.videoLibraryId,
    required this.filePath,
    DateTime? addedAt,
    this.caption,
    this.orderIndex = 0,
  }) : addedAt = addedAt ?? DateTime.now();

  factory VideoLibraryFile.fromDatabaseMap(Map<String, Object?> map) {
    return VideoLibraryFile(
      videoLibraryId: map['video_library_id'] as int? ?? 0,
      filePath: map['file_path'] as String? ?? '',
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        map['added_at'] as int? ?? 0,
      ),
      caption: map['caption'] as String?,
      orderIndex: map['order_index'] as int? ?? 0,
    )..id = map['id'] as int? ?? 0;
  }

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'id': id == 0 ? null : id,
      'video_library_id': videoLibraryId,
      'file_path': filePath,
      'added_at': addedAt.millisecondsSinceEpoch,
      'caption': caption,
      'order_index': orderIndex,
    };
  }

  VideoLibraryFile copyWith({
    int? videoLibraryId,
    String? filePath,
    DateTime? addedAt,
    String? caption,
    int? orderIndex,
  }) {
    return VideoLibraryFile(
      videoLibraryId: videoLibraryId ?? this.videoLibraryId,
      filePath: filePath ?? this.filePath,
      addedAt: addedAt ?? this.addedAt,
      caption: caption ?? this.caption,
      orderIndex: orderIndex ?? this.orderIndex,
    )..id = id;
  }

  @override
  String toString() {
    return 'VideoLibraryFile{id: $id, videoLibraryId: $videoLibraryId, '
        'filePath: $filePath, addedAt: $addedAt}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is VideoLibraryFile &&
        other.id == id &&
        other.videoLibraryId == videoLibraryId &&
        other.filePath == filePath &&
        other.addedAt == addedAt &&
        other.caption == caption &&
        other.orderIndex == orderIndex;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      videoLibraryId,
      filePath,
      addedAt,
      caption,
      orderIndex,
    );
  }
}
