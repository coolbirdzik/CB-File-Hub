import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Mobile long-press overlay: left = rewind, right = fast forward.
class FastSeekGestureOverlay extends StatelessWidget {
  final VoidCallback onRewindStart;
  final VoidCallback onRewindEnd;
  final VoidCallback onForwardStart;
  final VoidCallback onForwardEnd;

  const FastSeekGestureOverlay({
    Key? key,
    required this.onRewindStart,
    required this.onRewindEnd,
    required this.onForwardStart,
    required this.onForwardEnd,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (_) => onRewindStart(),
              onLongPressEnd: (_) => onRewindEnd(),
              child: const SizedBox.expand(),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (_) => onForwardStart(),
              onLongPressEnd: (_) => onForwardEnd(),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlay showing current fast seek amount (+5s, -10s, +1m, etc.).
class FastSeekIndicator extends StatelessWidget {
  final bool isFastSeeking;
  final int fastSeekSeconds;
  final bool fastSeekingForward;

  const FastSeekIndicator({
    Key? key,
    required this.isFastSeeking,
    required this.fastSeekSeconds,
    required this.fastSeekingForward,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isFastSeeking) return const SizedBox.shrink();

    String speedText;
    if (fastSeekSeconds >= 60) {
      final mins = fastSeekSeconds ~/ 60;
      speedText = fastSeekingForward ? '+${mins}m' : '-${mins}m';
    } else {
      speedText =
          fastSeekingForward ? '+${fastSeekSeconds}s' : '-${fastSeekSeconds}s';
    }

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: isFastSeeking ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    fastSeekingForward
                        ? PhosphorIconsLight.fastForward
                        : PhosphorIconsLight.rewind,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    speedText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
