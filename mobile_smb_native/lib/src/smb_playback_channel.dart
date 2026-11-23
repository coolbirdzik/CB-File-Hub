import 'package:flutter/services.dart';

import 'mobile_smb_native_platform_interface.dart';
import 'smb_connection_config.dart';

class SmbPlaybackChannel implements SmbPlaybackReader {
  SmbPlaybackChannel._(this._id, this.fileSize);

  static const _channel = MethodChannel('mobile_smb_native/playback');

  static Future<SmbPlaybackReader?> open(
    SmbConnectionConfig config,
    String path,
  ) async {
    try {
      final reader = await _channel.invokeMapMethod<String, Object?>('open', {
        ...config.toMap(),
        'path': path,
      });
      return SmbPlaybackChannel._(
        reader!['id'] as String,
        reader['size'] as int,
      );
    } on MissingPluginException {
      return null;
    }
  }

  final String _id;

  @override
  final int fileSize;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final bytes = await _channel.invokeMethod<Uint8List>('read', {
      'id': _id,
      'offset': offset,
      'length': length,
    });
    return bytes!;
  }

  @override
  Future<void> close() => _channel.invokeMethod<void>('close', {'id': _id});
}
