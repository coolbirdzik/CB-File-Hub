import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';
import 'package:flutter/gestures.dart'; // Import for PointerSignalEvent
import 'package:flutter/services.dart'; // Import for HardwareKeyboard
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/utils/scroll_velocity_notifier.dart';

import 'file_item.dart';
import 'file_grid_item.dart';
import 'folder_item.dart';
import 'folder_grid_item.dart';
import 'file_details_item.dart';
import 'folder_details_item.dart';

class FileView extends StatelessWidget {
  static const double _gridSpacing = 12.0;
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

  final List<File> files;
  final List<Directory> folders;
  final FolderListState state;
  final bool isSelectionMode;
  final bool isGridView;
  final List<String> selectedFiles;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;
  final Function() toggleSelectionMode;
  final Function(BuildContext, String, List<String>) showDeleteTagDialog;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final Function(String)? onFolderTap;
  final Function(File, bool)? onFileTap;
  final Function()? onThumbnailGenerated;
  final Function(int)? onZoomChanged; // Thêm callback mới cho thay đổi zoom
  final bool isDesktopMode;
  final String? lastSelectedPath;
  final ColumnVisibility columnVisibility;
  final Function()?
      clearSelectionMode; // Add new callback for clearing selection mode
  final bool showFileTags; // Add parameter to control tag display

