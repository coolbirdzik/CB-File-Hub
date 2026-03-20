import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:mobile_smb_native/mobile_smb_native.dart';
import 'network_service_base.dart';
import 'package:cb_file_manager/services/network_credentials_service.dart';
import 'package:cb_file_manager/models/database/network_credentials.dart';

/// Mobile SMB service implementation using the mobile_smb_native plugin
import 'package:cb_file_manager/services/network_browsing/i_smb_service.dart';

class MobileSMBService implements ISmbService {
  static const String _smbScheme = 'smb';

  final MobileSmbClient _smbClient = MobileSmbClient();

  // Connection state
  String _connectedHost = '';
  String _connectedShare = '';
  bool _isConnected = false;

  // Cache last successful credentials for reconnect attempts.
  String _lastUsername = '';
  String _lastPassword = '';
  int _lastPort = 445;

  @override
  String get serviceName => 'SMB';

  @override
  String get serviceDescription => 'Mobile SMB File Sharing';

  @override
  dynamic get serviceIcon => PhosphorIconsLight.folder;

  @override
  bool isAvailable() => Platform.isAndroid || Platform.isIOS;

  @override
  bool get isConnected => _isConnected;

  @override
  String get basePath => '$_smbScheme://$_connectedHost/$_connectedShare';

  @override
  Future<String?> getSmbDirectLink(String tabPath) async {
    try {
      final hostFromPath = _getHostFromTabPath(tabPath);
      final targetHost =
          _connectedHost.isNotEmpty ? _connectedHost : hostFromPath;
      if (targetHost.isEmpty) {
        return null;
      }

      // 1. Get credentials (prefer stored credentials, fallback to active config)
      String username = '';
      String password = '';
      String domain = '';
      NetworkCredentials? credentials;
      try {
        credentials = NetworkCredentialsService()
            .findCredentials(serviceType: 'SMB', host: targetHost);
      } catch (e) {
        credentials = null;
      }

      if (credentials != null) {
        username = credentials.username;
        password = credentials.password;
        domain = credentials.domain ?? '';
      } else {
        final config = _smbClient.currentConfig;
        if (config != null) {
          username = config.username;
          password = config.password;
          domain = config.domain ?? '';
        } else {}
      }

      // 2. Get the relative SMB path from the tab path
      final smbPath = _getSmbPathFromTabPath(tabPath);
      if (smbPath.isEmpty || smbPath == '/') {
        debugPrint(
            'MobileSMBService: Could not determine a valid file path from $tabPath');
        return null;
      }

      // The smbPath from _getSmbPathFromTabPath is like "/share/folder/file.txt"
      // We need to remove the leading slash for the URL
      final pathComponent =
          smbPath.startsWith('/') ? smbPath.substring(1) : smbPath;

      // 3. Construct the direct link; keep common SMB path characters intact
      final encodedPath = _encodeSmbPath(pathComponent);
      String link;
      if (username.isNotEmpty) {
        final userWithDomain =
            domain.isNotEmpty ? '$domain;$username' : username;
        final encodedUser = Uri.encodeComponent(userWithDomain);
        final encodedPass = Uri.encodeComponent(password);
        link = 'smb://$encodedUser:$encodedPass@$targetHost/$encodedPath';
      } else {
        link = 'smb://$targetHost/$encodedPath';
      }

      return link;
    } catch (e) {
      debugPrint('MobileSMBService: Error generating SMB direct link: $e');
      return null;
    }
  }

