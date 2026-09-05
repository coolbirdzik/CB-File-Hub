import 'package:equatable/equatable.dart';
import 'dart:io';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

/// Immutable state for FileNavigationBloc.
class FileNavigationState extends Equatable {
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
  final String? currentFilter;
  final String? currentSearchQuery;
  final ViewMode viewMode;
  final SortOption sortOption;
  final int gridZoomLevel;
  final Map<String, FileStat> fileStatsCache;
  final bool isSearchByName;
  final bool searchRecursive;

  const FileNavigationState({
    required this.currentPath,
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.folders = const [],
    this.files = const [],
    this.searchResults = const [],
    this.hasMoreSearchResults = false,
    this.isLoadingMoreSearchResults = false,
    this.searchResultsTotal,
    this.filteredFiles = const [],
    this.currentFilter,
    this.currentSearchQuery,
    this.viewMode = ViewMode.list,
    this.sortOption = SortOption.dateDesc,
    this.gridZoomLevel = 3,
    this.fileStatsCache = const {},
    this.isSearchByName = false,
    this.searchRecursive = false,
  });

  factory FileNavigationState.initial(String path) =>
      FileNavigationState(currentPath: Directory(path), isLoading: true);

  bool get isSearchActive => currentSearchQuery != null;

  FileNavigationState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    Object? error,
    Directory? currentPath,
    List<FileSystemEntity>? folders,
    List<FileSystemEntity>? files,
    List<FileSystemEntity>? searchResults,
    bool? hasMoreSearchResults,
    bool? isLoadingMoreSearchResults,
    Object? searchResultsTotal,
    List<FileSystemEntity>? filteredFiles,
    Object? currentFilter,
    Object? currentSearchQuery,
    ViewMode? viewMode,
    SortOption? sortOption,
    int? gridZoomLevel,
    Map<String, FileStat>? fileStatsCache,
    bool? isSearchByName,
    bool? searchRecursive,
  }) {
    return FileNavigationState(
      currentPath: currentPath ?? this.currentPath,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error is String ? error : (error == _unset ? this.error : null),
      folders: folders ?? this.folders,
      files: files ?? this.files,
      searchResults: searchResults ?? this.searchResults,
      hasMoreSearchResults: hasMoreSearchResults ?? this.hasMoreSearchResults,
      isLoadingMoreSearchResults:
          isLoadingMoreSearchResults ?? this.isLoadingMoreSearchResults,
      searchResultsTotal: searchResultsTotal is int
          ? searchResultsTotal
          : (searchResultsTotal == _unset ? this.searchResultsTotal : null),
      filteredFiles: filteredFiles ?? this.filteredFiles,
      currentFilter: currentFilter is String
          ? currentFilter
          : (currentFilter == _unset ? this.currentFilter : null),
      currentSearchQuery: currentSearchQuery is String
          ? currentSearchQuery
          : (currentSearchQuery == _unset ? this.currentSearchQuery : null),
      viewMode: viewMode ?? this.viewMode,
      sortOption: sortOption ?? this.sortOption,
      gridZoomLevel: gridZoomLevel ?? this.gridZoomLevel,
      fileStatsCache: fileStatsCache ?? this.fileStatsCache,
      isSearchByName: isSearchByName ?? this.isSearchByName,
      searchRecursive: searchRecursive ?? this.searchRecursive,
    );
  }

  static const _unset = Object();

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
    currentFilter,
    currentSearchQuery,
    viewMode,
    sortOption,
    gridZoomLevel,
    isSearchByName,
    searchRecursive,
  ];
}
