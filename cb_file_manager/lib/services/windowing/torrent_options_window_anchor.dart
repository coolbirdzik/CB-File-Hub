import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Windows uses a live HWND so coordinates never cross mixed-DPI spaces.
/// Other desktop hosts exchange logical window bounds instead.
class TorrentOptionsWindowAnchor {
  final int? windowId;
  final Rect? bounds;

  const TorrentOptionsWindowAnchor({this.windowId, this.bounds});

  static Future<TorrentOptionsWindowAnchor> capture() async {
    try {
      return Platform.isWindows
          ? TorrentOptionsWindowAnchor(windowId: await windowManager.getId())
          : TorrentOptionsWindowAnchor(bounds: await windowManager.getBounds());
    } catch (_) {
      return const TorrentOptionsWindowAnchor();
    }
  }

  factory TorrentOptionsWindowAnchor.fromJson(Map<String, dynamic> json) {
    final id = json['windowId'];
    final rect = json['bounds'];
    Rect? bounds;
    if (rect is List &&
        rect.length == 4 &&
        rect.every((value) => value is num && value.isFinite)) {
      final values = rect.cast<num>();
      if (values[2] > 0 && values[3] > 0) {
        bounds = Rect.fromLTWH(
          values[0].toDouble(),
          values[1].toDouble(),
          values[2].toDouble(),
          values[3].toDouble(),
        );
      }
    }
    return TorrentOptionsWindowAnchor(
      windowId: id is int && id > 0 ? id : null,
      bounds: bounds,
    );
  }

  Map<String, dynamic> toJson() => {
    'windowId': ?windowId,
    if (bounds case final rect?)
      'bounds': [rect.left, rect.top, rect.width, rect.height],
  };

  /// Called while hidden, before painting the next form at its target DPI.
  Future<void> place() async {
    if (Platform.isWindows) {
      final positioned = await const MethodChannel(
        'cb_file_manager/torrent_options_window',
      ).invokeMethod<bool>('centerOnParent', {'parentWindowId': windowId});
      if (positioned == true) return;
    } else if (bounds case final parent?) {
      final size = await windowManager.getSize();
      await windowManager.setPosition(
        parent.center - Offset(size.width / 2, size.height / 2),
      );
      return;
    }
    await windowManager.center();
  }
}
