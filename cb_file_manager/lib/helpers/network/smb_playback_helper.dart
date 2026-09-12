import 'dart:io';
import 'package:flutter/material.dart';
import '../files/file_type_registry.dart';
import '../../services/network_browsing/i_smb_service.dart';
import '../../config/languages/app_localizations.dart';
import '../../ui/components/video/video_player/video_player.dart';
// Unified player is StreamingMediaPlayer; this file only builds URLs.
import '../../ui/utils/route.dart';

/// Helper để mở media với Native SMB streaming
/// Stream trực tiếp từ SMB sử dụng thư viện mobile_smb_native
class SmbPlaybackHelper {
  /// Mở video/audio với Native SMB streaming
  /// Sử dụng mobile_smb_native để stream trực tiếp từ SMB
  static Future<void> openMediaWithSmbPlayback({
    required BuildContext context,
    required String smbPath,
    required String fileName,
    required FileCategory fileType,
    required ISmbService smbService,
  }) async {
    debugPrint('[SmbPlaybackHelper] ENTERING openMediaWithSmbPlayback');
    try {
      // Kiểm tra file type
      if (!_isSupportedMediaType(fileType)) {
        throw Exception('Unsupported media type: $fileType');
      }

      if (!smbService.isConnected) {
        // Continue: we can still attempt to build a direct SMB URL without an active connection.
      }

      debugPrint('SmbPlaybackHelper: Opening media with Native SMB streaming');
      debugPrint('SmbPlaybackHelper: SMB Path: $smbPath');
      debugPrint('SmbPlaybackHelper: File Name: $fileName');
      debugPrint('SmbPlaybackHelper: File Type: $fileType');

      // Create SMB MRL URL with credentials if available
      String smbUrl;
      try {
        final directLink = await smbService.getSmbDirectLink(smbPath);
        if (directLink != null && directLink.isNotEmpty) {
          smbUrl = directLink;
          debugPrint('SmbPlaybackHelper: Using direct link with credentials');
        } else {
          final basePath = smbService.basePath;
          if (basePath.isEmpty) {
            throw Exception('SMB base path not available');
          }
          smbUrl = createSmbUrl(smbService: smbService, smbPath: smbPath);
          debugPrint('SmbPlaybackHelper: Using base SMB URL');
        }
      } catch (_) {
        final basePath = smbService.basePath;
        if (basePath.isEmpty) {
          throw Exception('SMB base path not available');
        }
        // Fallback if credential fetch fails
        smbUrl = createSmbUrl(smbService: smbService, smbPath: smbPath);
        debugPrint('SmbPlaybackHelper: Fallback to base SMB URL');
      }

      // Open with the unified StreamingMediaPlayer directly
      if (context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => Scaffold(
              backgroundColor: Colors.black,
              appBar: (Platform.isAndroid || Platform.isIOS)
                  ? null
                  : AppBar(
                      leading: const BackButton(color: Colors.white),
                      title: Text(
                        fileName,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.black54,
                      iconTheme: const IconThemeData(color: Colors.white),
                    ),
              body: SafeArea(
                top: Platform.isAndroid || Platform.isIOS,
                bottom: Platform.isAndroid || Platform.isIOS,
                child: VideoPlayer.smb(
                  smbMrl: smbUrl,
                  fileName: fileName,
                  fileType: fileType,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('SmbPlaybackHelper: Error opening media: $e');

      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        RouteUtils.showAcrylicDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.mediaPlaybackError),
            content: Text(l10n.mediaPlaybackErrorSmbContent(e.toString())),
            actions: [
              TextButton(
                onPressed: () => RouteUtils.safePopDialog(ctx),
                child: Text(l10n.ok),
              ),
            ],
          ),
        );
      }

      rethrow;
    }
  }

  /// Kiểm tra xem có thể stream trực tiếp với media_kit không
  static bool canStreamDirectly(FileCategory fileType) {
    return _isSupportedMediaType(fileType);
  }

  /// Creates an SMB URL from the SMB service and an internal SMB tab path.
  ///
  /// Avoid duplicating the share name: if `basePath` is already `smb://host/share` then the
  /// appended path must only include segments after the share (e.g. `folder/file`).
  static String createSmbUrl({
    required ISmbService smbService,
    required String smbPath,
  }) {
    if (!smbService.isConnected) {
      throw Exception('SMB service not connected');
    }

    // Base path from service (e.g. smb://host or smb://host/share)
    final basePath = smbService.basePath;
    final baseUri = Uri.tryParse(basePath);
    final basePathSegments = baseUri != null
        ? baseUri.pathSegments.where((s) => s.isNotEmpty).toList()
        : <String>[];

    // Normalize: '#network/SMB/<host>/<share>/subdir/file' -> 'share/subdir/file'.
    String normalized = smbPath;
    final lower = normalized.toLowerCase();
    if (lower.startsWith('#network/smb/')) {
      normalized = normalized.substring('#network/smb/'.length);
      final firstSlash = normalized.indexOf('/');
      if (firstSlash != -1) {
        normalized = normalized.substring(firstSlash + 1);
      } else {
        normalized = '';
      }
    }

    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }

    var segments = normalized.split('/').where((s) => s.isNotEmpty).toList();

    // If basePath already includes a share (smb://host/share), drop the share segment from the
    // normalized path to avoid smb://host/share/share/folder/file.
    if (basePathSegments.isNotEmpty && segments.isNotEmpty) {
      segments = segments.sublist(1);
    }

    final pathToAppend = segments.join('/');
    final encodedPath = _encodeSmbPath(pathToAppend);

    final needsSlash = !basePath.endsWith('/');
    final prefix = needsSlash ? '$basePath/' : basePath;
    return encodedPath.isEmpty
        ? basePath.replaceAll(RegExp(r'/$'), '')
        : '$prefix$encodedPath';
  }

