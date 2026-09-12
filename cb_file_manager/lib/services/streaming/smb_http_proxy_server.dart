import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../services/network_browsing/smb_chunk_reader.dart';
import 'package:mobile_smb_native/mobile_smb_native.dart';

/// Lightweight HTTP proxy that exposes an SMB file as an HTTP stream with Range support.
/// Used by media_kit for authenticated SMB and mobile playback.
class SmbHttpProxyServer {
  static SmbHttpProxyServer? _instance;
  static SmbHttpProxyServer get instance =>
      _instance ??= SmbHttpProxyServer._();

  SmbHttpProxyServer._();

  HttpServer? _server;
  int? _port;
  Future<void>? _starting;
  final _sources = <String, String>{};

  // For simple per-request handling we do not cache connections long-term.
  // The player will reconnect with Range requests as needed.

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    if (_starting != null) return _starting;
    _starting = _start();
    try {
      await _starting;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start() async {
    final handler = const Pipeline().addHandler(_handle);
    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    _server!.autoCompress = false;
    _port = _server!.port;
  }

  /// Returns a URL that the player can consume for the given [smbUrl].
  Future<Uri> urlFor(String smbUrl) async {
    await _ensureStarted();
    final encoded = const Uuid().v4();
    _sources[encoded] = smbUrl;
    return Uri.parse('http://127.0.0.1:$_port/stream?u=$encoded');
  }

  void release(Uri url) => _sources.remove(url.queryParameters['u']);

  Future<Response> _handle(Request req) async {
    try {
      if (req.url.path != 'stream') {
        return Response.notFound('Not Found');
      }
      final u =
          req.requestedUri.queryParameters['u'] ?? req.url.queryParameters['u'];
      if (u == null || u.isEmpty) {
        return Response(400, body: 'Missing parameter u');
      }
      final smbUrl = _sources[u];
      if (smbUrl == null) return Response.notFound('Stream expired');

      final reader = SmbChunkReader();
      final info = _parseSmbUrl(smbUrl);
      if (info == null) {
        return Response(400, body: 'Invalid SMB URL');
      }
      final filePath = _buildClientPath(info);

      final ok = await reader.initialize(
        SmbConnectionConfig(
          host: info.host,
          port: info.port,
          domain: info.domain,
          username: info.username ?? '',
          password: info.password ?? '',
          shareName: info.share,
          timeoutMs: 60000,
        ),
      );
      if (!ok) {
        await reader.dispose();
        return Response(502, body: 'Failed to connect SMB');
      }

      // SmbChunkReader expects a path relative to the SMB base share.
      final fileOk = await reader.setFile(filePath);
      if (!fileOk) {
        await reader.dispose();
        return Response(404, body: 'File not found');
      }

      final fileSize = reader.fileSize;
      if (fileSize == null) {
        await reader.dispose();
        return Response.notFound('File size unavailable');
      }
      final range = req.headers['range'];
      var start = 0;
      var end = fileSize - 1;
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        var valid = match != null && fileSize > 0;
        if (valid) {
          final first = match.group(1)!;
          final last = match.group(2)!;
          if (first.isEmpty) {
            final suffix = int.tryParse(last) ?? 0;
            valid = suffix > 0;
            start = (fileSize - suffix).clamp(0, fileSize);
          } else {
            start = int.tryParse(first) ?? fileSize;
            end = last.isEmpty ? end : (int.tryParse(last) ?? -1);
            end = end.clamp(-1, fileSize - 1);
          }
          valid = valid && start < fileSize && end >= start;
        }
        if (!valid) {
          await reader.dispose();
          return Response(416, headers: {'Content-Range': 'bytes */$fileSize'});
        }
      }
      final statusCode = range == null ? 200 : 206;
      final headers = <String, String>{
        'Accept-Ranges': 'bytes',
        'Content-Type': _guessMime(info.path),
        'Content-Length': '${end - start + 1}',
        if (range != null) 'Content-Range': 'bytes $start-$end/$fileSize',
      };

      if (req.method == 'HEAD') {
        await reader.dispose();
        return Response(statusCode, headers: headers);
      }

      // Pull one chunk at a time so HTTP backpressure bounds memory, and
      // cancellation during a seek closes the previous SMB reader.
      Stream<List<int>> body() async* {
        var offset = start;
        const chunkSize = 256 * 1024;
        try {
          while (offset <= end) {
            final remaining = end - offset + 1;
            final count = remaining.clamp(0, chunkSize);
            if (count == 0) break;
            final chunk = await reader.readChunk(offset, count);
            if (chunk == null || chunk.data.isEmpty) break;
            yield chunk.data;
            offset += chunk.size;
            if (chunk.isLastChunk) break;
          }
        } finally {
          await reader.dispose();
        }
      }

      return Response(statusCode, headers: headers, body: body());
    } catch (e) {
      return Response.internalServerError(body: 'SMB stream failed');
    }
  }

  _SmbUrlInfo? _parseSmbUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme.toLowerCase() != 'smb') return null;
      final host = uri.host;
      final userInfo = uri.userInfo;
      String? username;
      String? password;
      String? domain;
      if (userInfo.isNotEmpty) {
        final colon = userInfo.indexOf(':');
        username = Uri.decodeComponent(
          colon < 0 ? userInfo : userInfo.substring(0, colon),
        );
        if (colon >= 0) {
          password = Uri.decodeComponent(userInfo.substring(colon + 1));
        }
        final separator = username.indexOf(RegExp(r'[;\\]'));
        if (separator > 0) {
          domain = username.substring(0, separator);
          username = username.substring(separator + 1);
        }
      }
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty) return null;
      final share = segs.first;
      final path = '/${segs.skip(1).join('/')}';
      return _SmbUrlInfo(
        host: host,
        port: uri.hasPort ? uri.port : 445,
        domain: domain,
        share: share,
        path: path,
        username: username,
        password: password,
      );
    } catch (_) {
      return null;
    }
  }

  String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    return 'application/octet-stream';
  }

  String _buildClientPath(_SmbUrlInfo info) {
    var path = info.path.trim();
    if (path.isEmpty || path == '/') {
      return '';
    }
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    return path;
  }
}

class _SmbUrlInfo {
  final String host;
  final int port;
  final String? domain;
  final String share;
  final String path;
  final String? username;
  final String? password;
  _SmbUrlInfo({
    required this.host,
    required this.port,
    this.domain,
    required this.share,
    required this.path,
    this.username,
    this.password,
  });
}
