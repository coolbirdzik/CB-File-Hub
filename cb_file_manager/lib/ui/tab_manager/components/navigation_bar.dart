import 'dart:io' show Platform;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/design_system_config.dart';
import '../../../design_system/fluent_surface_tokens.dart';
import '../core/tab_manager.dart';
import '../../../config/languages/app_localizations.dart';
import 'address_bar_menu.dart';
import '../../../helpers/files/archive_path_utils.dart';
import '../../../ui/components/common/breadcrumb_address_bar.dart';

/// Navigation bar component that includes back/forward buttons and path input field
class PathNavigationBar extends StatefulWidget {
  final String tabId;
  final TextEditingController pathController;
  final Function(String) onPathSubmitted;

  /// Path shown in the bar (e.g. empty when at drives view).
  final String currentPath;

  /// Logical tab path for Up navigation (e.g. `#drives`, `H:\\folder`, `#network/...`).
  final String tabPath;
  final bool isNetworkPath;
  final List<AddressBarMenuItem>? menuItems;
  final bool canNavigateToParent;
  final VoidCallback? onNavigateToParent;

  const PathNavigationBar({
    Key? key,
    required this.tabId,
    required this.pathController,
    required this.onPathSubmitted,
    required this.currentPath,
    required this.tabPath,
    this.isNetworkPath = false,
    this.menuItems,
    this.canNavigateToParent = false,
    this.onNavigateToParent,
  }) : super(key: key);

  @override
  State<PathNavigationBar> createState() => _PathNavigationBarState();
}

