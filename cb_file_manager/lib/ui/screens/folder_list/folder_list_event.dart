import 'package:equatable/equatable.dart';
import 'dart:io'; // Add import for FileSystemEntity
import 'folder_list_state.dart'; // Import for ViewMode and SortOption enums

abstract class FolderListEvent extends Equatable {
  const FolderListEvent();

  @override
  List<Object?> get props => [];
}

class FolderListInit extends FolderListEvent {
  const FolderListInit();
}

class FolderListLoad extends FolderListEvent {
  final String path;

  const FolderListLoad(this.path);

  @override
  List<Object> get props => [path];
}

class FolderListFilter extends FolderListEvent {
  final String? fileType;

  const FolderListFilter(this.fileType);

  @override
  List<Object?> get props => [fileType];
}

class AddTagToFile extends FolderListEvent {
  final String filePath;
  final String tag;

  const AddTagToFile(this.filePath, this.tag);

  @override
  List<Object> get props => [filePath, tag];
}

class RemoveTagFromFile extends FolderListEvent {
  final String filePath;
  final String tag;

  const RemoveTagFromFile(this.filePath, this.tag);

  @override
  List<Object> get props => [filePath, tag];
}

class SearchByTag extends FolderListEvent {
  final String tag;

  const SearchByTag(this.tag);

  @override
  List<Object> get props => [tag];
}

class SearchByTagGlobally extends FolderListEvent {
  final String tag;

  const SearchByTagGlobally(this.tag);

  @override
  List<Object> get props => [tag];
}

// New event for searching by multiple tags in current directory
class SearchByMultipleTags extends FolderListEvent {
  final List<String> tags;

  const SearchByMultipleTags(this.tags);

  @override
  List<Object> get props => [tags];
}

// New event for searching by multiple tags globally
class SearchByMultipleTagsGlobally extends FolderListEvent {
  final List<String> tags;

  const SearchByMultipleTagsGlobally(this.tags);

  @override
  List<Object> get props => [tags];
}

class SearchByFileName extends FolderListEvent {
  final String query;
  final bool recursive;
  final bool useRegex;

  const SearchByFileName(
    this.query, {
    this.recursive = false,
    this.useRegex = false,
  });

  @override
  List<Object> get props => [query, recursive, useRegex];
}

class SearchMediaFiles extends FolderListEvent {
  final MediaSearchType mediaType;
  final bool recursive;

  const SearchMediaFiles(this.mediaType, {this.recursive = false});

  @override
  List<Object> get props => [mediaType, recursive];
}

class LoadTagsFromFile extends FolderListEvent {
  final String filePath;

  const LoadTagsFromFile(this.filePath);

  @override
  List<Object> get props => [filePath];
}

class LoadAllTags extends FolderListEvent {
  final String directory;

  const LoadAllTags(this.directory);

  @override
  List<Object> get props => [directory];
}

class SetViewMode extends FolderListEvent {
  final ViewMode viewMode;

  const SetViewMode(this.viewMode);

  @override
  List<Object> get props => [viewMode];
}

class SetSortOption extends FolderListEvent {
  final SortOption sortOption;
  final bool persist;
  final String? folderPath;

  const SetSortOption(this.sortOption, {this.persist = true, this.folderPath});

  @override
  List<Object?> get props => [sortOption, persist, folderPath];
}

class SetGridZoom extends FolderListEvent {
  final int zoomLevel;

  const SetGridZoom(this.zoomLevel);

  @override
  List<Object> get props => [zoomLevel];
}

class FolderListDeleteFiles extends FolderListEvent {
  final List<String> filePaths;

  const FolderListDeleteFiles(this.filePaths);

  @override
  List<Object> get props => [filePaths];
}

class FolderListDeleteItems extends FolderListEvent {
  final List<String> filePaths;
  final List<String> folderPaths;
  final bool permanent;

  const FolderListDeleteItems({
    this.filePaths = const [],
    this.folderPaths = const [],
    this.permanent = false,
  });

  @override
  List<Object> get props => [filePaths, folderPaths, permanent];
}

class FolderListRetryDeleteAsAdministrator extends FolderListEvent {
  final List<String> failedPaths;

  const FolderListRetryDeleteAsAdministrator(this.failedPaths);

  @override
  List<Object> get props => [failedPaths];
}

class FolderListBatchAddTag extends FolderListEvent {
  final List<String> filePaths;
  final String tag;

  const FolderListBatchAddTag(this.filePaths, this.tag);

  @override
  List<Object> get props => [filePaths, tag];
}

class FolderListDeleteTagGlobally extends FolderListEvent {
  final String tag;

  const FolderListDeleteTagGlobally(this.tag);

  @override
  List<Object> get props => [tag];
}

class ClearSearchAndFilters extends FolderListEvent {
  const ClearSearchAndFilters();
}

/// Set tag search results
class SetTagSearchResults extends FolderListEvent {
  final List<FileSystemEntity> results;
  final String tagName;

  const SetTagSearchResults(this.results, this.tagName);

  @override
  List<Object?> get props => [results, tagName];
}

// Add a specific event for refreshing with thumbnail regeneration
class FolderListRefresh extends FolderListEvent {
  final String path;
  final bool forceRegenerateThumbnails;

  const FolderListRefresh(this.path, {this.forceRegenerateThumbnails = false});

  @override
  List<Object> get props => [path, forceRegenerateThumbnails];
}

// Add an event to reload the current folder without changing path
class FolderListReloadCurrentFolder extends FolderListEvent {
  const FolderListReloadCurrentFolder();

  @override
  List<Object?> get props => [];
}

// File operation events
class CopyFile extends FolderListEvent {
  final FileSystemEntity entity;

  const CopyFile(this.entity);

  @override
  List<Object> get props => [entity];
}

class CopyFiles extends FolderListEvent {
  final List<FileSystemEntity> entities;

  const CopyFiles(this.entities);

  @override
  List<Object> get props => [entities];
}

class CutFile extends FolderListEvent {
  final FileSystemEntity entity;

  const CutFile(this.entity);

  @override
  List<Object> get props => [entity];
}

class CutFiles extends FolderListEvent {
  final List<FileSystemEntity> entities;

  const CutFiles(this.entities);

  @override
  List<Object> get props => [entities];
}

class PasteFile extends FolderListEvent {
  final String destinationPath;

  const PasteFile(this.destinationPath);

  @override
  List<Object> get props => [destinationPath];
}

class RenameFileOrFolder extends FolderListEvent {
  final FileSystemEntity entity;
  final String newName;

  const RenameFileOrFolder(this.entity, this.newName);

  @override
  List<Object> get props => [entity, newName];
}

// Enum to represent media types for search
enum MediaSearchType { images, videos, audio, all }

class LoadMoreSearchResults extends FolderListEvent {
  const LoadMoreSearchResults();
}

// Add additional tag search results to existing results
class AddTagSearchResults extends FolderListEvent {
  final List<FileSystemEntity> results;

  const AddTagSearchResults(this.results);

  @override
  List<Object?> get props => [results];
}

// Event for lazy loading drive information
class FolderListLoadDrives extends FolderListEvent {
  const FolderListLoadDrives();

  @override
  List<Object?> get props => [];
}
