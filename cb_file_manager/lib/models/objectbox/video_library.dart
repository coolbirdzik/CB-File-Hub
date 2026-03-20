/// Data model for a video library.
class VideoLibrary {
  int id = 0;
  String name;
  String? description;
  String? coverImagePath;
  DateTime createdAt;
  DateTime modifiedAt;
  String? colorTheme;
  bool isSystemLibrary;

  VideoLibrary({
    required this.name,
    this.description,
    this.coverImagePath,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.colorTheme,
    this.isSystemLibrary = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  factory VideoLibrary.fromDatabaseMap(Map<String, Object?> map) {
    return VideoLibrary(
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      coverImagePath: map['cover_image_path'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int? ?? 0,
      ),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        map['modified_at'] as int? ?? 0,
      ),
      colorTheme: map['color_theme'] as String?,
      isSystemLibrary: (map['is_system_library'] as int? ?? 0) == 1,
    )..id = map['id'] as int? ?? 0;
  }

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'id': id == 0 ? null : id,
      'name': name,
      'description': description,
      'cover_image_path': coverImagePath,
      'created_at': createdAt.millisecondsSinceEpoch,
      'modified_at': modifiedAt.millisecondsSinceEpoch,
      'color_theme': colorTheme,
      'is_system_library': isSystemLibrary ? 1 : 0,
    };
  }

  void updateModifiedTime() {
    modifiedAt = DateTime.now();
  }

  VideoLibrary copyWith({
    String? name,
    String? description,
    String? coverImagePath,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? colorTheme,
    bool? isSystemLibrary,
  }) {
    return VideoLibrary(
      name: name ?? this.name,
      description: description ?? this.description,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      colorTheme: colorTheme ?? this.colorTheme,
      isSystemLibrary: isSystemLibrary ?? this.isSystemLibrary,
    )..id = id;
  }

  @override
  String toString() {
    return 'VideoLibrary{id: $id, name: $name, description: $description, '
        'createdAt: $createdAt, modifiedAt: $modifiedAt, '
        'isSystemLibrary: $isSystemLibrary}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is VideoLibrary &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.coverImagePath == coverImagePath &&
        other.createdAt == createdAt &&
        other.modifiedAt == modifiedAt &&
        other.colorTheme == colorTheme &&
        other.isSystemLibrary == isSystemLibrary;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      description,
      coverImagePath,
      createdAt,
      modifiedAt,
      colorTheme,
      isSystemLibrary,
    );
  }
}
