import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/components/navigation_bar.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/widgets/selection_summary_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'breadcrumb_address_bar.dart';
import 'file_view_shell.dart';
import 'screen_scaffold.dart';

/// Image and video hubs share the browser's toolbar and tab history controls.
class LibraryHubScaffold extends StatefulWidget {
  final String tabId;
  final String path;
  final String title;
  final IconData icon;
  final Widget body;
  final VoidCallback onRefresh;
  final Widget? floatingActionButton;
  final List<Widget> actions;
  final List<BreadcrumbSegment>? breadcrumbSegments;
  final String? parentPath;
  final ViewMode viewMode;
  final VoidCallback? onEscape;
  final ValueChanged<int>? onViewScaleDelta;
  final bool enablePathEditing;
  final ValueChanged<String>? onPathSubmitted;
  final bool showSearchBar;
  final Widget? searchBar;
  final bool showRefreshAction;
  final SelectionState selectionState;
  final VoidCallback? onClearSelection;
  final VoidCallback? onSelectAll;
  final void Function({required bool permanent})? onDelete;

  const LibraryHubScaffold({
    super.key,
    required this.tabId,
    required this.path,
    required this.title,
    required this.icon,
    required this.body,
    required this.onRefresh,
    this.floatingActionButton,
    this.actions = const [],
    this.breadcrumbSegments,
    this.parentPath,
    this.viewMode = ViewMode.grid,
    this.onEscape,
    this.onViewScaleDelta,
    this.enablePathEditing = false,
    this.onPathSubmitted,
    this.showSearchBar = false,
    this.searchBar,
    this.showRefreshAction = true,
    this.selectionState = const SelectionState(),
    this.onClearSelection,
    this.onSelectAll,
    this.onDelete,
  });

  @override
  State<LibraryHubScaffold> createState() => _LibraryHubScaffoldState();
}

class _LibraryHubScaffoldState extends State<LibraryHubScaffold> {
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _addressController.text = widget.path;
  }

  @override
  void didUpdateWidget(covariant LibraryHubScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _addressController.text = widget.path;
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _submitPath(String value) {
    final path = value.trim();
    if (path.isEmpty) {
      _addressController.text = widget.path;
      return;
    }
    final handler = widget.onPathSubmitted;
    if (handler != null) {
      handler(path);
      return;
    }
    if (path != widget.path) {
      TabNavigator.updateTabPath(context, widget.tabId, path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = context.read<TabManagerBloc>();
    final l10n = AppLocalizations.of(context)!;
    return FileViewShell(
      viewMode: widget.viewMode,
      onEscape: widget.onEscape,
      onViewScaleDelta: widget.onViewScaleDelta,
      onMouseBack: () => tabs.backNavigationToPath(widget.tabId),
      onMouseForward: () => tabs.forwardNavigationToPath(widget.tabId),
      onRefresh: widget.onRefresh,
      onSelectAll: widget.onSelectAll,
      onDelete: widget.onDelete,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          ScreenScaffold(
            selectionState: widget.selectionState,
            isNetworkPath: false,
            isDesktop:
                Platform.isWindows || Platform.isLinux || Platform.isMacOS,
            onClearSelection: widget.onClearSelection ?? () {},
            showRemoveTagsDialog: (_) {},
            showManageAllTagsDialog: (_) {},
            showDeleteConfirmationDialog: (_) =>
                widget.onDelete?.call(permanent: false),
            showAppBar: true,
            showSearchBar: widget.showSearchBar,
            searchBar: widget.searchBar ?? const SizedBox.shrink(),
            pathNavigationBar: PathNavigationBar(
              tabId: widget.tabId,
              pathController: _addressController,
              currentPath: widget.path,
              tabPath: widget.path,
              enablePathEditing: widget.enablePathEditing,
              onPathSubmitted: _submitPath,
              canNavigateToParent: widget.parentPath != null,
              onNavigateToParent: widget.parentPath == null
                  ? null
                  : () => TabNavigator.updateTabPath(
                      context,
                      widget.tabId,
                      widget.parentPath!,
                    ),
              onNavigateHome: () {
                TabNavigator.updateTabPath(context, widget.tabId, '#home');
                tabs.add(UpdateTabName(widget.tabId, l10n.homeTab));
              },
              breadcrumbSegments:
                  widget.breadcrumbSegments ??
                  [BreadcrumbSegment(label: widget.title, icon: widget.icon)],
            ),
            actions: [
              for (final action in widget.actions)
                Material(type: MaterialType.transparency, child: action),
              if (widget.showRefreshAction)
                CbButton.icon(
                  icon: PhosphorIconsLight.arrowClockwise,
                  tooltip: l10n.refresh,
                  onPressed: widget.onRefresh,
                ),
            ],
            body: Material(type: MaterialType.transparency, child: widget.body),
            floatingActionButton: widget.floatingActionButton,
          ),
          if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
              SelectionSummaryTooltip.isVisibleFor(widget.selectionState))
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SelectionSummaryTooltip(
                selectedFileCount:
                    widget.selectionState.selectedFilePaths.length,
                selectedFolderCount:
                    widget.selectionState.selectedFolderPaths.length,
                selectedFilePaths: widget.selectionState.selectedFilePaths
                    .toList(),
                selectedFolderPaths: widget.selectionState.selectedFolderPaths
                    .toList(),
                showTotalSize: false,
              ),
            ),
        ],
      ),
    );
  }
}
