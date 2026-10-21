import 'dart:io';

import 'package:equatable/equatable.dart';

// Define view modes
enum ViewMode { list, grid, details, gridPreview, columns, tree, tiles }

// Define sort options
enum SortOption {
  nameAsc,
  nameDesc,
  dateAsc,
  dateDesc,
  sizeAsc,
  sizeDesc,
  typeAsc,
  typeDesc, // Added type descending
  dateCreatedAsc, // Added date created
  dateCreatedDesc, // Added date created descending
  extensionAsc, // Added extension
  extensionDesc, // Added extension descending
  attributesAsc, // Added file attributes
  attributesDesc, // Added file attributes descending
  dateAccessedAsc,
  dateAccessedDesc,
  pathAsc,
  pathDesc,
}

/// Columns of the Details view. Declaration order is the default column
/// order; new columns are appended so saved orders keep their meaning.
enum DetailsColumn {
  name(280),
  type(140),
  size(100),
  dateModified(170),
  dateCreated(170),
  attributes(90),
  dateAccessed(170),
  extension(90),
  path(320),
  tags(160),
  dimensions(110),
  duration(90),
  itemCount(80),
  parentFolder(240),
  permissions(110),
  // Windows Shell properties, as in Explorer's Details view.
  owner(180, shell: true),
  authors(160, shell: true),
  title(200, shell: true),
  comments(220, shell: true),
  pageCount(70, shell: true),
  rating(110, shell: true),
  dateTaken(170, shell: true),
  cameraModel(150, shell: true),
  frameRate(110, shell: true),
  bitRate(100, shell: true),
  artist(170, shell: true),
  album(170, shell: true),
  genre(110, shell: true),
  year(70, shell: true),
  company(170, shell: true),
  fileDescription(220, shell: true),
  fileVersion(120, shell: true),
  productName(180, shell: true);

  const DetailsColumn(this.defaultWidth, {this.shell = false});

  final double defaultWidth;

  /// Read from the Windows Shell property system; Windows only.
  final bool shell;

  /// Whether this column can be shown on the running platform.
  bool get isAvailable => !shell || Platform.isWindows;

  static const double minWidth = 48;
}

// Define column visibility options for details view
class ColumnVisibility extends Equatable {
  final bool name;
  final bool size;
  final bool type;
  final bool dateModified;
  final bool dateCreated;
  final bool attributes;
  final bool dateAccessed;
  final bool extension;
  final bool path;
  final bool tags;
  final bool dimensions;
  final bool duration;
  final bool itemCount;
  final bool parentFolder;
  final bool permissions;

  /// Column order chosen by the user. It may be partial or stale;
  /// [orderedColumns] resolves it.
  final List<DetailsColumn> order;

  /// Widths the user resized columns to; other columns use their default.
  final Map<DetailsColumn, double> widths;

  /// Shown [DetailsColumn.shell] columns (they have no flag of their own).
  final Set<DetailsColumn> shellColumns;

  const ColumnVisibility({
    this.name = true, // Name is always visible by default
    this.size = true,
    this.type = true,
    this.dateModified = true,
    this.dateCreated = false,
    this.attributes = false,
    this.dateAccessed = false,
    this.extension = false,
    this.path = false,
    this.tags = false,
    this.dimensions = false,
    this.duration = false,
    this.itemCount = false,
    this.parentFolder = false,
    this.permissions = false,
    this.order = const [],
    this.widths = const {},
    this.shellColumns = const {},
  });

  bool isVisible(DetailsColumn column) => switch (column) {
    DetailsColumn.name => true,
    DetailsColumn.type => type,
    DetailsColumn.size => size,
    DetailsColumn.dateModified => dateModified,
    DetailsColumn.dateCreated => dateCreated,
    DetailsColumn.attributes => attributes,
    DetailsColumn.dateAccessed => dateAccessed,
    DetailsColumn.extension => extension,
    DetailsColumn.path => path,
    DetailsColumn.tags => tags,
    DetailsColumn.dimensions => dimensions,
    DetailsColumn.duration => duration,
    DetailsColumn.itemCount => itemCount,
    DetailsColumn.parentFolder => parentFolder,
    DetailsColumn.permissions => permissions,
    _ => shellColumns.contains(column),
  };

