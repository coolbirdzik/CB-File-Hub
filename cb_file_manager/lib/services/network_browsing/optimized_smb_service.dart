import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mobile_smb_native/mobile_smb_native.dart';
import 'network_service_base.dart';
import 'package:cb_file_manager/services/network_credentials_service.dart';
import 'smb_chunk_reader.dart';
import 'prefetch_controller.dart';

/// Optimized SMB service with advanced streaming capabilities
import 'i_smb_service.dart';

class OptimizedSMBService implements ISmbService {
  static const String _smbScheme = 'smb';

  final MobileSmbClient _smbClient = MobileSmbClient();
  SmbChunkReader? _chunkReader;
  PrefetchController? _prefetchController;

  // Connection state
  String _connectedHost = '';
  String _connectedShare = '';
  bool _isConnected = false;

  // Performance configuration
  final SmbChunkReaderConfig _chunkReaderConfig = const SmbChunkReaderConfig(
    maxConnections: 4,
    chunkSize: 256 * 1024, // 256KB chunks
    readAheadSize: 1024 * 1024, // 1MB readahead
    maxReadSize: 1024 * 1024, // 1MB max read size
    socketTimeoutMs: 5000, // 5 seconds
    retryAttempts: 3,
    enablePipelining: true,
    enableLargeMtu: true,
  );

  final PrefetchControllerConfig _prefetchConfig =
      const PrefetchControllerConfig(
        bufferSize: 5 * 1024 * 1024, // 5MB buffer
        prefetchSize: 2 * 1024 * 1024, // 2MB prefetch
        maxPrefetchChunks: 8,
        prefetchTimeout: Duration(seconds: 10),
        enableCircularBuffer: true,
      );

  @override
  String get serviceName => 'Optimized SMB';

  @override
  String get serviceDescription =>
      'High-performance SMB streaming with optimization';

  @override
  dynamic get serviceIcon => null; // Use default icon

  @override
  bool isAvailable() => Platform.isAndroid || Platform.isIOS;

  @override
  bool get isConnected => _isConnected;

  @override
  String get basePath => '$_smbScheme://$_connectedHost/$_connectedShare';

  @override
  Future<String?> getSmbDirectLink(String tabPath) async {
    if (!isConnected) return null;

    try {
      // 1. Get credentials
      final credentials = NetworkCredentialsService().findCredentials(
        serviceType: 'SMB',
        host: _connectedHost,
      );
      if (credentials == null) {
        debugPrint(
          'OptimizedSMBService: No credentials found for $_connectedHost',
        );
        return null;
      }

      final username = credentials.username;
      final password = credentials.password;

      // 2. Get the relative SMB path from the tab path
      final smbPath = _getSmbPathFromTabPath(tabPath);
      if (smbPath.isEmpty || smbPath == '/') {
        debugPrint(
          'OptimizedSMBService: Could not determine a valid file path from $tabPath',
        );
        return null;
      }

      // The smbPath from _getSmbPathFromTabPath is like "/share/folder/file.txt"
      // We need to remove the leading slash for the URL
      final pathComponent = smbPath.startsWith('/')
          ? smbPath.substring(1)
          : smbPath;

      // 3. Construct the direct link, ensure each path segment is URL-encoded
      final encodedUser = Uri.encodeComponent(username);
      final encodedPass = Uri.encodeComponent(password);
      final encodedPath = pathComponent
          .split('/')
          .map(Uri.encodeComponent)
          .join('/');
      final link =
          'smb://$encodedUser:$encodedPass@$_connectedHost/$encodedPath';

      debugPrint('OptimizedSMBService: Generated SMB direct link: $link');
      return link;
    } catch (e) {
      debugPrint('OptimizedSMBService: Error generating SMB direct link: $e');
      return null;
    }
  }

  /// Public method to convert tabPath to SMB path for external use
  String getSmbPathFromTabPath(String tabPath) {
    return _getSmbPathFromTabPath(tabPath);
  }

