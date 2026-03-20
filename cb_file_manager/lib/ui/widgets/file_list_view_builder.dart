import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/index.dart'
    as folder_list_components;
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/utils/fluent_background.dart';
import 'package:cb_file_manager/ui/utils/scroll_velocity_notifier.dart';
import 'package:cb_file_manager/ui/widgets/file_preview_pane.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';

/// Static factory class for building file list views in different modes
class FileListViewBuilder {
  static const double _gridSpacing = 8.0;
  static const double _gridAspectRatio = 0.8;
  static const double _gridReferenceWidth = 960.0;

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
    required VoidCallback toggleSelectionMode,
    required ColumnVisibility columnVisibility,
    required Function(BuildContext, Offset) showContextMenu,
    required bool isPreviewPaneVisible,
    required ValueListenable<double> previewPaneWidthListenable,
    required ValueChanged<int> onZoomLevelChanged,
    required ValueChanged<double> onPreviewPaneWidthChanged,
    required ValueChanged<double> onPreviewPaneWidthCommitted,
    required VoidCallback onPreviewPaneToggled,
    ValueChanged<int?>? onGridCrossAxisCountChanged,
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

    // Use separate builders for each view type to prevent complete tree rebuilds
    if (displayState.viewMode == ViewMode.gridPreview && isDesktopPlatform) {
      return _buildGridPreviewView(
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
        showDeleteTagDialog: showDeleteTagDialog,
        showAddTagToFileDialog: showAddTagToFileDialog,
        isPreviewPaneVisible: isPreviewPaneVisible,
        previewPaneWidthListenable: previewPaneWidthListenable,
        onZoomLevelChanged: onZoomLevelChanged,
        onPreviewPaneWidthChanged: onPreviewPaneWidthChanged,
        onPreviewPaneWidthCommitted: onPreviewPaneWidthCommitted,
        onPreviewPaneToggled: onPreviewPaneToggled,
        onGridCrossAxisCountChanged: onGridCrossAxisCountChanged,
      );
    }

