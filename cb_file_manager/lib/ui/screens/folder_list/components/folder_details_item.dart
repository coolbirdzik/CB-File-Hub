import 'dart:io';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';
import '../../../components/common/shared_file_context_menu.dart';
import '../../../tab_manager/components/tag_context_menu.dart';
import '../../../components/common/optimized_interaction_handler.dart';
import '../../../utils/item_interaction_style.dart';
import 'package:cb_file_manager/services/file_metadata_service.dart';
import 'package:cb_file_manager/core/service_locator.dart';

class FolderDetailsItem extends StatefulWidget {
  final Directory folder;
  final Function(String)? onTap;
  final bool isSelected;
  final ColumnVisibility columnVisibility;
  final Function(String, {bool shiftSelect, bool ctrlSelect})?
      toggleFolderSelection;
  final bool isDesktopMode;
  final String? lastSelectedPath;
  final Function()? clearSelectionMode;

  const FolderDetailsItem({
    Key? key,
    required this.folder,
    this.onTap,
    this.isSelected = false,
    required this.columnVisibility,
    this.toggleFolderSelection,
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.clearSelectionMode,
  }) : super(key: key);

  @override
  State<FolderDetailsItem> createState() => _FolderDetailsItemState();
}

class _FolderDetailsItemState extends State<FolderDetailsItem> {
  bool _isHovering = false;
  bool _visuallySelected = false;
  FileStat? _fileStat;

  /// Tag name when this "folder" is actually a child tag (`#search?tag=`).
  String? get _tagName => UriUtils.extractTagFromSearchPath(widget.folder.path);

  @override
  void initState() {
    super.initState();
    _visuallySelected = widget.isSelected;
    _loadFolderStats();
  }

  @override
  void didUpdateWidget(FolderDetailsItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      setState(() {
        _visuallySelected = widget.isSelected;
      });
    }

