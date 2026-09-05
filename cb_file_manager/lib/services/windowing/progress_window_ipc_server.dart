import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

/// TCP IPC server chạy trong process cha.
/// Bridge giữa [OperationProgressController] và progress window process con.
///
/// **Replay on connect**: khi client mới kết nối, server tự động gửi lại
/// [_lastUpdate] (nếu có) để tránh tình trạng client miss update vì chưa
/// connect kịp lúc parent đang gửi (process con cần ~1-2s để khởi động).
class ProgressWindowIpcServer {
  ServerSocket? _server;
  final List<Socket> _clients = [];
  int? _port;
  StreamSubscription<Socket>? _serverSub;

  /// Bộ nhớ đệm cho update cuối cùng — phát lại ngay khi client mới connect.
  Map<String, dynamic>? _lastUpdate;

  int? get port => _port;
  bool get isRunning => _server != null;

  /// Khởi động server, trả về port đang lắng nghe.
  Future<int?> start() async {
    if (_server != null) return _port;
    try {
      _server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0, // random port
        shared: false,
      );
      _port = _server!.port;
      _serverSub = _server!.listen(_onClient, onError: (_) {});
      AppLogger.info('[ProgressIPC] Server started on port $_port');
      return _port;
    } catch (e, st) {
      AppLogger.error(
        '[ProgressIPC] Failed to start server',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  void _onClient(Socket socket) {
    _clients.add(socket);

    // Replay last known state immediately so client không bị stuck ở 0%
    final lastMsg = _lastUpdate;
    if (lastMsg != null) {
      try {
        socket.write('${jsonEncode(lastMsg)}\n');
      } catch (_) {}
    }

    socket.done
        .then((_) {
          _clients.remove(socket);
          return null;
        })
        .catchError((Object _) {
          _clients.remove(socket);
          return null;
        });
  }

  /// Gửi update progress tới tất cả client đang kết nối.
  /// Cũng lưu vào [_lastUpdate] để replay cho client mới.
  void sendUpdate(OperationProgressEntry entry) {
    final msg = {
      'type': 'update',
      'title': entry.title,
      'detail': entry.detail,
      'completed': entry.completed,
      'total': entry.total,
      'status': entry.status.name,
      'isIndeterminate': entry.isIndeterminate,
    };
    _lastUpdate = msg; // Lưu để replay khi client connect
    _broadcast(msg);
  }

  /// Yêu cầu process con tự đóng.
  void sendDismiss() {
    _lastUpdate = null;
    _broadcast({'type': 'dismiss'});
  }

  void _broadcast(Map<String, dynamic> message) {
    if (_clients.isEmpty) return;
    final line = '${jsonEncode(message)}\n';
    final deadClients = <Socket>[];
    for (final client in _clients) {
      try {
        client.write(line);
      } catch (_) {
        deadClients.add(client);
      }
    }
    for (final c in deadClients) {
      _clients.remove(c);
    }
  }

  Future<void> stop() async {
    _broadcast({'type': 'dismiss'});
    _lastUpdate = null;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (final client in List<Socket>.from(_clients)) {
      try {
        await client.close();
      } catch (_) {}
    }
    _clients.clear();
    await _serverSub?.cancel();
    _serverSub = null;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    _port = null;
    AppLogger.info('[ProgressIPC] Server stopped');
  }
}
