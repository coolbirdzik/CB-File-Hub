import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';

import '../../../../bloc/selection/selection_bloc.dart';
import '../../../../bloc/selection/selection_event.dart';
import '../../../components/common/optimized_interaction_handler.dart';
import '../../../components/common/shared_file_context_menu.dart';
import '../../../utils/item_interaction_style.dart';
import 'thumbnail_only.dart';

class FileGridItem extends StatefulWidget {
  final FileSystemEntity file;
  final bool isSelected;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;
  final Function() toggleSelectionMode;
  final Function(File, bool)? onFileTap;
  final FolderListState? state;
  final bool isSelectionMode;
  final bool isDesktopMode;
  final String? lastSelectedPath;
  final Function()? onThumbnailGenerated;
  final Function(BuildContext, String, List<String>)? showDeleteTagDialog;
  final Function(BuildContext, String)? showAddTagToFileDialog;
  final bool showFileTags;

  const FileGridItem({
    Key? key,
    required this.file,
    required this.isSelected,
    required this.toggleFileSelection,
    required this.toggleSelectionMode,
    this.onFileTap,
    this.state,
    this.isSelectionMode = false,
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.onThumbnailGenerated,
    this.showDeleteTagDialog,
    this.showAddTagToFileDialog,
    this.showFileTags = true,
  }) : super(key: key);

  @override
  State<FileGridItem> createState() => _FileGridItemState();
}

class _FileGridItemState extends State<FileGridItem> {
  bool _isHovering = false;
  late List<String> _fileTags;
  StreamSubscription? _tagChangeSubscription;

