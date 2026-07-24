import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as pathlib;
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/helpers/core/filesystem_sorter.dart';
import 'package:cb_file_manager/helpers/core/text_utils.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/services/directory_watcher_service.dart';
import 'package:cb_file_manager/services/permission_state_service.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';

import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/services/directory_listing_cache_service.dart';

import 'file_navigation_event.dart';
import 'file_navigation_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

class FileNavigationBloc
    extends Bloc<FileNavigationEvent, FileNavigationState> {
  StreamSubscription<String>? _directoryWatcherSubscription;
  final DirectoryWatcherService _directoryWatcher =
      DirectoryWatcherService.instance;
  int _activeSortRequestId = 0;

  /// Paths with an in-flight disk scan (load or refresh). Used to dedupe the
  /// multiple folder-load events that tab activation, path sync and the tab
  /// refocus pipeline can enqueue for the same folder within a few frames.
  final Set<String> _inFlightScans = <String>{};

  static const int _searchResultsPageSize = 200;
  List<FileSystemEntity> _pendingSearchResults = [];

  FileNavigationBloc() : super(FileNavigationState.initial('/')) {
    // ── Lifecycle ───────────────────────────────────────────────
    on<FileNavigationInit>(_onInit);
    on<FileNavigationLoad>(_onLoad);
    on<FileNavigationRefresh>(_onRefresh);
    on<FileNavigationReloadCurrentFolder>(_onReloadCurrentFolder);
    on<FileNavigationLoadDrives>(_onLoadDrives);

    // ── Filtering & Sorting ────────────────────────────────────
    on<FileNavigationFilter>(_onFilter);
    on<FileNavigationSetSortOption>(_onSetSortOption);

    // ── View Mode ──────────────────────────────────────────────
    on<FileNavigationSetViewMode>(_onSetViewMode);
    on<FileNavigationSetGridZoom>(_onSetGridZoom);

    // ── Search ──────────────────────────────────────────────────
    on<FileNavigationSearchByFileName>(_onSearchByFileName);
    on<FileNavigationClearSearchAndFilters>(_onClearSearchAndFilters);
    on<FileNavigationLoadMoreSearchResults>(_onLoadMoreSearchResults);
    on<FileNavigationRemovePaths>(_onRemovePaths);

    // ── Directory watching ─────────────────────────────────────
    _directoryWatcherSubscription = _directoryWatcher.onDirectoryRefresh.listen(
      (path) {
        // Invalidate the directory listing cache so the next navigation
        // to this folder triggers a fresh scan instead of returning stale data.
        DirectoryListingCacheService.instance.invalidate(path);
        if (path == state.currentPath.path) {
          add(FileNavigationRefresh(path));
        }
      },
    );
  }

  void _onRemovePaths(
    FileNavigationRemovePaths event,
    Emitter<FileNavigationState> emit,
  ) {
    if (event.paths.isEmpty) return;
    final removed = event.paths;
    final searchBefore = state.searchResults.length;
    _pendingSearchResults = _pendingSearchResults
        .where((entity) => !removed.contains(entity.path))
        .toList();
    final filteredSearchResults = state.searchResults
        .where((entity) => !removed.contains(entity.path))
        .toList();
    final removedFromSearch = searchBefore - filteredSearchResults.length;
    final currentTotal = state.searchResultsTotal;

    emit(state.copyWith(
      folders: state.folders
          .where((entity) => !removed.contains(entity.path))
          .toList(),
      files: state.files
          .where((entity) => !removed.contains(entity.path))
          .toList(),
      filteredFiles: state.filteredFiles
          .where((entity) => !removed.contains(entity.path))
          .toList(),
      searchResults: filteredSearchResults,
      searchResultsTotal: currentTotal == null
          ? null
          : math.max(0, currentTotal - removedFromSearch),
    ));
  }

  @override
  Future<void> close() {
    _directoryWatcherSubscription?.cancel();
    _directoryWatcher.stopWatching();
    return super.close();
  }

  /// Pause directory watching for this bloc.
  ///
  /// Used by the tab activity manager when the bloc's tab transitions to
  /// inactive. Cancels the local refresh subscription so background fs
  /// events don't trigger needless work; the global singleton watcher
  /// only watches the currently focused tab's path so this primarily
  /// serves as a defensive cleanup.
  void pauseWatching() {
    _directoryWatcherSubscription?.cancel();
    _directoryWatcherSubscription = null;
  }

  /// Resume directory watching for this bloc after [pauseWatching].
  ///
  /// Idempotent: if the subscription is already active, returns immediately.
  /// The actual filesystem watch is re-armed on the next navigation event
  /// (the tab refocus pipeline triggers a refresh which calls
  /// [_directoryWatcher.startWatching]).
  void resumeWatching() {
    if (_directoryWatcherSubscription != null) return;
    _directoryWatcherSubscription = _directoryWatcher.onDirectoryRefresh.listen(
      (path) {
        DirectoryListingCacheService.instance.invalidate(path);
        if (path == state.currentPath.path) {
          add(FileNavigationRefresh(path));
        }
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Lifecycle handlers
  // ─────────────────────────────────────────────────────────────

  void _onInit(
    FileNavigationInit event,
    Emitter<FileNavigationState> emit,
  ) {
    emit(state.copyWith(isLoading: true));
  }

  Future<void> _onLoad(
    FileNavigationLoad event,
    Emitter<FileNavigationState> emit,
  ) async {
    final totalSw = Stopwatch()..start();
    AppLogger.perf('Starting folder load path=${event.path}');

    // Skip virtual paths — handled by specialized blocs (e.g. VideoLibraryNavigationBloc)
    if (event.isVirtualPath || event.path.startsWith('#')) {
      AppLogger.perf(
          'Virtual path skipped total=${totalSw.elapsedMilliseconds}ms');
      return;
    }

    // Dedupe concurrent loads/refreshes for the same folder. Tab activation,
    // path sync and the refocus pipeline can each enqueue a load for this path
    // within a few frames; without this guard bloc runs every one as a separate
    // full stat-scan in parallel, which is the main cause of the file list
    // staying empty for a long time on large folders.
    if (_inFlightScans.contains(event.path)) {
      AppLogger.perf(
          'Load skipped — scan already in flight path=${event.path}');
      return;
    }
    _inFlightScans.add(event.path);
    try {
      await _performLoad(event, emit, totalSw);
    } finally {
      _inFlightScans.remove(event.path);
    }
  }

  Future<void> _performLoad(
    FileNavigationLoad event,
    Emitter<FileNavigationState> emit,
    Stopwatch totalSw,
  ) async {
    emit(state.copyWith(
      isLoading: true,
      isRefreshing: false,
      error: null,
      currentPath: Directory(event.path),
      folders: const [],
      files: const [],
      filteredFiles: const [],
      searchResults: const [],
      hasMoreSearchResults: false,
      isLoadingMoreSearchResults: false,
      searchResultsTotal: null,
      currentFilter: null,
      currentSearchQuery: null,
      isSearchByName: false,
      searchRecursive: false,
      fileStatsCache: const {},
    ));

    // Gate: pause thumbnail generation while we scan/sort the file list.
    // Thumbnails will start AFTER the listing is emitted to the UI.
    ThumbnailLoader.setListingReady(false);

    if (event.path.isEmpty && Platform.isWindows) {
      emit(state.copyWith(isLoading: false, folders: [], files: []));
      ThumbnailLoader.setListingReady(true);
      AppLogger.perf('Empty path total=${totalSw.elapsedMilliseconds}ms');
      return;
    }

    if (_isDrivesPath(event.path)) {
      emit(state.copyWith(isLoading: false, folders: [], files: []));
      ThumbnailLoader.setListingReady(true);
      AppLogger.perf('Drives path total=${totalSw.elapsedMilliseconds}ms');
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    try {
      final directory = Directory(event.path);
      if (!await directory.exists()) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Directory does not exist: ${event.path}',
        ));
        return;
      }

      // Permission check
      final permService = PermissionStateService.instance;
      if (!await permService.hasStorageOrPhotosPermission()) {
        final granted = await permService.requestStorageOrPhotos();
        if (!granted) {
          emit(state.copyWith(
            isLoading: false,
            error: 'Storage permission required',
          ));
          return;
        }
      }

      // Sort option for this folder
      final folderSortManager = FolderSortManager();
      final folderSortOption = await _safeCall(
        () => folderSortManager.getFolderSortOption(event.path),
      );
      final sortOption = folderSortOption ?? state.sortOption;

      // ── Cache check ────────────────────────────────────────────────────────────
      // Before scanning the disk, check if we have a cached listing for this
      // folder. Cache hit = instant return, no OS I/O. This mirrors how Windows
      // Explorer re-uses its in-memory folder enumeration cache on navigate-back.
      final cacheResult =
          DirectoryListingCacheService.instance.getListing(event.path);
      if (cacheResult != null) {
        final sortNeedsStats = _sortOptionNeedsStats(sortOption);
        if (sortNeedsStats && cacheResult.stats.isEmpty) {
          AppLogger.perf(
              'Dir listing CACHE BYPASS "${event.path}" — sort needs stats');
        } else {
          final sortedFolders = await FileSystemSorter.sortDirectories(
            cacheResult.folders,
            sortOption,
            fileStatsCache: cacheResult.stats,
          );
          final sortedFiles = await FileSystemSorter.sortFiles(
            cacheResult.files,
            sortOption,
            fileStatsCache: cacheResult.stats,
          );
          emit(state.copyWith(
            isLoading: false,
            folders: sortedFolders,
            files: sortedFiles,
            fileStatsCache: Map.from(cacheResult.stats),
            sortOption: sortOption,
          ));
          AppLogger.perf(
              'Dir listing CACHE HIT "${event.path}" (${sortedFiles.length} files)');
          ThumbnailLoader.updateDisplayIndexMap(
              sortedFiles.map((f) => f.path).toList());
          ThumbnailLoader.clearFileExistsCache();
          ThumbnailLoader.setListingReady(true);
          await _directoryWatcher.startWatching(event.path);
          AppLogger.perf(
              'Complete (cached) total=${totalSw.elapsedMilliseconds}ms');
          return;
        }
      }
      AppLogger.perf('Dir listing CACHE MISS "${event.path}" — scanning disk');

      // ── Offload scan + stat + sort to background isolate ────────────────────
      // With 5000+ files, stat + sort on the main isolate causes UI jank.
      // compute() runs the work in a separate Dart isolate (background thread)
      // so the Flutter UI thread stays completely free.
      final scanResult = await compute(
        _scanDirectoryInIsolate,
        _ScanArgs(event.path, sortOption.name),
      );

      // Reconstruct typed objects from the isolate's plain path lists.
      final folders = scanResult.folderPaths.map(Directory.new).toList();
      final files = scanResult.filePaths.map(File.new).toList();
      final sortedFolders = folders; // already sorted in isolate
      final sortedFiles = files; // already sorted in isolate

      // Rebuild FileStat cache from raw stat rows for downstream consumers
      // (e.g. sort-on-demand, file details panel). We build it on the main
      // isolate from the already-fetched raw rows — no extra I/O needed.
      final statsCache = <String, FileStat>{};
      // FileStat cannot be constructed directly; fetch only for small folders
      // to populate the cache (large folders skip to avoid blocking).
      if (scanResult.statRows.length <= 500) {
        final allPaths = [...scanResult.folderPaths, ...scanResult.filePaths];
        await Future.wait(allPaths.map((p) async {
          try {
            statsCache[p] = await FileStat.stat(p);
          } catch (_) {}
        }));
      }

      emit(state.copyWith(
        isLoading: false,
        folders: sortedFolders,
        files: sortedFiles,
        fileStatsCache: Map.from(statsCache),
        sortOption: sortOption,
      ));

      // Store in directory listing cache so navigating back is instant.
      DirectoryListingCacheService.instance.storeListing(
        path: event.path,
        files: files,
        folders: folders,
        stats: statsCache,
      );

      // Update thumbnail loader priority map so loading respects display (sort) order,
      // not file-system listing order. This fixes the issue where thumbnails were
      // loaded for files at the bottom of the sort order first.
      ThumbnailLoader.updateDisplayIndexMap(
          sortedFiles.map((f) => f.path).toList());
      // Clear file-exists cache so stale entries from previous folders don't
      // persist to the new directory.
      ThumbnailLoader.clearFileExistsCache();
      // Open the gate: file list is ready, thumbnails can start generating.
      ThumbnailLoader.setListingReady(true);

      AppLogger.perf('UI ready total=${totalSw.elapsedMilliseconds}ms');

      // Proactive thumbnail generation
      _prefetchThumbnails(sortedFiles, event.path);

      // Start directory watching
      await _directoryWatcher.startWatching(event.path);

      AppLogger.perf('Complete total=${totalSw.elapsedMilliseconds}ms');
    } catch (e) {
      ThumbnailLoader.setListingReady(true);
      _emitPermissionError(emit, e, event.path);
    }
  }

  Future<void> _onRefresh(
    FileNavigationRefresh event,
    Emitter<FileNavigationState> emit,
  ) async {
    // Skip virtual paths — handled by specialized blocs
    if (event.isVirtualPath || _isDrivesPath(event.path)) {
      emit(state.copyWith(isRefreshing: false));
      return;
    }

    // Dedupe against an in-flight load/refresh for the same folder. The tab
    // refocus pipeline fires a refresh at the same time tab activation fires a
    // load; without this guard both run a full stat-scan in parallel and
    // contend for disk I/O, delaying the listing. The in-flight scan already
    // produces fresh data, so skipping this refresh is safe.
    if (_inFlightScans.contains(event.path)) {
      AppLogger.perf(
          'Refresh skipped — scan already in flight path=${event.path}');
      return;
    }
    _inFlightScans.add(event.path);
    try {
      await _performRefresh(event, emit);
    } finally {
      _inFlightScans.remove(event.path);
    }
  }

  Future<void> _performRefresh(
    FileNavigationRefresh event,
    Emitter<FileNavigationState> emit,
  ) async {
    // Use isRefreshing instead of isLoading so the existing file list
    // is not cleared/rebuilt — only the status bar indicator changes.
    emit(state.copyWith(isRefreshing: true));

    // Invalidate cache so refresh always hits disk (user explicitly wants fresh data).
    DirectoryListingCacheService.instance.invalidate(event.path);

    try {
      final directory = Directory(event.path);
      if (!await directory.exists()) {
        emit(state.copyWith(
          isRefreshing: false,
          error: 'Directory does not exist',
        ));
        return;
      }

      final folderSortManager = FolderSortManager();
      final folderSortOption = await _safeCall(
        () => folderSortManager.getFolderSortOption(event.path),
      );
      final sortOption = folderSortOption ?? state.sortOption;

      // Offload scan + stat + sort to background isolate (same as _onLoad).
      final scanResult = await compute(
        _scanDirectoryInIsolate,
        _ScanArgs(event.path, sortOption.name),
      );

      final sortedFolders = scanResult.folderPaths.map(Directory.new).toList();
      final sortedFiles = scanResult.filePaths.map(File.new).toList();

      emit(state.copyWith(
        isRefreshing: false,
        folders: sortedFolders,
        files: sortedFiles,
        currentPath: Directory(event.path),
        sortOption: sortOption,
        error: null,
      ));

      // Re-cache after refresh so navigating back is still instant.
      DirectoryListingCacheService.instance.storeListing(
        path: event.path,
        files: sortedFiles,
        folders: sortedFolders,
        stats: const {},
      );

      // Update thumbnail priority map so loading respects display (sort) order.
      ThumbnailLoader.updateDisplayIndexMap(
          sortedFiles.map((f) => f.path).toList());

      // Thumbnail prefetch
      if (event.forceRegenerateThumbnails) {
        VideoThumbnailHelper.regenerateThumbnailsForDirectory(event.path);
      } else {
        _prefetchThumbnails(sortedFiles, event.path);
      }
    } catch (e) {
      _emitPermissionError(emit, e, event.path);
    }
  }

  void _onReloadCurrentFolder(
    FileNavigationReloadCurrentFolder event,
    Emitter<FileNavigationState> emit,
  ) {
    if (state.currentPath.path.isNotEmpty) {
      add(FileNavigationRefresh(state.currentPath.path));
    }
  }

  void _onLoadDrives(
    FileNavigationLoadDrives event,
    Emitter<FileNavigationState> emit,
  ) {
    // Drives are loaded by DriveView's FutureBuilder
    // This event exists for consistent BLoC state management
  }

  // ─────────────────────────────────────────────────────────────
  // Filter & Sort handlers
  // ─────────────────────────────────────────────────────────────

  void _onFilter(
    FileNavigationFilter event,
    Emitter<FileNavigationState> emit,
  ) {
    if (event.fileType == null) {
      emit(state.copyWith(currentFilter: null, filteredFiles: []));
      return;
    }
    emit(state.copyWith(isLoading: true, currentFilter: event.fileType));
    final filtered = _filterFilesByType(state.files, event.fileType!);
    emit(state.copyWith(isLoading: false, filteredFiles: filtered));
  }

  Future<void> _onSetSortOption(
    FileNavigationSetSortOption event,
    Emitter<FileNavigationState> emit,
  ) async {
    final requestId = ++_activeSortRequestId;
    bool isStale() => isClosed || requestId != _activeSortRequestId;

    emit(state.copyWith(isLoading: true));

    try {
      if (event.persist) {
        final folderSortManager = FolderSortManager();
        await _safeCall(() => folderSortManager.saveFolderSortOption(
              event.folderPath ?? state.currentPath.path,
              event.sortOption,
            ));
      }

      if (isStale()) return;

      final targetPath = state.currentPath.path;
      Map<String, FileStat> statsCache = {};

      Future<void> cacheStats(List<FileSystemEntity> entities) async {
        for (final e in entities) {
          if (!statsCache.containsKey(e.path)) {
            try {
              statsCache[e.path] = await e.stat();
            } catch (_) {}
          }
        }
      }

      await Future.wait([
        cacheStats(state.folders),
        cacheStats(state.files),
        cacheStats(state.filteredFiles),
        cacheStats(state.searchResults),
      ]);
      if (isStale()) return;

      final cmp = _buildCompareFunction(event.sortOption, statsCache);

      List<FileSystemEntity> sortedFolders = List.from(state.folders)
        ..sort(cmp);
      List<FileSystemEntity> sortedFiles = List.from(state.files)..sort(cmp);
      List<FileSystemEntity> sortedFiltered = List.from(state.filteredFiles)
        ..sort(cmp);
      List<FileSystemEntity> sortedSearch = List.from(state.searchResults)
        ..sort(cmp);

      // Rebase if newer content arrived while sorting
      final hasNewerContent = state.currentPath.path == targetPath &&
          (state.folders.isNotEmpty || state.files.isNotEmpty) &&
          sortedFolders.isEmpty &&
          sortedFiles.isEmpty;
      if (hasNewerContent) {
        sortedFolders = List.from(state.folders)..sort(cmp);
        sortedFiles = List.from(state.files)..sort(cmp);
        sortedFiltered = List.from(state.filteredFiles)..sort(cmp);
        sortedSearch = List.from(state.searchResults)..sort(cmp);
        await Future.wait([
          cacheStats(sortedFolders),
          cacheStats(sortedFiles),
          cacheStats(sortedFiltered),
          cacheStats(sortedSearch),
        ]);
        if (isStale()) return;
        sortedFolders.sort(cmp);
        sortedFiles.sort(cmp);
        sortedFiltered.sort(cmp);
        sortedSearch.sort(cmp);
      }

      emit(state.copyWith(
        isLoading: false,
        sortOption: event.sortOption,
        folders: sortedFolders,
        files: sortedFiles,
        filteredFiles: sortedFiltered,
        searchResults: sortedSearch,
        fileStatsCache: statsCache,
      ));

      // Re-sort changes display order — update thumbnail priority map accordingly.
      ThumbnailLoader.updateDisplayIndexMap(
          sortedFiles.map((f) => f.path).toList());
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Error sorting: ${e.toString()}',
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────
  // View Mode handlers
  // ─────────────────────────────────────────────────────────────

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

  // ─────────────────────────────────────────────────────────────
  // Search handlers
  // ─────────────────────────────────────────────────────────────

  Future<void> _onSearchByFileName(
    FileNavigationSearchByFileName event,
    Emitter<FileNavigationState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));

    try {
      final query = event.query.toLowerCase();
      RegExp? regex;
      if (event.useRegex) {
        try {
          regex = RegExp(event.query, caseSensitive: false, unicode: true);
        } on FormatException catch (e) {
          emit(state.copyWith(
            isLoading: false,
            error: 'Invalid regex: ${e.message}',
          ));
          return;
        }
      }

      final List<FileSystemEntity> results = [];

      if (event.recursive) {
        await _recursiveSearch(
          Directory(state.currentPath.path),
          query,
          results,
          regex,
        );
      } else {
        for (final file in state.files) {
          if (_matchesQuery(pathlib.basename(file.path), query, regex)) {
            results.add(file);
          }
        }
        for (final folder in state.folders) {
          if (_matchesQuery(pathlib.basename(folder.path), query, regex)) {
            results.add(folder);
          }
        }
      }

      final grouped = <FileSystemEntity>[
        ...results.whereType<Directory>(),
        ...results.where((e) => e is! Directory && e is! File),
        ...results.whereType<File>(),
      ];

      emit(state.copyWith(
        isLoading: false,
        searchResults: grouped,
        currentSearchQuery: event.query,
        searchRecursive: event.recursive,
        isSearchByName: true,
        error: grouped.isEmpty ? 'No files found matching "$query"' : null,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Search error: ${e.toString()}',
      ));
    }
  }

  void _onClearSearchAndFilters(
    FileNavigationClearSearchAndFilters event,
    Emitter<FileNavigationState> emit,
  ) {
    _pendingSearchResults = [];
    emit(state.copyWith(
      currentSearchQuery: null,
      currentFilter: null,
      searchResults: [],
      filteredFiles: [],
      isSearchByName: false,
      searchRecursive: false,
      hasMoreSearchResults: false,
      isLoadingMoreSearchResults: false,
      searchResultsTotal: null,
      error: null,
    ));
  }

  void _onLoadMoreSearchResults(
    FileNavigationLoadMoreSearchResults event,
    Emitter<FileNavigationState> emit,
  ) {
    if (_pendingSearchResults.isEmpty) {
      emit(state.copyWith(
        hasMoreSearchResults: false,
        isLoadingMoreSearchResults: false,
      ));
      return;
    }
    if (state.isLoadingMoreSearchResults) return;

    emit(state.copyWith(isLoadingMoreSearchResults: true));

    final nextCount = _pendingSearchResults.length > _searchResultsPageSize
        ? _searchResultsPageSize
        : _pendingSearchResults.length;
    final nextChunk = _pendingSearchResults.take(nextCount).toList();
    _pendingSearchResults = _pendingSearchResults.skip(nextCount).toList();

    final currentResults = List<FileSystemEntity>.from(state.searchResults);
    for (final entity in nextChunk) {
      if (!currentResults.any((e) => e.path == entity.path)) {
        currentResults.add(entity);
      }
    }

    emit(state.copyWith(
      searchResults: currentResults,
      hasMoreSearchResults: _pendingSearchResults.isNotEmpty,
      isLoadingMoreSearchResults: false,
    ));
  }

  // ─────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────

  bool _isDrivesPath(String path) {
    return path.isEmpty ||
        path == '#drives' ||
        path.startsWith('#drives/') ||
        path == '#network' ||
        path == '#trash';
  }

  bool _sortOptionNeedsStats(SortOption sortOption) {
    switch (sortOption) {
      case SortOption.dateAsc:
      case SortOption.dateDesc:
      case SortOption.sizeAsc:
      case SortOption.sizeDesc:
      case SortOption.dateCreatedAsc:
      case SortOption.dateCreatedDesc:
      case SortOption.attributesAsc:
      case SortOption.attributesDesc:
        return true;
      case SortOption.nameAsc:
      case SortOption.nameDesc:
      case SortOption.typeAsc:
      case SortOption.typeDesc:
      case SortOption.extensionAsc:
      case SortOption.extensionDesc:
        return false;
    }
  }

  bool _matchesQuery(String name, String query, RegExp? regex) {
    return regex != null
        ? regex.hasMatch(name)
        : TextUtils.matchesVietnamese(name, query);
  }

  List<FileSystemEntity> _filterFilesByType(
    List<FileSystemEntity> files,
    String fileType,
  ) {
    return files.where((file) {
      if (file is File) {
        switch (fileType) {
          case 'image':
            return FileTypeUtils.isImageFile(file.path);
          case 'video':
            return FileTypeUtils.isVideoFile(file.path);
          case 'audio':
            return FileTypeUtils.isAudioFile(file.path);
          case 'document':
            return FileTypeUtils.isDocumentFile(file.path) ||
                FileTypeUtils.isSpreadsheetFile(file.path) ||
                FileTypeUtils.isPresentationFile(file.path);
          default:
            return true;
        }
      }
      return false;
    }).toList();
  }

  int Function(FileSystemEntity, FileSystemEntity) _buildCompareFunction(
    SortOption option,
    Map<String, FileStat> statsCache,
  ) {
    DateTime modifiedFor(FileSystemEntity entity) =>
        statsCache[entity.path]?.modified ??
        DateTime.fromMillisecondsSinceEpoch(0);

    DateTime changedFor(FileSystemEntity entity) =>
        statsCache[entity.path]?.changed ??
        DateTime.fromMillisecondsSinceEpoch(0);

    int sizeFor(FileSystemEntity entity) => statsCache[entity.path]?.size ?? -1;

    String attributesFor(FileSystemEntity entity) {
      final stat = statsCache[entity.path];
      if (stat == null) {
        return '';
      }
      return '${stat.mode},${stat.type}';
    }

    switch (option) {
      case SortOption.nameAsc:
        return (a, b) => pathlib
            .basename(a.path)
            .toLowerCase()
            .compareTo(pathlib.basename(b.path).toLowerCase());
      case SortOption.nameDesc:
        return (a, b) => pathlib
            .basename(b.path)
            .toLowerCase()
            .compareTo(pathlib.basename(a.path).toLowerCase());
      case SortOption.dateAsc:
        return (a, b) => modifiedFor(a).compareTo(modifiedFor(b));
      case SortOption.dateDesc:
        return (a, b) => modifiedFor(b).compareTo(modifiedFor(a));
      case SortOption.sizeAsc:
        return (a, b) => sizeFor(a).compareTo(sizeFor(b));
      case SortOption.sizeDesc:
        return (a, b) => sizeFor(b).compareTo(sizeFor(a));
      case SortOption.typeAsc:
      case SortOption.extensionAsc:
        return (a, b) => pathlib
            .extension(a.path)
            .toLowerCase()
            .compareTo(pathlib.extension(b.path).toLowerCase());
      case SortOption.typeDesc:
      case SortOption.extensionDesc:
        return (a, b) => pathlib
            .extension(b.path)
            .toLowerCase()
            .compareTo(pathlib.extension(a.path).toLowerCase());
      case SortOption.dateCreatedAsc:
        return (a, b) => changedFor(a).compareTo(changedFor(b));
      case SortOption.dateCreatedDesc:
        return (a, b) => changedFor(b).compareTo(changedFor(a));
      case SortOption.attributesAsc:
        return (a, b) => attributesFor(a).compareTo(attributesFor(b));
      case SortOption.attributesDesc:
        return (a, b) => attributesFor(b).compareTo(attributesFor(a));
    }
  }

  Future<void> _recursiveSearch(
    Directory dir,
    String query,
    List<FileSystemEntity> results,
    RegExp? regex,
  ) async {
    try {
      await for (final entity
          in dir.list(recursive: false, followLinks: false)) {
        try {
          final name = pathlib.basename(entity.path);
          if (_matchesQuery(name, query, regex)) {
            results.add(entity);
          }
          if (entity is Directory) {
            await _recursiveSearch(entity, query, results, regex);
          }
        } catch (_) {
          // Skip inaccessible entities
        }
      }
    } catch (_) {
      // Skip inaccessible directories
    }
  }

  /// Prefetches thumbnails for video files in the given list.
  /// [dirPath] can be a real directory path or a virtual path like
  /// '#video-library/{id}'. For virtual paths, it uses the virtual path
  /// as the directory identifier.
  void _prefetchThumbnails(List<FileSystemEntity> files, String dirPath) {
    final videoPaths = files
        .whereType<File>()
        .where((f) => FileTypeUtils.isVideoFile(f.path))
        .map((f) => f.path)
        .toList();
    if (videoPaths.isEmpty) return;
    VideoThumbnailHelper.setCurrentDirectory(dirPath);
    // Use optimizedBatchPreload instead of proactiveGenerateAll to avoid
    // blocking the event loop with per-item getFromCache() file I/O on large
    // directories. optimizedBatchPreload stages the queue in priority groups
    // and does not perform synchronous file existence checks inline.
    VideoThumbnailHelper.optimizedBatchPreload(
      videoPaths,
      maxConcurrent: 2,
      visibleCount: 10,
    );
  }

  void _emitPermissionError(
    Emitter<FileNavigationState> emit,
    Object e,
    String path,
  ) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('permission denied') || msg.contains('access denied')) {
      emit(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: 'Access denied. Try running as administrator.',
        folders: [],
        files: [],
      ));
    } else {
      emit(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: e.toString(),
        folders: [],
        files: [],
      ));
    }
  }

  Future<T?> _safeCall<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }
}

