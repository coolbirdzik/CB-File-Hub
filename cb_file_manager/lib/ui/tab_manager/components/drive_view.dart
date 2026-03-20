import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/windows_shell_context_menu.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/utils/entity_open_actions.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:win32/win32.dart' as win32;

import '../../components/common/skeleton_helper.dart';
import '../../screens/folder_list/folder_list_bloc.dart';
import '../../screens/folder_list/folder_list_event.dart';
import '../../screens/folder_list/folder_list_state.dart';
import '../core/tab_manager.dart';

/// Component for displaying local drives/local storage locations.
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
  List<_DriveEntry> _driveEntries = const <_DriveEntry>[];
  bool _isLoadingDrives = false;
  Object? _loadError;

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (!widget.isLazyLoading) {
      _reloadDriveEntries();
    }
  }

  @override
  void didUpdateWidget(covariant DriveView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.tabId != widget.tabId ||
        (oldWidget.isLazyLoading && !widget.isLazyLoading) ||
        (!oldWidget.isRefreshing && widget.isRefreshing)) {
      _reloadDriveEntries();
    }
  }

  Future<void> _reloadDriveEntries() async {
    if (_isLoadingDrives) return;

    if (mounted) {
      setState(() {
        _isLoadingDrives = true;
        _loadError = null;
      });
    }

    try {
      final entries = await _loadDriveEntries();
      if (!mounted) return;
      setState(() {
        _driveEntries = entries;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDrives = false;
        });
      }
    }
  }

  Future<List<_DriveEntry>> _loadDriveEntries() async {
    final List<Directory> drives = List<Directory>.from(
      await getAllStorageLocations(),
    )..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

    if (drives.isEmpty) {
      return const <_DriveEntry>[];
    }

    return Future.wait(
      drives.map((drive) async {
        final _DriveMeta meta = await _getDriveMeta(drive.path);
        return _DriveEntry(
          path: drive.path,
          displayName: meta.displayName,
          spaceInfo: meta.spaceInfo,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Listener(
      onPointerDown: _handlePointerDown,
      onPointerSignal: _handlePointerSignal,
      child: widget.isLazyLoading
          ? _buildSkeletonDriveList(context)
          : _buildActualDriveList(context),
    );

    // Workaround for intermittent Windows AXTree update errors in drives list mode.
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

  void _handlePointerSignal(PointerSignalEvent event) {
    if (widget.onZoomChanged == null || _effectiveViewMode() != ViewMode.grid) {
      return;
    }
    if (event is! PointerScrollEvent) return;

    final bool isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.logicalKeysPressed
            .contains(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed
            .contains(LogicalKeyboardKey.controlRight);
    if (!isCtrlPressed) return;

    final int direction = event.scrollDelta.dy > 0 ? 1 : -1;
    widget.onZoomChanged!.call(direction);
    GestureBinding.instance.pointerSignalResolver.resolve(event);
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
    if (_isLoadingDrives && _driveEntries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null && _driveEntries.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.noStorageLocationsFound,
        ),
      );
    }

    if (_driveEntries.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)!.noStorageLocationsFound),
      );
    }

    if (_effectiveViewMode() == ViewMode.grid) {
      return _buildGridView(context, _driveEntries);
    }
    return _buildListView(context, _driveEntries);
  }

  ViewMode _effectiveViewMode() {
    if (widget.viewMode == ViewMode.grid ||
        widget.viewMode == ViewMode.gridPreview) {
      return ViewMode.grid;
    }
    return ViewMode.list;
  }

  Widget _buildListView(BuildContext context, List<_DriveEntry> drives) {
    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
      itemCount: drives.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12.0),
      itemBuilder: (context, index) {
        return _buildDriveCard(
          key: ValueKey<String>('drive-list-${drives[index].path}'),
          context: context,
          drive: drives[index],
          compact: false,
        );
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

  Widget _buildGridView(BuildContext context, List<_DriveEntry> drives) {
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
          addSemanticIndexes: false,
          itemCount: drives.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: DriveView._gridSpacing,
            mainAxisSpacing: DriveView._gridSpacing,
            mainAxisExtent: itemHeight,
          ),
          itemBuilder: (context, index) {
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: _buildDriveCard(
                  key: ValueKey<String>('drive-grid-${drives[index].path}'),
                  context: context,
                  drive: drives[index],
                  compact: true,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDriveCard({
    required Key key,
    required BuildContext context,
    required _DriveEntry drive,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final _DriveSpaceInfo space = drive.spaceInfo;

    final Color progressColor = space.usageRatio > 0.9
        ? Colors.red
        : (space.usageRatio > 0.7
            ? Colors.orange
            : Theme.of(context).colorScheme.primary);

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
        onSecondaryTapDown: _isDesktopPlatform
            ? (details) {
                _showDriveContextMenu(
                  context,
                  drive,
                  details.globalPosition,
                );
              }
            : null,
        onLongPressStart: _isDesktopPlatform
            ? (details) {
                _showDriveContextMenu(
                  context,
                  drive,
                  details.globalPosition,
                );
              }
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12.0),
          onTap: () => _openDrive(context, drive.path),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      PhosphorIconsLight.hardDrives,
                      size: compact ? 24 : 32,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        drive.displayName,
                        style: TextStyle(
                          fontSize: compact ? 14 : 17,
                          fontWeight: FontWeight.bold,
                          color: headerTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
                      'Used: ${space.usedStr} • Free: ${space.freeStr}',
                      style: TextStyle(color: subtitleColor, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Used: ${space.usedStr}',
                          style: TextStyle(
                            color: progressColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Free: ${space.freeStr}',
                          style: TextStyle(color: subtitleColor, fontSize: 12),
                        ),
                        Text(
                          'Total: ${space.totalStr}',
                          style: TextStyle(color: subtitleColor, fontSize: 12),
                        ),
                      ],
                    ),
                ] else
                  Text(
                    'Tap to browse',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDriveContextMenu(
    BuildContext context,
    _DriveEntry drive,
    Offset globalPosition,
  ) async {
    if (!_isDesktopPlatform) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final prefs = UserPreferences.instance;
    await prefs.init();
    final isPinned = await prefs.isPathPinnedToSidebar(drive.path);
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final openInNewWindowText = _openInNewWindowLabel(context);
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
    final canShowShellMenu = Platform.isWindows &&
        FileSystemEntity.typeSync(drive.path) != FileSystemEntityType.notFound;

    final selected = await showMenu<String>(
      context: context,
      position: position,
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
          child:
              _menuRow('Open in new pane', PhosphorIconsLight.splitHorizontal),
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
        if (Platform.isWindows)
          PopupMenuItem(
            value: 'open_terminal',
            child: _menuRow(
                'Open in Windows Terminal', PhosphorIconsLight.terminalWindow),
          ),
        if (Platform.isWindows)
          PopupMenuItem(
            value: 'cleanup',
            child: _menuRow('Cleanup', PhosphorIconsLight.broom),
          ),
        if (Platform.isWindows)
          PopupMenuItem(
            value: 'format',
            child: _menuRow('Format', PhosphorIconsLight.floppyDiskBack),
          ),
        if (Platform.isWindows)
          PopupMenuItem(
            value: 'bitlocker',
            child: _menuRow('Turn on BitLocker', PhosphorIconsLight.lockSimple),
          ),
        if (canShowShellMenu) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'more_options',
            child: _menuRow(
                l10n.moreOptions, PhosphorIconsLight.dotsThreeVertical),
          ),
        ],
      ],
    );

    if (selected == null) return;
    if (!context.mounted) return;

    switch (selected) {
      case 'open':
        _openDrive(context, drive.path);
        break;
      case 'open_new_tab':
        EntityOpenActions.openInNewTab(context, sourcePath: drive.path);
        break;
      case 'open_new_window':
        await EntityOpenActions.openInNewWindow(context,
            sourcePath: drive.path);
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
      case 'open_terminal':
        await _openDriveInTerminal(context, drive.path);
        break;
      case 'cleanup':
        await _runDriveCleanup(context, drive.path);
        break;
      case 'format':
        await _formatDrive(context, drive.path);
        break;
      case 'bitlocker':
        await _openBitLocker(context, drive.path);
        break;
      case 'more_options':
        await WindowsShellContextMenu.showForPaths(
          paths: <String>[drive.path],
          globalPosition: globalPosition,
          devicePixelRatio: devicePixelRatio,
        );
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

  String _openInNewWindowLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return '${l10n.open} ${l10n.newWindow.toLowerCase()}';
  }

  Future<void> _openDriveInTerminal(
      BuildContext context, String drivePath) async {
    try {
      await Process.start(
        'wt.exe',
        <String>['-d', drivePath],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      try {
        await Process.start(
          'powershell.exe',
          <String>[
            '-NoExit',
            '-Command',
            "Set-Location -LiteralPath '${drivePath.replaceAll("'", "''")}'"
          ],
          mode: ProcessStartMode.detached,
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to open terminal: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _runDriveCleanup(BuildContext context, String drivePath) async {
    try {
      final driveLetter = drivePath.replaceAll('\\', '');
      await Process.start(
        'cleanmgr.exe',
        <String>['/d', driveLetter],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to start cleanup: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _formatDrive(BuildContext context, String drivePath) async {
    if (!Platform.isWindows) return;
    final driveLetter = _normalizeDriveLetter(drivePath);
    if (driveLetter == null) return;
    final driveRoot = '$driveLetter\\';

    try {
      final invoked = await WindowsShellContextMenu.invokeVerb(
        paths: <String>[driveRoot],
        verb: 'format',
      );
      if (invoked) return;

      final escapedDriveRoot = driveRoot.replaceAll("'", "''");
      await Process.start(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-Command',
          "Start-Process -FilePath '$escapedDriveRoot' -Verb Format",
        ],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to start format: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _openBitLocker(BuildContext context, String drivePath) async {
    if (!Platform.isWindows) return;

    Future<bool> tryStart(
      String executable,
      List<String> arguments, {
      bool runInShell = false,
    }) async {
      try {
        await Process.start(
          executable,
          arguments,
          mode: ProcessStartMode.detached,
          runInShell: runInShell,
        );
        return true;
      } catch (_) {
        return false;
      }
    }

    final String? driveLetter = _normalizeDriveLetter(drivePath);

    // Try native Control Panel entry first (works across most Windows versions).
    if (await tryStart(
      'control.exe',
      <String>['/name', 'Microsoft.BitLockerDriveEncryption'],
    )) {
      return;
    }

    // Try opening the specific drive configuration page when available.
    if (driveLetter != null &&
        await tryStart(
          'control.exe',
          <String>[
            '/name',
            'Microsoft.BitLockerDriveEncryption',
            '/page',
            'pageConfigureDrive',
            driveLetter,
          ],
        )) {
      return;
    }

    // Fallback through cmd shell start.
    if (await tryStart('cmd.exe', <String>[
      '/c',
      'start',
      '',
      'control.exe',
      '/name',
      'Microsoft.BitLockerDriveEncryption',
    ])) {
      return;
    }

    // Last fallback for modern Windows settings.
    if (await tryStart(
      'cmd.exe',
      <String>['/c', 'start', '', 'ms-settings:deviceencryption'],
      runInShell: true,
    )) {
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Unable to open BitLocker. Please open Control Panel > BitLocker Drive Encryption manually.',
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _togglePinSidebar(BuildContext context, String path) async {
    final prefs = UserPreferences.instance;
    await prefs.init();
    final isPinned = await prefs.isPathPinnedToSidebar(path);
    if (isPinned) {
      await prefs.removeSidebarPinnedPath(path);
    } else {
      await prefs.addSidebarPinnedPath(path);
    }
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final message = isPinned ? l10n.removedFromSidebar : l10n.pinnedToSidebar;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _normalizeDriveLetter(String drivePath) {
    var path = drivePath.trim();
    if (path.isEmpty) return null;
    path = path.replaceAll('\\', '');
    if (!path.contains(':')) return null;
    final driveLetter = path.substring(0, 2).toUpperCase();
    return driveLetter;
  }

  void _showDrivePropertiesDialog(BuildContext context, _DriveEntry drive) {
    final l10n = AppLocalizations.of(context)!;
    final space = drive.spaceInfo;
    final usagePercent =
        (space.usageRatio * 100).clamp(0, 100).toStringAsFixed(1);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.properties),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _propertyRow('Name', drive.displayName),
              const Divider(),
              _propertyRow(l10n.filePath, drive.path),
              if (space.hasDetails) ...<Widget>[
                const Divider(),
                _propertyRow('Used', space.usedStr),
                const Divider(),
                _propertyRow('Free', space.freeStr),
                const Divider(),
                _propertyRow('Total', space.totalStr),
                const Divider(),
                _propertyRow('Usage', '$usagePercent%'),
              ],
            ],
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
          width: 90,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }

  Future<_DriveMeta> _getDriveMeta(String drivePath) async {
    final String label = await _getDriveDisplayName(drivePath);
    final _DriveSpaceInfo spaceInfo = await _getDriveSpaceInfo(drivePath);
    return _DriveMeta(displayName: label, spaceInfo: spaceInfo);
  }

  Future<String> _getDriveDisplayName(String drivePath) async {
    if (Platform.isWindows) {
      final label = await getDriveLabel(drivePath);
      if (label.isNotEmpty) {
        return '$drivePath ($label)';
      }
    }
    return drivePath;
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
    if (parts.isEmpty) {
      return drivePath;
    }
    return parts.last;
  }

  Future<_DriveSpaceInfo> _getDriveSpaceInfo(String drivePath) async {
    if (!Platform.isWindows) {
      return _DriveSpaceInfo.empty();
    }

    final String drive = drivePath.endsWith('\\') ? drivePath : '$drivePath\\';
    final lpFreeBytesAvailable = calloc<Uint64>();
    final lpTotalNumberOfBytes = calloc<Uint64>();
    final lpTotalNumberOfFreeBytes = calloc<Uint64>();

    try {
      final result = win32.GetDiskFreeSpaceEx(
        drive.toNativeUtf16(),
        lpFreeBytesAvailable,
        lpTotalNumberOfBytes,
        lpTotalNumberOfFreeBytes,
      );

      if (result == 0) {
        return _DriveSpaceInfo.empty();
      }

      final int totalBytes = lpTotalNumberOfBytes.value;
      final int freeBytes = lpFreeBytesAvailable.value;
      final int usedBytes = totalBytes - freeBytes;
      final double usageRatio = totalBytes > 0 ? usedBytes / totalBytes : 0.0;

      return _DriveSpaceInfo(
        totalStr: _formatSize(totalBytes),
        freeStr: _formatSize(freeBytes),
        usedStr: _formatSize(usedBytes),
        usageRatio: usageRatio,
      );
    } catch (_) {
      return _DriveSpaceInfo.empty();
    } finally {
      calloc.free(lpFreeBytesAvailable);
      calloc.free(lpTotalNumberOfBytes);
      calloc.free(lpTotalNumberOfFreeBytes);
    }
  }

  String _formatSize(int bytes) {
    const suffixes = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    int index = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && index < suffixes.length - 1) {
      size /= 1024;
      index++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[index]}';
  }
}

class _DriveEntry {
  final String path;
  final String displayName;
  final _DriveSpaceInfo spaceInfo;

  const _DriveEntry({
    required this.path,
    required this.displayName,
    required this.spaceInfo,
  });
}

class _DriveMeta {
  final String displayName;
  final _DriveSpaceInfo spaceInfo;

  const _DriveMeta({
    required this.displayName,
    required this.spaceInfo,
  });
}

class _DriveSpaceInfo {
  final String totalStr;
  final String freeStr;
  final String usedStr;
  final double usageRatio;

  const _DriveSpaceInfo({
    required this.totalStr,
    required this.freeStr,
    required this.usedStr,
    required this.usageRatio,
  });

  bool get hasDetails => totalStr.isNotEmpty;

  factory _DriveSpaceInfo.empty() {
    return const _DriveSpaceInfo(
      totalStr: '',
      freeStr: '',
      usedStr: '',
      usageRatio: 0.0,
    );
  }
}
