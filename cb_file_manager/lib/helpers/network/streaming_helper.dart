import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:io';
import 'dart:async';

import '../../services/network_browsing/network_service_base.dart';
import '../../services/network_browsing/mobile_smb_service.dart';
import '../../services/network_browsing/i_smb_service.dart';
import '../../ui/components/video/video_player/streaming_image_viewer.dart';
import '../../ui/components/video/video_player/video_player.dart';
import 'package:path/path.dart' as p;
import '../files/file_type_registry.dart';
import '../../ui/utils/file_type_utils.dart';
import 'network_file_cache_service.dart';
import 'vlc_direct_smb_helper.dart';
// import '../helpers/libsmb2_streaming_helper.dart';
import 'native_vlc_direct_helper.dart';
import '../../config/languages/app_localizations.dart';
import '../../ui/utils/route.dart';
import '../../services/network_browsing/webdav_service.dart';
import 'package:open_filex/open_filex.dart';

/// Class để lưu trữ kết quả mở file
class FileOpenResult {
  final bool success;
  final String? errorMessage;
  final String? message;
  final Stream<List<int>>? fileStream;
  final String? streamingUrl;

  final String? localPath;
  final FileCategory? fileType;
  final bool requiresUserChoice;
  final bool viewerLaunched;

  FileOpenResult({
    required this.success,
    this.errorMessage,
    this.message,
    this.fileStream,
    this.streamingUrl,
    this.localPath,
    this.fileType,
    this.requiresUserChoice = false,
    this.viewerLaunched = false,
  });
}

/// Helper class để xử lý streaming files từ network services
class StreamingHelper {
  static StreamingHelper? _instance;
  static StreamingHelper get instance {
    _instance ??= StreamingHelper._();
    return _instance!;
  }

  StreamingHelper._();

  NetworkServiceBase? _currentNetworkService;

  /// Khởi tạo streaming cho network service
  Future<bool> initializeStreaming(NetworkServiceBase networkService) async {
    try {
      _currentNetworkService = networkService;
      debugPrint('Streaming initialized for ${networkService.serviceName}');
      return true;
    } catch (e) {
      debugPrint('Error initializing streaming: $e');
      return false;
    }
  }

  /// Dừng streaming
  Future<void> stopStreaming() async {
    _currentNetworkService = null;
    debugPrint('Streaming stopped');
  }

