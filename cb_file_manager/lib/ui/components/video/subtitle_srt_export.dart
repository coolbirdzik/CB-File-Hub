import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;

import '../../../../config/languages/app_localizations.dart';
import '../../../../services/media/local_subtitle_session.dart';
import '../../../../services/media/subtitle_srt.dart';

/// Manual "Export SRT…": the user picks the destination, so it is offered in
/// every file mode and never runs without that explicit action.
Future<void> exportSubtitleSrt(
  BuildContext context,
  LocalSubtitleSession session,
) async {
  final l = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void show(String message) =>
      messenger?.showSnackBar(SnackBar(content: Text(message)));
  try {
    final cues = await session.exportCues();
    if (cues.isEmpty) {
      show(l.aiSubtitleExportEmpty);
      return;
    }
    final complete = session.progress.reachedEnd;
    final bytes = srtBytes(
      formatSrt(cues, bilingual: session.preferences.bilingual),
    );
    final source = session.player.subtitleCacheSource;
    final local = subtitleLocalVideoPath(source);
    final videoName =
        local ??
        Uri.tryParse(source ?? '')?.pathSegments.lastOrNull ??
        'subtitles';
    final saved = await FilePicker.saveFile(
      dialogTitle: l.aiSubtitleExportSrt,
      fileName: subtitleSrtFileName(videoName, session.exportLanguage),
      initialDirectory: local == null ? null : pathlib.dirname(local),
      bytes: Uint8List.fromList(bytes),
      mimeType: 'application/x-subrip',
    );
    if (saved == null) return;
    final path = saved.isScheme('file') ? saved.toFilePath() : '$saved';
    show(
      complete
          ? l.aiSubtitleExportSaved(path)
          : '${l.aiSubtitleExportSaved(path)}\n${l.aiSubtitleExportIncomplete}',
    );
  } catch (e) {
    show(l.aiSubtitleExportFailed('$e'));
  }
}

/// Announces automatic sidecars and the "ask" prompt from the session.
/// Returns the shown snack bars so the player can close them when it closes;
/// the messenger is app-wide and would otherwise keep them on the next screen.
List<ScaffoldFeatureController<SnackBar, SnackBarClosedReason>>
announceSubtitleExports(BuildContext context, LocalSubtitleSession session) {
  final shown = <ScaffoldFeatureController<SnackBar, SnackBarClosedReason>>[];
  final messenger = ScaffoldMessenger.maybeOf(context);
  // Without a Scaffold the messenger would assert; leave the notice pending.
  if (messenger == null || Scaffold.maybeOf(context) == null) return shown;
  final l = AppLocalizations.of(context)!;
  if (session.takeExportPrompt()) {
    shown.add(
      messenger.showSnackBar(
        SnackBar(
          key: const ValueKey('ai-subtitle-export-ready'),
          content: Text(l.aiSubtitleExportReady),
          duration: const Duration(seconds: 12),
          action: SnackBarAction(
            label: l.aiSubtitleExportSrt,
            onPressed: () {
              if (context.mounted) exportSubtitleSrt(context, session);
            },
          ),
        ),
      ),
    );
  }
  final notice = session.takeExportNotice();
  if (notice == null) return shown;
  final message = notice.localOnly
      ? l.aiSubtitleExportLocalOnly
      : notice.error != null
      ? l.aiSubtitleExportFailed('${notice.error}')
      : l.aiSubtitleExportSaved(notice.path!);
  shown.add(messenger.showSnackBar(SnackBar(content: Text(message))));
  return shown;
}
