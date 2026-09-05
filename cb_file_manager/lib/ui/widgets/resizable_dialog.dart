import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cb_file_manager/utils/app_logger.dart';

/// Which edges a resize handle drives.
class _ResizeEdge {
  const _ResizeEdge({
    this.left = false,
    this.top = false,
    this.right = false,
    this.bottom = false,
  });

  final bool left;
  final bool top;
  final bool right;
  final bool bottom;

  SystemMouseCursor get cursor {
    final horizontal = left || right;
    final vertical = top || bottom;
    if (horizontal && vertical) {
      final isMainDiagonal = (left && top) || (right && bottom);
      return isMainDiagonal
          ? SystemMouseCursors.resizeUpLeftDownRight
          : SystemMouseCursors.resizeUpRightDownLeft;
    }
    if (horizontal) return SystemMouseCursors.resizeLeftRight;
    return SystemMouseCursors.resizeUpDown;
  }
}

/// A dialog shell that the user can resize, move, and maximize.
///
/// Behaves like an [AlertDialog] with [title] / [contentBuilder] / [actions]
/// slots, but instead of sizing itself from the content it keeps an explicit
/// rect that the user controls:
///
/// * drag any edge or corner to resize (min size enforced, kept on screen),
/// * drag the header to move it,
/// * the header button or a double-click on the header maximizes/restores.
///
/// When [prefsKeyPrefix] is set, the size and the maximized flag are persisted
/// so the next open reuses them. Position is intentionally not persisted — the
/// dialog re-centers on each open, which is what users expect from a modal.
class ResizableDialog extends StatefulWidget {
  const ResizableDialog({
    super.key,
    required this.contentBuilder,
    this.title,
    this.actions,
    this.prefsKeyPrefix,
    this.initialSizeFactor = const Size(0.5, 0.6),
    this.minSize = const Size(380, 320),
    this.titlePadding = const EdgeInsets.fromLTRB(28, 20, 12, 0),
    this.contentPadding = const EdgeInsets.fromLTRB(28, 16, 28, 8),
    this.actionsPadding = const EdgeInsets.fromLTRB(20, 4, 20, 14),
  });

  /// Builds the dialog body. Receives the current inner size (the dialog rect
  /// minus the header/actions padding is not subtracted — it is the full
  /// dialog size) so content can adapt to the user's chosen dimensions.
  final Widget Function(BuildContext context, Size dialogSize) contentBuilder;

  final Widget? title;
  final List<Widget>? actions;

  /// SharedPreferences key prefix used to remember size + maximized state.
  final String? prefsKeyPrefix;

  /// Fraction of the viewport used the first time the dialog is opened.
  final Size initialSizeFactor;

  final Size minSize;
  final EdgeInsets titlePadding;
  final EdgeInsets contentPadding;
  final EdgeInsets actionsPadding;

  @override
  State<ResizableDialog> createState() => _ResizableDialogState();
}

class _ResizableDialogState extends State<ResizableDialog> {
  /// Gap kept between the dialog and the viewport edges.
  static const double _margin = 16;

  /// Hit area of the edge handles / corner handles.
  static const double _edgeThickness = 7;
  static const double _cornerSize = 16;

  Size? _size;

  /// Top-left in viewport coordinates. Null means "centered".
  Offset? _topLeft;

  bool _isMaximized = false;
  Rect? _restoreRect;

  /// Rect captured when a drag starts, plus the total movement since then, so
  /// every update recomputes from the start rect instead of accumulating
  /// rounding drift.
  Rect? _dragStartRect;
  Offset _dragTotalDelta = Offset.zero;

  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _loadPersistedState();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  String? get _widthKey =>
      widget.prefsKeyPrefix == null ? null : '${widget.prefsKeyPrefix}_width';
  String? get _heightKey =>
      widget.prefsKeyPrefix == null ? null : '${widget.prefsKeyPrefix}_height';
  String? get _maximizedKey => widget.prefsKeyPrefix == null
      ? null
      : '${widget.prefsKeyPrefix}_maximized';

  Future<void> _loadPersistedState() async {
    final widthKey = _widthKey;
    if (widthKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final width = prefs.getDouble(widthKey);
      final height = prefs.getDouble(_heightKey!);
      final maximized = prefs.getBool(_maximizedKey!) ?? false;
      if (!mounted) return;
      setState(() {
        if (width != null && height != null && width > 0 && height > 0) {
          _size = Size(width, height);
        }
        _isMaximized = maximized;
      });
    } catch (error) {
      AppLogger.warning('[ResizableDialog] Failed to read saved size: $error');
    }
  }