  void _showContextMenu(BuildContext context, Offset globalPosition) {
    try {
      try {
        final selectionBloc = context.read<SelectionBloc>();
        final selectionState = selectionBloc.state;

        if (selectionState.allSelectedPaths.length > 1 &&
            selectionState.allSelectedPaths.contains(widget.file.path)) {
          showMultipleFilesContextMenu(
            context: context,
            selectedPaths: selectionState.allSelectedPaths,
            globalPosition: globalPosition,
            onClearSelection: () {
              selectionBloc.add(ClearSelection());
            },
          );
          return;
        }
      } catch (e) {
        debugPrint('Error checking selection state: $e');
      }

      final bool isVideo = FileTypeUtils.isVideoFile(widget.file.path);
      final bool isImage = FileTypeUtils.isImageFile(widget.file.path);
      final List<String> fileTags =
          widget.state?.getTagsForFile(widget.file.path) ?? [];

      showFileContextMenu(
        context: context,
        file: widget.file as File,
        fileTags: fileTags,
        isVideo: isVideo,
        isImage: isImage,
        showAddTagToFileDialog: widget.showAddTagToFileDialog,
        globalPosition: globalPosition,
      );
    } catch (e) {
      debugPrint('Error showing context menu: $e');
      try {
        showFileContextMenu(
          context: context,
          file: widget.file as File,
          fileTags: const [],
          isVideo: false,
          isImage: false,
          showAddTagToFileDialog: widget.showAddTagToFileDialog,
          globalPosition: globalPosition,
        );
      } catch (e2) {
        debugPrint('Critical error showing fallback context menu: $e2');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Initialize from state if available; will be refreshed from TagManager on first event
    final shouldUseTags = widget.showFileTags && widget.state != null;
    _fileTags = shouldUseTags
        ? (widget.state?.getTagsForFile(widget.file.path) ?? [])
        : const [];
    // Only subscribe/load when tags can actually be displayed. Album grids pass
    // no FolderListState, so paying per-item DB work/subscriptions is wasted.
    if (shouldUseTags) {
      _tagChangeSubscription = TagManager.onTagChanged.listen(_onTagChanged);
      _loadTagsFromTagManager();
    }
  }

  @override
  void dispose() {
    _tagChangeSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(FileGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync from state when bloc emits a new state (e.g. after reload)
    if (widget.state != oldWidget.state) {
      final newTags = widget.state?.getTagsForFile(widget.file.path) ?? [];
      if (!_areTagListsEqual(newTags, _fileTags) && newTags.isNotEmpty) {
        // State has fresh data; prefer it if it actually has tags
        if (mounted) setState(() => _fileTags = newTags);
      }
    }
  }

  void _onTagChanged(String changedFilePath) {
    // Handle global notifications
    if (changedFilePath == 'global:tag_updated' ||
        changedFilePath == 'global:tag_deleted') {
      _loadTagsFromTagManager();
      return;
    }

    // Extract actual path from prefixed events
    String actualPath = changedFilePath;
    if (changedFilePath.startsWith('preserve_scroll:')) {
      actualPath = changedFilePath.substring('preserve_scroll:'.length);
    } else if (changedFilePath.startsWith('tag_only:')) {
      actualPath = changedFilePath.substring('tag_only:'.length);
    }

    if (actualPath == widget.file.path) {
      _loadTagsFromTagManager();
    }
  }

  /// Load tags directly from TagManager (source of truth) — avoids reading
  /// from widget.state which may still be stale when the tag event fires.
  Future<void> _loadTagsFromTagManager() async {
    if (!mounted) return;
    final newTags = await TagManager.getTags(widget.file.path);
    if (mounted && !_areTagListsEqual(newTags, _fileTags)) {
      setState(() => _fileTags = newTags);
    }
  }

  bool _areTagListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    final s1 = List<String>.from(list1)..sort();
    final s2 = List<String>.from(list2)..sort();
    for (int i = 0; i < s1.length; i++) {
      if (s1[i] != s2[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String fileName = path.basename(widget.file.path);
    final bool isBeingCut = ItemInteractionStyle.isBeingCut(widget.file.path);

    // Check if this item is being renamed inline (desktop only)
    final renameController = InlineRenameScope.maybeOf(context);
    final isBeingRenamed = renameController != null &&
        renameController.renamingPath == widget.file.path;

    // Don't show selected background when renaming to avoid color conflict
    // with text selection color
    final bool showAsSelected = widget.isSelected && !isBeingRenamed;

    final Color overlayColor = ItemInteractionStyle.thumbnailOverlayColor(
      theme: theme,
      isDesktopMode: widget.isDesktopMode,
      isSelected: showAsSelected,
      isHovering: _isHovering,
    );

    // Windows Explorer style: transparent background, icon + name layout
    final double nameAreaHeight = (widget.showFileTags && widget.state != null)
        ? GridZoomConstraints.gridItemNameAreaHeightWithTags
        : GridZoomConstraints.gridItemNameAreaHeight;

    return RepaintBoundary(
      child: Opacity(
        opacity: isBeingCut ? ItemInteractionStyle.cutOpacity : 1.0,
        child: MouseRegion(
          onEnter: (_) {
            if (!widget.isDesktopMode) return;
            if (_isHovering) return;
            setState(() => _isHovering = true);
          },
          onExit: (_) {
            if (!widget.isDesktopMode) return;
            if (!_isHovering) return;
            setState(() => _isHovering = false);
          },
          cursor: SystemMouseCursors.click,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              // Icon/thumbnail area - takes all remaining space after fixed name area
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Icon rendered at large size (fills available space)
                      ThumbnailOnly(
                        key: ValueKey('thumb-only-${widget.file.path}'),
                        file: widget.file,
                        iconSize: 48.0,
                      ),
                      // Selection/hover overlay (transparent background, colored overlay)
                      if (overlayColor != Colors.transparent)
                        IgnorePointer(
                          child: Container(color: overlayColor),
                        ),
                      // Interaction layer
                      Positioned.fill(
                        child: OptimizedInteractionLayer(
                          onTap: () {
                            final keyboard = HardwareKeyboard.instance;
                            final bool isShiftPressed = keyboard.isShiftPressed;
                            final bool isCtrlPressed =
                                keyboard.isControlPressed ||
                                    keyboard.isMetaPressed;
                            final bool isVideo =
                                FileTypeUtils.isVideoFile(widget.file.path);

                            if (widget.isDesktopMode) {
                              widget.toggleFileSelection(
                                widget.file.path,
                                shiftSelect: isShiftPressed,
                                ctrlSelect: isCtrlPressed,
                              );
                              return;
                            }

                            if (widget.isSelectionMode) {
                              widget.toggleFileSelection(
                                widget.file.path,
                                shiftSelect: isShiftPressed,
                                ctrlSelect: isCtrlPressed,
                              );
                              return;
                            }

                            widget.onFileTap
                                ?.call(widget.file as File, isVideo);
                          },
                          onDoubleTap: () {
                            if (widget.isDesktopMode) {
                              widget.toggleFileSelection(
                                widget.file.path,
                                shiftSelect: false,
                                ctrlSelect: false,
                              );
                            }
                            widget.onFileTap?.call(
                              widget.file as File,
                              FileTypeUtils.isVideoFile(widget.file.path),
                            );
                          },
                          onSecondaryTapUp: (details) {
                            _showContextMenu(context, details.globalPosition);
                          },
                          onLongPress: widget.isDesktopMode
                              ? () {
                                  HapticFeedback.mediumImpact();
                                  widget.toggleFileSelection(widget.file.path);
                                  if (!widget.isSelectionMode) {
                                    widget.toggleSelectionMode();
                                  }
                                }
                              : null,
                          onLongPressStart: !widget.isDesktopMode
                              ? (d) {
                                  HapticFeedback.mediumImpact();
                                  _showContextMenu(context, d.globalPosition);
                                }
                              : null,
                        ),
                      ),
                      // Mobile: show checkmark when selected
                      if (showAsSelected && !widget.isDesktopMode)
                        IgnorePointer(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                PhosphorIconsLight.checkCircle,
                                color: theme.colorScheme.primary,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Filename (and optional tags) below icon - fixed height so thumbnail is always the same size
              SizedBox(
                height: nameAreaHeight,
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 4.0, left: 4.0, right: 4.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildNameWidget(
                        context,
                        theme,
                        fileName,
                        isBeingRenamed,
                        renameController,
                      ),
                      if (widget.showFileTags && widget.state != null) ...[
                        const SizedBox(height: 2),
                        _buildTagsDisplay(context),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNameWidget(
    BuildContext context,
    ThemeData theme,
    String fileName,
    bool isBeingRenamed,
    InlineRenameController? renameController,
  ) {
    final textWidget = Text(
      fileName,
      style: theme.textTheme.bodySmall
          ?.copyWith(fontSize: GridZoomConstraints.gridItemFilenameFontSize),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    if (isBeingRenamed &&
        renameController != null &&
        renameController.textController != null) {
      return Row(
        children: [
          Expanded(
            child: InlineRenameField(
              controller: renameController,
              onCommit: () => renameController.commitRename(context),
              onCancel: () => renameController.cancelRename(),
              textStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ],
      );
    }

    return textWidget;
  }

  Widget _buildTagsDisplay(BuildContext context) {
    if (widget.state == null) return const SizedBox.shrink();

    final List<String> fileTags = _fileTags;
    if (fileTags.isEmpty) return const SizedBox.shrink();

    final List<String> tagsToShow = fileTags.take(2).toList();
    final bool hasMoreTags = fileTags.length > 2;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: [
        ...tagsToShow.map(
          (tag) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 8,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (hasMoreTags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Text(
              '+${fileTags.length - 2}',
              style: TextStyle(
                fontSize: 8,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}
