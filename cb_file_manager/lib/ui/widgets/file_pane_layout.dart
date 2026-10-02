import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'file_pane_layout_model.dart';

export 'file_pane_layout_model.dart';

/// Shared across folder tabs. Writes are serialized so a slow earlier save
/// cannot overwrite the last drag; an initial read never overwrites user input.
class FilePaneLayoutController extends ValueNotifier<FilePaneLayoutNode> {
  FilePaneLayoutController({
    FilePaneLayoutNode? initial,
    Future<String> Function()? read,
    Future<bool> Function(String)? write,
  }) : _read = read ?? UserPreferences.instance.getFilePaneLayout,
       _write = write ?? UserPreferences.instance.setFilePaneLayout,
       super(initial ?? FilePaneLayoutNode.defaults);

  static final instance = FilePaneLayoutController();
  Future<void>? _loading;
  Future<void> _saving = Future.value();
  bool _touched = false;
  final Future<String> Function() _read;
  final Future<bool> Function(String) _write;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final encoded = await _read();
      if (!_touched) value = FilePaneLayoutNode.decode(encoded);
    } catch (error) {
      debugPrint('Could not load file pane layout: $error');
    }
  }

  void update(FilePaneLayoutNode layout, {bool persist = true}) {
    _touched = true;
    value = layout;
    if (persist) {
      final encoded = layout.encode();
      _saving = _saving.then((_) async {
        try {
          if (!await _write(encoded)) {
            debugPrint('Could not save file pane layout');
          }
        } catch (error) {
          debugPrint('Could not save file pane layout: $error');
        }
      });
    }
  }
}

class FilePaneLayout extends StatefulWidget {
  const FilePaneLayout({
    super.key,
    required this.files,
    required this.preview,
    required this.properties,
    required this.previewVisible,
    required this.propertiesVisible,
    required this.previewWidth,
    required this.propertiesHeight,
    this.controller,
    this.listFocusNode,
    this.previewFocusNode,
  });

  final Widget files;
  final Widget preview;
  final Widget properties;
  final bool previewVisible;
  final bool propertiesVisible;
  final double previewWidth;
  final double propertiesHeight;
  final FilePaneLayoutController? controller;
  final FocusNode? listFocusNode;
  final FocusNode? previewFocusNode;

  @override
  State<FilePaneLayout> createState() => _FilePaneLayoutState();
}

class _FilePaneLayoutState extends State<FilePaneLayout> {
  final _owner = Object();
  final _keys = {for (final p in FilePane.values) p: GlobalKey()};
  FilePane? _dragging;
  FilePaneLayoutController get _controller =>
      widget.controller ?? FilePaneLayoutController.instance;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) unawaited(_controller.load());
  }

  void _change(FilePaneLayoutNode layout) =>
      _controller.update(layout, persist: widget.controller == null);

  Widget _pane(FilePane pane) {
    final l10n = AppLocalizations.of(context)!;
    Widget content = switch (pane) {
      FilePane.files => Column(
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                const FilePaneDragHandle(pane: FilePane.files),
                Expanded(
                  child: Text(
                    l10n.files,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                IconButton(
                  key: const ValueKey('file-pane-layout-reset'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  iconSize: 16,
                  tooltip: l10n.resetFilePaneLayout,
                  onPressed: () => _change(FilePaneLayoutNode.defaults),
                  icon: const Icon(Icons.reset_tv),
                ),
              ],
            ),
          ),
          Expanded(child: widget.files),
        ],
      ),
      FilePane.preview => widget.preview,
      FilePane.properties => widget.properties,
    };
    if (pane == FilePane.preview && widget.previewFocusNode != null) {
      content = Focus(
        focusNode: widget.previewFocusNode,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            widget.listFocusNode?.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          onPointerDown: (_) => scheduleMicrotask(() {
            if (mounted && !widget.previewFocusNode!.hasFocus) {
              widget.previewFocusNode!.requestFocus();
            }
          }),
          child: content,
        ),
      );
    }
    return _PaneDropTarget(
      owner: _owner,
      pane: pane,
      dragging: _dragging,
      onDock: (moving, edge) =>
          _change(_controller.value.dock(moving, pane, edge)),
      child: KeyedSubtree(
        key: _keys[pane],
        child: RepaintBoundary(child: content),
      ),
    );
  }

  Widget _tree(FilePaneLayoutNode node) {
    if (node.pane != null) return _pane(node.pane!);
    return _PaneSplit(
      key: ValueKey('split-${node.splitId}'),
      node: node,
      previewWidth: widget.previewWidth,
      propertiesHeight: widget.propertiesHeight,
      onResize: (ratio) =>
          _change(_controller.value.resize(node.splitId, ratio)),
      first: _tree(node.first!),
      second: _tree(node.second!),
    );
  }

  @override
  Widget build(BuildContext context) => _PaneDragScope(
    owner: _owner,
    onDrag: (pane) {
      if (mounted) setState(() => _dragging = pane);
    },
    child: ValueListenableBuilder<FilePaneLayoutNode>(
      valueListenable: _controller,
      builder: (context, layout, _) => LayoutBuilder(
        builder: (context, size) {
          // Preserve saved geometry while making short/narrow windows usable.
          final shown = {
            FilePane.files,
            if (widget.previewVisible) FilePane.preview,
            if (widget.propertiesVisible) FilePane.properties,
          };
          var visible = layout.visible(shown)!;
          for (final auxiliary in [FilePane.properties, FilePane.preview]) {
            final minimum = visible.minimumSize;
            if (minimum.width > size.maxWidth ||
                minimum.height > size.maxHeight) {
              shown.remove(auxiliary);
              visible = layout.visible(shown)!;
            }
          }
          return _tree(visible);
        },
      ),
    ),
  );
}