  void _scheduleSave() {
    if (widget.prefsKeyPrefix == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persistState);
  }

  Future<void> _persistState() async {
    final widthKey = _widthKey;
    if (widthKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final size = _size;
      if (size != null) {
        await prefs.setDouble(widthKey, size.width);
        await prefs.setDouble(_heightKey!, size.height);
      }
      await prefs.setBool(_maximizedKey!, _isMaximized);
    } catch (error) {
      AppLogger.warning('[ResizableDialog] Failed to save size: $error');
    }
  }

  /// Resolves the rect to render for [viewport] without mutating state, so it
  /// is safe to call from `build`.
  Rect _effectiveRect(Size viewport) {
    final availableWidth = math.max(0.0, viewport.width - _margin * 2);
    final availableHeight = math.max(0.0, viewport.height - _margin * 2);

    if (_isMaximized) {
      return Rect.fromLTWH(_margin, _margin, availableWidth, availableHeight);
    }

    final requested =
        _size ??
        Size(
          viewport.width * widget.initialSizeFactor.width,
          viewport.height * widget.initialSizeFactor.height,
        );

    final width = requested.width
        .clamp(math.min(widget.minSize.width, availableWidth), availableWidth)
        .toDouble();
    final height = requested.height
        .clamp(
          math.min(widget.minSize.height, availableHeight),
          availableHeight,
        )
        .toDouble();

    final origin =
        _topLeft ??
        Offset((viewport.width - width) / 2, (viewport.height - height) / 2);

    final left = origin.dx
        .clamp(_margin, math.max(_margin, viewport.width - _margin - width))
        .toDouble();
    final top = origin.dy
        .clamp(_margin, math.max(_margin, viewport.height - _margin - height))
        .toDouble();

    return Rect.fromLTWH(left, top, width, height);
  }

  void _toggleMaximize(Size viewport) {
    setState(() {
      if (_isMaximized) {
        _isMaximized = false;
        final restore = _restoreRect;
        if (restore != null) {
          _size = restore.size;
          _topLeft = restore.topLeft;
        }
      } else {
        _restoreRect = _effectiveRect(viewport);
        _isMaximized = true;
      }
    });
    _scheduleSave();
  }

  void _startDrag(Size viewport) {
    _dragStartRect = _effectiveRect(viewport);
    _dragTotalDelta = Offset.zero;
  }

  void _endDrag() {
    _dragStartRect = null;
    _dragTotalDelta = Offset.zero;
    _scheduleSave();
  }

  void _moveBy(Offset delta, Size viewport) {
    final start = _dragStartRect;
    if (start == null || _isMaximized) return;
    _dragTotalDelta += delta;
    setState(() {
      _size = start.size;
      _topLeft = start.topLeft + _dragTotalDelta;
    });
  }

