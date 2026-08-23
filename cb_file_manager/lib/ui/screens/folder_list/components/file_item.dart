import 'dart:io';
import 'dart:async'; // Thêm import cho StreamSubscription
// For lerpDouble
// For more responsive animations

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/image_viewer_screen.dart';
import 'package:cb_file_manager/ui/utils/video_playback_launcher.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart'; // Import TagManager để lắng nghe thay đổi
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/bloc/selection/selection_bloc.dart';
import 'package:cb_file_manager/bloc/selection/selection_event.dart';
import 'package:cb_file_manager/ui/dialogs/open_with_dialog.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';
import 'package:cb_file_manager/helpers/files/file_icon_helper.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/ui/widgets/tag_chip.dart'; // Import the new TagChip widget
import '../../../components/common/shared_file_context_menu.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart'; // Import ThumbnailLoader
import 'package:flutter/services.dart'; // Import for keyboard key detection
// Import for RepaintBoundary
import '../../../components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';
import 'package:cb_file_manager/ui/widgets/file_preview_pane.dart';
import '../../../utils/item_interaction_style.dart';
import 'package:cb_file_manager/helpers/network/streaming_helper.dart';
import 'package:cb_file_manager/services/network_browsing/webdav_service.dart';
import 'package:cb_file_manager/services/network_browsing/ftp_service.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';

// Add this class to disable ripple effects
class NoSplashFactory extends InteractiveInkFeatureFactory {
  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return _NoSplash(
      controller: controller,
      referenceBox: referenceBox,
    );
  }
}

class _NoSplash extends InteractiveInkFeature {
  _NoSplash({
    required MaterialInkController controller,
    required RenderBox referenceBox,
  }) : super(
          controller: controller,
          referenceBox: referenceBox,
          color: Colors.transparent,
        );

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    // No painting needed
  }
}

class FileItem extends StatefulWidget {
  final File file;
  final FolderListState state;
  final bool isSelectionMode;
  final bool isSelected;
  final Function(String, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;
  final Function(BuildContext, String, List<String>) showDeleteTagDialog;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final Future<void> Function(BuildContext, File)? onDeleteFile;
  final Future<void> Function(BuildContext, List<String>)? onDeleteFiles;
  final Function(File, bool)? onFileTap;
  final bool isDesktopMode;
  final String?
      lastSelectedPath; // Add parameter to track last selected file for shift-selection
  final bool showFileTags; // Add parameter to control tag display
  final bool showItemBackground;

  const FileItem({
    Key? key,
    required this.file,
    required this.state,
    required this.isSelectionMode,
    required this.isSelected,
    required this.toggleFileSelection,
    required this.showDeleteTagDialog,
    required this.showAddTagToFileDialog,
    this.onDeleteFile,
    this.onDeleteFiles,
    this.onFileTap,
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.showFileTags = true, // Default to showing tags
    this.showItemBackground = true,
  }) : super(key: key);

  @override
  State<FileItem> createState() => _FileItemState();
}

class _FileItemState extends State<FileItem> {
  late List<String> _fileTags;
  StreamSubscription? _tagChangeSubscription;
  // Use ValueNotifier for state management
  final ValueNotifier<bool> _isHoveringNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isSelectedNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _fileTags = widget.state.getTagsForFile(widget.file.path);
    // Đăng ký lắng nghe thay đổi tag
    _tagChangeSubscription = TagManager.onTagChanged.listen(_onTagChanged);
    _isSelectedNotifier.value = widget.isSelected;
  }

  @override
  void dispose() {
    // Hủy đăng ký lắng nghe khi widget bị hủy
    _tagChangeSubscription?.cancel();
    _isHoveringNotifier.dispose();
    _isSelectedNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FileItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update selection state if it changed externally
    if (widget.isSelected != oldWidget.isSelected) {
      _isSelectedNotifier.value = widget.isSelected;
    }

    // Update tags if they've changed
    final newTags = widget.state.getTagsForFile(widget.file.path);
    if (!_areTagListsEqual(newTags, _fileTags)) {
      if (mounted) {
        setState(() {
          _fileTags = newTags;
        });
      }
    }
  }