  const FileView({
    Key? key,
    required this.files,
    required this.folders,
    required this.state,
    required this.isSelectionMode,
    required this.isGridView,
    required this.selectedFiles,
    required this.toggleFileSelection,
    required this.toggleSelectionMode,
    required this.showDeleteTagDialog,
    required this.showAddTagToFileDialog,
    this.onFolderTap,
    this.onFileTap,
    this.onThumbnailGenerated,
    this.onZoomChanged, // Thêm parameter
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.columnVisibility = const ColumnVisibility(),
    this.clearSelectionMode, // Add new parameter
    this.showFileTags = true, // Default to showing tags
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Optimize frame timing before building view
    FrameTimingOptimizer().optimizeBeforeHeavyOperation();

    if (isGridView) {
      return _buildGridView();
    } else if (state.viewMode == ViewMode.details) {
      return _buildDetailsView(context);
    } else {
      return _buildListView();
    }
  }

  Widget _buildListView() {
    // Optimize scrolling with frame timing
    FrameTimingOptimizer().optimizeScrolling();

    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final bool isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    // Use actual platform detection instead of parameter
    final bool actualIsDesktop = isDesktop;

    return ListView.builder(
      // Optimized physics for desktop smooth scrolling
      physics: isDesktop
          ? const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            )
          : isMobile
              ? const ClampingScrollPhysics()
              : const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
      // PERFORMANCE: Reduced cacheExtent to minimize pre-building during fast scroll
      cacheExtent: isDesktop ? 400 : (isMobile ? 200 : 300),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      itemCount: folders.length + files.length,
      itemBuilder: (context, index) {
        // Generate a stable key for item identity
        final String itemKey = index < folders.length
            ? 'folder-${folders[index].path}'
            : 'file-${files[index - folders.length].path}';

        // Use RepaintBoundary to reduce rendering load during scrolling
        return KeyedSubtree(
          key: ValueKey(itemKey),
          child: RepaintBoundary(
            child: index < folders.length
                ? FolderItem(
                    key: ValueKey('folder-item-${folders[index].path}'),
                    folder: folders[index],
                    onTap: onFolderTap,
                    isSelected: selectedFiles.contains(folders[index].path),
                    toggleFolderSelection: toggleFileSelection,
                    isDesktopMode: actualIsDesktop,
                    lastSelectedPath: lastSelectedPath,
                    clearSelectionMode: clearSelectionMode,
                  )
                : FileItem(
                    key: ValueKey(
                        'file-item-${files[index - folders.length].path}'),
                    file: files[index - folders.length],
                    state: state,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedFiles
                        .contains(files[index - folders.length].path),
                    toggleFileSelection: toggleFileSelection,
                    showDeleteTagDialog: showDeleteTagDialog,
                    showAddTagToFileDialog: showAddTagToFileDialog,
                    onFileTap: onFileTap,
                    isDesktopMode: actualIsDesktop,
                    lastSelectedPath: lastSelectedPath,
                    showFileTags: showFileTags,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildDetailsView(BuildContext context) {
    // Optimize scrolling with frame timing
    FrameTimingOptimizer().optimizeScrolling();
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final bool isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    // Define text style for headers once to be reused
    final TextStyle headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurface,
    );

    // Debug selection count
    debugPrint(
        "FileView _buildDetailsView - Selected files count: ${selectedFiles.length}");

    return Column(
      children: [
        // Column headers for details view with info tooltip
        Stack(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Row(
                children: [
                  // Name column (always visible)
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10.0, horizontal: 12.0),
                      child: Row(
                        children: [
                          Text(
                            'Tên',
                            style: headerStyle,
                          ),
                          const SizedBox(width: 4),
                          Icon(PhosphorIconsLight.arrowDown,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurface),
                        ],
                      ),
                    ),
                  ),

                  // Type column
                  if (columnVisibility.type)
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10.0, horizontal: 12.0),
                        child: Text(
                          'Loại',
                          style: headerStyle,
                        ),
                      ),
                    ),

                  // Size column
                  if (columnVisibility.size)
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10.0, horizontal: 12.0),
                        child: Text(
                          'Kích thước',
                          style: headerStyle,
                        ),
                      ),
                    ),

                  // Date modified column
                  if (columnVisibility.dateModified)
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10.0, horizontal: 12.0),
                        child: Text(
                          'Ngày sửa đổi',
                          style: headerStyle,
                        ),
                      ),
                    ),

                  // Date created column
                  if (columnVisibility.dateCreated)
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10.0, horizontal: 12.0),
                        child: Text(
                          'Ngày tạo',
                          style: headerStyle,
                        ),
                      ),
                    ),

                  // Attributes column
                  if (columnVisibility.attributes)
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10.0, horizontal: 12.0),
                        child: Text(
                          'Thuộc tính',
                          style: headerStyle,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Add info button with tooltip about customizing columns
            Positioned(
              right: 8,
              top: 8,
              child: Tooltip(
                message:
                    'Nhấn nút cài đặt cột ở thanh công cụ trên cùng để tùy chỉnh các cột hiển thị',
                child: Icon(
                  PhosphorIconsLight.info,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),

        // List of files and folders
        Expanded(
          child: ListView.builder(
            physics: isDesktop
                ? const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  )
                : isMobile
                    ? const ClampingScrollPhysics()
                    : const ClampingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
            // PERFORMANCE: Reduced cacheExtent to minimize pre-building during fast scroll
            cacheExtent: isDesktop ? 400 : (isMobile ? 200 : 300),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            addSemanticIndexes: false,
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            itemCount: folders.length + files.length,
            itemBuilder: (context, index) {
              // Add alternating row colors to make it look more like a details table
              final bool isEvenRow = index % 2 == 0;
              final Color rowColor = isEvenRow
                  ? Colors.transparent
                  : const Color.fromRGBO(128, 128, 128, 0.03);

              // Generate a stable key to help Flutter reuse widgets
              final String itemKey = index < folders.length
                  ? 'folder-${folders[index].path}'
                  : 'file-${files[index - folders.length].path}';

              return Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 2.0, horizontal: 12.0),
                decoration: BoxDecoration(
                  color: rowColor,
                ),
                // Use KeyedSubtree with a stable key to prevent unnecessary rebuilds
                child: KeyedSubtree(
                  key: ValueKey(itemKey),
                  child: RepaintBoundary(
                    child: index < folders.length
                        ? _FolderDetailsItemWrapper(
                            key: ValueKey(
                                'folder-detail-${folders[index].path}'),
                            folder: folders[index],
                            onTap: onFolderTap,
                            isSelected:
                                selectedFiles.contains(folders[index].path),
                            columnVisibility: columnVisibility,
                            toggleFolderSelection: toggleFileSelection,
                            isDesktopMode: isDesktopMode,
                            lastSelectedPath: lastSelectedPath,
                            clearSelectionMode: clearSelectionMode,
                          )
                        : _FileDetailsItemWrapper(
                            key: ValueKey(
                                'file-detail-${files[index - folders.length].path}'),
                            file: files[index - folders.length],
                            state: state,
                            isSelected: selectedFiles
                                .contains(files[index - folders.length].path),
                            columnVisibility: columnVisibility,
                            toggleFileSelection: toggleFileSelection,
                            showDeleteTagDialog: showDeleteTagDialog,
                            showAddTagToFileDialog: showAddTagToFileDialog,
                            onTap: onFileTap,
                            isDesktopMode: isDesktopMode,
                            lastSelectedPath: lastSelectedPath,
                            showFileTags: showFileTags,
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGridView() {
    // Optimize scrolling with frame timing
    FrameTimingOptimizer().optimizeScrolling();
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final bool isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    // Wrap the GridView with a Listener to detect mouse wheel events
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        // Only process if we have a zoom handler
        if (onZoomChanged == null) return;

        // Handle mouse wheel events with Ctrl key
        if (event is PointerScrollEvent) {
          if (HardwareKeyboard.instance.logicalKeysPressed
                  .contains(LogicalKeyboardKey.controlLeft) ||
              HardwareKeyboard.instance.logicalKeysPressed
                  .contains(LogicalKeyboardKey.controlRight)) {
            final int direction = event.scrollDelta.dy > 0 ? 1 : -1;
            onZoomChanged!(direction);
            GestureBinding.instance.pointerSignalResolver.resolve(event);
          }
        }
      },
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
          final availableWidth =
              math.max(0.0, constraints.maxWidth - (_gridSpacing * 2));
          final crossAxisCount = _gridCrossAxisCount(availableWidth, itemWidth);
          final itemHeight = itemWidth / _gridAspectRatio;
          final folderIndexByPath = <String, int>{
            for (var i = 0; i < folders.length; i++) folders[i].path: i,
          };
          final fileIndexByPath = <String, int>{
            for (var i = 0; i < files.length; i++) files[i].path: i,
          };

          return ScrollVelocityListener(
            child: GridView.builder(
              physics: isDesktop
                  ? const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    )
                  : isMobile
                      ? const ClampingScrollPhysics()
                      : const ClampingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
              // Reduced cache extent to prevent pre-building too many widgets during fast scroll
              cacheExtent: isDesktop ? 400 : (isMobile ? 200 : 300),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              addSemanticIndexes: false,
              findChildIndexCallback: (Key key) {
                if (key is! ValueKey<String>) return null;
                final value = key.value;
                if (value.startsWith('folder-grid-')) {
                  final folderPath = value.substring('folder-grid-'.length);
                  final index = folderIndexByPath[folderPath];
                  return index;
                }
                if (value.startsWith('file-grid-')) {
                  final filePath = value.substring('file-grid-'.length);
                  final index = fileIndexByPath[filePath];
                  if (index == null) return null;
                  return folders.length + index;
                }
                return null;
              },
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: _gridSpacing,
                mainAxisSpacing: _gridSpacing,
                mainAxisExtent: itemHeight,
              ),
              padding: const EdgeInsets.all(8.0),
              itemCount: folders.length + files.length,
              itemBuilder: (context, index) {
                // Generate a stable key to help Flutter optimize rendering
                final String itemKey = index < folders.length
                    ? 'folder-grid-${folders[index].path}'
                    : 'file-grid-${files[index - folders.length].path}';

                // Use KeyedSubtree with a stable key to prevent unnecessary rebuilds
                return KeyedSubtree(
                  key: ValueKey(itemKey),
                  child: RepaintBoundary(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: itemWidth,
                        height: itemHeight,
                        child: index < folders.length
                            ? FolderGridItem(
                                key: ValueKey(
                                    'folder-grid-item-${folders[index].path}'),
                                folder: folders[index],
                                onNavigate: onFolderTap ?? (_) {},
                                isSelected:
                                    selectedFiles.contains(folders[index].path),
                                toggleFolderSelection: toggleFileSelection,
                                isDesktopMode: isDesktopMode,
                                lastSelectedPath: lastSelectedPath,
                                clearSelectionMode: clearSelectionMode,
                              )
                            : FileGridItem(
                                key: ValueKey(
                                    'file-grid-item-${files[index - folders.length].path}'),
                                file: files[index - folders.length],
                                state: state,
                                isSelected: selectedFiles.contains(
                                    files[index - folders.length].path),
                                toggleFileSelection: toggleFileSelection,
                                toggleSelectionMode: toggleSelectionMode,
                                isSelectionMode: isSelectionMode,
                                onFileTap: onFileTap,
                                isDesktopMode: isDesktopMode,
                                lastSelectedPath: lastSelectedPath,
                                onThumbnailGenerated: onThumbnailGenerated,
                                showDeleteTagDialog: showDeleteTagDialog,
                                showAddTagToFileDialog: showAddTagToFileDialog,
                                showFileTags: showFileTags,
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// Helper wrapper classes to optimize selection rendering

class _FileDetailsItemWrapper extends StatelessWidget {
  final File file;
  final FolderListState state;
  final bool isSelected;
  final ColumnVisibility columnVisibility;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;
  final Function(BuildContext, String, List<String>) showDeleteTagDialog;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final Function(File, bool)? onTap;
  final bool isDesktopMode;
  final String? lastSelectedPath;
  final bool showFileTags; // Add parameter to control tag display

  const _FileDetailsItemWrapper({
    Key? key,
    required this.file,
    required this.state,
    required this.isSelected,
    required this.columnVisibility,
    required this.toggleFileSelection,
    required this.showDeleteTagDialog,
    required this.showAddTagToFileDialog,
    this.onTap,
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.showFileTags = true, // Default to showing tags
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Return the FileDetailsItem with isSelected already determined
    // This prevents rebuilding when only selection changes
    return FileDetailsItem(
      file: file,
      state: state,
      isSelected: isSelected,
      columnVisibility: columnVisibility,
      toggleFileSelection: toggleFileSelection,
      showDeleteTagDialog: showDeleteTagDialog,
      showAddTagToFileDialog: showAddTagToFileDialog,
      onTap: onTap,
      isDesktopMode: isDesktopMode,
      lastSelectedPath: lastSelectedPath,
      showFileTags: showFileTags,
    );
  }
}

class _FolderDetailsItemWrapper extends StatelessWidget {
  final Directory folder;
  final Function(String)? onTap;
  final bool isSelected;
  final ColumnVisibility columnVisibility;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFolderSelection;
  final bool isDesktopMode;
  final String? lastSelectedPath;
  final Function()? clearSelectionMode;

  const _FolderDetailsItemWrapper({
    Key? key,
    required this.folder,
    required this.isSelected,
    required this.columnVisibility,
    required this.toggleFolderSelection,
    this.onTap,
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.clearSelectionMode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Return the FolderDetailsItem with isSelected already determined
    // This prevents rebuilding when only selection changes
    return FolderDetailsItem(
      folder: folder,
      onTap: onTap,
      isSelected: isSelected,
      columnVisibility: columnVisibility,
      toggleFolderSelection: toggleFolderSelection,
      isDesktopMode: isDesktopMode,
      lastSelectedPath: lastSelectedPath,
      clearSelectionMode: clearSelectionMode,
    );
  }
}
