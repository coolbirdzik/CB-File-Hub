import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../widgets/file_drag_drop_item.dart';
import '../../../helpers/files/file_icon_helper.dart';
import '../../widgets/thumbnail_loader.dart';
import '../../widgets/lazy_video_thumbnail.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// A reusable widget for optimized touch/mouse interactions
/// that handles tap, double-tap, long-press and secondary tap events without delay
class OptimizedInteractionLayer extends StatefulWidget {
  final Widget? child;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final VoidCallback? onSecondaryTap;
  final void Function(TapUpDetails)? onSecondaryTapUp;
  final void Function(TapUpDetails)? onTertiaryTapUp;

  const OptimizedInteractionLayer({
    super.key,
    this.child,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTap,
    this.onSecondaryTapUp,
    this.onTertiaryTapUp,
  });

  @override
  OptimizedInteractionLayerState createState() =>
      OptimizedInteractionLayerState();
}

class OptimizedInteractionLayerState extends State<OptimizedInteractionLayer> {
  int _lastTapTime = 0;
  Offset? _lastTapPosition;
  bool _skipNextTap = false;
  TapDownDetails? _deferredTap;
  int _deferredTapTime = 0;
  bool _pressHandled = false;
  static const int _doubleTapTimeout = 300; // milliseconds
  static const double _doubleTapMaxDistance = 40.0; // pixels

  /// Mouse presses select immediately, like Explorer. The tap recognizer
  /// can't report the press any sooner: a draggable item keeps the gesture
  /// arena open until kPressTimeout or release, so selection used to land
  /// only after the button came back up.
  void _handlePointerDown(PointerDownEvent event) {
    _pressHandled = false;
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton ||
        widget.onLongPress != null ||
        widget.onLongPressStart != null) {
      return;
    }
    _pressHandled = true;
    _deferredTap = null;
    _skipNextTap = false;
    _pressDown(
      TapDownDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
        kind: event.kind,
      ),
    );
  }

  void _handleTapDown(TapDownDetails details) {
    if (_pressHandled) return;
    _pressDown(details);
  }

  void _pressDown(TapDownDetails details) {
    final dragItem = context.findAncestorWidgetOfExactType<FileDragDropItem>();
    if (dragItem != null && dragItem.selectedPaths.contains(dragItem.path)) {
      // Pressing an already-selected item may start dragging the whole
      // selection. Do not collapse it (or open on double-click) until the
      // press resolves as a tap.
      _deferredTap = details;
      _deferredTapTime = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    _activateTapDown(details);
  }

  /// [pressedAt] is when the button went down; a deferred press resolves on
  /// release, and timing it from there would stretch the double-click window.
  void _activateTapDown(TapDownDetails details, {int? pressedAt}) {
    final now = pressedAt ?? DateTime.now().millisecondsSinceEpoch;
    final position = details.globalPosition;

    // Check if this could be a double tap
    if (widget.onDoubleTap != null && _lastTapTime > 0) {
      final timeDiff = now - _lastTapTime;
      final distance = _lastTapPosition != null
          ? (position - _lastTapPosition!).distance
          : 0.0;

      // If within double tap time window and distance threshold
      if (timeDiff <= _doubleTapTimeout && distance <= _doubleTapMaxDistance) {
        widget.onDoubleTap!();
        // Reset to prevent triple tap
        _lastTapTime = 0;
        _lastTapPosition = null;
        _skipNextTap = true;
        return;
      }
    }

    final hasLongPressHandler =
        widget.onLongPress != null || widget.onLongPressStart != null;
    if (!hasLongPressHandler) {
      widget.onTap();
      _skipNextTap = true;
    } else {
      _skipNextTap = false;
    }

    // Store info for potential next tap
    if (widget.onDoubleTap != null) {
      _lastTapTime = now;
      _lastTapPosition = position;
    }
  }

  void _handleTap() {
    final deferred = _deferredTap;
    _deferredTap = null;
    _pressHandled = false;
    if (deferred != null) {
      _activateTapDown(deferred, pressedAt: _deferredTapTime);
    }
    if (_skipNextTap) {
      _skipNextTap = false;
      return;
    }
    widget.onTap();
  }

  void _handleTapCancel() {
    _deferredTap = null;
    _skipNextTap = false;
    _pressHandled = false;
  }

  void _handleLongPressStart(LongPressStartDetails d) {
    _skipNextTap = true;
    widget.onLongPressStart?.call(d);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      child: _buildGestureDetector(),
    );
  }

  Widget _buildGestureDetector() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // These layers are invisible hit-test strips stacked over an item; they
      // carry no label, so the semantics nodes they would emit are unusable by
      // a screen reader (the item name is announced by the Text node instead).
      // Emitting them is actively harmful on Windows: every list/grid item
      // contributes 1-3 extra nodes that are created and destroyed as sliver
      // slots recycle and as `isBeingRenamed` toggles. The engine batches those
      // create/destroy pairs into a single ui::AXTreeUpdate, and the Windows
      // AccessibilityBridge cannot serialize a batch where a node is dropped
      // and its slot reclaimed in the same frame, producing a flood of
      // "Failed to update ui::AXTree, error: <id> will not be in the tree and
      // is not the new root" on selection/focus changes.
      excludeFromSemantics: true,
      onTapDown: _handleTapDown,
      onTap: _handleTap,
      onTapCancel: _handleTapCancel,
      onLongPress: widget.onLongPress,
      onLongPressStart: widget.onLongPressStart != null
          ? _handleLongPressStart
          : null,
      onSecondaryTap: widget.onSecondaryTap,
      onSecondaryTapUp: widget.onSecondaryTapUp,
      onTertiaryTapUp: widget.onTertiaryTapUp,
      child: widget.child,
    );
  }
}

