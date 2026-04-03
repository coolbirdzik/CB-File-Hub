import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/services/directory_watcher_service.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart'; // Add import for TrashManager
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart'; // Import for FileOperations
import 'package:path/path.dart' as pathlib;
import 'package:cb_file_manager/helpers/core/text_utils.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'dart:async'; // Import for StreamSubscription
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/services/permission_state_service.dart';
import 'package:cb_file_manager/helpers/core/filesystem_sorter.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';

import 'folder_list_event.dart';
import 'folder_list_state.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/config/language_controller.dart';
import 'package:cb_file_manager/config/languages/vietnamese_localizations.dart';

// Error message helper class using localization
// Usage: Get the localized message from UI layer using AppLocalizations.of(context)
// and pass the appropriate parameters
class SearchErrorMessages {
  // Helper methods to get localized messages
  // Currently defaults to English as BLoC doesn't have context
  // ignore: unused_field
  static final _defaultLocalizations = EnglishLocalizations();

  static AppLocalizations _getL10n() => _l10nNoContext();

  static String noFilesFoundTag(String tag) {
    return _getL10n().noFilesFoundTag({'tag': tag});
  }

  static String noFilesFoundTagGlobal(String tag) {
    return _getL10n().noFilesFoundTagGlobal({'tag': tag});
  }

  static String noFilesFoundTags(String tags) {
    return _getL10n().noFilesFoundTags({'tags': tags});
  }

  static String noFilesFoundTagsGlobal(String tags) {
    return _getL10n().noFilesFoundTagsGlobal({'tags': tags});
  }

  static String errorSearchTag(String error) {
    return _getL10n().errorSearchTag({'error': error});
  }

  static String errorSearchTagGlobal(String error) {
    return _getL10n().errorSearchTagGlobal({'error': error});
  }

  static String errorSearchTags(String error) {
    return _getL10n().errorSearchTags({'error': error});
  }

  static String errorSearchTagsGlobal(String error) {
    return _getL10n().errorSearchTagsGlobal({'error': error});
  }
}

AppLocalizations _l10nNoContext() {
  try {
    final locale = locator<LanguageController>().currentLocale;
    if (locale.languageCode == LanguageController.english) {
      return EnglishLocalizations();
    }
    return VietnameseLocalizations();
  } catch (_) {
    return EnglishLocalizations();
  }
}

class FolderListBloc extends Bloc<FolderListEvent, FolderListState> {
  StreamSubscription? _tagChangeSubscription;
  StreamSubscription<String>? _directoryWatcherSubscription;
  final DirectoryWatcherService _directoryWatcher =
      DirectoryWatcherService.instance;

  static const int _searchResultsPageSize = 200;
  List<FileSystemEntity> _pendingSearchResults = [];
  int _activeSortRequestId = 0;

  FolderListBloc() : super(FolderListState("/")) {
    on<FolderListInit>(_onFolderListInit);
    on<FolderListLoad>(_onFolderListLoad);
    on<FolderListRefresh>(_onFolderListRefresh);
    on<FolderListFilter>(_onFolderListFilter);
    on<FolderListLoadDrives>(_onFolderListLoadDrives);

    // Register for local tag change events
    _tagChangeSubscription = TagManager.onTagChanged.listen(_onTagsChanged);

    // Register for directory file system changes (auto-refresh on file changes)
    _directoryWatcherSubscription = _directoryWatcher.onDirectoryRefresh.listen(
      (path) {
        // Only refresh if the changed path matches our current directory
        if (path == state.currentPath.path) {
          debugPrint(
              '📁 [FolderListBloc] Directory changed, auto-refreshing: $path');
          add(FolderListRefresh(path));
        }
      },
    );

    // Note: AddTagToFile, RemoveTagFromFile, SearchByTag, SearchByTagGlobally,
    // SearchByFileName, and SearchMediaFiles events are now handled directly
    // in the mapEventToState method for immediate UI updates with tag changes

    on<LoadTagsFromFile>(_onLoadTagsFromFile);
    on<LoadAllTags>(_onLoadAllTags);
    on<SetViewMode>(_onSetViewMode);
    on<SetSortOption>(_onSetSortOption);
    on<SetGridZoom>(_onSetGridZoom);
    on<ClearSearchAndFilters>(_onClearSearchAndFilters);
    on<FolderListDeleteFiles>(_onFolderListDeleteFiles);
    on<FolderListDeleteItems>(_onFolderListDeleteItems);
    on<SetTagSearchResults>(_onSetTagSearchResults);
    on<FolderListReloadCurrentFolder>(_onFolderListReloadCurrentFolder);
    on<FolderListDeleteTagGlobally>(_onFolderListDeleteTagGlobally);

    // Register file operation event handlers
    on<CopyFile>(_onCopyFile);
    on<CopyFiles>(_onCopyFiles);
    on<CutFile>(_onCutFile);
    on<CutFiles>(_onCutFiles);
    on<PasteFile>(_onPasteFile);
    on<RenameFileOrFolder>(_onRenameFileOrFolder);

    // Add missing event handlers
    on<SearchByFileName>(_onSearchByFileName);
    on<SearchByTag>(_onSearchByTag);
    on<SearchByTagGlobally>(_onSearchByTagGlobally);
    on<SearchByMultipleTags>(_onSearchByMultipleTags);
    on<SearchByMultipleTagsGlobally>(_onSearchByMultipleTagsGlobally);

    // Handler for adding tag search results
    on<AddTagSearchResults>(_onAddTagSearchResults);

    on<LoadMoreSearchResults>(_onLoadMoreSearchResults);
  }

  // Xử lý khi tag thay đổi
  void _onTagsChanged(String filePath) {
    // Khi có sự kiện tag thay đổi, cập nhật lại danh sách tag
    if (filePath == "global:tag_deleted") {
      // Nếu là xóa tag toàn cục, tải lại tất cả tag
      add(LoadAllTags(state.currentPath.path));
    } else {
      // Cập nhật tag của file cụ thể
      add(LoadTagsFromFile(filePath));
    }
  }

  // Refreshes only the tags without reloading the entire folder structure
  // This preserves scroll position and selection
  void _refreshTagsOnly(String dirPath, Emitter<FolderListState> emit) async {
    try {
      // Emit loading state to notify UI about ongoing operation
      emit(state.copyWith(isLoading: true));

      // Force clear all caches
      TagManager.clearCache();

      // Keep current files and folders as is
      final currentFiles = List<FileSystemEntity>.from(state.files);

      // Only refresh the tags for these files
      Map<String, List<String>> updatedFileTags = {};
      for (final file in currentFiles) {
        if (file is File) {
          // Get updated tags for this file - avoid using cache
          final tags = await TagManager.getTags(file.path);
          if (tags.isNotEmpty) {
            updatedFileTags[file.path] = tags;
          }
        }
      }

      // Get updated unique tags for the directory
      final allUniqueTags = await TagManager.getAllUniqueTags(dirPath);

      // Update state with new tags but keep files/folders and scroll position
      emit(state.copyWith(
        isLoading: false,
        fileTags: updatedFileTags,
        allUniqueTags: allUniqueTags,
      ));
    } catch (e) {
      debugPrint('Error refreshing tags only: $e');
      // Make sure we're not stuck in loading state
      emit(state.copyWith(isLoading: false));
    }
  }

  @override
  Future<void> close() {
    // Cancel all subscriptions when bloc is closed
    _tagChangeSubscription?.cancel();
    _directoryWatcherSubscription?.cancel();
    _directoryWatcher.stopWatching();
    return super.close();
  }

  void _onFolderListInit(
    FolderListInit event,
    Emitter<FolderListState> emit,
  ) async {
    // Initialize with empty folders list
    emit(state.copyWith(isLoading: true));
  }