  void _resizeBy(Offset delta, _ResizeEdge edge, Size viewport) {
    final start = _dragStartRect;
    if (start == null || _isMaximized) return;

    _dragTotalDelta += delta;
    final total = _dragTotalDelta;

    var left = edge.left ? start.left + total.dx : start.left;
    var top = edge.top ? start.top + total.dy : start.top;
    var right = edge.right ? start.right + total.dx : start.right;
    var bottom = edge.bottom ? start.bottom + total.dy : start.bottom;

    // Keep the dialog inside the viewport.
    final maxRight = math.max(_margin, viewport.width - _margin);
    final maxBottom = math.max(_margin, viewport.height - _margin);
    left = left.clamp(_margin, maxRight).toDouble();
    top = top.clamp(_margin, maxBottom).toDouble();
    right = right.clamp(_margin, maxRight).toDouble();
    bottom = bottom.clamp(_margin, maxBottom).toDouble();

    // Enforce the minimum size by pushing back the edge being dragged.
    final minWidth = math.min(widget.minSize.width, maxRight - _margin);
    final minHeight = math.min(widget.minSize.height, maxBottom - _margin);
    if (right - left < minWidth) {
      if (edge.left) {
        left = right - minWidth;
      } else {
        right = left + minWidth;
      }
    }
    if (bottom - top < minHeight) {
      if (edge.top) {
        top = bottom - minHeight;
      } else {
        bottom = top + minHeight;
      }
    }

    setState(() {
      _topLeft = Offset(left, top);
      _size = Size(right - left, bottom - top);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final rect = _effectiveRect(viewport);

        return Stack(
          children: [
            Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: _buildDialogBody(rect.size, viewport),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDialogBody(Size size, Size viewport) {
    final theme = Theme.of(context);
    final background =
        theme.dialogTheme.backgroundColor ??
        theme.colorScheme.surfaceContainerHigh;

    return Stack(
      children: [
        Positioned.fill(
          child: Material(
            color: background,
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(viewport),
                Expanded(
                  child: Padding(
                    padding: widget.contentPadding,
                    child: widget.contentBuilder(context, size),
                  ),
                ),
                if (widget.actions != null && widget.actions!.isNotEmpty)
                  Padding(
                    padding: widget.actionsPadding,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: widget.actions!,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!_isMaximized) ..._buildResizeHandles(viewport),
      ],
    );
  }

  Widget _buildHeader(Size viewport) {
    final theme = Theme.of(context);

    // The maximize button is a sibling of the drag area, not a child of it:
    // nesting it would put its tap in the same gesture arena as the header's
    // double-tap recognizer, which swallows the tap.
    return Padding(
      padding: widget.titlePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: MouseRegion(
              cursor: _isMaximized
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Report the drag from where the pointer went down so the
                // touch-slop distance is not lost and the dialog tracks the
                // cursor exactly.
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (_) => _startDrag(viewport),
                onPanUpdate: (details) => _moveBy(details.delta, viewport),
                onPanEnd: (_) => _endDrag(),
                onDoubleTap: () => _toggleMaximize(viewport),
                child: widget.title ?? const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildMaximizeButton(theme, viewport),
        ],
      ),
    );
  }

  Widget _buildMaximizeButton(ThemeData theme, Size viewport) {
    return Tooltip(
      message: _isMaximized ? 'Restore' : 'Maximize',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggleMaximize(viewport),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(
            _isMaximized
                ? PhosphorIconsLight.cornersIn
                : PhosphorIconsLight.cornersOut,
            size: 17,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildResizeHandles(Size viewport) {
    return <Widget>[
      // Edges.
      Positioned(
        left: _cornerSize,
        right: _cornerSize,
        top: 0,
        height: _edgeThickness,
        child: _handle(const _ResizeEdge(top: true), viewport),
      ),
      Positioned(
        left: _cornerSize,
        right: _cornerSize,
        bottom: 0,
        height: _edgeThickness,
        child: _handle(const _ResizeEdge(bottom: true), viewport),
      ),
      Positioned(
        top: _cornerSize,
        bottom: _cornerSize,
        left: 0,
        width: _edgeThickness,
        child: _handle(const _ResizeEdge(left: true), viewport),
      ),
      Positioned(
        top: _cornerSize,
        bottom: _cornerSize,
        right: 0,
        width: _edgeThickness,
        child: _handle(const _ResizeEdge(right: true), viewport),
      ),
      // Corners.
      Positioned(
        left: 0,
        top: 0,
        width: _cornerSize,
        height: _cornerSize,
        child: _handle(const _ResizeEdge(left: true, top: true), viewport),
      ),
      Positioned(
        right: 0,
        top: 0,
        width: _cornerSize,
        height: _cornerSize,
        child: _handle(const _ResizeEdge(right: true, top: true), viewport),
      ),
      Positioned(
        left: 0,
        bottom: 0,
        width: _cornerSize,
        height: _cornerSize,
        child: _handle(const _ResizeEdge(left: true, bottom: true), viewport),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        width: _cornerSize,
        height: _cornerSize,
        child: _buildCornerGrip(
          const _ResizeEdge(right: true, bottom: true),
          viewport,
        ),
      ),
    ];
  }

  Widget _handle(_ResizeEdge edge, Size viewport) {
    return MouseRegion(
      cursor: edge.cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => _startDrag(viewport),
        onPanUpdate: (details) => _resizeBy(details.delta, edge, viewport),
        onPanEnd: (_) => _endDrag(),
        child: const SizedBox.expand(),
      ),
    );
  }

  /// Bottom-right corner also shows a visible grip, like a window corner.
  Widget _buildCornerGrip(_ResizeEdge edge, Size viewport) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: edge.cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => _startDrag(viewport),
        onPanUpdate: (details) => _resizeBy(details.delta, edge, viewport),
        onPanEnd: (_) => _endDrag(),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Transform.rotate(
            angle: -math.pi / 4,
            child: Icon(
              PhosphorIconsLight.dotsSixVertical,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
