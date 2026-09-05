import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

import 'tag_search_event.dart';

/// State for tag operations and tag-based search.
class TagSearchState extends Equatable {
  final Map<String, List<String>> fileTags;
  final Set<String> allUniqueTags;
  final List<String> searchResultPaths;
  final String? currentSearchTag;
  final bool isGlobalSearch;
  final int? searchResultsTotal;
  final bool isLoading;
  final String? error;

  const TagSearchState({
    this.fileTags = const {},
    this.allUniqueTags = const {},
    this.searchResultPaths = const [],
    this.currentSearchTag,
    this.isGlobalSearch = false,
    this.searchResultsTotal,
    this.isLoading = false,
    this.error,
  });

  TagSearchState copyWith({
    Map<String, List<String>>? fileTags,
    Set<String>? allUniqueTags,
    List<String>? searchResultPaths,
    Object? currentSearchTag = _unset,
    bool? isGlobalSearch,
    Object? searchResultsTotal = _unset,
    bool? isLoading,
    Object? error = _unset,
  }) {
    return TagSearchState(
      fileTags: fileTags ?? this.fileTags,
      allUniqueTags: allUniqueTags ?? this.allUniqueTags,
      searchResultPaths: searchResultPaths ?? this.searchResultPaths,
      currentSearchTag: currentSearchTag is String
          ? currentSearchTag
          : (currentSearchTag == _unset ? this.currentSearchTag : null),
      isGlobalSearch: isGlobalSearch ?? this.isGlobalSearch,
      searchResultsTotal: searchResultsTotal is int
          ? searchResultsTotal
          : (searchResultsTotal == _unset ? this.searchResultsTotal : null),
      isLoading: isLoading ?? this.isLoading,
      error: error is String ? error : (error == _unset ? this.error : null),
    );
  }

  static const _unset = Object();

  List<String> getTags(String filePath) => fileTags[filePath] ?? [];

  @override
  List<Object?> get props => [
    fileTags,
    allUniqueTags,
    searchResultPaths,
    currentSearchTag,
    isGlobalSearch,
    searchResultsTotal,
    isLoading,
    error,
  ];
}

class TagSearchBloc extends Bloc<TagSearchEvent, TagSearchState> {
  final FileNavigationBloc navigationBloc;

  TagSearchBloc({required this.navigationBloc})
    : super(const TagSearchState()) {
    on<TagSearchLoadTagsForFile>(_onLoadTagsForFile);
    on<TagSearchLoadTagsForFiles>(_onLoadTagsForFiles);
    on<TagSearchLoadAllTags>(_onLoadAllTags);
    on<TagSearchAddTagToFile>(_onAddTagToFile);
    on<TagSearchRemoveTagFromFile>(_onRemoveTagFromFile);
    on<TagSearchDeleteTagGlobally>(_onDeleteTagGlobally);
    on<TagSearchBatchAddTag>(_onBatchAddTag);
    on<TagSearchByTag>(_onSearchByTag);
    on<TagSearchByTagGlobally>(_onSearchByTagGlobally);
    on<TagSearchByMultipleTags>(_onSearchByMultipleTags);
    on<TagSearchByMultipleTagsGlobally>(_onSearchByMultipleTagsGlobally);
    on<TagSearchSetResults>(_onSetResults);
    on<TagSearchClearResults>(_onClearResults);

    // Subscribe to TagManager changes to keep state in sync
    TagManager.onTagChanged.listen(_onTagChanged);
  }

  void _onTagChanged(String filePath) {
    if (filePath == "global:tag_deleted") {
      add(TagSearchLoadAllTags(navigationBloc.state.currentPath.path));
    } else {
      add(TagSearchLoadTagsForFile(filePath));
    }
  }

  // ─── Load tags ─────────────────────────────────────────────────

