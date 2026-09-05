import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:cb_file_manager/helpers/files/file_icon_helper.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart'
    as nav;
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_operations_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_operations_event.dart'
    as ops;
import 'package:cb_file_manager/ui/screens/folder_list/bloc/tag_search_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/tag_search_event.dart'
    as tag;
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';
import 'package:cb_file_manager/services/archive/archive_service.dart';

/// FolderListBloc is a Facade that composes three specialized BLoCs:
///
/// - [FileNavigationBloc] — browse, sort, filter, search, view mode
/// - [FileOperationsBloc] — copy, cut, paste, delete, rename
/// - [TagSearchBloc] — tag operations, tag-based search
///
/// It re-exports the same `FolderListState` / `FolderListEvent` API
/// so all 25+ dependent files continue to work without changes.
class FolderListBloc extends Bloc<FolderListEvent, FolderListState> {
  // ── Child BLoCs ─────────────────────────────────────────────────
  late final FileNavigationBloc _navigationBloc;
  late final FileOperationsBloc _operationsBloc;
  late final TagSearchBloc _tagSearchBloc;

  // ── Subscriptions ────────────────────────────────────────────────
  StreamSubscription? _navSubscription;
  StreamSubscription? _opsSubscription;
  StreamSubscription? _tagSubscription;
  StreamSubscription? _tagChangeSubscription;

  /// Non-null while the tab is browsing inside an archive (`#archive?…`).
  /// The virtual listing is produced here, not by [FileNavigationBloc], so
  /// child-bloc state merges must not overwrite it while this is set.
  String? _archiveBrowsePath;

  FolderListBloc() : super(FolderListState('/')) {
    // ── Initialize child BLoCs ──────────────────────────────────
    _navigationBloc = FileNavigationBloc();
    _operationsBloc = FileOperationsBloc(
      navigationBloc: _navigationBloc,
      progressController: locator<OperationProgressController>(),
    );
    _tagSearchBloc = TagSearchBloc(navigationBloc: _navigationBloc);

    // ── Forward FolderListEvent → child events ───────────────────
    on<FolderListInit>(_onInit);
    on<FolderListLoad>(_onLoad);
    on<FolderListRefresh>(_onRefresh);
    on<FolderListFilter>(_onFilter);
    on<FolderListLoadDrives>(_onLoadDrives);
    on<LoadTagsFromFile>(_onLoadTagsFromFile);
    on<LoadAllTags>(_onLoadAllTags);
    on<SetViewMode>(_onSetViewMode);
    on<SetSortOption>(_onSetSortOption);
    on<SetGridZoom>(_onSetGridZoom);
    on<ClearSearchAndFilters>(_onClearSearchAndFilters);
    on<FolderListDeleteFiles>(_onDeleteFiles);
    on<FolderListDeleteItems>(_onDeleteItems);
    on<FolderListRetryDeleteAsAdministrator>(_onRetryDeleteAsAdministrator);
    on<FolderListReloadCurrentFolder>(_onReloadCurrentFolder);
    on<FolderListDeleteTagGlobally>(_onDeleteTagGlobally);
    on<CopyFile>(_onCopyFile);
    on<CopyFiles>(_onCopyFiles);
    on<CutFile>(_onCutFile);
    on<CutFiles>(_onCutFiles);
    on<PasteFile>(_onPasteFile);
    on<RenameFileOrFolder>(_onRenameFileOrFolder);
    on<SearchByFileName>(_onSearchByFileName);
    on<SearchByTag>(_onSearchByTag);
    on<SearchByTagGlobally>(_onSearchByTagGlobally);
    on<SearchByMultipleTags>(_onSearchByMultipleTags);
    on<SearchByMultipleTagsGlobally>(_onSearchByMultipleTagsGlobally);
    on<SetTagSearchResults>(_onSetTagSearchResults);
    on<AddTagSearchResults>(_onAddTagSearchResults);
    on<LoadMoreSearchResults>(_onLoadMoreSearchResults);

    // ── Listen to child BLoC state changes and merge into
    //    FolderListState ──────────────────────────────────────────
    _navSubscription = _navigationBloc.stream.listen(_onNavStateChanged);
    _opsSubscription = _operationsBloc.stream.listen(_onOpsStateChanged);
    _tagSubscription = _tagSearchBloc.stream.listen(_onTagStateChanged);

    // ── External subscriptions ────────────────────────────────────
    _tagChangeSubscription = TagManager.onTagChanged.listen(
      _onExternalTagChanged,
    );
  }

