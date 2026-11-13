import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/helpers/core/desktop_shortcuts.dart';
import 'package:cb_file_manager/ui/controllers/file_operations_handler.dart';
import 'package:cb_file_manager/ui/widgets/file_tree_view.dart';
import 'package:cb_file_manager/ui/widgets/miller_columns_view.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_keyboard_shortcuts.dart';
import 'package:cb_file_manager/ui/components/common/file_entry_presentation.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_focus_gate.dart';
import 'package:cb_file_manager/ui/utils/view_mode_utils.dart';
import 'drive_browser_content.dart';
import 'drive_avatar.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/windows_shell_context_menu.dart';
import 'package:cb_file_manager/services/drive/drive_actions.dart';
import 'package:cb_file_manager/services/drive/drive_browser_entries.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:cb_file_manager/services/drive/drive_inventory_service.dart';
import 'package:cb_file_manager/services/drive/macos_volumes.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:cb_file_manager/ui/utils/entity_open_actions.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';
import 'package:cb_file_manager/ui/widgets/ctrl_scroll_zoom.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../components/common/skeleton_helper.dart';
import '../../screens/folder_list/folder_list_bloc.dart';
import '../../screens/folder_list/folder_list_event.dart';
import '../../screens/folder_list/folder_list_state.dart';
import '../core/tab_manager.dart';

/// Component for displaying and managing local drives / storage volumes.
class DriveView extends StatefulWidget {
  final String tabId;
  final Function(String) onPathChanged;
  final FolderListBloc folderListBloc;
  final VoidCallback? onBackButtonPressed;
  final VoidCallback? onForwardButtonPressed;
  final bool isLazyLoading;
  final ViewMode viewMode;
  final int gridZoomLevel;
  final ValueChanged<int>? onZoomChanged;
  final bool isRefreshing;
  final String searchQuery;
  final SortOption sortOption;
  final bool showProperties;
  final ValueChanged<SortOption>? onSort;
  final VoidCallback? onClearSearch;
  final Set<DriveDetailsColumn> visibleColumns;

  const DriveView({
    super.key,
    required this.tabId,
    required this.onPathChanged,
    required this.folderListBloc,
    this.onBackButtonPressed,
    this.onForwardButtonPressed,
    this.isLazyLoading = false,
    this.viewMode = ViewMode.list,
    this.gridZoomLevel = 4,
    this.onZoomChanged,
    this.isRefreshing = false,
    this.searchQuery = '',
    this.sortOption = SortOption.nameAsc,
    this.showProperties = false,
    this.onSort,
    this.onClearSearch,
    this.visibleColumns = const {
      DriveDetailsColumn.name,
      DriveDetailsColumn.path,
      DriveDetailsColumn.type,
      DriveDetailsColumn.filesystem,
      DriveDetailsColumn.total,
      DriveDetailsColumn.free,
      DriveDetailsColumn.used,
    },
  });

  @override
  State<DriveView> createState() => _DriveViewState();
}

class _DriveViewState extends State<DriveView> {
  List<DriveInfo> _drives = const <DriveInfo>[];
  bool _isLoadingDrives = false;
  Object? _loadError;
  final _browserSelection = SelectionBloc();
  final _focusNode = FocusNode(debugLabel: 'drive browser');
  late final TabbedFolderDragSelectionController _dragSelection;
  int _hierarchyRevision = 0;
  DriveGroup? _groupFilter;

  List<DriveInfo> _matchingDrives(BuildContext context) =>
      DriveBrowserEntries.filterAndSort(
        _drives.map((d) => d.copyWith(displayName: _driveName(context, d))),
        query: widget.searchQuery,
        sortOption: widget.sortOption,
      );

