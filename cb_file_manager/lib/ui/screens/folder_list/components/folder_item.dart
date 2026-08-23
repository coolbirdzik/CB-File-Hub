import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';
import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import '../../../components/common/shared_file_context_menu.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../bloc/selection/selection_bloc.dart';
import '../../../../bloc/selection/selection_event.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/components/tag_context_menu.dart';
import '../../../utils/item_interaction_style.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';
import 'package:cb_file_manager/helpers/files/lazy_path_size_calculator.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

class FolderItem extends StatefulWidget {
  final Directory folder;
  final Function(String)? onTap;
  final bool isSelected;
  final Function(String, {bool shiftSelect, bool ctrlSelect})?
      toggleFolderSelection;
  final bool isDesktopMode;
  final String? lastSelectedPath;
  final Function()? clearSelectionMode;
  final bool showItemBackground;

  const FolderItem({
    Key? key,
    required this.folder,
    this.onTap,
    this.isSelected = false,
    this.toggleFolderSelection,
    this.isDesktopMode = false,
    this.lastSelectedPath,
    this.clearSelectionMode,
    this.showItemBackground = true,
  }) : super(key: key);

  @override
  State<FolderItem> createState() => _FolderItemState();
}

class _FolderItemState extends State<FolderItem> {
  // Use ValueNotifier for hover state to reduce rebuilds
  final ValueNotifier<bool> _isHovering = ValueNotifier<bool>(false);

  // Lazy, cached folder stat to avoid I/O during fast scrolls
  late Future<FileStat> _folderStatFuture;
  late Future<int?> _folderSizeFuture;
  int _folderSizeGeneration = 0;
  static final Map<String, FileStat> _folderStatCache = <String, FileStat>{};
  static const int _maxCacheSize = 100;

  /// Tag name when this "folder" is actually a child tag (path `#search?tag=`),
  /// otherwise null. A tag behaves like a folder in the results grid/list.
  String? get _tagName => UriUtils.extractTagFromSearchPath(widget.folder.path);

  @override
  void initState() {
    super.initState();
    _folderStatFuture = _getFolderStatLazy();
    _folderSizeFuture = _getFolderSizeLazy();
  }

