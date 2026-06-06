import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/helpers/files/file_icon_helper.dart';
import 'package:cb_file_manager/ui/components/common/shared_file_context_menu.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/utils/item_interaction_style.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';

/// Data for a single column in the Miller columns view.
class _MillerColumnData {
  final String path;
  final List<FileSystemEntity> folders;
  final List<FileSystemEntity> files;
  final String? selectedPath;
  final bool isLoading;
  final Object? loadError;

  _MillerColumnData({
    required this.path,
    required this.folders,
    required this.files,
    this.selectedPath,
    this.isLoading = false,
    this.loadError,
  });

  _MillerColumnData copyWith({
    List<FileSystemEntity>? folders,
    List<FileSystemEntity>? files,
    String? selectedPath,
    bool clearSelectedPath = false,
    bool? isLoading,
    Object? loadError,
    bool clearLoadError = false,
  }) {
    return _MillerColumnData(
      path: path,
      folders: folders ?? this.folders,
      files: files ?? this.files,
      selectedPath:
          clearSelectedPath ? null : (selectedPath ?? this.selectedPath),
      isLoading: isLoading ?? this.isLoading,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
    );
  }
}

/// Miller columns view (macOS Finder-style) for browsing folders.
///
/// Each column displays the contents of a folder. Clicking a subfolder
/// opens its contents in the next column to the right.
/// Double-clicking a folder navigates the tab to that folder.
class MillerColumnsView extends StatefulWidget {
  final FolderListState state;
  final SelectionState selectionState;
  final bool isDesktopPlatform;
  final Function(String) onNavigateToPath;
  final Function(File, bool) onFileTap;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFolderSelection;
  final VoidCallback clearSelection;
  final TabbedFolderDragSelectionController dragSelectionController;
  final bool showFileTags;
  final Function(BuildContext, String, List<String>) showDeleteTagDialog;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final Future<void> Function(BuildContext, File)? onDeleteFile;
  final Future<void> Function(BuildContext, List<String>)? onDeleteFiles;
  final VoidCallback toggleSelectionMode;
  final Function(BuildContext, Offset) showContextMenu;
  final ScrollController? scrollController;
  final GlobalKey Function(String path)? itemKeyForPath;

  static const double columnWidth = 280.0;
  static const double dividerWidth = 1.0;

  const MillerColumnsView({
    Key? key,
    required this.state,
    required this.selectionState,
    required this.isDesktopPlatform,
    required this.onNavigateToPath,
    required this.onFileTap,
    required this.toggleFileSelection,
    required this.toggleFolderSelection,
    required this.clearSelection,
    required this.dragSelectionController,
    required this.showFileTags,
    required this.showDeleteTagDialog,
    required this.showAddTagToFileDialog,
    this.onDeleteFile,
    this.onDeleteFiles,
    required this.toggleSelectionMode,
    required this.showContextMenu,
    this.scrollController,
    this.itemKeyForPath,
  }) : super(key: key);

  @override
  State<MillerColumnsView> createState() => _MillerColumnsViewState();
}

class _MillerColumnsViewState extends State<MillerColumnsView> {
  final ScrollController _horizontalScrollController = ScrollController();
  List<_MillerColumnData> _columns = [];

  @override
  void initState() {
    super.initState();
    _initializeColumns();
  }

  @override
  void didUpdateWidget(MillerColumnsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the tab's current path changed (breadcrumb, address bar, back/forward),
    // reset columns to show only the new path.
    if (oldWidget.state.currentPath.path != widget.state.currentPath.path) {
      _initializeColumns();
    } else if (oldWidget.state.folders != widget.state.folders ||
        oldWidget.state.files != widget.state.files) {
      // Contents of root column changed (refresh, new files, etc.)
      _updateRootColumn();
    }
  }

  void _initializeColumns() {
    _columns = [
      _MillerColumnData(
        path: widget.state.currentPath.path,
        folders: widget.state.folders,
        files: widget.state.files,
      ),
    ];
  }

  void _updateRootColumn() {
    if (_columns.isNotEmpty) {
      setState(() {
        _columns[0] = _MillerColumnData(
          path: widget.state.currentPath.path,
          folders: widget.state.folders,
          files: widget.state.files,
          selectedPath: _columns[0].selectedPath,
        );
      });
    }
  }

