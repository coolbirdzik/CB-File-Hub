import 'dart:io';
import 'dart:math' as math;

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/utils/scroll_velocity_notifier.dart';
import 'package:cb_file_manager/ui/widgets/ctrl_scroll_zoom.dart';

import 'file_item.dart';
import 'file_grid_item.dart';
import 'folder_item.dart';
import 'folder_grid_item.dart';
import 'file_details_item.dart';
import 'folder_details_item.dart';

class FileView extends StatelessWidget {
  static const double _gridSpacing = 12.0;
  static const double _gridAspectRatio = 1.0;
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
  final Function(String, {bool shiftSelect, bool ctrlSelect})?
      toggleFolderSelection;
  final Function() toggleSelectionMode;
  final Function(BuildContext, String, List<String>) showDeleteTagDialog;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final Future<void> Function(BuildContext, File)? onDeleteFile;
  final Future<void> Function(BuildContext, List<String>)? onDeleteFiles;
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
  final ScrollController? scrollController;
  final GlobalKey Function(String path)? itemKeyForPath;
  final Function(ColumnVisibility)? onColumnVisibilityChanged;

  const FileView({
    Key? key,
    required this.files,
    required this.folders,
    required this.state,
    required this.isSelectionMode,
    required this.isGridView,
    required this.selectedFiles,
    required this.toggleFileSelection,
    this.toggleFolderSelection,
    required this.toggleSelectionMode,
    required this.showDeleteTagDialog,
    required this.showAddTagToFileDialog,
    this.onDeleteFile,
    this.onDeleteFiles,
    this.onFolderTap,
    this.onFileTap,
    this.onThumbnailGenerated,
    this.onZoomChanged, // Thêm parameter
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.columnVisibility = const ColumnVisibility(),
    this.clearSelectionMode, // Add new parameter
    this.showFileTags = true, // Default to showing tags
    this.scrollController,
    this.itemKeyForPath,
    this.onColumnVisibilityChanged,
  }) : super(key: key);

