import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../ssh/ssh_profile_store.dart';
import 'network_service_base.dart';

class SFTPService extends NetworkServiceBase {
  SSHClient? _ssh;
  SftpClient? _sftp;
  String _basePath = '';
  @override
  String get serviceName => 'SFTP';
  @override
  String get serviceDescription => 'SSH File Transfer Protocol';
  @override
  get serviceIcon => PhosphorIconsLight.folderLock;
  @override
  bool isAvailable() => true;
  @override
  bool get isConnected => _ssh != null && !_ssh!.isClosed && _sftp != null;
  @override
  String get basePath => _basePath;
  SftpClient get client {
    if (!isConnected) throw StateError('SFTP connection closed.');
    return _sftp!;
  }

  String resolveRemotePath(String path) {
    if (path.startsWith('#network/')) {
      final parts = path.split('/');
      if (parts.length < 3 ||
          parts[1] != 'SFTP' ||
          Uri.decodeComponent(parts[2]) != Uri.parse(basePath).authority) {
        throw ArgumentError('Path belongs to another SFTP connection.');
      }
      return '/${parts.skip(3).join('/')}';
    }
    return path.isEmpty ? '/' : path;
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
      await disconnect();
      final profile = SshProfile(
        id: '',
        name: host,
        host: host,
        username: username,
        password: password ?? '',
        port: port ?? 22,
        keyId: additionalOptions?['keyId'],
        proxyId: additionalOptions?['proxyId'],
      );
      _ssh = await SshConnector().connect(
        profile,
        trustPrompt: additionalOptions?['trustPrompt'] as SshTrustPrompt?,
      );
      _sftp = await _ssh!.sftp();
      _basePath = Uri(
        scheme: 'sftp',
        host: host,
        port: port ?? 22,
        userInfo: username,
      ).toString();
      return ConnectionResult(success: true, connectedPath: _basePath);
    } catch (e) {
      await disconnect();
      return ConnectionResult(success: false, errorMessage: e.toString());
    }
  }

  @override
  Future<void> disconnect() async {
    final ssh = _ssh;
    _ssh = null;
    try {
      await _sftp?.close();
    } finally {
      _sftp = null;
      ssh?.close();
    }
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    final remote = resolveRemotePath(path);
    final entries = await client.listdir(remote);
    final root =
        '#network/SFTP/${Uri.encodeComponent(Uri.parse(basePath).authority)}';
    final result = <FileSystemEntity>[];
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      final child = p.posix.join(remote, entry.filename);
      final virtual =
          '$root/${child.split('/').where((e) => e.isNotEmpty).join('/')}';
      var attrs = entry.attr;
      if (attrs.isSymbolicLink) {
        try {
          attrs = await client.stat(child);
        } catch (_) {
          continue;
        }
      }
      result.add(attrs.isDirectory ? Directory(virtual) : File(virtual));
    }
    return result;
  }

  @override
  Future<File> getFile(String remotePath, String localPath) =>
      getFileWithProgress(remotePath, localPath, null);
  @override
  Future<File> getFileWithProgress(
    String path,
    String localPath,
    void Function(double)? onProgress,
  ) async {
    final file = File(localPath);
    final size = await getFileSize(path) ?? 0;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final bytes in openFileStream(path)) {
        sink.add(bytes);
        received += bytes.length;
        if (size > 0) onProgress?.call(received / size);
      }
      await sink.flush();
      onProgress?.call(1);
      return file;
    } finally {
      await sink.close();
    }
  }

  @override
  Future<bool> putFile(String localPath, String remotePath) =>
      putFileWithProgress(localPath, remotePath, null);
  @override
  Future<bool> putFileWithProgress(
    String localPath,
    String path,
    void Function(double)? onProgress,
  ) async {
    final local = File(localPath);
    final size = await local.length();
    final file = await client.open(
      resolveRemotePath(path),
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      await file
          .write(
            local.openRead().map(Uint8List.fromList),
            onProgress: (bytes) {
              if (size > 0) onProgress?.call(bytes / size);
            },
          )
          .done;
      onProgress?.call(1);
      return true;
    } finally {
      await file.close();
    }
  }

  @override
  Stream<List<int>> openFileStream(String remotePath) async* {
    final file = await client.open(resolveRemotePath(remotePath));
    try {
      yield* file.read();
    } finally {
      await file.close();
    }
  }

  @override
  Future<int?> getFileSize(String remotePath) async =>
      (await client.stat(resolveRemotePath(remotePath))).size;
  @override
  Future<Uint8List?> readFileData(String remotePath) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in openFileStream(remotePath)) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  @override
  Future<bool> deleteFile(String path) async {
    await client.remove(resolveRemotePath(path));
    return true;
  }

  @override
  Future<bool> deleteDirectory(String path) async {
    await client.rmdir(resolveRemotePath(path));
    return true;
  }

  @override
  Future<bool> createDirectory(String path) async {
    await client.mkdir(resolveRemotePath(path));
    return true;
  }

  @override
  Future<bool> rename(String oldPath, String newPath) async {
    await client.rename(resolveRemotePath(oldPath), resolveRemotePath(newPath));
    return true;
  }
}