  // Xử lý sự kiện thay đổi tag
  void _onTagChanged(String changedFilePath) {
    debugPrint(
        "FileItem: received tag change notification: $changedFilePath for file: ${widget.file.path}");

    // Check for global notifications first
    if (changedFilePath == "global:tag_updated" ||
        changedFilePath == "global:tag_deleted") {
      _updateTagsIfChanged();
      return;
    }

    // Extract the actual file path if it has a prefix
    String actualPath = changedFilePath;
    bool isTagOnlyEvent = false;

    if (changedFilePath.startsWith("preserve_scroll:")) {
      actualPath = changedFilePath.substring("preserve_scroll:".length);
    } else if (changedFilePath.startsWith("tag_only:")) {
      isTagOnlyEvent = true;
      actualPath = changedFilePath.substring("tag_only:".length);
    }

    if (actualPath == widget.file.path) {
      if (!isTagOnlyEvent) {
        TagManager.clearCache();
      }
      _updateTagsIfChanged();
    }
  }

  void _updateTagsIfChanged() {
    final newTags = widget.state.getTagsForFile(widget.file.path);
    debugPrint(
        "FileItem: comparing tags for ${widget.file.path}: old=$_fileTags, new=$newTags");
    if (mounted && !_areTagListsEqual(newTags, _fileTags)) {
      debugPrint("FileItem: updating tags for ${widget.file.path}");
      setState(() {
        _fileTags = newTags;
      });
    }
  }

