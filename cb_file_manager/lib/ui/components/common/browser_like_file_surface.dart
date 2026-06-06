import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_keyboard_shortcuts.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_keyboard_controller.dart';
import 'package:cb_file_manager/ui/widgets/selection_summary_tooltip.dart';
import 'package:flutter/material.dart';

import 'file_view_shell.dart';
import 'screen_scaffold.dart';

class BrowserLikeFileSurface extends StatefulWidget {
  final SelectionState selectionState;
  final ViewMode viewMode;
  final bool isDesktop;
  final Iterable<String> visiblePaths;
  final Widget Function(
    BuildContext context,
    TabbedFolderKeyboardController keyboardController,
  ) bodyBuilder;

  final VoidCallback onClearSelection;
  final void Function(BuildContext) showRemoveTagsDialog;
  final void Function(BuildContext) showManageAllTagsDialog;
  final void Function(BuildContext) showDeleteConfirmationDialog;

  final bool showAppBar;
  final bool showSearchBar;
  final Widget searchBar;
  final Widget pathNavigationBar;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final Widget? selectionModeFloatingActionButton;

  final void Function(int delta)? onGridZoomDelta;
  final void Function(int delta)? onViewScaleDelta;
  final VoidCallback? onMouseBack;
  final VoidCallback? onMouseForward;
  final VoidCallback? onEscape;
  final VoidCallback? onRefresh;
  final VoidCallback? onSelectAll;
  final FutureOr<void> Function(
    TabbedFolderKeyboardController keyboardController,
    bool permanent,
  )? onDelete;
  final FolderListState? keyboardFolderListState;
  final String? currentFilter;
  final int? gridCrossAxisCount;
  final VoidCallback? onBackInTabHistory;
  final void Function(String folderPath)? focusFolderPath;
  final void Function(String filePath)? focusFilePath;
  final void Function({
    required Set<String> folderPaths,
    required Set<String> filePaths,
    required String lastSelectedPath,
    required bool ctrlSelect,
  })? selectRange;
  final void Function(FileSystemEntity entity)? activateEntity;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onPaste;
  final VoidCallback? onRename;
  final void Function(int index, int crossAxisCount, double itemMainAxisExtent)?
      onScrollToIndex;
  final KeyEventResult Function(
    TabbedFolderKeyboardController keyboardController,
    KeyEvent event,
  )? onKeyEvent;

  const BrowserLikeFileSurface({
    Key? key,
    required this.selectionState,
    required this.viewMode,
    required this.isDesktop,
    required this.visiblePaths,
    required this.bodyBuilder,
    required this.onClearSelection,
    required this.showRemoveTagsDialog,
    required this.showManageAllTagsDialog,
    required this.showDeleteConfirmationDialog,
    required this.showAppBar,
    required this.showSearchBar,
    required this.searchBar,
    required this.pathNavigationBar,
    required this.actions,
    this.floatingActionButton,
    this.selectionModeFloatingActionButton,
    this.onGridZoomDelta,
    this.onViewScaleDelta,
    this.onMouseBack,
    this.onMouseForward,
    this.onEscape,
    this.onRefresh,
    this.onSelectAll,
    this.onDelete,
    this.keyboardFolderListState,
    this.currentFilter,
    this.gridCrossAxisCount,
    this.onBackInTabHistory,
    this.focusFolderPath,
    this.focusFilePath,
    this.selectRange,
    this.activateEntity,
    this.onCopy,
    this.onCut,
    this.onPaste,
    this.onRename,
    this.onScrollToIndex,
    this.onKeyEvent,
  }) : super(key: key);

  @override
  State<BrowserLikeFileSurface> createState() => _BrowserLikeFileSurfaceState();
}

class _BrowserLikeFileSurfaceState extends State<BrowserLikeFileSurface> {
  late final TabbedFolderKeyboardController _keyboardController;

  @override
  void initState() {
    super.initState();
    _keyboardController = TabbedFolderKeyboardController();
  }

