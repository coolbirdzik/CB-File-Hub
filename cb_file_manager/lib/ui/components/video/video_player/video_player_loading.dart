import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';

/// Circular loading indicator: gradient ring + [CircularProgressIndicator] + icon.
/// [stackOverlays] are inserted between the progress and the icon (e.g. pulsing dot).
class VideoPlayerCircularLoadingIndicator extends StatelessWidget {
  final double size;
  final Color primaryColor;
  final Color? progressColor;
  final double strokeWidth;
  final IconData icon;
  final double iconSize;
  final Color? iconColor;
  final List<Widget>? stackOverlays;

  const VideoPlayerCircularLoadingIndicator({
    Key? key,
    required this.size,
    required this.primaryColor,
    this.progressColor,
    this.strokeWidth = 2,
    required this.icon,
    this.iconSize = 20,
    this.iconColor,
    this.stackOverlays,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final progress = progressColor ?? primaryColor.withValues(alpha: 0.6);
    final ico = iconColor ?? primaryColor.withValues(alpha: 0.9);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            primaryColor.withValues(alpha: 0.1),
            primaryColor.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: strokeWidth,
              valueColor: AlwaysStoppedAnimation<Color>(progress),
            ),
          ),
          ...?stackOverlays,
          Icon(icon, color: ico, size: iconSize),
        ],
      ),
    );
  }
}

/// TweenAnimationBuilder that loops: onEnd calls setState to restart.
/// [delay] shifts the [animationValue] (0..1) for staggered effects.
class LoopingTweenBuilder extends StatefulWidget {
  final double delay;
  final Duration duration;
  final Widget Function(double animationValue) builder;

  const LoopingTweenBuilder({
    Key? key,
    this.delay = 0,
    required this.duration,
    required this.builder,
  }) : super(key: key);

  @override
  State<LoopingTweenBuilder> createState() => _LoopingTweenBuilderState();
}

class _LoopingTweenBuilderState extends State<LoopingTweenBuilder> {
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: widget.duration,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, _) {
        final av = (value - widget.delay).clamp(0.0, 1.0);
        return widget.builder(av);
      },
      onEnd: () {
        if (mounted) setState(() {});
      },
    );
  }
}

/// Error state widget for video player with retry action.
class VideoPlayerErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const VideoPlayerErrorWidget({
    Key? key,
    required this.message,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(PhosphorIconsLight.warningCircle,
              color: Colors.red, size: 64),
          const SizedBox(height: 16),
          Text(
            'Error playing media',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onRetry,
            child: Text(AppLocalizations.of(context)!.retry),
          ),
        ],
      ),
    );
  }
}

/// Loading state widget for video player with animated indicator.
class VideoPlayerLoadingWidget extends StatefulWidget {
  final String loadingMessage;
  final String fileName;

  const VideoPlayerLoadingWidget({
    Key? key,
    required this.loadingMessage,
    required this.fileName,
  }) : super(key: key);

  @override
  State<VideoPlayerLoadingWidget> createState() =>
      _VideoPlayerLoadingWidgetState();
}

class _VideoPlayerLoadingWidgetState extends State<VideoPlayerLoadingWidget> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildAnimatedLoadingIndicator(),
          const SizedBox(height: 24),
          Text(
            widget.loadingMessage,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.fileName,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w400,
                ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          _buildLoadingDots(),
        ],
      ),
    );
  }

  Widget _buildAnimatedLoadingIndicator() {
    const Color primaryColor = Colors.white;
    final progressColor = primaryColor.withValues(alpha: 0.3);
    return VideoPlayerCircularLoadingIndicator(
      size: 80,
      primaryColor: primaryColor,
      progressColor: progressColor,
      strokeWidth: 3,
      icon: PhosphorIconsLight.play,
      iconSize: 24,
      stackOverlays: [
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 1500),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.scale(
              scale: 0.5 + (0.5 * (0.5 + 0.5 * math.sin(value * 2 * math.pi))),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor.withValues(alpha: 0.8),
                  boxShadow: [],
                ),
              ),
            );
          },
          onEnd: () {
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildLoadingDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return LoopingTweenBuilder(
          delay: index * 0.2,
          duration: const Duration(milliseconds: 600),
          builder: (av) {
            final scale =
                0.5 + (0.5 * (0.5 + 0.5 * math.sin(av * 2 * math.pi)));
            final opacity =
                0.3 + (0.7 * (0.5 + 0.5 * math.sin(av * 2 * math.pi)));
            return Transform.scale(
              scale: scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: opacity),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

/// VLC-specific placeholder shown while VLC player is initializing.
class VideoPlayerVlcPlaceholder extends StatefulWidget {
  const VideoPlayerVlcPlaceholder({Key? key}) : super(key: key);

  @override
  State<VideoPlayerVlcPlaceholder> createState() =>
      _VideoPlayerVlcPlaceholderState();
}

class _VideoPlayerVlcPlaceholderState extends State<VideoPlayerVlcPlaceholder> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            VideoPlayerCircularLoadingIndicator(
              size: 60,
              primaryColor: Colors.orange,
              progressColor: Colors.orange.withValues(alpha: 0.6),
              strokeWidth: 2,
              icon: PhosphorIconsLight.playCircle,
              iconSize: 20,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w400,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return LoopingTweenBuilder(
                  delay: index * 0.3,
                  duration: const Duration(milliseconds: 800),
                  builder: (av) {
                    final opacity =
                        0.2 + (0.8 * (0.5 + 0.5 * math.sin(av * 2 * math.pi)));
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.orange.withValues(alpha: opacity),
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
