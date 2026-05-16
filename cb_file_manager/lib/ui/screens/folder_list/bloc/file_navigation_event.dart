import 'package:equatable/equatable.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

/// Events for file navigation — browse, sort, filter, search, view mode
abstract class FileNavigationEvent extends Equatable {
  const FileNavigationEvent();

  @override
  List<Object?> get props => [];
}

// ─── Initialization ────────────────────────────────────────────────

class FileNavigationInit extends FileNavigationEvent {
  const FileNavigationInit();
}

class FileNavigationLoad extends FileNavigationEvent {
  final String path;

  /// If true, the path is a virtual path (e.g. '#video-library/{id}') and
  /// the parent bloc should skip processing so a specialized child bloc
  /// (e.g. VideoLibraryNavigationBloc) can handle it.
  final bool isVirtualPath;

  const FileNavigationLoad(this.path, {this.isVirtualPath = false});

  @override
  List<Object> get props => [path, isVirtualPath];
}

class FileNavigationRefresh extends FileNavigationEvent {
  final String path;
  final bool forceRegenerateThumbnails;

  /// If true, the path is a virtual path and the parent bloc should skip
  /// processing so a specialized child bloc can handle it.
  final bool isVirtualPath;

  const FileNavigationRefresh(this.path,
      {this.forceRegenerateThumbnails = false, this.isVirtualPath = false});

  @override
  List<Object> get props => [path, forceRegenerateThumbnails, isVirtualPath];
}

class FileNavigationReloadCurrentFolder extends FileNavigationEvent {
  const FileNavigationReloadCurrentFolder();
}

class FileNavigationLoadDrives extends FileNavigationEvent {
  const FileNavigationLoadDrives();
}

// ─── Filtering ─────────────────────────────────────────────────────

class FileNavigationFilter extends FileNavigationEvent {
  final String? fileType; // 'image', 'video', 'audio', 'document', null = clear

  const FileNavigationFilter(this.fileType);

  @override
  List<Object?> get props => [fileType];
}

// ─── Sorting ────────────────────────────────────────────────────────

class FileNavigationSetSortOption extends FileNavigationEvent {
  final SortOption sortOption;

  const FileNavigationSetSortOption(this.sortOption);

  @override
  List<Object> get props => [sortOption];
}

// ─── View Mode ─────────────────────────────────────────────────────

class FileNavigationSetViewMode extends FileNavigationEvent {
  final ViewMode viewMode;

  const FileNavigationSetViewMode(this.viewMode);

  @override
  List<Object> get props => [viewMode];
}

class FileNavigationSetGridZoom extends FileNavigationEvent {
  final int zoomLevel;

  const FileNavigationSetGridZoom(this.zoomLevel);

  @override
  List<Object> get props => [zoomLevel];
}

// ─── Search ────────────────────────────────────────────────────────

class FileNavigationSearchByFileName extends FileNavigationEvent {
  final String query;
  final bool recursive;
  final bool useRegex;

  const FileNavigationSearchByFileName(
    this.query, {
    this.recursive = false,
    this.useRegex = false,
  });

  @override
  List<Object> get props => [query, recursive, useRegex];
}

class FileNavigationClearSearchAndFilters extends FileNavigationEvent {
  const FileNavigationClearSearchAndFilters();
}

class FileNavigationLoadMoreSearchResults extends FileNavigationEvent {
  const FileNavigationLoadMoreSearchResults();
}

class FileNavigationRemovePaths extends FileNavigationEvent {
  final Set<String> paths;

  const FileNavigationRemovePaths(this.paths);

  @override
  List<Object> get props => [paths];
}