  @override
  Future<void> close() {
    _navSubscription?.cancel();
    _opsSubscription?.cancel();
    _tagSubscription?.cancel();
    _tagChangeSubscription?.cancel();
    _navigationBloc.close();
    _operationsBloc.close();
    _tagSearchBloc.close();
    return super.close();
  }

  /// Pause the underlying directory watcher subscription. Used by the tab
  /// activity manager when the bloc's tab transitions to inactive so
  /// background filesystem events don't trigger refresh work for a tab the
  /// user is not actively using.
  void pauseDirectoryWatching() {
    _navigationBloc.pauseWatching();
  }

  /// Resume the underlying directory watcher subscription. Idempotent.
  /// The actual filesystem watch handle is re-armed lazily on the next
  /// `FolderListLoad` / `FolderListRefresh` event.
  void resumeDirectoryWatching() {
    _navigationBloc.resumeWatching();
  }

  // ── Forwarding handlers ───────────────────────────────────────────

  void _onInit(FolderListInit event, Emitter<FolderListState> emit) {
    emit(state.copyWith(isLoading: true));
  }

  Future<void> _onLoad(
    FolderListLoad event,
    Emitter<FolderListState> emit,
  ) async {
    final path = event.path;
    if (ArchivePathUtils.isArchiveBrowsePath(path)) {
      await _loadArchiveBrowsePath(path, emit);
      return;
    }

    _archiveBrowsePath = null;

    // FileNavigationBloc exclusively owns the loading lifecycle. Do not emit a
    // second loading state here: duplicate drive-open events are intentionally
    // deduped by the child bloc, and a late duplicate can otherwise set this
    // facade back to loading after the child already published the listing.
    _navigationBloc.add(nav.FileNavigationLoad(path));
  }

  Future<void> _loadArchiveBrowsePath(
    String path,
    Emitter<FolderListState> emit,
  ) async {
    final location = ArchivePathUtils.parse(path);
    if (location == null) {
      _archiveBrowsePath = null;
      emit(state.copyWith(isLoading: false, error: 'Invalid archive path'));
      return;
    }

    // Claim ownership of the listing before the first await so a concurrent
    // FileNavigationBloc emit (directory watcher, in-flight scan of the folder
    // we navigated away from) cannot clobber the virtual entries.
    _archiveBrowsePath = path;

    // A repeat load of the same location (the tab listener and the opener both
    // request it) must not blank the list that is already on screen.
    final isSameLocation = state.currentPath.path == path;

    emit(
      state.copyWith(
        isLoading: true,
        isRefreshing: false,
        error: null,
        currentPath: Directory(path),
        folders: isSameLocation ? null : const [],
        files: isSameLocation ? null : const [],
        filteredFiles: const [],
        searchResults: const [],
        currentFilter: null,
        currentSearchQuery: null,
        currentSearchTag: null,
      ),
    );

    try {
      final listing = await locator<ArchiveService>().listDirectory(
        archiveFilePath: location.archiveFile,
        innerPath: location.innerPath,
        buildVirtualPath:
            ({
              required archiveFile,
              required innerPath,
              required entryName,
              required isDirectory,
            }) {
              return ArchivePathUtils.build(
                archiveFile: archiveFile,
                innerPath: innerPath,
              );
            },
      );

      // Drop the result if the user already navigated elsewhere while the
      // archive was being read.
      if (isClosed || _archiveBrowsePath != path) return;
      emit(
        state.copyWith(
          isLoading: false,
          isRefreshing: false,
          error: null,
          currentPath: Directory(path),
          folders: listing.folders,
          files: listing.files,
          filteredFiles: const [],
          searchResults: const [],
        ),
      );
    } catch (e) {
      if (isClosed || _archiveBrowsePath != path) return;
      emit(
        state.copyWith(
          isLoading: false,
          isRefreshing: false,
          error: e.toString(),
          folders: const [],
          files: const [],
        ),
      );
    }
  }

