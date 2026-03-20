/// Data model for video library scanning configuration.
class VideoLibraryConfig {
  int id = 0;
  int videoLibraryId;
  bool includeSubdirectories;
  String fileExtensions;
  bool autoRefresh;
  int maxFileCount;
  String sortBy;
  bool sortAscending;
  String excludePatterns;
  bool enableAutoRules;
  String directories;
  DateTime? lastScanTime;
  int fileCount;

  VideoLibraryConfig({
    required this.videoLibraryId,
    this.includeSubdirectories = true,
    this.fileExtensions =
        '.mp4,.avi,.mov,.wmv,.flv,.webm,.mkv,.m4v,.mpg,.mpeg,.3gp,.ogv',
    this.autoRefresh = true,
    this.maxFileCount = 10000,
    this.sortBy = 'date',
    this.sortAscending = false,
    this.excludePatterns = '',
    this.enableAutoRules = true,
    this.directories = '',
    this.lastScanTime,
    this.fileCount = 0,
  });

  factory VideoLibraryConfig.fromDatabaseMap(Map<String, Object?> map) {
    final lastScanTimeValue = map['last_scan_time'];
    return VideoLibraryConfig(
      videoLibraryId: map['video_library_id'] as int? ?? 0,
      includeSubdirectories: (map['include_subdirectories'] as int? ?? 0) == 1,
      fileExtensions: map['file_extensions'] as String? ?? '',
      autoRefresh: (map['auto_refresh'] as int? ?? 0) == 1,
      maxFileCount: map['max_file_count'] as int? ?? 0,
      sortBy: map['sort_by'] as String? ?? 'date',
      sortAscending: (map['sort_ascending'] as int? ?? 0) == 1,
      excludePatterns: map['exclude_patterns'] as String? ?? '',
      enableAutoRules: (map['enable_auto_rules'] as int? ?? 0) == 1,
      directories: map['directories'] as String? ?? '',
      lastScanTime: lastScanTimeValue == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastScanTimeValue as int),
      fileCount: map['file_count'] as int? ?? 0,
    )..id = map['id'] as int? ?? 0;
  }

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'id': id == 0 ? null : id,
      'video_library_id': videoLibraryId,
      'include_subdirectories': includeSubdirectories ? 1 : 0,
      'file_extensions': fileExtensions,
      'auto_refresh': autoRefresh ? 1 : 0,
      'max_file_count': maxFileCount,
      'sort_by': sortBy,
      'sort_ascending': sortAscending ? 1 : 0,
      'exclude_patterns': excludePatterns,
      'enable_auto_rules': enableAutoRules ? 1 : 0,
      'directories': directories,
      'last_scan_time': lastScanTime?.millisecondsSinceEpoch,
      'file_count': fileCount,
    };
  }

  List<String> get fileExtensionsList {
    if (fileExtensions.isEmpty) {
      return <String>[];
    }
    return fileExtensions.split(',').map((entry) => entry.trim()).toList();
  }

  set fileExtensionsList(List<String> extensions) {
    fileExtensions = extensions.join(',');
  }

  List<String> get excludePatternsList {
    if (excludePatterns.isEmpty) {
      return <String>[];
    }
    return excludePatterns.split(',').map((entry) => entry.trim()).toList();
  }

  set excludePatternsList(List<String> patterns) {
    excludePatterns = patterns.join(',');
  }

  List<String> get directoriesList {
    if (directories.isEmpty) {
      return <String>[];
    }
    return directories.split(',').map((entry) => entry.trim()).toList();
  }

  set directoriesList(List<String> values) {
    directories = values.join(',');
  }

  void updateScanStats(int foundFileCount) {
    lastScanTime = DateTime.now();
    fileCount = foundFileCount;
  }

  VideoLibraryConfig copyWith({
    int? videoLibraryId,
    bool? includeSubdirectories,
    String? fileExtensions,
    bool? autoRefresh,
    int? maxFileCount,
    String? sortBy,
    bool? sortAscending,
    String? excludePatterns,
    bool? enableAutoRules,
    String? directories,
    DateTime? lastScanTime,
    int? fileCount,
  }) {
    return VideoLibraryConfig(
      videoLibraryId: videoLibraryId ?? this.videoLibraryId,
      includeSubdirectories:
          includeSubdirectories ?? this.includeSubdirectories,
      fileExtensions: fileExtensions ?? this.fileExtensions,
      autoRefresh: autoRefresh ?? this.autoRefresh,
      maxFileCount: maxFileCount ?? this.maxFileCount,
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      enableAutoRules: enableAutoRules ?? this.enableAutoRules,
      directories: directories ?? this.directories,
      lastScanTime: lastScanTime ?? this.lastScanTime,
      fileCount: fileCount ?? this.fileCount,
    )..id = id;
  }

  @override
  String toString() {
    return 'VideoLibraryConfig{id: $id, videoLibraryId: $videoLibraryId, '
        'includeSubdirectories: $includeSubdirectories, '
        'autoRefresh: $autoRefresh, fileCount: $fileCount}';
  }
}
