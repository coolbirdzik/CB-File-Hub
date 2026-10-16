import 'dart:async';
import 'dart:math' as math;

import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/disk_cleaner/cleaner_suggestions.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_progress_indicator.dart';

/// Live progress of a Cleanup suggestions scan, in the same card style as
/// the Disk usage cleaning progress: current step and path, stat chips, a
/// determinate bar, and every checked source with what it has found so far.
class CleanerSuggestionScanPanel extends StatefulWidget {
  final ValueListenable<CleanerSuggestionProgress?> progress;
  final DateTime startedAt;
  final String Function(String categoryId) categoryLabel;

  const CleanerSuggestionScanPanel({
    super.key,
    required this.progress,
    required this.startedAt,
    required this.categoryLabel,
  });

  @override
  State<CleanerSuggestionScanPanel> createState() =>
      _CleanerSuggestionScanPanelState();
}

class _CleanerSuggestionScanPanelState
    extends State<CleanerSuggestionScanPanel> {
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed.value = DateTime.now().difference(widget.startedAt);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _elapsed.dispose();
    super.dispose();
  }

  String _sourceLabel(AppLocalizations l, String source) => switch (source) {
    CleanerSuggestionSource.downloads => l.cleanerSuggestionsSourceDownloads,
    CleanerSuggestionSource.system => l.cleanerSuggestionsSourceSystem,
    CleanerSuggestionSource.diskScan => l.cleanerSuggestionsSourceDiskScan,
    _ => widget.categoryLabel(source),
  };

  String _stepLabel(AppLocalizations l, CleanerSuggestionStep step) =>
      switch (step) {
        CleanerSuggestionStep.junk => l.cleanerSuggestionsStepJunk,
        CleanerSuggestionStep.downloads => l.cleanerSuggestionsStepDownloads,
        CleanerSuggestionStep.system => l.cleanerSuggestionsStepSystem,
        CleanerSuggestionStep.diskScan => l.cleanerSuggestionsStepDiskScan,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return ValueListenableBuilder<CleanerSuggestionProgress?>(
      valueListenable: widget.progress,
      builder: (context, progress, _) {
        final step = progress?.step ?? CleanerSuggestionStep.junk;
        final fraction = progress?.fraction ?? 0;
        final percent = (fraction * 100).floor();
        final sources = progress?.sources ?? const <String>[];
        final maxBytes = sources.fold<int>(
          1,
          (max, s) => math.max(max, progress!.sourceBytes[s] ?? 0),
        );
        return ListView(
          key: const ValueKey('cleaner-suggestions-progress'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: CbDecorations.card(context, radius: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          PhosphorIconsLight.magnifyingGlass,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _stepLabel(l, step),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              progress?.currentPath ?? '',
                              key: const ValueKey(
                                'cleaner-suggestions-progress-path',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      AppWaveLoader(size: 26, color: theme.colorScheme.primary),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(
                        icon: PhosphorIconsLight.files,
                        label: l.cleanerSuggestionsFoundItems(
                          progress?.itemsFound ?? 0,
                        ),
                      ),
                      _StatChip(
                        icon: PhosphorIconsLight.hardDrive,
                        label: l.cleanerSuggestionsFoundSize(
                          FormatUtils.formatFileSize(progress?.bytesFound ?? 0),
                        ),
                      ),
                      ValueListenableBuilder<Duration>(
                        valueListenable: _elapsed,
                        builder: (context, elapsed, _) => _StatChip(
                          icon: PhosphorIconsLight.timer,
                          label: _formatElapsed(elapsed),
                        ),
                      ),
                      _StatChip(
                        icon: PhosphorIconsLight.percent,
                        label: '$percent%',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: fraction),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        key: const ValueKey('cleaner-suggestions-progress-bar'),
                        value: value,
                        minHeight: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (sources.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Text(
                  l.cleanerSuggestionsSourcesTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: CbDecorations.card(context, radius: 12),
                child: Column(
                  children: [
                    for (final source in sources)
                      _SourceRow(
                        key: ValueKey('cleaner-suggestions-source-$source'),
                        label: _sourceLabel(l, source),
                        bytes: progress!.sourceBytes[source] ?? 0,
                        maxBytes: maxBytes,
                        state: progress.doneSources.contains(source)
                            ? _SourceState.done
                            : progress.activeSource == source
                            ? _SourceState.active
                            : _SourceState.waiting,
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _formatElapsed(Duration elapsed) {
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

enum _SourceState { waiting, active, done }

class _SourceRow extends StatelessWidget {
  final String label;
  final int bytes;
  final int maxBytes;
  final _SourceState state;

  const _SourceRow({
    super.key,
    required this.label,
    required this.bytes,
    required this.maxBytes,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final found = bytes > 0;
    final muted =
        state == _SourceState.waiting || (state == _SourceState.done && !found);
    final Widget status = switch (state) {
      _SourceState.active => AppWaveLoader(size: 16, color: scheme.primary),
      _SourceState.done => Icon(
        found ? Icons.check_circle_rounded : Icons.check_rounded,
        size: 16,
        color: found ? scheme.primary : scheme.outline,
      ),
      _SourceState.waiting => Icon(
        Icons.circle_outlined,
        size: 12,
        color: scheme.outlineVariant,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox.square(dimension: 20, child: Center(child: status)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
                fontWeight: state == _SourceState.active
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Bar length compares sources, so the biggest one stands out.
          SizedBox(
            width: 96,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: found ? bytes / maxBytes : 0),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(
              found ? FormatUtils.formatFileSize(bytes) : '—',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: found ? FontWeight.w700 : FontWeight.w400,
                color: found ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: CbDecorations.card(context, radius: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cleanup progress for the suggestions footer: processed count, current
/// path and a determinate bar.
class CleanerSuggestionsCleanProgress extends StatelessWidget {
  final ValueListenable<(int done, int total, String? path)?> progress;

  const CleanerSuggestionsCleanProgress({super.key, required this.progress});

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
