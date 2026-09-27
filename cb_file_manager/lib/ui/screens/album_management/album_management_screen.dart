import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/components/common/library_hub_scaffold.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/components/common/grid_list_collection.dart';
import 'package:cb_file_manager/ui/components/common/item_shell.dart';
import 'package:cb_file_manager/ui/widgets/compact_list_content.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/widgets/gallery_nsfw_toggle.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/utils/view_mode_spectrum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/models/objectbox/album.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
// import 'package:cb_file_manager/services/album_auto_rule_service.dart';
import 'dart:math' as math;

import 'create_album_dialog.dart';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/services/smart_album_service.dart';
import 'package:cb_file_manager/ui/components/common/skeleton_helper.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/tab_manager/components/search_bar.dart'
    as tab_components;

class AlbumManagementScreen extends StatefulWidget {
  final String tabId;
  final String rootPath;
  final String? title;
  final IconData icon;
  final bool sourceGalleryMode;

  const AlbumManagementScreen({
    super.key,
    required this.tabId,
    this.rootPath = '#albums',
    this.title,
    this.icon = PhosphorIconsLight.folder,
    this.sourceGalleryMode = false,
  });

  @override
  State<AlbumManagementScreen> createState() => _AlbumManagementScreenState();
}

class _AlbumManagementScreenState extends State<AlbumManagementScreen> {
  static const _supportedViewModes = {
    ViewMode.list,
    ViewMode.tiles,
    ViewMode.grid,
    ViewMode.details,
    ViewMode.tree,
  };
  // Migration to dependency injection: Use locator instead of .instance
  // Old way: final AlbumService _albumService = AlbumService.instance;
  // New way: Use service locator for better testability and dependency management
  final AlbumService _albumService = locator.isRegistered<AlbumService>()
      ? locator<AlbumService>()
      : AlbumService.instance;
  List<Album> _albums = [];
  final Map<int, Future<int>> _albumCountFutures = {};
  bool _isLoading = true;
  bool _showSearchBar = false;
  String _searchQuery = '';
  SortOption _sortOption = SortOption.nameAsc;
  int _gridZoomLevel = 3;
  final Set<int> _expandedTreeAlbums = {};
  late final GridListViewController _view;
  late final SelectionBloc _selectionBloc;
  late final TabbedFolderDragSelectionController _dragSelectionController;

  @override
  void initState() {
    super.initState();
    _selectionBloc = SelectionBloc();
    _dragSelectionController = TabbedFolderDragSelectionController(
      selectionBloc: _selectionBloc,
    );
    _view = GridListViewController(
      supportedModes: _supportedViewModes,
      load: () async {
        await UserPreferences.instance.init();
        return UserPreferences.instance.getGridListCollectionMode(
          'albums',
          supportedModes: _supportedViewModes,
        );
      },
      save: (mode) async {
        await UserPreferences.instance.init();
        await UserPreferences.instance.setGridListCollectionMode(
          'albums',
          mode,
        );
      },
    )..addListener(_onViewChanged);
    _loadAlbums();
    _view.initialize();
    _loadGridZoom();
  }

  Future<void> _loadGridZoom() async {
    await UserPreferences.instance.init();
    final zoom = await UserPreferences.instance.getGridZoomLevel();
    if (mounted) setState(() => _gridZoomLevel = zoom);
  }

  Future<void> _setGridZoom(int zoom) async {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(context);
    final resolved = zoom
        .clamp(UserPreferences.minGridZoomLevel, maxZoom)
        .toInt();
    if (resolved == _gridZoomLevel) return;
    setState(() => _gridZoomLevel = resolved);
    await UserPreferences.instance.setGridZoomLevel(resolved);
  }