  /// Every column in display order: Name first, then the saved order, then
  /// columns the saved order does not know yet.
  List<DetailsColumn> get orderedColumns {
    final seen = <DetailsColumn>{DetailsColumn.name};
    return [
      DetailsColumn.name,
      for (final column in [...order, ...DetailsColumn.values])
        if (seen.add(column)) column,
    ];
  }

  List<DetailsColumn> get visibleColumns => orderedColumns
      .where((column) => column.isAvailable && isVisible(column))
      .toList();

  double widthOf(DetailsColumn column) => widths[column] ?? column.defaultWidth;

  ColumnVisibility withColumn(DetailsColumn column, bool visible) =>
      switch (column) {
        DetailsColumn.name => this,
        DetailsColumn.type => copyWith(type: visible),
        DetailsColumn.size => copyWith(size: visible),
        DetailsColumn.dateModified => copyWith(dateModified: visible),
        DetailsColumn.dateCreated => copyWith(dateCreated: visible),
        DetailsColumn.attributes => copyWith(attributes: visible),
        DetailsColumn.dateAccessed => copyWith(dateAccessed: visible),
        DetailsColumn.extension => copyWith(extension: visible),
        DetailsColumn.path => copyWith(path: visible),
        DetailsColumn.tags => copyWith(tags: visible),
        DetailsColumn.dimensions => copyWith(dimensions: visible),
        DetailsColumn.duration => copyWith(duration: visible),
        DetailsColumn.itemCount => copyWith(itemCount: visible),
        DetailsColumn.parentFolder => copyWith(parentFolder: visible),
        DetailsColumn.permissions => copyWith(permissions: visible),
        _ => copyWith(
          shellColumns: visible
              ? {...shellColumns, column}
              : ({...shellColumns}..remove(column)),
        ),
      };

  /// Sets [column] to [width] (at least [DetailsColumn.minWidth]), or back to
  /// its default width when [width] is null.
  ColumnVisibility withWidth(DetailsColumn column, double? width) {
    final next = Map<DetailsColumn, double>.of(widths);
    if (width == null) {
      next.remove(column);
    } else {
      next[column] = width < DetailsColumn.minWidth
          ? DetailsColumn.minWidth
          : width.roundToDouble();
    }
    return copyWith(widths: next);
  }

  /// Moves [column] into the slot of [target], shifting the columns between
  /// them, like dropping a dragged header onto another one. Name stays first.
  ColumnVisibility moveColumn(DetailsColumn column, DetailsColumn target) {
    if (column == DetailsColumn.name || column == target) return this;
    final next = orderedColumns;
    final to = next.indexOf(target);
    next.remove(column);
    next.insert(to < 1 ? 1 : to, column);
    return copyWith(order: next.sublist(1));
  }

  /// Drops the custom order and widths, keeping which columns are shown.
  ColumnVisibility resetLayout() => copyWith(order: const [], widths: const {});

  // Create a copy with modified values
  ColumnVisibility copyWith({
    bool? name,
    bool? size,
    bool? type,
    bool? dateModified,
    bool? dateCreated,
    bool? attributes,
    bool? dateAccessed,
    bool? extension,
    bool? path,
    bool? tags,
    bool? dimensions,
    bool? duration,
    bool? itemCount,
    bool? parentFolder,
    bool? permissions,
    List<DetailsColumn>? order,
    Map<DetailsColumn, double>? widths,
    Set<DetailsColumn>? shellColumns,
  }) {
    return ColumnVisibility(
      name: name ?? this.name,
      size: size ?? this.size,
      type: type ?? this.type,
      dateModified: dateModified ?? this.dateModified,
      dateCreated: dateCreated ?? this.dateCreated,
      attributes: attributes ?? this.attributes,
      dateAccessed: dateAccessed ?? this.dateAccessed,
      extension: extension ?? this.extension,
      path: path ?? this.path,
      tags: tags ?? this.tags,
      dimensions: dimensions ?? this.dimensions,
      duration: duration ?? this.duration,
      itemCount: itemCount ?? this.itemCount,
      parentFolder: parentFolder ?? this.parentFolder,
      permissions: permissions ?? this.permissions,
      order: order ?? this.order,
      widths: widths ?? this.widths,
      shellColumns: shellColumns ?? this.shellColumns,
    );
  }

  // Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'size': size,
      'type': type,
      'dateModified': dateModified,
      'dateCreated': dateCreated,
      'attributes': attributes,
      'dateAccessed': dateAccessed,
      'extension': extension,
      'path': path,
      'tags': tags,
      'dimensions': dimensions,
      'duration': duration,
      'itemCount': itemCount,
      'parentFolder': parentFolder,
      'permissions': permissions,
      if (order.isNotEmpty) 'order': [for (final column in order) column.name],
      if (widths.isNotEmpty)
        'widths': {
          for (final entry in widths.entries) entry.key.name: entry.value,
        },
      if (shellColumns.isNotEmpty)
        'shellColumns': [for (final column in shellColumns) column.name],
    };
  }

  // Create from map
  factory ColumnVisibility.fromMap(Map<String, dynamic> map) {
    final byName = DetailsColumn.values.asNameMap();
    final order = map['order'];
    final widths = map['widths'];
    final shellColumns = map['shellColumns'];
    return ColumnVisibility(
      name: map['name'] ?? true,
      size: map['size'] ?? true,
      type: map['type'] ?? true,
      dateModified: map['dateModified'] ?? true,
      dateCreated: map['dateCreated'] ?? false,
      attributes: map['attributes'] ?? false,
      dateAccessed: map['dateAccessed'] ?? false,
      extension: map['extension'] ?? false,
      path: map['path'] ?? false,
      tags: map['tags'] ?? false,
      dimensions: map['dimensions'] ?? false,
      duration: map['duration'] ?? false,
      itemCount: map['itemCount'] ?? false,
      parentFolder: map['parentFolder'] ?? false,
      permissions: map['permissions'] ?? false,
      order: order is List
          ? [for (final name in order) ?byName[name]]
          : const [],
      widths: widths is Map
          ? {
              for (final entry in widths.entries)
                if ((byName[entry.key], entry.value) case (
                  final column?,
                  final num width,
                ))
                  column: width.toDouble(),
            }
          : const {},
      shellColumns: shellColumns is List
          ? {
              for (final name in shellColumns)
                if (byName[name] case final column? when column.shell) column,
            }
          : const {},
    );
  }

  @override
  List<Object?> get props => [
    name,
    size,
    type,
    dateModified,
    dateCreated,
    attributes,
    dateAccessed,
    extension,
    path,
    tags,
    dimensions,
    duration,
    itemCount,
    parentFolder,
    permissions,
    order,
    widths,
    shellColumns,
  ];
}

// Define field visibility options for list view mode
class ListFieldVisibility {
  final bool size;
  final bool dateModified;
  final bool dateCreated;
  final bool dateAccessed;
  final bool type;
  final bool extension;
  final bool tags;
  final bool dimensions;
  final bool duration;
  final bool itemCount;
  final bool path;

  const ListFieldVisibility({
    this.size = true,
    this.dateModified = false,
    this.dateCreated = false,
    this.dateAccessed = false,
    this.type = false,
    this.extension = false,
    this.tags = true,
    this.dimensions = false,
    this.duration = false,
    this.itemCount = false,
    this.path = false,
  });

  ListFieldVisibility copyWith({
    bool? size,
    bool? dateModified,
    bool? dateCreated,
    bool? dateAccessed,
    bool? type,
    bool? extension,
    bool? tags,
    bool? dimensions,
    bool? duration,
    bool? itemCount,
    bool? path,
  }) {
    return ListFieldVisibility(
      size: size ?? this.size,
      dateModified: dateModified ?? this.dateModified,
      dateCreated: dateCreated ?? this.dateCreated,
      dateAccessed: dateAccessed ?? this.dateAccessed,
      type: type ?? this.type,
      extension: extension ?? this.extension,
      tags: tags ?? this.tags,
      dimensions: dimensions ?? this.dimensions,
      duration: duration ?? this.duration,
      itemCount: itemCount ?? this.itemCount,
      path: path ?? this.path,
    );
  }