  void _onRefresh(FolderListRefresh event, Emitter<FolderListState> emit) {
    if (ArchivePathUtils.isArchiveBrowsePath(event.path)) {
      add(FolderListLoad(event.path));
      return;
    }
    _navigationBloc.add(
      nav.FileNavigationRefresh(
        event.path,
        forceRegenerateThumbnails: event.forceRegenerateThumbnails,
      ),
    );
  }

  void _onReloadCurrentFolder(
    FolderListReloadCurrentFolder event,
    Emitter<FolderListState> emit,
  ) {
    _navigationBloc.add(const nav.FileNavigationReloadCurrentFolder());
  }

  void _onFilter(FolderListFilter event, Emitter<FolderListState> emit) {
    _navigationBloc.add(nav.FileNavigationFilter(event.fileType));
  }

  void _onLoadDrives(
    FolderListLoadDrives event,
    Emitter<FolderListState> emit,
  ) {
    _archiveBrowsePath = null;
    _navigationBloc.add(const nav.FileNavigationLoadDrives());
  }

  void _onSetViewMode(SetViewMode event, Emitter<FolderListState> emit) {
    _navigationBloc.add(nav.FileNavigationSetViewMode(event.viewMode));
  }

  void _onSetGridZoom(SetGridZoom event, Emitter<FolderListState> emit) {
    _navigationBloc.add(nav.FileNavigationSetGridZoom(event.zoomLevel));
  }

  void _onClearSearchAndFilters(
    ClearSearchAndFilters event,
    Emitter<FolderListState> emit,
  ) {
    _navigationBloc.add(const nav.FileNavigationClearSearchAndFilters());
    _tagSearchBloc.add(const tag.TagSearchClearResults());
  }

  // ── File operations ───────────────────────────────────────────────

  void _onDeleteFiles(
    FolderListDeleteFiles event,
    Emitter<FolderListState> emit,
  ) {
    _operationsBloc.add(
      ops.FileOperationsDeleteFiles(event.filePaths, permanent: false),
    );
  }

  void _onDeleteItems(
    FolderListDeleteItems event,
    Emitter<FolderListState> emit,
  ) {
    _operationsBloc.add(
      ops.FileOperationsDeleteItems(
        filePaths: event.filePaths,
        folderPaths: event.folderPaths,
        permanent: event.permanent,
      ),
    );
  }

  void _onRetryDeleteAsAdministrator(
    FolderListRetryDeleteAsAdministrator event,
    Emitter<FolderListState> emit,
  ) {
    _operationsBloc.add(
      ops.FileOperationsRetryDeleteAsAdministrator(event.failedPaths),
    );
  }

  void _onCopyFile(CopyFile event, Emitter<FolderListState> emit) {
    _operationsBloc.add(ops.FileOperationsCopy([event.entity]));
  }

  void _onCopyFiles(CopyFiles event, Emitter<FolderListState> emit) {
    _operationsBloc.add(ops.FileOperationsCopy(event.entities));
  }

  void _onCutFile(CutFile event, Emitter<FolderListState> emit) {
    _operationsBloc.add(ops.FileOperationsCut([event.entity]));
  }

  void _onCutFiles(CutFiles event, Emitter<FolderListState> emit) {
    _operationsBloc.add(ops.FileOperationsCut(event.entities));
  }

  void _onPasteFile(PasteFile event, Emitter<FolderListState> emit) {
    _operationsBloc.add(ops.FileOperationsPaste(event.destinationPath));
  }

