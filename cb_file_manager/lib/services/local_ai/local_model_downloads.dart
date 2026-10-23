import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/local_ai/local_ai_advisor_model.dart';
import 'local_ai_advisor_service.dart';

/// One model download, in progress or failed.
class LocalModelDownload {
  final HuggingFaceModelEntry entry;
  int downloadedBytes = 0;
  int totalBytes;

  /// Set when the download failed; it stays listed so the user sees why.
  String? error;
  bool _cancelRequested = false;

  LocalModelDownload(this.entry) : totalBytes = entry.sizeBytes ?? 0;

  bool get failed => error != null;

  /// Fraction downloaded, or null while the size is unknown.
  double? get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

/// Model downloads that run in the background, independent of any screen, so
/// the user can close the installer or leave Settings while a model loads.
class LocalModelDownloads extends ChangeNotifier {
  final LocalAiAdvisorService _service;
  final _downloads = <String, LocalModelDownload>{};
  final _completed = StreamController<HuggingFaceModelEntry>.broadcast();

  /// Minimum gap between progress notifications; a download reports every
  /// network chunk.
  static const progressInterval = Duration(milliseconds: 200);

  LocalModelDownloads(this._service);

  /// Downloads in start order, failed ones included.
  List<LocalModelDownload> get downloads => _downloads.values.toList();

  LocalModelDownload? operator [](String catalogId) => _downloads[catalogId];

  bool isDownloading(String catalogId) {
    final download = _downloads[catalogId];
    return download != null && !download.failed;
  }

  /// Fires with each model once it is installed.
  Stream<HuggingFaceModelEntry> get onCompleted => _completed.stream;

  /// Starts downloading [entry] unless it is already downloading. A failed
  /// download of the same model is retried.
  void start(HuggingFaceModelEntry entry) {
    if (isDownloading(entry.id)) return;
    final download = LocalModelDownload(entry);
    _downloads[entry.id] = download;
    notifyListeners();
    unawaited(_run(download));
  }

  /// Stops a running download, or clears a failed one from the list.
  void cancel(String catalogId) {
    final download = _downloads[catalogId];
    if (download == null) return;
    if (download.failed) {
      _downloads.remove(catalogId);
      notifyListeners();
    } else {
      download._cancelRequested = true;
    }
  }

  Future<void> _run(LocalModelDownload download) async {
    var lastNotified = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await _service.installModel(
        download.entry,
        isCancelled: () => download._cancelRequested,
        onProgress: (progress) {
          download
            ..downloadedBytes = progress.downloadedBytes
            ..totalBytes = progress.totalBytes;
          final now = DateTime.now();
          if (now.difference(lastNotified) >= progressInterval) {
            lastNotified = now;
            notifyListeners();
          }
        },
      );
      _downloads.remove(download.entry.id);
      _completed.add(download.entry);
    } on LocalModelDownloadCancelled {
      _downloads.remove(download.entry.id);
    } catch (e) {
      download.error = e.toString();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final download in _downloads.values) {
      download._cancelRequested = true;
    }
    _completed.close();
    super.dispose();
  }
}