  Map<String, bool> toMap() {
    return {
      'size': size,
      'dateModified': dateModified,
      'dateCreated': dateCreated,
      'dateAccessed': dateAccessed,
      'type': type,
      'extension': extension,
      'tags': tags,
      'dimensions': dimensions,
      'duration': duration,
      'itemCount': itemCount,
      'path': path,
    };
  }

  factory ListFieldVisibility.fromMap(Map<String, dynamic> map) {
    return ListFieldVisibility(
      size: map['size'] ?? true,
      dateModified: map['dateModified'] ?? false,
      dateCreated: map['dateCreated'] ?? false,
      dateAccessed: map['dateAccessed'] ?? false,
      type: map['type'] ?? false,
      extension: map['extension'] ?? false,
      tags: map['tags'] ?? true,
      dimensions: map['dimensions'] ?? false,
      duration: map['duration'] ?? false,
      itemCount: map['itemCount'] ?? false,
      path: map['path'] ?? false,
    );
  }
}

// Define media types for search
enum MediaType { image, video, audio, document }

class FolderListState extends Equatable {
  static const Object _unset = Object();
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final Directory currentPath;
  final List<FileSystemEntity> folders;
  final List<FileSystemEntity> files;
  final List<FileSystemEntity> searchResults;
  final bool hasMoreSearchResults;
  final bool isLoadingMoreSearchResults;
  final int? searchResultsTotal;
  final List<FileSystemEntity> filteredFiles;
  final Map<String, List<String>> fileTags;
  final Set<String> allUniqueTags; // All unique tags found in the directory
  final String? currentFilter; // Current filter for file types
  final String? currentSearchTag; // The tag being searched for
  final String? currentSearchQuery; // Text query for file search
  final ViewMode viewMode;
  final SortOption sortOption;
  final int gridZoomLevel;
  final Map<String, FileStat>
  fileStatsCache; // Cache for file stats to improve performance
  final MediaType? currentMediaSearch; // For media searches
  final bool isSearchByName; // Flag for search by name operations
  final bool isSearchByMedia; // Flag for search by media type
  final bool isGlobalSearch; // Flag for global tag searches
  final bool searchRecursive; // Flag for recursive search operations
  final int
  clipboardRevision; // Revision counter to trigger rebuild on clipboard changes
  final List<String> retryableElevatedDeletePaths;

  FolderListState(
    String initialPath, {
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    List<FileSystemEntity>? folders,
    List<FileSystemEntity>? files,
    List<FileSystemEntity>? searchResults,
    this.hasMoreSearchResults = false,
    this.isLoadingMoreSearchResults = false,
    this.searchResultsTotal,
    List<FileSystemEntity>? filteredFiles,
    Map<String, List<String>>? fileTags,
    Set<String>? allUniqueTags,
    this.currentFilter,
    this.currentSearchTag,
    this.currentSearchQuery,
    this.viewMode = ViewMode.list,
    this.sortOption = SortOption.dateDesc,
    this.gridZoomLevel = 3, // Default level for grid view
    Map<String, FileStat>? fileStatsCache,
    this.currentMediaSearch,
    this.isSearchByName = false,
    this.isSearchByMedia = false,
    this.isGlobalSearch = false,
    this.searchRecursive = false,
    this.clipboardRevision = 0,
    this.retryableElevatedDeletePaths = const [],
  }) : currentPath = Directory(initialPath),
       folders = folders ?? [],
       files = files ?? [],
       searchResults = searchResults ?? [],
       filteredFiles = filteredFiles ?? [],
       fileTags = fileTags ?? {},
       allUniqueTags = allUniqueTags ?? {},
       fileStatsCache = fileStatsCache ?? {};

  // Helper getters
  List<String> get allTags => allUniqueTags.toList();
  bool get isSearchActive =>
      currentSearchTag != null || currentSearchQuery != null;

