import 'dart:math';

import 'package:flutter/material.dart';

import 'edit_model.dart';
import 'edit_renderer.dart';

enum _CropHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
  move,
}

/// The whole picture with a draggable crop frame on top.
class CropView extends StatefulWidget {
  final EditState state;

  /// Width / height of the crop in pixels, or null for a free crop.
  final double? aspectRatio;
  final ValueChanged<Rect> onChanged;
  final VoidCallback onChangeEnd;

  const CropView({
    super.key,
    required this.state,
    required this.aspectRatio,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<CropView> createState() => _CropViewState();
}

class _CropViewState extends State<CropView>
    with SingleTickerProviderStateMixin {
  static const EdgeInsets _padding = EdgeInsets.all(28);
  static const double _handleReach = 26;
  static const double _minCropPixels = 32;

  late final AnimationController _settle;
  Rect? _animateFrom;
  _CropHandle? _handle;
  Rect _dragStartCrop = EditGeometry.fullCrop;
  Offset _dragStart = Offset.zero;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(CropView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCrop = oldWidget.state.geometry.crop;
    final newCrop = widget.state.geometry.crop;
    final sameOrientation =
        oldWidget.state.geometry.quarterTurns ==
            widget.state.geometry.quarterTurns &&
        oldWidget.state.geometry.flipped == widget.state.geometry.flipped;
    // Changes that do not come from dragging (an aspect preset, a reset)
    // glide into place.
    if (_handle == null && sameOrientation && oldCrop != newCrop) {
      _animateFrom = _displayCrop(oldCrop);
      _settle.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  Rect _displayCrop([Rect? target]) {
    final crop = target ?? widget.state.geometry.crop;
    final from = _animateFrom;
    if (from == null || !_settle.isAnimating) return crop;
    return Rect.lerp(from, crop, Curves.easeOutCubic.transform(_settle.value))!;
  }

  _CropHandle _hitHandle(Offset point, Rect frame) {
    bool near(Offset corner) => (point - corner).distance <= _handleReach;
    if (near(frame.topLeft)) return _CropHandle.topLeft;
    if (near(frame.topRight)) return _CropHandle.topRight;
    if (near(frame.bottomRight)) return _CropHandle.bottomRight;
    if (near(frame.bottomLeft)) return _CropHandle.bottomLeft;
    if (widget.aspectRatio == null) {
      final withinX =
          point.dx > frame.left - _handleReach &&
          point.dx < frame.right + _handleReach;
      final withinY =
          point.dy > frame.top - _handleReach &&
          point.dy < frame.bottom + _handleReach;
      if (withinX && (point.dy - frame.top).abs() <= _handleReach / 1.5) {
        return _CropHandle.top;
      }
      if (withinX && (point.dy - frame.bottom).abs() <= _handleReach / 1.5) {
        return _CropHandle.bottom;
      }
      if (withinY && (point.dx - frame.left).abs() <= _handleReach / 1.5) {
        return _CropHandle.left;
      }
      if (withinY && (point.dx - frame.right).abs() <= _handleReach / 1.5) {
        return _CropHandle.right;
      }
    }
    return _CropHandle.move;
  }

  Rect _dragged(Offset delta, EditorViewport viewport) {
    final image = viewport.imageRect;
    final dx = delta.dx / image.width;
    final dy = delta.dy / image.height;
    final start = _dragStartCrop;
    final minW = min(1.0, _minCropPixels / image.width);
    final minH = min(1.0, _minCropPixels / image.height);

    if (_handle == _CropHandle.move) {
      final left = (start.left + dx).clamp(0.0, 1 - start.width);
      final top = (start.top + dy).clamp(0.0, 1 - start.height);
      return Rect.fromLTWH(left, top, start.width, start.height);
    }

    var left = start.left, top = start.top;
    var right = start.right, bottom = start.bottom;
    final handle = _handle!;
    final movesLeft =
        handle == _CropHandle.topLeft ||
        handle == _CropHandle.bottomLeft ||
        handle == _CropHandle.left;
    final movesRight =
        handle == _CropHandle.topRight ||
        handle == _CropHandle.bottomRight ||
        handle == _CropHandle.right;
    final movesTop =
        handle == _CropHandle.topLeft ||
        handle == _CropHandle.topRight ||
        handle == _CropHandle.top;
    final movesBottom =
        handle == _CropHandle.bottomLeft ||
        handle == _CropHandle.bottomRight ||
        handle == _CropHandle.bottom;
    if (movesLeft) left = (start.left + dx).clamp(0.0, right - minW);
    if (movesRight) right = (start.right + dx).clamp(left + minW, 1.0);
    if (movesTop) top = (start.top + dy).clamp(0.0, bottom - minH);
    if (movesBottom) bottom = (start.bottom + dy).clamp(top + minH, 1.0);

    final ratio = widget.aspectRatio;
    if (ratio == null) return Rect.fromLTRB(left, top, right, bottom);

    // Locked ratio: keep the opposite corner still and fit the ratio.
    final normalizedRatio = ratio * image.height / image.width;
    final anchorX = movesLeft ? start.right : start.left;
    final anchorY = movesTop ? start.bottom : start.top;
    var width = (right - left).abs();
    var height = (bottom - top).abs();
    if (width / height > normalizedRatio) {
      width = height * normalizedRatio;
    } else {
      height = width / normalizedRatio;
    }
    final roomX = movesLeft ? anchorX : 1 - anchorX;
    final roomY = movesTop ? anchorY : 1 - anchorY;
    if (width > roomX) {
      width = roomX;
      height = width / normalizedRatio;
    }
    if (height > roomY) {
      height = roomY;
      width = height * normalizedRatio;
    }
    return Rect.fromLTRB(
      movesLeft ? anchorX - width : anchorX,
      movesTop ? anchorY - height : anchorY,
      movesLeft ? anchorX : anchorX + width,
      movesTop ? anchorY : anchorY + height,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final viewport = EditorViewport.fit(
          size,
          widget.state,
          showWholeImage: true,
          padding: _padding,
        );
        final crop = _displayCrop();
        final image = viewport.imageRect;
        final frame = Rect.fromLTRB(
          image.left + crop.left * image.width,
          image.top + crop.top * image.height,
          image.left + crop.right * image.width,
          image.top + crop.bottom * image.height,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            _settle.stop();
            setState(() {
              _handle = _hitHandle(details.localPosition, frame);
              _dragStart = details.localPosition;
              _dragStartCrop = widget.state.geometry.crop;
            });
          },
          onPanUpdate: (details) {
            if (_handle == null) return;
            widget.onChanged(
              _dragged(details.localPosition - _dragStart, viewport),
            );
          },
          onPanEnd: (_) {
            setState(() => _handle = null);
            widget.onChangeEnd();
          },
          onPanCancel: () => setState(() => _handle = null),
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _CropImagePainter(widget.state, viewport)),
                AnimatedOpacity(
                  opacity: _handle == null ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: CustomPaint(painter: _CropGridPainter(frame)),
                ),
                CustomPaint(
                  painter: _CropFramePainter(
                    frame: frame,
                    image: image,
                    active: _handle != null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CropImagePainter extends CustomPainter {
  final EditState state;
  final EditorViewport viewport;

  _CropImagePainter(this.state, this.viewport);

  @override
  void paint(Canvas canvas, Size size) {
    paintEdit(
      canvas,
      state,
      sourceToView: viewport.sourceToView,
      frame: viewport.frame,
      clip: viewport.imageRect,
    );
  }

  @override
  bool shouldRepaint(_CropImagePainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.viewport.sourceToView != viewport.sourceToView ||
      oldDelegate.viewport.frame != viewport.frame;
}

class _CropFramePainter extends CustomPainter {
  final Rect frame;
  final Rect image;
  final bool active;

  _CropFramePainter({
    required this.frame,
    required this.image,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dim everything outside the frame.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(image),
        Path()..addRect(frame),
      ),
      Paint()..color = Colors.black.withValues(alpha: active ? 0.45 : 0.6),
    );
    canvas.drawRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.9),
    );

    final handle = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final arm = min(22.0, min(frame.width, frame.height) / 3);
    void corner(Offset point, double sx, double sy) {
      canvas.drawLine(point, point + Offset(arm * sx, 0), handle);
      canvas.drawLine(point, point + Offset(0, arm * sy), handle);
    }

    corner(frame.topLeft, 1, 1);
    corner(frame.topRight, -1, 1);
    corner(frame.bottomLeft, 1, -1);
    corner(frame.bottomRight, -1, -1);

    // Short bars in the middle of each edge.
    final bar = min(18.0, min(frame.width, frame.height) / 4);
    canvas.drawLine(
      frame.topCenter - Offset(bar / 2, 0),
      frame.topCenter + Offset(bar / 2, 0),
      handle,
    );
    canvas.drawLine(
      frame.bottomCenter - Offset(bar / 2, 0),
      frame.bottomCenter + Offset(bar / 2, 0),
      handle,
    );
    canvas.drawLine(
      frame.centerLeft - Offset(0, bar / 2),
      frame.centerLeft + Offset(0, bar / 2),
      handle,
    );
    canvas.drawLine(
      frame.centerRight - Offset(0, bar / 2),
      frame.centerRight + Offset(0, bar / 2),
      handle,
    );
  }

  @override
  bool shouldRepaint(_CropFramePainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.image != image ||
      oldDelegate.active != active;
}

/// Rule-of-thirds guides, shown while dragging.
class _CropGridPainter extends CustomPainter {
  final Rect frame;

  _CropGridPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = frame.left + frame.width * i / 3;
      final y = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), paint);
      canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), paint);
    }
  }

  @override
  bool shouldRepaint(_CropGridPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
