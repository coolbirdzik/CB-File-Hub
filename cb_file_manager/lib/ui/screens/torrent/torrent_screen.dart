import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import '../../../bloc/selection/selection.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../helpers/core/search_request_guard.dart';
import '../../../helpers/core/user_preferences.dart';
import '../../../helpers/tags/tag_manager.dart';
import '../../../services/torrent/torrent_repository.dart';
import '../../../services/torrent/torrent_entry.dart';
import '../../../services/torrent/magnet_link.dart';
import '../../../services/torrent/torrent_import_confirmation.dart';
import '../../../services/torrent/torrent_service.dart';
import '../../../services/torrent/torrent_source_discovery.dart';
import '../../../helpers/files/windows_app_icon.dart';
import '../../../helpers/files/file_icon_helper.dart';
import '../../components/common/browser_like_file_surface.dart';
import '../../components/common/file_entry_presentation.dart';
import '../../components/common/file_details_columns.dart';
import 'torrent_details_columns.dart';
import 'torrent_download_dialog.dart';
import 'torrent_link_dialog.dart';
import 'torrent_client_import_dialog.dart';
import 'torrent_move_confirmation_dialog.dart';
import 'qbittorrent_import_dialog.dart';
import '../../../services/torrent/qbittorrent_backup_importer.dart';
import '../../components/common/shared_file_context_menu.dart';
import '../../components/common/breadcrumb_address_bar.dart';
import '../../tab_manager/components/navigation_bar.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../../tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import '../../tab_manager/core/tabbed_folder/tabbed_folder_keyboard_controller.dart';
import '../../widgets/file_list_view_builder.dart';
import '../../widgets/selection_summary_tooltip.dart';
import '../../controllers/file_operations_handler.dart';
import '../../components/common/shared_action_bar.dart';
import '../../utils/grid_zoom_constraints.dart';
import '../folder_list/folder_list_state.dart';
import '../folder_list/folder_list_bloc.dart';
import '../folder_list/folder_list_event.dart';
import '../../tab_manager/components/search_bar.dart' as tab_components;
import '../../tab_manager/components/tag_dialogs.dart' as tag_dialogs;
import '../../utils/view_mode_spectrum.dart';

class TorrentScreen extends StatefulWidget {
  final String tabId;
  final TorrentService? service;
  final String? initialSource;
  final UserPreferences? userPreferences;
  const TorrentScreen({
    super.key,
    required this.tabId,
    this.service,
    this.initialSource,
    this.userPreferences,
  });
  @override
  State<TorrentScreen> createState() => _TorrentScreenState();
}