  /// Converts an application-specific tabPath to SMB path format
  /// e.g., "#network/smb/server/share/folder/" -> "/share/folder"
  String _getSmbPathFromTabPath(String tabPath) {
    final lowerPath = tabPath.toLowerCase();
    if (!lowerPath.startsWith('#network/$_smbScheme/')) {
      debugPrint('Invalid tab path format: $tabPath');
      return '/';
    }

    final bool endsWithSlash = tabPath.endsWith('/') || tabPath.endsWith('\\');

    // Remove the leading "#network/"
    final pathWithoutPrefix = tabPath.substring('#network/'.length);
    final parts =
        pathWithoutPrefix.split('/').where((p) => p.isNotEmpty).toList();

    // parts = ["smb", "host", "share", "folder"]
    if (parts.length < 2) {
      debugPrint('Tab path has too few parts: $tabPath');
      return '/';
    }

    // If no share specified, return root
    if (parts.length == 2) {
      return '/';
    }

    // If only share specified (parts.length == 3), return share root
    if (parts.length == 3) {
      final shareName = Uri.decodeComponent(parts[2]);
      final root = '/$shareName';
      return endsWithSlash ? '$root/' : root;
    }

    // Extract path after share
    if (parts.length > 3) {
      final shareName = Uri.decodeComponent(parts[2]);
      final folders =
          parts.sublist(3).map((f) => Uri.decodeComponent(f)).toList();
      final p = '/$shareName/${folders.join('/')}';
      return endsWithSlash ? '$p/' : p;
    }

    return '/';
  }

  String _encodeSmbPath(String path) {
    if (path.isEmpty) return path;
    final normalized = path.replaceAll('\\', '/');
    return normalized
        .replaceAll('%', '%25')
        .replaceAll('#', '%23')
        .replaceAll('?', '%3F')
        .replaceAll(' ', '%20');
  }

  /// Extract SMB host from a tab path.
  /// e.g., "#network/SMB/192.168.1.200/Share/folder" -> "192.168.1.200"
  String _getHostFromTabPath(String tabPath) {
    final lowerPath = tabPath.toLowerCase();
    if (!lowerPath.startsWith('#network/$_smbScheme/')) {
      return '';
    }

    final pathWithoutPrefix = tabPath.substring('#network/'.length);
    final parts =
        pathWithoutPrefix.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) {
      return '';
    }

