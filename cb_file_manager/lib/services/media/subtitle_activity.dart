import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pathlib;

/// Whether a player is generating subtitles right now, in any window.
///
/// The batch queue yields the GPU/CPU to a video the user is watching. Players
/// in this isolate are counted in [local]; players in other windows (separate
/// engines or processes) touch a small heartbeat file in the temp folder.
class SubtitleActivity {
  SubtitleActivity._();

  /// Interactive sessions of this isolate that are loading or processing.
  static final local = ValueNotifier<int>(0);

  /// Tests point this at a sandbox.
  @visibleForTesting
  static String? fileOverride;

  static const _beatInterval = Duration(seconds: 4);
  static const activeWindow = Duration(seconds: 12);
  static int _lastBeatMs = 0;

  static File get _file => File(
    fileOverride ??
        pathlib.join(
          Directory.systemTemp.path,
          'cb-file-hub-subtitle-activity',
        ),
  );

  /// Called while an interactive session works. Throttled; never throws.
  static void beat() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBeatMs < _beatInterval.inMilliseconds) return;
    _lastBeatMs = now;
    unawaited(
      _file.writeAsString('$now').then<void>((_) {}, onError: (Object _) {}),
    );
  }

  /// True while this isolate or another window generated subtitles for a
  /// video being watched within [activeWindow].
  static Future<bool> isActive() async {
    if (local.value > 0) return true;
    try {
      final at = int.tryParse((await _file.readAsString()).trim()) ?? 0;
      return DateTime.now().millisecondsSinceEpoch - at <
          activeWindow.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    local.value = 0;
    _lastBeatMs = 0;
  }
}