  // Helper method to get tags for a specific file
  List<String> getTagsForFile(String filePath) {
    return fileTags[filePath] ?? [];
  }

  // Create a new state with updated fields
  FolderListState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    Object? error = _unset,
    Directory? currentPath,
    List<FileSystemEntity>? folders,
    List<FileSystemEntity>? files,
    List<FileSystemEntity>? searchResults,
    bool? hasMoreSearchResults,
    bool? isLoadingMoreSearchResults,
    Object? searchResultsTotal = _unset,
    List<FileSystemEntity>? filteredFiles,
    Map<String, List<String>>? fileTags,
    Set<String>? allUniqueTags,
    Object? currentFilter = _unset,
    Object? currentSearchTag = _unset,
    Object? currentSearchQuery = _unset,
    ViewMode? viewMode,
    SortOption? sortOption,
    int? gridZoomLevel,
    Map<String, FileStat>? fileStatsCache,
    Object? currentMediaSearch = _unset,
    bool? isSearchByName,
    bool? isSearchByMedia,
    bool? isGlobalSearch,
    bool? searchRecursive,
    int? clipboardRevision,
    List<String>? retryableElevatedDeletePaths,
  }) {
    return FolderListState(
      currentPath?.path ?? this.currentPath.path,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error == _unset ? this.error : error as String?,
      folders: folders ?? this.folders,
      files: files ?? this.files,
      searchResults: searchResults ?? this.searchResults,
      hasMoreSearchResults: hasMoreSearchResults ?? this.hasMoreSearchResults,
      isLoadingMoreSearchResults:
          isLoadingMoreSearchResults ?? this.isLoadingMoreSearchResults,
      searchResultsTotal: searchResultsTotal == _unset
          ? this.searchResultsTotal
          : searchResultsTotal as int?,
      filteredFiles: filteredFiles ?? this.filteredFiles,
      fileTags: fileTags ?? this.fileTags,
      allUniqueTags: allUniqueTags ?? this.allUniqueTags,
      currentFilter: currentFilter == _unset
          ? this.currentFilter
          : currentFilter as String?,
      currentSearchTag: currentSearchTag == _unset
          ? this.currentSearchTag
          : currentSearchTag as String?,
      currentSearchQuery: currentSearchQuery == _unset
          ? this.currentSearchQuery
          : currentSearchQuery as String?,
      viewMode: viewMode ?? this.viewMode,
      sortOption: sortOption ?? this.sortOption,
      gridZoomLevel: gridZoomLevel ?? this.gridZoomLevel,
      fileStatsCache: fileStatsCache ?? this.fileStatsCache,
      currentMediaSearch: currentMediaSearch == _unset
          ? this.currentMediaSearch
          : currentMediaSearch as MediaType?,
      isSearchByName: isSearchByName ?? this.isSearchByName,
      isSearchByMedia: isSearchByMedia ?? this.isSearchByMedia,
      isGlobalSearch: isGlobalSearch ?? this.isGlobalSearch,
      searchRecursive: searchRecursive ?? this.searchRecursive,
      clipboardRevision: clipboardRevision ?? this.clipboardRevision,
      retryableElevatedDeletePaths:
          retryableElevatedDeletePaths ?? this.retryableElevatedDeletePaths,
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isRefreshing,
    error,
    currentPath.path,
    folders,
    files,
    searchResults,
    hasMoreSearchResults,
    isLoadingMoreSearchResults,
    searchResultsTotal,
    filteredFiles,
    fileTags,
    allUniqueTags,
    currentFilter,
    currentSearchTag,
    currentSearchQuery,
    viewMode,
    sortOption,
    gridZoomLevel,
    currentMediaSearch,
    isSearchByName,
    isSearchByMedia,
    isGlobalSearch,
    searchRecursive,
    retryableElevatedDeletePaths,
    // NOTE: clipboardRevision is intentionally excluded from props
    // to prevent full rebuild when clipboard changes (copy/cut operations)
    // Only items affected by cut should show visual feedback
  ];
}
