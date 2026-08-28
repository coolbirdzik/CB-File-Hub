// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' as p;

import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/index.dart'
    as folder_list_components;
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/widgets/ctrl_scroll_zoom.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/utils/fluent_background.dart';
import 'package:cb_file_manager/ui/utils/scroll_velocity_notifier.dart';
import 'package:cb_file_manager/ui/widgets/file_preview_pane.dart';
import 'package:cb_file_manager/ui/tab_manager/mobile/mobile_file_actions_controller.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/widgets/miller_columns_view.dart';
import 'package:cb_file_manager/ui/widgets/file_tree_view.dart';
import 'package:cb_file_manager/ui/utils/view_mode_utils.dart';

/// Static factory class for building file list views in different modes
class FileListViewBuilder {
  static const double _gridSpacing = 8.0;
  static const double _gridAspectRatio = 0.8;
  static const double _gridReferenceWidth = 960.0;
  static const double _tilesSpacing = 8.0;
  static const double _tilesMaxCrossAxisExtent = 280.0;
  static const double _tilesMainAxisExtent = 76.0;

  static double _gridItemWidthForZoom(int zoomLevel) {
    final clamped = zoomLevel.clamp(
      UserPreferences.minGridZoomLevel,
      UserPreferences.maxGridZoomLevel,
    );
    final totalSpacing = _gridSpacing * (clamped - 1);
    return math.max(56.0, (_gridReferenceWidth - totalSpacing) / clamped);
  }

  static int _gridCrossAxisCount(double availableWidth, double itemWidth) {
    final raw =
        ((availableWidth + _gridSpacing) / (itemWidth + _gridSpacing)).floor();
    return math.max(1, raw);
  }

