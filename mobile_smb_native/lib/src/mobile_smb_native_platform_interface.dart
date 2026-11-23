import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'smb_file.dart';
import 'smb_connection_config.dart';
import 'mobile_smb_native_method_channel.dart';

/// The interface that implementations of mobile_smb_native must implement.
abstract class MobileSmbNativePlatform extends PlatformInterface {
  /// Constructs a MobileSmbNativePlatform.
  MobileSmbNativePlatform() : super(token: _token);

  static final Object _token = Object();

  static MobileSmbNativePlatform _instance = MethodChannelMobileSmbNative();

  /// The default instance of [MobileSmbNativePlatform] to use.
  ///
  /// Defaults to [MethodChannelMobileSmbNative].
  static MobileSmbNativePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MobileSmbNativePlatform] when
  /// they register themselves.
  static set instance(MobileSmbNativePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Connect to an SMB server
  Future<bool> connect(SmbConnectionConfig config) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnect from the current SMB server
  Future<bool> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// List available shares on the connected server
  Future<List<String>> listShares() {
    throw UnimplementedError('listShares() has not been implemented.');
  }

  /// List files and directories in the specified path
  Future<List<SmbFile>> listDirectory(String path) {
    throw UnimplementedError('listDirectory() has not been implemented.');
  }

  /// Read file content as bytes
  Future<List<int>> readFile(String path) {
    throw UnimplementedError('readFile() has not been implemented.');
  }

  /// Write bytes to a file
  Future<bool> writeFile(String path, List<int> data) {
    throw UnimplementedError('writeFile() has not been implemented.');
  }

  /// Delete a file or directory
  Future<bool> delete(String path) {
    throw UnimplementedError('delete() has not been implemented.');
  }

  /// Create a directory
  Future<bool> createDirectory(String path) {
    throw UnimplementedError('createDirectory() has not been implemented.');
  }

  /// Check if connected to an SMB server
  Future<bool> isConnected() {
    throw UnimplementedError('isConnected() has not been implemented.');
  }

  /// Get file/directory information
  Future<SmbFile?> getFileInfo(String path) {
    throw UnimplementedError('getFileInfo() has not been implemented.');
  }

  /// Opens an independent, forward-only playback reader where supported.
  /// A null result means the caller should use the existing stream API.
  Future<SmbPlaybackReader?> openPlaybackReader(
    SmbConnectionConfig config,
    String path,
  ) async => null;

  /// Open file for streaming read
  Stream<List<int>>? openFileStream(String path) {
    throw UnimplementedError('openFileStream() has not been implemented.');
  }

  /// Get SMB version information
  Future<String> getSmbVersion() {
    throw UnimplementedError('getSmbVersion() has not been implemented.');
  }

  /// Get connection information including SMB version
  Future<String> getConnectionInfo() {
    throw UnimplementedError('getConnectionInfo() has not been implemented.');
  }

  /// Get native SMB context pointer for media streaming
  Future<int?> getNativeContext() {
    throw UnimplementedError('getNativeContext() has not been implemented.');
  }

  /// Open file for optimized video streaming
  Stream<List<int>>? openFileStreamOptimized(String path,
      {int chunkSize = 1024 * 1024}) {
    throw UnimplementedError(
        'openFileStreamOptimized() has not been implemented.');
  }

  /// Open file for optimized video streaming with seek support
  Stream<List<int>>? seekFileStreamOptimized(String path, int offset,
      {int chunkSize = 1024 * 1024}) {
    throw UnimplementedError(
        'seekFileStreamOptimized() has not been implemented.');
  }
}

abstract interface class SmbPlaybackReader {
  int get fileSize;
  Future<Uint8List> read(int offset, int length);
  Future<void> close();
}