class _TorrentScreenState extends State<TorrentScreen> {
  late final _service = widget.service ?? TorrentService.instance;
  final _requests = SearchRequestGuard();
  final _focus = FocusNode();
  final _address = TextEditingController(text: '#torrents');
  final _selection = SelectionBloc();
  final _operations = FolderListBloc();
  late final _drag = TabbedFolderDragSelectionController(
    selectionBloc: _selection,
  );
  final _previewWidth = ValueNotifier<double>(320);
  final _scroll = ScrollController();
  final _toolbarScroll = ScrollController();
  final _browserActionsScroll = ScrollController();
  bool _importing = false;
  TabbedFolderKeyboardController? _keyboard;
  ColumnVisibility _columns = const ColumnVisibility();
  Set<String> _torrentColumns = Set.of(TorrentDetailsColumns.defaults);
  bool _previewVisible = false;
  bool _showFileTags = false;
  Map<String, List<String>> _fileTags = {};
  StreamSubscription<String>? _tagChanges;
  StreamSubscription<TabManagerState>? _tabChanges;
  late final TabManagerBloc _tabBloc;
  bool _openingSources = false;
  int? _crossAxisCount;
  SharedPreferences? _preferences;
  String _query = '';
  bool _showSearch = false, _useRegex = false;
  ViewMode _viewMode = ViewMode.list;
  SortOption _sort = SortOption.dateDesc;
  int _zoom = UserPreferences.defaultGridZoomLevel;
  static const _viewModes = {
    ViewMode.list,
    ViewMode.tiles,
    ViewMode.grid,
    ViewMode.details,
    ViewMode.tree,
    ViewMode.columns,
  };
  TorrentPage _data = const TorrentPage([], 0);
  String? _error;
  TorrentEntry? _recentEntry;
  String _status = '', _category = '';
  bool _ready = false, _loading = true;
  int _offset = 0;
  static const _pageSizes = [20, 50, 80, 100, 200, 500, 1000];
  int _pageSize = 80;
  Timer? _debounce, _refresh;
  AppLocalizations get l => AppLocalizations.of(context)!;
  bool get _desktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _tabBloc = context.read<TabManagerBloc>();
    _tabChanges = _tabBloc.stream.listen((_) => _schedulePendingSources());
    _service.addListener(_changed);
    _tagChanges = TagManager.onTagChanged.listen((_) {
      if (_showFileTags) _changed();
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() => _run(() async {
    final prefs = _preferences = await SharedPreferences.getInstance();
    final defaults = widget.userPreferences ?? UserPreferences.instance;
    final defaultView = await defaults.getViewMode();
    final defaultColumns = await defaults.getColumnVisibility();
    _showFileTags = await defaults.getShowFileTags();
    final defaultZoom = await defaults.getGridZoomLevel();
    if (!mounted) return;
    final savedPageSize = prefs.getInt('torrent.pageSize');
    _pageSize = _pageSizes.contains(savedPageSize) ? savedPageSize! : 80;
    _viewMode = _viewModes.firstWhere(
      (v) => v.name == prefs.getString('torrent.viewMode'),
      orElse: () =>
          _viewModes.contains(defaultView) ? defaultView : ViewMode.list,
    );
    _sort = TorrentRepository.sortOptions.firstWhere(
      (s) => s.name == prefs.getString('torrent.browserSortOption'),
      orElse: () => SortOption.dateDesc,
    );
    _zoom = (prefs.getInt('torrent.gridZoom') ?? defaultZoom).clamp(
      UserPreferences.minGridZoomLevel,
      UserPreferences.maxGridZoomLevel,
    );
    final savedColumns = prefs.getString('torrent.columns');
    _columns = savedColumns == null
        ? defaultColumns
        : ColumnVisibility.fromMap(
            jsonDecode(savedColumns) as Map<String, dynamic>,
          );
    _previewVisible = prefs.getBool('torrent.preview') ?? false;
    _torrentColumns =
        (prefs.getStringList('torrent.detailColumns') ??
                TorrentDetailsColumns.defaults.toList())
            .toSet();
    await _service.initialize();
    if (!mounted) return;
    setState(() => _ready = true);
    await _load();
    _schedulePendingSources();
    if (mounted && widget.initialSource != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openSource(widget.initialSource!));
      });
    }
  });

  void _schedulePendingSources() {
    if (!mounted || !_ready || _openingSources) return;
    final tab = _tabBloc.state.tabs
        .where((tab) => tab.id == widget.tabId)
        .firstOrNull;
    if (tab == null || tab.pendingTorrentSources.isEmpty) return;
    _openingSources = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        while (mounted) {
          final tab = _tabBloc.state.tabs
              .where((tab) => tab.id == widget.tabId)
              .firstOrNull;
          if (tab == null || tab.pendingTorrentSources.isEmpty) break;
          final request = tab.pendingTorrentSources.first;
          // Acknowledge before opening the dialog. New requests stay queued
          // while the user chooses a destination or confirms a merge.
          final acknowledged = _tabBloc.stream.firstWhere(
            (state) =>
                !(state.tabs
                        .where((tab) => tab.id == widget.tabId)
                        .firstOrNull
                        ?.pendingTorrentSources
                        .contains(request) ??
                    false),
          );
          _tabBloc.add(ConsumeTorrentSource(widget.tabId, request));
          await acknowledged;
          if (mounted) await _openSource(request.source);
        }
      } finally {
        _openingSources = false;
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _queryChanged(String query) {
    _query = query;
    _offset = 0;
    _clearSelection();
    _debounce?.cancel();
    // Immediately invalidate earlier requests, including during debounce.
    _requests.invalidate();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_load());
    });
  }

  void _openSearch() {
    setState(() => _showSearch = true);
    _focus.requestFocus();
  }

  void _closeSearch() {
    _debounce?.cancel();
    setState(() {
      _showSearch = false;
      _useRegex = false;
      _query = '';
      _offset = 0;
    });
    unawaited(_load());
  }

  void _setSort(SortOption sort) {
    setState(() {
      _sort = sort;
      _offset = 0;
    });
    unawaited(_preferences?.setString('torrent.browserSortOption', sort.name));
    unawaited(_load());
  }

  void _setView(ViewMode mode) {
    if (!_viewModes.contains(mode)) return;
    _drag.clearItemPositions();
    setState(() => _viewMode = mode);
    unawaited(_preferences?.setString('torrent.viewMode', mode.name));
  }

  void _setZoom(int zoom) {
    setState(
      () => _zoom = zoom.clamp(
        UserPreferences.minGridZoomLevel,
        UserPreferences.maxGridZoomLevel,
      ),
    );
    unawaited(_preferences?.setInt('torrent.gridZoom', _zoom));
  }

  void _scaleView(int delta) {
    final result = ViewModeSpectrum.step(
      currentMode: _viewMode,
      currentZoom: _zoom,
      supported: _viewModes,
      delta: delta,
      maxZoom: GridZoomConstraints.maxGridSizeForContext(context),
    );
    _setView(result.mode);
    _setZoom(result.gridZoomLevel);
  }

  void _changed() {
    if (!mounted || !_ready) return;
    setState(() {});
    // Scan progress must not re-query/rebuild the library page every 700 ms.
    // F5 loads its page once after import; explicit scans refresh on completion.
    if (_service.scan.running || _importing) return;
    _refresh ??= Timer(const Duration(milliseconds: 700), () {
      _refresh = null;
      if (mounted && !_service.scan.running && !_importing) {
        unawaited(_load(background: true));
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (mounted) setState(() => _error = null);
    try {
      await action();
    } on TorrentImportCancelled {
      // Declining a duplicate merge leaves the library and download intent alone.
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _load({bool background = false}) async {
    if (!_ready) return;
    _debounce?.cancel();
    final generation = _requests.begin();
    if (!background && mounted) setState(() => _loading = true);
    try {
      var result = await _service.repository.page(
        offset: _offset,
        limit: _pageSize,
        query: _query,
        sort: _sort,
        useRegex: _useRegex,
        isCancelled: () => !_requests.isCurrent(generation),
        status: _status.isEmpty ? null : _status,
        category: _category.isEmpty ? null : _category,
      );
      if (!mounted || !_requests.isCurrent(generation)) return;
      if (_offset >= result.total && _offset > 0) {
        _offset = result.total == 0
            ? 0
            : ((result.total - 1) ~/ _pageSize) * _pageSize;
        result = await _service.repository.page(
          offset: _offset,
          limit: _pageSize,
          query: _query,
          sort: _sort,
          useRegex: _useRegex,
          isCancelled: () => !_requests.isCurrent(generation),
          status: _status.isEmpty ? null : _status,
          category: _category.isEmpty ? null : _category,
        );
      }
      if (!mounted || !_requests.isCurrent(generation)) return;
      final tags = _showFileTags
          ? await TagManager.getTagsForFiles(
              result.entries
                  .map(_filePath)
                  .where((path) => !path.startsWith('#torrents/'))
                  .toList(),
            )
          : <String, List<String>>{};
      if (result.entries.isNotEmpty) {
        // Native icons must not hold up the index or the refresh spinner.
        unawaited(
          Future.wait([
            for (final size in [20, 24, 48])
              FileIconHelper.warmExtensionIcons({'.torrent'}, size: size),
          ]).then((_) {
            if (mounted && _requests.isCurrent(generation)) setState(() {});
          }),
        );
      }
      if (!mounted || !_requests.isCurrent(generation)) return;
      setState(() {
        _data = result;
        _fileTags = tags;
        _drag.clearItemPositions();
        _loading = false;
        _error = null;
      });
      final visiblePaths = result.entries.map(_filePath).toSet();
      if (_selection.state.allSelectedPaths.any(
        (path) => !visiblePaths.contains(path),
      )) {
        _clearSelection();
      }
    } catch (e) {
      if (mounted && _requests.isCurrent(generation)) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<bool> _storageReady() async {
    if (_service.storageMode == 'index' || _service.libraryDirectory != null) {
      return true;
    }
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: l.torrentStorage,
    );
    if (dir == null) return false;
    if (_service.storageMode == 'move') {
      final plan = await _service.previewMove(destination: dir);
      if (!mounted || !await confirmTorrentMove(context, plan)) return false;
      await _service.setLibraryDirectory(dir, approvedMove: plan);
    } else {
      await _service.setLibraryDirectory(dir);
    }
    return true;
  }

  Future<void> _import() => _run(() async {
    if (!await _storageReady() || !mounted) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['torrent'],
      windowsOptions: const WindowsOptions(lockParentWindow: true),
    );
    if (files.isEmpty) return;
    final paths = files.map((file) => file.path).whereType<String>().toList();
    if (paths.length == 1) {
      await _openSource(paths.single);
      return;
    }
    await _service.importFiles(paths, onDuplicate: _confirmMerge);
    await _load();
  });

  Future<void> _scanFolder() => _run(() async {
    if (!await _storageReady() || !mounted) return;
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: l.torrentScanFolder,
    );
    if (dir == null) return;
    await _service.setScanRoots([..._service.scanRoots, dir]);
    await _service.scanDirectories([dir]);
    await _load();
  });

  Future<void> _openSource(String source) => _run(() async {
    if (!source.toLowerCase().startsWith('magnet:') && !await _storageReady()) {
      return;
    }
    final entry = await _service.openSource(source, onDuplicate: _confirmMerge);
    await _showOpenedEntry(entry);
  });

  Future<void> _showOpenedEntry(TorrentEntry entry) async {
    if (!mounted) return;
    final showNewest =
        _query.isEmpty &&
        _status.isEmpty &&
        _category.isEmpty &&
        _sort == SortOption.dateDesc;
    setState(() {
      _recentEntry = entry;
      if (showNewest) _offset = 0;
    });
    // Refresh the full library, retaining explicit searches/filters. In the
    // default newest-first view, return to the first page to show new imports.
    await _load();
    if (mounted && showNewest && _scroll.hasClients) _scroll.jumpTo(0);
    if (mounted) {
      if (_desktop) {
        await _download(entry, fromOpen: true);
      } else {
        await _details(entry);
      }
    }
  }

  Future<void> _addLink() => _run(() async {
    if (!await _storageReady() || !mounted) return;
    final entry = await showDialog<TorrentEntry>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TorrentLinkDialog(
        onAdd: (source) =>
            _service.openLink(source, onDuplicate: _confirmMerge),
      ),
    );
    if (entry != null) await _showOpenedEntry(entry);
  });

  Future<bool> _confirmMerge(TorrentEntry existing) async {
    if (!mounted) return false;
    final result = await CbDialog.show<bool>(
      context: context,
      barrierDismissible: false,
      dialog: CbDialog(
        key: const ValueKey('torrent-duplicate-dialog'),
        title: l.torrentDuplicateTitle,
        subtitle: l.torrentDuplicateHint,
        width: 680,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: CbSpacing.md,
          children: [
            SelectableText(existing.name),
            SelectableText(existing.hash),
          ],
        ),
        actions: [
          CbButton(
            key: const ValueKey('torrent-merge-cancel'),
            label: l.cancel,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
          ),
          CbButton(
            key: const ValueKey('torrent-merge-confirm'),
            label: l.torrentMerge,
            variant: CbButtonVariant.primary,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _revealRecentEntry() => _run(() async {
    final entry = _recentEntry;
    if (entry == null) return;
    final rank = await _service.repository.offsetInNewestOrder(entry.hash);
    if (!mounted || rank == null) return;
    _requests.invalidate();
    setState(() {
      _query = '';
      _showSearch = false;
      _useRegex = false;
      _status = '';
      _category = '';
      _sort = SortOption.dateDesc;
      _offset = rank ~/ _pageSize * _pageSize;
    });
    _clearSelection();
    await _load();
    if (!mounted) return;
    final index = _data.entries.indexWhere((item) => item.hash == entry.hash);
    if (index < 0) return;
    final path = _filePath(_data.entries[index]);
    _selectFile(path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final fraction = _data.entries.length < 2
          ? 0.0
          : index / (_data.entries.length - 1);
      _scroll.jumpTo(_scroll.position.maxScrollExtent * fraction);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final itemContext = _keyboard?.itemKeyForPath(path).currentContext;
        if (itemContext != null) Scrollable.ensureVisible(itemContext);
      });
    });
  });

  Widget _recentImportNotice() {
    final entry = _recentEntry!;
    final message = Text(
      l.torrentSaved(entry.name),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CbButton(
          key: const ValueKey('torrent-reveal-recent'),
          label: l.torrentReveal,
          onPressed: _loading ? null : _revealRecentEntry,
        ),
        const SizedBox(width: CbSpacing.sm),
        CbButton.icon(
          icon: PhosphorIconsLight.x,
          tooltip: l.close,
          onPressed: () => setState(() => _recentEntry = null),
        ),
      ],
    );
    return Padding(
      key: const ValueKey('torrent-import-notice'),
      padding: const EdgeInsets.all(CbSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 600
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: CbSpacing.sm,
                children: [message, controls],
              )
            : Row(
                children: [
                  Expanded(child: message),
                  const SizedBox(width: CbSpacing.md),
                  controls,
                ],
              ),
      ),
    );
  }

  Future<void> _scanSystem() => _run(() async {
    if (!await _storageReady() || !mounted) return;
    final confirmed = await CbDialog.show<bool>(
      context: context,
      dialog: CbDialog(
        title: l.torrentScanSystem,
        subtitle: l.torrentScanHint,
        actions: [
          CbButton(
            label: l.cancel,
            onPressed: () => Navigator.pop(context, false),
          ),
          CbButton(
            label: l.torrentScanSystem,
            variant: CbButtonVariant.primary,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final roots = await _service.systemRoots();
    if (roots.isEmpty) throw StateError('No accessible local drives');
    await _service.scanDirectories(roots);
    await _load();
  });

  Future<void> _importQbittorrent() => _run(() async {
    await showDialog<QbittorrentImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QbittorrentImportDialog(
        initialDestination: _service.qbittorrentImportDirectory,
        logPath: _service.qbittorrentLogPath,
        discover: () async => _service.qbittorrentSources.isNotEmpty
            ? _service.qbittorrentSources
            : await QbittorrentBackupImporter.discoverWindowsRoots(),
        loadPlan: QbittorrentBackupImporter.preview,
        checkCleanup: _service.qbittorrentImporter().checkCleanupAllowed,
        onImport: _service.importQbittorrent,
      ),
    );
    await _load();
  });

  Future<void> _importClient(TorrentClient client) => _run(() async {
    final root = await showDialog<String>(
      context: context,
      builder: (_) => TorrentClientImportDialog(
        client: client.label,
        storageMode: _service.storageMode,
        discover: () => TorrentSourceDiscovery.discoverClient(client),
      ),
    );
    if (root == null || !mounted || !await _storageReady() || !mounted) return;
    await _service.setScanRoots({..._service.scanRoots, root}.toList());
    await _service.scanDirectories([root]);
    await _load();
  });

  Future<void> _download(
    TorrentEntry entry, {
    bool fromOpen = false,
  }) => _run(() async {
    final pending = const [
      'active',
      'waiting',
      'paused',
    ].contains(entry.status);
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    TorrentDownloadOptions? options;
    if (fromOpen && !_service.showDownloadDialog) {
      // Opening an existing task silently must not pause, resume or restart it.
      if (pending || entry.status == 'complete') return;
      final directory = (entry.downloadDir ?? _service.defaultDownloadDirectory)
          ?.trim();
      if (directory != null && p.isAbsolute(directory)) {
        options = TorrentDownloadOptions(
          p.normalize(directory),
          _service.startDownloadsImmediately,
        );
      }
    }
    options ??= await showDialog<TorrentDownloadOptions>(
      context: context,
      builder: (_) => TorrentDownloadDialog(
        name: entry.name,
        initialDestination:
            entry.downloadDir ??
            _service.defaultDownloadDirectory ??
            (home == null ? '' : p.join(home, 'Downloads')),
        destinationLocked:
            entry.status == 'active' || entry.status == 'waiting',
        startImmediately: pending
            ? entry.status != 'paused'
            : entry.status == 'complete'
            ? false
            : _service.startDownloadsImmediately,
      ),
    );
    if (options == null || !mounted) return;
    final destinationChanged =
        entry.downloadDir == null ||
        !p.equals(p.normalize(entry.downloadDir!), options.destination);
    if (pending && !(entry.status == 'paused' && destinationChanged)) {
      if (options.startImmediately && entry.status == 'paused') {
        await _service.resume(entry);
      } else if (!options.startImmediately && entry.status != 'paused') {
        await _service.pause(entry);
      }
    } else {
      await _service.download(
        entry,
        options.destination,
        startImmediately: options.startImmediately,
      );
    }
    await _service.setDefaultDownloadDirectory(options.destination);
    await _service.setStartDownloadsImmediately(options.startImmediately);
    await _load(background: true);
  });

  Future<void> _group(TorrentEntry entry) => _run(() async {
    final controller = TextEditingController(text: entry.group);
    try {
      final group = await CbDialog.show<String>(
        context: context,
        dialog: CbDialog(
          title: l.torrentGroup,
          subtitle: entry.name,
          content: CbTextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
          ),
          actions: [
            CbButton(label: l.cancel, onPressed: () => Navigator.pop(context)),
            CbButton(
              label: l.save,
              variant: CbButtonVariant.primary,
              onPressed: () => Navigator.pop(context, controller.text.trim()),
            ),
          ],
        ),
      );
      if (group != null) {
        await _service.repository.update(entry.hash, {'group_name': group});
        await _load(background: true);
      }
    } finally {
      controller.dispose();
    }
  });

  Future<void> _details(TorrentEntry entry) => _run(() async {
    final sources = await _service.repository.sources(entry.hash);
    if (!mounted) return;
    await CbDialog.show<void>(
      context: context,
      dialog: CbDialog(
        title: entry.name,
        width: 760,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: CbSpacing.xl,
          children: [
            Text(
              '${_entryStatus(entry)} · ${_size(entry.completedBytes)} / ${_size(entry.totalBytes)}'
              ' · ${_size(entry.downloadSpeed)}/s\n'
              '${entry.fileCount} file · ${l.torrentCategory(entry.category)}',
              style: CbTypography.body.copyWith(height: 1.6),
            ),
            _detailField(l.torrentColumn('hash'), entry.hash),
            if (entry.group.isNotEmpty)
              _detailField(l.torrentGroup, entry.group),
            if (entry.torrentPath.isNotEmpty)
              _detailField(l.torrentColumn('torrentFile'), entry.torrentPath),
            if (entry.sourceUris.isNotEmpty)
              _detailField(
                l.torrentColumn('source'),
                entry.sourceUris.join('\n'),
              ),
            if (sources.isNotEmpty)
              _detailField(l.torrentSources, sources.join('\n')),
            if (entry.downloadDir != null)
              _detailField(l.torrentColumn('destination'), entry.downloadDir!),
            if (entry.error != null)
              _detailField(l.torrentColumn('error'), entry.error!),
          ],
        ),
        actions: [
          CbButton(label: l.close, onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  });

  Widget _detailField(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: CbSpacing.sm,
    children: [
      Text(
        label,
        style: CbTypography.labelSm.copyWith(
          color: context.cbColors.textSecondary,
        ),
      ),
      SelectableText(value, style: CbTypography.body.copyWith(height: 1.6)),
    ],
  );

  Future<void> _remove(TorrentEntry entry) => _run(() async {
    final confirmed = await CbDialog.show<bool>(
      context: context,
      dialog: CbDialog(
        title: l.torrentRemove,
        subtitle: '${entry.name}\n\n${l.torrentRemoveHint}',
        actions: [
          CbButton(
            label: l.cancel,
            onPressed: () => Navigator.pop(context, false),
          ),
          CbButton(
            label: l.torrentRemove,
            variant: CbButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.remove(entry);
      await _load();
    }
  });

  @override
  void dispose() {
    _tabChanges?.cancel();
    _requests.dispose();
    _debounce?.cancel();
    _refresh?.cancel();
    _service.removeListener(_changed);
    unawaited(_tagChanges?.cancel());
    _focus.dispose();
    _address.dispose();
    _scroll.dispose();
    _toolbarScroll.dispose();
    _browserActionsScroll.dispose();
    _previewWidth.dispose();
    _drag.dispose();
    unawaited(_selection.close());
    unawaited(_operations.close());
    super.dispose();
  }

  String _filePath(TorrentEntry entry) => entry.torrentPath.isNotEmpty
      ? entry.torrentPath
      : '#torrents/${entry.hash}.torrent';

  TorrentEntry? _entryForPath(String path) {
    for (final entry in _data.entries) {
      if (_filePath(entry) == path) return entry;
    }
    return null;
  }

  FolderListState _folderState() => FolderListState(
    '#torrents',
    files: [for (final entry in _data.entries) File(_filePath(entry))],
    viewMode: _viewMode,
    sortOption: _sort,
    gridZoomLevel: _zoom,
    fileStatsCache: {
      for (final entry in _data.entries)
        _filePath(entry): _TorrentFileStat(entry),
    },
    fileTags: _fileTags,
  );

  void _clearSelection() {
    _keyboard?.clearFocus();
    _selection.add(ClearSelection());
  }

  void _selectAll() => _selection.add(
    SelectAll(
      allFilePaths: _data.entries.map(_filePath).toList(),
      allFolderPaths: const [],
    ),
  );

  void _selectRange({
    required Set<String> folderPaths,
    required Set<String> filePaths,
    required String lastSelectedPath,
    required bool ctrlSelect,
  }) => _selection.add(
    SelectItemsInRect(
      folderPaths: folderPaths,
      filePaths: filePaths,
      lastSelectedPath: lastSelectedPath,
      isCtrlPressed: ctrlSelect,
      isShiftPressed: true,
    ),
  );

  void _selectFile(
    String path, {
    bool shiftSelect = false,
    bool ctrlSelect = false,
  }) {
    final previous = _selection.state.lastSelectedPath;
    _keyboard?.focusPickedPath(
      path,
      shiftSelect: shiftSelect,
      previousSelectedPath: previous,
    );
    final paths = _data.entries.map(_filePath).toList();
    if (shiftSelect &&
        previous != null &&
        paths.contains(previous) &&
        paths.contains(path)) {
      final a = paths.indexOf(previous), b = paths.indexOf(path);
      _selectRange(
        folderPaths: {},
        filePaths: paths.sublist(a < b ? a : b, (a > b ? a : b) + 1).toSet(),
        lastSelectedPath: path,
        ctrlSelect: ctrlSelect,
      );
    } else {
      _selection.add(ToggleFileSelection(path, ctrlSelect: ctrlSelect));
    }
  }

  Future<void> _activateFile(File file) async {
    final entry = _entryForPath(file.path);
    if (entry == null) return;
    if (!_desktop) {
      await _details(entry);
    } else {
      await _download(entry, fromOpen: true);
    }
  }

  void _setColumns(ColumnVisibility columns) {
    setState(() => _columns = columns);
    unawaited(
      _preferences?.setString('torrent.columns', jsonEncode(columns.toMap())),
    );
  }

  void _showColumns() => SharedActionBar.showColumnVisibilityDialog(
    context,
    currentVisibility: _columns,
    onApply: _setColumns,
    additionalColumns: {for (final c in _detailsColumns) c.id: c.label},
    visibleAdditionalColumns: _torrentColumns,
    onApplyAdditionalColumns: _setTorrentColumns,
  );

  List<FileDetailsColumn> get _detailsColumns => TorrentDetailsColumns.build(
    l: l,
    entries: {for (final e in _data.entries) _filePath(e): e},
    visible: _torrentColumns,
    formatSize: _size,
  );

  void _setTorrentColumns(Set<String> columns) {
    setState(() => _torrentColumns = Set.of(columns));
    unawaited(
      _preferences?.setStringList('torrent.detailColumns', columns.toList()),
    );
  }

  void _toggleTorrentColumn(String id) {
    final columns = Set<String>.of(_torrentColumns);
    if (!columns.remove(id)) columns.add(id);
    _setTorrentColumns(columns);
  }

  void _togglePreview() {
    setState(() => _previewVisible = !_previewVisible);
    unawaited(_preferences?.setBool('torrent.preview', _previewVisible));
  }

  Widget _fileBrowser(
    BuildContext context,
    FolderListState state,
    SelectionState selection,
    TabbedFolderKeyboardController keyboard,
  ) => FileListViewBuilder.build(
    state: state,
    selectionState: selection,
    isDesktopPlatform: _desktop,
    onNavigateToPath: (path) =>
        TabNavigator.updateTabPath(context, widget.tabId, path),
    onFileTap: (file, _) => unawaited(_activateFile(file)),
    toggleFileSelection: _selectFile,
    toggleFolderSelection: _selectFile,
    clearSelection: _clearSelection,
    dragSelectionController: _drag,
    showFileTags: _showFileTags,
    showDeleteTagDialog: tag_dialogs.showDeleteTagDialog,
    showAddTagToFileDialog: tag_dialogs.showAddTagToFileDialog,
    toggleSelectionMode: () => _selection.add(const ToggleSelectionMode()),
    columnVisibility: _columns,
    onColumnVisibilityChanged: _setColumns,
    onSortOptionSelected: _setSort,
    showContextMenu: _backgroundMenu,
    isPreviewPaneVisible: _previewVisible,
    previewPaneWidthListenable: _previewWidth,
    onZoomLevelChanged: _setZoom,
    onPreviewPaneWidthChanged: (width) => _previewWidth.value = width,
    onPreviewPaneWidthCommitted: (width) => _previewWidth.value = width,
    onPreviewPaneToggled: _togglePreview,
    scrollController: _scroll,
    itemKeyForPath: keyboard.itemKeyForPath,
    immediateSelectionForPath: keyboard.immediateSelectionForPath,
    onGridCrossAxisCountChanged: (count) => _crossAxisCount = count,
    tabId: widget.tabId,
  );

  void _backgroundMenu(BuildContext context, Offset position) {
    final paths = _selection.state.allSelectedPaths;
    if (paths.isEmpty) return;
    if (paths.length == 1) {
      showFileContextMenu(
        context: context,
        file: File(paths.single),
        fileTags: const [],
        isVideo: false,
        isImage: false,
        globalPosition: position,
      );
    } else {
      showMultipleFilesContextMenu(
        context: context,
        selectedPaths: paths,
        globalPosition: position,
        onClearSelection: _clearSelection,
      );
    }
  }

  List<ContextMenuSection> _torrentMenuSections(
    BuildContext context,
    List<String> paths,
  ) {
    final entries = paths.map(_entryForPath).whereType<TorrentEntry>().toList();
    if (entries.isEmpty) return [];
    final entry = entries.first;
    final pending = const [
      'active',
      'waiting',
      'paused',
    ].contains(entry.status);
    ContextMenuAction action(String id, String label, IconData icon) =>
        ContextMenuAction(
          id: 'torrent_$id',
          label: label,
          icon: icon,
          onSelected: (_) => _entryAction(entry, id),
        );
    return [
      ContextMenuSection(
        title: l.torrents,
        actions: [
          if (entries.length == 1) ...[
            if (_desktop && !pending)
              action(
                'download',
                l.torrentDownload,
                PhosphorIconsLight.downloadSimple,
              ),
            if (_desktop && const ['active', 'waiting'].contains(entry.status))
              action('pause', l.torrentPause, PhosphorIconsLight.pause),
            if (_desktop && entry.status == 'paused')
              action('resume', l.torrentResume, PhosphorIconsLight.play),
            if (pending) action('stop', l.torrentStop, PhosphorIconsLight.stop),
            if (entry.downloadDir != null)
              action(
                'folder',
                l.torrentOpenFolder,
                PhosphorIconsLight.folderOpen,
              ),
            action('group', l.torrentGroup, PhosphorIconsLight.tag),
            action(
              'details',
              '${l.torrents} · ${l.properties}',
              PhosphorIconsLight.info,
            ),
          ],
          ContextMenuAction(
            id: 'torrent_copy_magnet',
            label: l.torrentCopyMagnet,
            icon: PhosphorIconsLight.link,
            onSelected: (_) => _run(() async {
              final links = entries
                  .map(
                    (item) => MagnetLink.fromMetadata(
                      hash: item.hash,
                      name: item.name,
                      trackers: item.trackers,
                      sourceUri: item.sourceUri,
                    ).uri,
                  )
                  .join('\n');
              await Clipboard.setData(ClipboardData(text: links));
            }),
          ),
          ContextMenuAction(
            id: 'torrent_remove',
            label: l.torrentRemove,
            icon: PhosphorIconsLight.minusCircle,
            isDestructive: true,
            onSelected: (_) =>
                entries.length == 1 ? _remove(entry) : _removeEntries(entries),
          ),
        ],
      ),
    ];
  }

  Future<void> _removeSelected() => _removeEntries(
    _selection.state.allSelectedPaths
        .map(_entryForPath)
        .whereType<TorrentEntry>()
        .toList(),
  );

  Future<void> _deleteSelected({bool permanent = false}) async {
    final paths = _selection.state.allSelectedPaths;
    if (paths.any((path) => path.startsWith('#torrents/'))) {
      await _removeSelected();
      return;
    }
    await FileOperationsHandler.handleDelete(
      context: context,
      folderListBloc: _operations,
      selectedFiles: paths,
      selectedFolders: const [],
      selectionBloc: _selection,
      permanent: permanent,
      onClearSelection: _clearSelection,
    );
  }

  Future<void> _removeEntries(List<TorrentEntry> entries) async {
    if (entries.isEmpty) return;
    if (entries.length == 1) {
      await _remove(entries.single);
      return;
    }
    final confirmed = await CbDialog.show<bool>(
      context: context,
      dialog: CbDialog(
        title: l.torrentRemove,
        subtitle:
            '${l.itemsSelected(entries.length)}\n\n${l.torrentRemoveHint}',
        actions: [
          CbButton(
            label: l.cancel,
            onPressed: () => Navigator.pop(context, false),
          ),
          CbButton(
            label: l.torrentRemove,
            variant: CbButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() async {
        for (final entry in entries) {
          await _service.remove(entry);
        }
        _clearSelection();
        await _load();
      });
    }
  }

  Future<void> _refreshLibrary() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      await _run(() async {
        if (!_ready) await _initialize();
        if (!mounted || !await _storageReady()) return;
        FileIconHelper.invalidateExtension('.torrent');
        await _service.refreshImports();
        await _load();
      });
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _browserNavigationBar() => PathNavigationBar(
    tabId: widget.tabId,
    pathController: _address,
    currentPath: '#torrents',
    tabPath: '#torrents',
    enablePathEditing: false,
    onPathSubmitted: (path) =>
        TabNavigator.updateTabPath(context, widget.tabId, path),
    canNavigateToParent: false,
    onNavigateHome: () =>
        TabNavigator.updateTabPath(context, widget.tabId, '#home'),
    breadcrumbSegments: [
      BreadcrumbSegment(
        label: l.torrents,
        icon: PhosphorIconsLight.downloadSimple,
      ),
    ],
  );

  Widget _browserSearchBar() => tab_components.SearchBar(
    currentPath: '#torrents',
    tabId: widget.tabId,
    initialQuery: _query,
    focusNode: _focus,
    onCloseSearch: _closeSearch,
    showTagSearch: false,
    showGlobalSearchToggle: false,
    showTipsButton: false,
    onQueryChanged: _queryChanged,
    onClearSearch: () {
      _queryChanged('');
    },
    onRegexChanged: (value) {
      _useRegex = value;
      _queryChanged(_query);
    },
    onSearchWithOptions: (query, regex) {
      _query = query;
      _useRegex = regex;
      _offset = 0;
      unawaited(_load());
    },
  );

  List<Widget> _browserActions(List<Widget> actions, double width) {
    final materialActions = actions
        .map(
          (action) => Material(type: MaterialType.transparency, child: action),
        )
        .toList();
    if (width >= 760) return materialActions;
    return [
      SizedBox(
        width: width * (_showSearch ? 0.36 : 0.55),
        child: SingleChildScrollView(
          controller: _browserActionsScroll,
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: materialActions),
        ),
      ),
    ];
  }

  Widget _torrentToolbar() => SizedBox(
    height: 48,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: CbSpacing.md),
      child: Scrollbar(
        controller: _toolbarScroll,
        thumbVisibility: true,
        interactive: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          key: const ValueKey('torrent-toolbar'),
          controller: _toolbarScroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _importMenu(),
              const SizedBox(width: CbSpacing.sm),
              CbButton(
                key: const ValueKey('torrent-scan-folder-action'),
                label: l.torrentScanFolder,
                icon: PhosphorIconsLight.folder,
                onPressed: !_ready || _service.scan.running
                    ? null
                    : _scanFolder,
              ),
              if (_desktop) ...[
                const SizedBox(width: CbSpacing.sm),
                CbButton(
                  key: const ValueKey('torrent-add-link-action'),
                  label: l.torrentAddLink,
                  icon: PhosphorIconsLight.link,
                  onPressed: !_ready ? null : _addLink,
                ),
                const SizedBox(width: CbSpacing.sm),
                CbButton(
                  label: l.torrentScanSystem,
                  icon: PhosphorIconsLight.hardDrives,
                  onPressed: !_ready || _service.scan.running
                      ? null
                      : _scanSystem,
                ),
              ],
              _filterMenu(),
              CbButton.icon(
                icon: PhosphorIconsLight.gear,
                tooltip: l.settings,
                onPressed: !_ready
                    ? null
                    : () => unawaited(
                        CbDialog.show<void>(
                          context: context,
                          dialog: CbDialog(
                            title: l.torrents,
                            width: 760,
                            content: _TorrentSettings(service: _service),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _importMenu() => Material(
    type: MaterialType.transparency,
    child: MenuAnchor(
      builder: (context, controller, child) => CbButton(
        key: const ValueKey('torrent-import-action'),
        label: l.torrentImportMenu,
        icon: PhosphorIconsLight.plus,
        trailingIcon: PhosphorIconsLight.caretDown,
        variant: CbButtonVariant.primary,
        onPressed: !_ready || _service.scan.running
            ? null
            : () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
      ),
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('torrent-import-files-action'),
          leadingIcon: const Icon(PhosphorIconsLight.file),
          onPressed: _import,
          child: Text(l.torrentImport),
        ),
        if (_desktop) ...[
          const Divider(height: 1),
          if (Platform.isWindows)
            MenuItemButton(
              key: const ValueKey('torrent-qbittorrent-import-action'),
              leadingIcon: const Icon(PhosphorIconsLight.downloadSimple),
              onPressed: _importQbittorrent,
              child: Text(l.qbittorrentImport),
            ),
          for (final client in TorrentClient.values)
            if (Platform.isWindows ||
                client == TorrentClient.transmission ||
                client == TorrentClient.deluge)
              MenuItemButton(
                key: ValueKey('torrent-import-${client.name}-action'),
                leadingIcon: const Icon(PhosphorIconsLight.downloadSimple),
                onPressed: () => _importClient(client),
                child: Text(l.torrentImportFrom(client.label)),
              ),
        ],
      ],
    ),
  );

  Widget _filterMenu() => PopupMenuButton<String>(
    key: const ValueKey('torrent-filter-menu'),
    tooltip: l.torrentColumn('filters'),
    icon: Icon(
      PhosphorIconsLight.funnel,
      color: _status.isNotEmpty || _category.isNotEmpty
          ? Theme.of(context).colorScheme.primary
          : null,
    ),
    itemBuilder: (_) => [
      PopupMenuItem(enabled: false, child: Text(l.torrentStatusLabel)),
      for (final status in [
        '',
        'library',
        'active',
        'waiting',
        'paused',
        'complete',
        'error',
      ])
        CheckedPopupMenuItem(
          value: 'status:$status',
          checked: _status == status,
          child: Text(status.isEmpty ? l.all : l.torrentStatus(status)),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(enabled: false, child: Text(l.columnType)),
      for (final category in ['', 'video', 'audio', 'documents', 'other'])
        CheckedPopupMenuItem(
          value: 'category:$category',
          checked: _category == category,
          child: Text(category.isEmpty ? l.all : l.torrentCategory(category)),
        ),
    ],
    onSelected: (value) {
      setState(() {
        if (value.startsWith('status:')) _status = value.substring(7);
        if (value.startsWith('category:')) _category = value.substring(9);
        _offset = 0;
      });
      unawaited(_load());
    },
  );

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: _selection),
      BlocProvider.value(value: _operations),
    ],
    child: BlocBuilder<SelectionBloc, SelectionState>(
      builder: (context, selection) => LayoutBuilder(
        builder: (context, constraints) {
          final state = _folderState();
          final actions = SharedActionBar.buildCommonActions(
            context: context,
            onSearchPressed: () => _showSearch ? _closeSearch() : _openSearch(),
            isSearchActive: _showSearch,
            currentSortOption: _sort,
            onSortOptionSelected: _setSort,
            allowedSortOptions: TorrentRepository.sortOptions,
            viewMode: _viewMode,
            onViewModeToggled: () {},
            onViewModeSelected: _setView,
            allowedViewModes: _viewModes,
            currentGridZoomLevel: _zoom,
            onGridZoomChanged: _setZoom,
            onRefresh: _refreshLibrary,
            refreshTooltip: l.torrentRefreshImport,
            onSelectionModeToggled: () =>
                _selection.add(const ToggleSelectionMode()),
            showDesktopViewModes: _desktop,
            onColumnSettingsPressed: _showColumns,
            onPreviewPaneToggled: _togglePreview,
            isPreviewPaneVisible: _previewVisible,
          );
          return FileDetailsColumns(
            columns: _detailsColumns,
            onToggle: _toggleTorrentColumn,
            child: FileEntryPresentation(
              virtualPaths: {
                for (final entry in _data.entries)
                  if (entry.torrentPath.isEmpty) _filePath(entry),
              },
              names: {
                for (final entry in _data.entries) _filePath(entry): entry.name,
              },
              child: FileContextMenuExtension(
                sections: _torrentMenuSections,
                allowPaste: false,
                isVirtual: (path) => path.startsWith('#torrents/'),
                onOpen: (file) => _activateFile(file),
                child: BrowserLikeFileSurface(
                  selectionState: selection,
                  selectionTotalSize: _data.entries
                      .where(
                        (entry) => selection.selectedFilePaths.contains(
                          _filePath(entry),
                        ),
                      )
                      .fold<int>(0, (total, entry) => total + entry.totalBytes),
                  viewMode: _viewMode,
                  isDesktop: _desktop,
                  visiblePaths: state.files.map((file) => file.path),
                  onClearSelection: _clearSelection,
                  showRemoveTagsDialog: (_) {},
                  showManageAllTagsDialog: (_) {},
                  showDeleteConfirmationDialog: (_) =>
                      unawaited(_deleteSelected()),
                  showAppBar: true,
                  keyboardFolderListState: state,
                  onBackInTabHistory: () => context
                      .read<TabManagerBloc>()
                      .backNavigationToPath(widget.tabId),
                  focusFolderPath: (_) {},
                  focusFilePath: (path) => _selectFile(path),
                  selectRange: _selectRange,
                  activateEntity: (entity) =>
                      unawaited(_activateFile(File(entity.path))),
                  onSelectAll: _selectAll,
                  onCopy: () => _operations.add(
                    CopyFiles(
                      _selection.state.allSelectedPaths
                          .where((path) => !path.startsWith('#torrents/'))
                          .map(File.new)
                          .toList(),
                    ),
                  ),
                  onCut: () => _operations.add(
                    CutFiles(
                      _selection.state.allSelectedPaths
                          .where((path) => !path.startsWith('#torrents/'))
                          .map(File.new)
                          .toList(),
                    ),
                  ),
                  onDelete: (_, permanent) =>
                      _deleteSelected(permanent: permanent),
                  gridCrossAxisCount: _crossAxisCount,
                  pathNavigationBar: _browserNavigationBar(),
                  onRefresh: _refreshLibrary,
                  onSearch: _openSearch,
                  onEscape: () =>
                      _showSearch ? _closeSearch() : _clearSelection(),
                  onViewScaleDelta: _scaleView,
                  showSearchBar: _showSearch,
                  searchBar: _browserSearchBar(),
                  actions: _browserActions(actions, constraints.maxWidth),
                  bodyBuilder: (context, keyboard) {
                    _keyboard = keyboard;
                    return Material(
                      type: MaterialType.transparency,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _torrentToolbar(),
                          _taskStatus(selection),
                          if (_recentEntry != null) _recentImportNotice(),
                          if (!_desktop)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(l.torrentDesktopOnly),
                            ),
                          if (_ready &&
                              (_service.scan.running ||
                                  _service.scan.visited > 0 ||
                                  _service.scan.failed > 0))
                            _scanProgress(),
                          if (_error != null ||
                              _ready && _service.lastError != null)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                _error ?? _service.lastError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          if (_loading ||
                              _importing ||
                              (_ready && _service.scan.running))
                            const LinearProgressIndicator(minHeight: 2),
                          Expanded(
                            child: !_ready
                                ? const SizedBox.shrink()
                                : _data.entries.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(l.torrentEmpty),
                                    ),
                                  )
                                : _fileBrowser(
                                    context,
                                    state,
                                    selection,
                                    keyboard,
                                  ),
                          ),
                          if (_ready)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                CbSpacing.md,
                                CbSpacing.md,
                                CbSpacing.md,
                                CbSpacing.md +
                                    (_desktop && selection.isSelectionMode
                                        ? SelectionSummaryTooltip.height
                                        : 0),
                              ),
                              child: _pagination(),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  void _changePage(int delta) {
    _offset += delta;
    _clearSelection();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_load());
  }

  void _changePageSize(int value) {
    if (!_pageSizes.contains(value) || value == _pageSize) return;
    setState(() {
      _pageSize = value;
      _offset = 0;
    });
    _clearSelection();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_preferences?.setInt('torrent.pageSize', value));
    unawaited(_load());
  }

  Widget _pagination() => LayoutBuilder(
    builder: (context, constraints) {
      final sizePicker = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.torrentFilesPerPage),
          const SizedBox(width: CbSpacing.sm),
          CbSelect<int>(
            key: const ValueKey('torrent-page-size'),
            value: _pageSize,
            tooltip: l.torrentFilesPerPage,
            size: CbSelectSize.sm,
            width: 104,
            items: [
              for (final size in _pageSizes)
                CbSelectItem(value: size, label: '$size'),
            ],
            onChanged: _loading ? null : _changePageSize,
          ),
        ],
      );
      final navigation = Row(
        children: [
          Expanded(
            child: Text(
              l.torrentPageSummary(
                _data.total == 0 ? 0 : _offset + 1,
                _offset + _data.entries.length,
                _data.total,
              ),
            ),
          ),
          CbButton.icon(
            icon: PhosphorIconsLight.caretLeft,
            tooltip: l.previousPage,
            onPressed: _offset == 0 || _loading
                ? null
                : () => _changePage(-_pageSize),
          ),
          CbButton.icon(
            icon: PhosphorIconsLight.caretRight,
            tooltip: l.nextPage,
            onPressed: _offset + _pageSize >= _data.total || _loading
                ? null
                : () => _changePage(_pageSize),
          ),
        ],
      );
      if (constraints.maxWidth < 560) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: CbSpacing.sm,
          children: [sizePicker, navigation],
        );
      }
      return Row(
        children: [
          sizePicker,
          const SizedBox(width: CbSpacing.xl),
          Expanded(child: navigation),
        ],
      );
    },
  );

  Widget _scanProgress() {
    final scan = _service.scan;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.torrentScanSummary(
              scan.visited,
              scan.imported,
              scan.duplicates,
              scan.failed,
            ),
          ),
          if (scan.running)
            Text(
              scan.currentPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          Wrap(
            spacing: 8,
            children: [
              if (scan.running)
                CbButton(label: l.cancel, onPressed: _service.cancelScan),
              if (scan.failed > 0)
                CbButton(
                  label: l.torrentScanLog,
                  onPressed: () => _run(() async {
                    await OpenFilex.open(_service.scanLogPath);
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _taskStatus(SelectionState selection) {
    final paths = selection.selectedFilePaths;
    final entry = paths.length == 1 ? _entryForPath(paths.single) : null;
    if (entry == null || entry.status == 'library') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${entry.name} · ${_entryStatus(entry)} · ${_size(entry.completedBytes)} / ${_size(entry.totalBytes)} · ${_size(entry.downloadSpeed)}/s',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          LinearProgressIndicator(value: entry.progress, minHeight: 2),
          if (entry.error != null)
            Text(
              entry.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  String _entryStatus(TorrentEntry entry) =>
      '${l.torrentStatus(entry.status)}'
      '${entry.status == 'library' ? '' : ' ${(entry.progress * 100).toStringAsFixed(1)}%'}';

  void _entryAction(TorrentEntry entry, String action) {
    switch (action) {
      case 'download':
        _selectFile(_filePath(entry));
        unawaited(_download(entry));
      case 'pause':
        unawaited(_run(() => _service.pause(entry)));
      case 'resume':
        unawaited(_run(() => _service.resume(entry)));
      case 'stop':
        unawaited(_run(() => _service.stop(entry)));
      case 'folder':
        unawaited(
          _run(() async {
            await OpenFilex.open(entry.downloadDir!);
          }),
        );
      case 'group':
        unawaited(_group(entry));
      case 'details':
        unawaited(_details(entry));
      case 'remove':
        unawaited(_remove(entry));
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
  }
}

/// Supplies existing browser columns from the bounded torrent index page.
/// It is presentation metadata only; filesystem commands keep the real path.
class _TorrentFileStat implements FileStat {
  final TorrentEntry entry;
  const _TorrentFileStat(this.entry);
  @override
  DateTime get changed => entry.addedAt;
  @override
  DateTime get modified => entry.modifiedAt;
  @override
  DateTime get accessed => entry.modifiedAt;
  @override
  FileSystemEntityType get type => FileSystemEntityType.file;
  @override
  int get size => entry.totalBytes;
  @override
  int get mode => 0;
  @override
  String modeString() => '---------';
}

class _TorrentSettings extends StatefulWidget {
  final TorrentService service;
  const _TorrentSettings({required this.service});
  @override
  State<_TorrentSettings> createState() => _TorrentSettingsState();
}

class _TorrentSettingsState extends State<_TorrentSettings> {
  String? _error;
  bool _busy = false;
  TorrentService get service => widget.service;
  AppLocalizations get l => AppLocalizations.of(context)!;
  late final _downloadDirectory = TextEditingController(
    text: service.defaultDownloadDirectory ?? '',
  );
  @override
  void initState() {
    super.initState();
    service.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    service.removeListener(_changed);
    _downloadDirectory.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setMode(String value) async {
    if (value == service.storageMode) return;
    var destination = service.libraryDirectory;
    if (value != 'index' && destination == null) {
      destination = await FilePicker.getDirectoryPath(
        dialogTitle: l.torrentStorage,
      );
      if (destination == null) return;
    }
    if (value == 'move') {
      final plan = await service.previewMove(destination: destination);
      if (!mounted || !await confirmTorrentMove(context, plan)) return;
      await service.setStorageMode(value, approvedMove: plan);
    } else {
      if (destination != null && service.libraryDirectory == null) {
        await service.setLibraryDirectory(destination);
      }
      await service.setStorageMode(value);
    }
  }

  Future<void> _chooseStorage() async {
    final destination = await FilePicker.getDirectoryPath(
      dialogTitle: l.torrentStorage,
    );
    if (destination == null) return;
    if (service.storageMode == 'move') {
      final plan = await service.previewMove(destination: destination);
      if (!mounted || !await confirmTorrentMove(context, plan)) return;
      await service.setLibraryDirectory(destination, approvedMove: plan);
    } else {
      await service.setLibraryDirectory(destination);
    }
  }

  Future<void> _organize() async {
    if (service.storageMode == 'move') {
      final plan = await service.previewMove();
      if (!mounted || !await confirmTorrentMove(context, plan)) return;
      await service.organizeLibrary(approvedMove: plan);
    } else {
      await service.organizeLibrary();
    }
  }

  Future<void> _saveDownloadDirectory() async {
    final value = _downloadDirectory.text.trim();
    if (value.isNotEmpty && !p.isAbsolute(value)) {
      throw FormatException(l.torrentDestinationRequired);
    }
    await service.setDefaultDownloadDirectory(value);
  }

  Future<void> _chooseDownloadDirectory() async {
    final value = _downloadDirectory.text.trim();
    final exists = p.isAbsolute(value) && await Directory(value).exists();
    if (!mounted) return;
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: l.torrentColumn('destination'),
      initialDirectory: exists ? value : null,
      windowsOptions: const WindowsOptions(lockParentWindow: true),
    );
    if (directory == null || !mounted) return;
    _downloadDirectory.text = directory;
    await _saveDownloadDirectory();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: CbSpacing.xxl,
    children: [
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: CbSpacing.md,
        children: [
          CbSelect<String>(
            key: const ValueKey('torrent-storage-mode'),
            value: service.storageMode,
            label: l.torrentOrganize,
            items: [
              for (final mode in ['index', 'copy', 'move'])
                CbSelectItem(value: mode, label: l.torrentStorageMode(mode)),
            ],
            onChanged: service.scan.running || _busy
                ? null
                : (value) => _run(() => _setMode(value)),
          ),
          Text(
            l.torrentStorageHint,
            style: CbTypography.body.copyWith(
              color: context.cbColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (service.storageMode != 'index') ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CbSpacing.sm),
              child: SelectableText(
                service.libraryDirectory ?? l.torrentNoStorage,
              ),
            ),
            Wrap(
              spacing: CbSpacing.md,
              runSpacing: CbSpacing.md,
              children: [
                CbButton(
                  label: l.torrentStorage,
                  onPressed: service.scan.running || _busy
                      ? null
                      : () => _run(_chooseStorage),
                ),
                CbButton(
                  label: l.torrentOrganize,
                  onPressed:
                      service.scan.running ||
                          _busy ||
                          service.libraryDirectory == null
                      ? null
                      : () => _run(_organize),
                ),
              ],
            ),
            if (service.scan.running ||
                service.scan.visited > 0 ||
                service.scan.failed > 0) ...[
              Text(
                l.torrentScanSummary(
                  service.scan.visited,
                  service.scan.imported,
                  service.scan.duplicates,
                  service.scan.failed,
                ),
              ),
              Wrap(
                spacing: CbSpacing.md,
                runSpacing: CbSpacing.md,
                children: [
                  if (service.scan.running)
                    CbButton(label: l.cancel, onPressed: service.cancelScan),
                  if (service.scan.failed > 0)
                    CbButton(
                      label: l.torrentScanLog,
                      onPressed: () => OpenFilex.open(service.scanLogPath),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: CbSpacing.md,
          children: [
            Text(l.torrentOpeningOptions, style: CbTypography.headingSm),
            CheckboxListTile(
              key: const ValueKey('torrent-show-download-dialog'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.torrentShowDownloadDialog),
              subtitle: Text(l.torrentShowDownloadDialogHint),
              value: service.showDownloadDialog,
              onChanged: _busy
                  ? null
                  : (value) =>
                        _run(() => service.setShowDownloadDialog(value!)),
            ),
            CbTextField(
              key: const ValueKey('torrent-default-download-directory'),
              label: l.torrentColumn('destination'),
              controller: _downloadDirectory,
              placeholder: l.selectFolder,
              enabled: !_busy,
              onSubmitted: (_) => _run(_saveDownloadDirectory),
            ),
            Wrap(
              spacing: CbSpacing.md,
              runSpacing: CbSpacing.md,
              children: [
                CbButton(
                  key: const ValueKey('torrent-default-download-browse'),
                  label: l.browse,
                  icon: PhosphorIconsLight.folderOpen,
                  onPressed: _busy
                      ? null
                      : () => _run(_chooseDownloadDirectory),
                ),
                CbButton(
                  key: const ValueKey('torrent-default-download-save'),
                  label: l.save,
                  onPressed: _busy ? null : () => _run(_saveDownloadDirectory),
                ),
              ],
            ),
            CheckboxListTile(
              key: const ValueKey('torrent-default-start-immediately'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.torrentStartImmediately),
              value: service.startDownloadsImmediately,
              onChanged: _busy
                  ? null
                  : (value) => _run(
                      () => service.setStartDownloadsImmediately(value!),
                    ),
            ),
          ],
        ),
      if (Platform.isWindows)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: CbSpacing.md,
          children: [
            CbButton(
              label: l.torrentDefaultApps,
              icon: PhosphorIconsLight.gear,
              onPressed: () => _run(() async {
                if (!await WindowsAppIcon.openTorrentDefaultSettings()) {
                  throw StateError(l.operationFailed);
                }
              }),
            ),
            Text(
              l.torrentDefaultAppsHint,
              style: CbTypography.body.copyWith(
                color: context.cbColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: CbSpacing.md,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.torrentAutoImport),
            value: service.autoImport,
            onChanged: (value) => _run(() => service.setAutoImport(value!)),
          ),
          Text(l.torrentSources, style: CbTypography.headingSm),
          for (final source in service.scanRoots)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CbSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      source,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: CbSpacing.md),
                  CbButton.icon(
                    icon: PhosphorIconsLight.x,
                    tooltip: l.delete,
                    onPressed: () => _run(
                      () => service.setScanRoots(
                        service.scanRoots.where((s) => s != source).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: CbButton(
              label: l.torrentScanFolder,
              icon: PhosphorIconsLight.plus,
              onPressed: () => _run(() async {
                final path = await FilePicker.getDirectoryPath(
                  dialogTitle: l.torrentSources,
                );
                if (path != null) {
                  await service.setScanRoots([...service.scanRoots, path]);
                }
              }),
            ),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: CbSpacing.md,
        children: [
          if (service.executable != null) SelectableText(service.executable!),
          CbButton(
            label: l.torrentEngine,
            onPressed: () => _run(() async {
              final file = await FilePicker.pickFile();
              final path = file?.path;
              if (path != null) await service.setExecutable(path);
            }),
          ),
        ],
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