  @override
  void dispose() {
    _folderSizeGeneration++;
    _isHovering.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FolderItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder.path != widget.folder.path) {
      _folderSizeGeneration++;
      _folderStatFuture = _getFolderStatLazy();
      _folderSizeFuture = _getFolderSizeLazy();
    }
  }

  Future<FileStat> _getFolderStatLazy() async {
    final path = widget.folder.path;

    // Skip stat for virtual network / tag / archive paths to prevent errors and jank
    if (path.startsWith('#network/') ||
        path.startsWith('#search') ||
        ArchivePathUtils.isArchiveBrowsePath(path)) {
      return Future.error('Virtual folder - no stat needed');
    }

    // Serve from cache if available
    final cached = _folderStatCache[path];
    if (cached != null) return cached;

    // Small delay to prioritize smooth scrolling
    await Future.delayed(const Duration(milliseconds: 100));

    final stat = await widget.folder.stat();
    // Cache with simple size cap
    if (_folderStatCache.length >= _maxCacheSize) {
      _folderStatCache.remove(_folderStatCache.keys.first);
    }
    _folderStatCache[path] = stat;
    return stat;
  }

  Future<int?> _getFolderSizeLazy() async {
    final path = widget.folder.path;
    final generation = _folderSizeGeneration;
    if (path.startsWith('#network/') || path.startsWith('#search')) {
      return null;
    }
    return LazyPathSizeCalculator.calculateDirectory(
      path,
      isCancelled: () => !mounted || generation != _folderSizeGeneration,
    );
  }

  /// Leading icon: for a child-tag "folder" show its thumbnail (or a
  /// color-tinted tag placeholder); otherwise the standard folder icon.
  Widget _buildLeadingIcon(BuildContext context) {
    final tagName = _tagName;
    if (tagName != null) {
      final tagColor = TagColorManager.instance.getTagColor(tagName);
      final thumbnailPath =
          TagThumbnailManager.instance.getThumbnailSync(tagName);
      if (thumbnailPath != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16.0),
          child: Image.file(
            File(thumbnailPath),
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildTagIconPlaceholder(tagColor),
          ),
        );
      }
      return _buildTagIconPlaceholder(tagColor);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Center(
        child: Icon(
          PhosphorIconsLight.folder,
          color: Theme.of(context).colorScheme.primary,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildTagIconPlaceholder(Color tagColor) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tagColor.withValues(alpha: 0.55),
            tagColor.withValues(alpha: 0.22),
          ],
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Center(
        child: Icon(
          PhosphorIconsLight.tag,
          color: Colors.white.withValues(alpha: 0.85),
          size: 26,
        ),
      ),
    );
  }

  void _handleFolderSelection() {
    if (widget.toggleFolderSelection == null) return;

    // Check for Shift and Ctrl keys
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final bool isShiftPressed = keyboard.isShiftPressed;
    final bool isCtrlPressed =
        keyboard.isControlPressed || keyboard.isMetaPressed;

    // On desktop, a plain click selects only the clicked item (clearing the
    // previous selection); Ctrl+click adds/toggles it. Mirror the file item
    // behavior here — using `lastSelectedPath != null` made every click after
    // the first behave like a Ctrl+click, so the old selection was never
    // cleared.
    final bool shouldCtrlSelect = widget.isDesktopMode ? isCtrlPressed : true;

    // Call toggleFolderSelection with appropriate parameters
    widget.toggleFolderSelection!(widget.folder.path,
        shiftSelect: isShiftPressed, ctrlSelect: shouldCtrlSelect);
  }

  void _showFolderContextMenu(BuildContext context, Offset? globalPosition) {
    // A tag rendered as a folder-like card uses the tag context menu, not the
    // filesystem folder menu.
    final tagName = _tagName;
    if (tagName != null) {
      showTagContextMenu(
        context,
        tagName,
        globalPosition: globalPosition,
      );
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
      onNavigate: widget.onTap,
      folderTags: [], // Pass empty tags or fetch from database in real implementation
      globalPosition: globalPosition, // Pass position for desktop popup menu
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isBeingCut = ItemInteractionStyle.isBeingCut(widget.folder.path);
    final renameController = InlineRenameScope.maybeOf(context);
    final isBeingRenamed = renameController != null &&
        renameController.renamingPath == widget.folder.path;

    return ValueListenableBuilder<bool>(
      valueListenable: _isHovering,
      builder: (context, isHovering, _) {
        final Color backgroundColor = ItemInteractionStyle.backgroundColor(
          theme: Theme.of(context),
          isDesktopMode: widget.isDesktopMode,
          isSelected: widget.isSelected,
          isHovering: isHovering,
        );
        final Color effectiveBackgroundColor =
            widget.showItemBackground ? backgroundColor : Colors.transparent;

        return Opacity(
          opacity: isBeingCut ? ItemInteractionStyle.cutOpacity : 1.0,
          child: GestureDetector(
            onSecondaryTapDown: (details) =>
                _showFolderContextMenu(context, details.globalPosition),
            child: MouseRegion(
              onEnter: (_) => _isHovering.value = true,
              onExit: (_) => _isHovering.value = false,
              cursor: SystemMouseCursors.click,
              child: Container(
                margin: EdgeInsets.symmetric(
                    horizontal:
                        widget.isDesktopMode && widget.showItemBackground
                            ? 8.0
                            : 0,
                    vertical: widget.isDesktopMode && widget.showItemBackground
                        ? 4.0
                        : 0),
                decoration: BoxDecoration(
                  color: effectiveBackgroundColor,
                  borderRadius:
                      widget.isDesktopMode && widget.showItemBackground
                          ? BorderRadius.circular(16.0)
                          : BorderRadius.zero,
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12.0, horizontal: 16.0),
                      child: Row(
                        children: [
                          _buildLeadingIcon(context),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                isBeingRenamed &&
                                        renameController.textController != null
                                    ? InlineRenameField(
                                        controller: renameController,
                                        onCommit: () => renameController
                                            .commitRename(context),
                                        onCancel: () =>
                                            renameController.cancelRename(),
                                        textStyle: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                        textAlign: TextAlign.start,
                                        maxLines: 1,
                                      )
                                    : Text(
                                        _tagName ?? widget.folder.basename(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                const SizedBox(height: 4),
                                if (_tagName != null)
                                  Text(
                                    AppLocalizations.of(context)!.tagPrefix,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.7),
                                        ),
                                  )
                                else
                                  FutureBuilder<FileStat>(
                                    future: _folderStatFuture,
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        return FutureBuilder<int?>(
                                          future: _folderSizeFuture,
                                          builder: (context, sizeSnapshot) {
                                            final modified = snapshot
                                                .data!.modified
                                                .toString()
                                                .split('.')[0];
                                            final size = sizeSnapshot.data;
                                            final suffix = sizeSnapshot
                                                        .connectionState ==
                                                    ConnectionState.waiting
                                                ? '  •  Calculating size...'
                                                : size == null
                                                    ? ''
                                                    : '  •  ${FormatUtils.formatFileSize(size)}';
                                            return Text(
                                              '$modified$suffix',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                        .withValues(alpha: 0.7),
                                                  ),
                                            );
                                          },
                                        );
                                      } else if (snapshot.hasError) {
                                        // For network folders or stat errors
                                        return Text(
                                          '—',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.5),
                                              ),
                                        );
                                      }
                                      return Text(
                                        'Loading...',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
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
                          if (widget.toggleFolderSelection != null) {
                            _handleFolderSelection();
                          }
                        },
                        onLongPress: !widget.isDesktopMode
                            ? () {
                                if (widget.toggleFolderSelection != null) {
                                  _handleFolderSelection();
                                }
                              }
                            : null,
                        onTertiaryTapUp: (_) {
                          context
                              .read<TabManagerBloc>()
                              .add(AddTab(path: widget.folder.path));
                        },
                      ),
                    ),
                    // Interactive layer cho tên (navigate)
                    if (!isBeingRenamed)
                      Positioned(
                        key: const ValueKey('name-hit-area'),
                        left: 80,
                        top: 0,
                        right: 0,
                        bottom: 0,
                        child: OptimizedInteractionLayer(
                          onTap: () {
                            if (widget.isDesktopMode &&
                                widget.toggleFolderSelection != null) {
                              _handleFolderSelection();
                              return;
                            }

                            if (widget.onTap != null) {
                              widget.onTap!(widget.folder.path);
                            }
                          },
                          onDoubleTap: widget.isDesktopMode
                              ? () {
                                  if (widget.clearSelectionMode != null) {
                                    widget.clearSelectionMode!();
                                  }
                                  widget.onTap?.call(widget.folder.path);
                                }
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
                    // Selection indicator. Kept unconditionally in the Stack so
                    // selection only flips a paint property instead of adding or
                    // removing a child (see file_item.dart for the AXTree
                    // rationale).
                    Positioned(
                      key: const ValueKey('selection-indicator'),
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 3,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: widget.isSelected
                              ? BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
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
  }
}
