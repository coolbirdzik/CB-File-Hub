import 'package:flutter/material.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/services/media/subtitle_progress.dart';
import 'package:cb_file_manager/services/media/subtitle_languages.dart';
import 'video_player/video_player_utils.dart';

/// Only caption text occupies the picture; processing UI belongs to controls.
class SubtitleCaptionOverlay extends StatelessWidget {
  final String caption;
  final bool controlsVisible;
  const SubtitleCaptionOverlay({
    super.key,
    required this.caption,
    required this.controlsVisible,
  });

  @override
  Widget build(BuildContext context) {
    if (caption.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight < 300 || constraints.maxWidth < 420;
          final bottom = controlsVisible
              ? (compact ? 60.0 : 68.0)
              : (compact ? 10.0 : 24.0);
          if (constraints.maxHeight < bottom + 32) {
            return const SizedBox.shrink();
          }
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 8 : 24,
                0,
                compact ? 8 : 24,
                bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 900,
                  maxHeight: constraints.maxHeight - bottom - 8,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .78),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    caption,
                    key: const ValueKey('ai-subtitle-caption'),
                    textAlign: TextAlign.center,
                    maxLines: compact ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 16 : 22,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _SubtitleAction { settings, retry, regenerate, export }

/// One CC button in the existing playback row. Details/actions appear on demand.
class SubtitleControlButton extends StatelessWidget {
  final SubtitleProgress? progress;
  final VoidCallback onSettings, onRetry;
  final VoidCallback? onRegenerate;

  /// Saves finished cues as an SRT file wherever the user chooses.
  final VoidCallback? onExport;
  const SubtitleControlButton({
    super.key,
    this.progress,
    required this.onSettings,
    required this.onRetry,
    this.onRegenerate,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final current = this.progress;
    if (current == null || current.phase == SubtitlePhase.off) {
      return IconButton(
        key: const ValueKey('ai-subtitle-control'),
        tooltip: l.aiSubtitles,
        onPressed: onSettings,
        icon: const Icon(
          Icons.closed_caption_outlined,
          color: Colors.white70,
          size: 18,
        ),
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
      );
    }
    final progress = current;
    final failed = progress.phase == SubtitlePhase.failed;
    final warning =
        progress.phase == SubtitlePhase.missingModels || progress.lagging;
    final color = failed
        ? const Color(0xFFFF9696)
        : progress.busy || warning
        ? const Color(0xFFFFC36B)
        : const Color(0xFF61DEC9);
    final title = switch (progress.phase) {
      SubtitlePhase.off => l.aiSubtitleOff,
      SubtitlePhase.missingModels => l.aiSubtitleMissing,
      SubtitlePhase.failed => l.aiSubtitleFailed,
      SubtitlePhase.ready =>
        progress.cacheState == SubtitleCacheState.reused
            ? l.aiSubtitleCacheReused
            : progress.reachedEnd
            ? l.aiSubtitleComplete
            : l.aiSubtitleReady,
      SubtitlePhase.loading ||
      SubtitlePhase.processing => switch (progress.stage) {
        SubtitleWorkStage.loadingSpeech => l.aiSubtitleLoadingSpeech,
        SubtitleWorkStage.loadingTranslation => l.aiSubtitleLoadingTranslation,
        SubtitleWorkStage.recognizing => l.aiSubtitleRecognizing,
        SubtitleWorkStage.translating => l.aiSubtitleTranslating,
        SubtitleWorkStage.readingCache => l.aiSubtitleCacheReading,
        SubtitleWorkStage.idle => l.aiSubtitleProcessing,
      },
    };
    final model = progress.modelName;
    final source = progress.sourceLanguage;
    final target = progress.targetLanguage;
    final languages = source == null || target == null
        ? null
        : '${source == 'auto' ? 'Auto detect' : subtitleLanguageEnglishName(source)} → ${subtitleLanguageEnglishName(target)}';
    final cacheLabel = switch (progress.cacheState) {
      SubtitleCacheState.checking => l.aiSubtitleCacheReading,
      SubtitleCacheState.automatic => l.aiSubtitleCacheAutomatic,
      SubtitleCacheState.reused => l.aiSubtitleCacheReused,
      SubtitleCacheState.saved => l.aiSubtitleCacheSaved,
      SubtitleCacheState.failed => l.aiSubtitleCacheFailed,
      SubtitleCacheState.unavailable => l.aiSubtitleCacheUnavailable,
    };
    String time(Duration value) => VideoPlayerUtils.formatDuration(value);
    final processed = progress.processedUntil;
    final completedLabel = processed == null
        ? l.aiSubtitleNoProcessed
        : l.aiSubtitleProcessedUntil(
            time(processed),
            progress.duration > Duration.zero
                ? time(progress.duration)
                : '--:--',
          );
    final pending = progress.pending;
    final rangeLabel = pending == null
        ? null
        : l.aiSubtitleProcessingRange(time(pending.start), time(pending.end));
    final detail = [
      title,
      ?model,
      ?languages,
      completedLabel,
      ?rangeLabel,
      cacheLabel,
      if (progress.lagging) l.aiSubtitleLag,
      if (progress.error != null) progress.error!,
    ].join('\n');

    return PopupMenuButton<_SubtitleAction>(
      key: const ValueKey('ai-subtitle-control'),
      tooltip: detail,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(maxWidth: 360),
      onSelected: (action) {
        switch (action) {
          case _SubtitleAction.settings:
            onSettings();
          case _SubtitleAction.retry:
            onRetry();
          case _SubtitleAction.regenerate:
            onRegenerate?.call();
          case _SubtitleAction.export:
            onExport?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_SubtitleAction>(
          enabled: false,
          height: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              detail,
              key: const ValueKey('ai-subtitle-status'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _SubtitleAction.settings,
          child: Text(l.aiSubtitles),
        ),
        if (failed)
          PopupMenuItem(value: _SubtitleAction.retry, child: Text(l.retry)),
        if (onExport != null && progress.completed.isNotEmpty)
          PopupMenuItem(
            key: const ValueKey('ai-subtitle-export'),
            value: _SubtitleAction.export,
            child: Text(l.aiSubtitleExportSrt),
          ),
        if (onRegenerate != null)
          PopupMenuItem(
            key: const ValueKey('ai-subtitle-regenerate'),
            value: _SubtitleAction.regenerate,
            child: Text(l.aiSubtitleRegenerate),
          ),
      ],
      child: Semantics(
        button: true,
        label: '${l.aiSubtitles}: $title',
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                failed ? Icons.error_outline : Icons.closed_caption_outlined,
                color: color,
                size: 18,
              ),
              if (progress.busy)
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    key: const ValueKey('ai-subtitle-busy'),
                    strokeWidth: 1.5,
                    color: color,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tints only unplayed parts of the existing track with AI progress.
/// Slider hit testing, keyboard seeking and the playback thumb stay unchanged.
class SubtitleSeekTrackShape extends RoundedRectSliderTrackShape {
  final SubtitleProgress progress;
  const SubtitleSeekTrackShape(this.progress);
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    if (progress.phase == SubtitlePhase.off || !isEnabled) return;
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (track.isEmpty) return;
    final ltr = textDirection == TextDirection.ltr;
    final thumbX = thumbCenter.dx.clamp(track.left, track.right);
    context.canvas.save();
    context.canvas.clipRRect(
      RRect.fromRectAndRadius(track, Radius.circular(track.height / 2)),
    );
    // Played media stays white. AI ranges only tint what lies ahead of the
    // playback thumb, on the same baseline and within the same track height.
    context.canvas.clipRect(
      Rect.fromLTRB(
        ltr ? thumbX : track.left,
        track.top,
        ltr ? track.right : thumbX,
        track.bottom,
      ),
    );
    context.canvas.translate(ltr ? track.left : track.right, track.top);
    if (!ltr) context.canvas.scale(-1, 1);
    SubtitleTimelinePainter(
      progress,
      showPosition: false,
      showBackground: false,
    ).paint(context.canvas, track.size);
    context.canvas.restore();
  }
}

/// Green only covers finished intervals. Seeking/skipping never paints an
/// unprocessed prefix as complete. Amber denotes the current unfinished chunk.
class SubtitleTimelinePainter extends CustomPainter {
  final SubtitleProgress progress;
  final bool showPosition, showBackground;
  SubtitleTimelinePainter(
    this.progress, {
    this.showPosition = true,
    this.showBackground = true,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas.save();
    canvas.clipRRect(track);
    if (showBackground) {
      canvas.drawRRect(track, Paint()..color = Colors.white24);
    }
    final duration = progress.duration.inMilliseconds;
    if (duration > 0) {
      double x(Duration value) =>
          (value.inMilliseconds / duration).clamp(0.0, 1.0) * size.width;
      void range(SubtitleTimeRange span, Color color) {
        final left = x(span.start), right = x(span.end);
        if (right > left) {
          canvas.drawRect(
            Rect.fromLTRB(left, 0, right, size.height),
            Paint()..color = color,
          );
        }
      }

      for (final span in progress.completed) {
        range(span, const Color(0xFF61DEC9));
      }
      final pending = progress.pending;
      if (progress.busy && pending != null) {
        range(pending, const Color(0x99FFC36B));
      }
      if (showPosition) {
        final cursor = x(progress.position);
        canvas.drawRect(
          Rect.fromLTWH(cursor - 1, 0, 2, size.height),
          Paint()..color = Colors.white,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SubtitleTimelinePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.showPosition != showPosition ||
      oldDelegate.showBackground != showBackground;
}
