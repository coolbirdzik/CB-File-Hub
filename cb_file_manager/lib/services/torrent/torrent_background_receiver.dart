import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart' show Locale;

import '../../config/languages/app_localizations_delegate.dart';
import '../../core/service_locator.dart';
import '../../ui/controllers/operation_progress_controller.dart';
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
/// Each result is also recorded in the Status Center.
class TorrentBackgroundReceiver {
  final TorrentService service;
  final TorrentBackgroundNotice notify;
  final OperationProgressController? statusCenter;

  TorrentBackgroundReceiver(
    this.service, {
    this.notify = _notifyNative,
    OperationProgressController? statusCenter,
  }) : statusCenter =
           statusCenter ??
           (locator.isRegistered<OperationProgressController>()
               ? locator<OperationProgressController>()
               : null);

  Future<TorrentEntry?> receiveSource(String source) => _receive(
    () => service.openSourceInBackground(source),
    p.basename(source),
  );

  /// [existed] is set by callers that just imported [entry] from a link and
  /// found it already in the library.
  Future<TorrentEntry?> receiveEntry(
    TorrentEntry entry, {
    bool existed = false,
  }) => _receive(
    () async =>
        (entry: await service.downloadInBackground(entry), existed: existed),
    entry.name,
  );

  Future<TorrentEntry?> _receive(
    Future<({TorrentEntry entry, bool existed})> Function() action,
    String name,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final l = await const AppLocalizationsDelegate().load(
      Locale(prefs.getString('selected_language') ?? 'en'),
    );
    TorrentEntry? entry;
    var existed = false;
    Object? error;
    try {
      (:entry, :existed) = await action();
    } catch (e, stack) {
      error = e;
      AppLogger.warning(
        'Background torrent import failed: $name',
        error: e,
        stackTrace: stack,
      );
    }
    final title = error != null
        ? l.torrentBackgroundFailed
        : existed
        ? l.torrentBackgroundAlreadyExists
        : l.torrentBackgroundAdded;
    final body = error == null
        ? '${entry!.name}\n${l.torrentStatus(entry.status)}'
        : '$name\n$error';
    _recordStatus(title, body, isError: error != null);
    try {
      await notify(title: title, body: body, isError: error != null);
    } catch (e) {
      // Notification availability must never replay an already committed import.
      AppLogger.warning('Torrent notification unavailable: $e');
    }
    return entry;
  }

  void _recordStatus(String title, String body, {required bool isError}) {
    final status = statusCenter;
    if (status == null) return;
    final id = status.begin(
      title: title,
      total: 1,
      detail: body,
      kind: OperationProgressKind.network,
    );
    if (isError) {
      status.fail(id, detail: body);
    } else {
      status.succeed(id, detail: body);
    }
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