    if (widget.folder.path != oldWidget.folder.path) {
      _loadFolderStats();
    }
  }

  Future<void> _loadFolderStats() async {
    // Tag "folders" are virtual (path #search?tag=...) and have no real stat.
    if (_tagName != null) return;
    try {
      final stat = await widget.folder.stat();
      if (mounted) {
        setState(() {
          _fileStat = stat;
        });
      }
    } catch (e) {
      debugPrint('Error loading folder stats: $e');
    }
  }

  void _handleFolderSelection() {
    if (widget.toggleFolderSelection == null) return;

    // Check for Shift and Ctrl keys
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final bool isShiftPressed = keyboard.isShiftPressed;
    final bool isCtrlPressed =
        keyboard.isControlPressed || keyboard.isMetaPressed;

    // Log selection attempt
    debugPrint("Folder selection: ${widget.folder.path}");
    debugPrint("Shift: $isShiftPressed, Ctrl: $isCtrlPressed");

    // Visual update for immediate feedback
    if (!isShiftPressed) {
      setState(() {
        if (!isCtrlPressed) {
          // Single selection without Ctrl: this item will be selected
          _visuallySelected = true;
        } else {
          // Ctrl+click: toggle this item's selection
          _visuallySelected = !_visuallySelected;
        }
      });
    }

    // On desktop, a plain click selects only the clicked folder (clearing the
    // previous selection); Ctrl+click adds/toggles it. Using
    // `lastSelectedPath != null` made every click after the first behave like a
    // Ctrl+click, so the old selection was never cleared.
    final bool shouldCtrlSelect = widget.isDesktopMode ? isCtrlPressed : true;

    // Call toggleFolderSelection with appropriate parameters
    widget.toggleFolderSelection!(
      widget.folder.path,
      shiftSelect: isShiftPressed,
      ctrlSelect: shouldCtrlSelect,
    );
  }

  void _showFolderContextMenu(BuildContext context, Offset? globalPosition) {
    // A tag rendered as a folder row gets the tag-specific context menu.
    final tagName = _tagName;
    if (tagName != null) {
      showTagContextMenu(context, tagName, globalPosition: globalPosition);
      return;
    }

    // Use the shared folder context menu
    showFolderContextMenu(
      context: context,
      folder: widget.folder,
      onNavigate: widget.onTap,
      folderTags: [], // Pass empty tags or fetch from database in real implementation
      globalPosition: globalPosition, // Pass position for desktop popup menu
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isBeingCut = ItemInteractionStyle.isBeingCut(widget.folder.path);

    // Calculate colors based on selection state
    final Color itemBackgroundColor = ItemInteractionStyle.backgroundColor(
      theme: theme,
      isDesktopMode: widget.isDesktopMode,
      isSelected: _visuallySelected,
      isHovering: _isHovering,
    );

    final BoxDecoration boxDecoration = _visuallySelected
        ? BoxDecoration(
            color: itemBackgroundColor,
          )
        : BoxDecoration(
            color: itemBackgroundColor,
          );

    return Opacity(
      opacity: isBeingCut ? ItemInteractionStyle.cutOpacity : 1.0,
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showFolderContextMenu(context, details.globalPosition),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          cursor: SystemMouseCursors.click,
          child: Stack(
            children: [
              Container(
                decoration: boxDecoration,
                child: Row(
                  children: [
                    // Name column (always visible)
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 10.0),
                        child: Row(
                          children: [
                            Icon(
                                _tagName != null
                                    ? PhosphorIconsLight.tag
                                    : PhosphorIconsLight.folder,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildNameWidget(context),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Type column
                    if (widget.columnVisibility.type)
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: Text(
                            _tagName != null
                                ? AppLocalizations.of(context)!.tagPrefix
                                : AppLocalizations.of(context)!.folder,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Size column
                    if (widget.columnVisibility.size)
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: const Text(
                            '', // Folders don't typically show size in explorer
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Date modified column
                    if (widget.columnVisibility.dateModified)
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: Text(
                            _fileStat != null
                                ? _fileStat!.modified.toString().split('.')[0]
                                : 'Loading...',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Date created column
                    if (widget.columnVisibility.dateCreated)
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: Text(
                            _fileStat != null
                                ? _fileStat!.changed.toString().split('.')[0]
                                : 'Loading...',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Attributes column
                    if (widget.columnVisibility.attributes)
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: Text(
                            _getAttributes(_fileStat),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Date Accessed column
                    if (widget.columnVisibility.dateAccessed)
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: Text(
                            _fileStat != null
                                ? _fileStat!.accessed
                                    .toString()
                                    .split('.')
                                    .first
                                : 'Loading...',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Extension column (empty for folders)
                    if (widget.columnVisibility.extension)
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: const Text(
                            '',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Path column
                    if (widget.columnVisibility.path)
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: Text(
                            widget.folder.path,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Tags column (empty for folders)
                    if (widget.columnVisibility.tags)
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: const Text(
                            '',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Dimensions column (empty for folders)
                    if (widget.columnVisibility.dimensions)
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: const Text(
                            '',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Duration column (empty for folders)
                    if (widget.columnVisibility.duration)
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: const Text(
                            '',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Item Count column
                    if (widget.columnVisibility.itemCount)
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: _AsyncItemCountCell(
                              folderPath: widget.folder.path),
                        ),
                      ),
                  ],
                ),
              ),
              // Replace with optimized interaction layer
              Positioned.fill(
                child: OptimizedInteractionLayer(
                  onTap: () {
                    if (widget.isDesktopMode &&
                        widget.toggleFolderSelection != null) {
                      _handleFolderSelection();
                    } else if (widget.onTap != null) {
                      widget.onTap!(widget.folder.path);
                    }
                  },
                  onDoubleTap: () {
                    if (widget.clearSelectionMode != null) {
                      widget.clearSelectionMode!();
                    }
                    if (widget.onTap != null) {
                      widget.onTap!(widget.folder.path);
                    }
                  },
                  onLongPress: () {
                    if (widget.isDesktopMode &&
                        widget.toggleFolderSelection != null) {
                      _handleFolderSelection();
                    }
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getAttributes(FileStat? stat) {
    if (stat == null) return '';

    final List<String> attrs = [];

    if (stat.modeString()[0] == 'd') attrs.add('D');
    if (stat.modeString()[1] == 'r') attrs.add('R');
    if (stat.modeString()[2] == 'w') attrs.add('W');
    if (stat.modeString()[3] == 'x') attrs.add('X');

    return attrs.join(' ');
  }

  Widget _buildNameWidget(BuildContext context) {
    // Check if this item is being renamed inline (desktop only)
    final renameController = InlineRenameScope.maybeOf(context);
    final isBeingRenamed = renameController != null &&
        renameController.renamingPath == widget.folder.path;

    final textWidget = Text(
      _tagName ?? widget.folder.basename(),
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: _visuallySelected ? FontWeight.bold : FontWeight.normal,
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
                fontWeight:
                    _visuallySelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.start,
              maxLines: 1,
            ),
          ),
        ],
      );
    }

    return textWidget;
  }
}

// Separate interaction layer to handle gestures without requiring content to rebuild
class _FolderInteractionLayer extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _FolderInteractionLayer({
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  _FolderInteractionLayerState createState() => _FolderInteractionLayerState();
}

class _FolderInteractionLayerState extends State<_FolderInteractionLayer> {
  int _lastTapTime = 0;
  Offset? _lastTapPosition;
  static const int _doubleTapTimeout = 300; // milliseconds
  static const double _doubleTapMaxDistance = 40.0; // pixels

  void _handleTapDown(TapDownDetails details) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final position = details.globalPosition;

    // Always trigger onTap immediately
    widget.onTap();

    // Check if this could be a double tap
    if (_lastTapTime > 0) {
      final timeDiff = now - _lastTapTime;
      final distance = _lastTapPosition != null
          ? (position - _lastTapPosition!).distance
          : 0.0;

      // If within double tap time window and distance threshold
      if (timeDiff <= _doubleTapTimeout && distance <= _doubleTapMaxDistance) {
        widget.onDoubleTap();
        // Reset to prevent triple tap
        _lastTapTime = 0;
        _lastTapPosition = null;
        return;
      }
    }

    // Store info for potential next tap
    _lastTapTime = now;
    _lastTapPosition = position;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onLongPress: null,
    );
  }
}

/// Async widget that loads and displays folder item count.
class _AsyncItemCountCell extends StatefulWidget {
  final String folderPath;

  const _AsyncItemCountCell({required this.folderPath});

  @override
  State<_AsyncItemCountCell> createState() => _AsyncItemCountCellState();
}

class _AsyncItemCountCellState extends State<_AsyncItemCountCell> {
  int? _count;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  @override
  void didUpdateWidget(_AsyncItemCountCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.folderPath != oldWidget.folderPath) {
      _loaded = false;
      _count = null;
      _loadCount();
    }
  }

  Future<void> _loadCount() async {
    try {
      final service = locator<FileMetadataService>();
      final count = await service.getFolderItemCount(widget.folderPath);
      if (mounted) {
        setState(() {
          _count = count;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Text('...', overflow: TextOverflow.ellipsis);
    }
    if (_count == null) {
      return const Text('\u2014', overflow: TextOverflow.ellipsis);
    }
    final l10n = AppLocalizations.of(context)!;
    return Text(
      l10n.itemCountFormat(_count!),
      overflow: TextOverflow.ellipsis,
    );
  }
}
