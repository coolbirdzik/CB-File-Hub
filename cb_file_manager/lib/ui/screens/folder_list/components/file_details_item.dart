import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import '../../../components/common/shared_file_context_menu.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';
import 'package:path/path.dart' as path;
import '../../../components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/helpers/network/streaming_helper.dart';
import 'package:cb_file_manager/services/network_browsing/webdav_service.dart';
import 'package:cb_file_manager/services/network_browsing/ftp_service.dart';
import '../../../utils/item_interaction_style.dart';

class FileDetailsItem extends StatefulWidget {
  final File file;
  final Function(File, bool)? onTap;
  final bool isSelected;
  final ColumnVisibility columnVisibility;
  final FolderListState state;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;
  final Function(BuildContext, String, List<String>) showDeleteTagDialog;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final bool isDesktopMode;
  final String? lastSelectedPath;
  final bool showFileTags; // Add parameter to control tag display

  const FileDetailsItem({
    Key? key,
    required this.file,
    required this.onTap,
    required this.isSelected,
    required this.columnVisibility,
    required this.state,
    required this.toggleFileSelection,
    required this.showDeleteTagDialog,
    required this.showAddTagToFileDialog,
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.showFileTags = true, // Default to showing tags
  }) : super(key: key);

  @override
  State<FileDetailsItem> createState() => _FileDetailsItemState();
}

class _FileDetailsItemState extends State<FileDetailsItem> {
  bool _isHovering = false;
  bool _visuallySelected = false;
  FileStat? _fileStat;
  late bool isImage;
  late bool isVideo;
  // Create a key based on the file path to prevent thumbnail recreation
  late final ValueKey<String> _thumbnailKey;

  @override
  void initState() {
    super.initState();
    _visuallySelected = widget.isSelected;
    _loadFileStats();
    _checkFileType();
    _thumbnailKey = ValueKey('thumbnail-${widget.file.path}');
  }

  @override
  void didUpdateWidget(FileDetailsItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      setState(() {
        _visuallySelected = widget.isSelected;
      });
    }