  void _onRenameFileOrFolder(
    RenameFileOrFolder event,
    Emitter<FolderListState> emit,
  ) {
    _operationsBloc.add(ops.FileOperationsRename(event.entity, event.newName));
  }

  // ── Tag operations ────────────────────────────────────────────────

  void _onLoadTagsFromFile(
    LoadTagsFromFile event,
    Emitter<FolderListState> emit,
  ) {
    _tagSearchBloc.add(tag.TagSearchLoadTagsForFile(event.filePath));
  }

  void _onLoadAllTags(LoadAllTags event, Emitter<FolderListState> emit) {
    _tagSearchBloc.add(tag.TagSearchLoadAllTags(event.directory));
  }

  void _onDeleteTagGlobally(
    FolderListDeleteTagGlobally event,
    Emitter<FolderListState> emit,
  ) {
    _tagSearchBloc.add(
      tag.TagSearchDeleteTagGlobally(event.tag, state.currentPath.path),
    );
  }

  // ── Search ──────────────────────────────────────────────────────

  void _onSearchByFileName(
    SearchByFileName event,
    Emitter<FolderListState> emit,
  ) {
    _navigationBloc.add(
      nav.FileNavigationSearchByFileName(
        event.query,
        recursive: event.recursive,
        useRegex: event.useRegex,
      ),
    );
  }

  void _onSearchByTag(SearchByTag event, Emitter<FolderListState> emit) {
    _tagSearchBloc.add(tag.TagSearchByTag(event.tag, state.currentPath.path));
  }

  void _onSearchByTagGlobally(
    SearchByTagGlobally event,
    Emitter<FolderListState> emit,
  ) {
    _tagSearchBloc.add(tag.TagSearchByTagGlobally(event.tag));
  }

  void _onSearchByMultipleTags(
    SearchByMultipleTags event,
    Emitter<FolderListState> emit,
  ) {
    _tagSearchBloc.add(
      tag.TagSearchByMultipleTags(event.tags, state.currentPath.path),
    );
  }

  void _onSearchByMultipleTagsGlobally(
    SearchByMultipleTagsGlobally event,
    Emitter<FolderListState> emit,
  ) {
    _tagSearchBloc.add(tag.TagSearchByMultipleTagsGlobally(event.tags));
  }

  void _onSetTagSearchResults(
    SetTagSearchResults event,
    Emitter<FolderListState> emit,
  ) {
    _tagSearchBloc.add(
      tag.TagSearchSetResults(
        resultPaths: event.results.map((e) => e.path).toList(),
        tagName: event.tagName,
        total: event.results.length,
      ),
    );
  }

  void _onAddTagSearchResults(
    AddTagSearchResults event,
    Emitter<FolderListState> emit,
  ) {
    // Child bloc handles this; just forward
  }

  void _onLoadMoreSearchResults(
    LoadMoreSearchResults event,
    Emitter<FolderListState> emit,
  ) {
    _navigationBloc.add(const nav.FileNavigationLoadMoreSearchResults());
  }

  void _onSetSortOption(SetSortOption event, Emitter<FolderListState> emit) {
    _navigationBloc.add(
      nav.FileNavigationSetSortOption(
        event.sortOption,
        persist: event.persist,
        folderPath: event.folderPath,
      ),
    );
  }

  // ── External tag change listener ────────────────────────────────

  void _onExternalTagChanged(String filePath) {
    if (filePath == "global:tag_deleted") {
      add(LoadAllTags(state.currentPath.path));
    } else {
      add(LoadTagsFromFile(filePath));
    }
  }

  // ── State merge handlers ─────────────────────────────────────────

