import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../services/media/local_subtitle_session.dart';
import '../../../../services/media/media_kit_playback.dart';
import '../../../../services/media/subtitle_services.dart';
import 'subtitle_status_overlay.dart';

/// Shared outer layer for local-file and network player layouts. Keeping the
/// session here prevents a surface-specific layout from skipping AI subtitles.
class LocalSubtitleLayer extends StatelessWidget {
  final PlaybackPlayer? player;
  final bool controlsVisible;
  final Widget child;

  const LocalSubtitleLayer({
    super.key,
    required this.player,
    required this.controlsVisible,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final playback = player;
    if (playback == null) return child;
    return LocalSubtitleOverlay(
      key: ObjectKey(playback),
      player: playback,
      controlsVisible: controlsVisible,
      child: child,
    );
  }
}

class LocalSubtitleOverlay extends StatefulWidget {
  final PlaybackPlayer player;
  final bool controlsVisible;
  final Widget child;
  const LocalSubtitleOverlay({
    super.key,
    required this.player,
    required this.controlsVisible,
    required this.child,
  });
  @override
  State<LocalSubtitleOverlay> createState() => _LocalSubtitleOverlayState();
}

class _LocalSubtitleOverlayState extends State<LocalSubtitleOverlay> {
  LocalSubtitleSession? _session;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final services = await SubtitleServices.load();
    if (!mounted) return;
    _session = LocalSubtitleSession(
      player: widget.player,
      preferences: services.preferences,
      models: services.models,
      cache: services.cache,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LocalSubtitleScope(
    session: _session,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(
          child: Builder(
            builder: (context) {
              final session = LocalSubtitleScope.of(context);
              if (session == null || !session.preferences.enabled) {
                return const SizedBox.shrink();
              }
              final caption =
                  session.preferences.bilingual &&
                      session.original != session.text
                  ? '${session.original}\n${session.text}'.trim()
                  : session.text;
              return SubtitleCaptionOverlay(
                caption: caption,
                controlsVisible: widget.controlsVisible,
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// One owner for inference; only caption/seek/control consumers rebuild on updates.
class LocalSubtitleScope extends InheritedNotifier<LocalSubtitleSession> {
  const LocalSubtitleScope({
    super.key,
    required LocalSubtitleSession? session,
    required super.child,
  }) : super(notifier: session);
  static LocalSubtitleSession? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LocalSubtitleScope>()
      ?.notifier;
}

class LocalSubtitleControls extends StatelessWidget {
  final VoidCallback onSettings;
  const LocalSubtitleControls({super.key, required this.onSettings});
  @override
  Widget build(BuildContext context) {
    final session = LocalSubtitleScope.of(context);
    return SubtitleControlButton(
      progress: session?.progress,
      onSettings: onSettings,
      onRetry: session?.restart ?? onSettings,
      onRegenerate: session?.canRegenerate == true
          ? () async {
              try {
                await session!.regenerate();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.maybeOf(
                    context,
                  )?.showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            }
          : null,
    );
  }
}
