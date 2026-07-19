import 'dart:io';
import 'dart:async';
import 'dart:math' show min, max;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/models/objectbox/album.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/ui/utils/base_screen.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/image_viewer_screen.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/ui/widgets/app_progress_indicator.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'create_album_dialog.dart';
import 'batch_add_dialog.dart';
import 'package:path/path.dart' as pathlib;
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_action_handlers.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/services/smart_album_service.dart';
import 'package:cb_file_manager/services/album_auto_rule_service.dart';
import 'auto_rules_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/utils/view_mode_spectrum.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/components/common/file_view_shell.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/widgets/selection_summary_tooltip.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';

// Selection BLoC + drag-selection
import 'package:cb_file_manager/bloc/selection/selection_bloc.dart';
import 'package:cb_file_manager/bloc/selection/selection_event.dart';
import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'album_drag_selection_controller.dart';
import 'album_image_tile.dart';
import 'package:cb_file_manager/ui/widgets/slim_progress_bar.dart';

class AlbumDetailScreen extends StatefulWidget {
  final Album album;

  const AlbumDetailScreen({
    Key? key,
    required this.album,
  }) : super(key: key);

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final AlbumService _albumService = AlbumService.instance;

  // ── File data ──────────────────────────────────────────────────────────────
  List<File> _imageFiles = [];
  List<File> _originalImageFiles = [];
  bool _isLoading = true;
  // Grid zoom level — uses the SAME key, range, and column-count formula
  // as the main file browser so that the same setting produces identical
  // column density on every screen.
  int _gridZoomLevel = UserPreferences.defaultGridZoomLevel;
  String? _searchQuery;
  bool _isShuffled = false;
  late UserPreferences _preferences;

  // ── Grid scroll state ─────────────────────────────────────────────────────
  final ScrollController _gridScrollController = ScrollController();

  // ── Smart album state ──────────────────────────────────────────────────────
  bool _isSmartAlbum = false;
  bool _cancelSmartScan = false;
  // Tracks whether cached files were loaded so we skip redundant scans on revisit.
  // Since SmartAlbumService now has an in-memory scan cache, re-entering the
  // screen can populate files from cache without any disk I/O.
  bool _cachedFilesLoaded = false;
  Timer? _autoRescanTimer;
  int _activeRulesCount = 0;
  int _sourceFoldersCount = 0;
  DateTime? _lastScanTime;

  // ── Stream subscriptions ───────────────────────────────────────────────────
  StreamSubscription<int>? _albumUpdateSub;
  StreamSubscription<Map<String, dynamic>>? _progressSub;
  Timer? _refreshDebounce;

  // ── Background progress ────────────────────────────────────────────────────
  bool _isBackgroundProcessing = false;
  int _currentProgress = 0;
  int _totalProgress = 0;
  String _progressStatus = '';
  Timer? _progressDebounce;

  // ── Selection — using the shared SelectionBloc + drag controller ──────────
  late SelectionBloc _selectionBloc;
  late AlbumDragSelectionController _dragController;

  // ---------------------------------------------------------------------------
  // Life-cycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _selectionBloc = SelectionBloc();
    _dragController =
        AlbumDragSelectionController(selectionBloc: _selectionBloc);
    _preferences = UserPreferences.instance;
    _loadGridPreference();
    _initSmartStateAndLoad();
    _albumUpdateSub = AlbumService.instance.albumUpdatedStream
        .where((id) => id == widget.album.id)
        .listen((_) => _scheduleAlbumReload());