  static double _masonryHeightFactor(String path) {
    var hash = 0;
    for (final codeUnit in path.codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    const factors = [0.68, 0.86, 1.08, 1.32, 1.58];
    return factors[hash.abs() % factors.length];
  }

  static List<String> _dragPayloadFor(
    String path,
    SelectionState selectionState,
  ) {
    if (selectionState.isPathSelected(path) &&
        selectionState.allSelectedPaths.isNotEmpty) {
      return selectionState.allSelectedPaths.toSet().toList(growable: false);
    }
    return <String>[path];
  }

  static Widget _wrapFileDragDrop({
    required Widget child,
    required bool isDesktopPlatform,
    required bool isFolder,
    required String path,
    required SelectionState selectionState,
    ValueChanged<List<String>>? onStartFileDrag,
    Future<void> Function(List<String> sources, String destinationFolder)?
        onMoveItemsToFolder,
  }) {
    if (!isDesktopPlatform) return child;

    final payload = _dragPayloadFor(path, selectionState);
    Widget wrapped = Draggable<List<String>>(
      data: payload,
      maxSimultaneousDrags: 1,
      feedback: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              payload.length == 1
                  ? p.basename(payload.first)
                  : '${payload.length} items',
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.55, child: child),
      onDragStarted: () => onStartFileDrag?.call(payload),
      child: child,
    );

    if (!isFolder || onMoveItemsToFolder == null) return wrapped;

    return DragTarget<List<String>>(
      onWillAcceptWithDetails: (details) =>
          details.data.isNotEmpty && !details.data.contains(path),
      onAcceptWithDetails: (details) => onMoveItemsToFolder(details.data, path),
      builder: (context, candidateData, rejectedData) {
        if (candidateData.isEmpty) return wrapped;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: wrapped,
        );
      },
    );
  }

  /// Build the appropriate view based on the current view mode
  /// If [searchResults] is provided, it will be used instead of state.files and state.folders
  static Widget build({
    required FolderListState state,
    required SelectionState selectionState,
    required bool isDesktopPlatform,
    required Function(String) onNavigateToPath,
    required Function(File, bool) onFileTap,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
        toggleFileSelection,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
        toggleFolderSelection,
    required VoidCallback clearSelection,
    required TabbedFolderDragSelectionController dragSelectionController,
    required bool showFileTags,
    required Function(BuildContext, String, List<String>) showDeleteTagDialog,
    required Function(BuildContext, String) showAddTagToFileDialog,
    Future<void> Function(BuildContext, File)? onDeleteFile,
    Future<void> Function(BuildContext, List<String>)? onDeleteFiles,
    required VoidCallback toggleSelectionMode,
    required ColumnVisibility columnVisibility,
    required Function(BuildContext, Offset) showContextMenu,
    required bool isPreviewPaneVisible,
    required ValueListenable<double> previewPaneWidthListenable,
    required ValueChanged<int> onZoomLevelChanged,
    required ValueChanged<double> onPreviewPaneWidthChanged,
    required ValueChanged<double> onPreviewPaneWidthCommitted,
    required VoidCallback onPreviewPaneToggled,
    ScrollController? scrollController,
    GlobalKey Function(String path)? itemKeyForPath,
    ValueListenable<bool?> Function(String path)? immediateSelectionForPath,
    String? tabId,
    bool isMasonryLayout = false,
    ValueChanged<int?>? onGridCrossAxisCountChanged,
    ValueChanged<double?>? onGridItemMainAxisExtentChanged,
    ValueChanged<List<String>>? onStartFileDrag,
    Future<void> Function(List<String> sources, String destinationFolder)?
        onMoveItemsToFolder,
    List<FileSystemEntity>? searchResults,
  }) {
    // Apply frame timing optimizations before heavy list/grid operations
    FrameTimingOptimizer().optimizeBeforeHeavyOperation();

    // When searchResults is provided, create a modified state with search results as files/folders
    // This allows using the same build functions for both normal view and search results
    final FolderListState displayState;
    if (searchResults != null) {
      final searchFolders = searchResults.whereType<Directory>().toList();
      final searchFiles = searchResults.whereType<File>().toList();
      displayState = state.copyWith(
        folders: searchFolders,
        files: searchFiles,
      );
    } else {
      displayState = state;
    }

    final effectiveMasonryLayout = isMasonryLayout ||
        (tabId != null &&
            MobileFileActionsController.forTab(tabId).isMasonryLayout);

    final resolvedViewMode = ViewModeUtils.normalize(displayState.viewMode);

    final Widget contentView;
    if (resolvedViewMode == ViewMode.tiles) {
      contentView = _buildTilesView(
        state: displayState,
        selectionState: selectionState,
        isDesktopPlatform: isDesktopPlatform,
        onNavigateToPath: onNavigateToPath,
        onFileTap: onFileTap,
        toggleFileSelection: toggleFileSelection,
        toggleFolderSelection: toggleFolderSelection,
        clearSelection: clearSelection,
        dragSelectionController: dragSelectionController,
        showFileTags: showFileTags,
        showContextMenu: showContextMenu,
        showDeleteTagDialog: showDeleteTagDialog,
        showAddTagToFileDialog: showAddTagToFileDialog,
        onDeleteFile: onDeleteFile,
        onDeleteFiles: onDeleteFiles,
        onStartFileDrag: onStartFileDrag,
        onMoveItemsToFolder: onMoveItemsToFolder,
        scrollController: scrollController,
        onGridCrossAxisCountChanged: onGridCrossAxisCountChanged,
        onGridItemMainAxisExtentChanged: onGridItemMainAxisExtentChanged,
      );
    } else if (resolvedViewMode == ViewMode.grid) {
      contentView = _buildGridView(
        state: displayState,
        selectionState: selectionState,
        isDesktopPlatform: isDesktopPlatform,
        onNavigateToPath: onNavigateToPath,
        onFileTap: onFileTap,
        toggleFileSelection: toggleFileSelection,
        toggleFolderSelection: toggleFolderSelection,
        clearSelection: clearSelection,
        dragSelectionController: dragSelectionController,
        showFileTags: showFileTags,
        showContextMenu: showContextMenu,
        toggleSelectionMode: toggleSelectionMode,
        onZoomLevelChanged: onZoomLevelChanged,
        showDeleteTagDialog: showDeleteTagDialog,
        showAddTagToFileDialog: showAddTagToFileDialog,
        onDeleteFile: onDeleteFile,
        onDeleteFiles: onDeleteFiles,
        isMasonryLayout: effectiveMasonryLayout,
        onGridCrossAxisCountChanged: onGridCrossAxisCountChanged,
        onGridItemMainAxisExtentChanged: onGridItemMainAxisExtentChanged,
        onStartFileDrag: onStartFileDrag,
        onMoveItemsToFolder: onMoveItemsToFolder,
        scrollController: scrollController,
        itemKeyForPath: itemKeyForPath,
        immediateSelectionForPath: immediateSelectionForPath,
      );
    } else if (resolvedViewMode == ViewMode.columns && isDesktopPlatform) {
      contentView = MillerColumnsView(
        state: displayState,
        selectionState: selectionState,
        isDesktopPlatform: isDesktopPlatform,
        onNavigateToPath: onNavigateToPath,
        onFileTap: onFileTap,
        toggleFileSelection: toggleFileSelection,
        toggleFolderSelection: toggleFolderSelection,
        clearSelection: clearSelection,
        dragSelectionController: dragSelectionController,
        showFileTags: showFileTags,
        showDeleteTagDialog: showDeleteTagDialog,
        showAddTagToFileDialog: showAddTagToFileDialog,
        onDeleteFile: onDeleteFile,
        onDeleteFiles: onDeleteFiles,
        toggleSelectionMode: toggleSelectionMode,
        showContextMenu: showContextMenu,
        scrollController: scrollController,
        itemKeyForPath: itemKeyForPath,
      );
    } else if (resolvedViewMode == ViewMode.details) {
      contentView = _buildDetailsView(
        state: displayState,
        selectionState: selectionState,
        isDesktopPlatform: isDesktopPlatform,
        onNavigateToPath: onNavigateToPath,
        onFileTap: onFileTap,
        toggleFileSelection: toggleFileSelection,
        clearSelection: clearSelection,
        dragSelectionController: dragSelectionController,
        showDeleteTagDialog: showDeleteTagDialog,
        showAddTagToFileDialog: showAddTagToFileDialog,
        onDeleteFile: onDeleteFile,
        onDeleteFiles: onDeleteFiles,
        toggleSelectionMode: toggleSelectionMode,
        columnVisibility: columnVisibility,
        showFileTags: showFileTags,
        showContextMenu: showContextMenu,
        scrollController: scrollController,
        itemKeyForPath: itemKeyForPath,
        onStartFileDrag: onStartFileDrag,
        onMoveItemsToFolder: onMoveItemsToFolder,
      );
    } else if (resolvedViewMode == ViewMode.tree) {
      contentView = FileTreeView(
        state: displayState,
        selectionState: selectionState,
        isDesktopPlatform: isDesktopPlatform,
        onNavigateToPath: onNavigateToPath,
        onFileTap: onFileTap,
        toggleFileSelection: toggleFileSelection,
        toggleFolderSelection: toggleFolderSelection,
        clearSelection: clearSelection,
        showContextMenu: showContextMenu,
      );
    } else {
      contentView = _buildListView(
        state: displayState,
        selectionState: selectionState,
        isDesktopPlatform: isDesktopPlatform,
        onNavigateToPath: onNavigateToPath,
        onFileTap: onFileTap,
        toggleFileSelection: toggleFileSelection,
        toggleFolderSelection: toggleFolderSelection,
        clearSelection: clearSelection,
        dragSelectionController: dragSelectionController,
        showContextMenu: showContextMenu,
        showFileTags: showFileTags,
        showDeleteTagDialog: showDeleteTagDialog,
        showAddTagToFileDialog: showAddTagToFileDialog,
        onDeleteFile: onDeleteFile,
        onDeleteFiles: onDeleteFiles,
        onStartFileDrag: onStartFileDrag,
        onMoveItemsToFolder: onMoveItemsToFolder,
        scrollController: scrollController,
        itemKeyForPath: itemKeyForPath,
      );
    }

    if (isPreviewPaneVisible && isDesktopPlatform) {
      return _wrapWithPreviewPane(
        contentView: contentView,
        state: displayState,
        selectionState: selectionState,
        onFileTap: onFileTap,
        onPreviewPaneToggled: onPreviewPaneToggled,
        previewPaneWidthListenable: previewPaneWidthListenable,
        onPreviewPaneWidthChanged: onPreviewPaneWidthChanged,
        onPreviewPaneWidthCommitted: onPreviewPaneWidthCommitted,
      );
    }

    return contentView;
  }

  /// Build grid view for files and folders
  static Widget _buildGridView({
    required FolderListState state,
    required SelectionState selectionState,
    required bool isDesktopPlatform,
    required Function(String) onNavigateToPath,
    required Function(File, bool) onFileTap,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
        toggleFileSelection,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
        toggleFolderSelection,
    required VoidCallback clearSelection,
    required TabbedFolderDragSelectionController dragSelectionController,
    required bool showFileTags,
    required Function(BuildContext, Offset) showContextMenu,
    required VoidCallback toggleSelectionMode,
    required ValueChanged<int> onZoomLevelChanged,
    required Function(BuildContext, String, List<String>) showDeleteTagDialog,
    required Function(BuildContext, String) showAddTagToFileDialog,
    Future<void> Function(BuildContext, File)? onDeleteFile,
    Future<void> Function(BuildContext, List<String>)? onDeleteFiles,
    required bool isMasonryLayout,
    ValueChanged<int?>? onGridCrossAxisCountChanged,
    ValueChanged<double?>? onGridItemMainAxisExtentChanged,
    ValueChanged<List<String>>? onStartFileDrag,
    Future<void> Function(List<String> sources, String destinationFolder)?
        onMoveItemsToFolder,
    ScrollController? scrollController,
    GlobalKey Function(String path)? itemKeyForPath,
    ValueListenable<bool?> Function(String path)? immediateSelectionForPath,
  }) {
    final itemSelectionMode =
        selectionState.isSelectionMode && !isDesktopPlatform;
    return Stack(
      key: dragSelectionController.stackKey,
      clipBehavior: Clip.none,
      children: [
        FluentBackground(
          blurAmount: 8.0,
          opacity: 0.0,
          backgroundColor: Colors.transparent,
          enableBlur: false,
          child: BlocBuilder<SelectionBloc, SelectionState>(
            builder: (context, selectionState) {
              return GestureDetector(
                onTap: () {
                  if (selectionState.isSelectionMode) {
                    clearSelection();
                  }
                },
                onSecondaryTapUp: (details) {
                  showContextMenu(context, details.globalPosition);
                },
                onLongPressStart: !isDesktopPlatform
                    ? (details) {
                        HapticFeedback.mediumImpact();
                        showContextMenu(context, details.globalPosition);
                      }
                    : null,
                onPanStart: isDesktopPlatform
                    ? (details) {
                        // Don't start drag selection if user is editing text (inline rename)
                        final focused = FocusManager.instance.primaryFocus;
                        final focusedContext = focused?.context;
                        if (focusedContext != null) {
                          final isEditableText =
                              focusedContext.widget is EditableText ||
                                  focusedContext.findAncestorWidgetOfExactType<
                                          EditableText>() !=
                                      null;
                          if (isEditableText) {
                            return; // Don't start drag selection
                          }
                        }
                        dragSelectionController.start(details.localPosition);
                      }
                    : null,
                onPanUpdate: isDesktopPlatform
                    ? (details) {
                        dragSelectionController.update(details.localPosition);
                      }
                    : null,
                onPanEnd: isDesktopPlatform
                    ? (details) {
                        dragSelectionController.end();
                      }
                    : null,
                behavior: HitTestBehavior.translucent,
                // Ctrl+scroll is handled by an outer CtrlScrollZoom wrapper
                // (the unified view-spectrum handler). Disabled here to avoid
                // two Listeners competing for the same pointer-signal event.
                child: CtrlScrollZoom(
                  onDelta: null,
                  child: RepaintBoundary(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxZoom = GridZoomConstraints.maxGridSize(
                          availableWidth: constraints.maxWidth,
                          mode: GridSizeMode.referenceWidth,
                          spacing: _gridSpacing,
                          referenceWidth: _gridReferenceWidth,
                          minValue: UserPreferences.minGridZoomLevel,
                          maxValue: UserPreferences.maxGridZoomLevel,
                        );
                        final effectiveZoom = state.gridZoomLevel
                            .clamp(UserPreferences.minGridZoomLevel, maxZoom)
                            .toInt();
                        final itemWidth = _gridItemWidthForZoom(effectiveZoom);
                        final availableWidth = math.max(
                          0.0,
                          constraints.maxWidth - (_gridSpacing * 2),
                        );
                        final crossAxisCount = _gridCrossAxisCount(
                          availableWidth,
                          itemWidth,
                        );
                        onGridCrossAxisCountChanged?.call(crossAxisCount);
                        final itemHeight = itemWidth / _gridAspectRatio;
                        onGridItemMainAxisExtentChanged
                            ?.call(itemHeight + _gridSpacing);
                        final folderIndexByPath = <String, int>{
                          for (var i = 0; i < state.folders.length; i++)
                            state.folders[i].path: i,
                        };
                        final fileIndexByPath = <String, int>{
                          for (var i = 0; i < state.files.length; i++)
                            state.files[i].path: i,
                        };

                        final shouldUseMasonry = isMasonryLayout;

                        Widget buildGridItem(BuildContext context, int index) {
                          final String itemPath = index < state.folders.length
                              ? state.folders[index].path
                              : state.files[index - state.folders.length].path;
                          final String itemKey = index < state.folders.length
                              ? 'folder-grid-$itemPath'
                              : 'file-grid-$itemPath';

                          final bool isSelected =
                              selectionState.isPathSelected(itemPath);

                          return Container(
                            key: itemKeyForPath?.call(itemPath),
                            child: KeyedSubtree(
                              key: ValueKey(itemKey),
                              child: LayoutBuilder(
                                builder: (BuildContext context,
                                    BoxConstraints constraints) {
                                  if (isDesktopPlatform) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      try {
                                        final RenderBox? renderBox = context
                                            .findRenderObject() as RenderBox?;
                                        if (renderBox != null &&
                                            renderBox.hasSize &&
                                            renderBox.attached) {
                                          final position = renderBox
                                              .localToGlobal(Offset.zero);
                                          dragSelectionController
                                              .registerItemPosition(
                                                  itemPath,
                                                  Rect.fromLTWH(
                                                      position.dx,
                                                      position.dy,
                                                      renderBox.size.width,
                                                      renderBox.size.height));
                                        }
                                      } catch (e) {
                                        debugPrint(
                                            'Layout error in grid view: $e');
                                      }
                                    });
                                  }

                                  if (index < state.folders.length) {
                                    final folder =
                                        state.folders[index] as Directory;
                                    return _wrapFileDragDrop(
                                      isDesktopPlatform: isDesktopPlatform,
                                      isFolder: true,
                                      path: folder.path,
                                      selectionState: selectionState,
                                      onStartFileDrag: onStartFileDrag,
                                      onMoveItemsToFolder: onMoveItemsToFolder,
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: SizedBox(
                                          width: itemWidth,
                                          height: itemHeight,
                                          child: RepaintBoundary(
                                            child: folder_list_components
                                                .FolderGridItem(
                                              key: ValueKey(
                                                  'folder-grid-item-${folder.path}'),
                                              folder: folder,
                                              onNavigate: onNavigateToPath,
                                              isSelected: isSelected,
                                              toggleFolderSelection:
                                                  toggleFolderSelection,
                                              isDesktopMode: isDesktopPlatform,
                                              lastSelectedPath: selectionState
                                                  .lastSelectedPath,
                                              clearSelectionMode:
                                                  clearSelection,
                                              immediateSelectionListenable:
                                                  immediateSelectionForPath
                                                      ?.call(folder.path),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  } else {
                                    final file = state
                                            .files[index - state.folders.length]
                                        as File;
                                    final masonryHeight = shouldUseMasonry
                                        ? itemHeight *
                                            _masonryHeightFactor(file.path)
                                        : itemHeight;
                                    return _wrapFileDragDrop(
                                      isDesktopPlatform: isDesktopPlatform,
                                      isFolder: false,
                                      path: file.path,
                                      selectionState: selectionState,
                                      onStartFileDrag: onStartFileDrag,
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: SizedBox(
                                          width: itemWidth,
                                          height: masonryHeight,
                                          child: RepaintBoundary(
                                            child: folder_list_components
                                                .FileGridItem(
                                              key: ValueKey(
                                                  'file-grid-item-${file.path}'),
                                              file: file,
                                              state: state,
                                              isSelectionMode:
                                                  itemSelectionMode,
                                              isSelected: isSelected,
                                              toggleFileSelection:
                                                  toggleFileSelection,
                                              toggleSelectionMode:
                                                  toggleSelectionMode,
                                              onFileTap: onFileTap,
                                              isDesktopMode: isDesktopPlatform,
                                              lastSelectedPath: selectionState
                                                  .lastSelectedPath,
                                              showDeleteTagDialog:
                                                  showDeleteTagDialog,
                                              showAddTagToFileDialog:
                                                  showAddTagToFileDialog,
                                              onDeleteFile: onDeleteFile,
                                              onDeleteFiles: onDeleteFiles,
                                              showFileTags: showFileTags,
                                              immediateSelectionListenable:
                                                  immediateSelectionForPath
                                                      ?.call(file.path),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                        }

                        if (shouldUseMasonry) {
                          return ScrollVelocityListener(
                            child: MasonryGridView.count(
                              controller: scrollController,
                              padding: const EdgeInsets.all(8.0),
                              physics: const ClampingScrollPhysics(),
                              cacheExtent: 400,
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: _gridSpacing,
                              mainAxisSpacing: _gridSpacing,
                              itemCount:
                                  state.folders.length + state.files.length,
                              itemBuilder: buildGridItem,
                            ),
                          );
                        }

                        return ScrollVelocityListener(
                          child: GridView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.all(8.0),
                            physics: const ClampingScrollPhysics(),
                            // cacheExtent: keep more items alive near viewport to avoid thumbnail re-render
                            // Desktop: 400px, Mobile: 200px - balances smooth scrolling vs thumbnail generation
                            cacheExtent: isDesktopPlatform ? 600 : 400,
                            addAutomaticKeepAlives: true,
                            addRepaintBoundaries: true,
                            addSemanticIndexes: false,
                            findChildIndexCallback: (Key key) {
                              if (key is! ValueKey<String>) return null;
                              final value = key.value;
                              if (value.startsWith('folder-grid-')) {
                                final folderPath =
                                    value.substring('folder-grid-'.length);
                                final index = folderIndexByPath[folderPath];
                                return index;
                              }
                              if (value.startsWith('file-grid-')) {
                                final filePath =
                                    value.substring('file-grid-'.length);
                                final index = fileIndexByPath[filePath];
                                if (index == null) return null;
                                return state.folders.length + index;
                              }
                              return null;
                            },
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: _gridSpacing,
                              mainAxisSpacing: _gridSpacing,
                              mainAxisExtent: itemHeight,
                            ),
                            itemCount:
                                state.folders.length + state.files.length,
                            itemBuilder: buildGridItem,
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
        dragSelectionController.buildOverlay(),
      ],
    );
  }

  /// Build details view for files and folders
  static Widget _buildDetailsView({
    required FolderListState state,
    required SelectionState selectionState,
    required bool isDesktopPlatform,
    required Function(String) onNavigateToPath,
    required Function(File, bool) onFileTap,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
        toggleFileSelection,
    required VoidCallback clearSelection,
    required TabbedFolderDragSelectionController dragSelectionController,
    required Function(BuildContext, String, List<String>) showDeleteTagDialog,
    required Function(BuildContext, String) showAddTagToFileDialog,
    Future<void> Function(BuildContext, File)? onDeleteFile,
    Future<void> Function(BuildContext, List<String>)? onDeleteFiles,
    required VoidCallback toggleSelectionMode,
    required ColumnVisibility columnVisibility,
    required bool showFileTags,
    required Function(BuildContext, Offset) showContextMenu,
    ValueChanged<List<String>>? onStartFileDrag,
    Future<void> Function(List<String> sources, String destinationFolder)?
        onMoveItemsToFolder,
    ScrollController? scrollController,
    GlobalKey Function(String path)? itemKeyForPath,
  }) {
    final itemSelectionMode =
        selectionState.isSelectionMode && !isDesktopPlatform;
    return Stack(
      key: dragSelectionController.stackKey,
      clipBehavior: Clip.none,
      children: [
        FluentBackground(
          blurAmount: 8.0,
          opacity: 0.0,
          backgroundColor: Colors.transparent,
          enableBlur: false,
          child: BlocBuilder<SelectionBloc, SelectionState>(
            builder: (context, selectionState) {
              return GestureDetector(
                onTap: () {
                  if (selectionState.isSelectionMode) {
                    clearSelection();
                  }
                },
                onSecondaryTapUp: (details) {
                  showContextMenu(context, details.globalPosition);
                },
                onLongPressStart: !isDesktopPlatform
                    ? (details) {
                        HapticFeedback.mediumImpact();
                        showContextMenu(context, details.globalPosition);
                      }
                    : null,
                onPanStart: isDesktopPlatform
                    ? (details) {
                        // Don't start drag selection if user is editing text (inline rename)
                        final focused = FocusManager.instance.primaryFocus;
                        final focusedContext = focused?.context;
                        if (focusedContext != null) {
                          final isEditableText =
                              focusedContext.widget is EditableText ||
                                  focusedContext.findAncestorWidgetOfExactType<
                                          EditableText>() !=
                                      null;
                          if (isEditableText) {
                            return; // Don't start drag selection
                          }
                        }
                        dragSelectionController.start(details.localPosition);
                      }
                    : null,
                onPanUpdate: isDesktopPlatform
                    ? (details) {
                        dragSelectionController.update(details.localPosition);
                      }
                    : null,
                onPanEnd: isDesktopPlatform
                    ? (details) {
                        dragSelectionController.end();
                      }
                    : null,
                behavior: HitTestBehavior.translucent,
                child: RepaintBoundary(
                  child: folder_list_components.FileView(
                    files: state.files.whereType<File>().toList(),
                    folders: state.folders.whereType<Directory>().toList(),
                    state: state,
                    isSelectionMode: itemSelectionMode,
                    isGridView: false,
                    selectedFiles: selectionState.allSelectedPaths,
                    toggleFileSelection: toggleFileSelection,
                    toggleSelectionMode: toggleSelectionMode,
                    showDeleteTagDialog: showDeleteTagDialog,
                    showAddTagToFileDialog: showAddTagToFileDialog,
                    onDeleteFile: onDeleteFile,
                    onDeleteFiles: onDeleteFiles,
                    onFolderTap: onNavigateToPath,
                    onFileTap: onFileTap,
                    isDesktopMode: isDesktopPlatform,
                    lastSelectedPath: selectionState.lastSelectedPath,
                    columnVisibility: columnVisibility,
                    showFileTags: showFileTags,
                    scrollController: scrollController,
                    itemKeyForPath: itemKeyForPath,
                    dragSelectionController: dragSelectionController,
                    onStartFileDrag: onStartFileDrag,
                    onMoveItemsToFolder: onMoveItemsToFolder,
                  ),
                ),
              );
            },
          ),
        ),
        dragSelectionController.buildOverlay(),
      ],
    );
  }

  /// Build list view for files and folders
  static Widget _buildListView({
    required FolderListState state,
    required SelectionState selectionState,
    required bool isDesktopPlatform,
    required Function(String) onNavigateToPath,
    required Function(File, bool) onFileTap,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
        toggleFileSelection,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
        toggleFolderSelection,
    required VoidCallback clearSelection,
    required TabbedFolderDragSelectionController dragSelectionController,
    required Function(BuildContext, Offset) showContextMenu,
    required bool showFileTags,
    required Function(BuildContext, String, List<String>) showDeleteTagDialog,
    required Function(BuildContext, String) showAddTagToFileDialog,
    Future<void> Function(BuildContext, File)? onDeleteFile,
    Future<void> Function(BuildContext, List<String>)? onDeleteFiles,
    ValueChanged<List<String>>? onStartFileDrag,
    Future<void> Function(List<String> sources, String destinationFolder)?
        onMoveItemsToFolder,
    ScrollController? scrollController,
    GlobalKey Function(String path)? itemKeyForPath,
  }) {
    final itemSelectionMode =
        selectionState.isSelectionMode && !isDesktopPlatform;
    return Stack(
      key: dragSelectionController.stackKey,
      clipBehavior: Clip.none,
      children: [
        FluentBackground(
          blurAmount: 8.0,
          opacity: 0.0,
          backgroundColor: Colors.transparent,
          enableBlur: false,
          child: BlocBuilder<SelectionBloc, SelectionState>(
            builder: (context, selectionState) {
              return GestureDetector(
                onTap: () {
                  if (selectionState.isSelectionMode) {
                    clearSelection();
                  }
                },
                onSecondaryTapUp: (details) {
                  showContextMenu(context, details.globalPosition);
                },
                onLongPressStart: !isDesktopPlatform
                    ? (details) {
                        HapticFeedback.mediumImpact();
                        showContextMenu(context, details.globalPosition);
                      }
                    : null,
                onPanStart: isDesktopPlatform
                    ? (details) {
                        // Don't start drag selection if user is editing text (inline rename)
                        final focused = FocusManager.instance.primaryFocus;
                        final focusedContext = focused?.context;
                        if (focusedContext != null) {
                          final isEditableText =
                              focusedContext.widget is EditableText ||
                                  focusedContext.findAncestorWidgetOfExactType<
                                          EditableText>() !=
                                      null;
                          if (isEditableText) {
                            return; // Don't start drag selection
                          }
                        }
                        dragSelectionController.start(details.localPosition);
                      }
                    : null,
                onPanUpdate: isDesktopPlatform
                    ? (details) {
                        dragSelectionController.update(details.localPosition);
                      }
                    : null,
                onPanEnd: isDesktopPlatform
                    ? (details) {
                        dragSelectionController.end();
                      }
                    : null,
                behavior: HitTestBehavior.translucent,
                child: RepaintBoundary(
                  child: ListView.builder(
                    controller: scrollController,
                    physics: const ClampingScrollPhysics(),
                    cacheExtent: 800,
                    addAutomaticKeepAlives: true,
                    addRepaintBoundaries: true,
                    addSemanticIndexes: false,
                    // Extra bottom padding so users can drag-select in empty space below items
                    padding: const EdgeInsets.only(bottom: 200.0),
                    itemCount: state.folders.length + state.files.length,
                    itemBuilder: (context, index) {
                      final String itemPath = index < state.folders.length
                          ? state.folders[index].path
                          : state.files[index - state.folders.length].path;

                      final bool isSelected =
                          selectionState.isPathSelected(itemPath);

                      return LayoutBuilder(builder:
                          (BuildContext context, BoxConstraints constraints) {
                        if (isDesktopPlatform) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            try {
                              final RenderBox? renderBox =
                                  context.findRenderObject() as RenderBox?;
                              if (renderBox != null &&
                                  renderBox.hasSize &&
                                  renderBox.attached) {
                                final position =
                                    renderBox.localToGlobal(Offset.zero);
                                dragSelectionController.registerItemPosition(
                                    itemPath,
                                    Rect.fromLTWH(
                                        position.dx,
                                        position.dy,
                                        renderBox.size.width,
                                        renderBox.size.height));
                              }
                            } catch (e) {
                              debugPrint('Layout error in list view: $e');
                            }
                          });
                        }

                        if (index < state.folders.length) {
                          final folder = state.folders[index] as Directory;
                          return _wrapFileDragDrop(
                            isDesktopPlatform: isDesktopPlatform,
                            isFolder: true,
                            path: folder.path,
                            selectionState: selectionState,
                            onStartFileDrag: onStartFileDrag,
                            onMoveItemsToFolder: onMoveItemsToFolder,
                            child: Container(
                              key: itemKeyForPath?.call(folder.path),
                              child: KeyedSubtree(
                                key: ValueKey("folder-${folder.path}"),
                                child: FluentBackground(
                                  enableBlur: false,
                                  blurAmount: 3.0,
                                  opacity: 0.0,
                                  backgroundColor: Colors.transparent,
                                  borderRadius: BorderRadius.zero,
                                  child: RepaintBoundary(
                                    child: folder_list_components.FolderItem(
                                      key: ValueKey(
                                          "folder-item-${folder.path}"),
                                      folder: folder,
                                      onTap: onNavigateToPath,
                                      isSelected: isSelected,
                                      toggleFolderSelection:
                                          toggleFolderSelection,
                                      isDesktopMode: isDesktopPlatform,
                                      lastSelectedPath:
                                          selectionState.lastSelectedPath,
                                      showItemBackground: false,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        } else {
                          final file =
                              state.files[index - state.folders.length] as File;
                          return _wrapFileDragDrop(
                            isDesktopPlatform: isDesktopPlatform,
                            isFolder: false,
                            path: file.path,
                            selectionState: selectionState,
                            onStartFileDrag: onStartFileDrag,
                            child: Container(
                              key: itemKeyForPath?.call(file.path),
                              child: KeyedSubtree(
                                key: ValueKey("file-${file.path}"),
                                child: FluentBackground(
                                  enableBlur: false,
                                  blurAmount: 3.0,
                                  opacity: 0.0,
                                  backgroundColor: Colors.transparent,
                                  borderRadius: BorderRadius.zero,
                                  child: RepaintBoundary(
                                    child: folder_list_components.FileItem(
                                      key: ValueKey("file-item-${file.path}"),
                                      file: file,
                                      state: state,
                                      isSelectionMode: itemSelectionMode,
                                      isSelected: isSelected,
                                      toggleFileSelection: toggleFileSelection,
                                      showDeleteTagDialog: showDeleteTagDialog,
                                      showAddTagToFileDialog:
                                          showAddTagToFileDialog,
                                      onDeleteFile: onDeleteFile,
                                      onDeleteFiles: onDeleteFiles,
                                      onFileTap: onFileTap,
                                      isDesktopMode: isDesktopPlatform,
                                      lastSelectedPath:
                                          selectionState.lastSelectedPath,
                                      showFileTags: showFileTags,
                                      showItemBackground: false,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ),
        dragSelectionController.buildOverlay(),
      ],
    );
  }

  /// Build tiles view — multi-column layout with icon + metadata per item.
  /// Ctrl+scroll spectrum is handled by the outer [CtrlScrollZoom] wrapper.
  static Widget _buildTilesView({
    required FolderListState state,
    required SelectionState selectionState,
    required bool isDesktopPlatform,
    required Function(String) onNavigateToPath,
    required Function(File, bool) onFileTap,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
        toggleFileSelection,
    required Function(String, {bool shiftSelect, bool ctrlSelect})
        toggleFolderSelection,
    required VoidCallback clearSelection,
    required TabbedFolderDragSelectionController dragSelectionController,
    required Function(BuildContext, Offset) showContextMenu,
    required bool showFileTags,
    required Function(BuildContext, String, List<String>) showDeleteTagDialog,
    required Function(BuildContext, String) showAddTagToFileDialog,
    Future<void> Function(BuildContext, File)? onDeleteFile,
    Future<void> Function(BuildContext, List<String>)? onDeleteFiles,
    ValueChanged<List<String>>? onStartFileDrag,
    Future<void> Function(List<String> sources, String destinationFolder)?
        onMoveItemsToFolder,
    ScrollController? scrollController,
    GlobalKey Function(String path)? itemKeyForPath,
    ValueChanged<int?>? onGridCrossAxisCountChanged,
    ValueChanged<double?>? onGridItemMainAxisExtentChanged,
  }) {
    final itemSelectionMode =
        selectionState.isSelectionMode && !isDesktopPlatform;
    return Stack(
      key: dragSelectionController.stackKey,
      clipBehavior: Clip.none,
      children: [
        FluentBackground(
          blurAmount: 8.0,
          opacity: 0.0,
          backgroundColor: Colors.transparent,
          enableBlur: false,
          child: BlocBuilder<SelectionBloc, SelectionState>(
            builder: (context, selectionState) {
              return GestureDetector(
                onTap: () {
                  if (selectionState.isSelectionMode) {
                    clearSelection();
                  }
                },
                onSecondaryTapUp: (details) {
                  showContextMenu(context, details.globalPosition);
                },
                onLongPressStart: !isDesktopPlatform
                    ? (details) {
                        HapticFeedback.mediumImpact();
                        showContextMenu(context, details.globalPosition);
                      }
                    : null,
                onPanStart: isDesktopPlatform
                    ? (details) {
                        final focused = FocusManager.instance.primaryFocus;
                        final focusedContext = focused?.context;
                        if (focusedContext != null) {
                          final isEditableText =
                              focusedContext.widget is EditableText ||
                                  focusedContext.findAncestorWidgetOfExactType<
                                          EditableText>() !=
                                      null;
                          if (isEditableText) {
                            return;
                          }
                        }
                        dragSelectionController.start(details.localPosition);
                      }
                    : null,
                onPanUpdate: isDesktopPlatform
                    ? (details) {
                        dragSelectionController.update(details.localPosition);
                      }
                    : null,
                onPanEnd: isDesktopPlatform
                    ? (details) {
                        dragSelectionController.end();
                      }
                    : null,
                behavior: HitTestBehavior.translucent,
                child: RepaintBoundary(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final availableWidth = math.max(
                        0.0,
                        constraints.maxWidth - (_tilesSpacing * 2),
                      );
                      final crossAxisCount = math.max(
                        1,
                        ((availableWidth + _tilesSpacing) /
                                (_tilesMaxCrossAxisExtent + _tilesSpacing))
                            .floor(),
                      );
                      onGridCrossAxisCountChanged?.call(crossAxisCount);
                      onGridItemMainAxisExtentChanged
                          ?.call(_tilesMainAxisExtent + _tilesSpacing);

                      return GridView.builder(
                        controller: scrollController,
                        physics: const ClampingScrollPhysics(),
                        cacheExtent: 800,
                        padding: const EdgeInsets.all(_tilesSpacing),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: _tilesMaxCrossAxisExtent,
                          mainAxisExtent: _tilesMainAxisExtent,
                          crossAxisSpacing: _tilesSpacing,
                          mainAxisSpacing: _tilesSpacing,
                        ),
                        itemCount: state.folders.length + state.files.length,
                        itemBuilder: (context, index) {
                          final String itemPath = index < state.folders.length
                              ? state.folders[index].path
                              : state.files[index - state.folders.length].path;
                          final bool isSelected =
                              selectionState.isPathSelected(itemPath);

                          return LayoutBuilder(
                            builder: (context, constraints) {
                              if (isDesktopPlatform) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  try {
                                    final RenderBox? renderBox = context
                                        .findRenderObject() as RenderBox?;
                                    if (renderBox != null &&
                                        renderBox.hasSize &&
                                        renderBox.attached) {
                                      final position =
                                          renderBox.localToGlobal(Offset.zero);
                                      dragSelectionController
                                          .registerItemPosition(
                                        itemPath,
                                        Rect.fromLTWH(
                                          position.dx,
                                          position.dy,
                                          renderBox.size.width,
                                          renderBox.size.height,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    debugPrint(
                                        'Layout error in tiles view: $e');
                                  }
                                });
                              }

                              if (index < state.folders.length) {
                                final folder =
                                    state.folders[index] as Directory;
                                return _wrapFileDragDrop(
                                  isDesktopPlatform: isDesktopPlatform,
                                  isFolder: true,
                                  path: folder.path,
                                  selectionState: selectionState,
                                  onStartFileDrag: onStartFileDrag,
                                  onMoveItemsToFolder: onMoveItemsToFolder,
                                  child: Container(
                                    key: itemKeyForPath?.call(folder.path),
                                    child: KeyedSubtree(
                                      key: ValueKey(
                                          'folder-tile-${folder.path}'),
                                      child: RepaintBoundary(
                                        child:
                                            folder_list_components.FolderItem(
                                          key: ValueKey(
                                              'folder-tile-item-${folder.path}'),
                                          folder: folder,
                                          onTap: onNavigateToPath,
                                          isSelected: isSelected,
                                          toggleFolderSelection:
                                              toggleFolderSelection,
                                          isDesktopMode: isDesktopPlatform,
                                          lastSelectedPath:
                                              selectionState.lastSelectedPath,
                                          showItemBackground: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final file = state
                                  .files[index - state.folders.length] as File;
                              return _wrapFileDragDrop(
                                isDesktopPlatform: isDesktopPlatform,
                                isFolder: false,
                                path: file.path,
                                selectionState: selectionState,
                                onStartFileDrag: onStartFileDrag,
                                child: Container(
                                  key: itemKeyForPath?.call(file.path),
                                  child: KeyedSubtree(
                                    key: ValueKey('file-tile-${file.path}'),
                                    child: RepaintBoundary(
                                      child: folder_list_components.FileItem(
                                        key: ValueKey(
                                            'file-tile-item-${file.path}'),
                                        file: file,
                                        state: state,
                                        isSelectionMode: itemSelectionMode,
                                        isSelected: isSelected,
                                        toggleFileSelection:
                                            toggleFileSelection,
                                        showDeleteTagDialog:
                                            showDeleteTagDialog,
                                        showAddTagToFileDialog:
                                            showAddTagToFileDialog,
                                        onDeleteFile: onDeleteFile,
                                        onDeleteFiles: onDeleteFiles,
                                        onFileTap: onFileTap,
                                        isDesktopMode: isDesktopPlatform,
                                        lastSelectedPath:
                                            selectionState.lastSelectedPath,
                                        showFileTags: showFileTags,
                                        showItemBackground: true,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        dragSelectionController.buildOverlay(),
      ],
    );
  }

  static Widget _wrapWithPreviewPane({
    required Widget contentView,
    required FolderListState state,
    required SelectionState selectionState,
    required Function(File, bool) onFileTap,
    required VoidCallback onPreviewPaneToggled,
    required ValueListenable<double> previewPaneWidthListenable,
    required ValueChanged<double> onPreviewPaneWidthChanged,
    required ValueChanged<double> onPreviewPaneWidthCommitted,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minPreviewWidth = 280.0;
        const double minContentWidth = 240.0;
        final double maxPreviewWidthByRatio = constraints.maxWidth * 0.8;
        final double maxPreviewWidthByContent =
            constraints.maxWidth - minContentWidth;
        final double maxPreviewWidth = math.max(
          0.0,
          math.min(maxPreviewWidthByRatio, maxPreviewWidthByContent),
        );
        if (maxPreviewWidth <= 0.0) {
          return contentView;
        }
        final double effectiveMinPreviewWidth =
            math.min(minPreviewWidth, maxPreviewWidth);

        return _PreviewPaneLayout(
          contentView: contentView,
          state: state,
          selectionState: selectionState,
          onFileTap: onFileTap,
          onPreviewPaneToggled: onPreviewPaneToggled,
          previewPaneWidthListenable: previewPaneWidthListenable,
          onPreviewPaneWidthChanged: onPreviewPaneWidthChanged,
          onPreviewPaneWidthCommitted: onPreviewPaneWidthCommitted,
          minPreviewWidth: effectiveMinPreviewWidth,
          maxPreviewWidth: maxPreviewWidth,
          availableWidth: constraints.maxWidth,
        );
      },
    );
  }
}

class _PreviewPaneLayout extends StatefulWidget {
  final Widget contentView;
  final FolderListState state;
  final SelectionState selectionState;
  final Function(File, bool) onFileTap;
  final VoidCallback onPreviewPaneToggled;
  final ValueListenable<double> previewPaneWidthListenable;
  final ValueChanged<double> onPreviewPaneWidthChanged;
  final ValueChanged<double> onPreviewPaneWidthCommitted;
  final double minPreviewWidth;
  final double maxPreviewWidth;
  final double availableWidth;

  const _PreviewPaneLayout({
    required this.contentView,
    required this.state,
    required this.selectionState,
    required this.onFileTap,
    required this.onPreviewPaneToggled,
    required this.previewPaneWidthListenable,
    required this.onPreviewPaneWidthChanged,
    required this.onPreviewPaneWidthCommitted,
    required this.minPreviewWidth,
    required this.maxPreviewWidth,
    required this.availableWidth,
  });

  @override
  State<_PreviewPaneLayout> createState() => _PreviewPaneLayoutState();
}

class _PreviewPaneLayoutState extends State<_PreviewPaneLayout> {
  double? _dragStartX;
  double? _dragStartWidth;
  double? _dragPreviewWidth;

  void _handlePanStart(DragStartDetails details, double currentWidth) {
    _dragStartX = details.globalPosition.dx;
    _dragStartWidth = currentWidth;
    setState(() {
      _dragPreviewWidth = currentWidth;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final startX = _dragStartX;
    final startWidth = _dragStartWidth;
    if (startX == null || startWidth == null) return;

    final delta = details.globalPosition.dx - startX;
    final newWidth = (startWidth - delta).clamp(
      widget.minPreviewWidth,
      widget.maxPreviewWidth,
    );
    setState(() {
      _dragPreviewWidth = newWidth;
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    final widthToCommit =
        _dragPreviewWidth ?? widget.previewPaneWidthListenable.value;
    widget.onPreviewPaneWidthChanged(widthToCommit);
    widget.onPreviewPaneWidthCommitted(widthToCommit);
    setState(() {
      _dragPreviewWidth = null;
    });
    _dragStartX = null;
    _dragStartWidth = null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.previewPaneWidthListenable,
      child: widget.contentView,
      builder: (context, currentWidth, child) {
        final double effectivePreviewWidth =
            currentWidth.clamp(widget.minPreviewWidth, widget.maxPreviewWidth);
        final double previewWidthForIndicator =
            _dragPreviewWidth ?? effectivePreviewWidth;
        final double indicatorRight =
            (previewWidthForIndicator + _PreviewResizeHandle.handleWidth / 2)
                .clamp(0.0, widget.availableWidth);
        final double ghostWidth = previewWidthForIndicator.clamp(
          0.0,
          widget.availableWidth,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                Expanded(child: child!),
                _PreviewResizeHandle(
                  onPanStart: (details) =>
                      _handlePanStart(details, effectivePreviewWidth),
                  onPanUpdate: _handlePanUpdate,
                  onPanEnd: _handlePanEnd,
                ),
                SizedBox(
                  width: effectivePreviewWidth,
                  child: FilePreviewPane(
                    state: widget.state,
                    selectionState: widget.selectionState,
                    onOpenFile: widget.onFileTap,
                    onClosePreview: widget.onPreviewPaneToggled,
                  ),
                ),
              ],
            ),
            if (_dragPreviewWidth != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      if (ghostWidth > 0)
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width: ghostWidth,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
                                colors: [
                                  Theme.of(context).shadowColor.withValues(
                                        alpha: 0.04,
                                      ),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: indicatorRight.clamp(0.0, widget.availableWidth),
                        child: Center(
                          child: Container(
                            width: 1,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PreviewResizeHandle extends StatefulWidget {
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  static const double _handleWidth = 6.0;

  const _PreviewResizeHandle({
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  static double get handleWidth => _handleWidth;

  @override
  State<_PreviewResizeHandle> createState() => _PreviewResizeHandleState();
}

class _PreviewResizeHandleState extends State<_PreviewResizeHandle> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final active = _hovering || _dragging;
    final lineColor = active
        ? theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.16 : 0.1)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (details) {
          setState(() => _dragging = true);
          widget.onPanStart(details);
        },
        onPanUpdate: widget.onPanUpdate,
        onPanEnd: (details) {
          setState(() => _dragging = false);
          widget.onPanEnd(details);
        },
        child: SizedBox(
          width: _PreviewResizeHandle._handleWidth,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: active ? 1.5 : 0,
              height: active ? 56 : 0,
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
