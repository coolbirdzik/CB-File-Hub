import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'network_service_base.dart';

// WebDAV metadata class
class WebDavMeta {
  final int size; // -1 if directory
  final DateTime modified;
  const WebDavMeta(this.size, this.modified);
}

/// Service for WebDAV network file access
class WebDAVService implements NetworkServiceBase {
  static const String _webdavPrefix = 'webdav://';

  // State variables
  String _baseUrl = '';
  String _host = '';
  int _port = 0;
  bool _useSSL = false;
  String _username = '';
  String _password = '';
  bool _connected = false;
  String? _connectionError;
  HttpClient? _httpClient;

  // Mapping from local temp paths to remote paths
  final Map<String, String> _localToRemotePathMap = {};

  // WebDAV metadata storage
  final Map<String, WebDavMeta> _metaMap = {};

  /// Get metadata for a remote path
  WebDavMeta? getMeta(String remotePath) {
    return _metaMap[remotePath];
  }

  /// Add metadata for a remote path
  void _addMeta(String remotePath, WebDavMeta meta) {
    _metaMap[remotePath] = meta;
    debugPrint(
        'WebDAVService: Added meta for $remotePath: size=${meta.size}, modified=${meta.modified}');
  }

  /// Get remote path from local temp path
  String? getRemotePathFromLocal(String localPath) {
    debugPrint('WebDAVService: getRemotePathFromLocal called with: $localPath');
    debugPrint('WebDAVService: Current mappings: $_localToRemotePathMap');
    final remotePath = _localToRemotePathMap[localPath];
    debugPrint('WebDAVService: Found remote path: $remotePath');
    return remotePath;
  }

  /// Add mapping from local temp path to remote path
  void _addPathMapping(String localPath, String remotePath) {
    _localToRemotePathMap[localPath] = remotePath;
    debugPrint('WebDAVService: Added path mapping: $localPath -> $remotePath');
  }

  @override
  String get serviceName => 'WebDAV';

  @override
  String get serviceDescription => 'Web Distributed Authoring and Versioning';

  @override
  IconData get serviceIcon => PhosphorIconsLight.globe;

  @override
  bool isAvailable() => true; // Available on all platforms

  @override
  bool get isConnected => _connected;

  @override
  String get basePath =>
      '$_webdavPrefix${_username.isNotEmpty ? "$_username@" : ""}$_host:$_port';

