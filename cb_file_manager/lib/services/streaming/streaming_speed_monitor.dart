import 'dart:async';
import 'package:flutter/foundation.dart';

/// Service để theo dõi tốc độ stream file SMB
class StreamingSpeedMonitor {
  static final StreamingSpeedMonitor _instance =
      StreamingSpeedMonitor._internal();
  factory StreamingSpeedMonitor() => _instance;
  StreamingSpeedMonitor._internal();

  // Stream controllers để broadcast thông tin tốc độ
  final StreamController<StreamingSpeedInfo> _speedController =
      StreamController<StreamingSpeedInfo>.broadcast();

  // Timer để cập nhật tốc độ định kỳ
  Timer? _updateTimer;

  // Thông tin hiện tại
  int _totalBytesReceived = 0;
  int _lastBytesReceived = 0;
  DateTime _startTime = DateTime.now();
  DateTime _lastUpdateTime = DateTime.now();

  // Cấu hình
  static const Duration _updateInterval = Duration(
    milliseconds: 500,
  ); // Cập nhật mỗi 500ms

  /// Stream để lắng nghe thông tin tốc độ
  Stream<StreamingSpeedInfo> get speedStream => _speedController.stream;

  /// Bắt đầu theo dõi tốc độ stream
  void startMonitoring() {
    _reset();
    _updateTimer = Timer.periodic(_updateInterval, (_) => _updateSpeed());
    debugPrint('StreamingSpeedMonitor: Bắt đầu theo dõi tốc độ stream');
  }

  /// Dừng theo dõi tốc độ stream
  void stopMonitoring() {
    _updateTimer?.cancel();
    _updateTimer = null;
    debugPrint('StreamingSpeedMonitor: Dừng theo dõi tốc độ stream');
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _speedController.close();
    debugPrint('StreamingSpeedMonitor: Disposed resources');
  }

  /// Cập nhật số bytes đã nhận
  void updateBytesReceived(int bytesReceived) {
    _totalBytesReceived = bytesReceived;
  }

  /// Lấy số bytes đã nhận hiện tại
  int get totalBytesReceived => _totalBytesReceived;

  /// Reset thông tin theo dõi
  void _reset() {
    _totalBytesReceived = 0;
    _lastBytesReceived = 0;
    _startTime = DateTime.now();
    _lastUpdateTime = DateTime.now();
  }

  /// Cập nhật và broadcast thông tin tốc độ
  void _updateSpeed() {
    final now = DateTime.now();
    final timeDiff = now.difference(_lastUpdateTime).inMilliseconds;

    if (timeDiff > 0) {
      final bytesDiff = _totalBytesReceived - _lastBytesReceived;
      final speedBytesPerSecond = (bytesDiff * 1000) / timeDiff;

      final speedInfo = StreamingSpeedInfo(
        currentSpeed: speedBytesPerSecond,
        averageSpeed: _calculateAverageSpeed(),
        totalBytes: _totalBytesReceived,
        elapsedTime: now.difference(_startTime),
        formattedCurrentSpeed: _formatSpeed(speedBytesPerSecond),
        formattedAverageSpeed: _formatSpeed(_calculateAverageSpeed()),
        formattedTotalBytes: _formatBytes(_totalBytesReceived),
      );

      _speedController.add(speedInfo);

      _lastBytesReceived = _totalBytesReceived;
      _lastUpdateTime = now;
    }
  }

  /// Tính tốc độ trung bình
  double _calculateAverageSpeed() {
    final elapsedMs = DateTime.now().difference(_startTime).inMilliseconds;
    if (elapsedMs > 0) {
      return (_totalBytesReceived * 1000) / elapsedMs;
    }
    return 0.0;
  }

  /// Format tốc độ thành string dễ đọc
  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(1)} B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    } else if (bytesPerSecond < 1024 * 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else {
      return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
    }
  }

  /// Format bytes thành string dễ đọc
  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}

/// Model chứa thông tin tốc độ stream
class StreamingSpeedInfo {
  final double currentSpeed; // bytes per second
  final double averageSpeed; // bytes per second
  final int totalBytes;
  final Duration elapsedTime;
  final String formattedCurrentSpeed;
  final String formattedAverageSpeed;
  final String formattedTotalBytes;

  StreamingSpeedInfo({
    required this.currentSpeed,
    required this.averageSpeed,
    required this.totalBytes,
    required this.elapsedTime,
    required this.formattedCurrentSpeed,
    required this.formattedAverageSpeed,
    required this.formattedTotalBytes,
  });

  @override
  String toString() {
    return 'StreamingSpeedInfo(current: $formattedCurrentSpeed, avg: $formattedAverageSpeed, total: $formattedTotalBytes)';
  }
}

/// Wrapper cho Stream để theo dõi tốc độ
class SpeedMonitoredStream extends Stream<List<int>> {
  final Stream<List<int>> _sourceStream;
  final StreamingSpeedMonitor _monitor;

  SpeedMonitoredStream(this._sourceStream, this._monitor);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    int totalBytes = 0;

    return _sourceStream.listen(
      (data) {
        totalBytes += data.length;
        _monitor.updateBytesReceived(totalBytes);
        onData?.call(data);
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