  Function(String, {bool shiftSelect, bool ctrlSelect})
      get _folderSelectionHandler =>
          toggleFolderSelection ?? toggleFileSelection;

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
      controller: scrollController,
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
      // cacheExtent: keep more items alive near viewport to avoid thumbnail re-render
      cacheExtent: isDesktop ? 600 : (isMobile ? 400 : 500),
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      itemCount: folders.length + files.length,
      itemBuilder: (context, index) {
        // Use RepaintBoundary to reduce rendering load during scrolling
        return Container(
          key: itemKeyForPath?.call(index < folders.length
              ? folders[index].path
              : files[index - folders.length].path),
          child: RepaintBoundary(
            child: index < folders.length
                ? FolderItem(
                    key: ValueKey('folder-item-${folders[index].path}'),
                    folder: folders[index],
                    onTap: onFolderTap,
                    isSelected: selectedFiles.contains(folders[index].path),
                    toggleFolderSelection: _folderSelectionHandler,
                    isDesktopMode: actualIsDesktop,
                    lastSelectedPath: lastSelectedPath,
                    clearSelectionMode: clearSelectionMode,
                    showItemBackground: false,
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
                    onDeleteFile: onDeleteFile,
                    onDeleteFiles: onDeleteFiles,
                    onFileTap: onFileTap,
                    isDesktopMode: actualIsDesktop,
                    lastSelectedPath: lastSelectedPath,
                    showFileTags: showFileTags,
                    showItemBackground: false,
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
    final l10n = AppLocalizations.of(context)!;

    // Debug selection count
    debugPrint(
        "FileView _buildDetailsView - Selected files count: ${selectedFiles.length}");

    return Column(
      children: [
        // Column headers for details view with info tooltip
        Stack(
          children: [
            GestureDetector(
              onSecondaryTapUp: (details) {
                _showColumnHeaderContextMenu(
                    context, details.globalPosition, l10n);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Row(
                  children: [
                    // Name column (always visible)
                    Expanded(
                      flex: 3,
                      child: _buildSortableHeaderCell(
                        context: context,
                        label: l10n.columnName,
                        style: headerStyle,
                        ascendingOption: SortOption.nameAsc,
                        descendingOption: SortOption.nameDesc,
                      ),
                    ),

                  // Type column
                  if (columnVisibility.type)
                    Expanded(
                      flex: 2,
                      child: _buildSortableHeaderCell(
                        context: context,
                        label: l10n.columnType,
                        style: headerStyle,
                        ascendingOption: SortOption.typeAsc,
                        descendingOption: SortOption.typeDesc,
                      ),
                    ),

                  // Size column
                  if (columnVisibility.size)
                    Expanded(
                      flex: 1,
                      child: _buildSortableHeaderCell(
                        context: context,
                        label: l10n.columnSize,
                        style: headerStyle,
                        ascendingOption: SortOption.sizeAsc,
                        descendingOption: SortOption.sizeDesc,
                      ),
                    ),

                  // Date modified column
                  if (columnVisibility.dateModified)
                    Expanded(
                      flex: 2,
                      child: _buildSortableHeaderCell(
                        context: context,
                        label: l10n.columnDateModified,
                        style: headerStyle,
                        ascendingOption: SortOption.dateAsc,
                        descendingOption: SortOption.dateDesc,
                      ),
                    ),

                  // Date created column
                  if (columnVisibility.dateCreated)
                    Expanded(
                      flex: 2,
                      child: _buildSortableHeaderCell(
                        context: context,
                        label: l10n.columnDateCreated,
                        style: headerStyle,
                        ascendingOption: SortOption.dateCreatedAsc,
                        descendingOption: SortOption.dateCreatedDesc,
                      ),
                    ),

                  // Attributes column
                  if (columnVisibility.attributes)
                    Expanded(
                      flex: 1,
                      child: _buildSortableHeaderCell(
                        context: context,
                        label: l10n.columnAttributes,
                        style: headerStyle,
                        ascendingOption: SortOption.attributesAsc,
                        descendingOption: SortOption.attributesDesc,
                      ),
                    ),

                  // Date Accessed column
                  if (columnVisibility.dateAccessed)
                    Expanded(
                      flex: 2,
                      child: _buildHeaderCell(
                        context: context,
                        label: l10n.columnDateAccessed,
                        style: headerStyle,
                      ),
                    ),

                  // Extension column
                  if (columnVisibility.extension)
                    Expanded(
                      flex: 1,
                      child: _buildSortableHeaderCell(
                        context: context,
                        label: l10n.columnExtension,
                        style: headerStyle,
                        ascendingOption: SortOption.extensionAsc,
                        descendingOption: SortOption.extensionDesc,
                      ),
                    ),

                  // Path column
                  if (columnVisibility.path)
                    Expanded(
                      flex: 3,
                      child: _buildHeaderCell(
                        context: context,
                        label: l10n.columnPath,
                        style: headerStyle,
                      ),
                    ),

                  // Tags column
                  if (columnVisibility.tags)
                    Expanded(
                      flex: 2,
                      child: _buildHeaderCell(
                        context: context,
                        label: l10n.columnTags,
                        style: headerStyle,
                      ),
                    ),

                  // Dimensions column
                  if (columnVisibility.dimensions)
                    Expanded(
                      flex: 1,
                      child: _buildHeaderCell(
                        context: context,
                        label: l10n.columnDimensions,
                        style: headerStyle,
                      ),
                    ),

                  // Duration column
                  if (columnVisibility.duration)
                    Expanded(
                      flex: 1,
                      child: _buildHeaderCell(
                        context: context,
                        label: l10n.columnDuration,
                        style: headerStyle,
                      ),
                    ),

                  // Item Count column
                  if (columnVisibility.itemCount)
                    Expanded(
                      flex: 1,
                      child: _buildHeaderCell(
                        context: context,
                        label: l10n.columnItemCount,
                        style: headerStyle,
                      ),
                    ),
                ],
              ),
            ),
            ),

            // Add info button with tooltip about customizing columns
            Positioned(
              right: 8,
              top: 8,
              child: Tooltip(
                message: l10n.columnVisibilityInstructions,
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
            controller: scrollController,
            physics: isDesktop
                ? const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  )
                : isMobile
                    ? const ClampingScrollPhysics()
                    : const ClampingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
            // cacheExtent: keep more items alive near viewport to avoid thumbnail re-render
            cacheExtent: isDesktop ? 600 : (isMobile ? 400 : 500),
            addAutomaticKeepAlives: true,
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

              return Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 2.0, horizontal: 12.0),
                decoration: BoxDecoration(
                  color: rowColor,
                ),
                // Use KeyedSubtree with a stable key to prevent unnecessary rebuilds
                child: Container(
                  key: itemKeyForPath?.call(index < folders.length
                      ? folders[index].path
                      : files[index - folders.length].path),
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
                            toggleFolderSelection: _folderSelectionHandler,
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
                            onDeleteFile: onDeleteFile,
                            onDeleteFiles: onDeleteFiles,
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

  Widget _buildSortableHeaderCell({
    required BuildContext context,
    required String label,
    required TextStyle style,
    required SortOption ascendingOption,
    required SortOption descendingOption,
  }) {
    final currentSort = state.sortOption;
    final bool isAscending = currentSort == ascendingOption;
    final bool isDescending = currentSort == descendingOption;
    final bool isActive = isAscending || isDescending;
    final Color iconColor = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: () {
        final nextSort = isAscending ? descendingOption : ascendingOption;
        context.read<FolderListBloc>().add(SetSortOption(
              nextSort,
              folderPath: state.currentPath.path,
            ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
        child: Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              isDescending
                  ? PhosphorIconsLight.arrowDown
                  : PhosphorIconsLight.arrowUp,
              size: 16,
              color: iconColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell({
    required BuildContext context,
    required String label,
    required TextStyle style,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
      child: Text(
        label,
        style: style,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void _showColumnHeaderContextMenu(
    BuildContext context,
    Offset position,
    dynamic l10n,
  ) {
    if (onColumnVisibilityChanged == null) return;

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        _buildColumnToggleItem(l10n.columnSize, 'size', columnVisibility.size),
        _buildColumnToggleItem(l10n.columnType, 'type', columnVisibility.type),
        _buildColumnToggleItem(
            l10n.columnDateModified, 'dateModified', columnVisibility.dateModified),
        _buildColumnToggleItem(
            l10n.columnDateCreated, 'dateCreated', columnVisibility.dateCreated),
        _buildColumnToggleItem(
            l10n.columnAttributes, 'attributes', columnVisibility.attributes),
        _buildColumnToggleItem(
            l10n.columnDateAccessed, 'dateAccessed', columnVisibility.dateAccessed),
        _buildColumnToggleItem(
            l10n.columnExtension, 'extension', columnVisibility.extension),
        _buildColumnToggleItem(l10n.columnPath, 'path', columnVisibility.path),
        _buildColumnToggleItem(l10n.columnTags, 'tags', columnVisibility.tags),
        _buildColumnToggleItem(
            l10n.columnDimensions, 'dimensions', columnVisibility.dimensions),
        _buildColumnToggleItem(
            l10n.columnDuration, 'duration', columnVisibility.duration),
        _buildColumnToggleItem(
            l10n.columnItemCount, 'itemCount', columnVisibility.itemCount),
      ],
    ).then((value) {
      if (value == null || onColumnVisibilityChanged == null) return;
      final newVisibility = _toggleColumn(value);
      onColumnVisibilityChanged!(newVisibility);
    });
  }

  PopupMenuItem<String> _buildColumnToggleItem(
      String label, String key, bool isVisible) {
    return PopupMenuItem<String>(
      value: key,
      child: Row(
        children: [
          Icon(
            isVisible ? PhosphorIconsLight.checkSquare : PhosphorIconsLight.square,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  ColumnVisibility _toggleColumn(String key) {
    switch (key) {
      case 'size':
        return columnVisibility.copyWith(size: !columnVisibility.size);
      case 'type':
        return columnVisibility.copyWith(type: !columnVisibility.type);
      case 'dateModified':
        return columnVisibility.copyWith(
            dateModified: !columnVisibility.dateModified);
      case 'dateCreated':
        return columnVisibility.copyWith(
            dateCreated: !columnVisibility.dateCreated);
      case 'attributes':
        return columnVisibility.copyWith(
            attributes: !columnVisibility.attributes);
      case 'dateAccessed':
        return columnVisibility.copyWith(
            dateAccessed: !columnVisibility.dateAccessed);
      case 'extension':
        return columnVisibility.copyWith(
            extension: !columnVisibility.extension);
      case 'path':
        return columnVisibility.copyWith(path: !columnVisibility.path);
      case 'tags':
        return columnVisibility.copyWith(tags: !columnVisibility.tags);
      case 'dimensions':
        return columnVisibility.copyWith(
            dimensions: !columnVisibility.dimensions);
      case 'duration':
        return columnVisibility.copyWith(duration: !columnVisibility.duration);
      case 'itemCount':
        return columnVisibility.copyWith(
            itemCount: !columnVisibility.itemCount);
      default:
        return columnVisibility;
    }
  }

  Widget _buildGridView() {
    // Optimize scrolling with frame timing
    FrameTimingOptimizer().optimizeScrolling();
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final bool isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    // Ctrl+scroll → zoom: delegate to the canonical CtrlScrollZoom widget.
    return CtrlScrollZoom(
      onDelta: onZoomChanged,
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
              cacheExtent: isDesktop ? 600 : (isMobile ? 400 : 500),
              addAutomaticKeepAlives: true,
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
                                toggleFolderSelection: _folderSelectionHandler,
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
                                onDeleteFile: onDeleteFile,
                                onDeleteFiles: onDeleteFiles,
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
  final Future<void> Function(BuildContext, File)? onDeleteFile;
  final Future<void> Function(BuildContext, List<String>)? onDeleteFiles;
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
    this.onDeleteFile,
    this.onDeleteFiles,
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
      onDeleteFile: onDeleteFile,
      onDeleteFiles: onDeleteFiles,
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