    return Uri.decodeComponent(parts[1]);
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
        errorMessage: 'Mobile SMB is only available on Android and iOS.',
      );
    }

    await disconnect();

    // Parse host to extract server and share if provided
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
        timeoutMs:
            120000, // Increase timeout to 120 seconds for large image streaming
      );

      final success = await _smbClient.connect(config);

      if (success) {
        _isConnected = true;
        _connectedHost = serverHost;
        _connectedShare = shareName ?? '';
        _lastUsername = username;
        _lastPassword = password ?? '';
        _lastPort = port ?? 445;

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
          debugPrint('MobileSMBService: Credentials saved successfully');
        } catch (e) {
          debugPrint('MobileSMBService: Failed to save credentials: $e');
          // Don't fail the connection if credential saving fails
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

  @override
  Future<void> disconnect() async {
    try {
      await _smbClient.disconnect();
    } catch (e) {
      debugPrint('Error disconnecting from SMB: $e');
    } finally {
      _isConnected = false;
      _connectedHost = '';
      _connectedShare = '';
    }
  }

  /// Best-effort reconnect for cases where the native connection gets stuck.
  Future<bool> reconnect() async {
    if (_connectedHost.isEmpty) return false;

    String username = _lastUsername;
    String password = _lastPassword;

    if (username.isEmpty) {
      try {
        final credentials = NetworkCredentialsService()
            .findCredentials(serviceType: 'SMB', host: _connectedHost);
        if (credentials != null) {
          username = credentials.username;
          password = credentials.password;
        }
      } catch (_) {}
    }

    try {
      await _smbClient.disconnect().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ignore disconnect errors/timeouts.
    }

    final shareName = _connectedShare.isEmpty ? null : _connectedShare;
    final config = SmbConnectionConfig(
      host: _connectedHost,
      port: _lastPort,
      username: username,
      password: password,
      shareName: shareName,
      timeoutMs: 60000,
    );

    try {
      final ok =
          await _smbClient.connect(config).timeout(const Duration(seconds: 6));
      _isConnected = ok;
      return ok;
    } catch (_) {
      _isConnected = false;
      return false;
    }
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String tabPath) async {
    debugPrint('MobileSMBService: listDirectory called with tabPath: $tabPath');

    if (!isConnected) {
      debugPrint('MobileSMBService: Not connected to SMB server');
      throw Exception('Not connected to SMB server');
    }

    try {
      // Check if we're listing shares (server root)
      final pathWithoutPrefix = tabPath.substring('#network/'.length);
      final parts =
          pathWithoutPrefix.split('/').where((p) => p.isNotEmpty).toList();

      debugPrint(
        'MobileSMBService: Path parts: $parts, length: ${parts.length}',
      );

      if (parts.length <= 2) {
        // List shares
        debugPrint('MobileSMBService: Listing shares for tabPath: $tabPath');
        return await _listShares(tabPath);
      }

      // List directory contents
      final smbPath = _getSmbPathFromTabPath(tabPath);
      debugPrint('MobileSMBService: Converted tabPath to smbPath: $smbPath');

      final Duration timeout = const Duration(seconds: 12);
      List<SmbFile> smbFiles;
      try {
        smbFiles = await _smbClient.listDirectory(smbPath).timeout(timeout);
      } on TimeoutException {
        await reconnect();
        smbFiles = await _smbClient.listDirectory(smbPath).timeout(timeout);
      }
      debugPrint(
        'MobileSMBService: Got ${smbFiles.length} files from native client',
      );

      final entities = <FileSystemEntity>[];

      for (final smbFile in smbFiles) {
        debugPrint(
          'MobileSMBService: Processing file: ${smbFile.name}, isDirectory: ${smbFile.isDirectory}',
        );

        // Create tab path for this item
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

      debugPrint('MobileSMBService: Returning ${entities.length} entities');
      return entities;
    } catch (e) {
      debugPrint('MobileSMBService: Error listing directory $tabPath: $e');
      rethrow;
    }
  }

  Future<List<FileSystemEntity>> _listShares(String tabPath) async {
    debugPrint('MobileSMBService: _listShares called with tabPath: $tabPath');

    try {
      final shares = await _smbClient.listShares();
      debugPrint(
        'MobileSMBService: Got ${shares.length} shares from native client: $shares',
      );

      final entities = <FileSystemEntity>[];

      // Extract server from tab path
      final pathWithoutPrefix = tabPath.substring('#network/'.length);
      final parts =
          pathWithoutPrefix.split('/').where((p) => p.isNotEmpty).toList();
      final server =
          parts.length > 1 ? Uri.decodeComponent(parts[1]) : _connectedHost;

      debugPrint('MobileSMBService: Server extracted: $server');

      for (final shareName in shares) {
        final shareTabPath =
            '#network/${_smbScheme.toUpperCase()}/${Uri.encodeComponent(server)}/${Uri.encodeComponent(shareName)}/';
        debugPrint(
          'MobileSMBService: Adding share: $shareName -> $shareTabPath',
        );
        entities.add(Directory(shareTabPath));
      }

      debugPrint(
        'MobileSMBService: Returning ${entities.length} share entities',
      );
      return entities;
    } catch (e) {
      debugPrint('MobileSMBService: Error listing shares: $e');
      rethrow;
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
    // For now, just call the regular getFile method
    // TODO: Implement progress tracking when the native plugin supports it
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
    // For now, just call the regular putFile method
    // TODO: Implement progress tracking when the native plugin supports it
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
    if (!isConnected) {
      throw Exception('Not connected to SMB server');
    }

    // Mobile SMB plugin doesn't have rename function yet
    // We could implement it as copy + delete, but that's risky
    debugPrint('Rename operation not yet supported in mobile SMB');
    return false;
  }

  @override
  Stream<List<int>>? openFileStream(String remotePath, {int startOffset = 0}) {
    try {
      debugPrint(
          'MobileSmbService openFileStream: Starting for path: $remotePath');

      if (!isConnected) {
        debugPrint(
            'MobileSmbService openFileStream: Not connected to SMB server');
        return null;
      }

      // Convert path to SMB format
      final smbPath = _getSmbPathFromTabPath(remotePath);
      debugPrint(
          'MobileSmbService openFileStream: Converted SMB path: $smbPath');

      // Use optimized streaming with larger chunk size for better performance
      final stream = _smbClient.openFileStreamOptimized(smbPath,
          chunkSize:
              128 * 1024); // 128KB chunks for better streaming performance

      if (stream == null) {
        debugPrint(
            'MobileSmbService openFileStream: Failed to create optimized stream');
        return null;
      }

      debugPrint(
          'MobileSmbService openFileStream: Successfully created optimized stream');
      return stream;
    } catch (e) {
      debugPrint('MobileSmbService openFileStream error: $e');
      return null;
    }
  }

  /// Open file stream with seek support for video streaming
  Stream<List<int>>? openFileStreamWithSeek(String remotePath, int offset) {
    try {
      debugPrint(
          'MobileSmbService openFileStreamWithSeek: Starting for path: $remotePath at offset: $offset');

      if (!isConnected) {
        debugPrint(
            'MobileSmbService openFileStreamWithSeek: Not connected to SMB server');
        return null;
      }

      // Convert path to SMB format
      final smbPath = _getSmbPathFromTabPath(remotePath);
      debugPrint(
          'MobileSmbService openFileStreamWithSeek: Converted SMB path: $smbPath');

      // Use seek-optimized streaming with larger chunk size
      final stream = _smbClient.seekFileStreamOptimized(smbPath, offset,
          chunkSize:
              128 * 1024); // 128KB chunks for better streaming performance

      if (stream == null) {
        debugPrint(
            'MobileSmbService openFileStreamWithSeek: Failed to create seek stream');
        return null;
      }

      debugPrint(
          'MobileSmbService openFileStreamWithSeek: Successfully created seek stream');
      return stream;
    } catch (e) {
      debugPrint('MobileSmbService openFileStreamWithSeek error: $e');
      return null;
    }
  }

  /// Get SMB version information
  Future<String> getSmbVersion() async {
    try {
      return await _smbClient.getSmbVersion();
    } catch (e) {
      debugPrint('Failed to get SMB version: $e');
      return 'Unknown';
    }
  }

  /// Get SMB version for a specific host (placeholder)
  Future<String?> getSmbVersionForHost(String host) async {
    // This is now a placeholder, actual version is fetched upon connection.
    return "v?.?";
  }

  /// Create HTTP range request URL for SMB file (fallback mechanism)
  /// This can be used when SMB streaming fails due to buffer issues
  Future<String?> createHttpRangeUrl(String smbPath) async {
    try {
      // This would require setting up a local HTTP server that serves SMB files
      // For now, we'll return null to indicate this feature is not implemented
      debugPrint('HTTP range URL creation not implemented yet');
      return null;
    } catch (e) {
      debugPrint('Error creating HTTP range URL: $e');
      return null;
    }
  }

  /// Check if HTTP range fallback is available
  bool isHttpRangeFallbackAvailable() {
    // For now, return false as this feature needs to be implemented
    return false;
  }

  /// Get connection information including SMB version
  Future<String> getConnectionInfo() async {
    try {
      return await _smbClient.getConnectionInfo();
    } catch (e) {
      debugPrint('Failed to get connection info: $e');
      return 'Connection info unavailable';
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

  /// Read file data directly as bytes (for streaming fallback)
  @override
  Future<Uint8List?> readFileData(String remotePath) async {
    final startTime = DateTime.now();
    debugPrint('=== MobileSMBService.readFileData START ===');
    debugPrint('MobileSMBService: remotePath: $remotePath');
    debugPrint('MobileSMBService: timestamp: ${startTime.toIso8601String()}');
    debugPrint('MobileSMBService: connection status: $isConnected');

    if (!isConnected) {
      debugPrint('MobileSMBService: ERROR - Not connected to SMB server');
      debugPrint(
          'MobileSMBService: Server: $_connectedHost, Share: $_connectedShare');
      return null;
    }

    try {
      debugPrint('MobileSMBService: Converting path...');
      final smbPath = _getSmbPathFromTabPath(remotePath);
      debugPrint('MobileSMBService: Original path: $remotePath');
      debugPrint('MobileSMBService: Converted SMB path: $smbPath');
      debugPrint('MobileSMBService: Path length: ${smbPath.length} characters');
      debugPrint('MobileSMBService: Path bytes: ${smbPath.codeUnits}');

      debugPrint('MobileSMBService: Calling native readFile...');
      final nativeStartTime = DateTime.now();
      final fileData = await _smbClient.readFile(smbPath);
      final nativeDuration = DateTime.now().difference(nativeStartTime);

      if (fileData.isNotEmpty) {
        debugPrint('MobileSMBService: SUCCESS - File data read');
        debugPrint('MobileSMBService: Data length: ${fileData.length} bytes');
        debugPrint(
            'MobileSMBService: Data size: ${(fileData.length / 1024 / 1024).toStringAsFixed(2)} MB');
        debugPrint(
            'MobileSMBService: Native call duration: ${nativeDuration.inMilliseconds}ms');
        debugPrint(
            'MobileSMBService: Transfer speed: ${(fileData.length / 1024 / 1024 / (nativeDuration.inMilliseconds / 1000)).toStringAsFixed(2)} MB/s');

        final preview = fileData
            .take(10)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        debugPrint('MobileSMBService: First 10 bytes: $preview');

        return Uint8List.fromList(fileData);
      } else {
        debugPrint(
            'MobileSMBService: ERROR - Received empty file data for $smbPath');
        debugPrint(
            'MobileSMBService: Native call duration: ${nativeDuration.inMilliseconds}ms');
        return null;
      }
    } catch (e, stackTrace) {
      final duration = DateTime.now().difference(startTime);
      debugPrint('MobileSMBService: EXCEPTION in readFileData');
      debugPrint('MobileSMBService: Error: $e');
      debugPrint('MobileSMBService: Error type: ${e.runtimeType}');
      debugPrint('MobileSMBService: Duration: ${duration.inMilliseconds}ms');
      debugPrint('MobileSMBService: Stack trace: $stackTrace');
      return null;
    } finally {
      final totalDuration = DateTime.now().difference(startTime);
      debugPrint(
          'MobileSMBService: Total readFileData time: ${totalDuration.inMilliseconds}ms');
      debugPrint('=== MobileSMBService.readFileData END ===');
    }
  }

  /// Generate thumbnail for image or video file using mobile_smb_native
  @override
  Future<Uint8List?> getThumbnail(String tabPath, int size) async {
    if (!isConnected) {
      debugPrint('MobileSMBService: Not connected, cannot generate thumbnail');
      return null;
    }

    try {
      final smbPath = _getSmbPathFromTabPath(tabPath);
      // debugPrint(
      //   'MobileSMBService: Generating thumbnail for: $smbPath (size: $size)',
      // );

      // Use the mobile_smb_native service to generate thumbnail
      final smbService = SmbNativeService.instance;

      // Ensure the native service is connected before generating thumbnail
      if (!smbService.isConnected) {
        final credentials = NetworkCredentialsService()
            .findCredentials(serviceType: 'SMB', host: _connectedHost);
        if (credentials != null) {
          final config = SmbConnectionConfig(
            host: _connectedHost,
            shareName: _connectedShare,
            username: credentials.username,
            password: credentials.password,
          );
          await smbService.connect(config);
        }
      }

      final thumbnailData = await smbService.generateThumbnail(
        smbPath,
        width: size,
        height: size,
      );

      // if (thumbnailData != null) {
      //   debugPrint('Successfully generated thumbnail for $smbPath');
      // } else {
      //   debugPrint('Failed to generate thumbnail for $smbPath');
      // }

      if (thumbnailData != null && thumbnailData.isNotEmpty) {
        // debugPrint(
        //   'MobileSMBService: Successfully generated thumbnail (${thumbnailData.length} bytes)',
        // );
        return thumbnailData;
      } else {
        // debugPrint(
        //   'MobileSMBService: Thumbnail generation returned null or empty data',
        // );
        return null;
      }
    } catch (e) {
      debugPrint('MobileSMBService: Error generating thumbnail: $e');
      return null;
    }
  }
}
