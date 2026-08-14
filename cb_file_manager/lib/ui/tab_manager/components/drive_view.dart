import 'dart:io';
import 'dart:math' as math;

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/windows_shell_context_menu.dart';
import 'package:cb_file_manager/services/drive/drive_actions.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:cb_file_manager/services/drive/drive_inventory_service.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:cb_file_manager/ui/utils/entity_open_actions.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
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
  static const double _gridSpacing = 12.0;
  static const double _gridAspectRatio = 1.35;
  static const double _gridReferenceWidth = 960.0;

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

  const DriveView({
    Key? key,
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
  }) : super(key: key);

  @override
  State<DriveView> createState() => _DriveViewState();
}

class _DriveViewState extends State<DriveView> {
  List<DriveInfo> _drives = const <DriveInfo>[];
  bool _isLoadingDrives = false;
  Object? _loadError;

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    final cached = DriveInventoryService.cachedSnapshot;
    if (cached != null && cached.isNotEmpty) {
      _drives = cached;
    }
    if (!widget.isLazyLoading) {
      if (DriveInventoryService.hasFreshCache) {
        // Keep cached paint; still optional background refresh omitted when fresh.
      } else {
        _revalidateDrivesInBackground();
      }
    }
  }

  @override
  void didUpdateWidget(covariant DriveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabId != widget.tabId ||
        (oldWidget.isLazyLoading && !widget.isLazyLoading) ||
        (!oldWidget.isRefreshing && widget.isRefreshing)) {
      _reloadDriveEntries(force: true);
    }
  }

  Future<void> _revalidateDrivesInBackground() async {
    try {
      final entries = await DriveInventoryService.load();
      if (mounted) {
        setState(() => _drives = entries);
      }
    } catch (e) {
      debugPrint('Background drive revalidation failed: $e');
    }
  }

  Future<void> _reloadDriveEntries({bool force = false}) async {
    if (_isLoadingDrives) return;
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
    final isGridMode = _effectiveViewMode() == ViewMode.grid;
    final content = CtrlScrollZoom(
      onDelta: isGridMode ? widget.onZoomChanged : null,
      child: Listener(
        onPointerDown: _handlePointerDown,
        child: widget.isLazyLoading
            ? _buildSkeletonDriveList(context)
            : _buildActualDriveList(context),
      ),
    );

    if (Platform.isWindows && _effectiveViewMode() == ViewMode.list) {
      return ExcludeSemantics(child: content);
    }
    return content;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons == 8 && widget.onBackButtonPressed != null) {
      widget.onBackButtonPressed!();
    } else if (event.buttons == 16 && widget.onForwardButtonPressed != null) {
      widget.onForwardButtonPressed!();
    }
  }

  Widget _buildSkeletonDriveList(BuildContext context) {
    final bool isGrid = _effectiveViewMode() == ViewMode.grid;
    return SkeletonHelper.responsive(
      isGridView: isGrid,
      isAlbum: false,
      crossAxisCount: isGrid ? widget.gridZoomLevel : 1,
      itemCount: 6,
      wrapInCardOnDesktop: true,
    );
  }

  Widget _buildActualDriveList(BuildContext context) {
    if (_isLoadingDrives && _drives.isEmpty) {
      return _buildSkeletonDriveList(context);
    }
    if ((_loadError != null || _drives.isEmpty) && _drives.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)!.noStorageLocationsFound),
      );
    }

    if (_effectiveViewMode() == ViewMode.grid) {
      return _buildGridView(context, _drives);
    }
    return _buildListView(context, _drives);
  }

  ViewMode _effectiveViewMode() {
    if (widget.viewMode == ViewMode.grid ||
        widget.viewMode == ViewMode.gridPreview) {
      return ViewMode.grid;
    }
    return ViewMode.list;
  }

  List<_DriveSection> _sectionsFor(List<DriveInfo> drives) {
    final map = <DriveGroup, List<DriveInfo>>{};
    for (final drive in drives) {
      map.putIfAbsent(drive.group, () => <DriveInfo>[]).add(drive);
    }
    final order = <DriveGroup>[
      DriveGroup.fixed,
      DriveGroup.removable,
      DriveGroup.network,
      DriveGroup.other,
    ];
    return [
      for (final group in order)
        if (map[group]?.isNotEmpty == true)
          _DriveSection(group: group, drives: map[group]!),
    ];
  }

  String _groupTitle(BuildContext context, DriveGroup group) {
    final l10n = AppLocalizations.of(context)!;
    switch (group) {
      case DriveGroup.fixed:
        return l10n.driveGroupFixed;
      case DriveGroup.removable:
        return l10n.driveGroupRemovable;
      case DriveGroup.network:
        return l10n.driveGroupNetwork;
      case DriveGroup.other:
        return l10n.driveGroupOther;
    }
  }

  Widget _buildListView(BuildContext context, List<DriveInfo> drives) {
    final sections = _sectionsFor(drives);
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: sections.fold<int>(
        0,
        (sum, s) => sum + 1 + s.drives.length,
      ),
      itemBuilder: (context, index) {
        var cursor = 0;
        for (final section in sections) {
          if (index == cursor) {
            return Padding(
              padding: EdgeInsets.only(top: cursor == 0 ? 0 : 12, bottom: 8),
              child: Text(
                _groupTitle(context, section.group),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            );
          }
          cursor += 1;
          final driveIndex = index - cursor;
          if (driveIndex >= 0 && driveIndex < section.drives.length) {
            final drive = section.drives[driveIndex];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _buildDriveCard(
                key: ValueKey<String>('drive-list-${drive.path}'),
                context: context,
                drive: drive,
                compact: false,
              ),
            );
          }
          cursor += section.drives.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  static double _gridItemWidthForZoom(int zoomLevel) {
    final clamped = zoomLevel.clamp(
      UserPreferences.minGridZoomLevel,
      UserPreferences.maxGridZoomLevel,
    );
    final totalSpacing = DriveView._gridSpacing * (clamped - 1);
    return math.max(
      150.0,
      (DriveView._gridReferenceWidth - totalSpacing) / clamped,
    );
  }

  static int _gridCrossAxisCount(double availableWidth, double itemWidth) {
    final raw = ((availableWidth + DriveView._gridSpacing) /
            (itemWidth + DriveView._gridSpacing))
        .floor();
    return math.max(1, raw);
  }

  Widget _buildGridView(BuildContext context, List<DriveInfo> drives) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxZoom = GridZoomConstraints.maxGridSize(
          availableWidth: constraints.maxWidth,
          mode: GridSizeMode.referenceWidth,
          spacing: DriveView._gridSpacing,
          referenceWidth: DriveView._gridReferenceWidth,
          minValue: UserPreferences.minGridZoomLevel,
          maxValue: UserPreferences.maxGridZoomLevel,
        );
        final effectiveZoom = widget.gridZoomLevel
            .clamp(UserPreferences.minGridZoomLevel, maxZoom)
            .toInt();
        final itemWidth = _gridItemWidthForZoom(effectiveZoom);
        final availableWidth =
            math.max(0.0, constraints.maxWidth - (DriveView._gridSpacing * 2));
        final crossAxisCount = _gridCrossAxisCount(availableWidth, itemWidth);
        final itemHeight = itemWidth / DriveView._gridAspectRatio;

        return GridView.builder(
          padding: const EdgeInsets.all(16.0),
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          itemCount: drives.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: DriveView._gridSpacing,
            mainAxisSpacing: DriveView._gridSpacing,
            mainAxisExtent: itemHeight,
          ),
          itemBuilder: (context, index) {
            final drive = drives[index];
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: _buildDriveCard(
                  key: ValueKey<String>('drive-grid-${drive.path}'),
                  context: context,
                  drive: drive,
                  compact: true,
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _iconFor(DriveInfo drive) {
    switch (drive.kind) {
      case DriveKind.removable:
        return PhosphorIconsLight.usb;
      case DriveKind.network:
        return PhosphorIconsLight.cloud;
      case DriveKind.optical:
        return PhosphorIconsLight.disc;
      case DriveKind.ram:
        return PhosphorIconsLight.memory;
      case DriveKind.internal:
        return PhosphorIconsLight.deviceMobile;
      case DriveKind.fixed:
      case DriveKind.unknown:
        return PhosphorIconsLight.hardDrives;
    }
  }

  String _kindLabel(BuildContext context, DriveInfo drive) {
    final l10n = AppLocalizations.of(context)!;
    switch (drive.kind) {
      case DriveKind.fixed:
        return l10n.driveKindFixed;
      case DriveKind.removable:
        return l10n.driveKindRemovable;
      case DriveKind.network:
        return l10n.driveKindNetwork;
      case DriveKind.optical:
        return l10n.driveKindOptical;
      case DriveKind.ram:
        return l10n.driveKindRam;
      case DriveKind.internal:
        return l10n.driveKindInternal;
      case DriveKind.unknown:
        return l10n.driveKindUnknown;
    }
  }

  String _subtitleFor(BuildContext context, DriveInfo drive) {
    final l10n = AppLocalizations.of(context)!;
    final parts = <String>[];
    if (drive.filesystem.isNotEmpty) parts.add(drive.filesystem);
    parts.add(_kindLabel(context, drive));
    if (drive.requiresAdmin) parts.add(l10n.driveRestrictedAccess);
    return parts.join(' · ');
  }

  Widget _buildDriveCard({
    required Key key,
    required BuildContext context,
    required DriveInfo drive,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final space = drive.space;

    final Color progressColor = space.usageRatio > 0.9
        ? Colors.red
        : (space.usageRatio > 0.7
            ? Colors.orange
            : theme.colorScheme.primary);

    final Color progressBackgroundColor =
        isDarkMode ? Colors.grey[800]! : Colors.grey[200]!;
    final Color headerTextColor = isDarkMode ? Colors.white : Colors.black87;
    final Color subtitleColor =
        isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
    final cardColor = theme.colorScheme.surface.withValues(
      alpha: isDarkMode ? 0.58 : 0.64,
    );

    return Card(
      key: key,
      margin: EdgeInsets.zero,
      color: cardColor,
      elevation: 0,
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          _showDriveActions(context, drive, details.globalPosition);
        },
        onLongPressStart: (details) {
          _showDriveActions(context, drive, details.globalPosition);
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(12.0),
          onTap: _isDesktopPlatform
              ? null
              : () => _openDrive(context, drive.path),
          onDoubleTap: _isDesktopPlatform
              ? () => _openDrive(context, drive.path)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_iconFor(drive), size: compact ? 24 : 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            drive.displayName,
                            style: TextStyle(
                              fontSize: compact ? 14 : 17,
                              fontWeight: FontWeight.bold,
                              color: headerTextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _subtitleFor(context, drive),
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: compact ? 11 : 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (drive.canEject)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: l10n.driveEject,
                        icon: const Icon(PhosphorIconsLight.eject, size: 18),
                        onPressed: () => _confirmEject(context, drive),
                      )
                    else
                      const Icon(PhosphorIconsLight.caretRight, size: 16),
                  ],
                ),
                const SizedBox(height: 12),
                if (space.hasDetails) ...[
                  ExcludeSemantics(
                    child: LinearProgressIndicator(
                      value: space.usageRatio,
                      backgroundColor: progressBackgroundColor,
                      valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                      minHeight: compact ? 7 : 9,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (compact)
                    Text(
                      '${l10n.driveUsed}: ${FormatUtils.formatFileSize(space.usedBytes)}'
                      ' • ${l10n.driveFree}: ${FormatUtils.formatFileSize(space.freeBytes)}',
                      style: TextStyle(color: subtitleColor, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${l10n.driveUsed}: ${FormatUtils.formatFileSize(space.usedBytes)}',
                          style: TextStyle(
                            color: progressColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${l10n.driveFree}: ${FormatUtils.formatFileSize(space.freeBytes)}',
                          style: TextStyle(color: subtitleColor, fontSize: 12),
                        ),
                        Text(
                          '${l10n.driveTotal}: ${FormatUtils.formatFileSize(space.totalBytes)}',
                          style: TextStyle(color: subtitleColor, fontSize: 12),
                        ),
                      ],
                    ),
                ] else
                  Text(
                    drive.requiresAdmin
                        ? l10n.driveRestrictedAccess
                        : l10n.driveTapToBrowse,
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
    final canShowShellMenu = Platform.isWindows &&
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
          child: _menuRow(l10n.openInNewPane, PhosphorIconsLight.splitHorizontal),
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
        if (Platform.isWindows)
          PopupMenuItem(
            value: 'cleanup',
            child: _menuRow(l10n.driveCleanup, PhosphorIconsLight.broom),
          ),
        PopupMenuItem(
          value: 'open_cleaner',
          child: _menuRow(l10n.driveOpenInCleaner, PhosphorIconsLight.magicWand),
        ),
        if (Platform.isWindows && !drive.isSystemVolume)
          PopupMenuItem(
            value: 'format',
            child: _menuRow(l10n.driveFormat, PhosphorIconsLight.floppyDiskBack),
          ),
        if (Platform.isWindows)
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
                title: Text(drive.displayName),
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
      case 'rename':
        await _promptRename(context, drive);
        break;
      case 'eject':
        await _confirmEject(context, drive);
        break;
      case 'open_terminal':
        final ok = await DriveActions.openTerminal(drive.path);
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
          content: Text(l10n.driveEjectConfirmMessage(drive.displayName)),
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
      toast.error(l10n.driveEjectFailed(drive.displayName));
    }
  }

  Future<void> _confirmFormat(BuildContext context, DriveInfo drive) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.driveFormatConfirmTitle),
          content: Text(l10n.driveFormatConfirmMessage(drive.displayName)),
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
      toast.error(l10n.startFormatFailed(drive.displayName));
    }
  }

  Future<void> _promptRename(BuildContext context, DriveInfo drive) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: drive.label);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.driveRenameTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.driveRenameHint),
            maxLength: 32,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.driveRename),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    final toast = AppToast.capture(context);
    final ok = await DriveActions.rename(drive, controller.text);
    if (!context.mounted) return;
    if (ok) {
      toast.info(l10n.driveRenameSuccess);
      await _reloadDriveEntries(force: true);
    } else {
      toast.error(l10n.driveRenameFailed(controller.text));
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
    final usagePercent =
        (space.usageRatio * 100).clamp(0, 100).toStringAsFixed(1);

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
                _propertyRow('Name', drive.displayName),
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
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }

  void _openDrive(BuildContext context, String drivePath) {
    context.read<TabManagerBloc>().add(UpdateTabPath(widget.tabId, drivePath));
    context
        .read<TabManagerBloc>()
        .add(UpdateTabName(widget.tabId, _tabNameForPath(drivePath)));
    widget.onPathChanged(drivePath);
    widget.folderListBloc.add(FolderListLoad(drivePath));
  }

  String _tabNameForPath(String drivePath) {
    final normalized = drivePath.replaceAll('\\', '/');
    final parts =
        normalized.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return drivePath;
    return parts.last;
  }
}

class _DriveSection {
  final DriveGroup group;
  final List<DriveInfo> drives;

  const _DriveSection({required this.group, required this.drives});
}