// ── Isolate worker ───────────────────────────────────────────────────────────
// All scan + stat + sort work is done off the main isolate so the UI thread
// stays free during large directory listings (5000+ files).

/// Compact stat fields extracted from FileStat for isolate transfer.
/// FileStat is not sendable across isolates, but its primitive fields are.
/// Layout: [modified_ms, changed_ms, size, mode, type_index]
typedef _StatRow = List<dynamic>;

/// Result returned from [_scanDirectoryInIsolate].
class _ScanResult {
  final List<String> folderPaths;
  final List<String> filePaths;

  /// Maps file/folder path → [modified_ms, changed_ms, size, mode, type_index]
  final Map<String, _StatRow> statRows;

  const _ScanResult({
    required this.folderPaths,
    required this.filePaths,
    required this.statRows,
  });
}

class _ScanArgs {
  final String path;
  final String sortOption; // SortOption.name string

  const _ScanArgs(this.path, this.sortOption);
}

/// Top-level function — runs in a separate isolate.
/// Scans [args.path], stats all entities in parallel chunks, sorts them
/// by [args.sortOption] name, and returns already-sorted path lists + raw stats.
/// Doing all this off the main isolate prevents UI jank on large directories.
Future<_ScanResult> _scanDirectoryInIsolate(_ScanArgs args) async {
  const statChunkSize = 64;

  final dir = Directory(args.path);
  final folderPaths = <String>[];
  final filePaths = <String>[];

  await for (final entity in dir.list(followLinks: false)) {
    final p = entity.path;
    final name = p.contains(Platform.pathSeparator)
        ? p.substring(p.lastIndexOf(Platform.pathSeparator) + 1)
        : p;
    if (entity is Directory) {
      folderPaths.add(p);
    } else if (entity is File) {
      final skip = p.endsWith('.tags') || name == '.cbfile_config.json';
      if (!skip) filePaths.add(p);
    }
  }

  final allPaths = [...folderPaths, ...filePaths];
  final statRows = <String, _StatRow>{};

  for (var i = 0; i < allPaths.length; i += statChunkSize) {
    final chunk = allPaths.skip(i).take(statChunkSize).toList();
    final results = await Future.wait(
      chunk.map((p) async {
        try {
          final s = await FileStat.stat(p);
          return MapEntry(p, <dynamic>[
            s.modified.millisecondsSinceEpoch, // [0] modified
            s.changed.millisecondsSinceEpoch, // [1] changed (creation on Win)
            s.size, // [2] size
            s.mode, // [3] mode
          ]);
        } catch (_) {
          return null;
        }
      }),
    );
    for (final e in results) {
      if (e != null) statRows[e.key] = e.value;
    }
  }

  // Sort inside the isolate so the main thread just receives ready-to-use lists.
  int cmpName(String a, String b) {
    final aName = a.contains(Platform.pathSeparator)
        ? a.substring(a.lastIndexOf(Platform.pathSeparator) + 1).toLowerCase()
        : a.toLowerCase();
    final bName = b.contains(Platform.pathSeparator)
        ? b.substring(b.lastIndexOf(Platform.pathSeparator) + 1).toLowerCase()
        : b.toLowerCase();
    return aName.compareTo(bName);
  }

  int cmpDate(String a, String b, {bool ascending = true}) {
    final aMs = (statRows[a]?[0] as int?) ?? 0;
    final bMs = (statRows[b]?[0] as int?) ?? 0;
    return ascending ? aMs.compareTo(bMs) : bMs.compareTo(aMs);
  }

  int cmpSize(String a, String b, {bool ascending = true}) {
    final aSize = (statRows[a]?[2] as int?) ?? 0;
    final bSize = (statRows[b]?[2] as int?) ?? 0;
    return ascending ? aSize.compareTo(bSize) : bSize.compareTo(aSize);
  }

  int cmpExt(String a, String b, {bool ascending = true}) {
    String ext(String p) {
      final dot = p.lastIndexOf('.');
      return dot >= 0 ? p.substring(dot).toLowerCase() : '';
    }

    final cmp = ext(a).compareTo(ext(b));
    return ascending ? cmp : -cmp;
  }

  Comparator<String> comparator;
  switch (args.sortOption) {
    case 'nameDesc':
      comparator = (a, b) => -cmpName(a, b);
      break;
    case 'dateAsc':
      comparator = (a, b) => cmpDate(a, b, ascending: true);
      break;
    case 'dateDesc':
      comparator = (a, b) => cmpDate(a, b, ascending: false);
      break;
    case 'dateCreatedAsc':
      comparator = (a, b) {
        final aMs = (statRows[a]?[1] as int?) ?? 0;
        final bMs = (statRows[b]?[1] as int?) ?? 0;
        return aMs.compareTo(bMs);
      };
      break;
    case 'dateCreatedDesc':
      comparator = (a, b) {
        final aMs = (statRows[a]?[1] as int?) ?? 0;
        final bMs = (statRows[b]?[1] as int?) ?? 0;
        return bMs.compareTo(aMs);
      };
      break;
    case 'sizeAsc':
      comparator = (a, b) => cmpSize(a, b, ascending: true);
      break;
    case 'sizeDesc':
      comparator = (a, b) => cmpSize(a, b, ascending: false);
      break;
    case 'extensionAsc':
      comparator = (a, b) => cmpExt(a, b, ascending: true);
      break;
    case 'extensionDesc':
      comparator = (a, b) => cmpExt(a, b, ascending: false);
      break;
    default: // nameAsc and all others
      comparator = cmpName;
      break;
  }

  folderPaths.sort(comparator);
  filePaths.sort(comparator);

  return _ScanResult(
    folderPaths: folderPaths,
    filePaths: filePaths,
    statRows: statRows,
  );
}
