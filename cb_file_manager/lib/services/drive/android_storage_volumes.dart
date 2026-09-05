import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart side of `cb_file_manager/storage_volumes` (Android).
class AndroidStorageVolumes {
  AndroidStorageVolumes._();

  static const MethodChannel _channel = MethodChannel(
    'cb_file_manager/storage_volumes',
  );

  /// Lists mounted volumes with optional space metadata.
  static Future<List<AndroidStorageVolume>> listVolumes() async {
    if (kIsWeb) return const <AndroidStorageVolume>[];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listVolumes');
      if (raw == null) return const <AndroidStorageVolume>[];
      return raw
          .whereType<Map>()
          .map(
            (row) =>
                AndroidStorageVolume.fromMap(Map<String, dynamic>.from(row)),
          )
          .where((v) => v.path.isNotEmpty)
          .toList();
    } on MissingPluginException {
      return const <AndroidStorageVolume>[];
    } on PlatformException catch (e) {
      debugPrint('AndroidStorageVolumes.listVolumes failed: $e');
      return const <AndroidStorageVolume>[];
    }
  }

  static Future<bool> ejectVolume({required String path, String? uuid}) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'ejectVolume',
        <String, dynamic>{
          'path': path,
          if (uuid != null && uuid.isNotEmpty) 'uuid': uuid,
        },
      );
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('AndroidStorageVolumes.ejectVolume failed: $e');
      return false;
    }
  }

  static Future<bool> renameVolume({
    required String path,
    required String label,
    String? uuid,
  }) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('renameVolume', <String, dynamic>{
            'path': path,
            'label': label,
            if (uuid != null && uuid.isNotEmpty) 'uuid': uuid,
          });
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('AndroidStorageVolumes.renameVolume failed: $e');
      return false;
    }
  }
}

class AndroidStorageVolume {
  final String path;
  final String label;
  final String? uuid;
  final String description;
  final bool isPrimary;
  final bool isRemovable;
  final bool canEject;
  final int totalBytes;
  final int freeBytes;
  final String filesystem;

  const AndroidStorageVolume({
    required this.path,
    this.label = '',
    this.uuid,
    this.description = '',
    this.isPrimary = false,
    this.isRemovable = false,
    this.canEject = false,
    this.totalBytes = 0,
    this.freeBytes = 0,
    this.filesystem = '',
  });

  factory AndroidStorageVolume.fromMap(Map<String, dynamic> map) {
    return AndroidStorageVolume(
      path: (map['path'] as String?)?.trim() ?? '',
      label: (map['label'] as String?)?.trim() ?? '',
      uuid: (map['uuid'] as String?)?.trim(),
      description: (map['description'] as String?)?.trim() ?? '',
      isPrimary: map['isPrimary'] == true,
      isRemovable: map['isRemovable'] == true,
      canEject: map['canEject'] == true,
      totalBytes: _asInt(map['totalBytes']),
      freeBytes: _asInt(map['freeBytes']),
      filesystem: (map['filesystem'] as String?)?.trim() ?? '',
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
