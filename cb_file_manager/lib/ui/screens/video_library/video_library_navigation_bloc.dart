import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/helpers/core/filesystem_sorter.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/services/video_library_cache_service.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';

import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

/// A specialized FileNavigationBloc for video libraries.
/// Uses VideoLibraryService instead of Directory.list() to load files,
/// while keeping the same state shape and API as the parent bloc.
///
/// Usage:
/// ```dart
/// final bloc = VideoLibraryNavigationBloc(libraryId: 42);
/// bloc.loadLibrary(); // triggers loading
/// ```
class VideoLibraryNavigationBloc
    extends Bloc<FileNavigationEvent, FileNavigationState> {
  final VideoLibraryService _libraryService = VideoLibraryService();
  final VideoLibraryCacheService _cacheService =
      VideoLibraryCacheService.instance;
  final int libraryId;

  /// In-memory cache: libraryId → cached files list (mirrors disk cache).
  /// Used for fast in-session reuse. Disk cache is the source of truth.
  static final Map<int, List<File>> _memoryCache = {};

  VideoLibraryNavigationBloc({
    required this.libraryId,
    FileNavigationState? initialState,
  }) : super(initialState ??
            FileNavigationState.initial('#video-library/$libraryId')) {
    on<FileNavigationLoad>(_onLoad);
    on<FileNavigationRefresh>(_onRefresh);
    on<FileNavigationSetViewMode>(_onSetViewMode);
    on<FileNavigationSetGridZoom>(_onSetGridZoom);
    on<FileNavigationSetSortOption>(_onSetSortOption);
    on<FileNavigationFilter>(_onFilter);
    on<FileNavigationSearchByFileName>(_onSearchByFileName);
    on<FileNavigationClearSearchAndFilters>(_onClearSearchAndFilters);
  }

  /// Trigger loading of the library's files.
  void loadLibrary() {
    add(FileNavigationLoad(
      '#video-library/$libraryId',
      isVirtualPath: true,
    ));
  }

  /// Refresh the library's files — forces disk re-scan and clears disk cache.
  void refreshLibrary() {
    // Invalidate disk cache so we get fresh data
    _cacheService.invalidateLibrary(libraryId);
    add(FileNavigationRefresh(
      '#video-library/$libraryId',
      isVirtualPath: true,
    ));
  }

  /// Invalidate both memory and disk cache for a specific library.
  static Future<void> invalidateCache(int libraryId) async {
    _memoryCache.remove(libraryId);
    await VideoLibraryCacheService.instance.invalidateLibrary(libraryId);
  }

  /// Clear all cached library files from memory and disk.
  static Future<void> clearAllCache() async {
    _memoryCache.clear();
    await VideoLibraryCacheService.instance.clearAll();
  }

  // ── Event handlers ──────────────────────────────────────────────

  Future<void> _onLoad(
    FileNavigationLoad event,
    Emitter<FileNavigationState> emit,
  ) async {
    final totalSw = Stopwatch()..start();
    AppLogger.perf('Starting video library load libraryId=$libraryId');

    // 1. Check in-memory cache first (fastest)
    final memCached = _memoryCache[libraryId];
    if (memCached != null && memCached.isNotEmpty) {
      AppLogger.perf('Video library memory cache hit for libraryId=$libraryId');
      final sorted = await FileSystemSorter.sortFiles(
        memCached,
        state.sortOption,
      );
      emit(state.copyWith(
        isLoading: false,
        files: sorted,
        folders: const [],
        currentPath: Directory(event.path),
        error: null,
      ));
      _prefetchThumbnails(sorted, event.path);
      return;
    }

    // 2. Check disk cache
    final diskCached = await _cacheService.loadCachedFiles(libraryId);
    if (diskCached != null && diskCached.isNotEmpty) {
      AppLogger.perf('Video library disk cache hit for libraryId=$libraryId');
      final files = diskCached.map((p) => File(p)).toList();
      _memoryCache[libraryId] = files; // promote to memory
      final sorted = await FileSystemSorter.sortFiles(
        files,
        state.sortOption,
      );
      emit(state.copyWith(
        isLoading: false,
        files: sorted,
        folders: const [],
        currentPath: Directory(event.path),
        error: null,
      ));
      _prefetchThumbnails(sorted, event.path);
      return;
    }

    // 3. Cache miss — scan from disk
    emit(state.copyWith(
      isLoading: true,
      currentPath: Directory(event.path),
    ));

    try {
      // Stream files so UI updates progressively as each directory is scanned.
      //
      // Optimization: skip per-batch stat/cache rebuild for progressive
      // emissions. Cache miss → full scan only triggers stat for sort options
      // that need it (date, size, attributes). All other sort options use
      // fast in-memory sort that doesn't need filesystem I/O.
      final List<File> files = [];
      int nextEmitAt = 50; // first batch at 50 for quick initial display

      await for (final path in _libraryService.streamLibraryFiles(libraryId)) {
        if (isClosed) return;

        files.add(File(path));

        // Emit progressive state at adaptive intervals.
        // Use _needsStatsForSortOption to avoid expensive stat() calls on
        // every batch emission when the sort option doesn't require file stats.
        if (files.length >= nextEmitAt) {
          final needsStats = _needsStatsForSortOption(state.sortOption);
          final sorted = needsStats
              ? await FileSystemSorter.sortFiles(
                  List<File>.from(files),
                  state.sortOption,
                )
              : _fastSortFiles(files, state.sortOption);

          emit(state.copyWith(
            isLoading: true,
            files: sorted,
            folders: const [],
          ));

          // Increase batch size as list grows: 50 → 200 → 500 → 1000
          if (files.length < 200) {
            nextEmitAt = files.length + 150;
          } else if (files.length < 1000) {
            nextEmitAt = files.length + 500;
          } else {
            nextEmitAt = files.length + 1000;
          }
        }
      }

      // Final full sort (always needs stats for correctness)
      final sortedFiles = await FileSystemSorter.sortFiles(
        files,
        state.sortOption,
      );

      if (isClosed) return;
      emit(state.copyWith(
        isLoading: false,
        files: sortedFiles,
        folders: const [],
        error: null,
      ));

      // Save to memory + disk cache for future re-opens
      _memoryCache[libraryId] = files;
      await _cacheService.saveFiles(
          libraryId, files.map((f) => f.path).toList());

      // Persist file count to config table so VideoHubScreen can show
      // cached counts instantly without a second filesystem scan.
      _libraryService.updateCachedLibraryVideoCount(libraryId, files.length);

      AppLogger.perf('UI ready total=${totalSw.elapsedMilliseconds}ms');

      // Thumbnail prefetch — same pattern as regular folders
      _prefetchThumbnails(sortedFiles, event.path);

      AppLogger.perf('Complete total=${totalSw.elapsedMilliseconds}ms');
    } catch (e) {
      AppLogger.error('VideoLibraryNavigationBloc._onLoad failed', error: e);
      emit(state.copyWith(
        isLoading: false,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onRefresh(
    FileNavigationRefresh event,
    Emitter<FileNavigationState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));

    try {
      final List<File> files = [];
      int nextEmitAt = 50;

      await for (final path in _libraryService.streamLibraryFiles(libraryId)) {
        if (isClosed) return;

        files.add(File(path));

        // Emit progressive state at adaptive intervals.
        // Skip expensive stat() calls when sort option doesn't need them.
        if (files.length >= nextEmitAt) {
          final needsStats = _needsStatsForSortOption(state.sortOption);
          final sorted = needsStats
              ? await FileSystemSorter.sortFiles(
                  List<File>.from(files),
                  state.sortOption,
                )
              : _fastSortFiles(files, state.sortOption);

          emit(state.copyWith(
            isLoading: true,
            files: sorted,
            folders: const [],
          ));

          // Increase batch size as list grows
          if (files.length < 200) {
            nextEmitAt = files.length + 150;
          } else if (files.length < 1000) {
            nextEmitAt = files.length + 500;
          } else {
            nextEmitAt = files.length + 1000;
          }
        }
      }

      final sortedFiles = await FileSystemSorter.sortFiles(
        files,
        state.sortOption,
      );

      if (isClosed) return;
      emit(state.copyWith(
        isLoading: false,
        files: sortedFiles,
        folders: const [],
        error: null,
      ));

      // Save refreshed results and count for future fast loads.
      _memoryCache[libraryId] = files;
      await _cacheService.saveFiles(
          libraryId, files.map((f) => f.path).toList());
      _libraryService.updateCachedLibraryVideoCount(libraryId, files.length);

      // Thumbnail prefetch
      if (event.forceRegenerateThumbnails) {
        VideoThumbnailHelper.regenerateThumbnailsForDirectory(event.path);
      } else {
        _prefetchThumbnails(sortedFiles, event.path);
      }
    } catch (e) {
      AppLogger.error('VideoLibraryNavigationBloc._onRefresh failed', error: e);
      emit(state.copyWith(
        isLoading: false,
        error: e.toString(),
      ));
    }
  }

  void _onSetViewMode(
    FileNavigationSetViewMode event,
    Emitter<FileNavigationState> emit,
  ) {
    emit(state.copyWith(viewMode: event.viewMode));
  }

  void _onSetGridZoom(
    FileNavigationSetGridZoom event,
    Emitter<FileNavigationState> emit,
  ) {
    emit(state.copyWith(gridZoomLevel: event.zoomLevel));
  }

  void _onSetSortOption(
    FileNavigationSetSortOption event,
    Emitter<FileNavigationState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));

    final sortedFiles = await FileSystemSorter.sortFiles(
      state.files.cast<File>(),
      event.sortOption,
    );

    emit(state.copyWith(
      isLoading: false,
      files: sortedFiles,
      sortOption: event.sortOption,
    ));
  }

  void _onFilter(
    FileNavigationFilter event,
    Emitter<FileNavigationState> emit,
  ) {
    // For video libraries, we don't support filtering by type since
    // all files are already videos. Just emit current state.
    emit(state.copyWith(currentFilter: event.fileType));
  }

  void _onSearchByFileName(
    FileNavigationSearchByFileName event,
    Emitter<FileNavigationState> emit,
  ) {
    final query = event.query.toLowerCase();
    final results =
        state.files.where((f) => f.path.toLowerCase().contains(query)).toList();
    emit(state.copyWith(
      searchResults: results,
      currentSearchQuery: event.query,
      isSearchByName: true,
      searchRecursive: event.recursive,
    ));
  }

  void _onClearSearchAndFilters(
    FileNavigationClearSearchAndFilters event,
    Emitter<FileNavigationState> emit,
  ) {
    emit(state.copyWith(
      searchResults: const [],
      currentSearchQuery: null,
      currentFilter: null,
      isSearchByName: false,
    ));
  }

  void _prefetchThumbnails(List<FileSystemEntity> files, String dirPath) {
    final videoPaths = files
        .whereType<File>()
        .where((f) => FileTypeUtils.isVideoFile(f.path))
        .map((f) => f.path)
        .toList();
    if (videoPaths.isEmpty) return;
    VideoThumbnailHelper.setCurrentDirectory(dirPath);
    // Prefer a smaller, UI-friendly preload strategy on first load.
    // Generating thumbnails for every item immediately can stall the event loop
    // on large libraries, so we only prioritize the visible range and let the
    // queue expand gradually.
    VideoThumbnailHelper.optimizedBatchPreload(
      videoPaths,
      maxConcurrent: 2,
      visibleCount: 10,
    );
  }

  /// Returns true if the given sort option requires calling stat() on files.
  /// Used to skip expensive per-batch filesystem I/O when not needed.
  static bool _needsStatsForSortOption(SortOption option) {
    switch (option) {
      case SortOption.dateAsc:
      case SortOption.dateDesc:
      case SortOption.sizeAsc:
      case SortOption.sizeDesc:
      case SortOption.dateCreatedAsc:
      case SortOption.dateCreatedDesc:
      case SortOption.attributesAsc:
      case SortOption.attributesDesc:
        return true;
      default:
        return false;
    }
  }

  /// Fast in-memory file sort that doesn't need filesystem I/O.
  /// Only handles sort options that don't require stat() — for all others,
  /// use FileSystemSorter.sortFiles() which is async and builds a stats cache.
  static List<File> _fastSortFiles(List<File> files, SortOption sortOption) {
    final sorted = List<File>.from(files);
    switch (sortOption) {
      case SortOption.nameAsc:
        sorted.sort(
            (a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
        break;
      case SortOption.nameDesc:
        sorted.sort(
            (a, b) => path.basename(b.path).compareTo(path.basename(a.path)));
        break;
      case SortOption.typeAsc:
        sorted.sort(
            (a, b) => path.extension(a.path).compareTo(path.extension(b.path)));
        break;
      case SortOption.typeDesc:
        sorted.sort(
            (a, b) => path.extension(b.path).compareTo(path.extension(a.path)));
        break;
      case SortOption.extensionAsc:
        sorted.sort(
            (a, b) => path.extension(a.path).compareTo(path.extension(b.path)));
        break;
      case SortOption.extensionDesc:
        sorted.sort(
            (a, b) => path.extension(b.path).compareTo(path.extension(a.path)));
        break;
      default:
        // Fallback: sort by name ascending for unknown/default options
        sorted.sort(
            (a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
        break;
    }
    return sorted;
  }
}