  Future<void> _onLoadTagsForFile(
    TagSearchLoadTagsForFile event,
    Emitter<TagSearchState> emit,
  ) async {
    try {
      final tags = await TagManager.getTags(event.filePath);
      final updatedTags = Map<String, List<String>>.from(state.fileTags);
      if (tags.isEmpty) {
        updatedTags.remove(event.filePath);
      } else {
        updatedTags[event.filePath] = tags;
      }
      emit(state.copyWith(fileTags: updatedTags, error: null));
    } catch (e) {
      AppLogger.warning('Error loading tags for file: $e');
    }
  }

  Future<void> _onLoadTagsForFiles(
    TagSearchLoadTagsForFiles event,
    Emitter<TagSearchState> emit,
  ) async {
    if (event.filePaths.isEmpty) return;
    try {
      emit(state.copyWith(isLoading: true));
      final fileTags = await TagManager.getTagsForFiles(event.filePaths);
      emit(state.copyWith(fileTags: fileTags, isLoading: false, error: null));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: 'Error loading tags: $e'));
    }
  }

  Future<void> _onLoadAllTags(
    TagSearchLoadAllTags event,
    Emitter<TagSearchState> emit,
  ) async {
    try {
      final tags = await TagManager.getAllUniqueTags(event.directory);
      emit(state.copyWith(allUniqueTags: tags, error: null));
    } catch (e) {
      AppLogger.warning('Error loading all tags: $e');
    }
  }

  // ─── Single tag ops ────────────────────────────────────────────

  Future<void> _onAddTagToFile(
    TagSearchAddTagToFile event,
    Emitter<TagSearchState> emit,
  ) async {
    try {
      await TagManager.addTag(event.filePath, event.tag);
      final tags = await TagManager.getTags(event.filePath);
      final updatedTags = Map<String, List<String>>.from(state.fileTags);
      updatedTags[event.filePath] = tags;
      emit(state.copyWith(fileTags: updatedTags, error: null));
    } catch (e) {
      emit(state.copyWith(error: 'Error adding tag: ${e.toString()}'));
    }
  }

  Future<void> _onRemoveTagFromFile(
    TagSearchRemoveTagFromFile event,
    Emitter<TagSearchState> emit,
  ) async {
    try {
      await TagManager.removeTag(event.filePath, event.tag);
      final updatedTags = Map<String, List<String>>.from(state.fileTags);
      if (updatedTags.containsKey(event.filePath)) {
        updatedTags[event.filePath] = List.from(updatedTags[event.filePath]!)
          ..remove(event.tag);
        if (updatedTags[event.filePath]!.isEmpty) {
          updatedTags.remove(event.filePath);
        }
      }
      emit(state.copyWith(fileTags: updatedTags, error: null));
    } catch (e) {
      emit(state.copyWith(error: 'Error removing tag: ${e.toString()}'));
    }
  }

  Future<void> _onDeleteTagGlobally(
    TagSearchDeleteTagGlobally event,
    Emitter<TagSearchState> emit,
  ) async {
    try {
      await TagManager.deleteTagGlobally(event.tag);
      TagManager.clearCache();
      TagManager.instance.notifyTagChanged("global:tag_deleted");
      add(TagSearchLoadAllTags(event.currentDirectory));
    } catch (e) {
      AppLogger.warning('Error deleting tag globally: $e');
    }
  }

  Future<void> _onBatchAddTag(
    TagSearchBatchAddTag event,
    Emitter<TagSearchState> emit,
  ) async {
    try {
      for (final path in event.filePaths) {
        await TagManager.addTag(path, event.tag);
      }
      final updatedTags = Map<String, List<String>>.from(state.fileTags);
      for (final path in event.filePaths) {
        final tags = await TagManager.getTags(path);
        updatedTags[path] = tags;
      }
      emit(state.copyWith(fileTags: updatedTags, error: null));
    } catch (e) {
      emit(state.copyWith(error: 'Error batch adding tag: ${e.toString()}'));
    }
  }

  // ─── Tag search ───────────────────────────────────────────────

  Future<void> _onSearchByTag(
    TagSearchByTag event,
    Emitter<TagSearchState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      TagManager.clearCache();
      final results = await TagManager.findFilesByTag(
        event.currentDirectory,
        event.tag,
      );
      final paths = results.map((e) => e.path).toList();
      emit(
        state.copyWith(
          isLoading: false,
          searchResultPaths: paths,
          currentSearchTag: event.tag,
          isGlobalSearch: false,
          error: null,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Tag search error: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> _onSearchByTagGlobally(
    TagSearchByTagGlobally event,
    Emitter<TagSearchState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, searchResultPaths: []));
    try {
      TagManager.clearCache();
      final results = await TagManager.findFilesByTagGlobally(event.tag);
      final validPaths = <String>[];
      for (final entity in results) {
        if (entity is File && entity.existsSync()) {
          validPaths.add(entity.path);
        }
      }
      emit(
        state.copyWith(
          isLoading: false,
          searchResultPaths: validPaths,
          currentSearchTag: event.tag,
          isGlobalSearch: true,
          searchResultsTotal: validPaths.length,
          error: null,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Global tag search error: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> _onSearchByMultipleTags(
    TagSearchByMultipleTags event,
    Emitter<TagSearchState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      TagManager.clearCache();
      if (event.tags.isEmpty) return;

      var results = await TagManager.findFilesByTag(
        event.currentDirectory,
        event.tags.first,
      );

      for (int i = 1; i < event.tags.length; i++) {
        final filtered = <FileSystemEntity>[];
        for (final entity in results) {
          if (entity is File) {
            final tags = await TagManager.getTags(entity.path);
            if (tags.contains(event.tags[i])) {
              filtered.add(entity);
            }
          }
        }
        results = filtered;
      }

      final paths = results.map((e) => e.path).toList();
      emit(
        state.copyWith(
          isLoading: false,
          searchResultPaths: paths,
          currentSearchTag: event.tags.join(', '),
          isGlobalSearch: false,
          error: null,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Multi-tag search error: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> _onSearchByMultipleTagsGlobally(
    TagSearchByMultipleTagsGlobally event,
    Emitter<TagSearchState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, searchResultPaths: []));
    try {
      TagManager.clearCache();
      if (event.tags.isEmpty) return;

      var results = await TagManager.findFilesByTagGlobally(event.tags.first);

      for (int i = 1; i < event.tags.length; i++) {
        final filtered = <FileSystemEntity>[];
        for (final entity in results) {
          if (entity is File && entity.existsSync()) {
            final tags = await TagManager.getTags(entity.path);
            if (tags.contains(event.tags[i])) {
              filtered.add(entity);
            }
          }
        }
        results = filtered;
      }

      final validPaths = results
          .whereType<File>()
          .where((f) => f.existsSync())
          .map((f) => f.path)
          .toList();

      emit(
        state.copyWith(
          isLoading: false,
          searchResultPaths: validPaths,
          currentSearchTag: event.tags.join(', '),
          isGlobalSearch: true,
          searchResultsTotal: validPaths.length,
          error: null,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Global multi-tag search error: ${e.toString()}',
        ),
      );
    }
  }

  void _onSetResults(TagSearchSetResults event, Emitter<TagSearchState> emit) {
    emit(
      state.copyWith(
        searchResultPaths: event.resultPaths,
        currentSearchTag: event.tagName,
        isGlobalSearch: event.isGlobal,
        searchResultsTotal: event.total,
        error: null,
      ),
    );
  }

  void _onClearResults(
    TagSearchClearResults event,
    Emitter<TagSearchState> emit,
  ) {
    emit(
      state.copyWith(
        searchResultPaths: const [],
        currentSearchTag: null,
        isGlobalSearch: false,
        searchResultsTotal: null,
        error: null,
      ),
    );
  }
}