    if (widget.file.path != oldWidget.file.path) {
      _loadFileStats();
      _checkFileType();
      // We don't need to update the thumbnail key here since file path changed
      // and we'll get a new widget instance anyway
    }
  }

  Future<void> _loadFileStats() async {
    try {
      final stat = await widget.file.stat();
      if (mounted) {
        setState(() {
          _fileStat = stat;
        });
      }
    } catch (e) {
      debugPrint('Error loading file stats: $e');
    }
  }

  void _checkFileType() {
    final String extension = path.extension(widget.file.path).toLowerCase();
    final category = FileTypeRegistry.getCategory(extension);
    isImage = category == FileCategory.image;
    isVideo = category == FileCategory.video;
  }

  void _handleFileSelection() {
    // Check for Shift and Ctrl keys
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final bool isShiftPressed = keyboard.isShiftPressed;
    final bool isCtrlPressed =
        keyboard.isControlPressed || keyboard.isMetaPressed;

    // Log selection attempt
    debugPrint("File selection: ${widget.file.path}");
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

    // Call toggleFileSelection with appropriate parameters
    widget.toggleFileSelection(
      widget.file.path,
      shiftSelect: isShiftPressed,
      ctrlSelect: isCtrlPressed,
    );
  }

  void _showFileContextMenu(BuildContext context, Offset globalPosition) {
    showFileContextMenu(
      context: context,
      file: widget.file,
      fileTags: widget.state.fileTags[widget.file.path] ?? [],
      isVideo: isVideo,
      isImage: isImage,
      showAddTagToFileDialog: widget.showAddTagToFileDialog,
      globalPosition: globalPosition,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isBeingCut = ItemInteractionStyle.isBeingCut(widget.file.path);

    // Calculate colors based on selection state
    final Color itemBackgroundColor = ItemInteractionStyle.backgroundColor(
      theme: theme,
      isDesktopMode: widget.isDesktopMode,
      isSelected: _visuallySelected,
      isHovering: _isHovering,
    );

    final BoxDecoration boxDecoration = BoxDecoration(
      color: itemBackgroundColor,
    );

    // Get the file extension and icon
    final String fileExtension = path.extension(widget.file.path).toLowerCase();
    final IconData fileIcon = FileTypeRegistry.getIcon(fileExtension);
    final Color iconColor = FileTypeRegistry.getColor(fileExtension);

    return Opacity(
      opacity: isBeingCut ? ItemInteractionStyle.cutOpacity : 1.0,
      child: GestureDetector(
        onSecondaryTapUp: (details) =>
            _showFileContextMenu(context, details.globalPosition),
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
                            // Use a dedicated widget for file icon with a key to prevent rebuilds
                            _OptimizedFileIcon(
                              key: _thumbnailKey,
                              file: widget.file,
                              isVideo: isVideo,
                              isImage: isImage,
                              icon: fileIcon,
                              color: iconColor,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildNameWidget(context),
                            ),

                            // Show file tags if available and enabled
                            if (widget.showFileTags &&
                                (widget.state.fileTags[widget.file.path]
                                        ?.isNotEmpty ??
                                    false))
                              Padding(
                                padding: const EdgeInsets.only(left: 4.0),
                                child: Icon(
                                  PhosphorIconsLight.bookmark,
                                  size: 16,
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                ),
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
                            _getFileTypeLabel(fileExtension),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                    // Size column (prefer WebDAV metadata)
                    if (widget.columnVisibility.size)
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: Builder(builder: (context) {
                            String text = 'Loading...';
                            final svc =
                                StreamingHelper.instance.currentNetworkService;
                            if (svc is WebDAVService) {
                              final remotePath =
                                  svc.getRemotePathFromLocal(widget.file.path);
                              if (remotePath != null) {
                                final meta = svc.getMeta(remotePath);
                                if (meta != null && meta.size >= 0) {
                                  text = _formatFileSize(meta.size);
                                }
                              }
                            } else if (svc is FTPService) {
                              final meta = svc.getMeta(widget.file.path);
                              if (meta != null && meta.size >= 0) {
                                text = _formatFileSize(meta.size);
                              }
                            }
                            if (text == 'Loading...' && _fileStat != null) {
                              text = _formatFileSize(_fileStat!.size);
                            }
                            return Text(text, overflow: TextOverflow.ellipsis);
                          }),
                        ),
                      ),

                    // Date modified column (prefer WebDAV metadata)
                    if (widget.columnVisibility.dateModified)
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: Builder(builder: (context) {
                            String text = 'Loading...';
                            final svc =
                                StreamingHelper.instance.currentNetworkService;
                            if (svc is WebDAVService) {
                              final remotePath =
                                  svc.getRemotePathFromLocal(widget.file.path);
                              if (remotePath != null) {
                                final meta = svc.getMeta(remotePath);
                                if (meta != null) {
                                  text =
                                      meta.modified.toString().split('.').first;
                                }
                              }
                            } else if (svc is FTPService) {
                              final meta = svc.getMeta(widget.file.path);
                              if (meta != null) {
                                final dt = meta.modified ?? DateTime.now();
                                text = dt.toString().split('.').first;
                              }
                            }
                            if (text == 'Loading...' && _fileStat != null) {
                              text = _fileStat!.modified
                                  .toString()
                                  .split('.')
                                  .first;
                            }
                            return Text(text, overflow: TextOverflow.ellipsis);
                          }),
                        ),
                      ),

                    // Date created column (fallback to FileStat)
                    if (widget.columnVisibility.dateCreated)
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 10.0),
                          child: Text(
                            _fileStat != null
                                ? _fileStat!.changed.toString().split('.').first
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
                  ],
                ),
              ),
              // Add optimized interaction layer on top
              Positioned.fill(
                child: OptimizedInteractionLayer(
                  onTap: () {
                    if (widget.isDesktopMode) {
                      _handleFileSelection();
                    } else if (widget.onTap != null) {
                      widget.onTap!(widget.file, false);
                    }
                  },
                  onDoubleTap: widget.isDesktopMode && widget.onTap != null
                      ? () {
                          widget.onTap!(widget.file, true);
                        }
                      : null,
                  onLongPress: widget.isDesktopMode
                      ? () {
                          if (!_visuallySelected) {
                            _handleFileSelection();
                          }
                        }
                      : null,
                  onLongPressStart: !widget.isDesktopMode
                      ? (d) {
                          HapticFeedback.mediumImpact();
                          _showFileContextMenu(context, d.globalPosition);
                        }
                      : null,
                  onSecondaryTapUp: (details) =>
                      _showFileContextMenu(context, details.globalPosition),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getFileTypeLabel(String extension) {
    return FileTypeUtils.getFileTypeLabel(context, extension);
  }

  String _formatFileSize(int size) {
    return FileUtils.formatFileSize(size);
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
        renameController.renamingPath == widget.file.path;

    final textWidget = Text(
      path.basename(widget.file.path),
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: _visuallySelected ? FontWeight.bold : FontWeight.normal,
      ),
    );

    if (isBeingRenamed && renameController.textController != null) {
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

// Replace the _FileInteractionLayer class (remove it)
// Remove entire _FileInteractionLayer class and its state class

// Replace the _OptimizedFileIcon class with this:
class _OptimizedFileIcon extends StatefulWidget {
  final File file;
  final bool isVideo;
  final bool isImage;
  final IconData icon;
  final Color? color;

  const _OptimizedFileIcon({
    Key? key,
    required this.file,
    required this.isVideo,
    required this.isImage,
    required this.icon,
    required this.color,
  }) : super(key: key);

  @override
  State<_OptimizedFileIcon> createState() => _OptimizedFileIconState();
}

class _OptimizedFileIconState extends State<_OptimizedFileIcon>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return OptimizedFileIcon(
      file: widget.file,
      isVideo: widget.isVideo,
      isImage: widget.isImage,
      size: 24,
      fallbackIcon: widget.icon,
      fallbackColor: widget.color,
      borderRadius: BorderRadius.circular(2),
    );
  }
}