class _PaneDrag {
  const _PaneDrag(this.owner, this.pane);
  final Object owner;
  final FilePane pane;
}

class _PaneDragScope extends InheritedWidget {
  const _PaneDragScope({
    required this.owner,
    required this.onDrag,
    required super.child,
  });
  final Object owner;
  final ValueChanged<FilePane?> onDrag;
  @override
  bool updateShouldNotify(_PaneDragScope oldWidget) => owner != oldWidget.owner;
}

/// Only this grip starts a pane drag: file drag/drop and preview interactions
/// retain their existing gestures.
class FilePaneDragHandle extends StatelessWidget {
  const FilePaneDragHandle({super.key, required this.pane});
  final FilePane pane;
  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_PaneDragScope>();
    if (scope == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final title = switch (pane) {
      FilePane.files => l10n.files,
      FilePane.preview => l10n.previewPaneTitle,
      FilePane.properties => l10n.propertiesAndTags,
    };
    return Tooltip(
      message: l10n.dragFilePane,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<_PaneDrag>(
          key: ValueKey('file-pane-drag-${pane.name}'),
          data: _PaneDrag(scope.owner, pane),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          maxSimultaneousDrags: 1,
          onDragStarted: () => scope.onDrag(pane),
          onDragEnd: (_) => scope.onDrag(null),
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(title),
            ),
          ),
          child: Semantics(
            label: '$title: ${l10n.dragFilePane}',
            child: const SizedBox(
              width: 28,
              height: 28,
              child: Icon(Icons.drag_indicator, size: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneDropTarget extends StatefulWidget {
  const _PaneDropTarget({
    required this.owner,
    required this.pane,
    required this.dragging,
    required this.onDock,
    required this.child,
  });
  final Object owner;
  final FilePane pane;
  final FilePane? dragging;
  final void Function(FilePane, FilePaneEdge) onDock;
  final Widget child;
  @override
  State<_PaneDropTarget> createState() => _PaneDropTargetState();
}

class _PaneDropTargetState extends State<_PaneDropTarget> {
  FilePaneEdge? _edge;
  FilePaneEdge _edgeAt(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    final point = box.globalToLocal(global);
    final x = point.dx / box.size.width;
    final y = point.dy / box.size.height;
    final distances = [x, 1 - x, y, 1 - y];
    final min = distances.reduce(math.min);
    return FilePaneEdge.values[distances.indexOf(min)];
  }

  @override
  Widget build(BuildContext context) => DragTarget<_PaneDrag>(
    onWillAcceptWithDetails: (details) =>
        identical(details.data.owner, widget.owner) &&
        details.data.pane != widget.pane,
    onMove: (details) => setState(() => _edge = _edgeAt(details.offset)),
    onLeave: (_) => setState(() => _edge = null),
    onAcceptWithDetails: (details) {
      widget.onDock(details.data.pane, _edgeAt(details.offset));
      setState(() => _edge = null);
    },
    builder: (context, candidates, _) => Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.dragging != null && widget.dragging != widget.pane)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .35),
                ),
              ),
            ),
          ),
        if (candidates.isNotEmpty && _edge != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: switch (_edge!) {
                  FilePaneEdge.left => Alignment.centerLeft,
                  FilePaneEdge.right => Alignment.centerRight,
                  FilePaneEdge.top => Alignment.topCenter,
                  FilePaneEdge.bottom => Alignment.bottomCenter,
                },
                child: FractionallySizedBox(
                  widthFactor:
                      _edge == FilePaneEdge.left || _edge == FilePaneEdge.right
                      ? .5
                      : 1,
                  heightFactor:
                      _edge == FilePaneEdge.top || _edge == FilePaneEdge.bottom
                      ? .5
                      : 1,
                  child: ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .2),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _PaneSplit extends StatefulWidget {
  const _PaneSplit({
    super.key,
    required this.node,
    required this.previewWidth,
    required this.propertiesHeight,
    required this.onResize,
    required this.first,
    required this.second,
  });
  final FilePaneLayoutNode node;
  final double previewWidth;
  final double propertiesHeight;
  final ValueChanged<double> onResize;
  final Widget first;
  final Widget second;
  @override
  State<_PaneSplit> createState() => _PaneSplitState();
}

class _PaneSplitState extends State<_PaneSplit> {
  double? _dragExtent;
  bool _hover = false;
  bool _cancelled = false;
  double _minimum(FilePaneLayoutNode node, Axis axis) {
    final minimum = node.minimumSize;
    return axis == Axis.horizontal ? minimum.width : minimum.height;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final horizontal = widget.node.axis == Axis.horizontal;
      final available = math.max(
        0.0,
        (horizontal ? size.maxWidth : size.maxHeight) - 6,
      );
      final minA = _minimum(widget.node.first!, widget.node.axis!);
      final minB = _minimum(widget.node.second!, widget.node.axis!);
      final scale = math.min(1.0, available / (minA + minB));
      final lower = minA * scale;
      final upper = available - minB * scale;
      final defaultTrailing = horizontal
          ? widget.previewWidth
          : widget.propertiesHeight;
      final extent =
          (_dragExtent ??
                  (widget.node.ratio == null
                      ? available -
                            math.min(
                              defaultTrailing,
                              available / (horizontal ? 1.25 : 2),
                            )
                      : available * widget.node.ratio!))
              .clamp(lower, math.max(lower, upper))
              .toDouble();
      final accent = Theme.of(context).colorScheme.primary;
      final handle = MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpDown,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Listener(
          onPointerCancel: (_) {
            _cancelled = true;
            setState(() => _dragExtent = null);
          },
          child: GestureDetector(
            key: ValueKey('file-pane-resize-${widget.node.splitId}'),
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (_) => setState(() {
              _cancelled = false;
              _dragExtent = extent;
            }),
            onPanUpdate: (details) {
              final next =
                  ((_dragExtent ?? extent) +
                          (horizontal ? details.delta.dx : details.delta.dy))
                      .clamp(lower, math.max(lower, upper))
                      .toDouble();
              if (next == _dragExtent) return;
              // setState coalesces pointer updates into the next frame. Keep
              // transient sizing local to this split: its child widgets stay
              // mounted, and other tabs/storage only update on release.
              setState(() => _dragExtent = next);
            },
            onPanEnd: (_) {
              if (!_cancelled && _dragExtent != null && available > 0) {
                widget.onResize(_dragExtent! / available);
              }
              setState(() => _dragExtent = null);
            },
            onPanCancel: () => setState(() => _dragExtent = null),
            child: SizedBox(
              width: horizontal ? 6 : null,
              height: horizontal ? null : 6,
              child: Center(
                child: Container(
                  width: horizontal ? 2 : null,
                  height: horizontal ? null : 2,
                  color: _hover || _dragExtent != null
                      ? accent.withValues(alpha: .7)
                      : Theme.of(context).dividerColor.withValues(alpha: .3),
                ),
              ),
            ),
          ),
        ),
      );
      return Flex(
        direction: widget.node.axis!,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: horizontal ? extent : null,
            height: horizontal ? null : extent,
            child: widget.first,
          ),
          handle,
          Expanded(child: widget.second),
        ],
      );
    },
  );
}
