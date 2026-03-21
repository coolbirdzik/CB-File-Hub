import 'package:flutter/material.dart';
import 'dart:async';

/// Modern widget to display buffer information with beautiful UI
class BufferInfoWidget extends StatefulWidget {
  final Stream<List<int>>? stream;
  final String label;

  const BufferInfoWidget({
    Key? key,
    this.stream,
    this.label = 'Buffer Info',
  }) : super(key: key);

  @override
  State<BufferInfoWidget> createState() => _BufferInfoWidgetState();
}

class _BufferInfoWidgetState extends State<BufferInfoWidget>
    with TickerProviderStateMixin {
  int _totalBytes = 0;
  int _chunkCount = 0;
  bool _isActive = false;
  Timer? _updateTimer;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  final List<int> _recentChunkSizes = [];
  static const int _maxRecentChunks = 5;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
    );
    _startMonitoring();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  void _startMonitoring() {
    if (widget.stream != null) {
      _isActive = true;
      widget.stream!.listen(
        (data) {
          setState(() {
            _totalBytes += data.length;
            _chunkCount++;
            _recentChunkSizes.add(data.length);
            if (_recentChunkSizes.length > _maxRecentChunks) {
              _recentChunkSizes.removeAt(0);
            }
          });
          _progressController.forward(from: 0.0);
        },
        onDone: () {
          setState(() {
            _isActive = false;
          });
        },
        onError: (error) {
          setState(() {
            _isActive = false;
          });
          debugPrint('BufferInfoWidget: Stream error: $error');
        },
      );
    }

    // Update UI every second
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
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

  double _getAverageChunkSize() {
    if (_recentChunkSizes.isEmpty) return 0.0;
    return _recentChunkSizes.reduce((a, b) => a + b) / _recentChunkSizes.length;
  }

  Color _getBufferColor() {
    if (_totalBytes >= 10 * 1024 * 1024) return Colors.green; // 10MB+
    if (_totalBytes >= 5 * 1024 * 1024) return Colors.orange; // 5MB+
    if (_totalBytes >= 1 * 1024 * 1024) return Colors.yellow; // 1MB+
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
              ? Colors.purple.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isActive
                            ? 1.0 + (_progressAnimation.value * 0.2)
                            : 1.0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _getBufferColor(),
                            boxShadow: _isActive
                                ? [
                                    BoxShadow(
                                      color: _getBufferColor()
                                          .withValues(alpha: 0.5),
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
                      ? Colors.purple.withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: Text(
                  _isActive ? 'BUFFERING' : 'READY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _isActive ? Colors.purple : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Buffer size
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Buffer:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              Text(
                _formatBytes(_totalBytes),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _getBufferColor(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Chunk count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Chunks:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              Text(
                '$_chunkCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Average chunk size
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Avg Chunk:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              Text(
                _formatBytes(_getAverageChunkSize().round()),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _isActive ? 1.0 : 0.0,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(_getBufferColor()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