  Future<void> _onFolderTap(int columnIndex, String folderPath) async {
    // Single click: open folder contents in next column.
    // Show a loading placeholder column immediately so the user gets
    // feedback instead of an empty-looking pane while we list the directory.
    setState(() {
      _columns[columnIndex] = _columns[columnIndex].copyWith(
        selectedPath: folderPath,
      );
      // Keep columns up to and including the parent, then append a
      // placeholder column for the new selection.
      _columns = _columns.sublist(0, columnIndex + 1);
      _columns.add(_MillerColumnData(
        path: folderPath,
        folders: const [],
        files: const [],
        isLoading: true,
      ));
    });

    // Auto-scroll to reveal the new (loading) column right away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontalScrollController.hasClients) {
        _horizontalScrollController.animateTo(
          _horizontalScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });

    // Load the folder contents.
    try {
      final dir = Directory(folderPath);
      final entities = await dir.list().toList();
      final folders = entities.whereType<Directory>().toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      final files = entities.whereType<File>().toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

      if (!mounted) return;
      // Verify the placeholder is still the column we want to update
      // (user may have clicked another folder in the meantime).
      final int targetIndex = columnIndex + 1;
      if (targetIndex >= _columns.length ||
          _columns[targetIndex].path != folderPath) {
        return;
      }
      setState(() {
        _columns[targetIndex] = _columns[targetIndex].copyWith(
          folders: folders,
          files: files,
          isLoading: false,
          clearLoadError: true,
        );
      });
    } catch (e) {
      debugPrint('Error loading folder in Miller columns: $e');
      if (!mounted) return;
      final int targetIndex = columnIndex + 1;
      if (targetIndex >= _columns.length ||
          _columns[targetIndex].path != folderPath) {
        return;
      }
      setState(() {
        _columns[targetIndex] = _columns[targetIndex].copyWith(
          isLoading: false,
          loadError: e,
        );
      });
    }
  }

  void _onFolderDoubleTap(String folderPath) {
    // Double-click: navigate the tab to this folder
    widget.onNavigateToPath(folderPath);
  }

  /// Single-click on a file in [columnIndex]:
  ///  - clear the column's selectedPath (file selected, no folder is "open")
  ///  - remove all columns to the right
  ///
  /// Selection itself is handled by the row via [toggleFileSelection].
  /// This only adjusts column state — it does NOT open the file.
  /// Opening happens on double-click (see [_onFileDoubleTap]), matching
  /// Finder behavior.
  void _onFileTap(int columnIndex, File file) {
    setState(() {
      _columns[columnIndex] = _columns[columnIndex].copyWith(
        clearSelectedPath: true,
      );
      if (columnIndex + 1 < _columns.length) {
        _columns = _columns.sublist(0, columnIndex + 1);
      }
    });
  }

  void _onFileDoubleTap(File file) {
    final bool isVideo = FileTypeUtils.isVideoFile(file.path);
    widget.onFileTap(file, isVideo);
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: widget.dragSelectionController.stackKey,
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onSecondaryTapUp: (details) {
            widget.showContextMenu(context, details.globalPosition);
          },
          behavior: HitTestBehavior.translucent,
          child: Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < _columns.length; i++) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: MillerColumnsView.dividerWidth,
                        thickness: 1,
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.3),
                      ),
                    _buildColumn(context, i),
                  ],
                ],
              ),
            ),
          ),
        ),
        widget.dragSelectionController.buildOverlay(),
      ],
    );
  }

  Widget _buildColumn(BuildContext context, int columnIndex) {
    final column = _columns[columnIndex];

    // Loading: show skeleton rows while we list the directory.
    if (column.isLoading) {
      return const SizedBox(
        width: MillerColumnsView.columnWidth,
        child: _MillerLoadingSkeleton(),
      );
    }

    // Error: surface a friendly message rather than an empty pane.
    if (column.loadError != null) {
      return SizedBox(
        width: MillerColumnsView.columnWidth,
        child: _MillerErrorView(error: column.loadError!),
      );
    }

    final itemCount = column.folders.length + column.files.length;

    return SizedBox(
      width: MillerColumnsView.columnWidth,
      child: itemCount == 0
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Empty folder',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.5),
                      ),
                ),
              ),
            )
          : BlocBuilder<SelectionBloc, SelectionState>(
              builder: (context, selectionState) {
                return ListView.builder(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 100.0),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    if (index < column.folders.length) {
                      return _buildFolderItem(
                        context,
                        columnIndex,
                        column.folders[index] as Directory,
                        selectionState,
                      );
                    } else {
                      return _buildFileItem(
                        context,
                        columnIndex,
                        column.files[index - column.folders.length] as File,
                        selectionState,
                      );
                    }
                  },
                );
              },
            ),
    );
  }

  Widget _buildFolderItem(
    BuildContext context,
    int columnIndex,
    Directory folder,
    SelectionState selectionState,
  ) {
    final isSelected = selectionState.isPathSelected(folder.path);
    final isColumnSelected = _columns[columnIndex].selectedPath == folder.path;

    return _MillerFolderRow(
      key: ValueKey('miller-folder-${folder.path}'),
      folder: folder,
      isSelected: isSelected,
      isColumnSelected: isColumnSelected,
      lastSelectedPath: selectionState.lastSelectedPath,
      onOpenColumn: () => _onFolderTap(columnIndex, folder.path),
      onNavigate: () => _onFolderDoubleTap(folder.path),
      toggleFolderSelection: widget.toggleFolderSelection,
    );
  }

  Widget _buildFileItem(
    BuildContext context,
    int columnIndex,
    File file,
    SelectionState selectionState,
  ) {
    final isSelected = selectionState.isPathSelected(file.path);

    return _MillerFileRow(
      key: ValueKey('miller-file-${file.path}'),
      file: file,
      isSelected: isSelected,
      lastSelectedPath: selectionState.lastSelectedPath,
      showAddTagToFileDialog: widget.showAddTagToFileDialog,
      onDeleteFile: widget.onDeleteFile,
      onTapFile: () => _onFileTap(columnIndex, file),
      onOpenFile: () => _onFileDoubleTap(file),
      toggleFileSelection: widget.toggleFileSelection,
    );
  }
}

