import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/design_system/primitives/cb_inline_rename.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../components/common/shared_file_context_menu.dart';
import '../../../tab_manager/components/tag_context_menu.dart';
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
  final ValueListenable<bool?>? immediateSelectionListenable;

  const FolderGridItem({
    Key? key,
    required this.folder,
    required this.onNavigate,
    this.isSelected = false,
    this.toggleFolderSelection,
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.clearSelectionMode,
    this.immediateSelectionListenable,
  }) : super(key: key);

  @override
  State<FolderGridItem> createState() => _FolderGridItemState();
}

class _FolderGridItemState extends State<FolderGridItem> {
  bool _isHovering = false;

  /// Tag name when this "folder" is actually a child tag (path `#search?tag=`),
  /// otherwise null. A tag behaves like a folder in the results grid.
  String? get _tagName => UriUtils.extractTagFromSearchPath(widget.folder.path);

  /// Display label: the tag name for tag "folders", else the folder basename.
  String get _displayName => _tagName ?? widget.folder.basename();

  // Handle folder selection.
  void _handleFolderSelection() {
    if (widget.toggleFolderSelection == null) return;

    // Get keyboard state
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final bool isShiftPressed = keyboard.isShiftPressed;
    final bool isCtrlPressed =
        keyboard.isControlPressed || keyboard.isMetaPressed;
    // On desktop, a plain click selects only the clicked folder (clearing the
    // previous selection); Ctrl+click adds/toggles it. Using
    // `lastSelectedPath != null` made every click after the first behave like a
    // Ctrl+click, so the old selection was never cleared.
    final bool shouldCtrlSelect = widget.isDesktopMode ? isCtrlPressed : true;

    widget.toggleFolderSelection!(widget.folder.path,
        shiftSelect: isShiftPressed, ctrlSelect: shouldCtrlSelect);
  }

  @override
  Widget build(BuildContext context) {
    final immediateSelection = widget.immediateSelectionListenable;
    if (immediateSelection == null) {
      return _buildItem(context, widget.isSelected);
    }

    return ValueListenableBuilder<bool?>(
      valueListenable: immediateSelection,
      builder: (context, immediateValue, _) =>
          _buildItem(context, immediateValue ?? widget.isSelected),
    );
  }

  Widget _buildItem(BuildContext context, bool isVisuallySelected) {
    final bool isBeingCut = ItemInteractionStyle.isBeingCut(widget.folder.path);

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final Color borderColor = isVisuallySelected
        ? primary
        : _isHovering
            ? primary.withValues(alpha: 0.55)
            : primary.withValues(alpha: 0.35);
    final Color tabColor = isVisuallySelected
        ? primary.withValues(alpha: 0.25)
        : _isHovering
            ? primary.withValues(alpha: 0.12)
            : primary.withValues(alpha: 0.08);
    final Color bodyColor = isVisuallySelected
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
                    _displayName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: GridZoomConstraints.gridItemFilenameFontSize,
                      color: theme.colorScheme.onSurface,
                      fontWeight: isVisuallySelected
                          ? FontWeight.bold
                          : FontWeight.w500,
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
                  child: _buildNameWidget(context, isVisuallySelected),
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
    // A tag rendered as a folder card gets the tag-specific context menu.
    final tagName = _tagName;
    if (tagName != null) {
      showTagContextMenu(context, tagName, globalPosition: globalPosition);
      return;
    }

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

  Widget _buildNameWidget(
    BuildContext context,
    bool isVisuallySelected,
  ) {
    // Check if this item is being renamed inline (desktop only)
    final renameController = InlineRenameScope.maybeOf(context);
    final isBeingRenamed = renameController != null &&
        renameController.renamingPath == widget.folder.path;

    final textWidget = Text(
      _displayName,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: GridZoomConstraints.gridItemFilenameFontSize,
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: isVisuallySelected ? FontWeight.bold : FontWeight.w500,
      ),
    );

    if (isBeingRenamed && renameController.textController != null) {
      // Lifted into the overlay: the tile's name band budgets two ellipsised
      // lines, which is not enough to show a name while it is being typed.
      return CbInlineRenameOverlay(
        active: true,
        label: textWidget,
        editorBuilder: (context) => InlineRenameField(
          controller: renameController,
          onCommit: () => renameController.commitRename(context),
          onCancel: () => renameController.cancelRename(),
          textStyle: TextStyle(
            fontSize: GridZoomConstraints.gridItemFilenameFontSize,
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: isVisuallySelected ? FontWeight.bold : FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: cbInlineRenameMaxLines,
        ),
      );
    }

    return textWidget;
  }
}