  void _onNavStateChanged(FileNavigationState navState) {
    if (isClosed) return;

    // While browsing an archive the listing is owned by _loadArchiveBrowsePath.
    // Only display preferences may flow through from the navigation bloc.
    if (_archiveBrowsePath != null) {
      // ignore: invalid_use_of_visible_for_testing_member
      emit(
        state.copyWith(
          viewMode: navState.viewMode,
          sortOption: navState.sortOption,
          gridZoomLevel: navState.gridZoomLevel,
        ),
      );
      return;
    }

    final hasActiveTagSearch = state.currentSearchTag != null;

    // ignore: invalid_use_of_visible_for_testing_member
    emit(
      state.copyWith(
        isLoading: navState.isLoading,
        isRefreshing: navState.isRefreshing,
        error: navState.error,
        currentPath: navState.currentPath,
        folders: navState.folders,
        files: navState.files,
        searchResults: hasActiveTagSearch
            ? state.searchResults
            : navState.searchResults,
        hasMoreSearchResults: hasActiveTagSearch
            ? state.hasMoreSearchResults
            : navState.hasMoreSearchResults,
        isLoadingMoreSearchResults: hasActiveTagSearch
            ? state.isLoadingMoreSearchResults
            : navState.isLoadingMoreSearchResults,
        searchResultsTotal: hasActiveTagSearch
            ? state.searchResultsTotal
            : navState.searchResultsTotal,
        filteredFiles: navState.filteredFiles,
        currentFilter: navState.currentFilter,
        currentSearchQuery: hasActiveTagSearch
            ? state.currentSearchQuery
            : navState.currentSearchQuery,
        viewMode: navState.viewMode,
        sortOption: navState.sortOption,
        gridZoomLevel: navState.gridZoomLevel,
        fileStatsCache: navState.fileStatsCache,
        isSearchByName: hasActiveTagSearch
            ? state.isSearchByName
            : navState.isSearchByName,
        searchRecursive: navState.searchRecursive,
      ),
    );

    // Pre-warm extension icon cache when file listing arrives
    if (!navState.isLoading && navState.files.isNotEmpty) {
      final exts = navState.files
          .map((f) => p.extension(f.path).toLowerCase())
          .where((ext) => ext.isNotEmpty)
          .toSet();
      FileIconHelper.warmExtensionIcons(exts, size: 48);
    }
  }

  void _onOpsStateChanged(FileOperationsState opsState) {
    if (isClosed) return;
    // ignore: invalid_use_of_visible_for_testing_member
    emit(
      state.copyWith(
        error: opsState.error,
        clipboardRevision: opsState.clipboardRevision,
        retryableElevatedDeletePaths: opsState.retryableElevatedDeletePaths,
      ),
    );
  }

  void _onTagStateChanged(TagSearchState tagState) {
    if (isClosed) return;

    // Tag search does not apply inside an archive; merging its loading/error
    // flags would hide or replace the virtual listing.
    if (_archiveBrowsePath != null) {
      // ignore: invalid_use_of_visible_for_testing_member
      emit(
        state.copyWith(
          fileTags: tagState.fileTags,
          allUniqueTags: tagState.allUniqueTags,
        ),
      );
      return;
    }

    // Child tags are surfaced as virtual folders at the front of the results so
    // opening a parent tag lists its sub-tags (as folders) alongside its own
    // files, mirroring how tags behave like folders on the tag screen.
    final childTagFolders = <FileSystemEntity>[];
    final currentTag = tagState.currentSearchTag;
    if (currentTag != null && currentTag.isNotEmpty) {
      for (final child in TagHierarchyManager.instance.getChildren(
        currentTag,
      )) {
        childTagFolders.add(Directory(UriUtils.buildTagSearchPath(child)));
      }
    }

    final fileResults = tagState.searchResultPaths
        .map<FileSystemEntity>((path) => File(path))
        .toList(growable: false);

    final searchResults = <FileSystemEntity>[
      ...childTagFolders,
      ...fileResults,
    ];

    // ignore: invalid_use_of_visible_for_testing_member
    emit(
      state.copyWith(
        isLoading: tagState.isLoading,
        error: tagState.error,
        searchResults: searchResults,
        searchResultsTotal: tagState.searchResultsTotal,
        currentSearchTag: tagState.currentSearchTag,
        isGlobalSearch: tagState.isGlobalSearch,
        fileTags: tagState.fileTags,
        allUniqueTags: tagState.allUniqueTags,
      ),
    );
  }
}
