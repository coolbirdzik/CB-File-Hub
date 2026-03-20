import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Unified skeleton component for file, album, and media loading across all platforms
/// Automatically adapts to mobile/desktop with consistent design
class Skeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Duration duration;
  final SkeletonType type;
  final int? itemCount;
  final int? crossAxisCount;
  final bool isAlbum;

  /// Whether to wrap list items in Card on desktop (default: true)
  final bool wrapInCardOnDesktop;

  const Skeleton({
    Key? key,
    this.width = double.infinity,
    this.height = double.infinity,
    this.borderRadius,
    this.duration = const Duration(milliseconds: 1600),
    this.type = SkeletonType.single,
    this.itemCount = 12,
    this.crossAxisCount = 3,
    this.isAlbum = false,
    this.wrapInCardOnDesktop = true,
  }) : super(key: key);

  @override
  State<Skeleton> createState() => _SkeletonState();
}

enum SkeletonType {
  /// Single skeleton box for thumbnails, images, etc.
  single,

  /// List view skeleton for files/albums
  list,

  /// Grid view skeleton for files/albums
  grid,

  /// Album grid layout
  albumGrid,

  /// Album list layout
  albumList,

  /// Video thumbnail skeleton (optimized for video previews)
  videoThumbnail,

  /// Masonry grid layout (Pinterest-style with varying heights)
  masonry,
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.type) {
      case SkeletonType.single:
        return _buildSingleSkeleton(context);
      case SkeletonType.list:
        return _buildListSkeleton(context);
      case SkeletonType.grid:
        return _buildGridSkeleton(context);
      case SkeletonType.albumGrid:
        return _buildAlbumGridSkeleton(context);
      case SkeletonType.albumList:
        return _buildAlbumListSkeleton(context);
      case SkeletonType.videoThumbnail:
        return _buildVideoThumbnailSkeleton(context);
      case SkeletonType.masonry:
        return _buildMasonrySkeleton(context);
    }
  }

  /// Detect if current platform is mobile (Android/iOS)
  bool get _isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Widget _buildSingleSkeleton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = cs.surfaceContainerHighest.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.45 : 0.6);
    final midColor = cs.surfaceContainerHighest.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.45);
    final highlightColor = cs.surface.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.28);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double shift = (_controller.value * 2) - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment(-1.2 + shift, -0.3),
              end: Alignment(1.2 + shift, 0.3),
              colors: [
                baseColor,
                midColor,
                highlightColor,
                midColor,
                baseColor
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListSkeleton(BuildContext context) {
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      itemCount: widget.itemCount ?? 12,
      cacheExtent: 500,
      itemBuilder: (context, index) => _SkeletonListItem(
        index: index,
        controller: _controller,
        wrapInCard: !_isMobile && widget.wrapInCardOnDesktop,
      ),
    );
  }

  Widget _buildGridSkeleton(BuildContext context) {
    final int requestedCrossAxisCount = widget.crossAxisCount ?? 3;
    const double gridPadding = 8.0;
    const double spacing = 8.0;
    const double minItemWidth = 72.0;
    final double width = MediaQuery.of(context).size.width;
    final double safeWidth = math.max(0.0, width - (gridPadding * 2));
    final int maxColumns = ((safeWidth + spacing) / (minItemWidth + spacing))
        .floor()
        .clamp(1, 1000);
    final int crossAxisCount =
        requestedCrossAxisCount.clamp(1, maxColumns).toInt();

    return GridView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(8.0),
      cacheExtent: 800,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0, // Always use album ratio
      ),
      itemCount: widget.itemCount ?? 12,
      itemBuilder: (context, index) => _SkeletonGridItem(
        index: index,
        controller: _controller,
      ),
    );
  }

  Widget _buildAlbumGridSkeleton(BuildContext context) {
    return _buildGridSkeleton(context);
  }

  Widget _buildAlbumListSkeleton(BuildContext context) {
    return _buildListSkeleton(context);
  }

  Widget _buildVideoThumbnailSkeleton(BuildContext context) {
    // Video thumbnail skeleton - optimized for video previews
    return ShimmerBox(
      width: widget.width ?? double.infinity,
      height: widget.height ?? double.infinity,
      borderRadius: widget.borderRadius ?? BorderRadius.circular(16.0),
    );
  }

  Widget _buildMasonrySkeleton(BuildContext context) {
    // Masonry skeleton for Pinterest-style layout with varying heights
    // Note: Using standard GridView with varying aspect ratios to simulate masonry
    // For true masonry in production, the parent should use MasonryGridView
    return GridView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(8.0),
      cacheExtent: 800,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount ?? 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.75, // Slightly taller for masonry effect
      ),
      itemCount: widget.itemCount ?? 12,
      itemBuilder: (context, index) {
        // Vary heights for masonry effect (pattern: tall, medium, short)
        final heightVariation = index % 3;
        final aspectRatio = heightVariation == 0
            ? 0.65 // Tall
            : heightVariation == 1
                ? 0.75 // Medium
                : 0.85; // Short

        return _SkeletonMasonryItem(
          index: index,
          controller: _controller,
          aspectRatio: aspectRatio,
        );
      },
    );
  }
}

