import 'dart:math' as math;

import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../config/languages/app_localizations.dart';
import '../../widgets/app_progress_indicator.dart';

/// The Cleaner's progress bar: a thin rounded accent bar on the control
/// fill. Null [value] animates as indeterminate.
class CleanerProgressBar extends StatelessWidget {
  final double? value;

  const CleanerProgressBar({super.key, this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return ClipRRect(
      borderRadius: CbRadii.all(CbRadii.full),
      child: LinearProgressIndicator(
        value: value?.clamp(0.0, 1.0),
        minHeight: CbSpacing.xs,
        backgroundColor: CbDecorations.controlFill(c),
        color: c.accent.base,
      ),
    );
  }
}

/// A scan with nothing to show yet: loader, what is being read, a detail
/// line (counts), the current path and the bar, centered in the pane.
class CleanerScanPanel extends StatelessWidget {
  final String title;
  final String? detail;

  /// For tests that read the detail line.
  final Key? detailKey;

  /// The folder being read, muted and shortened.
  final String? path;
  final double? value;

  const CleanerScanPanel({
    super.key,
    required this.title,
    this.detail,
    this.detailKey,
    this.path,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final muted = CbTypography.bodySm.copyWith(color: c.textSecondary);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(CbSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppWaveLoader(size: 28, color: c.accent.base),
              const SizedBox(height: CbSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: CbTypography.label.copyWith(fontWeight: FontWeight.w600),
              ),
              if (detail != null) ...[
                const SizedBox(height: CbSpacing.xs),
                Text(
                  detail!,
                  key: detailKey,
                  textAlign: TextAlign.center,
                  style: muted,
                ),
              ],
              const SizedBox(height: CbSpacing.md),
              CleanerProgressBar(value: value),
              if (path != null && path!.isNotEmpty) ...[
                const SizedBox(height: CbSpacing.sm),
                Text(
                  path!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: muted.copyWith(color: c.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A scan still running above results already shown: loader, title, a
/// trailing count, an optional path and the bar, in a borderless block.
class CleanerScanStrip extends StatelessWidget {
  final String title;
  final String? trailing;
  final String? path;
  final double? value;

  const CleanerScanStrip({
    super.key,
    required this.title,
    this.trailing,
    this.path,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Container(
      padding: const EdgeInsets.all(CbSpacing.md),
      decoration: BoxDecoration(
        color: CbDecorations.controlFill(c),
        borderRadius: CbRadii.all(CbRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppWaveLoader(size: CbSizes.iconMd, color: c.accent.base),
              const SizedBox(width: CbSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CbTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: CbSpacing.sm),
                Text(
                  trailing!,
                  style: CbTypography.bodySm.copyWith(color: c.textSecondary),
                ),
              ],
            ],
          ),
          if (path != null && path!.isNotEmpty) ...[
            const SizedBox(height: CbSpacing.xs),
            Text(
              path!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CbTypography.bodySm.copyWith(color: c.textTertiary),
            ),
          ],
          const SizedBox(height: CbSpacing.sm),
          CleanerProgressBar(value: value),
        ],
      ),
    );
  }
}

/// [CleanerCleanStrip] fed by a listenable, so only the strip rebuilds per
/// progress message.
class CleanerCleanProgress extends StatelessWidget {
  final ValueListenable<(int done, int total, String? path)?> progress;

  const CleanerCleanProgress({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<(int, int, String?)?>(
      valueListenable: progress,
      builder: (context, value, _) {
        final (done, total, path) = value ?? (0, 0, null);
        return CleanerCleanStrip(done: done, total: total, path: path);
      },
    );
  }
}

/// Cleanup progress for a Cleaner footer: processed (or found, while
/// preparing) count, current path and the bar, as a [CleanerScanStrip].
class CleanerCleanStrip extends StatelessWidget {
  final int done;

  /// Zero while files are still being collected.
  final int total;
  final String? path;

  const CleanerCleanStrip({
    super.key,
    required this.done,
    required this.total,
    this.path,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CbSpacing.lg,
        CbSpacing.md,
        CbSpacing.lg,
        0,
      ),
      child: CleanerScanStrip(
        title: total > 0
            ? l.diskCleanerProcessedCount(done, total)
            : l.diskCleanerPreparingProgress(done),
        path: path,
        value: total > 0 ? done / total : null,
      ),
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