    if (displayState.viewMode == ViewMode.grid ||
        displayState.viewMode == ViewMode.gridPreview) {
      return _buildGridView(
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
        onGridCrossAxisCountChanged: onGridCrossAxisCountChanged,
      );
    } else if (displayState.viewMode == ViewMode.details) {
      return _buildDetailsView(
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
        toggleSelectionMode: toggleSelectionMode,
        columnVisibility: columnVisibility,
        showFileTags: showFileTags,
        showContextMenu: showContextMenu,
      );
    } else {
      return _buildListView(
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
      );
    }
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
    ValueChanged<int?>? onGridCrossAxisCountChanged,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FluentBackground(
          blurAmount: 8.0,
          opacity: 0.2,
          enableBlur: isDesktopPlatform,
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
                child: Listener(
                  onPointerSignal: (PointerSignalEvent event) {
                    if (state.viewMode != ViewMode.grid &&
                        state.viewMode != ViewMode.gridPreview) {
                      return;
                    }
                    if (event is PointerScrollEvent) {
                      if (RawKeyboard.instance.keysPressed
                              .contains(LogicalKeyboardKey.controlLeft) ||
                          RawKeyboard.instance.keysPressed
                              .contains(LogicalKeyboardKey.controlRight)) {
                        final direction = event.scrollDelta.dy > 0 ? 1 : -1;
                        onZoomLevelChanged(direction);
                        GestureBinding.instance.pointerSignalResolver
                            .resolve(event);
                      }
                    }
                  },
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
                        final folderIndexByPath = <String, int>{
                          for (var i = 0; i < state.folders.length; i++)
                            state.folders[i].path: i,
                        };
                        final fileIndexByPath = <String, int>{
                          for (var i = 0; i < state.files.length; i++)
                            state.files[i].path: i,
                        };

                        return ScrollVelocityListener(
                          child: GridView.builder(
                            padding: const EdgeInsets.all(8.0),
                            physics: const ClampingScrollPhysics(),
                            // PERFORMANCE: Reduced cacheExtent to minimize pre-building during fast scroll
                            // Desktop: 400px, Mobile: 200px - balances smooth scrolling vs thumbnail generation
                            cacheExtent: isDesktopPlatform ? 400 : 200,
                            addAutomaticKeepAlives: false,
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
                            itemBuilder: (context, index) {
                              final String itemPath =
                                  index < state.folders.length
                                      ? state.folders[index].path
                                      : state
                                          .files[index - state.folders.length]
                                          .path;
                              final String itemKey =
                                  index < state.folders.length
                                      ? 'folder-grid-$itemPath'
                                      : 'file-grid-$itemPath';

                              final bool isSelected =
                                  selectionState.isPathSelected(itemPath);

                              return KeyedSubtree(
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
                                      return Align(
                                        alignment: Alignment.topCenter,
                                        child: SizedBox(
                                          width: itemWidth,
                                          height: itemHeight,
                                          child: RepaintBoundary(
                                            child: FluentBackground.container(
                                              context: context,
                                              enableBlur: isDesktopPlatform,
                                              padding: EdgeInsets.zero,
                                              blurAmount: 5.0,
                                              opacity: isSelected ? 0.8 : 0.6,
                                              backgroundColor: isSelected
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                      .withValues(alpha: 0.6)
                                                  : Theme.of(context)
                                                      .cardColor
                                                      .withValues(alpha: 0.4),
                                              child: folder_list_components
                                                  .FolderGridItem(
                                                key: ValueKey(
                                                    'folder-grid-item-${folder.path}'),
                                                folder: folder,
                                                onNavigate: onNavigateToPath,
                                                isSelected: isSelected,
                                                toggleFolderSelection:
                                                    toggleFolderSelection,
                                                isDesktopMode:
                                                    isDesktopPlatform,
                                                lastSelectedPath: selectionState
                                                    .lastSelectedPath,
                                                clearSelectionMode:
                                                    clearSelection,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    } else {
                                      final file = state.files[
                                          index - state.folders.length] as File;
                                      return Align(
                                        alignment: Alignment.topCenter,
                                        child: SizedBox(
                                          width: itemWidth,
                                          height: itemHeight,
                                          child: RepaintBoundary(
                                            child: FluentBackground.container(
                                              context: context,
                                              enableBlur: isDesktopPlatform,
                                              padding: EdgeInsets.zero,
                                              blurAmount: 5.0,
                                              opacity: isSelected ? 0.8 : 0.6,
                                              backgroundColor: isSelected
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                      .withValues(alpha: 0.6)
                                                  : Theme.of(context)
                                                      .cardColor
                                                      .withValues(alpha: 0.4),
                                              child: folder_list_components
                                                  .FileGridItem(
                                                key: ValueKey(
                                                    'file-grid-item-${file.path}'),
                                                file: file,
                                                state: state,
                                                isSelectionMode: selectionState
                                                    .isSelectionMode,
                                                isSelected: isSelected,
                                                toggleFileSelection:
                                                    toggleFileSelection,
                                                toggleSelectionMode:
                                                    toggleSelectionMode,
                                                onFileTap: onFileTap,
                                                isDesktopMode:
                                                    isDesktopPlatform,
                                                lastSelectedPath: selectionState
                                                    .lastSelectedPath,
                                                showFileTags: showFileTags,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              );
                            },
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
    required VoidCallback toggleSelectionMode,
    required ColumnVisibility columnVisibility,
    required bool showFileTags,
    required Function(BuildContext, Offset) showContextMenu,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FluentBackground(
          blurAmount: 8.0,
          opacity: 0.2,
          enableBlur: isDesktopPlatform,
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
                    isSelectionMode: selectionState.isSelectionMode,
                    isGridView: false,
                    selectedFiles: selectionState.allSelectedPaths,
                    toggleFileSelection: toggleFileSelection,
                    toggleSelectionMode: toggleSelectionMode,
                    showDeleteTagDialog: showDeleteTagDialog,
                    showAddTagToFileDialog: showAddTagToFileDialog,
                    onFolderTap: onNavigateToPath,
                    onFileTap: onFileTap,
                    isDesktopMode: isDesktopPlatform,
                    lastSelectedPath: selectionState.lastSelectedPath,
                    columnVisibility: columnVisibility,
                    showFileTags: showFileTags,
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
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FluentBackground(
          blurAmount: 8.0,
          opacity: 0.2,
          enableBlur: isDesktopPlatform,
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
                    physics: const ClampingScrollPhysics(),
                    cacheExtent: 800,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    addSemanticIndexes: false,
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
                          return KeyedSubtree(
                            key: ValueKey("folder-${folder.path}"),
                            child: FluentBackground(
                              enableBlur: isDesktopPlatform,
                              blurAmount: 3.0,
                              opacity: isSelected ? 0.7 : 0.0,
                              backgroundColor: isSelected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.6)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16.0),
                              child: RepaintBoundary(
                                child: folder_list_components.FolderItem(
                                  key: ValueKey("folder-item-${folder.path}"),
                                  folder: folder,
                                  onTap: onNavigateToPath,
                                  isSelected: isSelected,
                                  toggleFolderSelection: toggleFolderSelection,
                                  isDesktopMode: isDesktopPlatform,
                                  lastSelectedPath:
                                      selectionState.lastSelectedPath,
                                ),
                              ),
                            ),
                          );
                        } else {
                          final file =
                              state.files[index - state.folders.length] as File;
                          return KeyedSubtree(
                            key: ValueKey("file-${file.path}"),
                            child: FluentBackground(
                              enableBlur: isDesktopPlatform,
                              blurAmount: 3.0,
                              opacity: isSelected ? 0.7 : 0.0,
                              backgroundColor: isSelected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.6)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16.0),
                              child: RepaintBoundary(
                                child: folder_list_components.FileItem(
                                  key: ValueKey("file-item-${file.path}"),
                                  file: file,
                                  state: state,
                                  isSelectionMode:
                                      selectionState.isSelectionMode,
                                  isSelected: isSelected,
                                  toggleFileSelection: toggleFileSelection,
                                  showDeleteTagDialog:
                                      (context, filePath, tags) {},
                                  showAddTagToFileDialog:
                                      (context, filePath) {},
                                  onFileTap: onFileTap,
                                  isDesktopMode: isDesktopPlatform,
                                  lastSelectedPath:
                                      selectionState.lastSelectedPath,
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

  static Widget _buildGridPreviewView({
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
    required Function(BuildContext, String, List<String>) showDeleteTagDialog,
    required Function(BuildContext, String) showAddTagToFileDialog,
    required bool isPreviewPaneVisible,
    required ValueListenable<double> previewPaneWidthListenable,
    required ValueChanged<int> onZoomLevelChanged,
    required ValueChanged<double> onPreviewPaneWidthChanged,
    required ValueChanged<double> onPreviewPaneWidthCommitted,
    required VoidCallback onPreviewPaneToggled,
    ValueChanged<int?>? onGridCrossAxisCountChanged,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!isPreviewPaneVisible) {
          return _buildGridView(
            state: state,
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
            onGridCrossAxisCountChanged: onGridCrossAxisCountChanged,
          );
        }

        const double minPreviewWidth = 280.0;
        const double minGridWidth = 360.0;
        final double maxPreviewWidthByRatio = constraints.maxWidth * 0.8;
        final double maxPreviewWidthByGrid =
            constraints.maxWidth - minGridWidth;
        final double maxPreviewWidth = math.max(
          0.0,
          math.min(maxPreviewWidthByRatio, maxPreviewWidthByGrid),
        );
        if (maxPreviewWidth <= 0.0) {
          return _buildGridView(
            state: state,
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
            onGridCrossAxisCountChanged: onGridCrossAxisCountChanged,
          );
        }
        final double effectiveMinPreviewWidth =
            math.min(minPreviewWidth, maxPreviewWidth);
        final gridView = _buildGridView(
          state: state,
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
          onGridCrossAxisCountChanged: onGridCrossAxisCountChanged,
        );

        return _GridPreviewLayout(
          gridView: gridView,
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

class _GridPreviewLayout extends StatefulWidget {
  final Widget gridView;
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

  const _GridPreviewLayout({
    required this.gridView,
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
  State<_GridPreviewLayout> createState() => _GridPreviewLayoutState();
}

class _GridPreviewLayoutState extends State<_GridPreviewLayout> {
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
      child: widget.gridView,
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
                          child: Container(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.04),
                          ),
                        ),
                      Positioned(
                        top: 8,
                        bottom: 8,
                        right: indicatorRight,
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.75),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: (indicatorRight - 14)
                            .clamp(0.0, widget.availableWidth - 28),
                        child: Center(
                          child: Container(
                            width: 28,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [],
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

class _PreviewResizeHandle extends StatelessWidget {
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  static const double _handleWidth = 12.0;
  static const double _indicatorWidth = 3.0;
  static const double _indicatorHeight = 96.0;

  const _PreviewResizeHandle({
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  static double get handleWidth => _handleWidth;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: SizedBox(
          width: _handleWidth,
          child: Center(
            child: Container(
              width: _indicatorWidth,
              height: _indicatorHeight,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