/// Optimized file icon widget that caches and efficiently renders file icons
class OptimizedFileIcon extends StatefulWidget {
  final File file;
  final bool isVideo;
  final bool isImage;
  final double size;
  final IconData fallbackIcon;
  final Color? fallbackColor;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  const OptimizedFileIcon({
    super.key,
    required this.file,
    this.isVideo = false,
    this.isImage = false,
    this.size = 24,
    this.fallbackIcon = PhosphorIconsLight.file,
    this.fallbackColor,
    this.borderRadius,
    this.fit = BoxFit.cover,
  });

  @override
  OptimizedFileIconState createState() => OptimizedFileIconState();
}

class OptimizedFileIconState extends State<OptimizedFileIcon>
    with AutomaticKeepAliveClientMixin {
  late Future<Widget> _iconFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Initialize the icon future only once if it's a regular file
    if (!widget.isVideo && !widget.isImage) {
      _iconFuture = FileIconHelper.getIconForFile(
        widget.file,
        size: widget.size,
      );
    }
  }

  @override
  void didUpdateWidget(OptimizedFileIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only refresh future if file path or type changes
    if (widget.file.path != oldWidget.file.path ||
        widget.isVideo != oldWidget.isVideo ||
        widget.isImage != oldWidget.isImage) {
      if (!widget.isVideo && !widget.isImage) {
        _iconFuture = FileIconHelper.getIconForFile(
          widget.file,
          size: widget.size,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Wrap in RepaintBoundary to prevent parent changes from triggering repaints
    return RepaintBoundary(child: _buildOptimizedIcon());
  }

  Widget _buildOptimizedIcon() {
    final BorderRadius borderRadius =
        widget.borderRadius ?? BorderRadius.circular(2);

    if (widget.isVideo) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: LazyVideoThumbnail(
            videoPath: widget.file.path,
            width: widget.size,
            height: widget.size,
            fit: widget.fit,
            fallbackBuilder: () => Icon(
              widget.fallbackIcon,
              size: widget.size,
              color: widget.fallbackColor,
            ),
            key: ValueKey('video-thumbnail-${widget.file.path}'),
          ),
        ),
      );
    } else if (widget.isImage) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: ThumbnailLoader(
            filePath: widget.file.path,
            isVideo: false,
            isImage: true,
            width: widget.size,
            height: widget.size,
            fit: widget.fit,
            fallbackBuilder: () => Icon(
              widget.fallbackIcon,
              size: widget.size,
              color: widget.fallbackColor,
            ),
          ),
        ),
      );
    } else {
      // Try sync extension icon cache first (warmed by batch native call)
      final ext = p.extension(widget.file.path).toLowerCase();
      final cachedIcon = FileIconHelper.getExtensionIconSync(
        ext,
        size: widget.size.toInt(),
      );
      if (cachedIcon != null) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: cachedIcon,
        );
      }

      // Fallback: use FutureBuilder for cold cache (rare after warmup)
      return FutureBuilder<Widget>(
        future: _iconFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              !snapshot.hasData) {
            return Icon(
              widget.fallbackIcon,
              size: widget.size,
              color: widget.fallbackColor,
            );
          }
          return snapshot.data!;
        },
      );
    }
  }
}

/// Helper class for calculating file sizes in human-readable format
class FileUtils {
  /// Format file size in bytes to a human-readable string (B, KB, MB, GB)
  static String formatFileSize(int size) {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
