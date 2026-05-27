import 'dart:io';

import 'package:equatable/equatable.dart';

// Define view modes
enum ViewMode { list, grid, details, gridPreview }

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
  attributesDesc // Added file attributes descending
}

// Define column visibility options for details view
class ColumnVisibility {
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
  });

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
    );
  }

  // Convert to map for storage
  Map<String, bool> toMap() {
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
    };
  }

  // Create from map
  factory ColumnVisibility.fromMap(Map<String, dynamic> map) {
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
    );
  }
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
  })  : currentPath = Directory(initialPath),
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
        // NOTE: clipboardRevision is intentionally excluded from props
        // to prevent full rebuild when clipboard changes (copy/cut operations)
        // Only items affected by cut should show visual feedback
      ];
}
