import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../components/common/shared_file_context_menu.dart';
import '../../../../bloc/selection/selection_bloc.dart';
import '../../../../bloc/selection/selection_event.dart';
import 'folder_thumbnail.dart';
import '../../../components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import '../../../utils/item_interaction_style.dart';

class FolderGridItem extends StatefulWidget {
  final Directory folder;
  final Function(String) onNavigate;
  final bool isSelected;
  final Function(String, {bool shiftSelect, bool ctrlSelect})?
      toggleFolderSelection;
  final bool isDesktopMode;
  final String? lastSelectedPath;
  final Function()? clearSelectionMode;

  const FolderGridItem({
    Key? key,
    required this.folder,
    required this.onNavigate,
    this.isSelected = false,
    this.toggleFolderSelection,
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.clearSelectionMode,
  }) : super(key: key);

  @override
  State<FolderGridItem> createState() => _FolderGridItemState();
}

class _FolderGridItemState extends State<FolderGridItem> {
  bool _isHovering = false;
  bool _visuallySelected = false;

  @override
  void initState() {
    super.initState();
    _visuallySelected = widget.isSelected;
  }

  @override
  void didUpdateWidget(FolderGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update when external selection state changes
    if (widget.isSelected != oldWidget.isSelected) {
      _visuallySelected = widget.isSelected;
    }
  }

  // Handle folder selection with immediate visual feedback
  void _handleFolderSelection() {
    if (widget.toggleFolderSelection == null) return;

    // Get keyboard state
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final bool isShiftPressed = keyboard.isShiftPressed;
    final bool isCtrlPressed =
        keyboard.isControlPressed || keyboard.isMetaPressed;

    // Visual update depends on the selection type
    if (!isShiftPressed) {
      if (!isCtrlPressed) {
        _visuallySelected = true;
      } else {
        _visuallySelected = !_visuallySelected;
      }
    }

    widget.toggleFolderSelection!(widget.folder.path,
        shiftSelect: isShiftPressed, ctrlSelect: isCtrlPressed);
  }

