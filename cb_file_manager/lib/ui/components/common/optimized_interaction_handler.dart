import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
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
    Key? key,
    this.child,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTap,
    this.onSecondaryTapUp,
    this.onTertiaryTapUp,
  }) : super(key: key);

  @override
  OptimizedInteractionLayerState createState() =>
      OptimizedInteractionLayerState();
}

class OptimizedInteractionLayerState extends State<OptimizedInteractionLayer> {
  int _lastTapTime = 0;
  Offset? _lastTapPosition;
  bool _skipNextTap = false;
  static const int _doubleTapTimeout = 300; // milliseconds
  static const double _doubleTapMaxDistance = 40.0; // pixels

  void _handleTapDown(TapDownDetails details) {
    final now = DateTime.now().millisecondsSinceEpoch;
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
    if (_skipNextTap) {
      _skipNextTap = false;
      return;
    }
    widget.onTap();
  }

  void _handleTapCancel() {
    _skipNextTap = false;
  }

  void _handleLongPressStart(LongPressStartDetails d) {
    _skipNextTap = true;
    widget.onLongPressStart?.call(d);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTap: _handleTap,
      onTapCancel: _handleTapCancel,
      onLongPress: widget.onLongPress,
      onLongPressStart:
          widget.onLongPressStart != null ? _handleLongPressStart : null,
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

  const OptimizedFileIcon({
    Key? key,
    required this.file,
    this.isVideo = false,
    this.isImage = false,
    this.size = 24,
    this.fallbackIcon = PhosphorIconsLight.file,
    this.fallbackColor,
    this.borderRadius,
  }) : super(key: key);

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
      _iconFuture =
          FileIconHelper.getIconForFile(widget.file, size: widget.size);
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
        _iconFuture =
            FileIconHelper.getIconForFile(widget.file, size: widget.size);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Wrap in RepaintBoundary to prevent parent changes from triggering repaints
    return RepaintBoundary(
      child: _buildOptimizedIcon(),
    );
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
            fallbackBuilder: () => Icon(widget.fallbackIcon,
                size: widget.size, color: widget.fallbackColor),
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
            fit: BoxFit.cover,
            fallbackBuilder: () => Icon(widget.fallbackIcon,
                size: widget.size, color: widget.fallbackColor),
          ),
        ),
      );
    } else {
      // Try sync extension icon cache first (warmed by batch native call)
      final ext = p.extension(widget.file.path).toLowerCase();
      final cachedIcon =
          FileIconHelper.getExtensionIconSync(ext, size: widget.size.toInt());
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
            return Icon(widget.fallbackIcon,
                size: widget.size, color: widget.fallbackColor);
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
