import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../local_ai/windows_process_reaper.dart';
import 'torrent_metainfo.dart';
import 'magnet_link.dart';

class Aria2RpcException implements Exception {
  final int code;
  final String message;
  const Aria2RpcException(this.code, this.message);
  @override
  String toString() => message;
}

/// Private loopback RPC server, authenticated by a fresh per-process token.
/// aria2 is stopped with its parent; task intent is persisted in SQLite and
/// `.aria2` control files preserve verified pieces across app restarts.
class Aria2Engine {
  Aria2Engine({this._enablePeerDiscovery = true});
  final bool _enablePeerDiscovery;

  /// Injects a transport for RPC contract unit tests without starting a process.
  Aria2Engine.forRpcTesting({
    required this._port,
    required this._secret,
    required this._httpClient,
  }) : _enablePeerDiscovery = true;
  Process? _process;
  RandomAccessFile? _ownershipLock;
  Future<void>? _releasingOwnership;
  Future<void>? _starting;
  HttpClient? _httpClient;
  HttpClient get _http =>
      _httpClient ??= (HttpClient()
        ..connectionTimeout = const Duration(seconds: 3));
  int? _port;
  String _secret = '';
  bool get running => _process != null;

  Future<void> start(String stateDirectory, {String? executable}) async {
    if (_starting != null) return _starting!;
    if (running) return;
    final future = _start(stateDirectory, executable);
    _starting = future;
    try {
      await future;
    } catch (_) {
      await _releaseOwnership();
      rethrow;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start(String stateDirectory, String? executable) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      throw UnsupportedError(
        'Torrent downloads currently require desktop aria2',
      );
    }
    await Directory(stateDirectory).create(recursive: true);
    final lock = await File(
      p.join(stateDirectory, 'engine.lock'),
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      _ownershipLock = lock;
    } on FileSystemException {
      await lock.close();
      throw StateError('Torrent downloads are managed by another app window');
    }
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _port = socket.port;
    await socket.close();
    _secret = base64Url.encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    var binary = executable;
    if (binary == null || binary.isEmpty) {
      final bundled = p.join(
        p.dirname(Platform.resolvedExecutable),
        'aria2',
        'aria2c.exe',
      );
      binary = Platform.isWindows && await File(bundled).exists()
          ? bundled
          : 'aria2c';
    }
    final child = await Process.start(binary, [
      '--no-conf=true',
      if (!_enablePeerDiscovery) ...[
        '--enable-dht=false',
        '--enable-dht6=false',
        '--enable-peer-exchange=false',
        '--bt-enable-lpd=false',
      ],
      '--enable-rpc=true',
      '--rpc-listen-all=false',
      '--rpc-listen-port=$_port',
      '--rpc-secret=$_secret',
      '--stop-with-process=$pid',
      '--enable-color=false',
      '--console-log-level=error',
      '--max-concurrent-downloads=3',
      '--seed-time=0',
      '--continue=true',
      '--auto-file-renaming=false',
      '--allow-overwrite=false',
      '--file-allocation=none',
      '--rpc-save-upload-metadata=false',
      '--dht-file-path=${p.join(stateDirectory, 'dht.dat')}',
      '--dht-file-path6=${p.join(stateDirectory, 'dht6.dat')}',
    ], workingDirectory: stateDirectory);
    _process = child;
    if (Platform.isWindows) {
      WindowsProcessReaper.instance.assignProcess(child.pid);
    }
    // Drain pipes so a noisy child never blocks on stdout/stderr.
    var diagnostics = '';
    void record(List<int> bytes) {
      diagnostics += utf8.decode(bytes, allowMalformed: true);
      if (diagnostics.length > 2048) {
        diagnostics = diagnostics.substring(diagnostics.length - 2048);
      }
    }

    child.stdout.listen(record);
    child.stderr.listen(record);
    unawaited(
      child.exitCode.then((_) {
        if (identical(_process, child)) {
          _process = null;
          unawaited(_releaseOwnership());
        }
      }),
    );
    Object? lastFailure;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      try {
        await call('getVersion');
        return;
      } catch (e) {
        lastFailure = e;
        if (_process == null) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    child.kill();
    await child.exitCode;
    _process = null;
    throw StateError(
      'aria2 could not start. Select a working aria2c executable in Torrent settings. '
      '${diagnostics.replaceAll(_secret, '[redacted]')} $lastFailure',
    );
  }

  Future<Object?> call(String method, [List<Object?> args = const []]) async {
    if (_port == null || !running) throw StateError('aria2 is not running');
    final request = await _http
        .postUrl(Uri.parse('http://127.0.0.1:$_port/jsonrpc'))
        .timeout(const Duration(seconds: 4));
    request.headers.contentType = ContentType.json;
    final requestBody = utf8.encode(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 'cb',
        'method': 'aria2.$method',
        'params': ['token:$_secret', ...args],
      }),
    );
    // aria2's RPC HTTP parser expects a sized body; chunked requests are
    // interpreted as malformed JSON (JSON-RPC -32700).
    request.contentLength = requestBody.length;
    request.add(requestBody);
    final response = await request.close().timeout(const Duration(seconds: 4));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 4));
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (data['error'] != null) {
      final error = data['error'] as Map<String, dynamic>;
      throw Aria2RpcException(error['code'] as int, error['message'] as String);
    }
    return data['result'];
  }

  Future<String> add(
    String torrentPath,
    String destination,
    String gid, {
    bool paused = false,
    String? expectedHash,
  }) async {
    final file = await File(torrentPath).open();
    late final List<int> bytes;
    try {
      bytes = await file.read(16 * 1024 * 1024 + 1);
    } finally {
      await file.close();
    }
    final info = TorrentMetainfo.parse(Uint8List.fromList(bytes));
    if (expectedHash != null && info.hash != expectedHash) {
      throw const FormatException('Torrent changed before download');
    }
    return await call('addTorrent', [
          base64Encode(bytes),
          <String>[],
          {
            'dir': destination,
            'gid': gid,
            'pause': paused.toString(),
            'seed-time': '0',
            'check-integrity': 'true',
          },
        ])
        as String;
  }

  Future<String> addMagnet(
    String uri,
    String destination,
    String gid, {
    bool paused = false,
  }) async {
    MagnetLink.parse(uri);
    return await call('addUri', [
          [uri],
          {
            'dir': destination,
            'gid': gid,
            'pause': paused.toString(),
            'seed-time': '0',
            'bt-metadata-only': 'false',
            'bt-save-metadata': 'true',
            'check-integrity': 'true',
          },
        ])
        as String;
  }

  Future<void> _releaseOwnership() async {
    if (_releasingOwnership != null) return _releasingOwnership!;
    final lock = _ownershipLock;
    _ownershipLock = null;
    if (lock != null) {
      final releasing = () async {
        try {
          await lock.unlock();
        } finally {
          await lock.close();
        }
      }();
      _releasingOwnership = releasing;
      try {
        await releasing;
      } finally {
        _releasingOwnership = null;
      }
    }
  }

  Future<void> dispose() async {
    if (running) {
      try {
        await call('shutdown');
      } catch (_) {
        _process?.kill();
      }
      final child = _process;
      if (child != null) {
        try {
          await child.exitCode.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          child.kill();
          await child.exitCode;
        }
      }
    }
    await _releaseOwnership();
    _httpClient?.close(force: true);
  }
}
