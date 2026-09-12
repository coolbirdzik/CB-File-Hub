import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;

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
        ? selectedPaths.toList(growable: false)
        : <String>[path];
    final draggable = Draggable<List<String>>(
      data: payload,
      maxSimultaneousDrags: 1,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            payload.length == 1
                ? p.basename(payload.first)
                : '${payload.length} items',
            style: const TextStyle(color: Colors.white, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
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

class _FolderDropPath {
  const _FolderDropPath(this.path);
  final String path;
}
