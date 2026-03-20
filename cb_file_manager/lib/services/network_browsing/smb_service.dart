import 'dart:ffi';
import 'dart:io';
import 'dart:async';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import 'network_service_base.dart';
import 'i_smb_service.dart';
import 'smb_native_bindings.dart';

/// Custom stream class for SMB file streaming
class SMBFileStream extends Stream<List<int>> {
  final SMBNativeBindings _bindings;
  final int _handle;
  final int _chunkSize;
  bool _closed = false;

  SMBFileStream(this._bindings, this._handle,
      [this._chunkSize = 8192 * 1024]); // 8MB chunks for video streaming

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    late StreamController<List<int>> controller;

    controller = StreamController<List<int>>(
      onListen: () {
        _readChunks(controller);
      },
      onCancel: () {
        _close();
      },
    );

    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Future<void> _readChunks(StreamController<List<int>> controller) async {
    try {
      while (!_closed) {
        final result = _bindings.readFileChunk(_handle, _chunkSize);
        if (result.bytesRead > 0) {
          // Copy the bytes into Dart-managed memory BEFORE freeing the native buffer
          final chunkData =
              Uint8List.fromList(result.data.asTypedList(result.bytesRead));
          _bindings.freeReadResultData(result.data);

          if (!controller.isClosed) {
            controller.add(chunkData);
          }
        } else {
          if (result.bytesRead < 0) {
            // Error
            if (!controller.isClosed) {
              controller.addError(Exception("Error reading file chunk"));
            }
          }
          // End of file
          break;
        }
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    } finally {
      _close();
      if (!controller.isClosed) {
        controller.close();
      }
    }
  }

  void _close() {
    if (!_closed) {
      _closed = true;
      _bindings.closeFile(_handle);
    }
  }
}

/// Service for SMB (Server Message Block) network file access using native Windows APIs.
class SMBService implements ISmbService {
  static const String _smbScheme = 'smb';

  // Native bindings
  late final SMBNativeBindings _bindings;

  // Connection state
  String _connectedHost = '';
  String _connectedShare = '';
  bool _isConnected = false;

  // Thumbnail cache to avoid regenerating
  static final Map<String, Uint8List> _thumbnailCache = {};

  SMBService() {
    if (Platform.isWindows) {
      _bindings = SMBNativeBindings();
    }
  }

  @override
  String get serviceName => 'SMB';

  @override
  String get serviceDescription => 'Windows Shared Folders (SMB via Win32)';

  @override
  IconData get serviceIcon => PhosphorIconsLight.folder;

  @override
  bool isAvailable() => Platform.isWindows;

  @override
  bool get isConnected => _isConnected;

  @override
  String get basePath => '$_smbScheme://$_connectedHost/$_connectedShare';

  /// Converts an application-specific tabPath to a native UNC path.
  /// e.g., "#network/smb/server/share/folder/" -> "\\server\share\folder\"
  String _getUncPathFromTabPath(String tabPath) {
    // Ensure we treat the scheme part case-insensitively so that both
    // "#network/smb/" and "#network/SMB/" are accepted.
    final lowerPath = tabPath.toLowerCase();
    if (!lowerPath.startsWith('#network/$_smbScheme/')) {
      debugPrint('Invalid tab path format: $tabPath');
      return '\\\\';
    }

    // Remove the leading "#network/" so we can reliably split the rest of the
    // parts regardless of original case.
    final pathWithoutPrefix = tabPath.substring('#network/'.length);

    final parts =
        pathWithoutPrefix.split('/').where((p) => p.isNotEmpty).toList();
    // parts = ["smb", "host", "share", "folder"]
    if (parts.length < 2) {
      debugPrint('Tab path has too few parts: $tabPath');
      return '\\\\';
    }

    // parts[0] == scheme (smb), so host starts at index 1
    final host = Uri.decodeComponent(parts[1]);

    // If no share specified, return just the server UNC path
    if (parts.length == 2) {
      debugPrint('Converting to server root UNC path: \\\\$host');
      return '\\\\$host';
    }

    // Extract share and remaining folders (if any)
    final share = Uri.decodeComponent(parts[2]);

    // Xử lý các thư mục con một cách cẩn thận
    List<String> folders = [];
    if (parts.length > 3) {
      try {
        folders = parts.sublist(3).map((part) {
          try {
            return Uri.decodeComponent(part);
          } catch (e) {
            // Nếu decode thất bại, sử dụng giá trị gốc
            debugPrint('Error decoding path component: $part, error: $e');
            return part;
          }
        }).toList();
      } catch (e) {
        debugPrint('Error processing path components: $e');
      }
    }

    // Build the UNC path
    final uncPath =
        '\\\\$host\\$share${folders.isNotEmpty ? '\\${folders.join('\\')}' : ''}';
    debugPrint('Converting tab path to UNC path: $tabPath -> $uncPath');

    return uncPath;
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
          errorMessage: 'SMB Native is only available on Windows.');
    }
    await disconnect();