  @override
  Future<ConnectionResult> connect({
    required String host,
    required String username,
    String? password,
    int? port,
    Map<String, dynamic>? additionalOptions,
  }) async {
    try {
      // Close any existing connection
      await disconnect();

      // Set connection details
      _host = host;
      _useSSL = additionalOptions?['useSSL'] ?? true;
      _port = port ?? (_useSSL ? 443 : 80);
      _username = username;
      _password = password ?? '';

      // Construct base URL
      final protocol = _useSSL ? 'https' : 'http';
      final basePath = additionalOptions?['basePath'] as String? ?? '';
      _baseUrl = '$protocol://$host:$_port$basePath';

      debugPrint('WebDAVService: Connecting to $_baseUrl');
      debugPrint('WebDAVService: Username: $_username');
      debugPrint('WebDAVService: Port: $_port');
      debugPrint('WebDAVService: SSL: $_useSSL');

      // Create HTTP client with proper configuration
      _httpClient = HttpClient();

      // Configure SSL if needed
      if (_useSSL) {
        _httpClient!.badCertificateCallback = (cert, host, port) {
          debugPrint('WebDAVService: SSL certificate warning for $host:$port');
          return true; // Accept all certificates for now
        };
      }

      // Test connection with PROPFIND request
      debugPrint('WebDAVService: Testing connection with PROPFIND request...');
      final testResult = await _makeRequest('PROPFIND', '/', depth: '0');
      debugPrint(
          'WebDAVService: Connection test result: ${testResult.statusCode}');
      debugPrint(
          'WebDAVService: Response body: ${testResult.body.substring(0, testResult.body.length > 200 ? 200 : testResult.body.length)}...');

      if (testResult.statusCode != 200 && testResult.statusCode != 207) {
        throw Exception(
            'WebDAV server not accessible: ${testResult.statusCode} - ${testResult.body}');
      }

      // Set connected status
      _connected = true;
      debugPrint('WebDAVService: Connection successful!');

      return ConnectionResult(success: true, connectedPath: _baseUrl);
    } catch (e) {
      debugPrint('WebDAVService: Connection failed: $e');
      _connectionError = 'Connection error: $e';
      _connected = false;
      return ConnectionResult(success: false, errorMessage: _connectionError);
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _connectionError = null;
    if (_httpClient != null) {
      _httpClient!.close();
    }
    _httpClient = null;
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String directoryPath) async {
    if (!_connected) {
      throw Exception('Not connected to WebDAV server');
    }

    try {
      final normalizedPath = _normalizePath(directoryPath);
      debugPrint('WebDAVService: Listing directory: $normalizedPath');

      final result = await _makeRequest('PROPFIND', normalizedPath, depth: '1');

      if (result.statusCode != 207) {
        throw Exception('Failed to list directory: ${result.statusCode}');
      }

      debugPrint(
          'WebDAVService: Directory listing response: ${result.body.substring(0, result.body.length > 500 ? 500 : result.body.length)}...');

      // Parse XML response manually
      final List<FileSystemEntity> entities =
          _parseWebDAVResponse(result.body, normalizedPath);

      debugPrint('WebDAVService: Found ${entities.length} entities');
      return entities;
    } catch (e) {
      debugPrint('WebDAVService: Error listing directory: $e');
      throw Exception('Failed to list directory: $e');
    }
  }

  @override
  Future<File> getFile(String remotePath, String localPath) async {
    if (!_connected) {
      throw Exception('Not connected to WebDAV server');
    }

    try {
      final normalizedPath = _normalizePath(remotePath);
      final result = await _makeRequest('GET', normalizedPath);

      if (result.statusCode != 200) {
        throw Exception('Failed to download file: ${result.statusCode}');
      }

      final file = File(localPath);
      await file.writeAsBytes(result.bodyBytes);
      return file;
    } catch (e) {
      throw Exception('Failed to download file: $e');
    }
  }

  @override
  Future<bool> putFile(String localPath, String remotePath) async {
    if (!_connected) {
      throw Exception('Not connected to WebDAV server');
    }

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        throw Exception('Local file does not exist: $localPath');
      }

      final normalizedPath = _normalizePath(remotePath);
      final bytes = await file.readAsBytes();

      final result = await _makeRequest('PUT', normalizedPath, body: bytes);

      return result.statusCode == 200 || result.statusCode == 201;
    } catch (e) {
      throw Exception('Failed to upload file: $e');
    }
  }

  @override
  Future<bool> deleteFile(String filePath) async {
    if (!_connected) {
      throw Exception('Not connected to WebDAV server');
    }

    try {
      final normalizedPath = _normalizePath(filePath);
      final result = await _makeRequest('DELETE', normalizedPath);

      return result.statusCode == 200 || result.statusCode == 204;
    } catch (e) {
      throw Exception('Failed to delete file: $e');
    }
  }

  @override
  Future<bool> createDirectory(String dirPath) async {
    if (!_connected) {
      throw Exception('Not connected to WebDAV server');
    }

    try {
      final normalizedPath = _normalizePath(dirPath);
      final result = await _makeRequest('MKCOL', normalizedPath);

      return result.statusCode == 200 || result.statusCode == 201;
    } catch (e) {
      throw Exception('Failed to create directory: $e');
    }
  }

  @override
  Future<bool> deleteDirectory(String dirPath) async {
    if (!_connected) {
      throw Exception('Not connected to WebDAV server');
    }

    try {
      final normalizedPath = _normalizePath(dirPath);
      final result = await _makeRequest('DELETE', normalizedPath);

      return result.statusCode == 200 || result.statusCode == 204;
    } catch (e) {
      throw Exception('Failed to delete directory: $e');
    }
  }

  @override
  Future<bool> rename(String oldPath, String newPath) async {
    if (!_connected) {
      throw Exception('Not connected to WebDAV server');
    }

    try {
      final normalizedOldPath = _normalizePath(oldPath);
      final normalizedNewPath = _normalizePath(newPath);

      final result = await _makeRequest('MOVE', normalizedOldPath,
          headers: {'Destination': normalizedNewPath});

      return result.statusCode == 200 || result.statusCode == 201;
    } catch (e) {
      throw Exception('Failed to rename: $e');
    }
  }

  @override
  Future<File> getFileWithProgress(
    String remotePath,
    String localPath,
    void Function(double progress)? onProgress,
  ) async {
    if (!_connected) {
      throw Exception('Not connected to WebDAV server');
    }

    try {
      final normalizedPath = _normalizePath(remotePath);
      final result = await _makeRequest('GET', normalizedPath);

      if (result.statusCode != 200) {
        throw Exception('Failed to download file: ${result.statusCode}');
      }

      final file = File(localPath);
      final bytes = result.bodyBytes;
      final totalBytes = bytes.length;

      // Write file in chunks to show progress
      final sink = file.openWrite();
      int writtenBytes = 0;
      const chunkSize = 8192;

      for (int i = 0; i < bytes.length; i += chunkSize) {
        final end =
            (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end);
        sink.add(chunk);
        writtenBytes += chunk.length;

        if (onProgress != null) {
          onProgress(writtenBytes / totalBytes);
        }

        // Small delay to allow UI updates
        await Future.delayed(const Duration(milliseconds: 10));
      }

      await sink.close();
      return file;
    } catch (e) {
      throw Exception('Failed to download file: $e');
    }
  }

  @override
  Future<bool> putFileWithProgress(
    String localPath,
    String remotePath,
    void Function(double progress)? onProgress,
  ) async {
    if (!_connected) {
      throw Exception('Not connected to WebDAV server');
    }

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        throw Exception('Local file does not exist: $localPath');
      }

      final normalizedPath = _normalizePath(remotePath);
      // final totalBytes = await file.length(); // Not used in current implementation

      // For now, we'll upload the entire file at once
      // In a real implementation, you might want to use chunked upload
      final bytes = await file.readAsBytes();

      if (onProgress != null) {
        onProgress(0.5); // Simulate progress
      }

      final result = await _makeRequest('PUT', normalizedPath, body: bytes);

      if (onProgress != null) {
        onProgress(1.0);
      }

      return result.statusCode == 200 || result.statusCode == 201;
    } catch (e) {
      throw Exception('Failed to upload file: $e');
    }
  }

  // Helper method
  String _normalizePath(String filePath) {
    debugPrint('WebDAVService: _normalizePath input: $filePath');

    // If it's already a full URL, extract just the path part
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      try {
        final uri = Uri.parse(filePath);
        filePath = uri.path;
        debugPrint('WebDAVService: Extracted path from URL: $filePath');
      } catch (e) {
        debugPrint('WebDAVService: Error parsing URL: $e');
      }
    }

    // Remove the protocol and server prefix if present
    String prefix =
        '$_webdavPrefix${_username.isNotEmpty ? "$_username@" : ""}$_host:$_port';
    if (filePath.startsWith(prefix)) {
      filePath = filePath.substring(prefix.length);
      debugPrint('WebDAVService: After removing prefix: $filePath');
    }

    // Replace backslashes with forward slashes
    filePath = filePath.replaceAll('\\', '/');

    // Ensure the path starts with '/' but avoid double slashes
    if (!filePath.startsWith('/')) {
      filePath = '/$filePath';
    }

    debugPrint('WebDAVService: _normalizePath output: $filePath');
    return filePath;
  }

  @override
  Stream<List<int>>? openFileStream(String remotePath) {
    if (!_connected) {
      debugPrint('WebDAVService: Cannot create stream - not connected');
      return null;
    }

    try {
      debugPrint('WebDAVService: Creating stream for: $remotePath');

      // Create a stream controller
      final controller = StreamController<List<int>>();

      // Start the download in the background
      _downloadAndStream(remotePath, controller);

      return controller.stream;
    } catch (e) {
      debugPrint('WebDAVService: Error creating stream: $e');
      return null;
    }
  }

  Future<void> _downloadAndStream(
      String remotePath, StreamController<List<int>> controller) async {
    try {
      final normalizedPath = _normalizePath(remotePath);
      debugPrint('WebDAVService: Streaming file: $normalizedPath');

      final result = await _makeRequest('GET', normalizedPath);

      if (result.statusCode != 200) {
        controller.addError('Failed to download file: ${result.statusCode}');
        await controller.close();
        return;
      }

      debugPrint(
          'WebDAVService: Stream created successfully: ${result.bodyBytes.length} bytes');

      // Send the data in chunks
      const chunkSize = 8192;
      final bytes = result.bodyBytes;

      for (int i = 0; i < bytes.length; i += chunkSize) {
        final end =
            (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end);
        controller.add(chunk);

        // Small delay to allow UI updates
        await Future.delayed(const Duration(milliseconds: 1));
      }

      await controller.close();
      debugPrint('WebDAVService: Stream completed');
    } catch (e) {
      debugPrint('WebDAVService: Stream error: $e');
      controller.addError('Failed to stream file: $e');
      await controller.close();
    }
  }

  @override
  Future<int?> getFileSize(String remotePath) async {
    try {
      final normalizedPath = _normalizePath(remotePath);
      final result = await _makeRequest('HEAD', normalizedPath);

      if (result.statusCode == 200) {
        final contentLength = result.headers['content-length']?.first;
        return contentLength != null ? int.tryParse(contentLength) : null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Uint8List?> getThumbnail(String remotePath, int size) async {
    // WebDAV doesn't support thumbnail generation, return null
    return null;
  }

  @override
  Future<Uint8List?> readFileData(String remotePath) async {
    if (!_connected) {
      throw Exception('Not connected to WebDAV server');
    }

    try {
      final normalizedPath = _normalizePath(remotePath);
      debugPrint('WebDAVService: Reading file data: $normalizedPath');

      final result = await _makeRequest('GET', normalizedPath);

      if (result.statusCode != 200) {
        throw Exception('Failed to read file: ${result.statusCode}');
      }

      debugPrint(
          'WebDAVService: File data read successfully: ${result.bodyBytes.length} bytes');
      return Uint8List.fromList(result.bodyBytes);
    } catch (e) {
      debugPrint('WebDAVService: Error reading file data: $e');
      throw Exception('Failed to read file data: $e');
    }
  }

  // Helper method to make HTTP requests
  Future<WebDAVResponse> _makeRequest(
    String method,
    String path, {
    Map<String, String>? headers,
    List<int>? body,
    String? depth,
  }) async {
    if (_httpClient == null) {
      throw Exception('HTTP client not initialized');
    }

    final url = Uri.parse('$_baseUrl$path');
    debugPrint('WebDAVService: Making $method request to $url');

    try {
      final request = await _httpClient!.openUrl(method, url);

      // Add authentication
      if (_username.isNotEmpty) {
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        debugPrint('WebDAVService: Added Basic authentication');
      }

      // Add WebDAV headers
      request.headers.set('User-Agent', 'CB File Hub WebDAV Client');

      if (depth != null) {
        request.headers.set('Depth', depth);
        debugPrint('WebDAVService: Added Depth header: $depth');
      }

      // Add custom headers
      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.set(key, value);
          debugPrint('WebDAVService: Added header $key: $value');
        });
      }

      // Add body if provided
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
        debugPrint('WebDAVService: Added body with ${body.length} bytes');
      }

      final response = await request.close();
      debugPrint('WebDAVService: Response status: ${response.statusCode}');

      // Read response body as bytes first
      final responseBytes = await response
          .toList()
          .then((chunks) => chunks.expand((chunk) => chunk).toList());

      debugPrint(
          'WebDAVService: Response body size: ${responseBytes.length} bytes');

      // Convert bytes to string for text responses
      final responseBody = utf8.decode(responseBytes, allowMalformed: true);

      return WebDAVResponse(
        statusCode: response.statusCode,
        body: responseBody,
        bodyBytes: responseBytes,
        headers: response.headers,
      );
    } catch (e) {
      debugPrint('WebDAVService: Request failed: $e');
      throw Exception('WebDAV request failed: $e');
    }
  }

  // Simple XML parser for WebDAV response with metadata parsing
  List<FileSystemEntity> _parseWebDAVResponse(
      String xmlResponse, String basePath) {
    final List<FileSystemEntity> entities = [];

    try {
      // Extract response blocks
      final responsePattern =
          RegExp(r'<D:response>(.*?)</D:response>', dotAll: true);
      final responseMatches = responsePattern.allMatches(xmlResponse);

      for (final responseMatch in responseMatches) {
        final responseBlock = responseMatch.group(1);
        if (responseBlock == null) continue;

        // Extract href from this response block
        final hrefMatch =
            RegExp(r'<D:href>(.*?)</D:href>').firstMatch(responseBlock);
        if (hrefMatch == null) continue;

        final href = hrefMatch.group(1);
        if (href == null || href.isEmpty) continue;

        // Decode URL-encoded path
        final decodedHref = Uri.decodeComponent(href);

        // Skip the base path itself
        if (decodedHref == basePath || decodedHref == '$basePath/') continue;

        // Extract the relative path
        Uri hrefUri;
        try {
          hrefUri = Uri.parse(decodedHref);
        } catch (_) {
          // Fallback to previous behaviour if parse fails
          hrefUri = Uri(path: decodedHref);
        }

        // Raw path from server (always starts with '/')
        String relativePath = hrefUri.path;

        // Determine configured base path from _baseUrl (e.g. '/webdav')
        final String configuredBasePath =
            Uri.parse(_baseUrl).path; // includes leading '/'

        // Remove configured base path (e.g. '/webdav') if present to avoid double usage later
        if (relativePath.startsWith(configuredBasePath)) {
          relativePath = relativePath.substring(configuredBasePath.length);
        }

        // Ensure leading '/'
        if (!relativePath.startsWith('/')) {
          relativePath = '/$relativePath';
        }

        // Skip empty paths
        if (relativePath.isEmpty) continue;

        // Check if it's a directory by looking for iscollection tag
        final isDirectory = responseBlock
                .contains('<D:iscollection>1</D:iscollection>') ||
            responseBlock
                .contains('<D:resourcetype><D:collection/></D:resourcetype>');

        // Extract metadata
        int size = -1;
        DateTime modified = DateTime.now();

        // Parse getcontentlength
        final sizeMatch =
            RegExp(r'<D:getcontentlength>(\d+)</D:getcontentlength>')
                .firstMatch(responseBlock);
        if (sizeMatch != null) {
          size = int.tryParse(sizeMatch.group(1) ?? '') ?? -1;
        }

        // Parse getlastmodified
        final modifiedMatch =
            RegExp(r'<D:getlastmodified>(.*?)</D:getlastmodified>')
                .firstMatch(responseBlock);
        if (modifiedMatch != null) {
          try {
            // Parse HTTP date format (e.g., "Wed, 21 Oct 2015 07:28:00 GMT")
            final dateStr = modifiedMatch.group(1) ?? '';
            modified = HttpDate.parse(dateStr);
          } catch (e) {
            debugPrint('WebDAVService: Error parsing date: $e');
            modified = DateTime.now();
          }
        }

        // Store metadata
        final meta = WebDavMeta(size, modified);
        _addMeta(relativePath, meta);

        // Extract just the name (last part of path)
        final name = relativePath.split('/').last;

        debugPrint(
            'WebDAVService: Found entity - Name: $name, Path: $relativePath, IsDirectory: $isDirectory, Size: $size, Modified: $modified');

        // Create temporary local files/directories for UI display
        final tempDir = Directory.systemTemp;
        final tempPath =
            '${tempDir.path}/webdav_${DateTime.now().millisecondsSinceEpoch}_$name';

        if (isDirectory) {
          // Create a temporary directory
          final tempDir = Directory(tempPath);
          entities.add(tempDir);
        } else {
          // Create a temporary file
          final tempFile = File(tempPath);
          entities.add(tempFile);

          // Store mapping from local temp path to remote path
          _addPathMapping(tempPath, relativePath);
        }
      }
    } catch (e) {
      debugPrint('WebDAVService: Error parsing XML response: $e');
    }

    return entities;
  }
}

// Helper classes for WebDAV implementation
class WebDAVResponse {
  final int statusCode;
  final String body;
  final List<int> bodyBytes;
  final HttpHeaders headers;

  WebDAVResponse({
    required this.statusCode,
    required this.body,
    required this.bodyBytes,
    required this.headers,
  });
}
