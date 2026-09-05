import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// Enum trạng thái progress (mirror OperationProgressStatus không import controller)
enum _ProgressStatus { running, success, error }

/// Màn hình progress chạy trong process con riêng biệt.
/// Kết nối tới IPC server của process cha để nhận cập nhật theo thời gian thực.
class ProgressWindowScreen extends StatefulWidget {
  final int ipcPort;
  final String initialTitle;
  final int initialTotal;
  final bool initialIndeterminate;

  const ProgressWindowScreen({
    super.key,
    required this.ipcPort,
    required this.initialTitle,
    required this.initialTotal,
    required this.initialIndeterminate,
  });

  @override
  State<ProgressWindowScreen> createState() => _ProgressWindowScreenState();
}

class _ProgressWindowScreenState extends State<ProgressWindowScreen>
    with WindowListener {
  Socket? _socket;
  StreamSubscription<String>? _lineSub;
  Timer? _reconnectTimer;
  Timer? _autoDismissTimer;
  bool _connecting = false;
  bool _dismissed = false;

  String _title = '';
  String? _detail;
  int _completed = 0;
  int _total = 0;
  bool _isIndeterminate = false;
  _ProgressStatus _status = _ProgressStatus.running;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _title = widget.initialTitle;
    _total = widget.initialTotal;
    _isIndeterminate = widget.initialIndeterminate;
    _connectToParent();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _reconnectTimer?.cancel();
    windowManager.removeListener(this);
    _discardSocket();
    super.dispose();
  }

  void _discardSocket() {
    _lineSub?.cancel();
    _lineSub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  Future<void> _connectToParent() async {
    if (_connecting || _dismissed) return;
    _connecting = true;
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        widget.ipcPort,
        timeout: const Duration(seconds: 5),
      );
      _socket = socket;
      _lineSub = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onDone: _onSocketDone,
            onError: (_) => _onSocketDone(),
            cancelOnError: true,
          );
    } catch (_) {
      // Retry sau 500ms nếu process cha chưa sẵn sàng
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    if (_dismissed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_dismissed) _connectToParent();
    });
  }

  void _onSocketDone() {
    _discardSocket();
    if (!_dismissed) {
      // Nếu connection bị mất → tự đóng sau 3s
      _autoDismissTimer ??= Timer(const Duration(seconds: 3), _closeWindow);
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic>? msg;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map) msg = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    if (msg == null) return;

    final type = msg['type'] as String?;

    if (type == 'dismiss') {
      _closeWindow();
      return;
    }

    if (type == 'update') {
      final statusStr = msg['status'] as String? ?? 'running';
      final newStatus = _parseStatus(statusStr);
      final wasFinished = _status != _ProgressStatus.running;
      // Capture non-nullable before setState to satisfy Dart flow analysis
      final newTitle = (msg['title'] as String?) ?? _title;
      final newDetail = msg['detail'] as String?;
      final newCompleted = (msg['completed'] as int?) ?? _completed;
      final newTotal = (msg['total'] as int?) ?? _total;
      final newIndeterminate =
          (msg['isIndeterminate'] as bool?) ?? _isIndeterminate;
      setState(() {
        _title = newTitle;
        _detail = newDetail;
        _completed = newCompleted;
        _total = newTotal;
        _isIndeterminate = newIndeterminate;
        _status = newStatus;
      });

      if (!wasFinished && newStatus == _ProgressStatus.success) {
        _autoDismissTimer?.cancel();
        _autoDismissTimer = Timer(const Duration(seconds: 2), _closeWindow);
      }
    }
  }

  _ProgressStatus _parseStatus(String s) {
    switch (s) {
      case 'success':
        return _ProgressStatus.success;
      case 'error':
        return _ProgressStatus.error;
      default:
        return _ProgressStatus.running;
    }
  }

  Future<void> _closeWindow() async {
    if (_dismissed) return;
    _dismissed = true;
    _autoDismissTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      await windowManager.close();
    } catch (_) {
      exit(0);
    }
  }

  bool get _isRunning => _status == _ProgressStatus.running;
  bool get _isFinished => _status != _ProgressStatus.running;

  double? get _progressFraction {
    if (_isIndeterminate) return null;
    if (_total <= 0) return null;
    return (_completed / _total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color accent;
    final IconData icon;
    switch (_status) {
      case _ProgressStatus.running:
        accent = theme.colorScheme.primary;
        icon = PhosphorIconsLight.arrowsClockwise;
        break;
      case _ProgressStatus.success:
        accent = const Color(0xFF4CAF50);
        icon = PhosphorIconsLight.checkCircle;
        break;
      case _ProgressStatus.error:
        accent = theme.colorScheme.error;
        icon = PhosphorIconsLight.warningCircle;
        break;
    }

    final label = _isRunning
        ? (_isIndeterminate ? 'Processing...' : '$_completed / $_total')
        : (_status == _ProgressStatus.success ? 'Done' : 'Error');

    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    final titleBarColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFE8E8E8);

    return Material(
      color: bgColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Custom title bar (draggable)
          GestureDetector(
            onPanStart: (_) => windowManager.startDragging(),
            child: Container(
              height: 32,
              color: titleBarColor,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  // Minimize
                  _TitleBarBtn(
                    icon: PhosphorIconsLight.minus,
                    tooltip: 'Minimize',
                    onTap: () => windowManager.minimize(),
                    isDark: isDark,
                  ),
                  // Close (only when finished)
                  _TitleBarBtn(
                    icon: PhosphorIconsLight.x,
                    tooltip: 'Close',
                    onTap: _isFinished ? _closeWindow : null,
                    isDark: isDark,
                    enabled: _isFinished,
                  ),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (_detail != null && _detail!.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              _detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: _progressFraction,
                    minHeight: 7,
                    backgroundColor: isDark ? Colors.white12 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBarBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isDark;
  final bool enabled;

  const _TitleBarBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.isDark,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? (isDark ? Colors.white70 : Colors.black54)
        : (isDark ? Colors.white24 : Colors.black26);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}
