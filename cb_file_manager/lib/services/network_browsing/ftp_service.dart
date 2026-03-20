import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path/path.dart' as path;
import 'ftp_client/index.dart';

import 'network_service_base.dart';

/// Service for FTP (File Transfer Protocol) network file access
class FTPService implements NetworkServiceBase {
  static const String _ftpPrefix = 'ftp://';
  static const int _defaultFtpPort = 21;

  // State variables
  String _host = '';
  int _port = _defaultFtpPort;
  String _username = '';
  String _password = '';
  String _currentPath = '/';
  bool _connected = false;
  String? _connectionError;

  // FTP client
  FtpServiceAdapter? _ftpClient;

  // Keep-alive timer
  Timer? _keepAliveTimer;

  // Debugging info
  final Map<String, dynamic> _lastConnectionInfo = {};

  // FTP metadata storage (UI path -> meta)
  final Map<String, FtpMeta> _metaMap = {};

  FtpMeta? getMeta(String uiPath) => _metaMap[uiPath];

  @override
  String get serviceName => 'FTP';

  @override
  String get serviceDescription => 'File Transfer Protocol (FTP)';

  @override
  IconData get serviceIcon => PhosphorIconsLight.cloudArrowUp;

  @override
  bool isAvailable() => true; // Available on all platforms

  @override
  bool get isConnected => _connected;

  @override
  String get basePath => '$_ftpPrefix$_username@$_host:$_port';

  // Method to get connection diagnostic info
  Map<String, dynamic> getConnectionDiagnostics() {
    return {
      'host': _host,
      'port': _port,
      'username': _username,
      'passwordProvided': _password.isNotEmpty,
      'connected': _connected,
      'currentPath': _currentPath,
      'lastError': _connectionError,
      'lastConnectionInfo': _lastConnectionInfo,
    };
  }

  @override
  Future<ConnectionResult> connect({
    required String host,
    required String username,
    String? password,
    int? port,
    Map<String, dynamic>? additionalOptions,
  }) async {
    try {
      // Check if we have a passive mode setting
      bool usePassiveMode = true; // Default to passive mode
      if (additionalOptions != null &&
          additionalOptions.containsKey('usePassiveMode')) {
        usePassiveMode = additionalOptions['usePassiveMode'] as bool;
      }

      debugPrint(
        'FTPService: Connecting to $host with passive mode: $usePassiveMode',
      );

      // Create and connect to FTP server
      final client = FtpServiceAdapter(
        host: host,
        port: port ?? 21,
        username: username,
        password: password ?? 'anonymous',
      );

      await client.connect();

      // Set passive/active mode based on setting
      await client.setPassiveMode(usePassiveMode);

      // Test connection by trying to list the directory
      try {
        final files = await client.listDirectory();
        debugPrint(
          'FTPService: Successfully listed ${files.length} files/directories',
        );
      } catch (e) {
        debugPrint('FTPService: Error listing directory: $e');

        // If listing fails, try toggling passive mode
        debugPrint('FTPService: Trying to toggle passive mode');
        await client.togglePassiveMode();

        try {
          final files = await client.listDirectory();
          debugPrint(
            'FTPService: Successfully listed ${files.length} files/directories after toggling mode',
          );
        } catch (e2) {
          // If it still fails after toggling, revert back and continue
          debugPrint(
            'FTPService: Error listing directory after toggling mode: $e2',
          );
          await client.setPassiveMode(usePassiveMode);
        }
      }

      // Store the client
      _ftpClient = client;

      // Generate unique path for FTP connection
      final basePath = 'ftp://$username@$host:${port ?? 21}/';
      _host = host;
      _port = port ?? 21;
      _username = username;
      _password = password ?? 'anonymous';
      _connected = true;
      _currentPath = '/';

      // Start keep-alive timer
      _startKeepAlive();

      return ConnectionResult(success: true, connectedPath: basePath);
    } catch (e) {
      debugPrint('FTPService: Connection error: $e');
      _connected = false;
      _connectionError = 'Failed to connect to FTP server: $e';
      return ConnectionResult(
        success: false,
        errorMessage: 'Failed to connect to FTP server: $e',
      );
    }
  }

