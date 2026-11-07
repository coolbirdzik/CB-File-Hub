import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'cleaner_models.dart';

abstract final class MacosCleanerPlatform {
  static const channel = MethodChannel('cb_file_manager/macos_window');
  static const volumeEvents = EventChannel('cb_file_manager/cleaner_volumes');
  static final Stream<void> volumeChanges = volumeEvents
      .receiveBroadcastStream()
      .map<void>((_) {});
  static Future<void> openTrash() =>
      channel.invokeMethod<void>('openCleanerTrash');
  static Future<List<DriveSpace>> volumes() async {
    final rows = await channel.invokeListMethod<dynamic>('getCleanerVolumes');
    return [
      for (final row in rows ?? const [])
        if (row is Map && row['path'] is String)
          DriveSpace(
            path: row['path'] as String,
            label: row['label'] as String? ?? '',
            totalBytes: (row['totalBytes'] as num?)?.toInt() ?? 0,
            freeBytes: (row['freeBytes'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  static final Map<String, Future<ui.Image?>> _icons = {};

  /// The Finder icon of [path] (an app bundle), [pixels] square. Kept for
  /// the session; null when the path has none or the channel is missing.
  static Future<ui.Image?> appIcon(String path, int pixels) =>
      _icons.putIfAbsent('$pixels|$path', () async {
        try {
          final bytes = await channel.invokeMethod<Uint8List>(
            'cleanerAppIcon',
            {'path': path, 'size': pixels},
          );
          if (bytes == null || bytes.isEmpty) return null;
          final codec = await ui.instantiateImageCodec(bytes);
          return (await codec.getNextFrame()).image;
        } on PlatformException {
          return null;
        } on MissingPluginException {
          return null;
        }
      });

  /// Returns a result for every requested path, including permission failures.
  static Future<Map<String, String?>> trash(List<String> paths) async {
    final rows = await channel.invokeListMethod<dynamic>('trashCleanerItems', {
      'paths': paths,
    });
    final result = <String, String?>{
      for (final path in paths) path: 'No Trash result returned',
    };
    for (final row in rows ?? const []) {
      if (row is Map && result.containsKey(row['path'])) {
        result[row['path'] as String] = row['error'] as String?;
      }
    }
    return result;
  }
}
