import 'package:flutter/material.dart';

/// Slim 3px indeterminate progress bar, designed to be overlaid at the bottom
/// of a screen via [Positioned].  Used by the album detail screen and the
/// folder list screen so all loading indicators are visually consistent.
class SlimProgressBar extends StatelessWidget {
  const SlimProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      ),
      child: LinearProgressIndicator(
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation<Color>(
          colorScheme.primary.withValues(alpha: 0.8),
        ),
        minHeight: 3,
      ),
    );
  }
}