  @override
  Widget build(BuildContext context) {
    final bool isBeingCut = ItemInteractionStyle.isBeingCut(widget.folder.path);

    final Color overlayColor = ItemInteractionStyle.thumbnailOverlayColor(
      theme: Theme.of(context),
      isDesktopMode: widget.isDesktopMode,
      isSelected: _visuallySelected,
      isHovering: _isHovering,
    );

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final Color borderColor = _visuallySelected
        ? primary
        : _isHovering
            ? primary.withValues(alpha: 0.55)
            : primary.withValues(alpha: 0.35);
    final Color tabColor = _visuallySelected
        ? primary.withValues(alpha: 0.25)
        : _isHovering
            ? primary.withValues(alpha: 0.12)
            : primary.withValues(alpha: 0.08);
    final Color bodyColor = _visuallySelected
        ? primary.withValues(alpha: 0.08)
        : primary.withValues(alpha: 0.03);
    const double borderWidth = 1.5;
    const double bodyRadius = 6.0;
    const double tabRadius = 5.0;

    // Fixed height for name area — ensures the folder shape (thumbnail) is
    // always the same height regardless of whether the name is 1 or 2 lines.
    const double nameAreaHeight = GridZoomConstraints.gridItemNameAreaHeight;

    if (!widget.isDesktopMode) {
      return Opacity(
        opacity: isBeingCut ? ItemInteractionStyle.cutOpacity : 1.0,
        child: GestureDetector(
          onSecondaryTapDown: (details) =>
              _showFolderContextMenu(context, details.globalPosition),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: _buildFolderShape(
                  context,
                  borderColor: borderColor,
                  tabColor: tabColor,
                  bodyColor: bodyColor,
                  borderWidth: borderWidth,
                  bodyRadius: bodyRadius,
                  tabRadius: tabRadius,
                  overlayColor: overlayColor,
                  interactionLayer: OptimizedInteractionLayer(
                    onTap: () {
                      widget.onNavigate(widget.folder.path);
                    },
                    onDoubleTap: () {
                      if (widget.clearSelectionMode != null) {
                        widget.clearSelectionMode!();
                      }
                      widget.onNavigate(widget.folder.path);
                    },
                    onLongPress: widget.isDesktopMode
                        ? () => _showFolderContextMenu(context, null)
                        : null,
                    onLongPressStart: !widget.isDesktopMode
                        ? (details) {
                            HapticFeedback.mediumImpact();
                            _showFolderContextMenu(
                              context,
                              details.globalPosition,
                            );
                          }
                        : null,
                    onTertiaryTapUp: (_) {
                      context
                          .read<TabManagerBloc>()
                          .add(AddTab(path: widget.folder.path));
                    },
                  ),
                ),
              ),
              SizedBox(
                height: nameAreaHeight,
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 4.0, left: 4.0, right: 4.0),
                  child: Text(
                    widget.folder.basename(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: GridZoomConstraints.gridItemFilenameFontSize,
                      color: theme.colorScheme.onSurface,
                      fontWeight:
                          _visuallySelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Desktop layout
    return Opacity(
      opacity: isBeingCut ? ItemInteractionStyle.cutOpacity : 1.0,
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showFolderContextMenu(context, details.globalPosition),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          cursor: SystemMouseCursors.click,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: _buildFolderShape(
                  context,
                  borderColor: borderColor,
                  tabColor: tabColor,
                  bodyColor: bodyColor,
                  borderWidth: borderWidth,
                  bodyRadius: bodyRadius,
                  tabRadius: tabRadius,
                  overlayColor: overlayColor,
                  interactionLayer: OptimizedInteractionLayer(
                    onTap: () {
                      if (widget.isDesktopMode &&
                          widget.toggleFolderSelection != null) {
                        _handleFolderSelection();
                      } else {
                        widget.onNavigate(widget.folder.path);
                      }
                    },
                    onDoubleTap: () {
                      if (widget.clearSelectionMode != null) {
                        widget.clearSelectionMode!();
                      }
                      widget.onNavigate(widget.folder.path);
                    },
                    onLongPress: widget.isDesktopMode
                        ? () => _showFolderContextMenu(context, null)
                        : null,
                    onLongPressStart: !widget.isDesktopMode
                        ? (details) {
                            HapticFeedback.mediumImpact();
                            _showFolderContextMenu(
                              context,
                              details.globalPosition,
                            );
                          }
                        : null,
                    onTertiaryTapUp: (_) {
                      context
                          .read<TabManagerBloc>()
                          .add(AddTab(path: widget.folder.path));
                    },
                  ),
                ),
              ),
              SizedBox(
                height: nameAreaHeight,
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 4.0, left: 4.0, right: 4.0),
                  child: _buildNameWidget(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderShape(
    BuildContext context, {
    required Color borderColor,
    required Color tabColor,
    required Color bodyColor,
    required double borderWidth,
    required double bodyRadius,
    required double tabRadius,
    required Color overlayColor,
    required Widget interactionLayer,
  }) {
    return Column(
      children: [
        // Folder tab — small strip at top-left
        Row(
          children: [
            Container(
              height: 10,
              width: 32,
              decoration: BoxDecoration(
                color: tabColor,
                border: Border(
                  top: BorderSide(color: borderColor, width: borderWidth),
                  left: BorderSide(color: borderColor, width: borderWidth),
                  right: BorderSide(color: borderColor, width: borderWidth),
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(tabRadius),
                  topRight: Radius.circular(tabRadius),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
        // Folder body — contains the thumbnail
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: bodyColor,
              border: Border.all(color: borderColor, width: borderWidth),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(bodyRadius),
                bottomLeft: Radius.circular(bodyRadius),
                bottomRight: Radius.circular(bodyRadius),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(bodyRadius - borderWidth),
                bottomLeft: Radius.circular(bodyRadius - borderWidth),
                bottomRight: Radius.circular(bodyRadius - borderWidth),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FolderThumbnail(folder: widget.folder),
                  if (overlayColor != Colors.transparent)
                    IgnorePointer(
                      child: Container(color: overlayColor),
                    ),
                  Positioned.fill(child: interactionLayer),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showFolderContextMenu(BuildContext context, Offset? globalPosition) {
    // Check for multiple selection
    try {
      final selectionBloc = context.read<SelectionBloc>();
      final selectionState = selectionBloc.state;

      if (selectionState.allSelectedPaths.length > 1 &&
          selectionState.allSelectedPaths.contains(widget.folder.path)) {
        showMultipleFilesContextMenu(
          context: context,
          selectedPaths: selectionState.allSelectedPaths,
          globalPosition: globalPosition ?? Offset.zero,
          onClearSelection: () {
            selectionBloc.add(ClearSelection());
          },
        );
        return;
      }
    } catch (e) {
      debugPrint('Error showing context menu: $e');
    }

    // Use the shared folder context menu
    showFolderContextMenu(
      context: context,
      folder: widget.folder,
      onNavigate: widget.onNavigate,
      folderTags: [],
      globalPosition: globalPosition,
    );
  }

  Widget _buildNameWidget(BuildContext context) {
    // Check if this item is being renamed inline (desktop only)
    final renameController = InlineRenameScope.maybeOf(context);
    final isBeingRenamed = renameController != null &&
        renameController.renamingPath == widget.folder.path;

    final textWidget = Text(
      widget.folder.basename(),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: GridZoomConstraints.gridItemFilenameFontSize,
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: _visuallySelected ? FontWeight.bold : FontWeight.w500,
      ),
    );

    if (isBeingRenamed && renameController.textController != null) {
      return Row(
        children: [
          Expanded(
            child: InlineRenameField(
              controller: renameController,
              onCommit: () => renameController.commitRename(context),
              onCancel: () => renameController.cancelRename(),
              textStyle: TextStyle(
                fontSize: GridZoomConstraints.gridItemFilenameFontSize,
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight:
                    _visuallySelected ? FontWeight.bold : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ],
      );
    }

    return textWidget;
  }
}
