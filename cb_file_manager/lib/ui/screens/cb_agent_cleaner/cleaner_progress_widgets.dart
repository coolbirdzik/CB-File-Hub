import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../config/languages/app_localizations.dart';
import '../../widgets/app_progress_indicator.dart';

/// Cleanup progress for a Cleaner footer: processed count, current path and
/// a determinate bar.
class CleanerCleanProgress extends StatelessWidget {
  final ValueListenable<(int done, int total, String? path)?> progress;

  const CleanerCleanProgress({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return ValueListenableBuilder<(int, int, String?)?>(
      valueListenable: progress,
      builder: (context, value, _) {
        final (done, total, path) = value ?? (0, 0, null);
        final fraction = total > 0 ? done / total : null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppWaveLoader(size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    total > 0
                        ? l.diskCleanerProcessedCount(done, total)
                        : l.diskCleanerPreparingFiles,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      path ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: fraction, minHeight: 8),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Fades and slides a child up once, delayed by its position in a list.
class CleanerStaggeredEntrance extends StatelessWidget {
  final int index;
  final Widget child;

  const CleanerStaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final delay = math.min(index, 8) * 55;
    const length = 320;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: delay + length),
      curve: Interval(delay / (delay + length), 1, curve: Curves.easeOutCubic),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
