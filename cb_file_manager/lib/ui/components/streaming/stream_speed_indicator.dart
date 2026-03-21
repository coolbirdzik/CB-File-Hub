import 'package:flutter/material.dart';
import 'dart:async';

/// Modern real-time stream speed indicator with beautiful UI
class StreamSpeedIndicator extends StatefulWidget {
  final Stream<List<int>>? stream;
  final String label;

  const StreamSpeedIndicator({
    Key? key,
    this.stream,
    this.label = 'Stream Speed',
  }) : super(key: key);

  @override
  State<StreamSpeedIndicator> createState() => _StreamSpeedIndicatorState();
}

class _StreamSpeedIndicatorState extends State<StreamSpeedIndicator>
    with TickerProviderStateMixin {
  Timer? _updateTimer;
  double _currentSpeed = 0.0; // MB/s
  int _totalBytes = 0;
  int _lastBytes = 0;
  DateTime? _lastUpdate;
  bool _isActive = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final List<double> _speedHistory = [];
  static const int _maxHistoryLength = 10;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startMonitoring();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startMonitoring() {
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        _updateSpeed();
      }
    });

    if (widget.stream != null) {
      _isActive = true;
      _pulseController.repeat(reverse: true);

      widget.stream!.listen(
        (data) {
          _totalBytes += data.length;
        },
        onDone: () {
          _isActive = false;
          _pulseController.stop();
        },
        onError: (error) {
          _isActive = false;
          _pulseController.stop();
          debugPrint('Stream error: $error');
        },
      );
    }
  }

  void _updateSpeed() {
    final now = DateTime.now();
    if (_lastUpdate != null) {
      final duration = now.difference(_lastUpdate!).inMilliseconds / 1000.0;
      if (duration > 0) {
        final bytesDiff = _totalBytes - _lastBytes;
        final speedMBps = (bytesDiff / 1024 / 1024) / duration;

        setState(() {
          _currentSpeed = speedMBps;
          _speedHistory.add(speedMBps);
          if (_speedHistory.length > _maxHistoryLength) {
            _speedHistory.removeAt(0);
          }
        });
      }
    }

    _lastBytes = _totalBytes;
    _lastUpdate = now;
  }

  String _formatSpeed(double speedMBps) {
    if (speedMBps >= 1.0) {
      return '${speedMBps.toStringAsFixed(1)} MB/s';
    } else {
      final speedKBps = speedMBps * 1024;
      return '${speedKBps.toStringAsFixed(0)} KB/s';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    } else {
      return '$bytes B';
    }
  }

  Color _getSpeedColor(double speed) {
    if (speed >= 5.0) return Colors.green;
    if (speed >= 2.0) return Colors.orange;
    if (speed >= 0.5) return Colors.yellow;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isActive
              ? Colors.blue.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with status indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isActive ? _pulseAnimation.value : 1.0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isActive ? Colors.green : Colors.grey,
                            boxShadow: _isActive
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.green.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isActive
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: Text(
                  _isActive ? 'LIVE' : 'IDLE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _isActive ? Colors.green : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Speed display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Speed:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              Text(
                _formatSpeed(_currentSpeed),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _getSpeedColor(_currentSpeed),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Total bytes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              Text(
                _formatBytes(_totalBytes),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Speed graph
          if (_speedHistory.isNotEmpty)
            Container(
              height: 30,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16.0),
                child: CustomPaint(
                  size: const Size(double.infinity, 30),
                  painter: SpeedGraphPainter(_speedHistory),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SpeedGraphPainter extends CustomPainter {
  final List<double> speedHistory;

  SpeedGraphPainter(this.speedHistory);

  @override
  void paint(Canvas canvas, Size size) {
    if (speedHistory.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.blue.withValues(alpha: 0.3),
          Colors.blue.withValues(alpha: 0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final maxSpeed = speedHistory.reduce((a, b) => a > b ? a : b);
    const minSpeed = 0.0;
    final range = maxSpeed - minSpeed;

    fillPath.moveTo(0, size.height);

    for (int i = 0; i < speedHistory.length; i++) {
      final x = (i / (speedHistory.length - 1)) * size.width;
      final normalizedSpeed =
          range > 0 ? (speedHistory[i] - minSpeed) / range : 0.5;
      final y = size.height - (normalizedSpeed * size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
