import 'package:flutter/material.dart';

/// Centered on-screen display for transient feedback (volume, wheel seek,
/// mouse-wheel mode switch). Fades out when [visible] turns false.
class VideoPlayerOsd extends StatelessWidget {
  final bool visible;
  final IconData? icon;
  final String label;

  /// Optional 0..1 bar under the label (e.g. volume level).
  final double? progress;

  /// Optional small line at the bottom (e.g. how to switch wheel mode).
  final String? hint;

  const VideoPlayerOsd({
    super.key,
    required this.visible,
    required this.icon,
    required this.label,
    this.progress,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final hint = this.hint;

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 32),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 120,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 4,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  ],
                  if (hint != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
