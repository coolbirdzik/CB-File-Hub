import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_smb_native/mobile_smb_native.dart';
import '../files/file_type_registry.dart';
import '../../services/network_browsing/i_smb_service.dart';
import '../../config/languages/app_localizations.dart';
import '../../ui/components/video/video_player/video_player.dart';
import 'smb_playback_helper.dart';
import '../../ui/utils/route.dart';

/// Helper để mở media với Native media_kit Direct SMB streaming
/// Sử dụng mobile_smb_native để tạo SMB URL trực tiếp cho media_kit
class NativeSmbPlaybackHelper {
  /// Mở video/audio với Native media_kit Direct SMB streaming
  /// Sử dụng mobile_smb_native để tạo SMB URL trực tiếp cho media_kit
  static Future<void> openMediaWithNativeSmbPlayback({
    required BuildContext context,
    required String smbPath,
    required String fileName,
    required FileCategory fileType,
    required ISmbService smbService,
  }) async {
    debugPrint(
      '[NativeSmbPlaybackHelper] ENTERING openMediaWithNativeSmbPlayback',
    );
    try {
      // Kiểm tra file type
      if (!_isSupportedMediaType(fileType)) {
        throw Exception('Unsupported media type: $fileType');
      }

      if (!smbService.isConnected) {
        // Continue: we can still attempt to build a direct SMB URL without an active connection.
      }

      debugPrint(
        'NativeSmbPlaybackHelper: Opening media with Native media_kit Direct SMB streaming',
      );
      debugPrint('NativeSmbPlaybackHelper: SMB Path: $smbPath');
      debugPrint('NativeSmbPlaybackHelper: File Name: $fileName');
      debugPrint('NativeSmbPlaybackHelper: File Type: $fileType');

      // Resolve REAL SMB MRL (prefer native direct link with credentials)
      String finalSmbMrl;
      try {
        final directLink = await smbService.getSmbDirectLink(smbPath);
        if (directLink != null && directLink.isNotEmpty) {
          finalSmbMrl = directLink;
          debugPrint(
            'NativeSmbPlaybackHelper: Using direct SMB link from service',
          );
        } else {
          final basePath = smbService.basePath;
          if (basePath.isEmpty) {
            throw Exception('SMB base path not available');
          }
          finalSmbMrl = SmbPlaybackHelper.createSmbUrl(
            smbService: smbService,
            smbPath: smbPath,
          );
          debugPrint('NativeSmbPlaybackHelper: Using constructed SMB URL');
        }
      } catch (_) {
        final basePath = smbService.basePath;
        if (basePath.isEmpty) {
          throw Exception('SMB base path not available');
        }
        finalSmbMrl = SmbPlaybackHelper.createSmbUrl(
          smbService: smbService,
          smbPath: smbPath,
        );
        debugPrint('NativeSmbPlaybackHelper: Fallback to constructed SMB URL');
      }

      debugPrint(
        'NativeSmbPlaybackHelper: Final SMB MRL => ${Uri.parse(finalSmbMrl).replace(userInfo: '')}',
      );

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
                  smbMrl: finalSmbMrl,
                  fileName: fileName,
                  fileType: fileType,
                ),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('NativeSmbPlaybackHelper: Error opening media: $e');

      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        RouteUtils.showAcrylicDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.mediaPlaybackError),
            content: Text(l10n.mediaPlaybackErrorNativeContent(e.toString())),
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

  /// Kiểm tra xem có thể stream trực tiếp với Native media_kit không
  static bool canStreamDirectly(FileCategory fileType) {
    return _isSupportedMediaType(fileType);
  }

  /// Kiểm tra xem Native SMB client có sẵn sàng không
  static Future<bool> isNativeSmbAvailable() async {
    try {
      // Try to initialize the native SMB service
      // This will throw an exception if the native library is not available
      SmbNativeService.instance;
      return true;
    } catch (e) {
      debugPrint('NativeSmbPlaybackHelper: Native SMB not available: $e');
      return false;
    }
  }

  /// Kiểm tra xem có thể sử dụng Native media_kit Direct streaming không
  static Future<bool> canUseNativeSmbPlayback({
    required FileCategory fileType,
    required ISmbService smbService,
  }) async {
    debugPrint(
      'NativeSmbPlaybackHelper: Checking if can use Native media_kit Direct...',
    );
    debugPrint('NativeSmbPlaybackHelper: File type: $fileType');
    debugPrint(
      'NativeSmbPlaybackHelper: SMB service type: ${smbService.runtimeType}',
    );
    debugPrint(
      'NativeSmbPlaybackHelper: SMB service connected: ${smbService.isConnected}',
    );

    // Kiểm tra file type
    if (!_isSupportedMediaType(fileType)) {
      debugPrint(
        'NativeSmbPlaybackHelper: ❌ File type not supported: $fileType',
      );
      return false;
    }
    debugPrint('NativeSmbPlaybackHelper: ✅ File type supported: $fileType');

    // Kiểm tra kết nối SMB
    if (!smbService.isConnected) {
      debugPrint('NativeSmbPlaybackHelper: ❌ SMB service not connected');
      return false;
    }
    debugPrint('NativeSmbPlaybackHelper: ✅ SMB service connected');

    // Kiểm tra Native SMB availability
    final nativeAvailable = await isNativeSmbAvailable();
    if (!nativeAvailable) {
      debugPrint('NativeSmbPlaybackHelper: ❌ Native SMB not available');
      return false;
    }
    debugPrint('NativeSmbPlaybackHelper: ✅ Native SMB available');

    debugPrint(
      'NativeSmbPlaybackHelper: ✅ All checks passed - can use Native media_kit Direct',
    );
    return true;
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

  /// Lấy danh sách các format audio được hỗ trợ bởi media_kit
  static List<String> getSupportedAudioFormats() {
    return [
      'mp3',
      'wav',
      'flac',
      'aac',
      'ogg',
      'm4a',
      'wma',
      'opus',
      'ac3',
      'dts',
      'ra',
      'amr',
      'ape',
      'wv',
      'tta',
      'alac',
      'aiff',
      'au',
      'snd',
      'mid',
      'midi',
      'kar',
      'rmi',
    ];
  }

  /// So sánh hiệu suất giữa các phương pháp streaming
  static Map<String, String> getStreamingMethodComparison() {
    return {
      'Native media_kit Direct': 'Cao nhất - Stream trực tiếp từ SMB URL',
      'media_kit Direct SMB':
          'Cao - Stream trực tiếp nhưng có thể cần credentials',
      'HTTP Proxy': 'Trung bình - Qua HTTP proxy server',
      'LibSMB2 Direct': 'Cao - Sử dụng native libsmb2',
      'Chunked Download': 'Thấp - Tải từng chunk và tạo file tạm',
    };
  }

  /// Lấy thông tin về Native media_kit Direct streaming
  static Map<String, String> getNativeSmbPlaybackInfo() {
    return {
      'Phương pháp': 'Native media_kit Direct SMB',
      'Mô tả': 'Stream trực tiếp từ SMB URL sử dụng mobile_smb_native',
      'Ưu điểm': 'Hiệu suất cao nhất, không cần file tạm, hỗ trợ seek',
      'Nhược điểm': 'Cần native SMB client, có thể cần credentials',
      'Tương thích': 'Android, iOS (với native library)',
      'Protocol': 'SMB2/SMB3 trực tiếp',
      'Buffering': 'Native media_kit buffering',
      'Seek support': 'Có',
      'Hardware acceleration': 'Có',
    };
  }
}