/// Skeleton list item with album design
/// Automatically wraps in Card on desktop if wrapInCard is true
class _SkeletonListItem extends StatelessWidget {
  final int index;
  final AnimationController controller;
  final bool wrapInCard;

  const _SkeletonListItem({
    required this.index,
    required this.controller,
    this.wrapInCard = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ShimmerBox(
            width: 56, // Always use album size for consistency
            height: 56,
            borderRadius: BorderRadius.circular(16),
            controller: controller,
            delay: Duration(milliseconds: (index * 80).clamp(0, 800)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(
                  width: double.infinity,
                  height: 18, // Always use album size
                  borderRadius: BorderRadius.circular(16.0),
                  controller: controller,
                  delay:
                      Duration(milliseconds: (index * 80 + 40).clamp(0, 840)),
                ),
                const SizedBox(height: 12),
                ShimmerBox(
                  width: MediaQuery.of(context).size.width * 0.6,
                  height: 16, // Always use album size
                  borderRadius: BorderRadius.circular(16.0),
                  controller: controller,
                  delay:
                      Duration(milliseconds: (index * 80 + 80).clamp(0, 880)),
                ),
                const SizedBox(height: 8),
                ShimmerBox(
                  width: 120,
                  height: 12,
                  borderRadius: BorderRadius.circular(6),
                  controller: controller,
                  delay:
                      Duration(milliseconds: (index * 80 + 120).clamp(0, 920)),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Wrap in Card on desktop for elevated appearance
    if (wrapInCard) {
      return RepaintBoundary(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          elevation: 0,
          child: content,
        ),
      );
    }

    return RepaintBoundary(child: content);
  }
}

/// Skeleton grid item with album design
class _SkeletonGridItem extends StatelessWidget {
  final int index;
  final AnimationController controller;

  const _SkeletonGridItem({
    required this.index,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(16.0), // Always use album style
                child: ShimmerBox(
                  width: double.infinity,
                  height: double.infinity,
                  controller: controller,
                  delay: Duration(milliseconds: (index * 60).clamp(0, 600)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ShimmerBox(
              width: double.infinity,
              height: 16, // Always use album size
              borderRadius: BorderRadius.circular(16.0),
              controller: controller,
              delay: Duration(milliseconds: (index * 60 + 30).clamp(0, 630)),
            ),
            const SizedBox(height: 8),
            ShimmerBox(
              width: 100, // Always use album size
              height: 14, // Always use album size
              borderRadius: BorderRadius.circular(16.0),
              controller: controller,
              delay: Duration(milliseconds: (index * 60 + 60).clamp(0, 660)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton masonry item with varying heights for Pinterest-style layout
class _SkeletonMasonryItem extends StatelessWidget {
  final int index;
  final AnimationController controller;
  final double aspectRatio;

  const _SkeletonMasonryItem({
    required this.index,
    required this.controller,
    required this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ShimmerBox(
              width: double.infinity,
              height: double.infinity,
              controller: controller,
              delay: Duration(milliseconds: (index * 60).clamp(0, 600)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shimmer effect box with animation - Public for reuse in other components
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final Duration delay;
  final AnimationController? controller;

  const ShimmerBox({
    Key? key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.delay = Duration.zero,
    this.controller,
  }) : super(key: key);

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  bool _isDelayComplete = false;
  AnimationController? _internalController;

  AnimationController get _effectiveController =>
      widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    // Create internal controller if none provided
    if (widget.controller == null) {
      _internalController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat();
    }

    Future.delayed(widget.delay, () {
      if (mounted) {
        setState(() {
          _isDelayComplete = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = _skeletonColor(context);
    final highlightColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.white.withValues(alpha: 0.8);

    if (!_isDelayComplete) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(16.0),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _effectiveController,
      builder: (context, child) {
        final double value = _effectiveController.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(16.0),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                (value - 0.3).clamp(0.0, 1.0),
                value.clamp(0.0, 1.0),
                (value + 0.3).clamp(0.0, 1.0),
              ],
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
            ),
          ),
        );
      },
    );
  }
}

Color _skeletonColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.colorScheme.surfaceContainerHighest
      .withValues(alpha: theme.brightness == Brightness.dark ? 0.35 : 0.6);
}
