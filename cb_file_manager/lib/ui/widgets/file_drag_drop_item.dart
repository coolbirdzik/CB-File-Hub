import 'dart:io';

import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Shared drag source and folder drop target for every file-view layout.
class FileDragDropItem extends StatefulWidget {
  const FileDragDropItem({
    super.key,
    required this.path,
    required this.isFolder,
    required this.selectedPaths,
    required this.child,
    this.onStartFileDrag,
    this.onMoveItemsToFolder,
  });

  final String path;
  final bool isFolder;
  final Set<String> selectedPaths;
  final Widget child;
  final ValueChanged<List<String>>? onStartFileDrag;
  final Future<void> Function(List<String>, String)? onMoveItemsToFolder;

  @override
  State<FileDragDropItem> createState() => _FileDragDropItemState();

  /// Native Windows drops and Flutter drags hit the same rendered folder.
  /// [position] is in Flutter view logical coordinates, not screen pixels.
  static String? folderAt(BuildContext context, Offset position) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      position,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is _FolderDropPath) {
        return (target.metaData as _FolderDropPath).path;
      }
    }
    return null;
  }
}

class _FileDragDropItemState extends State<FileDragDropItem> {
  int? _pointer;
  List<String> _payload = const [];
  bool _handedToWindows = false;

  void _updateDrag(DragUpdateDetails details) {
    if (_handedToWindows || widget.onStartFileDrag == null) return;
    final view = View.of(context);
    final bounds = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    if (bounds.contains(details.globalPosition)) return;
    // Keep in-app moves in Flutter. OLE takes over only on leaving the view;
    // starting it immediately lets desktop_drop's child HWND swallow drops.
    _handedToWindows = true;
    final paths = _payload;
    if (_pointer != null) GestureBinding.instance.cancelPointer(_pointer!);
    widget.onStartFileDrag!(paths);
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    final selectedPaths = widget.selectedPaths;
    final child = widget.child;
    final payload = selectedPaths.contains(path)
        ? <String>[
            path,
            ...selectedPaths.where((selectedPath) => selectedPath != path),
          ]
        : <String>[path];
    final draggable = Draggable<List<String>>(
      data: payload,
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _FileDragFeedback(
        path: path,
        isFolder: widget.isFolder,
        itemCount: payload.length,
      ),
      childWhenDragging: Opacity(opacity: 0.55, child: child),
      onDragStarted: () {
        _payload = payload;
        _handedToWindows = false;
      },
      onDragUpdate: _updateDrag,
      child: child,
    );
    final source = Listener(
      onPointerDown: (event) => _pointer = event.pointer,
      child: draggable,
    );
    if (!widget.isFolder ||
        widget.onMoveItemsToFolder == null ||
        path.startsWith('#')) {
      return source;
    }
    return MetaData(
      metaData: _FolderDropPath(path),
      behavior: HitTestBehavior.translucent,
      child: DragTarget<List<String>>(
        onWillAcceptWithDetails: (details) =>
            details.data.isNotEmpty &&
            !details.data.any(
              (source) => p.equals(source, path) || p.isWithin(source, path),
            ),
        onAcceptWithDetails: (details) =>
            widget.onMoveItemsToFolder!(details.data, path),
        builder: (context, candidates, _) => DecoratedBox(
          decoration: BoxDecoration(
            border: candidates.isEmpty
                ? null
                : Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: source,
        ),
      ),
    );
  }
}

class _FileDragFeedback extends StatelessWidget {
  const _FileDragFeedback({
    required this.path,
    required this.isFolder,
    required this.itemCount,
  });

  final String path;
  final bool isFolder;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = p.extension(path).toLowerCase();
    final category = FileTypeRegistry.getCategory(extension);
    final typeLabel = isFolder
        ? 'Folder'
        : switch (category) {
            FileCategory.video => 'Video',
            FileCategory.image => 'Image',
            _ =>
              extension.isEmpty ? 'File' : extension.substring(1).toUpperCase(),
          };

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('file-drag-feedback'),
        width: 240,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _buildPreview(theme, category),
                if (itemCount > 1)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      key: const ValueKey('file-drag-count'),
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$itemCount',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basename(path),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    itemCount > 1 ? '$itemCount items' : typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme, FileCategory category) {
    if (isFolder) {
      return _iconPreview(
        theme,
        PhosphorIconsFill.folder,
        theme.colorScheme.primary,
      );
    }

    final cachedPath = ThumbnailWidgetCache().getCachedThumbnailPath(path);
    final previewPath = cachedPath != null && File(cachedPath).existsSync()
        ? cachedPath
        : category == FileCategory.image && File(path).existsSync()
        ? path
        : null;
    if (previewPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.file(
          File(previewPath),
          key: const ValueKey('file-drag-thumbnail'),
          width: 56,
          height: 56,
          cacheWidth: 160,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _typeIconPreview(theme, category),
        ),
      );
    }
    return _typeIconPreview(theme, category);
  }

  Widget _typeIconPreview(ThemeData theme, FileCategory category) {
    return _iconPreview(
      theme,
      category == FileCategory.video
          ? PhosphorIconsFill.videoCamera
          : FileTypeRegistry.getIcon(p.extension(path).toLowerCase()),
      FileTypeRegistry.getColor(p.extension(path).toLowerCase()),
    );
  }

  Widget _iconPreview(ThemeData theme, IconData icon, Color color) {
    return Container(
      key: const ValueKey('file-drag-type-icon'),
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.18),
          theme.colorScheme.surfaceContainerHighest,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 30, color: color),
    );
  }
}

class _FolderDropPath {
  const _FolderDropPath(this.path);
  final String path;
}