    _progressSub = AlbumService.instance.progressStream
        .where((p) => p['albumId'] == widget.album.id)
        .listen(_handleProgressUpdate);
  }

  @override
  void dispose() {
    _selectionBloc.close();
    _dragController.dispose();
    _gridScrollController.dispose();
    _albumUpdateSub?.cancel();
    _progressSub?.cancel();
    _refreshDebounce?.cancel();
    _progressDebounce?.cancel();
    _autoRescanTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Selection helpers — mirrors SelectionCoordinator logic
  // ---------------------------------------------------------------------------

  /// Toggle a file with full Shift/Ctrl support + range selection.
  void _toggleFileSelection(
    String filePath, {
    bool shiftSelect = false,
    bool ctrlSelect = false,
  }) {
    if (!shiftSelect) {
      _selectionBloc.add(ToggleFileSelection(
        filePath,
        shiftSelect: false,
        ctrlSelect: ctrlSelect,
      ));
      return;
    }

    // Shift+click: range selection over the visible _imageFiles list.
    final sel = _selectionBloc.state;
    if (sel.lastSelectedPath == null) {
      _selectionBloc.add(ToggleFileSelection(
        filePath,
        shiftSelect: false,
        ctrlSelect: ctrlSelect,
      ));
      return;
    }

    final allPaths = _imageFiles.map((f) => f.path).toList();
    final curIdx = allPaths.indexOf(filePath);
    final lastIdx = allPaths.indexOf(sel.lastSelectedPath!);

    if (curIdx != -1 && lastIdx != -1) {
      final start = min(curIdx, lastIdx);
      final end = max(curIdx, lastIdx);
      _selectionBloc.add(SelectItemsInRect(
        folderPaths: const {},
        filePaths: allPaths.sublist(start, end + 1).toSet(),
        isCtrlPressed: ctrlSelect,
        isShiftPressed: true,
      ));
    }
  }

  void _clearSelection() => _selectionBloc.add(ClearSelection());

  void _selectAll() {
    _selectionBloc.add(SelectAll(
      allFilePaths: _imageFiles.map((f) => f.path).toList(),
      allFolderPaths: const [],
    ));
  }

  // ---------------------------------------------------------------------------
  // Album-specific actions
  // ---------------------------------------------------------------------------

  Future<void> _removeSelectedFiles(Set<String> selectedPaths) async {
    if (selectedPaths.isEmpty || !mounted) return;

    final count = selectedPaths.length;
    final confirmed = await BrowserLikeActionHandlers.showConfirmationDialog(
      context: context,
      showDialogWithWidget: (dialogContext, dialog) =>
          RouteUtils.showAcrylicDialog<bool>(
        context: dialogContext,
        builder: (_) => dialog,
      ),
      dialog: AlertDialog(
        title: Text('Remove $count ${count == 1 ? 'image' : 'images'}?'),
        content: const Text(
          'Remove selected images from this album? The original files will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed) {
      final successCount =
          await BrowserLikeActionHandlers.runBatchOperation<String>(
        items: selectedPaths,
        operation: (filePath) =>
            _albumService.removeFileFromAlbum(widget.album.id, filePath),
      );
      _clearSelection();
      await _loadAlbumFiles();

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppToast.success(context, l10n.removedFromAlbum(successCount));
      }
    }
  }

  Future<void> _deleteSelectedFilesFromDisk(Set<String> selectedPaths) async {
    if (selectedPaths.isEmpty || !mounted) return;
    await BrowserLikeActionHandlers.confirmAndMoveFilesToTrash(
      context: context,
      filePaths: selectedPaths.toList(),
      showDialogWithWidget: (dialogContext, dialog) =>
          RouteUtils.showAcrylicDialog<bool>(
        context: dialogContext,
        builder: (_) => dialog,
      ),
      onMoved: (filePath) =>
          _albumService.removeFileFromAlbum(widget.album.id, filePath),
      onAfterSuccess: (_) async {
        _clearSelection();
        await _loadAlbumFiles();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Initialization helpers
  // ---------------------------------------------------------------------------

  Future<void> _initSmartStateAndLoad() async {
    try {
      _isSmartAlbum =
          await SmartAlbumService.instance.isSmartAlbum(widget.album.id);
    } catch (_) {
      _isSmartAlbum = false;
    }
    if (mounted) {
      if (_isSmartAlbum) {
        await _refreshSmartStatus();
        await _loadCachedSmartImages();
        _startAutoRescan();
      }
      _loadAlbumFiles(initial: true);
    }
  }

  Future<void> _refreshSmartStatus() async {
    try {
      final allRules = await AlbumAutoRuleService.instance.loadRules();
      final rules = allRules
          .where((r) => r.albumId == widget.album.id && r.isActive)
          .toList();
      final roots =
          await SmartAlbumService.instance.getScanRoots(widget.album.id);
      final last =
          await SmartAlbumService.instance.getLastScanTime(widget.album.id);
      if (mounted) {
        setState(() {
          _activeRulesCount = rules.length;
          _sourceFoldersCount = roots.length;
          _lastScanTime = last;
        });
      }
    } catch (_) {}
  }

  String _smartStatusText() {
    final last = _lastScanTime != null
        ? DateFormat('HH:mm dd/MM').format(_lastScanTime!)
        : 'Never';
    return '$_activeRulesCount rules • $_sourceFoldersCount sources • Last: $last';
  }

  Future<void> _loadGridPreference() async {
    try {
      await _preferences.init();
      // Use the shared gridZoomLevel key so album and file browser
      // stay in sync (same preference, same default, same range).
      final level = await _preferences.getGridZoomLevel();
      if (mounted) setState(() => _gridZoomLevel = level);
    } catch (_) {}
  }

  void _handleProgressUpdate(Map<String, dynamic> progress) {
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      setState(() {
        _isBackgroundProcessing =
            progress['status'] != 'completed' && progress['status'] != 'error';
        _currentProgress = progress['current'] ?? 0;
        _totalProgress = progress['total'] ?? 0;
        switch (progress['status']) {
          case 'scanning':
            _progressStatus = 'Scanning files...';
            break;
          case 'processing':
            _progressStatus =
                'Adding files... ($_currentProgress/$_totalProgress)';
            break;
          case 'completed':
            _progressStatus = 'Completed!';
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _isBackgroundProcessing = false);
            });
            break;
          case 'error':
            _progressStatus = 'Error: ${progress['error'] ?? 'Unknown error'}';
            break;
        }
      });
    });
  }

  Future<void> _loadAlbumFiles({bool initial = false}) async {
    if (initial || !_isLoading) setState(() => _isLoading = true);
    // Gate: pause thumbnail work while loading album file list.
    ThumbnailLoader.setListingReady(false);
    try {
      if (_isSmartAlbum) {
        if (_cachedFilesLoaded) {
          if (mounted) setState(() => _isLoading = false);
          ThumbnailLoader.setListingReady(true);
          return;
        }
        await _scanSmartAlbumImages();
        // Gate opened at end of _scanSmartAlbumImages.
        return;
      }
      final albumFiles = await _albumService.getAlbumFiles(widget.album.id);
      final imageFiles = <File>[];
      for (final af in albumFiles) {
        final file = File(af.filePath);
        if (await file.exists()) imageFiles.add(file);
      }
      if (mounted) {
        setState(() {
          _originalImageFiles = List<File>.from(imageFiles);
          _applyFiltersAndOrder();
          _isLoading = false;
        });
        _updateThumbnailPriorityMap();
      }
      ThumbnailLoader.setListingReady(true);
    } catch (e) {
      debugPrint('Error loading album files: $e');
      if (mounted) setState(() => _isLoading = false);
      ThumbnailLoader.setListingReady(true);
    }
  }

  Future<void> _scanSmartAlbumImages() async {
    final allRules = await AlbumAutoRuleService.instance.loadRules();
    final rules = allRules
        .where((r) => r.albumId == widget.album.id && r.isActive)
        .toList();
    if (mounted) {
      if (rules.isNotEmpty && _originalImageFiles.isNotEmpty) {
        _originalImageFiles = _originalImageFiles.where((f) {
          final base = pathlib.basename(f.path);
          return rules.any((r) => r.matches(base));
        }).toList();
        _applyFiltersAndOrder();
      }
      setState(() {
        _cancelSmartScan = false;
        _isBackgroundProcessing = true;
        _isLoading = false;
        _progressStatus = 'Scanning...';
        _currentProgress = 0;
        _totalProgress = 0;
      });
    }

    final roots =
        await SmartAlbumService.instance.getScanRoots(widget.album.id);
    if (roots.isEmpty) {
      if (mounted) {
        setState(() {
          _isBackgroundProcessing = false;
          _progressStatus = 'No scan locations configured';
        });
      }
      return;
    }

    int matched = 0;
    int processed = 0;

    Future<void> scanDir(Directory dir) async {
      try {
        await for (final entity
            in dir.list(recursive: false, followLinks: false)) {
          if (_cancelSmartScan) return;
          if (entity is File) {
            processed++;
            if (FileTypeUtils.isMediaFile(entity.path)) {
              final name = pathlib.basename(entity.path);
              if (rules.isEmpty || rules.any((r) => r.matches(name))) {
                matched++;
                if (mounted) {
                  if (!_originalImageFiles.any((f) => f.path == entity.path)) {
                    _originalImageFiles.add(entity);
                  }
                  if (matched % 10 == 0 || processed % 100 == 0) {
                    setState(() {
                      _applyFiltersAndOrder();
                      _progressStatus = 'Scanning... found $matched';
                    });
                  }
                }
              }
            }
          } else if (entity is Directory) {
            await scanDir(entity);
          }
        }
      } catch (_) {}
    }

    for (final rootPath in roots) {
      if (_cancelSmartScan) break;
      await scanDir(Directory(rootPath));
    }

    if (mounted) {
      setState(() {
        _applyFiltersAndOrder();
        _isLoading = false;
        _isBackgroundProcessing = false;
        _progressStatus = 'Completed! Found $matched files';
      });
      _updateThumbnailPriorityMap();
      // Open the gate: scan done, thumbnails can start generating.
      ThumbnailLoader.setListingReady(true);
    }

    try {
      await SmartAlbumService.instance.setCachedFiles(
          widget.album.id, _originalImageFiles.map((f) => f.path).toList());
    } catch (_) {}
  }

  Future<void> _loadCachedSmartImages() async {
    try {
      final cached =
          await SmartAlbumService.instance.getCachedFiles(widget.album.id);
      if (cached.isNotEmpty && mounted) {
        final allRules = await AlbumAutoRuleService.instance.loadRules();
        final rules = allRules
            .where((r) => r.albumId == widget.album.id && r.isActive)
            .toList();
        final files = <File>[];
        for (final p in cached) {
          final f = File(p);
          if (!f.existsSync()) continue;
          if (rules.isEmpty) {
            // No active rules — show all cached files (unfiltered).
            files.add(f);
          } else {
            // Filter by rules.
            final base = pathlib.basename(p);
            if (rules.any((r) => r.matches(base))) files.add(f);
          }
        }
        if (files.isNotEmpty) {
          setState(() {
            _originalImageFiles = files;
            _applyFiltersAndOrder();
            _isLoading = false;
          });
          _cachedFilesLoaded = true;
          _updateThumbnailPriorityMap();
          ThumbnailLoader.setListingReady(true);
        }
      }
    } catch (_) {}
  }

  void _startAutoRescan() {
    _autoRescanTimer?.cancel();
    _autoRescanTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!_isBackgroundProcessing) _scanSmartAlbumImages();
    });
  }

  Future<void> _showManageSourcesDialog() async {
    final service = SmartAlbumService.instance;
    List<String> roots = await service.getScanRoots(widget.album.id);
    if (!mounted) return;
    await RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) {
        List<String> localRoots = List.from(roots);
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Scan Locations'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (localRoots.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'No locations selected. Add folders to scan for this album.',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: localRoots.length,
                      itemBuilder: (context, index) {
                        final p = localRoots[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(PhosphorIconsLight.folder),
                          title: Text(p,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: Icon(PhosphorIconsLight.trash,
                                color: Theme.of(context).colorScheme.error),
                            onPressed: () =>
                                setState(() => localRoots.removeAt(index)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final dir =
                            await FilePicker.platform.getDirectoryPath();
                        if (dir != null && dir.isNotEmpty) {
                          setState(() {
                            if (!localRoots.contains(dir)) localRoots.add(dir);
                          });
                        }
                      },
                      icon: const Icon(PhosphorIconsLight.plus),
                      label: const Text('Add folder'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await service.setScanRoots(widget.album.id, localRoots);
                  if (mounted) {
                    try {
                      navigator.pop();
                    } catch (_) {}
                  }
                  if (mounted && _isSmartAlbum) {
                    await _refreshSmartStatus();
                    _scanSmartAlbumImages();
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _scheduleAlbumReload() {
    if (mounted) _loadAlbumFiles();
  }

  /// Unified Ctrl+scroll spectrum handler. The album detail view is grid-only,
  /// so the spectrum collapses to pure grid item-size zoom (no mode changes).
  /// `+1` = more spacious (bigger items), `-1` = denser (smaller items).
  void _handleViewScaleDelta(int delta) {
    if (delta == 0) return;
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final result = ViewModeSpectrum.step(
      currentMode: ViewMode.grid,
      currentZoom: _gridZoomLevel,
      supported: const {},
      delta: delta,
      minZoom: UserPreferences.minGridZoomLevel,
      maxZoom: maxZoom,
    );
    if (result.gridZoomLevel == _gridZoomLevel) return;
    _applyGridSize(result.gridZoomLevel);
  }

  Future<void> _applyGridSize(int size) async {
    setState(() => _gridZoomLevel = size);
    try {
      await _preferences.setGridZoomLevel(size);
    } catch (_) {}
  }

  void _applyFiltersAndOrder() {
    List<File> files = List<File>.from(_originalImageFiles);
    if (_searchQuery != null && _searchQuery!.trim().isNotEmpty) {
      final q = _searchQuery!.toLowerCase();
      files = files
          .where((f) => pathlib.basename(f.path).toLowerCase().contains(q))
          .toList();
    }
    if (_isShuffled) files.shuffle();
    _imageFiles = files;
    _updateThumbnailPriorityMap();
    // Clear stale item positions whenever the file list changes.
    _dragController.clearItemPositions();
  }

  void _updateThumbnailPriorityMap() {
    ThumbnailLoader.updateDisplayIndexMap(
      _imageFiles.map((file) => file.path).toList(growable: false),
    );
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffled = !_isShuffled;
      _applyFiltersAndOrder();
    });
  }

  void _showSearchDialog() {
    String query = _searchQuery ?? '';
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search in Album'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter image name...',
            prefixIcon: Icon(PhosphorIconsLight.magnifyingGlass),
          ),
          controller: TextEditingController(text: query),
          onChanged: (value) => query = value,
          onSubmitted: (_) {
            RouteUtils.safePopDialog(context);
            setState(() {
              _searchQuery = query.trim().isEmpty ? null : query.trim();
              _applyFiltersAndOrder();
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () => RouteUtils.safePopDialog(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              RouteUtils.safePopDialog(context);
              setState(() {
                _searchQuery = query.trim().isEmpty ? null : query.trim();
                _applyFiltersAndOrder();
              });
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFilesMenu() async {
    if (!mounted) return;
    final result = await RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => BatchAddDialog(albumId: widget.album.id),
    );
    if (result != null && mounted) {
      final l10n = AppLocalizations.of(context)!;
      if (result is Map<String, dynamic>) {
        if (result.containsKey('error')) {
          AppToast.error(
            context,
            l10n.errorWithMessage(result['error'].toString()),
          );
        } else if (result.containsKey('background')) {
          AppToast.info(context, l10n.addingFilesInBackground);
        } else {
          final added = result['added'] ?? 0;
          final total = result['total'] ?? 0;
          final addedInt = (added is int) ? added : int.tryParse('$added') ?? 0;
          final totalInt = (total is int) ? total : int.tryParse('$total') ?? 0;
          AppToast.success(
            context,
            l10n.addedFilesProgress(addedInt, totalInt),
          );
        }
      } else {
        AppToast.success(context, l10n.filesAddedSuccessfully);
      }
      if (result is Map<String, dynamic> && !result.containsKey('background')) {
        _loadAlbumFiles();
      }
    }
  }

  Future<void> _editAlbum() async {
    if (!mounted) return;
    await RouteUtils.showAcrylicDialog<Album>(
      context: context,
      builder: (context) => CreateAlbumDialog(editingAlbum: widget.album),
    );
    if (mounted) setState(() {});
  }

  // _resolveGridColumns() removed — column count is now computed inside
  // _buildGrid() with a LayoutBuilder so it can use the actual available
  // width, matching the file-browser formula exactly.

  Widget _buildAddressBar(BuildContext context) {
    final count = _imageFiles.length;
    return BreadcrumbAddressBar(
      segments: [
        BreadcrumbSegment(
          label: 'Albums',
          icon: PhosphorIconsLight.images,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        BreadcrumbSegment(
          label: widget.album.name,
          badge: count > 0 ? '$count' : null,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // AppBar action builders
  // ---------------------------------------------------------------------------

  /// Actions for the normal (non-selection) AppBar.
  /// On desktop, also contains the "Remove from album" button (enabled when
  /// items are selected), matching the file-browser pattern of not switching
  /// the AppBar on desktop selection mode.
  List<Widget> _buildNormalActions(
      BuildContext context, SelectionState sel, bool isDesktop) {
    final hasSelection = sel.selectedFilePaths.isNotEmpty;
    return [
      // ── Album-specific: remove selected items ─────────────────────────────
      // Visible on desktop when in selection mode (mirrors file-browser: no
      // AppBar change on desktop, actions stay visible but enabled/disabled).
      if (isDesktop && hasSelection)
        IconButton(
          icon: const Icon(PhosphorIconsLight.minusCircle),
          tooltip: 'Remove from album',
          onPressed: () => _removeSelectedFiles(sel.selectedFilePaths),
        ),
      if (isDesktop && hasSelection)
        IconButton(
          icon: const Icon(PhosphorIconsLight.trash),
          tooltip: 'Move selected files to Trash Bin',
          onPressed: () => _deleteSelectedFilesFromDisk(sel.selectedFilePaths),
        ),

      // ── Standard album actions ────────────────────────────────────────────
      IconButton(
        icon: const Icon(PhosphorIconsLight.magnifyingGlass),
        tooltip: 'Search',
        onPressed: _showSearchDialog,
      ),
      if (Platform.isAndroid || Platform.isIOS)
        IconButton(
          icon: const Icon(PhosphorIconsLight.squaresFour),
          tooltip: 'Grid Size',
          onPressed: () => SharedActionBar.showGridSizeDialog(
            context,
            currentGridSize: _gridZoomLevel,
            onApply: _applyGridSize,
            sizeMode: GridSizeMode.referenceWidth,
            minGridSize: UserPreferences.minGridZoomLevel,
            maxGridSize: UserPreferences.maxGridZoomLevel,
          ),
        )
      else
        PopupMenuButton<void>(
          icon: const Icon(PhosphorIconsLight.squaresFour),
          tooltip: 'Grid Size',
          offset: const Offset(0, 50),
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              enabled: false,
              padding: EdgeInsets.zero,
              child: GridSizeSliderMenu(
                currentValue: _gridZoomLevel,
                minValue: UserPreferences.minGridZoomLevel,
                maxValue: GridZoomConstraints.maxGridSizeForContext(
                  context,
                  mode: GridSizeMode.referenceWidth,
                  minValue: UserPreferences.minGridZoomLevel,
                  maxValue: UserPreferences.maxGridZoomLevel,
                ),
                onChanged: _applyGridSize,
              ),
            ),
          ],
        ),
      IconButton(
        icon: const Icon(PhosphorIconsLight.shuffle),
        color: _isShuffled ? Theme.of(context).colorScheme.primary : null,
        tooltip: _isShuffled ? 'Unshuffle' : 'Shuffle',
        onPressed: _toggleShuffle,
      ),
      IconButton(
        icon: const Icon(PhosphorIconsLight.plus),
        onPressed: _showAddFilesMenu,
        tooltip: 'Add images',
      ),
      PopupMenuButton<String>(
        onSelected: (value) async {
          switch (value) {
            case 'edit':
              _editAlbum();
              break;
            case 'select':
              _selectionBloc.add(const ToggleSelectionMode(forceValue: true));
              break;
            case 'shuffle':
              _toggleShuffle();
              break;
            case 'clear_search':
              setState(() {
                _searchQuery = null;
                _applyFiltersAndOrder();
              });
              break;
            case 'manage_rules':
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AutoRulesScreen(
                    scopedAlbumId: widget.album.id,
                    scopedAlbumName: widget.album.name,
                  ),
                ),
              );
              if (mounted && _isSmartAlbum) {
                await _loadCachedSmartImages();
                _scanSmartAlbumImages();
              }
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'edit',
            child: Row(children: [
              Icon(PhosphorIconsLight.pencilSimple),
              SizedBox(width: 8),
              Text('Edit Album'),
            ]),
          ),
          const PopupMenuItem(
            value: 'select',
            child: Row(children: [
              Icon(PhosphorIconsLight.checks),
              SizedBox(width: 8),
              Text('Select Images'),
            ]),
          ),
          const PopupMenuItem(
            value: 'shuffle',
            child: Row(children: [
              Icon(PhosphorIconsLight.shuffle),
              SizedBox(width: 8),
              Text('Shuffle'),
            ]),
          ),
          const PopupMenuItem(
            value: 'clear_search',
            child: Row(children: [
              Icon(PhosphorIconsLight.x),
              SizedBox(width: 8),
              Text('Clear Search'),
            ]),
          ),
          if (_isSmartAlbum)
            const PopupMenuItem(
              value: 'manage_rules',
              child: Row(children: [
                Icon(PhosphorIconsLight.faders),
                SizedBox(width: 8),
                Text('Manage Rules'),
              ]),
            ),
        ],
      ),
    ];
  }

  /// Mobile-only AppBar actions shown when in selection mode.
  List<Widget> _buildMobileSelectionActions(
      BuildContext context, SelectionState sel) {
    final count = sel.selectedFilePaths.length;
    final total = _imageFiles.length;
    return [
      IconButton(
        icon: const Icon(PhosphorIconsLight.minusCircle),
        tooltip: 'Remove from album',
        onPressed: count == 0
            ? null
            : () => _removeSelectedFiles(sel.selectedFilePaths),
      ),
      IconButton(
        icon: const Icon(PhosphorIconsLight.trash),
        tooltip: 'Move selected files to Trash Bin',
        onPressed: count == 0
            ? null
            : () => _deleteSelectedFilesFromDisk(sel.selectedFilePaths),
      ),
      IconButton(
        icon: const Icon(PhosphorIconsLight.checkSquare),
        tooltip: count == total ? 'Deselect all' : 'Select all',
        onPressed: () {
          if (count == total) {
            _clearSelection();
          } else {
            _selectAll();
          }
        },
      ),
      IconButton(
        icon: const Icon(PhosphorIconsLight.x),
        tooltip: 'Cancel selection',
        onPressed: _clearSelection,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return BlocProvider.value(
      value: _selectionBloc,
      child: BlocBuilder<SelectionBloc, SelectionState>(
        builder: (context, sel) {
          final inSel = sel.isSelectionMode;
          final selectedCount = sel.selectedFilePaths.length;

          // Mobile shows a dedicated selection AppBar; desktop keeps the
          // normal AppBar (with "Remove" button enabled when items selected).
          final bool useMobileSelectionBar = inSel && !isDesktop;

          return BaseScreen(
            // Desktop: always show normal title/addressbar.
            // Mobile-selection: show "N selected" as plain title.
            title: useMobileSelectionBar
                ? '$selectedCount selected'
                : widget.album.name,
            titleWidget:
                useMobileSelectionBar ? null : _buildAddressBar(context),
            automaticallyImplyLeading: !useMobileSelectionBar,
            actions: useMobileSelectionBar
                ? _buildMobileSelectionActions(context, sel)
                : _buildNormalActions(context, sel, isDesktop),
            body: FileViewShell(
              viewMode: ViewMode.grid,
              onViewScaleDelta: _handleViewScaleDelta,
              onEscape: inSel ? _clearSelection : null,
              onSelectAll: _selectAll,
              onRefresh: _loadAlbumFiles,
              child: Stack(
                key: _dragController.stackKey,
                children: [
                  Column(
                    children: [
                      if (isDesktop) const SizedBox(height: kToolbarHeight),

                      // Smart album banner
                      if (_isSmartAlbum)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(PhosphorIconsLight.sparkle, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                        'Smart Album (dynamic by rules)'),
                                    const SizedBox(height: 2),
                                    Text(_smartStatusText(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _showManageSourcesDialog,
                                icon: const Icon(PhosphorIconsLight.folderOpen),
                                label: const Text('Sources'),
                              ),
                              if (_isBackgroundProcessing)
                                TextButton.icon(
                                  onPressed: () => setState(() {
                                    _cancelSmartScan = true;
                                    _isBackgroundProcessing = false;
                                    _progressStatus = 'Canceled';
                                  }),
                                  icon: const Icon(PhosphorIconsLight.x),
                                  label: const Text('Cancel'),
                                ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () {
                                  if (!_isBackgroundProcessing) {
                                    setState(() => _isLoading = true);
                                    _scanSmartAlbumImages();
                                  }
                                },
                                icon: const Icon(
                                    PhosphorIconsLight.arrowsClockwise),
                                label: const Text('Rescan'),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AutoRulesScreen(
                                        scopedAlbumId: widget.album.id,
                                        scopedAlbumName: widget.album.name,
                                      ),
                                    ),
                                  );
                                  if (mounted && _isSmartAlbum) {
                                    await _loadCachedSmartImages();
                                    _scanSmartAlbumImages();
                                    await _refreshSmartStatus();
                                  }
                                },
                                icon: const Icon(PhosphorIconsLight.faders),
                                label: const Text('Rules'),
                              ),
                            ],
                          ),
                        ),

                      // Background-scan progress
                      if (_isBackgroundProcessing)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_progressStatus,
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              AppProgressIndicator(
                                value: _totalProgress > 0
                                    ? _currentProgress / _totalProgress
                                    : null,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.2),
                              ),
                            ],
                          ),
                        ),

                      // ── Main grid (+ tap-deselect + drag-selection) ────────
                      Expanded(
                        // GestureDetector wraps the grid content — same
                        // pattern as file_list_view_builder.dart so taps on
                        // empty space (grid padding / below items) deselect,
                        // and left-button drag starts rubber-band selection.
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          // Tap on empty grid area → deselect
                          onTap: inSel ? _clearSelection : null,
                          // Desktop pan → rubber-band drag selection.
                          // Before starting, we force a setState so that the
                          // grid rebuilds with isDragging=true and registers
                          // all item positions via addPostFrameCallback.
                          onPanStart: isDesktop
                              ? (d) {
                                  final focused =
                                      FocusManager.instance.primaryFocus;
                                  final isText = focused?.context?.widget
                                          is EditableText ||
                                      focused?.context
                                              ?.findAncestorWidgetOfExactType<
                                                  EditableText>() !=
                                          null;
                                  if (!isText) {
                                    // isDragging becomes true → next build
                                    // registers all item positions.
                                    _dragController.start(d.localPosition);
                                    // Force rebuild so LayoutBuilder runs
                                    // addPostFrameCallback for each item.
                                    setState(() {});
                                  }
                                }
                              : null,
                          onPanUpdate: isDesktop
                              ? (d) => _dragController.update(d.localPosition)
                              : null,
                          onPanEnd:
                              isDesktop ? (_) => _dragController.end() : null,
                          child: _imageFiles.isEmpty && !_isLoading
                              ? _buildEmptyState()
                              : _buildGrid(context, sel, inSel, isDesktop),
                        ),
                      ),
                    ],
                  ),

                  // Rubber-band selection overlay
                  _dragController.buildOverlay(),

                  // Desktop: SelectionSummaryTooltip at the bottom — exactly
                  // like the file browser (no AppBar change on desktop).
                  if (isDesktop && sel.selectedFilePaths.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SelectionSummaryTooltip(
                        selectedFileCount: sel.selectedFilePaths.length,
                        selectedFolderCount: 0,
                        selectedFilePaths: sel.selectedFilePaths.toList(),
                        selectedFolderPaths: const [],
                      ),
                    ),

                  // Slim bottom progress bar — same style as folder list screen.
                  // Shown during initial load and background scan.
                  // Does NOT displace the grid layout (Positioned overlay).
                  if (_isLoading || _isBackgroundProcessing)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SlimProgressBar(),
                    ),
                ],
              ),
            ),
            floatingActionButton: inSel
                ? null
                : FloatingActionButton(
                    onPressed: _showAddFilesMenu,
                    tooltip: 'Add images',
                    child: const Icon(PhosphorIconsLight.plus),
                  ),
          );
        },
      ),
    );
  }

  /// Grid view with drag-selection position registration — mirrors
  /// [FileListViewBuilder._buildGridView] item-position logic.
  Widget _buildGrid(
    BuildContext context,
    SelectionState sel,
    bool inSel,
    bool isDesktop,
  ) {
    // Wrap in LayoutBuilder so the column count reflects the ACTUAL available
    // width, using the same formula as FileListViewBuilder.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = GridZoomConstraints.columnCountForZoom(
          _gridZoomLevel,
          constraints.maxWidth,
        );
        return GridView.builder(
          controller: _gridScrollController,
          padding: const EdgeInsets.all(GridZoomConstraints.fileGridSpacing),
          // Match file-browser GridView settings for consistent perf.
          physics: const ClampingScrollPhysics(),
          cacheExtent: isDesktop ? 300 : 200,
          // Let off-screen album item states dispose promptly. Thumbnail image
          // cache already handles reuse; keeping widget states alive adds RAM
          // and per-item stream/subscription pressure in large albums.
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          addSemanticIndexes: false,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: GridZoomConstraints.fileGridSpacing,
            mainAxisSpacing: GridZoomConstraints.fileGridSpacing,
          ),
          itemCount: _imageFiles.length,
          itemBuilder: (context, index) {
            final file = _imageFiles[index];
            final isSelected = sel.selectedFilePaths.contains(file.path);
            return LayoutBuilder(
              builder: (context, _) {
                // Register bounding-box for drag-selection hit-testing.
                // Guard: only register when drag is potentially active (user is
                // in selection mode or a drag is already happening). Skipping
                // this during normal browsing eliminates N addPostFrameCallback
                // calls per build frame — the main source of per-frame overhead.
                if (isDesktop && (inSel || _dragController.isDragging.value)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    try {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box != null && box.hasSize && box.attached) {
                        final origin = box.localToGlobal(Offset.zero);
                        _dragController.registerItemPosition(
                          file.path,
                          Rect.fromLTWH(
                            origin.dx,
                            origin.dy,
                            box.size.width,
                            box.size.height,
                          ),
                        );
                      }
                    } catch (_) {}
                  });
                }
                return AlbumImageTile(
                  key: ValueKey('album-grid-${file.path}'),
                  file: file,
                  isSelected: isSelected,
                  isSelectionMode: inSel,
                  isDesktopMode: isDesktop,
                  onSelect: ({shiftSelect = false, ctrlSelect = false}) {
                    _toggleFileSelection(
                      file.path,
                      shiftSelect: shiftSelect,
                      ctrlSelect: ctrlSelect,
                    );
                  },
                  onOpen: () {
                    Navigator.of(context, rootNavigator: true).push(
                      PageRouteBuilder(
                        opaque: false,
                        barrierColor: Colors.black,
                        fullscreenDialog: true,
                        pageBuilder: (_, __, ___) => ImageViewerScreen(
                          file: file,
                          imageFiles: _imageFiles,
                          initialIndex: index,
                        ),
                        transitionsBuilder: (_, animation, __, child) =>
                            FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
                          child: child,
                        ),
                        transitionDuration: const Duration(milliseconds: 180),
                        reverseTransitionDuration:
                            const Duration(milliseconds: 150),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIconsLight.images,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery == null || _searchQuery!.isEmpty
                ? 'No images in this album'
                : 'No images match your search',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add images to start building your album',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddFilesMenu,
            icon: const Icon(PhosphorIconsLight.images),
            label: const Text('Add Images'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