    final serverHost = host.trim().split('/').first.replaceAll('\\', '');
    if (serverHost.isEmpty) {
      return ConnectionResult(
          success: false, errorMessage: 'Server address cannot be empty.');
    }

    final uncPath = '\\\\$serverHost';
    final uncPathPtr = uncPath.toNativeUtf16();
    final usernamePtr = username.toNativeUtf16();
    final passwordPtr = password != null && password.isNotEmpty
        ? password.toNativeUtf16()
        : nullptr;

    try {
      final result = _bindings.connect(uncPathPtr, usernamePtr, passwordPtr);
      if (result == 0) {
        // NO_ERROR
        _isConnected = true;
        _connectedHost = serverHost;
        // At this point we are connected to the server, but not a specific share.
        // The share will be determined when listing directories.
        return ConnectionResult(
            success: true, connectedPath: '$_smbScheme://$_connectedHost');
      } else {
        return ConnectionResult(
            success: false,
            errorMessage: 'SMB Connection failed with error code: $result');
      }
    } finally {
      malloc.free(uncPathPtr);
      malloc.free(usernamePtr);
      if (passwordPtr != nullptr) malloc.free(passwordPtr);
    }
  }

  @override
  Future<void> disconnect() async {
    if (!isConnected) return;
    final uncPath = '\\\\$_connectedHost';
    final uncPathPtr = uncPath.toNativeUtf16();
    try {
      _bindings.disconnect(uncPathPtr);
    } finally {
      malloc.free(uncPathPtr);
      _isConnected = false;
      _connectedHost = '';
      _connectedShare = '';
    }
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String tabPath) async {
    if (!isConnected) throw Exception('Not connected to SMB server');

    final stopwatch = Stopwatch()..start();
    debugPrint('SMB listDirectory starting for: $tabPath');

    final uncPath = _getUncPathFromTabPath(tabPath);

    // Check if we're listing the server root (to show shares)
    final pathParts = uncPath.split('\\').where((p) => p.isNotEmpty).toList();
    if (pathParts.length <= 1) {
      // We're at the server root, need to list shares
      debugPrint('Listing shares for server root: $uncPath');
      return _listShares(uncPath, tabPath);
    }

    // If we're accessing a share, update the _connectedShare variable
    if (pathParts.length >= 2) {
      final shareName = pathParts[1];
      if (_connectedShare != shareName) {
        debugPrint('Setting connected share to: $shareName');
        _connectedShare = shareName;
      }
    }

    // Normal directory listing
    debugPrint('Calling native listDirectory for UNC path: $uncPath');
    final uncPathPtr = uncPath.toNativeUtf16();
    final Pointer<NativeFileList> nativeListPtr =
        _bindings.listDirectory(uncPathPtr);
    malloc.free(uncPathPtr);

    if (nativeListPtr == nullptr) {
      // Could be an error or an empty directory. Assume empty for now.
      debugPrint('ListDirectory returned null for path: $uncPath');
      stopwatch.stop();
      debugPrint(
          'SMB listDirectory completed in ${stopwatch.elapsedMilliseconds}ms (empty)');
      return [];
    }

    try {
      final nativeList = nativeListPtr.ref;
      final List<FileSystemEntity> entities = [];

      debugPrint('Found ${nativeList.count} items in directory $uncPath');

      for (int i = 0; i < nativeList.count; i++) {
        final fileInfo = nativeList.files[i];
        final itemName = fileInfo.name.toDartString();

        String entityTabPath = p.join(tabPath, itemName).replaceAll('\\', '/');

        if (fileInfo.isDirectory) {
          if (!entityTabPath.endsWith('/')) {
            entityTabPath += '/';
          }
          entities.add(Directory(entityTabPath));
        } else {
          entities.add(File(entityTabPath));
        }
      }

      stopwatch.stop();
      debugPrint(
          'SMB listDirectory completed in ${stopwatch.elapsedMilliseconds}ms (${entities.length} items)');
      return entities;
    } finally {
      _bindings.freeFileList(nativeListPtr);
    }
  }

  // Helper method to list shares on a server
  Future<List<FileSystemEntity>> _listShares(
      String uncPath, String tabPath) async {
    // Extract server name from UNC path
    final server = uncPath.replaceAll('\\\\', '');
    final List<FileSystemEntity> shares = [];

    // Use the native function to enumerate shares
    final serverPtr = server.toNativeUtf16();
    final Pointer<NativeShareList> nativeListPtr =
        _bindings.enumerateShares(serverPtr);
    malloc.free(serverPtr);

    if (nativeListPtr == nullptr) {
      debugPrint('Failed to enumerate shares on server: $server');
      // Fall back to common shares
      return _getCommonShares(server);
    }

    try {
      final nativeList = nativeListPtr.ref;

      for (int i = 0; i < nativeList.count; i++) {
        final shareInfo = nativeList.shares[i];
        final shareName = shareInfo.name.toDartString();

        // Create a path for this share in the format #network/SMB/server/share/
        final shareTabPath =
            "#network/${_smbScheme.toUpperCase()}/${Uri.encodeComponent(server)}/${Uri.encodeComponent(shareName)}/";
        shares.add(Directory(shareTabPath));
      }

      return shares;
    } finally {
      _bindings.freeShareList(nativeListPtr);
    }
  }

  // Fallback method to get common shares if native enumeration fails
  List<FileSystemEntity> _getCommonShares(String server) {
    final commonShares = [
      'Users',
      'Public',
      'Documents',
      'Pictures',
      'Music',
      'Videos',
      'Downloads'
    ];
    final List<FileSystemEntity> shares = [];

    // Add common shares
    for (final shareName in commonShares) {
      // Create a path for this share in the format #network/SMB/server/share/
      final shareTabPath =
          "#network/${_smbScheme.toUpperCase()}/${Uri.encodeComponent(server)}/${Uri.encodeComponent(shareName)}/";
      shares.add(Directory(shareTabPath));
    }

    return shares;
  }

  @override
  Future<File> getFile(String remoteTabPath, String localPath) async {
    // This is a simplified version. getFileWithProgress has the full streaming implementation.
    final sink = File(localPath).openWrite();
    final uncPath = _getUncPathFromTabPath(remoteTabPath);
    final uncPathPtr = uncPath.toNativeUtf16();

    final handle = _bindings.openFileForReading(uncPathPtr);
    malloc.free(uncPathPtr);

    if (handle == 0 || handle == -1) {
      // INVALID_HANDLE_VALUE is -1 but 0 can also indicate error
      await sink.close();
      throw Exception('Failed to open remote file for reading.');
    }

    try {
      while (true) {
        final result = _bindings.readFileChunk(
            handle, 8192 * 1024); // 8MB chunks for video streaming performance
        if (result.bytesRead > 0) {
          // Copy the bytes into Dart-managed memory BEFORE freeing the native buffer
          final chunkData =
              Uint8List.fromList(result.data.asTypedList(result.bytesRead));
          _bindings.freeReadResultData(result.data);

          sink.add(chunkData);
        } else {
          if (result.bytesRead < 0) {
            // Error
            throw Exception("Error reading file chunk");
          }
          // End of file
          break;
        }
      }
    } finally {
      _bindings.closeFile(handle);
      await sink.close();
    }
    return File(localPath);
  }

  @override
  Future<bool> putFile(String localPath, String remoteTabPath) async {
    // This is a simplified version. putFileWithProgress has the full streaming implementation.
    final localFile = File(localPath);
    final remoteUncPath = _getUncPathFromTabPath(remoteTabPath);
    final remoteUncPathPtr = remoteUncPath.toNativeUtf16();

    final handle = _bindings.createFileForWriting(remoteUncPathPtr);
    malloc.free(remoteUncPathPtr);

    if (handle == 0 || handle == -1) {
      throw Exception('Failed to create remote file for writing.');
    }

    try {
      final stream = localFile.openRead();
      await for (final chunk in stream) {
        final chunkPtr = calloc<Uint8>(chunk.length);
        chunkPtr.asTypedList(chunk.length).setAll(0, chunk);
        final success =
            _bindings.writeFileChunk(handle, chunkPtr, chunk.length);
        calloc.free(chunkPtr);
        if (!success) {
          _bindings.closeFile(handle); // Close file on error
          throw Exception("Failed to write chunk to remote file.");
        }
      }
    } finally {
      _bindings.closeFile(handle);
    }
    return true;
  }

  @override
  Future<bool> deleteFile(String tabPath) {
    return delete(tabPath);
  }

  @override
  Future<bool> createDirectory(String tabPath) async {
    if (!isConnected) throw Exception('Not connected.');

    // remove trailing slash
    String cleanTabPath = tabPath.endsWith('/')
        ? tabPath.substring(0, tabPath.length - 1)
        : tabPath;
    final uncPath = _getUncPathFromTabPath(cleanTabPath);
    final uncPathPtr = uncPath.toNativeUtf16();
    try {
      return _bindings.createDir(uncPathPtr);
    } finally {
      malloc.free(uncPathPtr);
    }
  }

  Future<bool> delete(String tabPath, {bool recursive = false}) async {
    if (!isConnected) throw Exception('Not connected.');
    // Note: Native RemoveDirectory requires the directory to be empty.
    // A true recursive delete would require listing and deleting contents first.
    if (recursive) {
      debugPrint(
          "Warning: Recursive delete on native SMB is not implemented. Directory must be empty.");
    }
    final uncPath = _getUncPathFromTabPath(tabPath);
    final uncPathPtr = uncPath.toNativeUtf16();
    try {
      return _bindings.deleteFileOrDir(uncPathPtr);
    } finally {
      malloc.free(uncPathPtr);
    }
  }

  @override
  Future<bool> rename(String oldTabPath, String newTabPath) async {
    if (!isConnected) throw Exception('Not connected.');
    final oldUncPath = _getUncPathFromTabPath(oldTabPath);
    final newUncPath = _getUncPathFromTabPath(newTabPath);

    final oldPtr = oldUncPath.toNativeUtf16();
    final newPtr = newUncPath.toNativeUtf16();

    try {
      return _bindings.rename(oldPtr, newPtr);
    } finally {
      malloc.free(oldPtr);
      malloc.free(newPtr);
    }
  }

  @override
  Stream<List<int>>? openFileStream(String tabPath) {
    if (!isConnected) return null;

    final uncPath = _getUncPathFromTabPath(tabPath);
    final uncPathPtr = uncPath.toNativeUtf16();
    final handle = _bindings.openFileForReading(uncPathPtr);
    malloc.free(uncPathPtr);

    if (handle == 0 || handle == -1) {
      debugPrint('Failed to open remote file for streaming: $tabPath');
      return null;
    }

    return SMBFileStream(_bindings, handle);
  }

  @override
  Future<bool> deleteDirectory(String tabPath, {bool recursive = false}) {
    return delete(tabPath, recursive: recursive);
  }

  @override
  Future<File> getFileWithProgress(String remotePath, String localPath,
      void Function(double progress)? onProgress) async {
    final sink = File(localPath).openWrite();
    final uncPath = _getUncPathFromTabPath(remotePath);
    final uncPathPtr = uncPath.toNativeUtf16();

    final handle = _bindings.openFileForReading(uncPathPtr);
    malloc.free(uncPathPtr);

    if (handle == 0 || handle == -1) {
      await sink.close();
      throw Exception('Failed to open remote file for reading.');
    }

    try {
      // We can't easily get total size for progress, so we'll just stream.
      // A proper implementation would first query file size.
      onProgress?.call(0.0);
      await getFile(remotePath, localPath); // reuse non-progress for now
      onProgress?.call(1.0);
    } finally {
      _bindings.closeFile(handle);
      await sink.close();
    }
    return File(localPath);
  }

  @override
  Future<bool> putFileWithProgress(String localPath, String remotePath,
      void Function(double progress)? onProgress) async {
    final localFile = File(localPath);
    final totalSize = await localFile.length();
    var bytesWritten = 0;

    final remoteUncPath = _getUncPathFromTabPath(remotePath);
    final remoteUncPathPtr = remoteUncPath.toNativeUtf16();

    final handle = _bindings.createFileForWriting(remoteUncPathPtr);
    malloc.free(remoteUncPathPtr);

    if (handle == 0 || handle == -1) {
      throw Exception('Failed to create remote file for writing.');
    }

    try {
      final stream = localFile.openRead();
      onProgress?.call(0.0);

      await for (final chunk in stream) {
        final chunkPtr = calloc<Uint8>(chunk.length);
        chunkPtr.asTypedList(chunk.length).setAll(0, chunk);

        final success =
            _bindings.writeFileChunk(handle, chunkPtr, chunk.length);
        calloc.free(chunkPtr);

        if (!success) {
          _bindings.closeFile(handle); // Close file on error
          throw Exception("Failed to write chunk to remote file.");
        }

        bytesWritten += chunk.length;
        onProgress?.call(bytesWritten / totalSize);
      }
      onProgress?.call(1.0);
    } finally {
      _bindings.closeFile(handle);
    }
    return true;
  }

  /// Fetches a thumbnail for a given file path.
  ///
  /// Returns a [Uint8List] containing the PNG data of the thumbnail,
  /// or `null` if a thumbnail could not be generated.
  @override
  Future<Uint8List?> getThumbnail(String tabPath, int size) async {
    if (!isAvailable() || !isConnected) return null;

    // Check if this is an image file first
    final ext = p.extension(tabPath).toLowerCase();
    final supportedExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.tiff',
      '.tif'
    ];
    if (!supportedExtensions.contains(ext)) {
      return null;
    }

    // Check cache first
    final cacheKey = '$tabPath:$size';
    if (_thumbnailCache.containsKey(cacheKey)) {
      return _thumbnailCache[cacheKey];
    }

    // Kiểm tra và dọn dẹp bộ nhớ định kỳ
    _thumbnailCount++;
    if (_thumbnailCount > _resetThresholdCount) {
      _cleanupResources();
    }

    // Concurrency control to prevent overwhelming the system
    if (_concurrentOperations.length >= _maxConcurrentOperations) {
      return null;
    }

    final completer = Completer<void>();
    _concurrentOperations[tabPath] = completer;

    try {
      final uncPath = _getUncPathFromTabPath(tabPath);

      // First try native thumbnail
      final nativeThumbnail = await _getNativeThumbnail(uncPath, size)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);

      if (nativeThumbnail != null) {
        _thumbnailCache[cacheKey] = nativeThumbnail;
        return nativeThumbnail;
      }

      // Fallback: try downloading and processing the image
      final fallbackThumbnail = await _getFallbackThumbnail(tabPath, size)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);

      if (fallbackThumbnail != null) {
        _thumbnailCache[cacheKey] = fallbackThumbnail;
        return fallbackThumbnail;
      }

      return null;
    } catch (e) {
      return null;
    } finally {
      _concurrentOperations.remove(tabPath);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /// Dọn dẹp tài nguyên định kỳ
  void _cleanupResources() {
    _thumbnailCount = 0;

    // Dọn dẹp bộ nhớ cache nếu quá lớn
    if (_thumbnailCache.length > 100) {
      final keysToRemove = _thumbnailCache.keys.take(50).toList();
      for (final key in keysToRemove) {
        _thumbnailCache.remove(key);
      }
    }

    // Dọn dẹp các hoạt động đồng thời bị treo
    final keysToRemove = <String>[];
    for (final entry in _concurrentOperations.entries) {
      if (!entry.value.isCompleted) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _concurrentOperations.remove(key);
    }
  }

  @override
  Future<Uint8List?> readFileData(String remotePath) async {
    // SMB doesn't support direct file data reading, return null
    return null;
  }

  /// Try to get thumbnail using native Windows API
  Future<Uint8List?> _getNativeThumbnail(String uncPath, int size) async {
    final uncPathPtr = uncPath.toNativeUtf16();

    try {
      // Call native GetThumbnail function
      final result = _bindings.getThumbnail(uncPathPtr, size);

      if (result.data != nullptr && result.size > 0) {
        // Copy thumbnail data to Dart memory
        final thumbnailData =
            Uint8List.fromList(result.data.asTypedList(result.size));

        // Free native memory
        _bindings.freeThumbnailResult(result);

        return thumbnailData;
      }

      return null;
    } catch (e) {
      return null;
    } finally {
      malloc.free(uncPathPtr);
    }
  }

  /// Fallback method: download image and create thumbnail
  Future<Uint8List?> _getFallbackThumbnail(String tabPath, int size) async {
    try {
      // Use streaming to get image data
      final stream = openFileStream(tabPath);
      if (stream == null) {
        return null;
      }

      // Collect image data (limit to 3MB for thumbnails)
      final chunks = <int>[];
      int totalBytes = 0;
      const maxSize = 3 * 1024 * 1024; // 3MB

      try {
        await for (final chunk in stream) {
          totalBytes += chunk.length;
          if (totalBytes > maxSize) {
            return null;
          }
          chunks.addAll(chunk);
        }
      } catch (e) {
        return null;
      }

      if (chunks.isEmpty) {
        return null;
      }

      // Decode and resize
      final imageBytes = Uint8List.fromList(chunks);

      final image = img.decodeImage(imageBytes);
      if (image == null) {
        return null;
      }

      // Tạo thumbnail với chất lượng cao hơn
      final thumbnail = img.copyResize(
        image,
        width: size,
        height: size,
        interpolation: img.Interpolation.cubic,
      );

      // Tăng chất lượng của ảnh PNG
      return Uint8List.fromList(img.encodePng(thumbnail, level: 6));
    } catch (e) {
      return null;
    }
  }

  /// Get file size without downloading the file
  @override
  Future<int?> getFileSize(String tabPath) async {
    if (!isConnected) return null;

    final uncPath = _getUncPathFromTabPath(tabPath);
    final uncPathPtr = uncPath.toNativeUtf16();

    try {
      // We can use the existing ListDirectory but filter for just this file
      // For now, return null and let the caller handle it
      return null;
    } finally {
      malloc.free(uncPathPtr);
    }
  }

  // Semaphore to limit concurrent operations
  static final _concurrentOperations = <String, Completer<void>>{};
  static const _maxConcurrentOperations =
      5; // Tăng từ 3 lên 5 để cải thiện hiệu suất

  // Thêm biến đếm số lượng thumbnail đã tạo
  static int _thumbnailCount = 0;
  static const int _resetThresholdCount =
      40; // Ngưỡng để reset bộ đếm và dọn dẹp

  @override
  Future<String?> getSmbDirectLink(String tabPath) async {
    if (!isConnected) return null;

    try {
      // Convert tab path to UNC path
      final uncPath = _getUncPathFromTabPath(tabPath);

      // Convert UNC path to SMB URL format
      // Example: \\server\share\file.mp4 -> smb://server/share/file.mp4
      final parts = uncPath.split('\\').where((p) => p.isNotEmpty).toList();
      if (parts.length < 2) return null;

      final server = parts[0];
      final pathParts = parts.sublist(1);
      final smbUrl = 'smb://$server/${pathParts.join('/')}';

      debugPrint('Generated SMB direct link: $smbUrl');
      return smbUrl;
    } catch (e) {
      debugPrint('Error generating SMB direct link: $e');
      return null;
    }
  }
}
