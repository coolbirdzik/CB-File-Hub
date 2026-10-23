import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart' show Locale;

import '../../config/languages/app_localizations_delegate.dart';
import '../../utils/app_logger.dart';
import 'torrent_entry.dart';
import 'torrent_service.dart';

typedef TorrentBackgroundNotice =
    Future<void> Function({
      required String title,
      required String body,
      required bool isError,
    });

/// No routes or focus changes: failures use the same notification path as
/// success, and the library retains download errors for later inspection.
class TorrentBackgroundReceiver {
  final TorrentService service;
  final TorrentBackgroundNotice notify;

  TorrentBackgroundReceiver(this.service, {this.notify = _notifyNative});

  Future<TorrentEntry?> receiveSource(String source) => _receive(
    () => service.openSourceInBackground(source),
    p.basename(source),
  );

  Future<TorrentEntry?> receiveEntry(TorrentEntry entry) =>
      _receive(() => service.downloadInBackground(entry), entry.name);

  Future<TorrentEntry?> _receive(
    Future<TorrentEntry> Function() action,
    String name,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final l = await const AppLocalizationsDelegate().load(
      Locale(prefs.getString('selected_language') ?? 'en'),
    );
    TorrentEntry? entry;
    Object? error;
    try {
      entry = await action();
    } catch (e, stack) {
      error = e;
      AppLogger.warning(
        'Background torrent import failed: $name',
        error: e,
        stackTrace: stack,
      );
    }
    try {
      await notify(
        title: error == null
            ? l.torrentBackgroundAdded
            : l.torrentBackgroundFailed,
        body: error == null
            ? '${entry!.name}\n${l.torrentStatus(entry.status)}'
            : '$name\n$error',
        isError: error != null,
      );
    } catch (e) {
      // Notification availability must never replay an already committed import.
      AppLogger.warning('Torrent notification unavailable: $e');
    }
    return entry;
  }

  static Future<void> _notifyNative({
    required String title,
    required String body,
    required bool isError,
  }) async {
    await const MethodChannel(
      'cb_file_manager/window_utils',
    ).invokeMethod<bool>('notifyTorrent', {
      'title': title,
      'body': body,
      'isError': isError,
    });
  }
}