  /// Mở file với streaming
  Future<void> openFileWithStreaming(
    BuildContext context,
    String filePath,
    String fileName,
  ) async {
    // Capture mounted state early to avoid issues with stale context
    if (!context.mounted) return;

    // For WebDAV, convert local temp path to remote path
    String remotePath = filePath;
    if (_currentNetworkService?.serviceName == 'WebDAV') {
      final webdavService = _currentNetworkService as dynamic;
      if (webdavService.getRemotePathFromLocal != null) {
        final actualRemotePath = webdavService.getRemotePathFromLocal(filePath);
        if (actualRemotePath != null) {
          remotePath = actualRemotePath;
          debugPrint(
              'StreamingHelper: Converted local path $filePath to remote path $remotePath');
        } else {
          debugPrint(
              'StreamingHelper: No remote path mapping found for $filePath');
        }
      } else {
        debugPrint(
            'StreamingHelper: getRemotePathFromLocal method not available');
      }
    }
    try {
      // Hiển thị loading dialog
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
      }

      final result = await _openFileDirectly(context, remotePath, fileName);

      // Đóng loading dialog
      if (context.mounted) {
        RouteUtils.safePopDialog(context);
      }

      if (result.success && context.mounted) {
        await _handleSuccessfulOpen(context, result, fileName, remotePath);
      } else if (!result.success && context.mounted) {
        await _handleOpenError(context, result.errorMessage ?? 'Unknown error');
      }
    } catch (e) {
      // Đóng loading dialog nếu còn mở
      if (context.mounted) {
        RouteUtils.safePopDialog(context);
      }
      if (context.mounted) {
        await _handleOpenError(context, 'Error opening file: $e');
      }
    }
  }

  /// Optimized streaming with caching support - Phase 1 improvements
  Future<FileOpenResult> _openFileDirectly(
    BuildContext context,
    String remotePath,
    String fileName,
  ) async {
    final startTime = DateTime.now();
    debugPrint('=== StreamingHelper._openFileDirectly START (Optimized) ===');
    debugPrint('StreamingHelper: remotePath: $remotePath');
    debugPrint('StreamingHelper: timestamp: ${startTime.toIso8601String()}');

    if (_currentNetworkService == null) {
      debugPrint('StreamingHelper: ERROR - Network service not initialized');
      return FileOpenResult(
        success: false,
        errorMessage: 'Network service not initialized',
      );
    }

    final service = _currentNetworkService!;
    debugPrint('StreamingHelper: Service type: ${service.runtimeType}');
    debugPrint('StreamingHelper: Service connected: ${service.isConnected}');

    try {
      final fileExtension = p.extension(remotePath).toLowerCase();
      final fileType = _getFileType(fileExtension);
      debugPrint('StreamingHelper: File extension: $fileExtension');
      debugPrint('StreamingHelper: File type: $fileType');

      // Check immediately if this is an unsupported file type and return early
      // to avoid lag on mobile
      if (fileType == FileCategory.unknown ||
          (!canStreamFile(remotePath) && !isDocumentFile(remotePath))) {
        debugPrint(
            'StreamingHelper: Unsupported file type detected, downloading and opening with system app');
        await _downloadAndOpen(context, remotePath);
        return FileOpenResult(
            success: true, viewerLaunched: true, fileType: fileType);
      }

      // Handle FTP by downloading to a temp file and opening with system default app
      if (service.serviceName == 'FTP') {
        try {
          final tempDir = Directory.systemTemp;
          final fileName = p.basename(remotePath);
          final tempPath = p.join(tempDir.path,
              'ftp_${DateTime.now().millisecondsSinceEpoch}_$fileName');
          debugPrint('StreamingHelper: FTP - downloading to temp: $tempPath');

          await service.getFileWithProgress(
            remotePath,
            tempPath,
            (progress) {
              if (progress >= 0) {
                debugPrint(
                    'StreamingHelper: FTP download ${(progress * 100).toStringAsFixed(1)}%');
              } else {
                debugPrint('StreamingHelper: FTP downloading (indeterminate)');
              }
            },
          );

          // Open with system default app
          await OpenFilex.open(tempPath);

          return FileOpenResult(success: true, viewerLaunched: true);
        } catch (e) {
          debugPrint('StreamingHelper: FTP fallback open failed: $e');
          // Continue to other flows if needed
        }
      }

      // Priority 1: Attempt Native VLC Direct streaming (highest priority)
      debugPrint(
          'StreamingHelper: Checking for Native VLC Direct streaming...');
      debugPrint(
          'StreamingHelper: NativeVlcDirectHelper.canStreamDirectly($fileType): ${NativeVlcDirectHelper.canStreamDirectly(fileType)}');
      if (service is ISmbService &&
          NativeVlcDirectHelper.canStreamDirectly(fileType)) {
        try {
          final canUseNative =
              await NativeVlcDirectHelper.canUseNativeVlcDirect(
            fileType: fileType,
            smbService: service,
          );

          if (canUseNative) {
            debugPrint(
                'StreamingHelper: ✅ Attempting Native VLC Direct streaming');
            if (context.mounted) {
              await NativeVlcDirectHelper.openMediaWithNativeVlcDirect(
                context: context,
                smbPath: remotePath,
                fileName: fileName,
                fileType: fileType,
                smbService: service,
              );
            }
            return FileOpenResult(success: true, viewerLaunched: true);
          } else {
            debugPrint(
                'StreamingHelper: ❌ Native VLC Direct not available, trying LibSMB2');
          }
        } catch (e) {
          debugPrint(
              'StreamingHelper: ❌ Native VLC Direct streaming failed: $e. Trying LibSMB2 fallback.');
        }
      }

      // LibSMB2 streaming removed - now using flutter_vlc_player for SMB direct streaming

      // Priority 3: Fallback to VLC Direct SMB streaming for other SMB services
      debugPrint('StreamingHelper: Checking for VLC Direct SMB fallback...');
      debugPrint(
          'StreamingHelper: VlcDirectSmbHelper.canStreamDirectly($fileType): ${VlcDirectSmbHelper.canStreamDirectly(fileType)}');
      if (service is ISmbService &&
          VlcDirectSmbHelper.canStreamDirectly(fileType)) {
        try {
          debugPrint(
              'StreamingHelper: ✅ Attempting VLC Direct SMB streaming (fallback)');
          if (context.mounted) {
            await VlcDirectSmbHelper.openMediaWithVlcDirectSmb(
              context: context,
              smbPath: remotePath,
              fileName: fileName,
              fileType: fileType,
              smbService: service,
            );
          }
          // If VLC player is launched, we return a success result indicating this
          return FileOpenResult(success: true, viewerLaunched: true);
        } catch (e) {
          debugPrint(
              'StreamingHelper: ❌ VLC Direct SMB failed: $e. Proceeding to other fallbacks.');
          // If it fails, we just log it and continue with other methods
        }
      }

      // For Android SMB media, avoid stream fallback to keep seek/duration correct.
      if (Platform.isAndroid &&
          service is ISmbService &&
          (fileType == FileCategory.video || fileType == FileCategory.audio)) {
        return FileOpenResult(
          success: false,
          errorMessage: 'VLC SMB playback failed on Android.',
          fileType: fileType,
        );
      }

      // Check if file is already cached
      final cacheService = NetworkFileCacheService();
      final cachedFile = await cacheService.getCachedFile(remotePath);

      if (cachedFile != null && await cachedFile.exists()) {
        debugPrint('StreamingHelper: Found cached file, using cached version');
        final cachedStream = cachedFile.openRead();
        return FileOpenResult(
          success: true,
          fileStream: cachedStream,
          fileType: fileType,
          message:
              'File loaded from cache (${(await cachedFile.length() / 1024).toStringAsFixed(1)} KB)',
        );
      }

      // Priority 4: For WebDAV, prefer readFileData over openFileStream for better reliability
      if (service.serviceName == 'WebDAV' &&
          (fileType != FileCategory.video && fileType != FileCategory.audio)) {
        debugPrint(
            'StreamingHelper: Using readFileData for WebDAV non-media file');
        debugPrint('StreamingHelper: remotePath for readFileData: $remotePath');

        try {
          final fileData = await service.readFileData(remotePath);
          if (fileData != null && fileData.isNotEmpty) {
            final fileStream = Stream.value(fileData);
            return FileOpenResult(
              success: true,
              fileStream: fileStream,
              fileType: fileType,
              message:
                  'WebDAV file loaded via readFileData (${(fileData.length / 1024).toStringAsFixed(1)} KB)',
            );
          } else {
            debugPrint(
                'StreamingHelper: WebDAV readFileData returned null or empty data');
          }
        } catch (e) {
          debugPrint('StreamingHelper: WebDAV readFileData failed: $e');
        }
      }

      // Priority 5: Try openFileStream for other cases
      debugPrint(
          'StreamingHelper: DECISION - Using openFileStream method (optimized)');
      debugPrint('StreamingHelper: Calling service.openFileStream...');
      debugPrint('StreamingHelper: remotePath for openFileStream: $remotePath');

      final streamStartTime = DateTime.now();
      final sourceStream = service.openFileStream(remotePath);

      if (sourceStream != null) {
        debugPrint('StreamingHelper: openFileStream SUCCESS');
        debugPrint(
            'StreamingHelper: Stream creation time: ${DateTime.now().difference(streamStartTime).inMilliseconds}ms');

        // For media files (video/audio), use caching to improve performance
        if (fileType == FileCategory.video || fileType == FileCategory.audio) {
          debugPrint('StreamingHelper: Applying caching for media file');

          // Create a controller for the cached stream
          final controller = StreamController<List<int>>();

          // Use NetworkFileCacheService to buffer and forward the stream
          cacheService.bufferStreamAndForward(
              remotePath, sourceStream, controller);

          return FileOpenResult(
            success: true,
            fileStream: controller.stream,
            fileType: fileType,
            message: 'Media file streaming with smart caching enabled',
          );
        } else {
          // For non-media files, stream directly without caching
          return FileOpenResult(
            success: true,
            fileStream: sourceStream,
            fileType: fileType,
            message: 'File streaming directly (no caching for non-media)',
          );
        }
      }

      // Fallback: Try readFileData only for small non-media files (excluding WebDAV which was already handled)
      if (service is MobileSMBService &&
          (fileType != FileCategory.video && fileType != FileCategory.audio)) {
        debugPrint(
            'StreamingHelper: openFileStream failed, trying readFileData fallback for non-media file');

        // Get file size for small file check
        int? fileSize;
        try {
          fileSize = await service.getFileSize(remotePath);
          debugPrint('StreamingHelper: File size: $fileSize bytes');
        } catch (e) {
          debugPrint('StreamingHelper: Could not get file size: $e');
        }

        // Only use readFileData for small files (< 10MB)
        const int smallFileThreshold = 10 * 1024 * 1024; // 10MB
        if (fileSize != null && fileSize <= smallFileThreshold) {
          debugPrint(
              'StreamingHelper: Using readFileData for small non-media file');
          try {
            final fileData = await service.readFileData(remotePath);
            if (fileData != null && fileData.isNotEmpty) {
              final fileStream = Stream.value(fileData);
              return FileOpenResult(
                success: true,
                fileStream: fileStream,
                fileType: fileType,
                message:
                    'Small file loaded via readFileData (${(fileData.length / 1024).toStringAsFixed(1)} KB)',
              );
            }
          } catch (e) {
            debugPrint('StreamingHelper: readFileData fallback failed: $e');
          }
        } else {
          debugPrint(
              'StreamingHelper: File too large for readFileData fallback (${fileSize != null ? (fileSize / 1024 / 1024).toStringAsFixed(1) : "unknown"} MB)');
        }
      }

      // If streaming failed for a non-media file, fall back to download + open.
      if (fileType != FileCategory.video && fileType != FileCategory.audio) {
        debugPrint(
            'StreamingHelper: All streaming methods failed for non-media file, downloading and opening with system app');
        // ignore: use_build_context_synchronously
        await _downloadAndOpen(context, remotePath);
        return FileOpenResult(
            success: true, viewerLaunched: true, fileType: fileType);
      }

      // All methods failed
      debugPrint('StreamingHelper: ERROR - All streaming methods failed');
      debugPrint('StreamingHelper: Service type: ${service.runtimeType}');
      debugPrint('StreamingHelper: Service connected: ${service.isConnected}');

      return FileOpenResult(
        success: false,
        errorMessage:
            'Không thể tạo stream cho file này. Vui lòng kiểm tra kết nối mạng và thử lại.',
        fileType: fileType,
      );
    } catch (e, stackTrace) {
      final duration = DateTime.now().difference(startTime);
      debugPrint('StreamingHelper: CRITICAL ERROR in _openFileDirectly');
      debugPrint('StreamingHelper: Error: $e');
      debugPrint('StreamingHelper: Duration: ${duration.inMilliseconds}ms');
      debugPrint('StreamingHelper: Stack trace: $stackTrace');

      return FileOpenResult(
        success: false,
        errorMessage: 'Lỗi không mong muốn khi mở file: $e',
      );
    } finally {
      final totalDuration = DateTime.now().difference(startTime);
      debugPrint(
          'StreamingHelper: Total execution time: ${totalDuration.inMilliseconds}ms');
      debugPrint('=== StreamingHelper._openFileDirectly END (Optimized) ===');
    }
  }

  /// Downloads a file from network service to local storage
  Future<void> downloadFile(String filePath, String destinationPath) async {
    if (_currentNetworkService == null) {
      throw Exception('No network service available');
    }

    try {
      debugPrint(
          'StreamingHelper: Starting download from $filePath to $destinationPath');
      final svc = _currentNetworkService!;
      // Resolve remote path if the service uses local-temp mapping (WebDAV)
      String remotePath = filePath;
      if (svc is WebDAVService) {
        final mapped = svc.getRemotePathFromLocal(filePath);
        if (mapped == null) {
          throw Exception('Could not determine remote path for file');
        }
        remotePath = mapped;
      }

      debugPrint('StreamingHelper: Resolved remote path: $remotePath');

      // Prefer progress-enabled download when available
      await svc.getFileWithProgress(
        remotePath,
        destinationPath,
        (progress) {
          if (progress >= 0) {
            debugPrint(
                'StreamingHelper: Download ${(progress * 100).toStringAsFixed(1)}%');
          } else {
            debugPrint('StreamingHelper: Downloading (indeterminate)');
          }
        },
      );

      debugPrint('StreamingHelper: Download completed successfully');
    } catch (e) {
      debugPrint('StreamingHelper: Download failed: $e');
      throw Exception('Failed to download file: $e');
    }
  }

  /// Xác định loại file dựa trên extension
  FileCategory _getFileType(String extension) {
    return FileTypeRegistry.getCategory(extension);
  }

  /// Xử lý khi mở file thành công
  Future<void> _handleSuccessfulOpen(
    BuildContext context,
    FileOpenResult result,
    String fileName,
    String remotePath,
  ) async {
    if (!context.mounted) return;

    // Kiểm tra nếu kết quả không thành công
    if (!result.success) {
      if (context.mounted) {
        await _handleOpenError(
          context,
          result.errorMessage ?? 'Failed to open file',
        );
      }
      return;
    }

    // If an external viewer was launched (e.g., VLC), we don't need to do anything else.
    if (result.viewerLaunched) {
      debugPrint(
          "StreamingHelper: Viewer already launched, skipping internal player.");
      return;
    }

    if (result.requiresUserChoice) {
      // Hiển thị dialog cho người dùng chọn
      if (context.mounted) {
        await _showFileOptionsDialog(context, result, fileName, remotePath);
      }
      return;
    }

    if (result.fileStream != null || result.streamingUrl != null) {
      // Mở media player hoặc image viewer với stream, URL hoặc SMB MRL
      if (context.mounted) {
        await _openStreamingViewer(context, result, fileName, remotePath);
      }
    } else if (result.localPath != null) {
      // File đã được tải về và mở
      // Intentionally no success toast for downloads/opens.
    } else {
      // Không có dữ liệu để mở file
      if (context.mounted) {
        await _handleOpenError(context, 'No data available to open this file');
      }
    }
  }

  /// Mở streaming viewer dựa trên loại file
  Future<void> _openStreamingViewer(
    BuildContext context,
    FileOpenResult result,
    String fileName,
    String remotePath,
  ) async {
    if (!context.mounted) return;

    // Kiểm tra xem có dữ liệu để stream không
    if (result.fileStream == null && result.streamingUrl == null) {
      await _handleOpenError(
        context,
        'No streaming data available for this file',
      );
      return;
    }

    if (result.fileType == FileCategory.image) {
      // Mở image viewer
      if (context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => result.fileStream != null
                ? StreamingImageViewer.fromStream(
                    fileStream: result.fileStream!,
                    fileName: fileName,
                  )
                : result.streamingUrl != null
                    ? StreamingImageViewer.fromUrl(
                        streamingUrl: result.streamingUrl!,
                        fileName: fileName,
                      )
                    : throw Exception(
                        'Neither fileStream nor streamingUrl available',
                      ),
          ),
        );
      }
    } else if (result.fileType == FileCategory.video ||
        result.fileType == FileCategory.audio) {
      // Debug thông tin trước khi kiểm tra VLC Direct SMB
      debugPrint('StreamingHelper: Processing video/audio file');
      debugPrint(
          'StreamingHelper: _currentNetworkService type: ${_currentNetworkService.runtimeType}');

      debugPrint('StreamingHelper: File type: ${result.fileType}');
      debugPrint(
          'StreamingHelper: Can stream directly: ${VlcDirectSmbHelper.canStreamDirectly(result.fileType!)}');

      // LibSMB2 streaming removed - now using flutter_vlc_player for SMB

      // Fallback: VLC Direct SMB streaming
      if (result.streamingUrl == null &&
          _currentNetworkService is ISmbService &&
          VlcDirectSmbHelper.canStreamDirectly(result.fileType!)) {
        try {
          debugPrint(
              'StreamingHelper: ✅ Attempting VLC Direct SMB streaming (fallback)');
          debugPrint('StreamingHelper: Using remotePath: $remotePath');
          await VlcDirectSmbHelper.openMediaWithVlcDirectSmb(
            context: context,
            smbPath: remotePath,
            fileName: fileName,
            fileType: result.fileType!,
            smbService: _currentNetworkService as ISmbService,
          );
          return;
        } catch (e) {
          debugPrint('StreamingHelper: ❌ VLC Direct SMB failed: $e');
          // Tiếp tục với fallback khác
        }
      } else {
        debugPrint(
            'StreamingHelper: ❌ Direct streaming conditions not met, using other fallbacks');
      }

      // Fallback: Mở media player với các phương thức khác
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
                child: result.fileStream != null
                    ? VideoPlayer.stream(
                        fileStream: result.fileStream!,
                        fileName: fileName,
                        fileType: result.fileType!,
                      )
                    : result.streamingUrl != null
                        ? VideoPlayer.url(
                            streamingUrl: result.streamingUrl!,
                            fileName: fileName,
                            fileType: result.fileType!,
                          )
                        : throw Exception(
                            'No streaming data available',
                          ),
              ),
            ),
          ),
        );
      }
    } else {
      // Handle other file types (text, documents, etc.)
      debugPrint(
          'StreamingHelper: Processing other file type: ${result.fileType}');

      // For text files and other non-media files, save to temp and open with system default app
      if (result.fileStream != null) {
        try {
          debugPrint(
              'StreamingHelper: result.fileStream is not null, attempting to read');

          // Create temporary file
          final tempDir = Directory.systemTemp;
          final tempFile = File(
              '${tempDir.path}/webdav_${DateTime.now().millisecondsSinceEpoch}_$fileName');

          debugPrint('StreamingHelper: Creating temp file: ${tempFile.path}');

          // Write stream to temp file
          final sink = tempFile.openWrite();
          int totalBytes = 0;
          await for (final chunk in result.fileStream!) {
            sink.add(chunk);
            totalBytes += chunk.length;
            debugPrint(
                'StreamingHelper: Read chunk: ${chunk.length} bytes, total: $totalBytes');
          }
          await sink.close();

          debugPrint(
              'StreamingHelper: Temp file created successfully: ${await tempFile.length()} bytes');

          // Open with the system handler (works on Android/iOS/desktop via open_filex).
          final openResult = await OpenFilex.open(tempFile.path);
          final opened = openResult.type.toString().contains('done');

          if (opened) {
            // Clean up temp file after a delay
            Future.delayed(const Duration(seconds: 10), () async {
              try {
                await tempFile.delete();
                debugPrint('StreamingHelper: Temp file cleaned up');
              } catch (e) {
                debugPrint('StreamingHelper: Failed to clean up temp file: $e');
              }
            });
          } else {
            if (context.mounted) {
              await _handleOpenError(
                context,
                'Failed to open file with a system app.${openResult.message.isEmpty ? '' : ' ${openResult.message}'}',
              );
            }
          }
        } catch (e) {
          debugPrint('StreamingHelper: Error handling other file type: $e');
          if (context.mounted) {
            await _handleOpenError(context, 'Error opening file: $e');
          }
        }
      } else {
        if (context.mounted) {
          await _handleOpenError(context, 'No file data available to open');
        }
      }
    }
  }

  /// Hiển thị dialog tùy chọn cho file không được hỗ trợ trực tiếp
  Future<void> _showFileOptionsDialog(
    BuildContext context,
    FileOpenResult result,
    String fileName,
    String remotePath,
  ) async {
    if (!context.mounted) return;

    // Extract file extension for better messaging
    final fileExtension = p.extension(fileName).toLowerCase();
    final fileTypeString = fileExtension.isNotEmpty
        ? fileExtension.substring(1).toUpperCase()
        : "This";

    if (context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.openFileTypeFile(fileTypeString)),
          content: Text(l10n.streamDownloadPrompt(fileTypeString)),
          actions: [
            TextButton(
              onPressed: () => RouteUtils.safePopDialog(ctx),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () async {
                RouteUtils.safePopDialog(ctx);
                await _downloadAndOpen(context, remotePath);
              },
              child: Text(l10n.download),
            ),
          ],
        ),
      );
    }
  }

  /// Tải file về
  Future<void> _downloadAndOpen(BuildContext context, String remotePath) async {
    if (_currentNetworkService == null) {
      if (context.mounted) {
        await _handleOpenError(
            context, AppLocalizations.of(context)!.networkServiceNotAvailable);
      }
      return;
    }

    try {
      // Hiển thị loading
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text(AppLocalizations.of(context)!.downloadingFile),
              ],
            ),
          ),
        );
      }

      // Tạo file tạm thời
      final fileName = p.basename(remotePath);
      final tempDir = Directory.systemTemp;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final localPath = p.join(tempDir.path, 'smb_files', '${stamp}_$fileName');

      // Tạo thư mục nếu chưa tồn tại
      final localDir = Directory(p.dirname(localPath));
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }

      // Tải file từ network service
      await _currentNetworkService!.getFile(remotePath, localPath);

      if (context.mounted) {
        RouteUtils.safePopDialog(context); // Đóng loading
      }

      bool opened = false;
      String? openErrorMessage;
      try {
        final openResult = await OpenFilex.open(localPath);
        opened = openResult.type.toString().contains('done');
        if (!opened) {
          debugPrint(
              'StreamingHelper: OpenFilex failed: ${openResult.type} - ${openResult.message}');
          openErrorMessage = openResult.message;
        }
      } catch (e) {
        debugPrint('StreamingHelper: OpenFilex exception: $e');
        openErrorMessage = e.toString();
      }

      if (context.mounted) {
        if (!opened) {
          final suffix = (openErrorMessage?.isNotEmpty ?? false)
              ? ' $openErrorMessage'
              : '';
          await _handleOpenError(
            context,
            'File downloaded, but it could not be opened automatically.$suffix',
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        RouteUtils.safePopDialog(context); // Đóng loading
      }
      if (context.mounted) {
        await _handleOpenError(context,
            '${AppLocalizations.of(context)!.errorDownloadingFile}: $e');
      }
    }
  }

  /// Xử lý lỗi khi mở file
  Future<void> _handleOpenError(
    BuildContext context,
    String errorMessage,
  ) async {
    if (!context.mounted) return;

    if (context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.errorTitle),
          content: Text(errorMessage),
          actions: [
            TextButton(
              onPressed: () => RouteUtils.safePopDialog(ctx),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    }
  }

  /// Kiểm tra xem file có thể streaming không
  bool canStreamFile(String filePath) {
    return FileTypeUtils.isImageFile(filePath) ||
        FileTypeUtils.isVideoFile(filePath) ||
        FileTypeUtils.isAudioFile(filePath);
  }

  /// Lấy icon phù hợp cho loại file
  IconData getFileIcon(String filePath) {
    if (FileTypeUtils.isVideoFile(filePath)) {
      return PhosphorIconsLight.videoCamera;
    } else if (FileTypeUtils.isAudioFile(filePath)) {
      return PhosphorIconsLight.musicNote;
    } else if (FileTypeUtils.isImageFile(filePath)) {
      return PhosphorIconsLight.image;
    } else if (FileTypeUtils.isDocumentFile(filePath) ||
        FileTypeUtils.isSpreadsheetFile(filePath) ||
        FileTypeUtils.isPresentationFile(filePath)) {
      return PhosphorIconsLight.fileText;
    } else {
      return PhosphorIconsLight.file;
    }
  }

  /// Kiểm tra trạng thái streaming
  bool get isStreamingActive => _currentNetworkService != null;

  /// Lấy network service hiện tại
  NetworkServiceBase? get currentNetworkService => _currentNetworkService;

  /// Kiểm tra xem có thể streaming file không
  bool canStreamFileWithService(String filePath) {
    return _currentNetworkService != null && canStreamFile(filePath);
  }

  /// Kiểm tra xem file có phải là document không
  bool isDocumentFile(String filePath) {
    return FileTypeUtils.isDocumentFile(filePath) ||
        FileTypeUtils.isSpreadsheetFile(filePath) ||
        FileTypeUtils.isPresentationFile(filePath) ||
        filePath.toLowerCase().endsWith('.pdf');
  }
}