  void _onFolderListLoad(
    FolderListLoad event,
    Emitter<FolderListState> emit,
  ) async {
    // ===== PERFORMANCE LOGGING START =====
    final totalStopwatch = Stopwatch()..start();
    final stepStopwatch = Stopwatch();

    debugPrint('🟢 [FolderListBloc] Loading path: ${event.path}');
    AppLogger.perf(
        '⏱️ [PERF] Starting folder load at ${DateTime.now()} — path=${event.path}');
    emit(state.copyWith(isLoading: true, currentPath: Directory(event.path)));

    // Special case for empty path on Windows - this is used for the drive listing view
    if (event.path.isEmpty && Platform.isWindows) {
      emit(
        state.copyWith(isLoading: false, folders: [], files: [], error: null),
      );
      AppLogger.perf(
          '⏱️ [PERF] Empty path - total time: ${totalStopwatch.elapsedMilliseconds}ms');
      return;
    }

    if (isDrivesPath(event.path)) {
      emit(
        state.copyWith(isLoading: false, folders: [], files: [], error: null),
      );
      AppLogger.perf(
          '⏱️ [PERF] Drives path - total time: ${totalStopwatch.elapsedMilliseconds}ms');
      return;
    }

    // Special case for mobile - add retry mechanism for folder loading
    if (Platform.isAndroid || Platform.isIOS) {
      // Add a small delay to ensure directory is ready
      await Future.delayed(const Duration(milliseconds: 100));
    }

    try {
      final directory = Directory(event.path);

      stepStopwatch.start();
      final exists = await directory.exists();
      AppLogger.perf(
          '⏱️ [PERF] directory.exists() took: ${stepStopwatch.elapsedMilliseconds}ms');
      stepStopwatch.reset();

      if (exists) {
        try {
          // Debug: Check permission status
          stepStopwatch.start();
          final permissionService = PermissionStateService.instance;
          final hasPermission =
              await permissionService.hasStorageOrPhotosPermission();
          AppLogger.perf(
              '⏱️ [PERF] Permission check took: ${stepStopwatch.elapsedMilliseconds}ms');
          stepStopwatch.reset();
          AppLogger.debug('DEBUG: Storage permission status: $hasPermission');

          // If no permission, try to request it
          if (!hasPermission) {
            debugPrint('DEBUG: No storage permission, requesting...');
            final granted = await permissionService.requestStorageOrPhotos();
            debugPrint('DEBUG: Permission request result: $granted');

            // If still no permission, emit error state
            if (!granted) {
              emit(state.copyWith(
                isLoading: false,
                error: _l10nNoContext().storagePermissionRequiredMessage,
              ));
              return;
            }
          }

          // Get folder-specific sort option BEFORE loading (for consistent sorting during batching)
          stepStopwatch.start();
          final folderSortManager = FolderSortManager();
          SortOption? folderSortOption;
          try {
            folderSortOption =
                await folderSortManager.getFolderSortOption(event.path);
          } catch (e) {
            debugPrint(
                'Error getting folder sort option for ${event.path}: $e');
            folderSortOption = null;
          }
          AppLogger.perf(
              '⏱️ [PERF] getFolderSortOption took: ${stepStopwatch.elapsedMilliseconds}ms');
          stepStopwatch.reset();
          final SortOption sortOptionToUse =
              folderSortOption ?? state.sortOption;

          // Stream-based loading with batch emission for lazy loading
          // OPTIMIZATION: Sort DURING loading to ensure thumbnails are generated
          // in the correct priority order from the start.
          final List<FileSystemEntity> folders = [];
          final List<FileSystemEntity> files = [];
          int batchCount = 0;
          const int batchSize = 50; // Emit partial state every 50 items
          int retryCount = 0;
          const maxRetries = 3;
          // Cache file stats for sorting during loading
          final Map<String, FileStat> loadingFileStatsCache = {};

          stepStopwatch.start();
          while (retryCount < maxRetries) {
            try {
              // Use stream-based loading for progressive display
              await for (final entity in directory.list()) {
                // Cache stats for sorting
                try {
                  loadingFileStatsCache[entity.path] = await entity.stat();
                } catch (_) {}

                if (entity is Directory) {
                  folders.add(entity);
                } else if (entity is File) {
                  // Skip tag files and hidden config files
                  if (!entity.path.endsWith('.tags') &&
                      pathlib.basename(entity.path) != '.cbfile_config.json') {
                    files.add(entity);
                  }
                }
                batchCount++;

                // Emit partial state every batchSize items
                // Always sort during loading to maintain correct thumbnail priority
                if (batchCount % batchSize == 0) {
                  // Sort during loading for correct thumbnail priority
                  final sortedFoldersBatch =
                      await FileSystemSorter.sortDirectories(
                    folders.cast<Directory>(),
                    sortOptionToUse,
                    fileStatsCache: loadingFileStatsCache,
                  );
                  final sortedFilesBatch = await FileSystemSorter.sortFiles(
                    files.cast<File>(),
                    sortOptionToUse,
                    fileStatsCache: loadingFileStatsCache,
                  );
                  emit(state.copyWith(
                    isLoading: true,
                    folders: sortedFoldersBatch,
                    files: sortedFilesBatch,
                    error: null,
                    sortOption: sortOptionToUse,
                    fileStatsCache: Map.from(loadingFileStatsCache),
                  ));
                }
              }
              break; // Success, exit retry loop
            } catch (e) {
              retryCount++;
              if (retryCount < maxRetries) {
                debugPrint(
                    'Directory listing failed, retrying... ($retryCount/$maxRetries): $e');
                await Future.delayed(Duration(milliseconds: 200 * retryCount));
              } else {
                rethrow; // Re-throw the last error
              }
            }
          }
          AppLogger.perf(
              '⏱️ [PERF] directory.list() stream took: ${stepStopwatch.elapsedMilliseconds}ms for ${folders.length + files.length} items');
          stepStopwatch.reset();

          debugPrint(
              'DEBUG: Directory listing found ${folders.length + files.length} items');
          debugPrint('DEBUG: Directory path: ${event.path}');
          debugPrint(
              'DEBUG: Final result - ${folders.length} folders, ${files.length} files');

          // Final sort for the complete list (using the stats cache from loading)
          stepStopwatch.start();
          final sortedFolders = await FileSystemSorter.sortDirectories(
            folders.cast<Directory>(),
            sortOptionToUse,
            fileStatsCache: loadingFileStatsCache,
          );
          final sortedFiles = await FileSystemSorter.sortFiles(
            files.cast<File>(),
            sortOptionToUse,
            fileStatsCache: loadingFileStatsCache,
          );
          AppLogger.perf(
              '⏱️ [PERF] Final sorting took: ${stepStopwatch.elapsedMilliseconds}ms');
          stepStopwatch.reset();

          // Update folders and files with sorted versions
          folders.clear();
          folders.addAll(sortedFolders);
          files.clear();
          files.addAll(sortedFiles);

          // File stats cache is already built during loading
          // Use the loadingFileStatsCache that was populated during directory listing

          final activeFilter = state.currentFilter;
          final List<FileSystemEntity> filteredFiles =
              activeFilter != null && activeFilter.isNotEmpty
                  ? _filterFilesByType(files, activeFilter)
                  : [];

          // PROGRESSIVE LOADING: Emit content immediately with isLoading: false
          // Tags will be loaded asynchronously and updated later
          emit(state.copyWith(
            isLoading: false,
            folders: folders,
            files: files,
            currentFilter: activeFilter,
            filteredFiles: filteredFiles,
            fileTags: {}, // Empty tags initially - will be updated async
            fileStatsCache: Map.from(loadingFileStatsCache),
            error: null,
            sortOption: folderSortOption ?? state.sortOption,
          ));

          AppLogger.perf(
              '⏱️ [PERF] 📍 UI READY - Total time to show files: ${totalStopwatch.elapsedMilliseconds}ms');
          debugPrint(
              'DEBUG: Emitting state with ${files.length} files (tags loading async)');

          // Load tags asynchronously AFTER showing content
          // This prevents blocking the UI while tags are being loaded
          // OPTIMIZATION: Use batch loading instead of loading one by one
          stepStopwatch.start();
          final filePaths = files.whereType<File>().map((f) => f.path).toList();
          final fileTags = await TagManager.getTagsForFiles(filePaths);
          AppLogger.perf(
              '⏱️ [PERF] Batch tag loading for ${files.length} files took: ${stepStopwatch.elapsedMilliseconds}ms');
          stepStopwatch.reset();

          // Update state with loaded tags if any were found
          if (fileTags.isNotEmpty) {
            emit(state.copyWith(
              fileTags: fileTags,
            ));
          }

          // Load all unique tags in this directory (async)
          add(LoadAllTags(event.path));

          // Prefetch thumbnails for the entire directory in background
          _prefetchThumbnailsForDirectory(files, event.path);

          // Start watching the directory for file system changes (auto-refresh)
          await _directoryWatcher.startWatching(event.path);

          AppLogger.perf(
              '⏱️ [PERF] ✅ COMPLETE - Total folder load time: ${totalStopwatch.elapsedMilliseconds}ms');
          // ===== PERFORMANCE LOGGING END =====
        } catch (e) {
          debugPrint('🔴 [FolderListBloc] ERROR loading directory: $e');
          debugPrint('🔴 [FolderListBloc] Error type: ${e.runtimeType}');
          debugPrint('🔴 [FolderListBloc] Stack trace: ${StackTrace.current}');

          // Handle specific permission errors
          if (e.toString().toLowerCase().contains('permission denied') ||
              e.toString().toLowerCase().contains('access denied')) {
            emit(
              state.copyWith(
                isLoading: false,
                error: _l10nNoContext().accessDeniedAdminMessage(event.path),
                folders: [],
                files: [],
              ),
            );
          } else {
            emit(
              state.copyWith(
                isLoading: false,
                error: _l10nNoContext()
                    .errorAccessingDirectoryWithError(e.toString()),
                folders: [],
                files: [],
              ),
            );
          }
        }
      } else {
        debugPrint(
            '🔴 [FolderListBloc] Directory does not exist: ${event.path}');
        emit(
          state.copyWith(
              isLoading: false,
              error: _l10nNoContext().directoryDoesNotExist(event.path)),
        );
      }
    } catch (e) {
      debugPrint('🔴 [FolderListBloc] OUTER ERROR: $e');
      debugPrint('🔴 [FolderListBloc] Error type: ${e.runtimeType}');

      // Improved error handling with user-friendly messages
      if (e.toString().toLowerCase().contains('permission denied') ||
          e.toString().toLowerCase().contains('access denied')) {
        emit(
          state.copyWith(
            isLoading: false,
            error: _l10nNoContext().accessDeniedAdminMessage(event.path),
            folders: [],
            files: [],
          ),
        );
      } else {
        emit(
          state.copyWith(
            isLoading: false,
            error: _l10nNoContext().errorWithMessage(e.toString()),
            folders: [],
            files: [],
          ),
        );
      }
    }
  }