  void _handleViewScaleDelta(int delta) {
    if (delta == 0) return;
    final result = ViewModeSpectrum.step(
      currentMode: _view.mode,
      currentZoom: _gridZoomLevel,
      supported: const {
        ViewMode.tree,
        ViewMode.details,
        ViewMode.list,
        ViewMode.tiles,
      },
      delta: delta,
      minZoom: UserPreferences.minGridZoomLevel,
      maxZoom: GridZoomConstraints.maxGridSizeForContext(context),
    );
    if (result.mode != _view.mode) _view.select(result.mode);
    if (result.gridZoomLevel != _gridZoomLevel) {
      _setGridZoom(result.gridZoomLevel);
    }
  }

  void _onViewChanged() {
    if (mounted) setState(() {});
  }

  List<Album> get _visibleAlbums {
    final query = _searchQuery.trim().toLowerCase();
    final albums = _albums.where((album) {
      if (query.isEmpty) return true;
      return album.name.toLowerCase().contains(query) ||
          (album.description?.toLowerCase().contains(query) ?? false);
    }).toList();
    albums.sort((a, b) {
      final result = switch (_sortOption) {
        SortOption.nameDesc => b.name.toLowerCase().compareTo(
          a.name.toLowerCase(),
        ),
        SortOption.dateAsc => a.modifiedAt.compareTo(b.modifiedAt),
        SortOption.dateDesc => b.modifiedAt.compareTo(a.modifiedAt),
        SortOption.dateCreatedAsc => a.createdAt.compareTo(b.createdAt),
        SortOption.dateCreatedDesc => b.createdAt.compareTo(a.createdAt),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      return result == 0 ? a.id.compareTo(b.id) : result;
    });
    return albums;
  }

  void _toggleSearchBar() => setState(() => _showSearchBar = !_showSearchBar);

  void _closeSearchBar() => setState(() => _showSearchBar = false);

  void _setSearchQuery(String value) => setState(() => _searchQuery = value);

  void _setSortOption(SortOption option) =>
      setState(() => _sortOption = option);

  void _toggleSelectionMode() {
    _selectionBloc.add(
      ToggleSelectionMode(forceValue: !_selectionBloc.state.isSelectionMode),
    );
  }

  @override
  void dispose() {
    _view.removeListener(_onViewChanged);
    _view.dispose();
    _dragSelectionController.dispose();
    _selectionBloc.close();
    super.dispose();
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final albums = await _albumService.getAllAlbums();
      if (mounted) {
        setState(() {
          _albums = albums;
          _albumCountFutures
            ..clear()
            ..addEntries(
              albums.map(
                (album) => MapEntry(album.id, _getAlbumImageCount(album)),
              ),
            );
          final available = albums.map(_albumPath).toSet();
          if (!_selectionBloc.state.selectedFilePaths.every(
            available.contains,
          )) {
            _selectionBloc.add(ClearSelection());
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading albums: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCreateAlbumDialog() async {
    final result = await RouteUtils.showAcrylicDialog<Album>(
      context: context,
      builder: (context) =>
          CreateAlbumDialog(sourceMode: widget.sourceGalleryMode),
    );

    if (result != null) {
      await _loadAlbums();
    }
  }

  Future<void> _showEditAlbumDialog(Album album) async {
    final result = await RouteUtils.showAcrylicDialog<Album>(
      context: context,
      builder: (context) => CreateAlbumDialog(
        editingAlbum: album,
        sourceMode: widget.sourceGalleryMode,
      ),
    );
    if (result != null) await _loadAlbums();
  }

  Future<void> _toggleAlbumNsfw(Album album) async {
    final success = await _albumService.updateAlbum(
      album.copyWith(isNsfw: !album.isNsfw),
    );
    if (!mounted) return;
    if (success) {
      await _loadAlbums();
    } else {
      AppToast.error(context, AppLocalizations.of(context)!.operationFailed);
    }
  }

  String _albumPath(Album album) => '#album/${album.id}';

  void _clearSelection() => _selectionBloc.add(ClearSelection());

  void _selectAlbum(Album album) {
    final keyboard = HardwareKeyboard.instance;
    final isCtrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final isShift = keyboard.isShiftPressed;
    final albumPath = _albumPath(album);
    final anchor = _selectionBloc.state.lastSelectedPath;

    if (isShift && anchor != null) {
      final visibleAlbums = _visibleAlbums;
      final anchorIndex = visibleAlbums.indexWhere(
        (candidate) => _albumPath(candidate) == anchor,
      );
      final targetIndex = visibleAlbums.indexOf(album);
      if (anchorIndex >= 0 && targetIndex >= 0) {
        final start = math.min(anchorIndex, targetIndex);
        final end = math.max(anchorIndex, targetIndex);
        _selectionBloc.add(
          SelectItemsInRect(
            folderPaths: const {},
            filePaths: visibleAlbums
                .sublist(start, end + 1)
                .map(_albumPath)
                .toSet(),
            isCtrlPressed: isCtrl,
            isShiftPressed: true,
            lastSelectedPath: albumPath,
          ),
        );
        return;
      }
    }

    _selectionBloc.add(ToggleFileSelection(albumPath, ctrlSelect: isCtrl));
  }

  void _selectAllAlbums() {
    _selectionBloc.add(
      SelectAll(
        allFilePaths: _visibleAlbums.map(_albumPath).toList(),
        allFolderPaths: const [],
      ),
    );
  }

  List<Album> get _selectedAlbums {
    final selected = _selectionBloc.state.selectedFilePaths;
    return _albums
        .where((album) => selected.contains(_albumPath(album)))
        .toList();
  }

  Future<void> _deleteAlbum(Album album) => _deleteAlbums([album]);

  Future<void> _deleteSelectedAlbums({required bool permanent}) async {
    await _deleteAlbums(_selectedAlbums);
  }

  Future<void> _deleteAlbums(List<Album> albums) async {
    if (albums.isEmpty) return;
    final confirmed = await RouteUtils.showAcrylicDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteAlbum),
        content: Text(
          albums.length == 1
              ? 'Are you sure you want to delete the album "${albums.single.name}"? This action cannot be undone.'
              : 'Are you sure you want to delete ${albums.length} albums? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final results = await Future.wait(
        albums.map((album) => _albumService.deleteAlbum(album.id)),
      );
      final successCount = results.where((success) => success).length;
      if (successCount > 0) {
        _clearSelection();
        await _loadAlbums();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                successCount == 1
                    ? 'Album deleted successfully'
                    : '$successCount albums deleted successfully',
              ),
            ),
          );
        }
      }
      if (successCount != albums.length && mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to delete ${albums.length - successCount} album(s)',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<int> _getAlbumImageCount(Album album) async {
    try {
      final isSmart = await SmartAlbumService.instance.isSmartAlbum(album.id);
      if (isSmart) {
        final cached = await SmartAlbumService.instance.getCachedFiles(
          album.id,
        );
        return cached.length;
      }
      return await _albumService.getAlbumImageCount(album.id);
    } catch (_) {
      return 0;
    }
  }

  // Removed auto rule processing from listing screen as requested

  void _openAlbum(Album album) {
    final tabBloc = context.read<TabManagerBloc>();
    final activeTab = tabBloc.state.tabs
        .where((tab) => tab.id == widget.tabId)
        .firstOrNull;
    final path = '#album/${album.id}';
    if (activeTab != null) {
      TabNavigator.updateTabPath(context, activeTab.id, path);
      tabBloc.add(UpdateTabName(activeTab.id, album.name));
    } else {
      tabBloc.add(AddTab(path: path, name: album.name, switchToTab: true));
    }
  }

  Widget _buildAlbumCard(Album album) {
    return _buildAlbumListShell(
      album,
      CompactListContent(
        leading: SizedBox(
          width: 28,
          height: 28,
          child: _buildAlbumCover(album),
        ),
        label: Text(
          album.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: SizedBox(
          width: 36,
          height: 36,
          child: _buildAlbumMenu(album),
        ),
      ),
    );
  }

  Widget _buildAlbumListShell(Album album, Widget child) {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final isSelected = _selectionBloc.state.selectedFilePaths.contains(
      _albumPath(album),
    );
    return ListItemShell(
      key: ValueKey('album-${album.id}'),
      isSelected: isSelected,
      isSelectionMode: !isDesktop && _selectionBloc.state.isSelectionMode,
      isDesktopMode: isDesktop,
      onTap: isDesktop ? () => _selectAlbum(album) : () => _openAlbum(album),
      onDoubleTap: isDesktop ? () => _openAlbum(album) : null,
      onToggleSelection: () => _selectAlbum(album),
      onEnterSelectionMode: () => _selectAlbum(album),
      onSecondaryTapUp: (details) =>
          _showAlbumContextMenu(album, details.globalPosition),
      borderRadius: BorderRadius.circular(8),
      padding: EdgeInsets.zero,
      child: child,
    );
  }

  Widget _buildAlbumTile(Album album) {
    return _buildAlbumListShell(
      album,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: _buildAlbumCover(album),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  FutureBuilder<int>(
                    future: _getAlbumImageCount(album),
                    builder: (_, snapshot) => Text(
                      '${snapshot.data ?? 0} images',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            _buildAlbumMenu(album),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsHeader(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.center,
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('Name', style: style)),
          Expanded(child: Text('Images', style: style)),
          Expanded(child: Text('Privacy', style: style)),
          Expanded(flex: 2, child: Text('Modified', style: style)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildAlbumDetailsRow(Album album) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return _buildAlbumListShell(
      album,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            SizedBox(width: 28, height: 28, child: _buildAlbumCover(album)),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(album.name, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              child: FutureBuilder<int>(
                future: _getAlbumImageCount(album),
                builder: (_, snapshot) => Text('${snapshot.data ?? 0}'),
              ),
            ),
            Expanded(
              child: Text(
                album.isNsfw ? 'NSFW' : 'Public',
                style: TextStyle(color: secondary),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _formatDate(album.modifiedAt),
                style: TextStyle(color: secondary),
              ),
            ),
            SizedBox(width: 40, child: _buildAlbumMenu(album)),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Widget _buildAlbumTreeItem(Album album) {
    return FutureBuilder(
      future: _albumService.getAlbumConfig(album.id),
      builder: (context, snapshot) {
        final directories = snapshot.data?.directoriesList ?? const <String>[];
        final expanded = _expandedTreeAlbums.contains(album.id);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAlbumListShell(
              album,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    IconButton(
                      key: ValueKey('album-tree-toggle-${album.id}'),
                      visualDensity: VisualDensity.compact,
                      onPressed: directories.isEmpty
                          ? null
                          : () => setState(() {
                              expanded
                                  ? _expandedTreeAlbums.remove(album.id)
                                  : _expandedTreeAlbums.add(album.id);
                            }),
                      icon: Icon(
                        expanded
                            ? PhosphorIconsLight.caretDown
                            : PhosphorIconsLight.caretRight,
                        size: 15,
                      ),
                    ),
                    const Icon(PhosphorIconsLight.folder, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        album.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (directories.isNotEmpty)
                      Text(
                        '${directories.length} source${directories.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    _buildAlbumMenu(album),
                  ],
                ),
              ),
            ),
            if (expanded)
              for (final directory in directories)
                Padding(
                  padding: const EdgeInsets.only(left: 48, right: 8),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      PhosphorIconsLight.folderOpen,
                      size: 18,
                    ),
                    title: Text(directory, overflow: TextOverflow.ellipsis),
                    onTap: () => TabNavigator.updateTabPath(
                      context,
                      widget.tabId,
                      directory,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Future<void> _handleAlbumMenuAction(Album album, String value) async {
    if (value == 'edit') await _showEditAlbumDialog(album);
    if (value == 'set_cover') await _showPickCoverDialog(album);
    if (value == 'random_cover') {
      final files = await _albumService.getAlbumFiles(album.id);
      if (files.isNotEmpty) {
        final chosen = files[math.Random().nextInt(files.length)];
        await _albumService.updateAlbum(
          album.copyWith(coverImagePath: chosen.filePath),
        );
        await _loadAlbums();
      }
    }
    if (value == 'nsfw') await _toggleAlbumNsfw(album);
    if (value == 'delete') await _deleteAlbum(album);
  }

  List<PopupMenuEntry<String>> _albumMenuItems(Album album) => [
    PopupMenuItem(
      value: 'edit',
      child: Text(widget.sourceGalleryMode ? 'Source settings' : 'Edit album'),
    ),
    galleryNsfwMenuItem(context, album.isNsfw),
    const PopupMenuItem(value: 'set_cover', child: Text('Set Cover…')),
    const PopupMenuItem(value: 'random_cover', child: Text('Random Cover')),
    PopupMenuItem(
      value: 'delete',
      child: Text(
        AppLocalizations.of(context)!.delete,
        style: const TextStyle(color: Colors.red),
      ),
    ),
  ];

  Future<void> _showAlbumContextMenu(Album album, Offset position) async {
    if (!_selectionBloc.state.selectedFilePaths.contains(_albumPath(album))) {
      _selectionBloc.add(ToggleFileSelection(_albumPath(album)));
    }
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, 0, 0),
      items: _albumMenuItems(album),
    );
    if (value != null) await _handleAlbumMenuAction(album, value);
  }

  Widget _buildAlbumMenu(Album album) => PopupMenuButton<String>(
    tooltip: 'Album options',
    onSelected: (value) => _handleAlbumMenuAction(album, value),
    itemBuilder: (_) => _albumMenuItems(album),
  );

  List<Widget> _buildToolbarActions(
    BuildContext context,
    SelectionState selection,
    AppLocalizations l10n,
  ) {
    final actions = SharedActionBar.buildCommonActions(
      context: context,
      onSearchPressed: _toggleSearchBar,
      isSearchActive: _showSearchBar,
      onSortOptionSelected: _setSortOption,
      currentSortOption: _sortOption,
      allowedSortOptions: const {
        SortOption.nameAsc,
        SortOption.nameDesc,
        SortOption.dateAsc,
        SortOption.dateDesc,
        SortOption.dateCreatedAsc,
        SortOption.dateCreatedDesc,
      },
      viewMode: _view.mode,
      onViewModeToggled: () => _view.select(
        _view.mode == ViewMode.grid ? ViewMode.list : ViewMode.grid,
      ),
      onViewModeSelected: _view.select,
      onRefresh: _loadAlbums,
      currentGridZoomLevel: _view.mode == ViewMode.grid ? _gridZoomLevel : null,
      onGridZoomChanged: _setGridZoom,
      onSelectionModeToggled: _toggleSelectionMode,
    );
    actions.insert(
      actions.length - 1,
      CbButton.icon(
        key: ValueKey(
          widget.sourceGalleryMode ? 'create-image-source' : 'create-album',
        ),
        icon: PhosphorIconsLight.plus,
        tooltip: l10n.create,
        onPressed: _showCreateAlbumDialog,
      ),
    );
    return [
      if (selection.isSelectionMode) ...[
        CbButton.icon(
          key: const ValueKey('albums-delete-selection'),
          icon: PhosphorIconsLight.trash,
          tooltip: l10n.delete,
          onPressed: () => _deleteSelectedAlbums(permanent: false),
        ),
        CbButton.icon(
          key: const ValueKey('albums-clear-selection'),
          icon: PhosphorIconsLight.x,
          tooltip: l10n.cancel,
          onPressed: _clearSelection,
        ),
      ],
      ...actions,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocProvider.value(
      value: _selectionBloc,
      child: BlocBuilder<SelectionBloc, SelectionState>(
        builder: (context, selection) {
          final albums = _visibleAlbums;
          return LibraryHubScaffold(
            tabId: widget.tabId,
            path: widget.rootPath,
            title: widget.title ?? l10n.albums,
            icon: widget.icon,
            viewMode: _view.mode,
            enablePathEditing: true,
            onViewScaleDelta: _handleViewScaleDelta,
            onRefresh: _loadAlbums,
            showRefreshAction: false,
            showSearchBar: _showSearchBar,
            searchBar: tab_components.SearchBar(
              currentPath: widget.rootPath,
              tabId: widget.tabId,
              initialQuery: _searchQuery,
              hintText: widget.sourceGalleryMode
                  ? 'Search image sources'
                  : 'Search albums',
              onQueryChanged: _setSearchQuery,
              onClearSearch: () => _setSearchQuery(''),
              onCloseSearch: _closeSearchBar,
              showTipsButton: false,
              showTagSearch: false,
              showGlobalSearchToggle: false,
              showRegexToggle: false,
            ),
            selectionState: selection,
            onClearSelection: _clearSelection,
            onSelectAll: _selectAllAlbums,
            onDelete: _deleteSelectedAlbums,
            onEscape: selection.isSelectionMode
                ? _clearSelection
                : _showSearchBar
                ? _closeSearchBar
                : null,
            breadcrumbSegments: [
              BreadcrumbSegment(
                label: widget.title ?? l10n.albums,
                icon: widget.icon,
              ),
            ],
            actions: _buildToolbarActions(context, selection, l10n),
            body: _isLoading
                ? SkeletonHelper.responsive(
                    isGridView: _view.mode == ViewMode.grid,
                    isAlbum: true,
                    crossAxisCount: 3,
                    itemCount: 12,
                  )
                : albums.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIconsLight.imageSquare,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.trim().isNotEmpty
                              ? 'No matching results'
                              : widget.sourceGalleryMode
                              ? 'No image sources yet'
                              : 'No albums yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.sourceGalleryMode
                              ? 'Add a source to browse images from its folders'
                              : 'Create your first album to organize your images',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_searchQuery.trim().isEmpty) ...[
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _showCreateAlbumDialog,
                            icon: const Icon(PhosphorIconsLight.plus),
                            label: Text(
                              widget.sourceGalleryMode
                                  ? 'Create Image Source'
                                  : 'Create Album',
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : GridListCollection<Album>(
                    mode: _view.mode,
                    items: albums,
                    isDesktop:
                        Platform.isWindows ||
                        Platform.isLinux ||
                        Platform.isMacOS,
                    identity: _albumPath,
                    onRefresh: _loadAlbums,
                    supportedModes: _supportedViewModes,
                    gridZoomLevel: _gridZoomLevel,
                    gridAspectRatio: 1.28,
                    gridMinExtent: 132,
                    gridMaxExtent: 260,
                    detailsHeader: _buildDetailsHeader(context),
                    dragSelectionController: _dragSelectionController,
                    onBackgroundTap: selection.isSelectionMode
                        ? _clearSelection
                        : null,
                    itemBuilder: (_, album, mode) => switch (mode) {
                      ViewMode.grid => _buildAlbumGridTile(album),
                      ViewMode.tiles => _buildAlbumTile(album),
                      ViewMode.details => _buildAlbumDetailsRow(album),
                      ViewMode.tree => _buildAlbumTreeItem(album),
                      _ => _buildAlbumCard(album),
                    },
                  ),
          );
        },
      ),
    );
  }

  Widget _buildAlbumGridTile(Album album) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final isSelected = _selectionBloc.state.selectedFilePaths.contains(
      _albumPath(album),
    );
    return GridItemShell(
      key: ValueKey('album-${album.id}'),
      isSelected: isSelected,
      isSelectionMode: !isDesktop && _selectionBloc.state.isSelectionMode,
      isDesktopMode: isDesktop,
      onTap: isDesktop ? () => _selectAlbum(album) : () => _openAlbum(album),
      onDoubleTap: isDesktop ? () => _openAlbum(album) : null,
      onToggleSelection: () => _selectAlbum(album),
      onEnterSelectionMode: () => _selectAlbum(album),
      onSecondaryTapUp: (details) =>
          _showAlbumContextMenu(album, details.globalPosition),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withValues(
            alpha: isDesktop ? 0.72 : 1,
          ),
          borderRadius: CbRadii.mdAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildAlbumCover(album),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Wrap(
                      spacing: 6,
                      children: [
                        if (widget.sourceGalleryMode)
                          _buildAlbumBadge(
                            icon: PhosphorIconsLight.folderOpen,
                            label: 'Source',
                          ),
                        if (album.isNsfw)
                          _buildAlbumBadge(
                            icon: PhosphorIconsLight.eyeSlash,
                            label: 'NSFW',
                            color: colors.error,
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.48),
                        shape: BoxShape.circle,
                      ),
                      child: PopupMenuButton<String>(
                        tooltip: 'Album options',
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          PhosphorIconsLight.dotsThreeVertical,
                          size: 18,
                          color: Colors.white,
                        ),
                        onSelected: (value) async {
                          await _handleAlbumMenuAction(album, value);
                        },
                        itemBuilder: (context) => _albumMenuItems(album),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          album.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FutureBuilder<int>(
                        future: _albumCountFutures.putIfAbsent(
                          album.id,
                          () => _getAlbumImageCount(album),
                        ),
                        builder: (context, snapshot) =>
                            _buildAlbumCount(context, snapshot.data),
                      ),
                    ],
                  ),
                  if (album.description?.trim().isNotEmpty ?? false) ...[
                    const SizedBox(height: 3),
                    Text(
                      album.description!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumCover(Album album) {
    final placeholder = _buildAlbumCoverPlaceholder(album);
    // If explicit cover is set and exists, show it
    if (album.coverImagePath != null &&
        File(album.coverImagePath!).existsSync()) {
      return Image.file(
        File(album.coverImagePath!),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }

    // Otherwise pick a deterministic "random" file from album images
    return FutureBuilder(
      future: _albumService.getAlbumFileInfos(album.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SkeletonHelper.box(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(16),
          );
        }
        final files = (snapshot.data as List?) ?? [];
        if (files.isEmpty) {
          return placeholder;
        }
        final idx = album.id % files.length;
        final imagePath = files[idx].path as String;
        if (!File(imagePath).existsSync()) {
          return placeholder;
        }
        return Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stackTrace) => placeholder,
        );
      },
    );
  }

  Widget _buildAlbumCoverPlaceholder(Album album) {
    final colors = Theme.of(context).colorScheme;
    final accent = _albumAccentColor(album, colors.primary);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              accent.withValues(alpha: 0.18),
              colors.surfaceContainerHigh,
            ),
            Color.alphaBlend(
              accent.withValues(alpha: 0.06),
              colors.surfaceContainer,
            ),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.56),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          widget.sourceGalleryMode
              ? PhosphorIconsLight.folderOpen
              : PhosphorIconsLight.images,
          size: 26,
          color: accent,
        ),
      ),
    );
  }

  Color _albumAccentColor(Album album, Color fallback) {
    final raw = album.colorTheme?.replaceFirst('#', '');
    if (raw == null) return fallback;
    final value = int.tryParse(raw, radix: 16);
    if (value == null) return fallback;
    return Color(raw.length <= 6 ? 0xff000000 | value : value);
  }

  Widget _buildAlbumBadge({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final badgeColor = color ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: badgeColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumCount(BuildContext context, int? count) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    if (count == null) {
      return SkeletonHelper.box(
        width: 34,
        height: 14,
        borderRadius: BorderRadius.circular(4),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(PhosphorIconsLight.image, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }

  Future<void> _showPickCoverDialog(Album album) async {
    final files = await _albumService.getAlbumFiles(album.id);
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No images to pick as cover')),
        );
      }
      return;
    }

    String? selected;
    if (mounted) {
      await RouteUtils.showAcrylicDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Choose Cover Image'),
            content: SizedBox(
              width: 600,
              height: 400,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final p = files[index].filePath;
                  return GestureDetector(
                    onTap: () {
                      selected = p;
                      Navigator.of(context).pop();
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(p),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(PhosphorIconsLight.imageBroken),
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    }

    if (selected != null) {
      final updated = album.copyWith(coverImagePath: selected);
      await _albumService.updateAlbum(updated);
      _loadAlbums();
    }
  }
}