class _PathNavigationBarState extends State<PathNavigationBar> {
  // Lưu trữ tham chiếu đến TabManagerBloc
  TabManagerBloc? _tabBloc;
  bool _canNavigateBack = false;
  bool _canNavigateForward = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lấy TabManagerBloc mỗi khi dependencies thay đổi
    try {
      _tabBloc = context.read<TabManagerBloc>();
      _updateNavigationState();
    } catch (e) {
      _tabBloc = null;
    }
  }

  void _updateNavigationState() {
    if (_tabBloc != null) {
      setState(() {
        _canNavigateBack = _tabBloc!.canTabNavigateBack(widget.tabId);
        _canNavigateForward = _tabBloc!.canTabNavigateForward(widget.tabId);
      });
    }
  }

  // Converts the current filesystem path into breadcrumb segments.
  List<BreadcrumbSegment> _buildSegments() {
    if (ArchivePathUtils.isArchiveBrowsePath(widget.tabPath)) {
      final crumbs = ArchivePathUtils.breadcrumbs(widget.tabPath);
      if (crumbs.isEmpty) {
        return [BreadcrumbSegment(label: widget.tabPath)];
      }

      return [
        for (int i = 0; i < crumbs.length; i++)
          BreadcrumbSegment(
            label: crumbs[i].label,
            icon: i == 0 ? PhosphorIconsLight.archive : null,
            onTap: i == crumbs.length - 1
                ? null
                : () => widget.onPathSubmitted(crumbs[i].virtualPath),
          ),
      ];
    }

    final path = widget.currentPath;
    if (path.isEmpty) {
      return [
        const BreadcrumbSegment(
          label: 'This PC',
          icon: PhosphorIconsLight.desktopTower,
        ),
      ];
    }

    final parts = path.split(Platform.pathSeparator);
    final segments = <BreadcrumbSegment>[];

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      // Skip the empty leading token from Unix absolute paths ("/foo" → ["", "foo"])
      if (part.isEmpty && i == 0) continue;

      final isLast = i == parts.length - 1;
      final segmentPath = parts.sublist(0, i + 1).join(Platform.pathSeparator);

      segments.add(BreadcrumbSegment(
        label: part,
        // Show a drive/hard-disk icon only on the first (root) segment.
        icon: segments.isEmpty ? PhosphorIconsLight.hardDrive : null,
        onTap: isLast ? null : () => widget.onPathSubmitted(segmentPath),
      ));
    }

    return segments.isEmpty ? [BreadcrumbSegment(label: path)] : segments;
  }

  @override
  Widget build(BuildContext context) {
    // Gọi lại _updateNavigationState để đảm bảo trạng thái mới nhất
    if (_tabBloc != null) {
      _updateNavigationState();
    }

    final useFluentDesktopShell =
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
            DesignSystemConfig.enableFluentDesktopShell &&
            !DesignSystemConfig.enableLegacyMaterialDesktopShell;
    if (useFluentDesktopShell) {
      return _buildDesktopNavigationBar(context);
    }

    return Row(
      children: [
        IconButton(
          icon: const Icon(PhosphorIconsLight.arrowLeft),
          onPressed: _canNavigateBack
              ? () => BlocProvider.of<TabManagerBloc>(context)
                  .backNavigationToPath(widget.tabId)
              : null,
          tooltip: 'Go back',
        ),
        IconButton(
          icon: const Icon(PhosphorIconsLight.arrowRight),
          onPressed: _canNavigateForward
              ? () => BlocProvider.of<TabManagerBloc>(context)
                  .forwardNavigationToPath(widget.tabId)
              : null,
          tooltip: 'Go forward',
        ),
        if (widget.onNavigateToParent != null)
          IconButton(
            icon: const Icon(PhosphorIconsLight.arrowUp),
            onPressed:
                widget.canNavigateToParent ? widget.onNavigateToParent : null,
            tooltip: AppLocalizations.of(context)!.parentFolder,
          ),

        // Special display for network paths
        if (widget.isNetworkPath) ...[
          const Icon(PhosphorIconsLight.wifiHigh),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _formatNetworkPath(widget.currentPath),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Normal path: breadcrumb chips, click last chip to type
        ] else ...[
          Expanded(
            child: BreadcrumbAddressBar(
              segments: _buildSegments(),
              editController: widget.pathController,
              onPathSubmitted: widget.onPathSubmitted,
            ),
          ),
        ],
        if (widget.menuItems != null && widget.menuItems!.isNotEmpty)
          AddressBarMenu(
            items: widget.menuItems!,
            tooltip: 'Tùy chọn',
          ),
      ],
    );
  }

  Widget _buildDesktopNavigationBar(BuildContext context) {
    final surfaces = FluentSurfaceTokens.of(context);
    final buttonStyle = fluent.ButtonStyle(
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: FluentSurfaceTokens.controlRadius,
        ),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(7)),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return surfaces.controlPressed;
        }
        if (states.contains(WidgetState.hovered)) {
          return surfaces.controlHover;
        }
        return Colors.transparent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return surfaces.textDisabled;
        }
        return surfaces.icon;
      }),
    );

    Widget iconButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return fluent.Tooltip(
        message: tooltip,
        child: fluent.IconButton(
          // Let Fluent's IconTheme apply the state-resolved foreground color.
          // An explicit Icon color would override disabled contrast.
          icon: Icon(icon, size: 16),
          style: buttonStyle,
          iconButtonMode: fluent.IconButtonMode.small,
          onPressed: onPressed,
        ),
      );
    }

    final pathContent = widget.isNetworkPath
        ? Row(
            children: [
              Icon(
                PhosphorIconsLight.wifiHigh,
                size: 15,
                color: surfaces.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _formatNetworkPath(widget.currentPath),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: surfaces.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          )
        : BreadcrumbAddressBar(
            segments: _buildSegments(),
            editController: widget.pathController,
            onPathSubmitted: widget.onPathSubmitted,
          );

    return Row(
      children: [
        iconButton(
          icon: PhosphorIconsLight.arrowLeft,
          tooltip: 'Go back',
          onPressed: _canNavigateBack
              ? () => context.read<TabManagerBloc>().backNavigationToPath(
                    widget.tabId,
                  )
              : null,
        ),
        iconButton(
          icon: PhosphorIconsLight.arrowRight,
          tooltip: 'Go forward',
          onPressed: _canNavigateForward
              ? () => context.read<TabManagerBloc>().forwardNavigationToPath(
                    widget.tabId,
                  )
              : null,
        ),
        if (widget.onNavigateToParent != null)
          iconButton(
            icon: PhosphorIconsLight.arrowUp,
            tooltip: AppLocalizations.of(context)!.parentFolder,
            onPressed:
                widget.canNavigateToParent ? widget.onNavigateToParent : null,
          ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: FluentSurfaceTokens.controlHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: surfaces.control,
              borderRadius: FluentSurfaceTokens.controlRadius,
              border: Border.all(color: surfaces.stroke),
            ),
            child: pathContent,
          ),
        ),
        if (widget.menuItems != null && widget.menuItems!.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6),
            child: AddressBarMenu(
              items: widget.menuItems!,
              tooltip: 'Options',
            ),
          ),
      ],
    );
  }

  // Format a network path for display
  String _formatNetworkPath(String path) {
    if (!path.startsWith('#network/')) return path;

    try {
      final parts = path.split('/');
      if (parts.length < 3) return path;

      final protocol = parts[1].toUpperCase(); // SMB, FTP, etc.
      final server = Uri.decodeComponent(parts[2]);

      if (parts.length >= 4 && parts[3].startsWith('S')) {
        // We have a share
        final share = Uri.decodeComponent(parts[3].substring(1));

        if (parts.length > 4) {
          // We have a subfolder
          final remainingPath = parts.sublist(4).join('/');
          return '$protocol://$server/$share/$remainingPath';
        } else {
          return '$protocol://$server/$share';
        }
      } else {
        return '$protocol://$server';
      }
    } catch (_) {
      return path;
    }
  }
}