  @override
  void dispose() {
    _keyboardController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (!widget.isDesktop ||
        BrowserLikeKeyboardShortcuts.isTextInputFocused()) {
      return KeyEventResult.ignored;
    }

    final escapeResult = BrowserLikeKeyboardShortcuts.handleBasic(
      isDesktop: widget.isDesktop,
      event: event,
      onEscape: widget.onEscape,
    );
    if (escapeResult != KeyEventResult.ignored) {
      return escapeResult;
    }

    final folderListState = widget.keyboardFolderListState;
    if (folderListState != null &&
        widget.onBackInTabHistory != null &&
        widget.focusFolderPath != null &&
        widget.focusFilePath != null &&
        widget.selectRange != null &&
        widget.activateEntity != null &&
        widget.onDelete != null) {
      final commonResult = BrowserLikeKeyboardShortcuts.handle(
        isDesktop: widget.isDesktop,
        keyboardController: _keyboardController,
        folderListState: folderListState,
        selectionState: widget.selectionState,
        currentFilter: widget.currentFilter,
        gridCrossAxisCount: widget.gridCrossAxisCount,
        onBackInTabHistory: widget.onBackInTabHistory!,
        focusFolderPath: widget.focusFolderPath!,
        focusFilePath: widget.focusFilePath!,
        selectRange: widget.selectRange!,
        activateEntity: widget.activateEntity!,
        onDelete: (permanent) {
          unawaited(
            Future<void>.sync(
              () => widget.onDelete!(_keyboardController, permanent),
            ),
          );
        },
        onSelectAll: widget.onSelectAll,
        onCopy: widget.onCopy,
        onCut: widget.onCut,
        onPaste: widget.onPaste,
        onRename: widget.onRename,
        onRefresh: widget.onRefresh,
        onScrollToIndex: widget.onScrollToIndex,
        event: event,
      );
      if (commonResult != KeyEventResult.ignored) {
        return commonResult;
      }
    }

    final basicResult = BrowserLikeKeyboardShortcuts.handleBasic(
      isDesktop: widget.isDesktop,
      event: event,
      onRefresh: widget.onRefresh,
      onSelectAll: widget.onSelectAll,
      onDelete: widget.onDelete == null
          ? null
          : (permanent) {
              unawaited(
                Future<void>.sync(
                  () => widget.onDelete!(_keyboardController, permanent),
                ),
              );
            },
      onCopy: widget.onCopy,
      onCut: widget.onCut,
      onPaste: widget.onPaste,
      onRename: widget.onRename,
    );
    if (basicResult != KeyEventResult.ignored) {
      return basicResult;
    }

    final customResult = widget.onKeyEvent?.call(_keyboardController, event);
    if (customResult != null && customResult != KeyEventResult.ignored) {
      return customResult;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    _keyboardController.syncFromSelection(widget.selectionState);
    _keyboardController.pruneItemKeys(widget.visiblePaths);

    final scaffold = ScreenScaffold(
      selectionState: widget.selectionState,
      body: FileViewShell(
        viewMode: widget.viewMode,
        onGridZoomDelta: widget.onGridZoomDelta,
        onViewScaleDelta: widget.onViewScaleDelta,
        onMouseBack: widget.onMouseBack,
        onMouseForward: widget.onMouseForward,
        onRefresh: widget.onRefresh,
        onEscape: widget.onEscape,
        enableKeyboardShortcuts: false,
        child: widget.bodyBuilder(context, _keyboardController),
      ),
      isNetworkPath: false,
      onClearSelection: widget.onClearSelection,
      showRemoveTagsDialog: widget.showRemoveTagsDialog,
      showManageAllTagsDialog: widget.showManageAllTagsDialog,
      showDeleteConfirmationDialog: widget.showDeleteConfirmationDialog,
      isDesktop: widget.isDesktop,
      selectionModeFloatingActionButton:
          widget.selectionModeFloatingActionButton,
      showAppBar: widget.showAppBar,
      showSearchBar: widget.showSearchBar,
      searchBar: widget.searchBar,
      pathNavigationBar: widget.pathNavigationBar,
      actions: widget.actions,
      floatingActionButton: widget.floatingActionButton,
    );

    return Focus(
      focusNode: _keyboardController.focusNode,
      autofocus: true,
      onKeyEvent: (_, event) => _handleKeyEvent(event),
      child: Listener(
        onPointerDown: (_) {
          if (widget.isDesktop &&
              !BrowserLikeKeyboardShortcuts.isTextInputFocused()) {
            _keyboardController.focusNode.requestFocus();
          }
        },
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            scaffold,
            if (widget.selectionState.isSelectionMode && widget.isDesktop)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SelectionSummaryTooltip(
                  selectedFileCount:
                      widget.selectionState.selectedFilePaths.length,
                  selectedFolderCount:
                      widget.selectionState.selectedFolderPaths.length,
                  selectedFilePaths:
                      widget.selectionState.selectedFilePaths.toList(),
                  selectedFolderPaths:
                      widget.selectionState.selectedFolderPaths.toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