/// Compact folder row for Miller columns view.
///
/// Click behavior (Finder-style):
///  - single click → opens the folder in the next column (no Ctrl/Shift)
///  - Ctrl/Shift+click → toggles multi-selection (no column open)
///  - double-click → navigates the tab into the folder
///  - right-click → folder context menu
class _MillerFolderRow extends StatefulWidget {
  final Directory folder;
  final bool isSelected;
  final bool isColumnSelected;
  final String? lastSelectedPath;
  final VoidCallback onOpenColumn;
  final VoidCallback onNavigate;
  final Function(String, {bool shiftSelect, bool ctrlSelect})?
      toggleFolderSelection;

  const _MillerFolderRow({
    Key? key,
    required this.folder,
    required this.isSelected,
    required this.isColumnSelected,
    required this.lastSelectedPath,
    required this.onOpenColumn,
    required this.onNavigate,
    required this.toggleFolderSelection,
  }) : super(key: key);

  @override
  State<_MillerFolderRow> createState() => _MillerFolderRowState();
}

class _MillerFolderRowState extends State<_MillerFolderRow> {
  final ValueNotifier<bool> _isHovering = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isHovering.dispose();
    super.dispose();
  }

  void _handleSingleTap() {
    final keyboard = HardwareKeyboard.instance;
    final bool isShiftPressed = keyboard.isShiftPressed;
    final bool isCtrlPressed =
        keyboard.isControlPressed || keyboard.isMetaPressed;

    if (isShiftPressed || isCtrlPressed) {
      // Modifier key: toggle multi-selection only, do not open column.
      widget.toggleFolderSelection?.call(
        widget.folder.path,
        shiftSelect: isShiftPressed,
        ctrlSelect: isCtrlPressed,
      );
      return;
    }

    // Plain click: open this folder in the next column.
    widget.onOpenColumn();
  }

  void _showContextMenu(Offset globalPosition) {
    showFolderContextMenu(
      context: context,
      folder: widget.folder,
      onNavigate: (_) => widget.onNavigate(),
      folderTags: const [],
      globalPosition: globalPosition,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final renameController = InlineRenameScope.maybeOf(context);
    final bool isBeingRenamed = renameController != null &&
        renameController.renamingPath == widget.folder.path;
    final bool isBeingCut = ItemInteractionStyle.isBeingCut(widget.folder.path);
    final String name = widget.folder.path.split(Platform.pathSeparator).last;

    return ValueListenableBuilder<bool>(
      valueListenable: _isHovering,
      builder: (context, isHovering, _) {
        Color background = ItemInteractionStyle.backgroundColor(
          theme: theme,
          isDesktopMode: true,
          isSelected: widget.isSelected,
          isHovering: isHovering,
        );
        if (widget.isColumnSelected && !widget.isSelected) {
          // Folder is the currently expanded column: subtle accent background.
          background = theme.colorScheme.primary.withValues(alpha: 0.18);
        }

        return Opacity(
          opacity: isBeingCut ? ItemInteractionStyle.cutOpacity : 1.0,
          child: MouseRegion(
            onEnter: (_) => _isHovering.value = true,
            onExit: (_) => _isHovering.value = false,
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleSingleTap,
              onDoubleTap: widget.onNavigate,
              onSecondaryTapUp: (details) =>
                  _showContextMenu(details.globalPosition),
              child: Container(
                color: background,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10.0,
                  vertical: 6.0,
                ),
                child: Row(
                  children: [
                    Icon(
                      PhosphorIconsLight.folder,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: isBeingRenamed &&
                              renameController.textController != null
                          ? InlineRenameField(
                              controller: renameController,
                              onCommit: () =>
                                  renameController.commitRename(context),
                              onCancel: () => renameController.cancelRename(),
                              textStyle: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.start,
                              maxLines: 1,
                            )
                          : Text(
                              name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: widget.isColumnSelected
                                    ? theme.colorScheme.primary
                                    : null,
                                fontWeight: widget.isColumnSelected
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      PhosphorIconsLight.caretRight,
                      size: 14,
                      color: widget.isColumnSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compact file row for Miller columns view.
///
/// Click behavior (Finder-style):
///  - single click → preview file + collapse columns to the right
///  - Ctrl/Shift+click → toggle multi-selection
///  - double-click → open file
///  - right-click → file context menu
class _MillerFileRow extends StatefulWidget {
  final File file;
  final bool isSelected;
  final String? lastSelectedPath;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final Future<void> Function(BuildContext, File)? onDeleteFile;
  final VoidCallback onTapFile;
  final VoidCallback onOpenFile;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;

  const _MillerFileRow({
    Key? key,
    required this.file,
    required this.isSelected,
    required this.lastSelectedPath,
    required this.showAddTagToFileDialog,
    required this.onDeleteFile,
    required this.onTapFile,
    required this.onOpenFile,
    required this.toggleFileSelection,
  }) : super(key: key);

  @override
  State<_MillerFileRow> createState() => _MillerFileRowState();
}

class _MillerFileRowState extends State<_MillerFileRow> {
  final ValueNotifier<bool> _isHovering = ValueNotifier<bool>(false);
  late Future<Widget> _iconFuture;

  @override
  void initState() {
    super.initState();
    _iconFuture = FileIconHelper.getIconForFile(widget.file, size: 20);
  }

  @override
  void didUpdateWidget(_MillerFileRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file.path != oldWidget.file.path) {
      _iconFuture = FileIconHelper.getIconForFile(widget.file, size: 20);
    }
  }

  @override
  void dispose() {
    _isHovering.dispose();
    super.dispose();
  }

  void _handleSingleTap() {
    final keyboard = HardwareKeyboard.instance;
    final bool isShiftPressed = keyboard.isShiftPressed;
    final bool isCtrlPressed =
        keyboard.isControlPressed || keyboard.isMetaPressed;

    if (isShiftPressed || isCtrlPressed) {
      widget.toggleFileSelection(
        widget.file.path,
        shiftSelect: isShiftPressed,
        ctrlSelect: isCtrlPressed,
      );
      return;
    }

    // Plain click: select-only-this and trigger preview.
    widget.toggleFileSelection(
      widget.file.path,
      shiftSelect: false,
      ctrlSelect: false,
    );
    widget.onTapFile();
  }

  void _showContextMenu(Offset globalPosition) {
    final bool isVideo = FileTypeUtils.isVideoFile(widget.file.path);
    final bool isImage = FileTypeUtils.isImageFile(widget.file.path);
    showFileContextMenu(
      context: context,
      file: widget.file,
      fileTags: const [],
      isVideo: isVideo,
      isImage: isImage,
      showAddTagToFileDialog: widget.showAddTagToFileDialog,
      onDeleteFile: widget.onDeleteFile,
      globalPosition: globalPosition,
    );
  }

  Widget _buildLeadingIcon(ThemeData theme) {
    final bool isVideo = FileTypeUtils.isVideoFile(widget.file.path);
    final bool isImage = FileTypeUtils.isImageFile(widget.file.path);
    if (isVideo || isImage) {
      return SizedBox(
        width: 20,
        height: 20,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ThumbnailLoader(
            filePath: widget.file.path,
            isVideo: isVideo,
            isImage: isImage,
            width: 20,
            height: 20,
            borderRadius: BorderRadius.circular(4),
            fallbackBuilder: () => Icon(
              isVideo
                  ? PhosphorIconsLight.videoCamera
                  : PhosphorIconsLight.image,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 20,
      height: 20,
      child: FutureBuilder<Widget>(
        future: _iconFuture,
        builder: (context, snapshot) {
          if (snapshot.hasData) return snapshot.data!;
          return Icon(
            PhosphorIconsLight.file,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final renameController = InlineRenameScope.maybeOf(context);
    final bool isBeingRenamed = renameController != null &&
        renameController.renamingPath == widget.file.path;
    final bool isBeingCut = ItemInteractionStyle.isBeingCut(widget.file.path);
    final String name = widget.file.path.split(Platform.pathSeparator).last;

    return ValueListenableBuilder<bool>(
      valueListenable: _isHovering,
      builder: (context, isHovering, _) {
        final Color background = ItemInteractionStyle.backgroundColor(
          theme: theme,
          isDesktopMode: true,
          isSelected: widget.isSelected,
          isHovering: isHovering,
        );

        return Opacity(
          opacity: isBeingCut ? ItemInteractionStyle.cutOpacity : 1.0,
          child: MouseRegion(
            onEnter: (_) => _isHovering.value = true,
            onExit: (_) => _isHovering.value = false,
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleSingleTap,
              onDoubleTap: widget.onOpenFile,
              onSecondaryTapUp: (details) =>
                  _showContextMenu(details.globalPosition),
              child: Container(
                color: background,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10.0,
                  vertical: 6.0,
                ),
                child: Row(
                  children: [
                    _buildLeadingIcon(theme),
                    const SizedBox(width: 10),
                    Expanded(
                      child: isBeingRenamed &&
                              renameController.textController != null
                          ? InlineRenameField(
                              controller: renameController,
                              onCommit: () =>
                                  renameController.commitRename(context),
                              onCancel: () => renameController.cancelRename(),
                              textStyle: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.start,
                              maxLines: 1,
                            )
                          : Text(
                              name,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Loading skeleton shown while a Miller column is fetching directory contents.
///
/// Renders a top progress bar plus shimmering placeholder rows so the column
/// never looks like an "Empty folder" while the listing is in flight.
class _MillerLoadingSkeleton extends StatelessWidget {
  const _MillerLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color baseColor = theme.colorScheme.onSurface.withValues(alpha: 0.06);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            backgroundColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            itemCount: 12,
            itemBuilder: (context, index) {
              // Vary the name-block width so the placeholder feels organic.
              final double nameWidth = 80.0 + ((index * 23) % 100);
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10.0,
                  vertical: 6.0,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: nameWidth,
                      height: 12,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Error placeholder shown when listing a folder fails (permission denied, etc.).
class _MillerErrorView extends StatelessWidget {
  final Object error;

  const _MillerErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsLight.warning,
              size: 28,
              color: theme.colorScheme.error.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 8),
            Text(
              'Cannot read folder',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              error.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
