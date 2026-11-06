import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'thumbnail_placeholder.dart';

/// Keeps the placeholder until a decoded frame exists, including FileImage.
class ThumbnailImage extends StatefulWidget {
  const ThumbnailImage({
    super.key,
    required this.image,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.isVideo = false,
    this.showLoadingIndicator = true,
    this.onReady,
    this.onError,
    this.errorBuilder,
  });

  final ImageProvider image;
  final double width;
  final double height;
  final BoxFit fit;
  final bool isVideo;
  final bool showLoadingIndicator;
  final VoidCallback? onReady;
  final ValueChanged<Object>? onError;
  final Widget Function()? errorBuilder;

  @override
  State<ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<ThumbnailImage> {
  int _generation = 0;
  bool _reportedReady = false;
  bool _reportedError = false;

  @override
  void didUpdateWidget(ThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _generation++;
      _reportedReady = false;
      _reportedError = false;
    }
  }

  void _report({Object? error}) {
    if (error == null ? _reportedReady : _reportedError) return;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      if (error != null) {
        if (_reportedError) return;
        _reportedError = true;
        widget.onError?.call(error);
      } else {
        if (_reportedReady) return;
        _reportedReady = true;
        widget.onReady?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Image(
    image: widget.image,
    width: widget.width,
    height: widget.height,
    fit: widget.fit,
    filterQuality: FilterQuality.low,
    excludeFromSemantics: true,
    frameBuilder: (context, child, frame, synchronous) {
      if (frame == null) {
        return ThumbnailPlaceholder(
          isVideo: widget.isVideo,
          visible: widget.showLoadingIndicator,
        );
      }
      _report();
      if (!widget.isVideo) return child;
      return LayoutBuilder(
        builder: (context, constraints) {
          final shortest = constraints.biggest.shortestSide;
          return Stack(
            fit: StackFit.expand,
            children: [
              child,
              Center(
                child: ExcludeSemantics(
                  child: Icon(
                    PhosphorIconsLight.playCircle,
                    color: Colors.white,
                    size: shortest.isFinite
                        ? (shortest * .35).clamp(12.0, 32.0)
                        : 32,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
    errorBuilder: (context, error, stack) {
      _report(error: error);
      return widget.errorBuilder?.call() ??
          ThumbnailPlaceholder(isVideo: widget.isVideo, failed: true);
    },
  );
}
