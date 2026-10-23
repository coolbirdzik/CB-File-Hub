import 'package:flutter/services.dart';
import 'cleaner_models.dart';

abstract final class MacosCleanerPlatform {
  static const channel = MethodChannel('cb_file_manager/macos_window');
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