  bool _areTagListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    list1.sort();
    list2.sort();
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  Future<void> _removeTagDirectly(String tag) async {
    try {
      await TagManager.removeTag(widget.file.path, tag);
      if (mounted) {
        setState(() {
          _fileTags.remove(tag);
        });

        // Clear cache to ensure fresh data
        TagManager.clearCache();

        // Send multiple notifications to ensure all components update
        TagManager.instance.notifyTagChanged("tag_only:${widget.file.path}");
        TagManager.instance.notifyTagChanged(widget.file.path);
        TagManager.instance.notifyTagChanged("global:tag_updated");

        // Update via bloc if available
        try {
          final bloc = BlocProvider.of<FolderListBloc>(context, listen: false);
          bloc.add(RemoveTagFromFile(widget.file.path, tag));
        } catch (e) {
          debugPrint('FolderListBloc not available in this context: $e');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.tagDeleted(tag)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context)!.errorDeletingTag(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _openFile(bool isVideo, bool isImage) {
    if (widget.onFileTap != null) {
      widget.onFileTap!(widget.file, isVideo);
    } else {
      // Video: default in-app player; only system default when user enabled in Settings
      if (isVideo) {
        ExternalAppHelper.openWithPreferredVideoApp(widget.file.path)
            .then((openedPreferred) {
          if (openedPreferred) return;

          locator<UserPreferences>()
              .getUseSystemDefaultForVideo()
              .then((useSystem) {
            if (useSystem) {
              ExternalAppHelper.openWithSystemDefault(widget.file.path)
                  .then((success) {
                if (!success && mounted) {
                  RouteUtils.showAcrylicDialog(
                      context: context,
                      builder: (dialogContext) =>
                          OpenWithDialog(filePath: widget.file.path));
                }
              });
            } else {
              if (mounted) {
                unawaited(
                  VideoPlaybackLauncher.open(context, file: widget.file),
                );
              }
            }
          });
        });
      } else if (isImage) {
        if (!context.mounted) return;
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => ImageViewerScreen(file: widget.file)));
      } else if (FileTypeUtils.isArchiveFile(widget.file.path)) {
        ExternalAppHelper.openFileWithApp(widget.file.path, 'shell_open')
            .then((success) {
          if (!success && mounted) {
            RouteUtils.showAcrylicDialog(
              context: context,
              builder: (dialogContext) =>
                  OpenWithDialog(filePath: widget.file.path),
            );
          }
        });
      } else if (FileTypeUtils.isTextFile(widget.file.path) ||
          FileTypeUtils.isPdfFile(widget.file.path)) {
        if (mounted) {
          unawaited(InAppFileViewer.open(context, widget.file));
        }
      } else {
        ExternalAppHelper.openFileWithApp(widget.file.path, 'shell_open')
            .then((success) {
          if (!success) {
            if (mounted) {
              RouteUtils.showAcrylicDialog(
                  context: context,
                  builder: (dialogContext) =>
                      OpenWithDialog(filePath: widget.file.path));
            }
          }
        });
      }
    }
  }

  void _handleSelection() {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final bool isShiftPressed = keyboard.isShiftPressed;
    final bool isCtrlPressed =
        keyboard.isControlPressed || keyboard.isMetaPressed;

    final bool shouldCtrlSelect = widget.isDesktopMode ? isCtrlPressed : true;

    widget.toggleFileSelection(widget.file.path,
        shiftSelect: isShiftPressed, ctrlSelect: shouldCtrlSelect);
  }

  void _showContextMenu(BuildContext context, Offset globalPosition) {
    try {
      // Check for multiple selection
      try {
        final selectionBloc = context.read<SelectionBloc>();
        final selectionState = selectionBloc.state;

        if (selectionState.allSelectedPaths.length > 1 &&
            selectionState.allSelectedPaths.contains(widget.file.path)) {
          showMultipleFilesContextMenu(
            context: context,
            selectedPaths: selectionState.allSelectedPaths,
            globalPosition: globalPosition,
            onDeleteFiles: widget.onDeleteFiles,
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

      showFileContextMenu(
        context: context,
        file: widget.file,
        fileTags: _fileTags,
        isVideo: isVideo,
        isImage: isImage,
        showAddTagToFileDialog: widget.showAddTagToFileDialog,
        onDeleteFile: widget.onDeleteFile,
        showOpenFileLocation: widget.state.isSearchActive,
        globalPosition: globalPosition,
      );
    } catch (e) {
      debugPrint('Error showing context menu: $e');
      // Fallback
      try {
        showFileContextMenu(
          context: context,
          file: widget.file,
          fileTags: _fileTags,
          isVideo: false,
          isImage: false,
          showAddTagToFileDialog: widget.showAddTagToFileDialog,
          onDeleteFile: widget.onDeleteFile,
          showOpenFileLocation: widget.state.isSearchActive,
          globalPosition: globalPosition,
        );
      } catch (e2) {
        debugPrint('Critical error showing fallback context menu: $e2');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isVideo = FileTypeUtils.isVideoFile(widget.file.path);
    final bool isImage = FileTypeUtils.isImageFile(widget.file.path);
    final bool isBeingCut = ItemInteractionStyle.isBeingCut(widget.file.path);
    final renameController = InlineRenameScope.maybeOf(context);
    final isBeingRenamed = renameController != null &&
        renameController.renamingPath == widget.file.path;

    // Use ValueListenableBuilder for hover and selection state to avoid full rebuilds
    return ValueListenableBuilder<bool>(
      valueListenable: _isHoveringNotifier,
      builder: (context, isHovering, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: _isSelectedNotifier,
          builder: (context, isSelected, _) {
            final Color backgroundColor = ItemInteractionStyle.backgroundColor(
              theme: Theme.of(context),
              isDesktopMode: widget.isDesktopMode,
              isSelected: isSelected,
              isHovering: isHovering,
            );
            // When showItemBackground is false, still show selection/hover
            // highlight but skip the rounded card styling (margin + radius).
            final Color effectiveBackgroundColor = widget.showItemBackground
                ? backgroundColor
                : (isSelected || isHovering)
                    ? backgroundColor
                    : Colors.transparent;

            return RepaintBoundary(
              child: Opacity(
                opacity: isBeingCut ? ItemInteractionStyle.cutOpacity : 1.0,
                child: MouseRegion(
                  onEnter: (_) => _isHoveringNotifier.value = true,
                  onExit: (_) => _isHoveringNotifier.value = false,
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    margin: EdgeInsets.symmetric(
                        horizontal:
                            widget.isDesktopMode && widget.showItemBackground
                                ? 8.0
                                : 0,
                        vertical:
                            widget.isDesktopMode && widget.showItemBackground
                                ? 4.0
                                : 0),
                    decoration: BoxDecoration(
                      color: effectiveBackgroundColor,
                      borderRadius:
                          widget.isDesktopMode && widget.showItemBackground
                              ? BorderRadius.circular(16)
                              : BorderRadius.zero,
                    ),
                    child: Stack(
                      children: [
                        // File content that doesn't need to rebuild on selection changes
                        RepaintBoundary(
                          key: ValueKey('content_${widget.file.path}'),
                          child: _FileItemContent(
                            file: widget.file,
                            fileTags: _fileTags,
                            state: widget.state,
                            showDeleteTagDialog: widget.showDeleteTagDialog,
                            showAddTagToFileDialog:
                                widget.showAddTagToFileDialog,
                            removeTagDirectly: _removeTagDirectly,
                            showFileTags: widget.showFileTags,
                            renameController: renameController,
                            isBeingRenamed: isBeingRenamed,
                          ),
                        ),
                        // Interactive layer cho icon (select)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 80, // Vùng icon + padding
                          child: OptimizedInteractionLayer(
                            onTap: () {
                              // Click vào icon sẽ select item
                              _handleSelection();
                            },
                            onLongPress: !widget.isDesktopMode
                                ? () {
                                    if (!widget.isSelectionMode) {
                                      widget.toggleFileSelection(
                                        widget.file.path,
                                        shiftSelect: false,
                                        ctrlSelect: false,
                                      );
                                    }
                                  }
                                : null,
                          ),
                        ),
                        // Interactive layer cho tên (open)
                        if (!isBeingRenamed)
                          Positioned(
                            key: const ValueKey('name-hit-area'),
                            left: 80,
                            top: 0,
                            right: 0,
                            bottom: 0,
                            child: OptimizedInteractionLayer(
                              onTap: () {
                                if (widget.isDesktopMode) {
                                  _handleSelection();
                                  return;
                                }
                                _openFile(isVideo, isImage);
                              },
                              onDoubleTap: widget.isDesktopMode
                                  ? () {
                                      _handleSelection();
                                      _openFile(isVideo, isImage);
                                    }
                                  : null,
                              onSecondaryTapUp: (details) {
                                _showContextMenu(
                                    context, details.globalPosition);
                              },
                              onLongPressStart: !widget.isDesktopMode
                                  ? (d) {
                                      HapticFeedback.mediumImpact();
                                      _showContextMenu(
                                          context, d.globalPosition);
                                    }
                                  : null,
                            ),
                          ),
                        // Selection indicator. Kept unconditionally in the Stack
                        // so selection only flips a paint property instead of
                        // adding/removing a child. Inserting a Stack child on
                        // every arrow-key press churned the element and render
                        // trees, which on Windows made the engine batch node
                        // creates and destroys into one ui::AXTreeUpdate and log
                        // "Failed to update ui::AXTree, error: <id> will not be
                        // in the tree and is not the new root".
                        Positioned(
                          key: const ValueKey('selection-indicator'),
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 3,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: isSelected &&
                                      (!widget.isDesktopMode ||
                                          !widget.showItemBackground)
                                  ? BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      borderRadius: widget.isDesktopMode
                                          ? const BorderRadius.horizontal(
                                              left: Radius.circular(12),
                                            )
                                          : BorderRadius.zero,
                                    )
                                  : const BoxDecoration(),
                              child: const SizedBox.expand(),
                            ),
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
      },
    );
  }
}

// Content widget that doesn't change with selection
class _FileItemContent extends StatefulWidget {
  final File file;
  final List<String> fileTags;
  final FolderListState state;
  final Function(BuildContext, String, List<String>) showDeleteTagDialog;
  final Function(BuildContext, String) showAddTagToFileDialog;
  final Function(String) removeTagDirectly;
  final bool showFileTags;
  final InlineRenameController? renameController;
  final bool isBeingRenamed;

  const _FileItemContent({
    required this.file,
    required this.fileTags,
    required this.state,
    required this.showDeleteTagDialog,
    required this.showAddTagToFileDialog,
    required this.removeTagDirectly,
    required this.showFileTags,
    required this.renameController,
    required this.isBeingRenamed,
  });

  @override
  State<_FileItemContent> createState() => _FileItemContentState();
}

class _FileItemContentState extends State<_FileItemContent> {
  late Future<Widget> _iconFuture;
  late Future<FileStat> _fileStatFuture;

  // Static cache for file stats to avoid repeated calls
  static final Map<String, FileStat> _fileStatCache = <String, FileStat>{};
  static const int _maxCacheSize = 100;

  @override
  void initState() {
    super.initState();

    // Simple approach: load icon immediately but skip file stats for network files
    _iconFuture = FileIconHelper.getIconForFile(widget.file);

    // Skip file stat for network files completely to avoid lag
    if (widget.file.path.startsWith('#network/')) {
      _fileStatFuture = Future.error('Network file - no stat needed');
    } else {
      _fileStatFuture = _getFileStatLazy();
    }
  }

  Future<FileStat> _getFileStatLazy() async {
    final path = widget.file.path;

    // Check cache first
    if (_fileStatCache.containsKey(path)) {
      return _fileStatCache[path]!;
    }

    // Add a longer delay for better UI responsiveness
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final stat = await widget.file.stat();

      // Add to cache, but limit cache size
      if (_fileStatCache.length >= _maxCacheSize) {
        final firstKey = _fileStatCache.keys.first;
        _fileStatCache.remove(firstKey);
      }
      _fileStatCache[path] = stat;

      return stat;
    } catch (e) {
      rethrow; // Let the FutureBuilder handle the error
    }
  }

  @override
  void didUpdateWidget(_FileItemContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file.path != oldWidget.file.path) {
      _iconFuture = FileIconHelper.getIconForFile(widget.file);

      // Skip file stat for network files completely to avoid lag
      if (widget.file.path.startsWith('#network/')) {
        _fileStatFuture = Future.error('Network file - no stat needed');
      } else {
        _fileStatFuture = _getFileStatLazy();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isVideo = FileTypeUtils.isVideoFile(widget.file.path);
    final bool isImage = FileTypeUtils.isImageFile(widget.file.path);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      child: Row(
        children: [
          _buildThumbnail(isVideo, isImage),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildName(context),
                const SizedBox(height: 4),
                _buildFileDetails(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(bool isVideo, bool isImage) {
    // Always use ThumbnailLoader for all files (network and local)
    return RepaintBoundary(
      child: SizedBox(
        width: 48,
        height: 48,
        child: isVideo || isImage
            ? ValueListenableBuilder<FileThumbnailFitMode>(
                valueListenable: UserPreferences.instance.fileThumbnailFitMode,
                builder: (context, fitMode, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(16.0),
                  child: ThumbnailLoader(
                    filePath: widget.file.path,
                    isVideo: isVideo,
                    isImage: isImage,
                    width: 48,
                    height: 48,
                    fit: fitMode == FileThumbnailFitMode.contain
                        ? BoxFit.contain
                        : BoxFit.cover,
                    borderRadius: BorderRadius.circular(16.0),
                    fallbackBuilder: () {
                      final theme = Theme.of(context);
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16.0),
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                        ),
                        child: Icon(
                          isVideo
                              ? PhosphorIconsLight.videoCamera
                              : PhosphorIconsLight.image,
                          size: 36,
                          color: theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ),
              )
            : FutureBuilder<Widget>(
                future: _iconFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return snapshot.data!;
                  }
                  final theme = Theme.of(context);
                  return Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16.0),
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                    ),
                    child: Icon(
                      PhosphorIconsLight.file,
                      size: 36,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildFileDetails(BuildContext context) {
    // Prefer WebDAV metadata when available
    try {
      final service = StreamingHelper.instance.currentNetworkService;
      if (service is WebDAVService) {
        final remotePath = service.getRemotePathFromLocal(widget.file.path);
        if (remotePath != null) {
          final meta = service.getMeta(remotePath);
          if (meta != null) {
            final sizeText =
                meta.size >= 0 ? FileUtils.formatFileSize(meta.size) : '--';
            final modifiedText = meta.modified.toString().split('.').first;
            return Row(
              children: [
                Text(sizeText, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 12),
                Icon(PhosphorIconsLight.calendar,
                    size: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(modifiedText,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            );
          }
        }
      } else if (service is FTPService) {
        // For FTP, we keyed meta by UI path directly
        final meta = service.getMeta(widget.file.path);
        if (meta != null) {
          final sizeText =
              meta.size >= 0 ? FileUtils.formatFileSize(meta.size) : '--';
          final modifiedText =
              (meta.modified ?? DateTime.now()).toString().split('.').first;
          return Row(
            children: [
              Text(sizeText, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 12),
              Icon(PhosphorIconsLight.calendar,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(modifiedText, style: Theme.of(context).textTheme.bodySmall),
            ],
          );
        }
      }
    } catch (_) {}

    // Calculate approximate available width for tags
    // File size text ~100px, icon button ~48px, spacing ~32px, bookmark icon ~20px
    final screenWidth = MediaQuery.of(context).size.width;
    final approximateAvailableWidth =
        screenWidth * 0.6 - 200; // Conservative estimate

    // Estimate tag chip width: each character ~8px + padding ~20px
    int totalTagWidth = 0;
    final List<String> tagsToShow = [];

    // Sort tags by length to prioritize shorter tags that fit better
    final sortedTags = List<String>.from(widget.fileTags)
      ..sort((a, b) => a.length.compareTo(b.length));

    // Determine how many tags can fit
    for (final tag in sortedTags) {
      final estimatedWidth =
          tag.length * 8 + 40; // Character width + padding and icon
      if (totalTagWidth + estimatedWidth <= approximateAvailableWidth) {
        totalTagWidth += estimatedWidth;
        tagsToShow.add(tag);
      } else {
        break;
      }
    }

    // Limit to max 3 tags for aesthetics
    if (tagsToShow.length > 3) {
      tagsToShow.length = 3;
    }

    return Row(
      children: [
        FutureBuilder<FileStat>(
          future: _fileStatFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final size = snapshot.data!.size;
              return Text(FileUtils.formatFileSize(size),
                  style: Theme.of(context).textTheme.bodySmall);
            } else if (snapshot.hasError) {
              // For network files or files with stat errors
              if (widget.file.path.startsWith('#network/')) {
                return Text(AppLocalizations.of(context)!.networkFile,
                    style: Theme.of(context).textTheme.bodySmall);
              }
              return Text('--', style: Theme.of(context).textTheme.bodySmall);
            }

            return Text('...', style: Theme.of(context).textTheme.bodySmall);
          },
        ),
        if (widget.showFileTags && widget.fileTags.isNotEmpty) ...[
          const SizedBox(width: 16),
          Icon(PhosphorIconsLight.bookmark,
              size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          if (tagsToShow.isEmpty)
            // If no tags fit, show count
            Text(
              AppLocalizations.of(context)!.tagCount(widget.fileTags.length),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          else if (tagsToShow.length == widget.fileTags.length)
            // All tags fit, show them
            Flexible(
              child: Wrap(
                spacing: 4,
                children: tagsToShow
                    .map((tag) => TagChip(
                          tag: tag,
                          isCompact: true,
                          onTap: () {
                            final bloc = BlocProvider.of<FolderListBloc>(
                                context,
                                listen: false);
                            bloc.add(SearchByTag(tag));
                          },
                          onDeleted: () => widget.removeTagDirectly(tag),
                        ))
                    .toList(),
              ),
            )
          else
            // Some tags fit, show them + count of remaining
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...tagsToShow.map((tag) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: TagChip(
                          tag: tag,
                          isCompact: true,
                          onTap: () {
                            final bloc = BlocProvider.of<FolderListBloc>(
                                context,
                                listen: false);
                            bloc.add(SearchByTag(tag));
                          },
                          onDeleted: () => widget.removeTagDirectly(tag),
                        ),
                      )),
                  Text(
                    '+${widget.fileTags.length - tagsToShow.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildName(BuildContext context) {
    if (widget.isBeingRenamed &&
        widget.renameController != null &&
        widget.renameController!.textController != null) {
      return InlineRenameField(
        controller: widget.renameController!,
        onCommit: () => widget.renameController!.commitRename(context),
        onCancel: () => widget.renameController!.cancelRename(),
        textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
        textAlign: TextAlign.start,
        maxLines: 1,
      );
    }

    return Text(
      _getDisplayName(widget.file),
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _getDisplayName(File file) {
    // Archive entries live behind a virtual path; show the entry name.
    final archiveEntryName = ArchivePathUtils.entryDisplayName(file.path);
    if (archiveEntryName != null) return archiveEntryName;
    // For network files, extract just the filename from the path
    if (file.path.startsWith('#network/')) {
      final parts = file.path.split('/');
      return parts.last; // Return just the filename
    }
    // For local files, use the standard method
    return file.path.split(Platform.pathSeparator).last;
  }
}
