import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../services/network_browsing/smb_chunk_reader.dart';
import 'package:mobile_smb_native/mobile_smb_native.dart';

/// Lightweight HTTP proxy that exposes an SMB file as an HTTP stream with Range support.
/// Designed specifically to feed ExoPlayer during Android PiP mode.
class SmbHttpProxyServer {
  static SmbHttpProxyServer? _instance;
  static SmbHttpProxyServer get instance =>
      _instance ??= SmbHttpProxyServer._();

  SmbHttpProxyServer._();

  HttpServer? _server;
  int? _port;

  // For simple per-request handling we do not cache connections long-term.
  // ExoPlayer will reconnect with Range requests as needed.

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    final handler = const Pipeline().addHandler(_handle);
    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    _server!.autoCompress = false;
    _port = _server!.port;
  }

  /// Returns a URL that ExoPlayer can consume for the given [smbUrl].
  Future<Uri> urlFor(String smbUrl) async {
    await _ensureStarted();
    final encoded = base64Url.encode(utf8.encode(smbUrl));
    return Uri.parse('http://127.0.0.1:$_port/stream?u=$encoded');
  }

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
      final smbUrl = utf8.decode(base64Url.decode(u));

      // Parse Range header
      final rangeHeader = req.headers['range'] ?? req.headers['Range'];
      int start = 0;
      int? end;
      if (rangeHeader != null &&
          rangeHeader.toLowerCase().startsWith('bytes=')) {
        final spec = rangeHeader.substring(6);
        final parts = spec.split('-');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          start = int.tryParse(parts[0]) ?? 0;
        }
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]);
        }
      }

      final reader = SmbChunkReader();
      final info = _parseSmbUrl(smbUrl);
      if (info == null) {
        return Response(400, body: 'Invalid SMB URL');
      }
      final filePath = _buildClientPath(info);

      final ok = await reader.initialize(
        SmbConnectionConfig(
          host: info.host,
          port: 445,
          username: info.username ?? '',
          password: info.password ?? '',
          shareName: info.share,
          timeoutMs: 60000,
        ),
      );
      if (!ok) {
        return Response(502, body: 'Failed to connect SMB');
      }

      // SmbChunkReader expects a path relative to the SMB base share.
      final fileOk = await reader.setFile(filePath);
      if (!fileOk) {
        return Response(404, body: 'File not found');
      }

      final fileSize = reader.fileSize;
      final total = fileSize ?? -1;
      final clampedStart = start.clamp(0, (total > 0 ? total - 1 : start));
      final controller = StreamController<List<int>>();

      // Build headers
      final headers = <String, String>{
        'Accept-Ranges': 'bytes',
        'Connection': 'keep-alive',
        'Content-Type': _guessMime(info.path),
      };

      int statusCode = 200;
      if (fileSize != null) {
        final effectiveEnd = end == null
            ? (fileSize - 1)
            : end.clamp(0, fileSize - 1);
        final length = (effectiveEnd - clampedStart + 1).clamp(0, fileSize);
        headers['Content-Length'] = '$length';
        headers['Content-Range'] =
            'bytes $clampedStart-$effectiveEnd/$fileSize';
        statusCode =
            (clampedStart == 0 && (end == null || effectiveEnd == fileSize - 1))
            ? 200
            : 206;
      }

      // Start pushing data
      unawaited(() async {
        int offset = clampedStart;
        const chunk = 256 * 1024; // 256KB per read
        try {
          while (true) {
            if (end != null && offset > end) break;
            final size = end != null ? (end - offset + 1) : chunk;
            final readSize = size > chunk ? chunk : size;
            if (readSize <= 0) break;
            final c = await reader.readChunk(offset, readSize);
            if (c == null || c.data.isEmpty) break;
            controller.add(c.data);
            offset += c.size;
            if (c.isLastChunk) break;
          }
        } catch (_) {
          // client cancelled or read error
        } finally {
          try {
            await reader.dispose();
          } catch (_) {}
          await controller.close();
        }
      }());

      return Response(statusCode, headers: headers, body: controller.stream);
    } catch (e) {
      return Response(500, body: 'Proxy error: $e');
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
      if (userInfo.isNotEmpty) {
        final parts = userInfo.split(':');
        if (parts.isNotEmpty) username = Uri.decodeComponent(parts[0]);
        if (parts.length > 1) password = Uri.decodeComponent(parts[1]);
      }
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty) return null;
      final share = Uri.decodeComponent(segs.first);
      final path = '/${segs.skip(1).map(Uri.decodeComponent).join('/')}';
      return _SmbUrlInfo(
        host: host,
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
  final String share;
  final String path;
  final String? username;
  final String? password;
  _SmbUrlInfo({
    required this.host,
    required this.share,
    required this.path,
    this.username,
    this.password,
  });
}
