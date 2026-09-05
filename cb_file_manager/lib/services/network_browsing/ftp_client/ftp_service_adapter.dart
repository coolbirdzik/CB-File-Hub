import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pathlib;

import 'ftp_client.dart';

/// Adapter to integrate the custom FTP client with the network_browsing_service
class FtpServiceAdapter {
  /// The underlying FTP client
  final FtpClient _client;

  /// Current connection state
  bool _isConnected = false;

  /// Current directory path
  String _currentPath = '/';

  /// Creates a new FTP service adapter
  FtpServiceAdapter({
    required String host,
    int port = 21,
    String username = 'anonymous',
    String password = 'anonymous@',
  }) : _client = FtpClient(
         host: host,
         port: port,
         username: username,
         password: password,
       );

  /// Connects to the FTP server
  Future<bool> connect() async {
    try {
      _isConnected = await _client.connect();
      if (_isConnected) {
        _currentPath = _client.currentDirectory ?? '/';
      }
      return _isConnected;
    } catch (e) {
      debugPrint('FTP connection error: $e');
      return false;
    }
  }

  /// Disconnects from the FTP server
  Future<void> disconnect() async {
    await _client.disconnect();
    _isConnected = false;
  }

  /// Sends a NOOP command to keep the connection alive
  Future<void> sendNoop() async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }
    await _client.sendNoop();
  }

  /// Returns true if connected to the server
  bool get isConnected => _isConnected;

  /// Returns the current directory path
  String get currentPath => _currentPath;

  /// Lists files and directories in the current or specified path
  Future<List<FileSystemEntity>> listDirectory([String? path]) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    final targetPath = path ?? _currentPath;
    debugPrint('FtpServiceAdapter: Listing directory: $targetPath');

    final ftpFileInfos = await _client.listDirectory(targetPath);
    debugPrint(
      'FtpServiceAdapter: Got ${ftpFileInfos.length} FtpFileInfo objects',
    );

    // Convert FtpFileInfo objects to FileSystemEntity objects
    final List<FileSystemEntity> results = [];

    for (var fileInfo in ftpFileInfos) {
      // Make sure we have robust path handling
      if (fileInfo.path.isEmpty) {
        debugPrint('FtpServiceAdapter: Skipping item with empty path');
        continue;
      }

      debugPrint(
        'FtpServiceAdapter: Processing ${fileInfo.isDirectory ? 'directory' : 'file'}: ${fileInfo.name}, path: ${fileInfo.path}',
      );

      try {
        if (fileInfo.isDirectory) {
          // Ensure the path is properly formatted as a network path
          final dirPath = fileInfo.path;

          // Create a directory object with the processed path
          final directory = Directory(dirPath);
          results.add(directory);
          debugPrint('FtpServiceAdapter: Added directory: ${directory.path}');
        } else {
          // Ensure the path is properly formatted as a network path
          final filePath = fileInfo.path;

          // Create a file object with the processed path
          final file = File(filePath);
          results.add(file);
          debugPrint('FtpServiceAdapter: Added file: ${file.path}');
        }
      } catch (e) {
        debugPrint('FtpServiceAdapter: Error processing item: $e');
      }
    }

    debugPrint(
      'FtpServiceAdapter: Returning ${results.length} FileSystemEntity objects',
    );
    for (var item in results) {
      debugPrint('  - ${item.runtimeType}: ${item.path}');
    }

    if (path != null) {
      _currentPath = path;
    }

    return results;
  }

  /// Changes the current directory
  Future<bool> changeDirectory(String path) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    final success = await _client.changeDirectory(path);
    if (success) {
      _currentPath = _client.currentDirectory ?? path;
    }

    return success;
  }

  /// Returns to the parent directory
  Future<bool> goToParentDirectory() async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    final success = await _client.goToParentDirectory();
    if (success) {
      _currentPath = _client.currentDirectory ?? pathlib.dirname(_currentPath);
    }

    return success;
  }

  /// Creates a new directory
  Future<bool> createDirectory(String dirName) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.createDirectory(dirName);
  }

  /// Deletes a directory
  Future<bool> deleteDirectory(String dirName) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.deleteDirectory(dirName);
  }

  /// Deletes a file
  Future<bool> deleteFile(String fileName) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.deleteFile(fileName);
  }

  /// Renames a file or directory
  Future<bool> rename(String oldName, String newName) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.rename(oldName, newName);
  }

  /// Downloads a file
  Future<Uint8List?> downloadFile(String remotePath) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.downloadFile(remotePath);
  }

  /// Downloads a file with progress tracking
  Future<Uint8List?> downloadFileWithProgress(
    String remotePath,
    void Function(int bytesReceived) onProgress,
  ) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.downloadFileWithProgress(remotePath, onProgress);
  }

  /// Uploads a file
  Future<bool> uploadFile(String localPath, String remotePath) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.uploadFile(localPath, remotePath);
  }

  /// Uploads a file with progress tracking
  Future<bool> uploadFileWithProgress(
    String localPath,
    String remotePath,
    void Function(int bytesSent) onProgress,
  ) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.uploadFileWithProgress(
      localPath,
      remotePath,
      onProgress,
    );
  }

  /// Uploads data directly
  Future<bool> uploadData(Uint8List data, String remotePath) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.uploadData(data, remotePath);
  }

  /// Returns the absolute path by joining the current directory with a relative path
  String absolutePath(String relativePath) {
    if (pathlib.isAbsolute(relativePath)) {
      return relativePath;
    }

    return pathlib.join(_currentPath, relativePath);
  }

  /// Set passive mode
  Future<bool> setPassiveMode(bool passive) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.setPassiveMode(passive);
  }

  /// Toggle between passive and active mode
  Future<bool> togglePassiveMode() async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    return await _client.togglePassiveMode();
  }

  /// Normalize path for FTP operations
  static String normalizePath(String path) {
    // Ensure the path starts with "/"
    if (!path.startsWith('/') && !path.startsWith('#')) {
      path = '/$path';
    }

    // Special case for FTP root
    if (path == '/' || path.endsWith('://')) {
      return '/';
    }

    // For network paths that contain service information, extract just the path part
    if (path.startsWith('#network/')) {
      final parts = path.split('://');
      if (parts.length > 1) {
        path = parts[1];
        if (!path.startsWith('/')) {
          path = '/$path';
        }
      }
    }

    // Ensure we don't have double slashes
    while (path.contains('//')) {
      path = path.replaceAll('//', '/');
    }

    debugPrint("FtpServiceAdapter: Normalized path: '$path'");
    return path;
  }
}