  // Note: _buildFileStatsCacheAsync is no longer needed.
  // File stats cache is now built during directory listing (loadingFileStatsCache)
  // to enable sorting during loading and correct thumbnail priority.

  void _onFolderListRefresh(
    FolderListRefresh event,
    Emitter<FolderListState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));

    try {
      if (isDrivesPath(event.path)) {
        emit(
          state.copyWith(
            isLoading: false,
            folders: [],
            files: [],
            error: null,
          ),
        );
        return;
      }

      // Check if this is a system path (starts with #)
      if (event.path.startsWith('#')) {
        // For system paths, we need special handling
        if (event.path == '#tags') {
          // For tag management screen, just load all unique tags
          final allUniqueTags = await TagManager.getAllUniqueTags("");
          emit(state.copyWith(
            isLoading: false,
            allUniqueTags: allUniqueTags,
          ));
          return;
        } else if (event.path.startsWith('#search?tag=')) {
          emit(state.copyWith(
            isLoading: false,
          ));
          return;
        }
      }

      final directory = Directory(event.path);
      if (await directory.exists()) {
        // Load folder contents first
        List<FileSystemEntity> contents = await directory.list().toList();

        // Separate folders and files
        final List<FileSystemEntity> folders = [];
        final List<FileSystemEntity> files = [];

        for (var entity in contents) {
          if (entity is Directory) {
            folders.add(entity);
          } else if (entity is File) {
            // Skip tag files
            if (!entity.path.endsWith('.tags') &&
                pathlib.basename(entity.path) != '.cbfile_config.json') {
              files.add(entity);
            }
          }
        }

        // Get folder-specific sort option if available (with defensive error handling)
        final folderSortManager = FolderSortManager();
        SortOption? folderSortOption;
        try {
          folderSortOption =
              await folderSortManager.getFolderSortOption(event.path);
        } catch (e) {
          debugPrint('Error getting folder sort option for ${event.path}: $e');
          folderSortOption = null;
        }

        // Use folder-specific sort option if available, otherwise use the current sort option
        SortOption sortOptionToUse = folderSortOption ?? state.sortOption;

        // Apply sorting
        final sortedFolders = await FileSystemSorter.sortDirectories(
          folders.cast<Directory>(),
          sortOptionToUse,
        );

        final sortedFiles = await FileSystemSorter.sortFiles(
          files.cast<File>(),
          sortOptionToUse,
        );

        final activeFilter = state.currentFilter;
        final List<FileSystemEntity> filteredFiles =
            activeFilter != null && activeFilter.isNotEmpty
                ? _filterFilesByType(sortedFiles, activeFilter)
                : [];

        // PROGRESSIVE LOADING: Emit content immediately
        // Tags and stats will be loaded asynchronously
        emit(
          state.copyWith(
            isLoading: false,
            folders: sortedFolders,
            files: sortedFiles,
            currentFilter: activeFilter,
            filteredFiles: filteredFiles,
            fileTags: {}, // Empty tags initially - will be updated async
            error: null,
            currentPath: Directory(event.path),
            sortOption: folderSortOption ?? state.sortOption,
          ),
        );

        // Load tags asynchronously AFTER showing content
        // OPTIMIZATION: Use batch loading instead of one-by-one
        TagManager.clearCache();
        final filePaths = sortedFiles.map((f) => f.path).toList();
        final fileTags = await TagManager.getTagsForFiles(filePaths);

        // Update state with loaded tags
        if (fileTags.isNotEmpty) {
          final allUniqueTags = await TagManager.getAllUniqueTags(event.path);
          emit(state.copyWith(
            fileTags: fileTags,
            allUniqueTags: allUniqueTags,
          ));
        }

        // Build file stats cache asynchronously
        Map<String, FileStat> fileStatsCache = {};
        final allEntities = [...sortedFolders, ...sortedFiles];
        for (var entity in allEntities) {
          try {
            fileStatsCache[entity.path] = await entity.stat();
          } catch (e) {
            continue;
          }
        }
        if (fileStatsCache.isNotEmpty) {
          emit(state.copyWith(fileStatsCache: fileStatsCache));
        }

        // Start thumbnail generation in background AFTER updating UI
        if (event.forceRegenerateThumbnails) {
          unawaited(
            VideoThumbnailHelper.regenerateThumbnailsForDirectory(event.path),
          );
        } else {
          _prefetchThumbnailsForDirectory(sortedFiles, event.path);
        }
      } else {
        emit(
          state.copyWith(
            isLoading: false,
            error: _l10nNoContext().directoryDoesNotExist(event.path),
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          error:
              _l10nNoContext().errorAccessingDirectoryWithError(e.toString()),
        ),
      );
    } finally {
      // Extra safety: ensure loading indicator is gone
      if (state.isLoading) {
        emit(state.copyWith(isLoading: false));
      }
    }
  }

  // Proactively generate thumbnails for ALL video files in the directory
  // Priority is based on list position (top items get higher priority)
  void _prefetchThumbnailsForDirectory(
      List<FileSystemEntity> files, String dirPath) {
    try {
      // Skip special/system paths
      if (dirPath.startsWith('#')) return;

      // Collect video file paths in sorted order
      final videoPaths = files
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => FileTypeUtils.isVideoFile(p))
          .toList();

      if (videoPaths.isEmpty) return;

      // Inform helper about current directory to cancel other queues
      VideoThumbnailHelper.setCurrentDirectory(dirPath);

      // Generate thumbnails for ALL files with priority based on position
      // Top items get highest priority, decreasing as we go down
      unawaited(
        VideoThumbnailHelper.proactiveGenerateAll(
          videoPaths,
          directoryPath: dirPath,
        ),
      );
    } catch (e) {
      debugPrint('Error prefetching thumbnails for $dirPath: $e');
    }
  }

  void _onFolderListFilter(
    FolderListFilter event,
    Emitter<FolderListState> emit,
  ) async {
    // Filter files by type (videos, images, etc.)
    if (event.fileType == null) {
      emit(state.copyWith(currentFilter: null, filteredFiles: []));
      return;
    }

    emit(state.copyWith(isLoading: true, currentFilter: event.fileType));

    try {
      final List<FileSystemEntity> filteredFiles =
          _filterFilesByType(state.files, event.fileType!);
      emit(state.copyWith(isLoading: false, filteredFiles: filteredFiles));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
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

  void _onLoadTagsFromFile(
    LoadTagsFromFile event,
    Emitter<FolderListState> emit,
  ) async {
    try {
      final tags = await TagManager.getTags(event.filePath);

      // Only update if we have tags
      if (tags.isNotEmpty) {
        Map<String, List<String>> updatedFileTags = Map.from(state.fileTags);
        updatedFileTags[event.filePath] = tags;

        emit(state.copyWith(fileTags: updatedFileTags));
      }
    } catch (e) {
      debugPrint('Error loading tags for file: ${e.toString()}');
    }
  }

  void _onLoadAllTags(LoadAllTags event, Emitter<FolderListState> emit) async {
    try {
      // Get all unique tags across the entire file system (globally)
      final Set<String> allTags = await TagManager.getAllUniqueTags(
        event.directory,
      );
      emit(state.copyWith(allUniqueTags: allTags));
    } catch (e) {
      debugPrint('Error loading all tags: ${e.toString()}');
    }
  }

  void _onSetViewMode(SetViewMode event, Emitter<FolderListState> emit) {
    emit(state.copyWith(viewMode: event.viewMode));
  }

  void _onSetGridZoom(SetGridZoom event, Emitter<FolderListState> emit) {
    // Update the grid zoom level
    emit(state.copyWith(gridZoomLevel: event.zoomLevel));
  }

  void _onSetSortOption(
    SetSortOption event,
    Emitter<FolderListState> emit,
  ) async {
    final int sortRequestId = ++_activeSortRequestId;
    bool isStaleSort() => isClosed || sortRequestId != _activeSortRequestId;

    emit(state.copyWith(isLoading: true));

    try {
      final String targetPath = state.currentPath.path;

      // Get file stats for sorting
      Map<String, FileStat> fileStatsCache = {};

      // Create new sorted lists by copying the original lists
      List<FileSystemEntity> sortedFolders = List.from(state.folders);
      List<FileSystemEntity> sortedFiles = List.from(state.files);
      List<FileSystemEntity> sortedFilteredFiles = List.from(
        state.filteredFiles,
      );

      // Cache file stats for better performance
      Future<void> cacheFileStats(List<FileSystemEntity> entities) async {
        for (var entity in entities) {
          if (!fileStatsCache.containsKey(entity.path)) {
            fileStatsCache[entity.path] = await entity.stat();
          }
        }
      }

      // Wait for all file stats to be loaded
      await Future.wait([
        cacheFileStats(sortedFolders),
        cacheFileStats(sortedFiles),
        cacheFileStats(sortedFilteredFiles),
      ]);
      if (isStaleSort()) return;

      // Save the sort option to the current folder (with defensive error handling)
      final folderSortManager = FolderSortManager();
      debugPrint(
          'Trying to save sort option ${event.sortOption} to folder: ${state.currentPath.path}');

      bool saveResult = false;
      try {
        // Remove timeout - let it run quickly without blocking
        saveResult = await folderSortManager.saveFolderSortOption(
            state.currentPath.path, event.sortOption);
      } catch (e) {
        debugPrint(
            'Error saving folder sort option for ${state.currentPath.path}: $e');
        saveResult = false; // Continue without saving if error occurs
      }
      debugPrint('Save sort option result: $saveResult');

      // Check if sort option was actually saved (with defensive error handling)
      SortOption? savedOption;
      try {
        // Remove timeout - let it run quickly with cache
        savedOption =
            await folderSortManager.getFolderSortOption(state.currentPath.path);
      } catch (e) {
        debugPrint(
            'Error getting folder sort option for ${state.currentPath.path}: $e');
        savedOption = null; // Continue without saved option if error occurs
      }
      debugPrint('Retrieved sort option after save: ${savedOption?.name}');
      if (isStaleSort()) return;

      // Define the sorting function based on the selected sort option
      int Function(FileSystemEntity, FileSystemEntity) compareFunction;

      switch (event.sortOption) {
        case SortOption.nameAsc:
          compareFunction = (a, b) => pathlib
              .basename(a.path)
              .toLowerCase()
              .compareTo(pathlib.basename(b.path).toLowerCase());
          break;
        case SortOption.nameDesc:
          compareFunction = (a, b) => pathlib
              .basename(b.path)
              .toLowerCase()
              .compareTo(pathlib.basename(a.path).toLowerCase());
          break;
        case SortOption.dateAsc:
          compareFunction = (a, b) {
            final aStats = fileStatsCache[a.path]!;
            final bStats = fileStatsCache[b.path]!;
            return aStats.modified.compareTo(bStats.modified);
          };
          break;
        case SortOption.dateDesc:
          compareFunction = (a, b) {
            final aStats = fileStatsCache[a.path]!;
            final bStats = fileStatsCache[b.path]!;
            return bStats.modified.compareTo(aStats.modified);
          };
          break;
        case SortOption.sizeAsc:
          compareFunction = (a, b) {
            final aStats = fileStatsCache[a.path]!;
            final bStats = fileStatsCache[b.path]!;
            return aStats.size.compareTo(bStats.size);
          };
          break;
        case SortOption.sizeDesc:
          compareFunction = (a, b) {
            final aStats = fileStatsCache[a.path]!;
            final bStats = fileStatsCache[b.path]!;
            return bStats.size.compareTo(aStats.size);
          };
          break;
        case SortOption.typeAsc:
          compareFunction = (a, b) {
            final aExt = pathlib.extension(a.path).toLowerCase();
            final bExt = pathlib.extension(b.path).toLowerCase();
            return aExt.compareTo(bExt);
          };
          break;
        case SortOption.typeDesc:
          compareFunction = (a, b) {
            final aExt = pathlib.extension(a.path).toLowerCase();
            final bExt = pathlib.extension(b.path).toLowerCase();
            return bExt.compareTo(aExt);
          };
          break;
        case SortOption.dateCreatedAsc:
          compareFunction = (a, b) {
            // On Windows, we can get creation time
            if (Platform.isWindows) {
              try {
                final aStats = fileStatsCache[a.path]!;
                final bStats = fileStatsCache[b.path]!;
                return aStats.changed.compareTo(bStats.changed);
              } catch (e) {
                // Fallback to modified date if any error
                final aStats = fileStatsCache[a.path]!;
                final bStats = fileStatsCache[b.path]!;
                return aStats.modified.compareTo(bStats.modified);
              }
            } else {
              // On other platforms, use modified as a fallback
              final aStats = fileStatsCache[a.path]!;
              final bStats = fileStatsCache[b.path]!;
              return aStats.modified.compareTo(bStats.modified);
            }
          };
          break;
        case SortOption.dateCreatedDesc:
          compareFunction = (a, b) {
            // On Windows, we can get creation time
            if (Platform.isWindows) {
              try {
                final aStats = fileStatsCache[a.path]!;
                final bStats = fileStatsCache[b.path]!;
                return bStats.changed.compareTo(aStats.changed);
              } catch (e) {
                // Fallback to modified date if any error
                final aStats = fileStatsCache[a.path]!;
                final bStats = fileStatsCache[b.path]!;
                return bStats.modified.compareTo(aStats.modified);
              }
            } else {
              // On other platforms, use modified as a fallback
              final aStats = fileStatsCache[a.path]!;
              final bStats = fileStatsCache[b.path]!;
              return bStats.modified.compareTo(aStats.modified);
            }
          };
          break;
        case SortOption.extensionAsc:
          compareFunction = (a, b) {
            final aExt = pathlib.extension(a.path).toLowerCase();
            final bExt = pathlib.extension(b.path).toLowerCase();
            return aExt.compareTo(bExt);
          };
          break;
        case SortOption.extensionDesc:
          compareFunction = (a, b) {
            final aExt = pathlib.extension(a.path).toLowerCase();
            final bExt = pathlib.extension(b.path).toLowerCase();
            return bExt.compareTo(aExt);
          };
          break;
        case SortOption.attributesAsc:
          compareFunction = (a, b) {
            final aStats = fileStatsCache[a.path]!;
            final bStats = fileStatsCache[b.path]!;
            // Create a string representation of attributes for comparison
            final aAttrs = '${aStats.mode},${aStats.type}';
            final bAttrs = '${bStats.mode},${bStats.type}';
            return aAttrs.compareTo(bAttrs);
          };
          break;
        case SortOption.attributesDesc:
          compareFunction = (a, b) {
            final aStats = fileStatsCache[a.path]!;
            final bStats = fileStatsCache[b.path]!;
            // Create a string representation of attributes for comparison
            final aAttrs = '${aStats.mode},${aStats.type}';
            final bAttrs = '${bStats.mode},${bStats.type}';
            return bAttrs.compareTo(aAttrs);
          };
          break;
        default:
          compareFunction = (a, b) => pathlib
              .basename(a.path)
              .toLowerCase()
              .compareTo(pathlib.basename(b.path).toLowerCase());
      }

      // Folders always come first, then apply the sort function within each group

      // Sort folders and files separately
      sortedFolders.sort(compareFunction);
      sortedFiles.sort(compareFunction);
      sortedFilteredFiles.sort(compareFunction);
      if (isStaleSort()) return;

      // Rebase to latest state if folder load finished while sort was running.
      final bool hasNewerContent = state.currentPath.path == targetPath &&
          (state.folders.isNotEmpty || state.files.isNotEmpty) &&
          sortedFolders.isEmpty &&
          sortedFiles.isEmpty;
      if (hasNewerContent) {
        sortedFolders = List<FileSystemEntity>.from(state.folders);
        sortedFiles = List<FileSystemEntity>.from(state.files);
        sortedFilteredFiles = List<FileSystemEntity>.from(state.filteredFiles);
        await Future.wait([
          cacheFileStats(sortedFolders),
          cacheFileStats(sortedFiles),
          cacheFileStats(sortedFilteredFiles),
        ]);
        if (isStaleSort()) return;
        sortedFolders.sort(compareFunction);
        sortedFiles.sort(compareFunction);
        sortedFilteredFiles.sort(compareFunction);
      }

      // Always re-read search results at the end to avoid overwriting newer data.
      List<FileSystemEntity> sortedSearchResults =
          List.from(state.searchResults);
      await cacheFileStats(sortedSearchResults);
      if (isStaleSort()) return;

      final sortedSearchFolders = sortedSearchResults
          .whereType<Directory>()
          .toList()
        ..sort(compareFunction);
      final sortedSearchFiles = sortedSearchResults.whereType<File>().toList()
        ..sort(compareFunction);
      final sortedSearchOthers = sortedSearchResults
          .where((e) => e is! Directory && e is! File)
          .toList()
        ..sort(compareFunction);

      sortedSearchResults = [
        ...sortedSearchFolders,
        ...sortedSearchOthers,
        ...sortedSearchFiles,
      ];
      if (isStaleSort()) return;

      // Emit the new state with sorted lists and the updated sort option
      emit(
        state.copyWith(
          isLoading: false,
          sortOption: event.sortOption,
          folders: sortedFolders,
          files: sortedFiles,
          filteredFiles: sortedFilteredFiles,
          searchResults: sortedSearchResults,
          fileStatsCache: fileStatsCache,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          error: "Error sorting files: ${e.toString()}",
        ),
      );
    }
  }

  void _onClearSearchAndFilters(
    ClearSearchAndFilters event,
    Emitter<FolderListState> emit,
  ) {
    _pendingSearchResults = [];
    // Reset all search and filter related state variables
    emit(
      state.copyWith(
        currentSearchTag: null,
        currentSearchQuery: null,
        currentFilter: null,
        searchResults: [],
        hasMoreSearchResults: false,
        isLoadingMoreSearchResults: false,
        searchResultsTotal: null,
        filteredFiles: [],
        isSearchByName: false,
        isSearchByMedia: false,
        isGlobalSearch: false,
        searchRecursive: false,
        currentMediaSearch: null,
        error: null, // Also clear any previous error messages
      ),
    );
  }

  void _onFolderListDeleteFiles(
    FolderListDeleteFiles event,
    Emitter<FolderListState> emit,
  ) async {
    final l10n = _l10nNoContext();
    final Set<String> targetPaths = event.filePaths.toSet();
    if (targetPaths.isNotEmpty) {
      emit(_removePathsFromState(state, targetPaths).copyWith(error: null));
    }
    final operation = locator<OperationProgressController>();
    String? opId;
    try {
      final String currentOpId = operation.begin(
        title: l10n.deletingFiles,
        total: event.filePaths.length,
        detail: event.filePaths.isEmpty
            ? null
            : pathlib.basename(event.filePaths.first),
        showModal: false,
      );
      opId = currentOpId;
      List<String> failedDeletes = [];
      final trashManager = TrashManager(); // Create an instance of TrashManager
      int completed = 0;

      for (var filePath in event.filePaths) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            await trashManager.moveToTrash(filePath); // Use the instance method
          }
          completed++;
          operation.update(
            currentOpId,
            completed: completed,
            detail: pathlib.basename(filePath),
          );
        } catch (e) {
          failedDeletes.add(filePath);
          debugPrint('Error deleting file $filePath: $e');
        }
      }

      if (failedDeletes.isNotEmpty) {
        final message = l10n.failedToDeleteFilesCount(failedDeletes.length);
        emit(
          state.copyWith(
            error: message,
          ),
        );
        operation.fail(
          currentOpId,
          detail: message,
        );
        // Refresh to restore any items that failed to delete.
        add(FolderListLoad(state.currentPath.path));
        return;
      }

      operation.succeed(
        currentOpId,
        detail: l10n.done,
      );
      // Keep the optimistic UI state; no need to reload on success.
    } catch (e) {
      emit(
        state.copyWith(
          error: l10n.errorDeletingFilesWithError(e.toString()),
        ),
      );
      if (opId != null) {
        // ignore: unnecessary_non_null_assertion
        operation.fail(opId!, detail: l10n.operationFailed);
      }
      // Fallback: refresh the entire folder if something goes wrong.
      add(FolderListLoad(state.currentPath.path));
    }
  }

  FolderListState _removePathsFromState(
    FolderListState current,
    Set<String> targetPaths,
  ) {
    if (targetPaths.isEmpty) return current;

    final updatedFiles =
        current.files.where((e) => !targetPaths.contains(e.path)).toList();
    final updatedFolders =
        current.folders.where((e) => !targetPaths.contains(e.path)).toList();
    final updatedFiltered = current.filteredFiles
        .where((e) => !targetPaths.contains(e.path))
        .toList();
    final updatedSearch = current.searchResults
        .where((e) => !targetPaths.contains(e.path))
        .toList();

    final updatedTags = Map<String, List<String>>.from(current.fileTags);
    for (final p in targetPaths) {
      updatedTags.remove(p);
    }

    final updatedStats = Map<String, FileStat>.from(current.fileStatsCache);
    for (final p in targetPaths) {
      updatedStats.remove(p);
    }

    final Set<String> updatedUniqueTags = <String>{};
    for (final tags in updatedTags.values) {
      updatedUniqueTags.addAll(tags);
    }

    return current.copyWith(
      files: updatedFiles,
      folders: updatedFolders,
      filteredFiles: updatedFiltered,
      searchResults: updatedSearch,
      fileTags: updatedTags,
      fileStatsCache: updatedStats,
      allUniqueTags: updatedUniqueTags,
    );
  }

  void _onFolderListDeleteItems(
    FolderListDeleteItems event,
    Emitter<FolderListState> emit,
  ) async {
    final l10n = _l10nNoContext();
    // Don't show loading indicator for delete operation - it's usually fast
    final Set<String> targetPaths = {
      ...event.filePaths,
      ...event.folderPaths,
    };
    if (targetPaths.isNotEmpty) {
      emit(_removePathsFromState(state, targetPaths).copyWith(error: null));
    }
    final operation = locator<OperationProgressController>();
    String? opId;
    try {
      final int total = event.filePaths.length + event.folderPaths.length;
      final String title =
          event.permanent ? l10n.deletingItems : l10n.movingItemsToTrash;
      final String? first = event.filePaths.isNotEmpty
          ? pathlib.basename(event.filePaths.first)
          : (event.folderPaths.isNotEmpty
              ? pathlib.basename(event.folderPaths.first)
              : null);
      final String currentOpId = operation.begin(
        title: title,
        total: total,
        detail: first,
        showModal: false,
      );
      opId = currentOpId;
      List<String> failedDeletes = [];
      final trashManager = TrashManager();
      final deletedPaths = <String>[];
      int completed = 0;

      Future<void> deleteItem(String path, bool isFile) async {
        try {
          if (event.permanent) {
            if (isFile) {
              final file = File(path);
              if (await file.exists()) {
                await file.delete();
                deletedPaths.add(path);
              }
            } else {
              final dir = Directory(path);
              if (await dir.exists()) {
                await dir.delete(recursive: true);
                deletedPaths.add(path);
              }
            }
          } else {
            await trashManager.moveToTrash(path);
            deletedPaths.add(path);
          }
          completed++;
          operation.update(
            currentOpId,
            completed: completed,
            detail: pathlib.basename(path),
          );
        } catch (e) {
          failedDeletes.add(path);
          debugPrint('Error deleting $path: $e');
        }
      }

      for (var path in event.filePaths) {
        await deleteItem(path, true);
      }

      for (var path in event.folderPaths) {
        await deleteItem(path, false);
      }

      if (failedDeletes.isNotEmpty) {
        final message = l10n.failedToDeleteItemsCount(failedDeletes.length);
        emit(state.copyWith(
          error: message,
        ));
        operation.fail(
          currentOpId,
          detail: message,
        );
        // Still need to refresh if some items failed
        add(FolderListLoad(state.currentPath.path));
        return;
      }

      // Keep the optimistic UI state; items already removed before deletion ran.

      debugPrint(
          'Deleted ${deletedPaths.length} items successfully (optimized refresh)');
      operation.succeed(currentOpId, detail: l10n.done);
    } catch (e) {
      emit(state.copyWith(
        error: l10n.errorDeletingItemsWithError(e.toString()),
      ));
      if (opId != null) {
        // ignore: unnecessary_non_null_assertion
        operation.fail(opId!, detail: l10n.operationFailed);
      }
      // Fallback: refresh the entire folder if something goes wrong
      add(FolderListLoad(state.currentPath.path));
    }
  }

  void _onSetTagSearchResults(
    SetTagSearchResults event,
    Emitter<FolderListState> emit,
  ) {
    // Update the state with tag search results
    emit(
      state.copyWith(
        searchResults: event.results,
        currentSearchTag: event.tagName,
        isLoading: false,
        isSearchByName: false,
        isGlobalSearch: false,
        currentSearchQuery: null,
      ),
    );
  }

  // File operation handlers
  void _onCopyFile(CopyFile event, Emitter<FolderListState> emit) {
    try {
      // Use the FileOperations singleton to add the file to clipboard
      FileOperations().copyToClipboard(event.entity);
      emit(
        state.copyWith(
          error: null, // Clear any previous errors
          clipboardRevision: state.clipboardRevision + 1, // Clear cut effect
        ),
      );
    } catch (e) {
      emit(state.copyWith(error: 'Error copying file/folder: ${e.toString()}'));
    }
  }

  void _onCutFile(CutFile event, Emitter<FolderListState> emit) {
    try {
      // Use the FileOperations singleton to add the file to clipboard for cutting
      FileOperations().cutToClipboard(event.entity);
      emit(
        state.copyWith(
          error: null, // Clear any previous errors
          clipboardRevision:
              state.clipboardRevision + 1, // Trigger rebuild for cut effect
        ),
      );
    } catch (e) {
      emit(state.copyWith(error: 'Error cutting file/folder: ${e.toString()}'));
    }
  }

  void _onCopyFiles(CopyFiles event, Emitter<FolderListState> emit) {
    try {
      FileOperations().copyFilesToClipboard(event.entities);
      emit(state.copyWith(
        error: null,
        clipboardRevision: state.clipboardRevision + 1, // Clear cut effect
      ));
    } catch (e) {
      emit(state.copyWith(error: 'Error copying files: ${e.toString()}'));
    }
  }

  void _onCutFiles(CutFiles event, Emitter<FolderListState> emit) {
    try {
      FileOperations().cutFilesToClipboard(event.entities);
      emit(state.copyWith(
        error: null,
        clipboardRevision:
            state.clipboardRevision + 1, // Trigger rebuild for cut effect
      ));
    } catch (e) {
      emit(state.copyWith(error: 'Error cutting files: ${e.toString()}'));
    }
  }

  void _onPasteFile(PasteFile event, Emitter<FolderListState> emit) async {
    if (!FileOperations().hasClipboardItem) {
      emit(state.copyWith(error: 'Nothing to paste - clipboard is empty'));
      return;
    }

    emit(state.copyWith(isLoading: true));

    // Get the progress controller
    final progressController = locator<OperationProgressController>();

    // Determine operation type for display
    final isCutOperation = FileOperations().isCutOperation;
    final operationType = isCutOperation ? 'Moving' : 'Copying';
    final itemCount = FileOperations().clipboardItemCount;

    // Start progress tracking (for non-Windows or when native fails)
    final progressId = progressController.begin(
      title: '$operationType $itemCount item${itemCount > 1 ? 's' : ''}...',
      total: itemCount,
    );

    try {
      // Use the FileOperations singleton to paste the file
      await FileOperations().pasteFromClipboard(
        event.destinationPath,
        onProgress: (completed, total) {
          // Update progress
          progressController.update(
            progressId,
            completed: completed,
            detail: '$operationType file $completed of $total',
          );
        },
      );

      // Mark operation as successful
      progressController.succeed(
        progressId,
        detail:
            '${isCutOperation ? 'Moved' : 'Copied'} $itemCount item${itemCount > 1 ? 's' : ''}',
      );

      // Increment clipboard revision to clear cut effect after paste
      emit(state.copyWith(
        clipboardRevision: state.clipboardRevision + 1,
      ));

      // Refresh the current directory to show the new file/folder
      add(FolderListLoad(state.currentPath.path));
    } catch (e) {
      progressController.fail(progressId, detail: 'Error: ${e.toString()}');
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Error pasting file/folder: ${e.toString()}',
        ),
      );
    }
  }

  void _onRenameFileOrFolder(
    RenameFileOrFolder event,
    Emitter<FolderListState> emit,
  ) async {
    // OPTIMIZATION: Use optimistic update instead of full folder reload
    // This prevents full grid/list re-render when renaming a single item

    final oldPath = event.entity.path;
    final newPath = pathlib.join(pathlib.dirname(oldPath), event.newName);
    final isFile = event.entity is File;

    // Temporarily stop directory watcher to avoid triggering refresh
    // when rename causes file system events
    await _directoryWatcher.stopWatching();

    try {
      // Perform the actual rename operation
      await FileOperations().rename(event.entity, event.newName);

      // OPTIMISTIC UPDATE: Update only the affected item in state
      final List<FileSystemEntity> updatedFiles = List.from(state.files);
      final List<FileSystemEntity> updatedFolders = List.from(state.folders);
      final List<FileSystemEntity> updatedSearchResults =
          List.from(state.searchResults);
      final List<FileSystemEntity> updatedFilteredFiles =
          List.from(state.filteredFiles);

      if (isFile) {
        // Update in files list
        final index = updatedFiles.indexWhere((f) => f.path == oldPath);
        if (index >= 0) {
          updatedFiles[index] = File(newPath);
        }

        // Update in search results if present
        final searchIndex =
            updatedSearchResults.indexWhere((f) => f.path == oldPath);
        if (searchIndex >= 0) {
          updatedSearchResults[searchIndex] = File(newPath);
        }

        // Update in filtered files if present
        final filteredIndex =
            updatedFilteredFiles.indexWhere((f) => f.path == oldPath);
        if (filteredIndex >= 0) {
          updatedFilteredFiles[filteredIndex] = File(newPath);
        }
      } else {
        // Update in folders list
        final index = updatedFolders.indexWhere((f) => f.path == oldPath);
        if (index >= 0) {
          updatedFolders[index] = Directory(newPath);
        }

        // Update in search results if present
        final searchIndex =
            updatedSearchResults.indexWhere((f) => f.path == oldPath);
        if (searchIndex >= 0) {
          updatedSearchResults[searchIndex] = Directory(newPath);
        }
      }

      // Update tags map if the file had tags
      final Map<String, List<String>> updatedFileTags =
          Map.from(state.fileTags);
      if (updatedFileTags.containsKey(oldPath)) {
        final tags = updatedFileTags.remove(oldPath);
        if (tags != null) {
          updatedFileTags[newPath] = tags;
        }
      }

      // Update file stats cache
      final Map<String, FileStat> updatedFileStatsCache =
          Map.from(state.fileStatsCache);
      if (updatedFileStatsCache.containsKey(oldPath)) {
        final stats = updatedFileStatsCache.remove(oldPath);
        if (stats != null) {
          updatedFileStatsCache[newPath] = stats;
        }
      }

      // Re-sort the updated lists to maintain proper order
      final sortedFiles = await FileSystemSorter.sortFiles(
        updatedFiles.cast<File>(),
        state.sortOption,
      );
      final sortedFolders = await FileSystemSorter.sortDirectories(
        updatedFolders.cast<Directory>(),
        state.sortOption,
      );

      // Emit the updated state WITHOUT triggering a full reload
      emit(
        state.copyWith(
          files: sortedFiles,
          folders: sortedFolders,
          searchResults: updatedSearchResults,
          filteredFiles: updatedFilteredFiles,
          fileTags: updatedFileTags,
          fileStatsCache: updatedFileStatsCache,
          error: null,
        ),
      );

      // Restart directory watcher after rename is complete
      await _directoryWatcher.startWatching(state.currentPath.path);
    } catch (e) {
      emit(
        state.copyWith(
          error: 'Error renaming file/folder: ${e.toString()}',
        ),
      );

      // Make sure to restart watcher even if rename fails
      await _directoryWatcher.startWatching(state.currentPath.path);
    }
  }

  // Handle reloading the current folder
  void _onFolderListReloadCurrentFolder(
    FolderListReloadCurrentFolder event,
    Emitter<FolderListState> emit,
  ) async {
    // Only proceed if we have a valid current path
    if (state.currentPath.path.isNotEmpty) {
      // Use the optimized refresh that doesn't reset scroll position
      _refreshTagsOnly(state.currentPath.path, emit);
    }
  }

  // Handle deleting a tag globally
  void _onFolderListDeleteTagGlobally(
    FolderListDeleteTagGlobally event,
    Emitter<FolderListState> emit,
  ) async {
    try {
      // Delete the tag from all files in the system
      await TagManager.deleteTagGlobally(event.tag);

      // Clear tag cache to ensure fresh data
      TagManager.clearCache();

      // Notify with special path to indicate global tag deletion
      TagManager.instance.notifyTagChanged("global:tag_deleted");

      // Refresh the current directory view
      if (state.currentPath.path.isNotEmpty) {
        add(FolderListRefresh(state.currentPath.path,
            forceRegenerateThumbnails: true));
      }
    } catch (e) {
      debugPrint('Error deleting tag globally: $e');
      // No state update needed as we'll refresh the entire view
    }
  }

  // Handler for filename search
  void _onSearchByFileName(
    SearchByFileName event,
    Emitter<FolderListState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));

    try {
      final String query = event.query.toLowerCase();
      RegExp? regexPattern;
      if (event.useRegex) {
        try {
          regexPattern = RegExp(
            event.query,
            caseSensitive: false,
            unicode: true,
          );
        } on FormatException catch (e) {
          emit(state.copyWith(
            isLoading: false,
            error: 'Invalid regex pattern: ${e.message}',
          ));
          return;
        }
      }
      final List<FileSystemEntity> searchResults = [];

      if (event.recursive) {
        // Recursive search in current directory and subdirectories
        final currentDir = Directory(state.currentPath.path);

        debugPrint('🔍 Starting recursive search in: ${currentDir.path}');
        debugPrint('🔍 Query: "$query"');

        int scannedCount = 0;
        int matchedCount = 0;
        int errorCount = 0;

        // Use manual recursive search to handle permission errors gracefully
        await _recursiveSearch(
          currentDir,
          query,
          searchResults,
          (scanned, matched, errors) {
            scannedCount = scanned;
            matchedCount = matched;
            errorCount = errors;

            // Log progress every 100 items
            if (scannedCount % 100 == 0) {
              debugPrint(
                  '🔍 Scanned: $scannedCount, Matched: $matchedCount, Errors: $errorCount');
            }
          },
          regexPattern,
        );

        debugPrint(
            '🔍 Search complete! Scanned: $scannedCount, Matched: $matchedCount, Errors: $errorCount');
      } else {
        // Search in current directory only (both files and folders)
        final allFiles = state.files;
        final allFolders = state.folders;

        // Search in files
        for (var file in allFiles) {
          final fileName = pathlib.basename(file.path);
          final bool isMatch = regexPattern != null
              ? regexPattern.hasMatch(fileName)
              : TextUtils.matchesVietnamese(fileName, query);
          if (isMatch) {
            searchResults.add(file);
          }
        }

        // Search in folders
        for (var folder in allFolders) {
          final folderName = pathlib.basename(folder.path);
          final bool isMatch = regexPattern != null
              ? regexPattern.hasMatch(folderName)
              : TextUtils.matchesVietnamese(folderName, query);
          if (isMatch) {
            searchResults.add(folder);
          }
        }
      }

      final groupedResults = <FileSystemEntity>[
        ...searchResults.whereType<Directory>(),
        ...searchResults.where((e) => e is! Directory && e is! File),
        ...searchResults.whereType<File>(),
      ];

      // Update state with search results
      emit(state.copyWith(
        isLoading: false,
        searchResults: groupedResults,
        currentSearchQuery: event.query,
        currentSearchTag: null, // Clear any previous tag search
        searchRecursive: event.recursive,
        error: searchResults.isEmpty
            ? 'No files or folders found matching "${event.query}"'
            : null,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Error searching: ${e.toString()}',
      ));
    }
  }

  // Helper method for recursive search that handles permission errors gracefully
  Future<void> _recursiveSearch(
    Directory dir,
    String query,
    List<FileSystemEntity> results,
    Function(int scanned, int matched, int errors) onProgress,
    RegExp? regexPattern,
  ) async {
    int scannedCount = 0;
    int matchedCount = 0;
    int errorCount = 0;

    try {
      // List current directory (non-recursive)
      await for (var entity in dir.list(recursive: false, followLinks: false)) {
        try {
          scannedCount++;

          final entityName = pathlib.basename(entity.path);

          final bool isMatch = regexPattern != null
              ? regexPattern.hasMatch(entityName)
              : TextUtils.matchesVietnamese(entityName, query);
          if (isMatch) {
            results.add(entity);
            matchedCount++;
            debugPrint('✅ Match found: ${entity.path}');
          }

          // If it's a directory, recursively search it
          if (entity is Directory) {
            try {
              await _recursiveSearch(entity, query, results, (s, m, e) {
                scannedCount += s;
                matchedCount += m;
                errorCount += e;
                onProgress(scannedCount, matchedCount, errorCount);
              }, regexPattern);
            } catch (e) {
              // Skip directories that cause errors
              errorCount++;
              debugPrint('⚠️ Skipping directory: ${entity.path} - $e');
            }
          }

          onProgress(scannedCount, matchedCount, errorCount);
        } catch (e) {
          // Skip individual entities that cause errors
          errorCount++;
          debugPrint('⚠️ Skipping entity: ${entity.path} - $e');
        }
      }
    } catch (e) {
      // Directory listing failed (permission denied, etc.)
      errorCount++;
      debugPrint('⚠️ Cannot access directory: ${dir.path} - $e');
    }
  }

  // Handler for tag search in current directory
  void _onSearchByTag(
    SearchByTag event,
    Emitter<FolderListState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));

    try {
      // Clear tag cache to ensure fresh data
      TagManager.clearCache();

      debugPrint(
          'Searching for files with tag "${event.tag}" in directory ${state.currentPath.path}');

      // Use the improved findFilesByTag method to search including subdirectories
      final List<FileSystemEntity> results = await TagManager.findFilesByTag(
        state.currentPath.path,
        event.tag,
      );

      // Log the search results for debugging
      debugPrint('Found ${results.length} results for tag: ${event.tag}');
      for (var entity in results) {
        debugPrint('  - ${entity.path}');
      }

      emit(state.copyWith(
        isLoading: false,
        searchResults: results,
        currentSearchTag: event.tag,
        currentSearchQuery: null, // Clear any previous text search
        error: results.isEmpty
            ? SearchErrorMessages.noFilesFoundTag(event.tag)
            : null,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: SearchErrorMessages.errorSearchTag(e.toString()),
        searchResults: [], // Ensure we clear results on error
      ));
    }
  }

  // Handler for global tag search
  void _onSearchByTagGlobally(
    SearchByTagGlobally event,
    Emitter<FolderListState> emit,
  ) async {
    _pendingSearchResults = [];
    emit(state.copyWith(
      isLoading: true,
      searchResults: [],
      hasMoreSearchResults: false,
      isLoadingMoreSearchResults: false,
      searchResultsTotal: null,
    ));

    try {
      // Clear tag cache to ensure fresh data
      TagManager.clearCache();

      debugPrint('Searching for files with tag "${event.tag}" globally');

      // Get results from both sources to ensure we find all files
      final List<FileSystemEntity> results =
          await TagManager.findFilesByTagGlobally(event.tag);

      // Log the search results for debugging
      debugPrint(
          'Found ${results.length} global results for tag: ${event.tag}');

      // Filter out any non-existent files or directories
      final List<FileSystemEntity> validResults = [];
      for (var entity in results) {
        try {
          if (entity is File && entity.existsSync()) {
            validResults.add(entity);
            debugPrint('  - ${entity.path}');
          }
        } catch (e) {
          debugPrint('Error checking file existence: ${entity.path} - $e');
        }
      }

      // If no results from TagManager, try directly from database
      if (validResults.isEmpty) {
        debugPrint(
            'No valid results from TagManager, trying database directly');
        try {
          final dbResults =
              await DatabaseManager.getInstance().findFilesByTag(event.tag);
          for (var path in dbResults) {
            try {
              final file = File(path);
              if (file.existsSync()) {
                validResults.add(file);
                debugPrint('  - (From DB) ${file.path}');
              }
            } catch (e) {
              debugPrint('Error checking file from DB: $path - $e');
            }
          }
        } catch (e) {
          debugPrint('Error querying database: $e');
        }
      }

      final int total = validResults.length;
      final int initialCount =
          total > _searchResultsPageSize ? _searchResultsPageSize : total;
      final initialResults = validResults.take(initialCount).toList();
      _pendingSearchResults =
          total > initialCount ? validResults.skip(initialCount).toList() : [];

      emit(state.copyWith(
        isLoading: false,
        searchResults: initialResults,
        currentSearchTag: event.tag,
        currentSearchQuery: null, // Clear any previous text search
        isGlobalSearch: true,
        hasMoreSearchResults: _pendingSearchResults.isNotEmpty,
        isLoadingMoreSearchResults: false,
        searchResultsTotal: total,
        error: validResults.isEmpty
            ? SearchErrorMessages.noFilesFoundTagGlobal(event.tag)
            : null,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: SearchErrorMessages.errorSearchTagGlobal(e.toString()),
        searchResults: [], // Ensure we clear results on error
      ));
    }
  }

  // Handler for adding tag search results
  void _onAddTagSearchResults(
    AddTagSearchResults event,
    Emitter<FolderListState> emit,
  ) {
    // Get the current search results
    final currentResults = List<FileSystemEntity>.from(state.searchResults);

    // Add the new results, avoiding duplicates
    for (final entity in event.results) {
      if (!currentResults.any((e) => e.path == entity.path)) {
        currentResults.add(entity);
      }
    }

    emit(state.copyWith(
      searchResults: currentResults,
      // Keep the current search tag and query unchanged
    ));
  }

  void _onLoadMoreSearchResults(
    LoadMoreSearchResults event,
    Emitter<FolderListState> emit,
  ) {
    if (_pendingSearchResults.isEmpty) {
      emit(
        state.copyWith(
          hasMoreSearchResults: false,
          isLoadingMoreSearchResults: false,
        ),
      );
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

    emit(
      state.copyWith(
        searchResults: currentResults,
        hasMoreSearchResults: _pendingSearchResults.isNotEmpty,
        isLoadingMoreSearchResults: false,
      ),
    );
  }

  // New handler for searching by multiple tags in current directory
  void _onSearchByMultipleTags(
    SearchByMultipleTags event,
    Emitter<FolderListState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));

    try {
      // Clear tag cache to ensure fresh data
      TagManager.clearCache();

      String tagListStr = event.tags.map((t) => '"$t"').join(', ');
      debugPrint(
          'Searching for files with multiple tags $tagListStr in directory ${state.currentPath.path}');

      // Start with all files containing the first tag
      List<FileSystemEntity> results = [];
      if (event.tags.isNotEmpty) {
        results = await TagManager.findFilesByTag(
          state.currentPath.path,
          event.tags.first,
        );
      }

      // For each additional tag, filter the results to only include files with all tags
      for (int i = 1; i < event.tags.length; i++) {
        String tag = event.tags[i];
        List<FileSystemEntity> filteredResults = [];

        for (var entity in results) {
          if (entity is File) {
            List<String> fileTags = await TagManager.getTags(entity.path);
            if (fileTags.contains(tag)) {
              filteredResults.add(entity);
            }
          }
        }

        results = filteredResults;
      }

      // Log the search results for debugging
      debugPrint(
          'Found ${results.length} results for multiple tags: $tagListStr');
      for (var entity in results) {
        debugPrint('  - ${entity.path}');
      }

      emit(state.copyWith(
        isLoading: false,
        searchResults: results,
        currentSearchTag: event.tags.join(", "), // Join tags for display
        currentSearchQuery: null, // Clear any previous text search
        error: results.isEmpty
            ? SearchErrorMessages.noFilesFoundTags(tagListStr)
            : null,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: SearchErrorMessages.errorSearchTags(e.toString()),
        searchResults: [], // Ensure we clear results on error
      ));
    }
  }

  // New handler for global search with multiple tags
  void _onSearchByMultipleTagsGlobally(
    SearchByMultipleTagsGlobally event,
    Emitter<FolderListState> emit,
  ) async {
    _pendingSearchResults = [];
    emit(state.copyWith(
      isLoading: true,
      searchResults: [],
      hasMoreSearchResults: false,
      isLoadingMoreSearchResults: false,
      searchResultsTotal: null,
    ));

    try {
      // Clear tag cache to ensure fresh data
      TagManager.clearCache();

      String tagListStr = event.tags.map((t) => '"$t"').join(', ');
      debugPrint('Searching for files with multiple tags $tagListStr globally');

      // Start with all files containing the first tag
      List<FileSystemEntity> results = [];
      if (event.tags.isNotEmpty) {
        results = await TagManager.findFilesByTagGlobally(event.tags.first);
      }

      // For each additional tag, filter the results to only include files with all tags
      for (int i = 1; i < event.tags.length; i++) {
        String tag = event.tags[i];
        List<FileSystemEntity> filteredResults = [];

        for (var entity in results) {
          if (entity is File && entity.existsSync()) {
            List<String> fileTags = await TagManager.getTags(entity.path);
            if (fileTags.contains(tag)) {
              filteredResults.add(entity);
            }
          }
        }

        results = filteredResults;
      }

      // Filter out any non-existent files
      final List<FileSystemEntity> validResults = [];
      for (var entity in results) {
        try {
          if (entity is File && entity.existsSync()) {
            validResults.add(entity);
            debugPrint('  - ${entity.path}');
          }
        } catch (e) {
          debugPrint('Error checking file existence: ${entity.path} - $e');
        }
      }

      final int total = validResults.length;
      final int initialCount =
          total > _searchResultsPageSize ? _searchResultsPageSize : total;
      final initialResults = validResults.take(initialCount).toList();
      _pendingSearchResults =
          total > initialCount ? validResults.skip(initialCount).toList() : [];

      emit(state.copyWith(
        isLoading: false,
        searchResults: initialResults,
        currentSearchTag: event.tags.join(", "), // Join tags for display
        currentSearchQuery: null, // Clear any previous text search
        isGlobalSearch: true,
        hasMoreSearchResults: _pendingSearchResults.isNotEmpty,
        isLoadingMoreSearchResults: false,
        searchResultsTotal: total,
        error: validResults.isEmpty
            ? SearchErrorMessages.noFilesFoundTagsGlobal(tagListStr)
            : null,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: SearchErrorMessages.errorSearchTagsGlobal(e.toString()),
        searchResults: [], // Ensure we clear results on error
      ));
    }
  }

  // Add handler for loading drives
  void _onFolderListLoadDrives(
    FolderListLoadDrives event,
    Emitter<FolderListState> emit,
  ) async {
    // Drives will be loaded by the DriveView's FutureBuilder directly
    // This event is primarily for BLoC state management when lazy loading
    // No need to change the state here since we're already showing skeleton UI
    // Just log the event for debugging
    debugPrint(
        'FolderListLoadDrives event received - drives will load asynchronously');
  }
}
