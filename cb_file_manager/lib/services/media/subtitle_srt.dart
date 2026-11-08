import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as pathlib;
import 'package:shared_preferences/shared_preferences.dart';

import 'media_kit_playback.dart';
import 'subtitle_cache.dart';

/// Where finished AI subtitles go besides the app's own SQLite cache.
enum SubtitleFileMode {
  /// No file; subtitles are only reused inside the app.
  appOnly,

  /// Process the whole video, then offer a save dialog the user may ignore.
  askWhenDone,

  /// Process the whole video and write `Subs/<video>.<lang>.srt`.
  subsFolder,

  /// Process the whole video and write `<video>.<lang>.srt`, hidden.
  besideHidden;

  /// Linux has no hidden attribute and a dot prefix hides the file from
  /// players too, so the hidden sidecar is offered on Windows and macOS only.
  static List<SubtitleFileMode> get available => [
    for (final mode in values)
      if (mode != besideHidden || Platform.isWindows || Platform.isMacOS) mode,
  ];

  bool get writesAutomatically => this == subsFolder || this == besideHidden;
}

/// `<video name>.<language>.srt`, the sidecar name VLC, mpv, Plex and TVs
/// match to a video.
String subtitleSrtFileName(String videoPath, String language) =>
    '${pathlib.basenameWithoutExtension(videoPath)}.$language.srt';

/// The local path of a playback source, or null for http/SMB proxies whose
/// folder the app cannot write to.
String? subtitleLocalVideoPath(String? source) {
  if (source == null) return null;
  final uri = playbackSourceUri(source);
  if (uri.scheme != 'file') return null;
  return uri.toFilePath(windows: Platform.isWindows);
}

/// SubRip text. Cues are sorted and made non-overlapping: chunks generated on
/// both sides of a seek may overlap by the 800 ms recognition pre-roll, and
/// players would otherwise stack both lines.
String formatSrt(Iterable<LocalSubtitleCue> cues, {required bool bilingual}) {
  final sorted = [...cues]
    ..sort((a, b) {
      final start = a.startMs.compareTo(b.startMs);
      return start != 0 ? start : a.endMs.compareTo(b.endMs);
    });
  final out = StringBuffer();
  var index = 0;
  var previousEnd = 0;
  for (final cue in sorted) {
    final start = cue.startMs < previousEnd ? previousEnd : cue.startMs;
    if (cue.endMs <= start) continue; // Contained in the previous cue.
    final text = _cueText(cue, bilingual);
    if (text.isEmpty) continue;
    index++;
    out
      ..write('$index\r\n')
      ..write('${_time(start)} --> ${_time(cue.endMs)}\r\n')
      ..write('$text\r\n\r\n');
    previousEnd = cue.endMs;
  }
  return out.toString();
}

/// UTF-8 with a byte order mark: TVs and older Windows players otherwise
/// guess a legacy code page for Vietnamese, Japanese or Chinese text.
List<int> srtBytes(String srt) => [0xEF, 0xBB, 0xBF, ...utf8.encode(srt)];

String _cueText(LocalSubtitleCue cue, bool bilingual) {
  final lines = <String>[
    if (bilingual && cue.original.trim() != cue.text.trim()) cue.original,
    cue.text,
  ];
  // A blank line ends an SRT cue, so blank lines inside the text are dropped.
  return lines
      .expand((text) => const LineSplitter().convert(text))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\r\n');
}

String _time(int ms) {
  String two(int v) => v.toString().padLeft(2, '0');
  final hours = ms ~/ 3600000;
  final minutes = ms ~/ 60000 % 60;
  final seconds = ms ~/ 1000 % 60;
  final millis = (ms % 1000).toString().padLeft(3, '0');
  return '${two(hours)}:${two(minutes)}:${two(seconds)},$millis';
}

/// Result of an automatic sidecar write.
class SubtitleSrtWrite {
  final String path;

  /// False when the existing file already had identical content.
  final bool changed;
  const SubtitleSrtWrite(this.path, this.changed);
}

/// Writes sidecar files next to videos without ever replacing a subtitle file
/// the app did not create. Paths it wrote are remembered across windows.
class SubtitleSrtWriter {
  final SharedPreferences prefs;
  final Future<void> Function(String path, bool hidden) setHidden;
  SubtitleSrtWriter(
    this.prefs, {
    Future<void> Function(String, bool)? setHidden,
  }) : setHidden = setHidden ?? setFileHidden;

  static const writtenKey = 'ai_subtitles_written_srt';
  static const _maxRemembered = 2000;

  Future<SubtitleSrtWrite> write({
    required String videoPath,
    required String language,
    required SubtitleFileMode mode,
    required List<int> bytes,
  }) async {
    assert(mode.writesAutomatically);
    final folder = mode == SubtitleFileMode.subsFolder
        ? pathlib.join(pathlib.dirname(videoPath), 'Subs')
        : pathlib.dirname(videoPath);
    final hidden = mode == SubtitleFileMode.besideHidden;
    // The separate video window has its own preference cache.
    await prefs.reload();
    final written = {...?prefs.getStringList(writtenKey)};
    final name = subtitleSrtFileName(videoPath, language);
    var target = pathlib.join(folder, name);
    if (await File(target).exists() && !written.contains(_key(target))) {
      // Someone's own subtitle file: keep it and write beside it instead.
      target = pathlib.join(
        folder,
        '${pathlib.basenameWithoutExtension(name)}.ai.srt',
      );
      if (await File(target).exists() && !written.contains(_key(target))) {
        throw FileSystemException('A subtitle file already exists', target);
      }
    }
    final existing = File(target);
    if (await existing.exists() && _same(await existing.readAsBytes(), bytes)) {
      if (hidden) await setHidden(target, true);
      return SubtitleSrtWrite(target, false);
    }
    await Directory(folder).create(recursive: true);
    final temp = File('$target.cbpart');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      // Windows refuses to replace a hidden file with a normal one.
      if (await existing.exists()) await setHidden(target, false);
      await temp.rename(target);
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Best effort: never mask the write failure.
      }
    }
    if (hidden) await setHidden(target, true);
    final remembered = [
      ...?prefs.getStringList(writtenKey)?.where((p) => p != _key(target)),
      _key(target),
    ];
    await prefs.setStringList(
      writtenKey,
      remembered.length > _maxRemembered
          ? remembered.sublist(remembered.length - _maxRemembered)
          : remembered,
    );
    return SubtitleSrtWrite(target, true);
  }

  static String _key(String path) {
    final normal = pathlib.normalize(pathlib.absolute(path));
    return Platform.isWindows ? normal.toLowerCase() : normal;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Sets or clears the hidden flag Explorer/Finder honour. Linux has none.
Future<void> setFileHidden(String path, bool hidden) async {
  final ProcessResult result;
  if (Platform.isWindows) {
    result = await Process.run('attrib', [hidden ? '+h' : '-h', path]);
  } else if (Platform.isMacOS) {
    result = await Process.run('chflags', [
      hidden ? 'hidden' : 'nohidden',
      path,
    ]);
  } else {
    return;
  }
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Cannot change the hidden attribute: ${result.stdout}${result.stderr}'
          .trim(),
      path,
    );
  }
}
