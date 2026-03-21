import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';

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

    final Color cardBackgroundColor = ItemInteractionStyle.backgroundColor(
      theme: theme,
      isDesktopMode: widget.isDesktopMode,
      isSelected: showAsSelected,
      isHovering: _isHovering,
    );

    final Color thumbnailOverlayColor =
        ItemInteractionStyle.thumbnailOverlayColor(
      theme: theme,
      isDesktopMode: widget.isDesktopMode,
      isSelected: showAsSelected,
      isHovering: _isHovering,
    );

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
          child: Container(
            decoration: BoxDecoration(
              color: cardBackgroundColor,
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ThumbnailOnly(
                          key: ValueKey('thumb-only-${widget.file.path}'),
                          file: widget.file,
                          iconSize: 48.0,
                        ),
                        if (thumbnailOverlayColor != Colors.transparent)
                          IgnorePointer(
                            child: Container(color: thumbnailOverlayColor),
                          ),
                        Positioned.fill(
                          child: OptimizedInteractionLayer(
                            onTap: () {
                              final keyboard = HardwareKeyboard.instance;
                              final bool isShiftPressed =
                                  keyboard.isShiftPressed;
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
                                widget.toggleSelectionMode();
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
                                    widget
                                        .toggleFileSelection(widget.file.path);
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
                Padding(
                  padding:
                      const EdgeInsets.only(top: 4.0, left: 4.0, right: 4.0),
                  child: Column(
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
              ],
            ),
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
      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    if (isBeingRenamed &&
        renameController != null &&
        renameController.textController != null) {
      return Stack(
        children: [
          // Invisible text for layout sizing
          Opacity(opacity: 0, child: textWidget),
          // Positioned editable field on top
          Positioned.fill(
            child: InlineRenameField(
              controller: renameController,
              onCommit: () => renameController.commitRename(context),
              onCancel: () => renameController.cancelRename(),
              textStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
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

    final List<String> fileTags =
        widget.state!.getTagsForFile(widget.file.path);
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