  /// Kiểm tra file type có được hỗ trợ không
  static bool _isSupportedMediaType(FileCategory fileType) {
    switch (fileType) {
      case FileCategory.video:
      case FileCategory.audio:
        return true;
      case FileCategory.image:
      case FileCategory.document:
      case FileCategory.archive:
      default:
        return false;
    }
  }

  static String _encodeSmbPath(String path) {
    if (path.isEmpty) return path;
    final normalized = path.replaceAll('\\', '/');
    return normalized
        .replaceAll('%', '%25')
        .replaceAll('#', '%23')
        .replaceAll('?', '%3F')
        .replaceAll(' ', '%20');
  }

  /// Lấy danh sách các format được hỗ trợ bởi media_kit
  static List<String> getSupportedVideoFormats() {
    return [
      'mp4',
      'avi',
      'mkv',
      'mov',
      'wmv',
      'flv',
      'webm',
      'm4v',
      'mpg',
      'mpeg',
      '3gp',
      'asf',
      'rm',
      'rmvb',
      'vob',
      'ts',
      'mts',
      'm2ts',
      'divx',
      'xvid',
      'ogv',
      'dv',
      'mxf',
    ];
  }

  static List<String> getSupportedAudioFormats() {
    return [
      'mp3',
      'wav',
      'flac',
      'aac',
      'ogg',
      'wma',
      'm4a',
      'opus',
      'ac3',
      'dts',
      'ape',
      'aiff',
      'au',
      'ra',
      'amr',
      'awb',
    ];
  }

  /// Kiểm tra extension có được hỗ trợ không
  static bool isSupportedExtension(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    return getSupportedVideoFormats().contains(ext) ||
        getSupportedAudioFormats().contains(ext);
  }

  /// Lấy thông tin về media_kit capabilities
  static Map<String, dynamic> getPlaybackCapabilities() {
    return {
      'direct_smb_streaming': true,
      'hardware_acceleration': true,
      'seek_support': true,
      'playback_speed_control': true,
      'volume_control': true,
      'subtitle_support': true,
      'audio_track_selection': true,
      'video_track_selection': true,
      'supported_protocols': ['smb', 'http', 'https', 'ftp', 'rtsp', 'rtmp'],
      'supported_video_codecs': [
        'H.264',
        'H.265/HEVC',
        'VP8',
        'VP9',
        'AV1',
        'MPEG-2',
        'MPEG-4',
        'DivX',
        'XviD',
        'WMV',
        'FLV',
        'Theora',
      ],
      'supported_audio_codecs': [
        'AAC',
        'MP3',
        'FLAC',
        'Vorbis',
        'Opus',
        'AC-3',
        'DTS',
        'PCM',
        'WMA',
        'ALAC',
      ],
    };
  }

  /// Debug info cho troubleshooting
  static void printDebugInfo({
    required ISmbService smbService,
    required String smbPath,
    required String fileName,
    required FileCategory fileType,
  }) {
    debugPrint('=== media_kit Direct SMB Debug Info ===');
    debugPrint('SMB Service Connected: ${smbService.isConnected}');
    debugPrint('SMB Service connected: ${smbService.isConnected}');
    debugPrint('SMB Path: $smbPath');
    debugPrint('File Name: $fileName');
    debugPrint('File Type: $fileType');
    debugPrint('Supported: ${_isSupportedMediaType(fileType)}');

    try {
      final smbUrl = createSmbUrl(smbService: smbService, smbPath: smbPath);
      debugPrint(
        'Generated SMB URL: ${Uri.parse(smbUrl).replace(userInfo: '')}',
      );
    } catch (e) {
      debugPrint('Error creating SMB URL: $e');
    }

    debugPrint('media_kit Capabilities: ${getPlaybackCapabilities()}');
    debugPrint('================================');
  }
}