  /// Converts an application-specific tabPath to SMB path format
  String _getSmbPathFromTabPath(String tabPath) {
    final lowerPath = tabPath.toLowerCase();
    if (!lowerPath.startsWith('#network/$_smbScheme/')) {
      debugPrint('Invalid tab path format: $tabPath');
      return '/';
    }

    final pathWithoutPrefix = tabPath.substring('#network/'.length);
    final parts = pathWithoutPrefix
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.length < 2) {
      debugPrint('Tab path has too few parts: $tabPath');
      return '/';
    }

    if (parts.length == 2) {
      return '/';
    }

    if (parts.length == 3) {
      final shareName = Uri.decodeComponent(parts[2]);
      return '/$shareName';
    }

    if (parts.length > 3) {
      final shareName = Uri.decodeComponent(parts[2]);
      final folders = parts
          .sublist(3)
          .map((f) => Uri.decodeComponent(f))
          .toList();
      return '/$shareName/${folders.join('/')}';
    }

    return '/';
  }

  @override
  Future<ConnectionResult> connect({
    required String host,
    required String username,
    String? password,
    int? port,
    Map<String, dynamic>? additionalOptions,
  }) async {
    if (!isAvailable()) {
      return ConnectionResult(
        success: false,
        errorMessage: 'Optimized SMB is only available on Android and iOS.',
      );
    }

    await disconnect();

    final hostParts = host.trim().split('/');
    final serverHost = hostParts.first.replaceAll('\\', '');
    final shareName = hostParts.length > 1 ? hostParts[1] : null;

    if (serverHost.isEmpty) {
      return ConnectionResult(
        success: false,
        errorMessage: 'Server address cannot be empty.',
      );
    }

    try {
      final config = SmbConnectionConfig(
        host: serverHost,
        port: port ?? 445,
        username: username,
        password: password ?? '',
        shareName: shareName,
        timeoutMs: 120000, // 120 seconds timeout
      );

      final success = await _smbClient.connect(config);

      if (success) {
        _isConnected = true;
        _connectedHost = serverHost;
        _connectedShare = shareName ?? '';

        // Initialize chunk reader and prefetch controller
        await _initializeOptimizations(config);

        // Save credentials if connection is successful
        try {
          final domain = additionalOptions?['domain'] as String?;
          await NetworkCredentialsService().saveCredentials(
            serviceType: 'SMB',
            host: serverHost,
            username: username,
            password: password ?? '',
            port: port,
            domain: domain,
          );
          debugPrint('OptimizedSMBService: Credentials saved successfully');
        } catch (e) {
          debugPrint('OptimizedSMBService: Failed to save credentials: $e');
        }

        final connectedPath = shareName != null
            ? '$_smbScheme://$serverHost/$shareName'
            : '$_smbScheme://$serverHost';

        return ConnectionResult(success: true, connectedPath: connectedPath);
      } else {
        return ConnectionResult(
          success: false,
          errorMessage: 'Failed to connect to SMB server',
        );
      }
    } catch (e) {
      return ConnectionResult(
        success: false,
        errorMessage: 'SMB Connection error: $e',
      );
    }
  }

  /// Initialize optimization components
  Future<void> _initializeOptimizations(SmbConnectionConfig config) async {
    try {
      // Initialize chunk reader
      _chunkReader = SmbChunkReader(config: _chunkReaderConfig);
      final readerInitialized = await _chunkReader!.initialize(config);

      if (readerInitialized) {
        // Initialize prefetch controller
        _prefetchController = PrefetchController(
          reader: _chunkReader!,
          config: _prefetchConfig,
        );
        await _prefetchController!.initialize();

        debugPrint(
          'OptimizedSMBService: Optimizations initialized successfully',
        );
      } else {
        debugPrint('OptimizedSMBService: Failed to initialize chunk reader');
      }
    } catch (e) {
      debugPrint('OptimizedSMBService: Error initializing optimizations: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _prefetchController?.dispose();
      await _chunkReader?.dispose();
      await _smbClient.disconnect();
    } catch (e) {
      debugPrint('Error disconnecting from SMB: $e');
    } finally {
      _isConnected = false;
      _connectedHost = '';
      _connectedShare = '';
      _chunkReader = null;
      _prefetchController = null;
    }
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String tabPath) async {
    debugPrint(
      'OptimizedSMBService: listDirectory called with tabPath: $tabPath',
    );

    if (!isConnected) {
      debugPrint('OptimizedSMBService: Not connected to SMB server');
      throw Exception('Not connected to SMB server');
    }

    try {
      final pathWithoutPrefix = tabPath.substring('#network/'.length);
      final parts = pathWithoutPrefix
          .split('/')
          .where((p) => p.isNotEmpty)
          .toList();

      debugPrint(
        'OptimizedSMBService: Path parts: $parts, length: ${parts.length}',
      );

      if (parts.length <= 2) {
        return await _listShares(tabPath);
      }

      final smbPath = _getSmbPathFromTabPath(tabPath);
      debugPrint('OptimizedSMBService: Converted tabPath to smbPath: $smbPath');

      final smbFiles = await _smbClient.listDirectory(smbPath);
      debugPrint(
        'OptimizedSMBService: Got ${smbFiles.length} files from native client',
      );

      final entities = <FileSystemEntity>[];

      for (final smbFile in smbFiles) {
        final encodedName = Uri.encodeComponent(smbFile.name);
        final itemTabPath = tabPath.endsWith('/')
            ? '$tabPath$encodedName${smbFile.isDirectory ? '/' : ''}'
            : '$tabPath/$encodedName${smbFile.isDirectory ? '/' : ''}';

        if (smbFile.isDirectory) {
          entities.add(Directory(itemTabPath));
        } else {
          entities.add(File(itemTabPath));
        }
      }

      debugPrint('OptimizedSMBService: Returning ${entities.length} entities');
      return entities;
    } catch (e) {
      debugPrint('OptimizedSMBService: Error listing directory $tabPath: $e');
      return [];
    }
  }

  Future<List<FileSystemEntity>> _listShares(String tabPath) async {
    debugPrint(
      'OptimizedSMBService: _listShares called with tabPath: $tabPath',
    );

    try {
      final shares = await _smbClient.listShares();
      debugPrint(
        'OptimizedSMBService: Got ${shares.length} shares from native client: $shares',
      );

      final entities = <FileSystemEntity>[];

      final pathWithoutPrefix = tabPath.substring('#network/'.length);
      final parts = pathWithoutPrefix
          .split('/')
          .where((p) => p.isNotEmpty)
          .toList();
      final server = parts.length > 1
          ? Uri.decodeComponent(parts[1])
          : _connectedHost;

      debugPrint('OptimizedSMBService: Server extracted: $server');

      for (final shareName in shares) {
        final shareTabPath =
            '#network/${_smbScheme.toUpperCase()}/${Uri.encodeComponent(server)}/${Uri.encodeComponent(shareName)}/';
        debugPrint(
          'OptimizedSMBService: Adding share: $shareName -> $shareTabPath',
        );
        entities.add(Directory(shareTabPath));
      }

      debugPrint(
        'OptimizedSMBService: Returning ${entities.length} share entities',
      );
      return entities;
    } catch (e) {
      debugPrint('OptimizedSMBService: Error listing shares: $e');
      return [];
    }
  }

  @override
  Future<File> getFile(String remotePath, String localPath) async {
    if (!isConnected) {
      throw Exception('Not connected to SMB server');
    }

    try {
      final smbPath = _getSmbPathFromTabPath(remotePath);
      final fileData = await _smbClient.readFile(smbPath);

      final localFile = File(localPath);
      await localFile.writeAsBytes(fileData);

      return localFile;
    } catch (e) {
      throw Exception('Failed to get file: $e');
    }
  }

  @override
  Future<File> getFileWithProgress(
    String remotePath,
    String localPath,
    void Function(double progress)? onProgress,
  ) async {
    onProgress?.call(0.0);
    final result = await getFile(remotePath, localPath);
    onProgress?.call(1.0);
    return result;
  }

  @override
  Future<bool> putFile(String localPath, String remotePath) async {
    if (!isConnected) {
      throw Exception('Not connected to SMB server');
    }

    try {
      final localFile = File(localPath);
      if (!await localFile.exists()) {
        throw Exception('Local file does not exist: $localPath');
      }

      final fileData = await localFile.readAsBytes();
      final smbPath = _getSmbPathFromTabPath(remotePath);

      return await _smbClient.writeFile(smbPath, fileData);
    } catch (e) {
      debugPrint('Failed to put file: $e');
      return false;
    }
  }

  @override
  Future<bool> putFileWithProgress(
    String localPath,
    String remotePath,
    void Function(double progress)? onProgress,
  ) async {
    onProgress?.call(0.0);
    final result = await putFile(localPath, remotePath);
    onProgress?.call(1.0);
    return result;
  }

  @override
  Future<bool> deleteFile(String path) async {
    if (!isConnected) {
      throw Exception('Not connected to SMB server');
    }

    try {
      final smbPath = _getSmbPathFromTabPath(path);
      return await _smbClient.delete(smbPath);
    } catch (e) {
      debugPrint('Failed to delete file: $e');
      return false;
    }
  }

  @override
  Future<bool> createDirectory(String path) async {
    if (!isConnected) {
      throw Exception('Not connected to SMB server');
    }

    try {
      final smbPath = _getSmbPathFromTabPath(path);
      return await _smbClient.createDirectory(smbPath);
    } catch (e) {
      debugPrint('Failed to create directory: $e');
      return false;
    }
  }

  @override
  Future<bool> deleteDirectory(String path) async {
    if (!isConnected) {
      throw Exception('Not connected to SMB server');
    }

    try {
      final smbPath = _getSmbPathFromTabPath(path);
      return await _smbClient.delete(smbPath);
    } catch (e) {
      debugPrint('Failed to delete directory: $e');
      return false;
    }
  }

  @override
  Future<bool> rename(String oldPath, String newPath) async {
    debugPrint('Rename operation not yet supported in optimized SMB');
    return false;
  }

  /// Optimized file streaming with prefetch and caching
  @override
  Stream<List<int>>? openFileStream(String remotePath, {int startOffset = 0}) {
    try {
      debugPrint(
        'OptimizedSMBService openFileStream: Starting for path: $remotePath',
      );

      if (!isConnected) {
        debugPrint(
          'OptimizedSMBService openFileStream: Not connected to SMB server',
        );
        return null;
      }

      final smbPath = _getSmbPathFromTabPath(remotePath);
      debugPrint(
        'OptimizedSMBService openFileStream: Converted SMB path: $smbPath',
      );

      // Create optimized stream with prefetch
      return _createOptimizedStream(smbPath, startOffset);
    } catch (e) {
      debugPrint('OptimizedSMBService openFileStream error: $e');
      return null;
    }
  }

  /// Create optimized stream with prefetch support
  Stream<List<int>> _createOptimizedStream(String smbPath, int startOffset) {
    // Use native SMB client directly for reliable streaming
    final stream = _smbClient.seekFileStreamOptimized(
      smbPath,
      startOffset,
      chunkSize: 128 * 1024,
    );

    if (stream != null) {
      debugPrint(
        'OptimizedSMBService: Using native SMB stream with 128KB chunks',
      );
      return _createContinuousStream(stream);
    }

    // Fallback to periodic stream if native stream fails
    debugPrint('OptimizedSMBService: Native stream failed, using fallback');
    return Stream.periodic(
      const Duration(milliseconds: 16), // ~60 FPS
      (tick) async {
        if (_prefetchController != null) {
          // Read 64KB chunks for smooth streaming
          final data = await _prefetchController!.read(64 * 1024);
          if (data != null && data.isNotEmpty) {
            return data.toList();
          }
        }

        // Fallback to direct streaming if prefetch is not available
        return <int>[];
      },
    ).asyncMap((future) => future).where((data) => data.isNotEmpty);
  }

  /// Create a continuous stream that ensures all chunks are properly buffered
  Stream<List<int>> _createContinuousStream(Stream<List<int>> sourceStream) {
    final controller = StreamController<List<int>>();
    int totalBytes = 0;
    int chunkCount = 0;
    bool isClosed = false;

    void closeStream([Object? error]) {
      if (!isClosed) {
        isClosed = true;
        if (error != null) {
          controller.addError(error);
        }
        controller.close();
      }
    }

    sourceStream.listen(
      (chunk) {
        if (!isClosed && chunk.isNotEmpty) {
          totalBytes += chunk.length;
          chunkCount++;

          // Log progress for debugging
          if (chunkCount % 10 == 0) {
            debugPrint(
              'OptimizedSMBService: Streamed $chunkCount chunks, ${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB',
            );
          }

          controller.add(chunk);
        }
      },
      onError: (error) {
        debugPrint('OptimizedSMBService: Stream error: $error');
        closeStream(error);
      },
      onDone: () {
        debugPrint(
          'OptimizedSMBService: Stream completed - $chunkCount chunks, ${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB total',
        );
        closeStream();
      },
      cancelOnError: false,
    );

    return controller.stream;
  }

  /// Open file stream with seek support for video streaming
  Stream<List<int>>? openFileStreamWithSeek(String remotePath, int offset) {
    try {
      debugPrint(
        'OptimizedSMBService openFileStreamWithSeek: Starting for path: $remotePath at offset: $offset',
      );

      if (!isConnected) {
        debugPrint(
          'OptimizedSMBService openFileStreamWithSeek: Not connected to SMB server',
        );
        return null;
      }

      final smbPath = _getSmbPathFromTabPath(remotePath);
      debugPrint(
        'OptimizedSMBService openFileStreamWithSeek: Converted SMB path: $smbPath',
      );

      // Create optimized stream with seek support
      return _createOptimizedStream(smbPath, offset);
    } catch (e) {
      debugPrint('OptimizedSMBService openFileStreamWithSeek error: $e');
      return null;
    }
  }

  @override
  Future<int?> getFileSize(String remotePath) async {
    if (!isConnected) {
      return null;
    }

    try {
      final smbPath = _getSmbPathFromTabPath(remotePath);
      final fileInfo = await _smbClient.getFileInfo(smbPath);
      return fileInfo?.size;
    } catch (e) {
      debugPrint('Failed to get file size: $e');
      return null;
    }
  }

  @override
  Future<Uint8List?> readFileData(String remotePath) async {
    final startTime = DateTime.now();
    debugPrint('=== OptimizedSMBService.readFileData START ===');
    debugPrint('OptimizedSMBService: remotePath: $remotePath');
    debugPrint(
      'OptimizedSMBService: timestamp: ${startTime.toIso8601String()}',
    );
    debugPrint('OptimizedSMBService: connection status: $isConnected');

    if (!isConnected) {
      debugPrint('OptimizedSMBService: ERROR - Not connected to SMB server');
      return null;
    }

    try {
      final smbPath = _getSmbPathFromTabPath(remotePath);
      debugPrint('OptimizedSMBService: Converted SMB path: $smbPath');

      // Use optimized chunk reader if available
      if (_chunkReader != null && _chunkReader!.isInitialized) {
        await _chunkReader!.setFile(smbPath);

        final fileSize = _chunkReader!.fileSize;
        if (fileSize != null && fileSize > 0) {
          // Read file in chunks for better performance
          final chunks = <Uint8List>[];
          int totalSize = 0;
          int offset = 0;
          const chunkSize = 1024 * 1024; // 1MB chunks

          while (offset < fileSize) {
            final remainingSize = fileSize - offset;
            final currentChunkSize = remainingSize < chunkSize
                ? remainingSize
                : chunkSize;

            final chunk = await _chunkReader!.readChunk(
              offset,
              currentChunkSize,
            );
            if (chunk != null) {
              chunks.add(chunk.data);
              totalSize += chunk.size;
              offset += chunk.size;
            } else {
              break;
            }
          }

          if (chunks.isNotEmpty) {
            final combinedData = Uint8List(totalSize);
            int currentOffset = 0;

            for (final chunk in chunks) {
              combinedData.setRange(
                currentOffset,
                currentOffset + chunk.length,
                chunk,
              );
              currentOffset += chunk.length;
            }

            final duration = DateTime.now().difference(startTime);
            debugPrint(
              'OptimizedSMBService: SUCCESS - File data read with optimization',
            );
            debugPrint(
              'OptimizedSMBService: Data length: ${combinedData.length} bytes',
            );
            debugPrint(
              'OptimizedSMBService: Transfer speed: ${(combinedData.length / 1024 / 1024 / (duration.inMilliseconds / 1000)).toStringAsFixed(2)} MB/s',
            );

            return combinedData;
          }
        }
      }

      // Fallback to direct reading
      debugPrint('OptimizedSMBService: Using fallback direct reading');
      final fileData = await _smbClient.readFile(smbPath);

      if (fileData.isNotEmpty) {
        final duration = DateTime.now().difference(startTime);
        debugPrint('OptimizedSMBService: SUCCESS - File data read (fallback)');
        debugPrint(
          'OptimizedSMBService: Data length: ${fileData.length} bytes',
        );
        debugPrint(
          'OptimizedSMBService: Transfer speed: ${(fileData.length / 1024 / 1024 / (duration.inMilliseconds / 1000)).toStringAsFixed(2)} MB/s',
        );

        return Uint8List.fromList(fileData);
      } else {
        debugPrint('OptimizedSMBService: ERROR - Received empty file data');
        return null;
      }
    } catch (e, stackTrace) {
      final duration = DateTime.now().difference(startTime);
      debugPrint('OptimizedSMBService: EXCEPTION in readFileData');
      debugPrint('OptimizedSMBService: Error: $e');
      debugPrint('OptimizedSMBService: Duration: ${duration.inMilliseconds}ms');
      debugPrint('OptimizedSMBService: Stack trace: $stackTrace');
      return null;
    } finally {
      final totalDuration = DateTime.now().difference(startTime);
      debugPrint(
        'OptimizedSMBService: Total readFileData time: ${totalDuration.inMilliseconds}ms',
      );
      debugPrint('=== OptimizedSMBService.readFileData END ===');
    }
  }

  /// Get performance statistics
  Map<String, dynamic> getPerformanceStats() {
    final stats = <String, dynamic>{
      'isConnected': isConnected,
      'chunkReaderInitialized': _chunkReader?.isInitialized ?? false,
      'prefetchControllerActive': _prefetchController != null,
      'streamingMethod': 'Native SMB with 128KB chunks',
      'optimizationLevel': 'High',
    };

    if (_chunkReader != null) {
      stats['chunkReader'] = {
        'isInitialized': _chunkReader!.isInitialized,
        'isConnected': _chunkReader!.isConnected,
        'availableWorkerCount': _chunkReader!.availableWorkerCount,
        'currentPath': _chunkReader!.currentPath,
        'fileSize': _chunkReader!.fileSize,
      };
    }

    if (_prefetchController != null) {
      stats['prefetchController'] = _prefetchController!.bufferStats;
    }

    // Add streaming performance metrics
    stats['streaming'] = {
      'chunkSize': '128KB',
      'bufferSize': '5MB',
      'prefetchSize': '2MB',
      'maxConnections': 4,
      'estimatedSpeed': '5-10 MB/s (WiFi), 500KB-1MB/s (4G)',
    };

    return stats;
  }

  /// Generate thumbnail for image or video file
  @override
  Future<Uint8List?> getThumbnail(String tabPath, int size) async {
    if (!isConnected) {
      debugPrint(
        'OptimizedSMBService: Not connected, cannot generate thumbnail',
      );
      return null;
    }

    try {
      final smbPath = _getSmbPathFromTabPath(tabPath);
      // debugPrint(
      //     'OptimizedSMBService: Generating thumbnail for: $smbPath (size: $size)');

      final smbService = SmbNativeService.instance;
      final thumbnailData = await smbService.generateThumbnail(
        smbPath,
        width: size,
        height: size,
      );

      if (thumbnailData != null && thumbnailData.isNotEmpty) {
        debugPrint(
          'OptimizedSMBService: Successfully generated thumbnail (${thumbnailData.length} bytes)',
        );
        return thumbnailData;
      } else {
        debugPrint(
          'OptimizedSMBService: Thumbnail generation returned null or empty data',
        );
        return null;
      }
    } catch (e) {
      debugPrint('OptimizedSMBService: Error generating thumbnail: $e');
      return null;
    }
  }

  /// Get the underlying MobileSmbClient for direct access
  /// This allows other components to use libsmb2 streaming directly
  MobileSmbClient get smbClient => _smbClient;

  /// Create a new MobileSmbClient instance with the same configuration
  /// Useful for creating separate streaming connections
  Future<MobileSmbClient?> createNewSmbClient() async {
    if (!_isConnected || _smbClient.currentConfig == null) {
      return null;
    }

    try {
      final newClient = MobileSmbClient();
      final success = await newClient.connect(_smbClient.currentConfig!);

      if (success) {
        debugPrint('OptimizedSMBService: Created new SMB client successfully');
        return newClient;
      } else {
        debugPrint('OptimizedSMBService: Failed to create new SMB client');
        return null;
      }
    } catch (e) {
      debugPrint('OptimizedSMBService: Error creating new SMB client: $e');
      return null;
    }
  }

  /// Open file stream optimized for video streaming
  /// Returns a stream that can be used directly for media playback
  Stream<List<int>>? openFileStreamForVideo(
    String tabPath, {
    int chunkSize = 1024 * 1024,
  }) {
    try {
      final smbPath = _getSmbPathFromTabPath(tabPath);
      debugPrint('OptimizedSMBService: Opening video stream for: $smbPath');

      return _smbClient.openFileStreamOptimized(smbPath, chunkSize: chunkSize);
    } catch (e) {
      debugPrint('OptimizedSMBService: Error opening video stream: $e');
      return null;
    }
  }

  /// Open file stream with seek support for video streaming
  /// Useful for seeking to specific positions in video files
  Stream<List<int>>? seekFileStreamForVideo(
    String tabPath,
    int offset, {
    int chunkSize = 1024 * 1024,
  }) {
    try {
      final smbPath = _getSmbPathFromTabPath(tabPath);
      debugPrint(
        'OptimizedSMBService: Opening seekable video stream for: $smbPath at offset: $offset',
      );

      return _smbClient.seekFileStreamOptimized(
        smbPath,
        offset,
        chunkSize: chunkSize,
      );
    } catch (e) {
      debugPrint(
        'OptimizedSMBService: Error opening seekable video stream: $e',
      );
      return null;
    }
  }

  /// Benchmark streaming performance
  Future<Map<String, dynamic>> benchmarkStreaming(String remotePath) async {
    final startTime = DateTime.now();
    final results = <String, dynamic>{};

    try {
      final smbPath = _getSmbPathFromTabPath(remotePath);
      final fileInfo = await _smbClient.getFileInfo(smbPath);

      if (fileInfo == null) {
        results['error'] = 'File not found';
        return results;
      }

      results['fileSize'] = fileInfo.size;
      results['fileName'] = remotePath.split('/').last;

      // Test streaming speed
      final stream = _smbClient.seekFileStreamOptimized(
        smbPath,
        0,
        chunkSize: 128 * 1024,
      );
      if (stream != null) {
        int totalBytes = 0;
        int chunkCount = 0;
        const testDuration = Duration(seconds: 5);
        final endTime = startTime.add(testDuration);

        await for (final chunk in stream) {
          totalBytes += chunk.length;
          chunkCount++;

          if (DateTime.now().isAfter(endTime)) {
            break;
          }
        }

        final actualDuration = DateTime.now().difference(startTime);
        final speedMBps =
            (totalBytes / 1024 / 1024) / (actualDuration.inMilliseconds / 1000);

        results['testDuration'] = actualDuration.inMilliseconds;
        results['totalBytes'] = totalBytes;
        results['chunkCount'] = chunkCount;
        results['speedMBps'] = speedMBps.toStringAsFixed(2);
        results['speedKBps'] = (speedMBps * 1024).toStringAsFixed(0);
        results['status'] = 'Success';
      } else {
        results['error'] = 'Failed to create stream';
      }
    } catch (e) {
      results['error'] = e.toString();
    }

    return results;
  }
}