  // _checkNetworkConnectivity removed (unused)

  @override
  Future<void> disconnect() async {
    _keepAliveTimer?.cancel(); // Stop keep-alive timer
    if (_connected && _ftpClient != null) {
      try {
        await _ftpClient!.disconnect();
      } catch (e) {
        // Ignore errors during disconnect
      }
      _connected = false;
      _connectionError = null;
    }
  }

  /// Starts a timer to send NOOP commands periodically to keep the connection alive.
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_connected && _ftpClient != null) {
        debugPrint("FTPService: Sending NOOP to keep connection alive.");
        _ftpClient!.sendNoop().catchError((e) {
          debugPrint(
            "FTPService: Keep-alive NOOP failed: $e. Connection lost.",
          );
          _connected = false;
          _connectionError = "Connection lost: Keep-alive failed.";
          timer.cancel();
        });
      } else {
        // If not connected anymore, stop the timer.
        timer.cancel();
      }
    });
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    if (!_connected || _ftpClient == null) {
      throw Exception('Not connected to FTP server');
    }

    // Convert UI path to FTP path
    final ftpPath = _convertUIPathToFtpPath(path);
    debugPrint("FTPService: Listing directory: $path -> $ftpPath");

    try {
      // Get FTP directory listing
      final List<dynamic> results = await _ftpClient!.listDirectory(ftpPath);

      debugPrint("FTPService: Got ${results.length} items from FTP");

      // Log the raw results for debugging
      for (var item in results) {
        debugPrint("FTPService: Raw item: $item (${item.runtimeType})");
        if (item is FtpFileInfo) {
          debugPrint(
            "  - FtpFileInfo: ${item.path} (isDir: ${item.isDirectory})",
          );
        }
      }

      // Convert to FileSystemEntity list
      final List<FileSystemEntity> result = [];

      for (var item in results) {
        // Check if this is a FtpFileInfo object (from our custom FTP client)
        if (item is FtpFileInfo) {
          // Create appropriate path for UI
          final uiPath = _convertFtpPathToUIPath(item.path);
          debugPrint(
            "FTPService: Converting FtpFileInfo path ${item.path} -> $uiPath",
          );

          if (item.isDirectory) {
            final dir = Directory(uiPath);
            result.add(dir);
            // Save metadata for directory
            _metaMap[uiPath] = FtpMeta(
              size: -1,
              modified: item.lastModified,
              isDirectory: true,
            );
            debugPrint(
              "FTPService: Added directory: $uiPath (${dir.runtimeType})",
            );
          } else {
            final file = File(uiPath);
            result.add(file);
            // Save metadata for file
            _metaMap[uiPath] = FtpMeta(
              size: item.size,
              modified: item.lastModified,
              isDirectory: false,
            );
            debugPrint("FTPService: Added file: $uiPath (${file.runtimeType})");
          }
        }
        // It could already be a Directory or File object
        else if (item is Directory) {
          final uiPath = _convertFtpPathToUIPath(item.path);
          final dir = Directory(uiPath);
          result.add(dir);
          debugPrint(
            "FTPService: Added directory from Directory: $uiPath (${dir.runtimeType})",
          );
        } else if (item is File) {
          final uiPath = _convertFtpPathToUIPath(item.path);
          final file = File(uiPath);
          result.add(file);
          debugPrint(
            "FTPService: Added file from File: $uiPath (${file.runtimeType})",
          );
        } else {
          // For unknown types, try to determine based on the path
          String itemPath = '';

          // Try different ways to get the path depending on what kind of object we have
          if (item.path != null) {
            itemPath = item.path.toString();
          } else if (item.name != null) {
            itemPath = item.name.toString();
          } else if (item.toString().contains('/')) {
            itemPath = item.toString();
          }

          debugPrint(
            "FTPService: Unknown item type, extracted path: '$itemPath'",
          );

          if (itemPath.isNotEmpty) {
            final uiPath = _convertFtpPathToUIPath(itemPath);

            // Simple heuristic: if it ends with a slash, it's probably a directory
            if (itemPath.endsWith('/') || itemPath.endsWith('\\')) {
              final dir = Directory(uiPath);
              result.add(dir);
              debugPrint(
                "FTPService: Added directory from unknown type: $uiPath (${dir.runtimeType})",
              );
            } else {
              final file = File(uiPath);
              result.add(file);
              debugPrint(
                "FTPService: Added file from unknown type: $uiPath (${file.runtimeType})",
              );
            }
          }
        }
      }

      // Force refresh the UI by making sure the objects are all the right type
      final directories = result.whereType<Directory>().toList();
      final files = result.whereType<File>().toList();

      final processedResult = [...directories, ...files];

      debugPrint(
        "FTPService: Final result - ${directories.length} directories, ${files.length} files",
      );

      // Log all the paths in the final result for debugging
      debugPrint("FTPService: Final paths:");
      for (var item in processedResult) {
        debugPrint("  - ${item.runtimeType}: ${item.path}");
      }

      return processedResult;
    } catch (e, stackTrace) {
      debugPrint('FTPService: Error listing directory: $e');
      debugPrint('FTPService: Stack trace: $stackTrace');
      throw Exception('Failed to list directory: $e');
    }
  }

  /// Convert UI path (#network/FTP/host/) to FTP path (/)
  String _convertUIPathToFtpPath(String uiPath) {
    if (!uiPath.startsWith('#network/FTP/')) {
      // It might be a relative path or already an FTP path
      return uiPath;
    }

    // Skip the #network/FTP/host/ part
    final parts = uiPath.split('/');
    if (parts.length <= 3) {
      // Root path
      return '/';
    }

    // Join the remaining parts with / to create the FTP path
    return '/${parts.sublist(3).join('/')}';
  }

  /// Convert FTP path to UI path
  String _convertFtpPathToUIPath(String ftpPath) {
    // If the path is already a UI path, return it
    if (ftpPath.startsWith('#network/')) {
      debugPrint(
        "FTPService: Path '$ftpPath' is already a UI path, no conversion needed",
      );
      return ftpPath;
    }

    // Otherwise, construct a proper network path
    final hostPart = Uri.encodeComponent('$_username@$_host:$_port');

    // Make sure ftpPath starts with /
    final normalizedPath = ftpPath.startsWith('/') ? ftpPath : '/$ftpPath';

    final uiPath = '#network/FTP/$hostPart$normalizedPath';
    debugPrint(
      "FTPService: Converted FTP path '$ftpPath' to UI path '$uiPath'",
    );
    return uiPath;
  }

  @override
  Future<File> getFile(String remotePath, String localPath) async {
    if (!_connected || _ftpClient == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      String normalizedPath = _normalizePath(remotePath);

      // Download the file
      final fileData = await _ftpClient!.downloadFile(normalizedPath);
      if (fileData == null) {
        throw Exception('Failed to download file: $normalizedPath');
      }

      // Write to local file
      File localFile = File(localPath);
      await localFile.writeAsBytes(fileData);

      return localFile;
    } catch (e) {
      throw Exception('Error downloading file: $e');
    }
  }

  @override
  Future<File> getFileWithProgress(
    String remotePath,
    String localPath,
    void Function(double progress)? onProgress,
  ) async {
    debugPrint(
      "FTPService: Getting file with progress: $remotePath -> $localPath",
    );

    if (!_connected || _ftpClient == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      String normalizedPath = _normalizePath(remotePath);
      debugPrint("FTPService: Normalized path for download: $normalizedPath");

      // Get file size if possible, otherwise we'll track progress without size
      int? totalSize;

      try {
        // Try to get file size from parent directory listing
        final parentDir = path.dirname(normalizedPath);
        final fileName = path.basename(normalizedPath);

        debugPrint(
          "FTPService: Getting file size from parent directory: $parentDir, filename: $fileName",
        );

        final filesList = await _ftpClient!.listDirectory(parentDir);
        debugPrint(
          "FTPService: Found ${filesList.length} entries in parent directory",
        );

        // Debug output all files in directory
        for (var item in filesList) {
          debugPrint(
            "FTPService: Directory entry: ${item.runtimeType} - ${item.path}",
          );
        }

        // Find matching file by name
        for (var item in filesList) {
          final itemName = path.basename(item.path);
          debugPrint("FTPService: Comparing $itemName with $fileName");

          if (itemName == fileName && !item.path.endsWith('/')) {
            try {
              final stat = await item.stat();
              totalSize = stat.size;
              debugPrint("FTPService: Found file size: $totalSize bytes");
              break;
            } catch (e) {
              debugPrint("FTPService: Error getting file stat: $e");
            }
          }
        }
      } catch (e) {
        debugPrint('FTPService: Could not determine file size: $e');
        // Continue without size information
      }

      // Create local file
      final localFile = File(localPath);
      debugPrint("FTPService: Created local file: ${localFile.path}");

      // Progress callback function
      void progressCallback(int bytesReceived) {
        debugPrint("FTPService: Download progress: $bytesReceived bytes");
        if (onProgress != null) {
          if (totalSize != null && totalSize > 0) {
            // If we know the total size, calculate percentage
            final progressValue = bytesReceived / totalSize;
            onProgress(progressValue.clamp(0.0, 1.0));
          } else {
            // If we don't know the size, just report bytes received
            // Note: this isn't a true percentage but helps show activity
            onProgress(
              -1.0,
            ); // Use negative value to indicate indeterminate progress
          }
        }
      }

      debugPrint("FTPService: Starting download with progress tracking...");
      // Download with progress
      final fileData = await _ftpClient!.downloadFileWithProgress(
        normalizedPath,
        progressCallback,
      );

      if (fileData == null) {
        throw Exception('Failed to download file: $normalizedPath');
      }

      debugPrint(
        "FTPService: Download complete, writing ${fileData.length} bytes to local file",
      );
      // Write to local file
      await localFile.writeAsBytes(fileData);

      // Final progress update
      if (onProgress != null) {
        onProgress(1.0);
      }

      return localFile;
    } catch (e, stack) {
      debugPrint("FTPService: Error downloading file: $e");
      debugPrint("FTPService: Stack trace: $stack");
      throw Exception('Error downloading file: $e');
    }
  }

  @override
  Future<bool> putFile(String localPath, String remotePath) async {
    if (!_connected || _ftpClient == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      String normalizedPath = _normalizePath(remotePath);

      return await _ftpClient!.uploadFile(localPath, normalizedPath);
    } catch (e) {
      throw Exception('Error uploading file: $e');
    }
  }

  @override
  Future<bool> putFileWithProgress(
    String localPath,
    String remotePath,
    void Function(double progress)? onProgress,
  ) async {
    if (!_connected || _ftpClient == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      String normalizedPath = _normalizePath(remotePath);

      // Get local file size for progress calculation
      final file = File(localPath);
      final fileSize = await file.length();

      return await _ftpClient!.uploadFileWithProgress(
        localPath,
        normalizedPath,
        (uploaded) {
          if (onProgress != null && fileSize > 0) {
            final progress = uploaded / fileSize;
            onProgress(progress.clamp(0.0, 1.0));
          }
        },
      );
    } catch (e) {
      throw Exception('Error uploading file: $e');
    }
  }

  @override
  Future<bool> deleteFile(String filePath) async {
    if (!_connected || _ftpClient == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      String normalizedPath = _normalizePath(filePath);

      return await _ftpClient!.deleteFile(normalizedPath);
    } catch (e) {
      throw Exception('Error deleting file: $e');
    }
  }

  @override
  Future<bool> createDirectory(String dirPath) async {
    if (!_connected || _ftpClient == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      String normalizedPath = _normalizePath(dirPath);

      return await _ftpClient!.createDirectory(normalizedPath);
    } catch (e) {
      throw Exception('Error creating directory: $e');
    }
  }

  @override
  Future<bool> deleteDirectory(String dirPath) async {
    if (!_connected || _ftpClient == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      String normalizedPath = _normalizePath(dirPath);

      return await _ftpClient!.deleteDirectory(normalizedPath);
    } catch (e) {
      throw Exception('Error deleting directory: $e');
    }
  }

  @override
  Future<bool> rename(String oldPath, String newPath) async {
    if (!_connected || _ftpClient == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      String oldNormalized = _normalizePath(oldPath);
      String newNormalized = _normalizePath(newPath);
      String newName = path.basename(newNormalized);

      return await _ftpClient!.rename(oldNormalized, newName);
    } catch (e) {
      throw Exception('Error renaming file/directory: $e');
    }
  }

  // Helper methods
  String _normalizePath(String filePath) {
    debugPrint("FTPService: Normalizing path: $filePath");

    if (filePath.startsWith('#network/FTP/')) {
      return _extractPathFromNetworkPath(filePath);
    }

    // Remove the protocol and server prefix if present
    String prefix = '$_ftpPrefix$_username@$_host:$_port';
    if (filePath.startsWith(prefix)) {
      filePath = filePath.substring(prefix.length);
    }

    // Ensure the path starts with '/'
    if (!filePath.startsWith('/')) {
      filePath = '/$filePath';
    }

    debugPrint("FTPService: Normalized path: $filePath");
    return filePath;
  }

  // _extractRelativePath removed (unused)

  // Helper method to extract path from network path format
  String _extractPathFromNetworkPath(String networkPath) {
    debugPrint("FTPService: Extracting path from network path: $networkPath");

    // Handle case where the path is already normalized
    if (!networkPath.startsWith('#network/FTP/')) {
      return networkPath;
    }

    try {
      // Remove the #network/FTP/ prefix
      final pathWithoutPrefix = networkPath.substring('#network/FTP/'.length);
      debugPrint("FTPService: Path without prefix: $pathWithoutPrefix");

      // Split by / to separate host component from path
      final parts = pathWithoutPrefix.split('/');
      if (parts.isEmpty) return '/';

      // The host part might be URL encoded, especially with @ and : characters
      String hostPart = parts[0];
      debugPrint("FTPService: Host part: $hostPart");

      // Skip the host component (first part) and join the rest as path
      if (parts.length > 1) {
        final pathParts = parts.skip(1).join('/');
        debugPrint("FTPService: Extracted path parts: $pathParts");
        return '/$pathParts';
      } else {
        // If there's only a host and no path components, return root
        return '/';
      }
    } catch (e) {
      debugPrint("FTPService: Error extracting path from network path: $e");
      return networkPath; // Return original path if extraction fails
    }
  }

  // Helper methods to create FileSystemEntity objects from FTP entries
  // _createFileInfo removed (unused)

  // _createDirectoryInfo removed (unused)

  @override
  Stream<List<int>>? openFileStream(String remotePath) {
    // FTP doesn't support true streaming, return null to use default download behavior
    return null;
  }

  @override
  Future<int?> getFileSize(String remotePath) async {
    // Try to get file size from directory listing
    if (!_connected || _ftpClient == null) return null;

    try {
      String normalizedPath = _normalizePath(remotePath);
      final parentDir = path.dirname(normalizedPath);
      final fileName = path.basename(normalizedPath);

      final filesList = await _ftpClient!.listDirectory(parentDir);

      for (var item in filesList) {
        final itemName = path.basename(item.path);
        if (itemName == fileName && !item.path.endsWith('/')) {
          try {
            final stat = await item.stat();
            return stat.size;
          } catch (e) {
            debugPrint("FTPService: Error getting file stat: $e");
          }
        }
      }
    } catch (e) {
      debugPrint('FTPService: Could not determine file size: $e');
    }

    return null;
  }

  @override
  Future<Uint8List?> getThumbnail(String remotePath, int size) async {
    // FTP doesn't support thumbnail generation, return null
    return null;
  }

  @override
  Future<Uint8List?> readFileData(String remotePath) async {
    // FTP doesn't support direct file data reading, return null
    return null;
  }
}

/// FTP metadata class
class FtpMeta {
  final int size; // -1 for directories/unknown
  final DateTime? modified;
  final bool isDirectory;

  const FtpMeta({
    required this.size,
    required this.modified,
    required this.isDirectory,
  });
}

// Helper class for dynamic loading
class Class {
  Class();

  dynamic get FTPConnect => throw Exception(
        'FTP functionality requires the ftpconnect package. '
        'Please ensure it is properly installed and configured in pubspec.yaml.',
      );
}