  List<DriveInfo> _visibleDrives(BuildContext context) {
    final matching = _matchingDrives(context);
    final visible =
        _groupFilter == null || !matching.any((d) => d.group == _groupFilter)
        ? matching
        : matching.where((d) => d.group == _groupFilter).toList();
    final mode = ViewModeUtils.normalize(widget.viewMode);
    return {ViewMode.list, ViewMode.tiles, ViewMode.grid}.contains(mode)
        ? DriveBrowserEntries.groupForDisplay(
            visible,
            descending: widget.sortOption == SortOption.typeDesc,
          )
        : visible;
  }

  StreamSubscription<void>? _volumeChanges;

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _dragSelection = TabbedFolderDragSelectionController(
      selectionBloc: _browserSelection,
      folderPaths: () => _drives.map((d) => d.path),
    );
    _volumeChanges = MacosVolumes.changes.listen(
      (_) => _reloadDriveEntries(force: true),
      onError: (Object e) => debugPrint('Volume changes failed: $e'),
    );
    final cached = DriveInventoryService.cachedSnapshot;
    if (cached != null && cached.isNotEmpty) {
      _drives = cached;
    }
    if (!widget.isLazyLoading) {
      if (DriveInventoryService.hasFreshCache) {
        // Keep cached paint; still optional background refresh omitted when fresh.
      } else {
        _reloadDriveEntries();
      }
    }
  }

  @override
  void didUpdateWidget(covariant DriveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _groupFilter = null;
      _browserSelection.add(ClearSelection());
    }
    if (oldWidget.tabId != widget.tabId ||
        (oldWidget.isLazyLoading && !widget.isLazyLoading) ||
        (!oldWidget.isRefreshing && widget.isRefreshing)) {
      _reloadDriveEntries(force: true);
    }
  }

  @override
  void dispose() {
    _volumeChanges?.cancel();
    _focusNode.dispose();
    _dragSelection.dispose();
    unawaited(_browserSelection.close());
    super.dispose();
  }

  Future<void> _reloadDriveEntries({bool force = false}) async {
    if (_isLoadingDrives) return;
    _hierarchyRevision++;
    if (mounted) {
      setState(() {
        _isLoadingDrives = true;
        _loadError = null;
      });
    }
    try {
      if (force) DriveInventoryService.invalidateCache();
      final entries = await DriveInventoryService.load(forceRefresh: force);
      if (!mounted) return;
      setState(() => _drives = entries);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _isLoadingDrives = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SelectionBloc>.value(
      value: _browserSelection,
      child: Focus(
        focusNode: _focusNode,
        autofocus: _isDesktopPlatform,
        onKeyEvent: (_, event) => _handleKeyEvent(event),
        child: CtrlScrollZoom(
          onDelta: widget.onZoomChanged,
          child: BlocBuilder<SelectionBloc, SelectionState>(
            bloc: _browserSelection,
            builder: (context, selection) => widget.isLazyLoading
                ? _buildSkeletonDriveList(context)
                : _buildActualDriveList(context, selection),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonDriveList(BuildContext context) => SkeletonHelper.files(
    viewMode: ViewModeUtils.normalize(widget.viewMode),
    gridZoomLevel: widget.gridZoomLevel,
    itemCount: 6,
    drives: true,
  );

  Widget _emptyState(BuildContext context, {required bool noMatches}) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              noMatches
                  ? PhosphorIconsLight.magnifyingGlass
                  : PhosphorIconsLight.hardDrives,
              size: 48,
              color: context.cbColors.iconSubtle,
            ),
            const SizedBox(height: 16),
            Text(
              noMatches
                  ? l.noResultsFound
                  : _loadError != null
                  ? l.errorAccessingDirectory
                  : l.noStorageLocationsFound,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 18),
            CbButton(
              label: noMatches ? l.clearSearch : l.retry,
              icon: noMatches
                  ? PhosphorIconsLight.x
                  : PhosphorIconsLight.arrowsClockwise,
              onPressed: noMatches
                  ? widget.onClearSearch
                  : () => _reloadDriveEntries(force: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActualDriveList(BuildContext context, SelectionState selection) {
    if (_isLoadingDrives && _drives.isEmpty) {
      return _buildSkeletonDriveList(context);
    }
    if (_drives.isEmpty) return _emptyState(context, noMatches: false);
    final drives = _visibleDrives(context);
    if (drives.isEmpty) return _emptyState(context, noMatches: true);
    return DriveBrowserContent(
      drives: drives,
      availableDrives: _matchingDrives(context),
      groupFilter: _groupFilter,
      onGroupFilterChanged: (group) {
        setState(() {
          _groupFilter = group;
          _hierarchyRevision++;
        });
        _browserSelection.add(ClearSelection());
      },
      viewMode: ViewModeUtils.normalize(widget.viewMode),
      gridZoom: widget.gridZoomLevel,
      selectedPaths: selection.allSelectedPaths.toSet(),
      focusedPath: selection.lastSelectedPath,
      showProperties: widget.showProperties,
      visibleColumns: widget.visibleColumns,
      onSelect: (drive) {
        _focusNode.requestFocus();
        if (!_isDesktopPlatform) {
          _openDrive(context, drive.path);
          return;
        }
        _selectPath(drive.path, drives);
      },
      selectOnPointerDown: _isDesktopPlatform,
      onOpen: (drive) => _openDrive(context, drive.path),
      onOpenInNewTab: (drive) =>
          EntityOpenActions.openInNewTab(context, sourcePath: drive.path),
      onMenu: (drive, position) {
        _browserSelection.add(ToggleFolderSelection(drive.path));
        _showDriveActions(context, drive, position);
      },
      onSort:
          widget.onSort ??
          (option) => widget.folderListBloc.add(
            SetSortOption(option, folderPath: kDrivesPath),
          ),
      sortOption: DriveBrowserEntries.effectiveSort(widget.sortOption),
      hierarchyBuilder: () => _buildHierarchy(context, drives, selection),
    );
  }

  void _selectPath(String path, List<DriveInfo> visible) {
    final keyboard = HardwareKeyboard.instance;
    final anchor = visible.indexWhere(
      (d) => d.path == _browserSelection.state.lastSelectedPath,
    );
    final index = visible.indexWhere((d) => d.path == path);
    if (keyboard.isShiftPressed && anchor >= 0 && index >= 0) {
      final first = anchor < index ? anchor : index;
      final last = anchor > index ? anchor : index;
      _browserSelection.add(
        SelectItemsInRect(
          folderPaths: visible
              .sublist(first, last + 1)
              .map((d) => d.path)
              .toSet(),
          filePaths: const {},
          isShiftPressed: true,
          isCtrlPressed: DesktopShortcuts.isPrimaryPressed,
          lastSelectedPath: path,
        ),
      );
    } else {
      _browserSelection.add(
        ToggleFolderSelection(
          path,
          ctrlSelect: DesktopShortcuts.isPrimaryPressed,
        ),
      );
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (!_isDesktopPlatform ||
        !TabFocusGate.isActiveTab(context) ||
        BrowserLikeKeyboardShortcuts.isTextInputFocused() ||
        event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final visible = _visibleDrives(context);
    final selection = _browserSelection.state;
    final selected = visible
        .where((d) => d.path == selection.lastSelectedPath)
        .firstOrNull;
    final key = event.logicalKey;
    if (DesktopShortcuts.matchesPrimary(event, LogicalKeyboardKey.keyA)) {
      _browserSelection.add(
        SelectAll(
          allFilePaths: const [],
          allFolderPaths: visible.map((d) => d.path).toList(),
        ),
      );
    } else if (DesktopShortcuts.matchesPrimary(
      event,
      LogicalKeyboardKey.keyC,
    )) {
      _copyPaths(selection.allSelectedPaths);
    } else if (key == LogicalKeyboardKey.escape) {
      _browserSelection.add(ClearSelection());
    } else if (key == LogicalKeyboardKey.enter && selected != null) {
      if (HardwareKeyboard.instance.isAltPressed) {
        _showDrivePropertiesDialog(context, selected);
      } else {
        _openDrive(context, selected.path);
      }
    } else if (key == LogicalKeyboardKey.f2 && selected?.canRename == true) {
      _promptRename(context, selected!);
    } else if (key == LogicalKeyboardKey.contextMenu && selected != null) {
      final box = context.findRenderObject() as RenderBox;
      _showDriveActions(
        context,
        selected,
        box.localToGlobal(const Offset(40, 100)),
      );
    } else if ([
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.home,
          LogicalKeyboardKey.end,
        ].contains(key) &&
        visible.isNotEmpty) {
      final current = visible.indexWhere(
        (d) => d.path == selection.lastSelectedPath,
      );
      final index = key == LogicalKeyboardKey.home
          ? 0
          : key == LogicalKeyboardKey.end
          ? visible.length - 1
          : (current + (key == LogicalKeyboardKey.arrowUp ? -1 : 1)).clamp(
              0,
              visible.length - 1,
            );
      _selectPath(visible[index].path, visible);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _copyPaths(Iterable<String> paths) {
    if (paths.isNotEmpty) {
      unawaited(Clipboard.setData(ClipboardData(text: paths.join('\n'))));
    }
  }

  Widget _buildHierarchy(
    BuildContext context,
    List<DriveInfo> drives,
    SelectionState selection,
  ) {
    final state = FolderListState(
      kDrivesPath,
      folders: drives.map((d) => Directory(d.path)).toList(),
      viewMode: widget.viewMode,
      sortOption: widget.sortOption,
    );
    void selectFolder(
      String path, {
      bool shiftSelect = false,
      bool ctrlSelect = false,
    }) {
      _browserSelection.add(
        ToggleFolderSelection(
          path,
          shiftSelect: shiftSelect,
          ctrlSelect: ctrlSelect,
        ),
      );
    }

    void selectFile(
      String path, {
      bool shiftSelect = false,
      bool ctrlSelect = false,
    }) {
      _browserSelection.add(
        ToggleFileSelection(
          path,
          shiftSelect: shiftSelect,
          ctrlSelect: ctrlSelect,
        ),
      );
    }

    void openFile(File file, bool _) => FileOperationsHandler.onFileTap(
      context: context,
      file: file,
      folderListBloc: widget.folderListBloc,
      selectionBloc: _browserSelection,
      onNavigateToPath: (path) => _openDrive(context, path),
    );
    void entityMenu(FileSystemEntity entity, Offset position) {
      final drive = drives.where((d) => d.path == entity.path).firstOrNull;
      if (drive != null) {
        _browserSelection.add(ToggleFolderSelection(drive.path));
        _showDriveActions(context, drive, position);
      } else {
        _showChildMenu(context, entity, position);
      }
    }

    final key = ValueKey(
      '${widget.viewMode}-$_hierarchyRevision-${widget.searchQuery}',
    );
    Widget withDriveNames(Widget child) => FileEntryPresentation(
      names: {
        for (final drive in drives)
          drive.path: drive.displayName.isEmpty
              ? drive.path
              : drive.displayName,
      },
      leadingBuilder: (context, path, size) {
        final drive = drives.where((d) => d.path == path).firstOrNull;
        return drive == null ? null : DriveAvatar(drive: drive, size: size);
      },
      child: child,
    );
    if (widget.viewMode == ViewMode.tree) {
      return withDriveNames(
        FileTreeView(
          key: key,
          state: state,
          selectionState: selection,
          isDesktopPlatform: _isDesktopPlatform,
          onNavigateToPath: (path) => _openDrive(context, path),
          onFileTap: openFile,
          toggleFolderSelection: selectFolder,
          toggleFileSelection: selectFile,
          clearSelection: () => _browserSelection.add(ClearSelection()),
          onEntityContextMenu: entityMenu,
          showContextMenu: (_, _) {},
        ),
      );
    }
    return withDriveNames(
      MillerColumnsView(
        key: key,
        state: state,
        selectionState: selection,
        isDesktopPlatform: _isDesktopPlatform,
        onNavigateToPath: (path) => _openDrive(context, path),
        onFileTap: openFile,
        toggleFolderSelection: selectFolder,
        toggleFileSelection: selectFile,
        clearSelection: () => _browserSelection.add(ClearSelection()),
        dragSelectionController: _dragSelection,
        showFileTags: false,
        showDeleteTagDialog: (_, _, _) {},
        showAddTagToFileDialog: (_, _) {},
        toggleSelectionMode: () {},
        showContextMenu: (_, _) {},
        onEntityContextMenu: entityMenu,
      ),
    );
  }

  Future<void> _showChildMenu(
    BuildContext context,
    FileSystemEntity entity,
    Offset position,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final l = AppLocalizations.of(context)!;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'open', child: Text(l.open)),
        PopupMenuItem(value: 'tab', child: Text(l.openInNewTab)),
        PopupMenuItem(value: 'copy_path', child: Text(l.ivCopyPath)),
      ],
    );
    if (!context.mounted) return;
    if (action == 'copy_path') {
      _copyPaths([entity.path]);
    }
    if (action == 'open' && entity is Directory) {
      _openDrive(context, entity.path);
    }
    if (action == 'tab' || action == 'open' && entity is File) {
      EntityOpenActions.openInNewTab(context, sourcePath: entity.path);
    }
  }

  String _kindLabel(BuildContext context, DriveInfo drive) =>
      driveKindLabel(context, drive);
  String _subtitleFor(BuildContext context, DriveInfo drive) => [
    if (drive.filesystem.isNotEmpty) drive.filesystem,
    _kindLabel(context, drive),
    if (drive.requiresAdmin)
      AppLocalizations.of(context)!.driveRestrictedAccess,
  ].join(' · ');

  Future<void> _showDriveActions(
    BuildContext context,
    DriveInfo drive,
    Offset globalPosition,
  ) async {
    if (_isDesktopPlatform) {
      await _showDesktopContextMenu(context, drive, globalPosition);
    } else {
      await _showMobileActionSheet(context, drive);
    }
  }

  Future<void> _showDesktopContextMenu(
    BuildContext context,
    DriveInfo drive,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final prefs = UserPreferences.instance;
    await prefs.init();
    final isPinned = await prefs.isPathPinnedToSidebar(drive.path);
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final openInNewWindowText = '${l10n.open} ${l10n.newWindow.toLowerCase()}';
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
    final canShowShellMenu =
        Platform.isWindows &&
        drive.kind != DriveKind.wsl &&
        FileSystemEntity.typeSync(drive.path) != FileSystemEntityType.notFound;
    final menuColor = Theme.of(context).colorScheme.surface.withAlpha(255);

    final selected = await showMenu<String>(
      context: context,
      position: position,
      color: menuColor,
      items: <PopupMenuEntry<String>>[
        PopupMenuItem(
          value: 'open',
          child: _menuRow(l10n.open, PhosphorIconsLight.folderOpen),
        ),
        PopupMenuItem(
          value: 'open_new_tab',
          child: _menuRow(l10n.openInNewTab, PhosphorIconsLight.squaresFour),
        ),
        PopupMenuItem(
          value: 'open_new_window',
          child: _menuRow(openInNewWindowText, PhosphorIconsLight.appWindow),
        ),
        PopupMenuItem(
          value: 'open_new_pane',
          child: _menuRow(
            l10n.openInNewPane,
            PhosphorIconsLight.splitHorizontal,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'toggle_pin_sidebar',
          child: _menuRow(
            isPinned ? l10n.unpinFromSidebar : l10n.pinToSidebar,
            isPinned
                ? PhosphorIconsLight.pushPinSlash
                : PhosphorIconsLight.pushPin,
          ),
        ),
        PopupMenuItem(
          value: 'properties',
          child: _menuRow(l10n.properties, PhosphorIconsLight.info),
        ),
        PopupMenuItem(
          value: 'copy_path',
          child: _menuRow(l10n.ivCopyPath, PhosphorIconsLight.copy),
        ),
        if (drive.canRename)
          PopupMenuItem(
            value: 'rename',
            child: _menuRow(l10n.driveRename, PhosphorIconsLight.pencilSimple),
          ),
        if (drive.canEject)
          PopupMenuItem(
            value: 'eject',
            child: _menuRow(l10n.driveEject, PhosphorIconsLight.eject),
          ),
        if (Platform.isWindows)
          PopupMenuItem(
            value: 'open_terminal',
            child: _menuRow(
              l10n.openInWindowsTerminal,
              PhosphorIconsLight.terminalWindow,
            ),
          ),
        if (Platform.isWindows && drive.isWindowsVolume)
          PopupMenuItem(
            value: 'cleanup',
            child: _menuRow(l10n.driveCleanup, PhosphorIconsLight.broom),
          ),
        PopupMenuItem(
          value: 'open_cleaner',
          child: _menuRow(
            l10n.driveOpenInCleaner,
            PhosphorIconsLight.magicWand,
          ),
        ),
        if (Platform.isWindows &&
            drive.isWindowsVolume &&
            !drive.isSystemVolume)
          PopupMenuItem(
            value: 'format',
            child: _menuRow(
              l10n.driveFormat,
              PhosphorIconsLight.floppyDiskBack,
            ),
          ),
        if (Platform.isWindows && drive.isWindowsVolume)
          PopupMenuItem(
            value: 'bitlocker',
            child: _menuRow(l10n.driveBitLocker, PhosphorIconsLight.lockSimple),
          ),
        if (canShowShellMenu) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'more_options',
            child: _menuRow(
              l10n.moreOptions,
              PhosphorIconsLight.dotsThreeVertical,
            ),
          ),
        ],
      ],
    );

    if (selected == null || !context.mounted) return;
    await _handleAction(
      context,
      drive,
      selected,
      globalPosition: globalPosition,
      devicePixelRatio: devicePixelRatio,
    );
  }

  Future<void> _showMobileActionSheet(
    BuildContext context,
    DriveInfo drive,
  ) async {
    final prefs = UserPreferences.instance;
    await prefs.init();
    final isPinned = await prefs.isPathPinnedToSidebar(drive.path);
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(_driveName(context, drive)),
                subtitle: Text(_subtitleFor(context, drive)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(PhosphorIconsLight.folderOpen),
                title: Text(l10n.open),
                onTap: () => Navigator.pop(sheetContext, 'open'),
              ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.squaresFour),
                title: Text(l10n.openInNewTab),
                onTap: () => Navigator.pop(sheetContext, 'open_new_tab'),
              ),
              ListTile(
                leading: Icon(
                  isPinned
                      ? PhosphorIconsLight.pushPinSlash
                      : PhosphorIconsLight.pushPin,
                ),
                title: Text(
                  isPinned ? l10n.unpinFromSidebar : l10n.pinToSidebar,
                ),
                onTap: () => Navigator.pop(sheetContext, 'toggle_pin_sidebar'),
              ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.info),
                title: Text(l10n.properties),
                onTap: () => Navigator.pop(sheetContext, 'properties'),
              ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.copy),
                title: Text(l10n.ivCopyPath),
                onTap: () => Navigator.pop(sheetContext, 'copy_path'),
              ),
              if (drive.canRename)
                ListTile(
                  leading: const Icon(PhosphorIconsLight.pencilSimple),
                  title: Text(l10n.driveRename),
                  onTap: () => Navigator.pop(sheetContext, 'rename'),
                ),
              if (drive.canEject)
                ListTile(
                  leading: const Icon(PhosphorIconsLight.eject),
                  title: Text(l10n.driveEject),
                  onTap: () => Navigator.pop(sheetContext, 'eject'),
                ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.magicWand),
                title: Text(l10n.driveOpenInCleaner),
                onTap: () => Navigator.pop(sheetContext, 'open_cleaner'),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || !context.mounted) return;
    await _handleAction(context, drive, selected);
  }

  Future<void> _handleAction(
    BuildContext context,
    DriveInfo drive,
    String action, {
    Offset? globalPosition,
    double? devicePixelRatio,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final toast = AppToast.capture(context);

    switch (action) {
      case 'open':
        _openDrive(context, drive.path);
        break;
      case 'open_new_tab':
        EntityOpenActions.openInNewTab(context, sourcePath: drive.path);
        break;
      case 'open_new_window':
        await EntityOpenActions.openInNewWindow(
          context,
          sourcePath: drive.path,
        );
        break;
      case 'open_new_pane':
        EntityOpenActions.openInNewPane(context, sourcePath: drive.path);
        break;
      case 'toggle_pin_sidebar':
        await _togglePinSidebar(context, drive.path);
        break;
      case 'properties':
        _showDrivePropertiesDialog(context, drive);
        break;
      case 'copy_path':
        _copyPaths([drive.path]);
        break;
      case 'rename':
        await _promptRename(context, drive);
        break;
      case 'eject':
        await _confirmEject(context, drive);
        break;
      case 'open_terminal':
        final ok = await DriveActions.openTerminal(
          drive.path,
          distribution: drive.kind == DriveKind.wsl ? drive.label : null,
        );
        if (!ok && context.mounted) {
          toast.error(l10n.openTerminalFailed('Windows Terminal'));
        }
        break;
      case 'cleanup':
        final ok = await DriveActions.openCleanup(drive.path);
        if (!ok && context.mounted) {
          toast.error(l10n.startCleanupFailed('cleanmgr'));
        }
        break;
      case 'open_cleaner':
        context.read<TabManagerBloc>().add(
          AddTab(path: kCbAgentCleanerPath, name: l10n.driveOpenInCleaner),
        );
        break;
      case 'format':
        await _confirmFormat(context, drive);
        break;
      case 'bitlocker':
        final ok = await DriveActions.openBitLocker();
        if (!ok && context.mounted) {
          toast.error(
            'Unable to open BitLocker. Open Control Panel > BitLocker Drive Encryption manually.',
          );
        }
        break;
      case 'more_options':
        if (globalPosition != null && devicePixelRatio != null) {
          await WindowsShellContextMenu.showForPaths(
            paths: <String>[drive.path],
            globalPosition: globalPosition,
            devicePixelRatio: devicePixelRatio,
          );
        }
        break;
    }
  }

  Widget _menuRow(String title, IconData icon, {Color? color}) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: color)),
      ],
    );
  }

  Future<void> _confirmEject(BuildContext context, DriveInfo drive) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.driveEjectConfirmTitle),
          content: Text(
            l10n.driveEjectConfirmMessage(_driveName(context, drive)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.driveEject),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final toast = AppToast.capture(context);
    final ok = await DriveActions.eject(drive);
    if (!context.mounted) return;
    if (ok) {
      toast.info(l10n.driveEjectSuccess);
      await _reloadDriveEntries(force: true);
    } else {
      toast.error(l10n.driveEjectFailed(_driveName(context, drive)));
    }
  }

  Future<void> _confirmFormat(BuildContext context, DriveInfo drive) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.driveFormatConfirmTitle),
          content: Text(
            l10n.driveFormatConfirmMessage(_driveName(context, drive)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.driveFormat),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    final toast = AppToast.capture(context);
    final ok = await DriveActions.openFormat(drive);
    if (!ok && context.mounted) {
      toast.error(l10n.startFormatFailed(_driveName(context, drive)));
    }
  }

  Future<void> _promptRename(BuildContext context, DriveInfo drive) async {
    final l10n = AppLocalizations.of(context)!;
    final anchorRect = cbAnchorRectOf(context);
    final newLabel = await showCbInlineRename(
      context: context,
      title: l10n.driveRenameTitle,
      subtitle: _driveName(context, drive),
      initialValue: drive.label,
      icon: PhosphorIconsLight.hardDrives,
      hintText: l10n.renameShortcutHint,
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.driveRename,
      anchorRect: anchorRect,
      // Windows volume labels cap out at 32 characters.
      maxLength: 32,
      validator: (value) =>
          value.trim().isEmpty ? l10n.renameNameRequired : null,
    );
    if (newLabel == null || !context.mounted) return;
    final toast = AppToast.capture(context);
    final ok = await DriveActions.rename(drive, newLabel);
    if (!context.mounted) return;
    if (ok) {
      toast.info(l10n.driveRenameSuccess);
      await _reloadDriveEntries(force: true);
    } else {
      toast.error(l10n.driveRenameFailed(newLabel));
    }
  }

  Future<void> _togglePinSidebar(BuildContext context, String path) async {
    final l10n = AppLocalizations.of(context)!;
    final toast = AppToast.capture(context);
    final prefs = UserPreferences.instance;
    await prefs.init();
    final isPinned = await prefs.isPathPinnedToSidebar(path);
    if (isPinned) {
      await prefs.removeSidebarPinnedPath(path);
    } else {
      await prefs.addSidebarPinnedPath(path);
    }
    if (!context.mounted) return;
    toast.info(isPinned ? l10n.removedFromSidebar : l10n.pinnedToSidebar);
  }

  void _showDrivePropertiesDialog(BuildContext context, DriveInfo drive) {
    final l10n = AppLocalizations.of(context)!;
    final space = drive.space;
    final usagePercent = (space.usageRatio * 100)
        .clamp(0, 100)
        .toStringAsFixed(1);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.properties),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _propertyRow('Name', _driveName(context, drive)),
                const Divider(),
                _propertyRow(l10n.filePath, drive.path),
                const Divider(),
                _propertyRow(l10n.driveType, _kindLabel(context, drive)),
                if (drive.filesystem.isNotEmpty) ...[
                  const Divider(),
                  _propertyRow(l10n.driveFilesystem, drive.filesystem),
                ],
                if (drive.volumeSerial != null &&
                    drive.volumeSerial!.isNotEmpty) ...[
                  const Divider(),
                  _propertyRow(l10n.driveSerial, drive.volumeSerial!),
                ],
                if (space.hasDetails) ...<Widget>[
                  const Divider(),
                  _propertyRow(
                    l10n.driveUsed,
                    FormatUtils.formatFileSize(space.usedBytes),
                  ),
                  const Divider(),
                  _propertyRow(
                    l10n.driveFree,
                    FormatUtils.formatFileSize(space.freeBytes),
                  ),
                  const Divider(),
                  _propertyRow(
                    l10n.driveTotal,
                    FormatUtils.formatFileSize(space.totalBytes),
                  ),
                  const Divider(),
                  _propertyRow('Usage', '$usagePercent%'),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.close.toUpperCase()),
            ),
          ],
        );
      },
    );
  }

  Widget _propertyRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }

  void _openDrive(BuildContext context, String drivePath) {
    context.read<TabManagerBloc>().add(UpdateTabPath(widget.tabId, drivePath));
    context.read<TabManagerBloc>().add(
      UpdateTabName(widget.tabId, _tabNameForPath(drivePath)),
    );
    widget.onPathChanged(drivePath);
    widget.folderListBloc.add(FolderListLoad(drivePath));
  }

  String _tabNameForPath(String drivePath) {
    final normalized = drivePath.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return drivePath;
    return parts.last;
  }
}

/// Android reports the primary volume's label in the device language
/// ("Bộ nhớ trong dùng chung"), not the app's, so use our own string there.
String _driveName(BuildContext context, DriveInfo drive) {
  if (Platform.isAndroid && drive.isPrimary) {
    return AppLocalizations.of(context)?.internalStorage ?? drive.displayName;
  }
  return drive.displayName;
}
