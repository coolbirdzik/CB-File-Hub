import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:async';
import '../../../services/network_browsing/optimized_smb_service.dart';

/// Widget to display streaming performance metrics
class StreamingPerformanceWidget extends StatefulWidget {
  final OptimizedSMBService smbService;
  final String? currentFilePath;
  final bool isStreaming;

  const StreamingPerformanceWidget({
    Key? key,
    required this.smbService,
    this.currentFilePath,
    this.isStreaming = false,
  }) : super(key: key);

  @override
  State<StreamingPerformanceWidget> createState() =>
      _StreamingPerformanceWidgetState();
}

class _StreamingPerformanceWidgetState
    extends State<StreamingPerformanceWidget> {
  Timer? _updateTimer;
  Map<String, dynamic> _performanceStats = {};
  Map<String, dynamic>? _benchmarkResults;
  bool _isBenchmarking = false;

  @override
  void initState() {
    super.initState();
    _startPeriodicUpdate();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicUpdate() {
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _updatePerformanceStats();
      }
    });
  }

  Future<void> _updatePerformanceStats() async {
    try {
      final stats = widget.smbService.getPerformanceStats();
      setState(() {
        _performanceStats = stats;
      });
    } catch (e) {
      debugPrint('Error updating performance stats: $e');
    }
  }

  Future<void> _runBenchmark() async {
    if (widget.currentFilePath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file selected for benchmarking')),
        );
      }
      return;
    }

    setState(() {
      _isBenchmarking = true;
    });

    try {
      final results =
          await widget.smbService.benchmarkStreaming(widget.currentFilePath!);
      if (mounted) {
        setState(() {
          _benchmarkResults = results;
          _isBenchmarking = false;
        });

        if (results['error'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Benchmark error: ${results['error']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBenchmarking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Benchmark failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Streaming Performance',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    if (widget.currentFilePath != null)
                      ElevatedButton.icon(
                        onPressed: _isBenchmarking ? null : _runBenchmark,
                        icon: _isBenchmarking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(PhosphorIconsLight.speedometer,
                                size: 16),
                        label:
                            Text(_isBenchmarking ? 'Testing...' : 'Benchmark'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      widget.isStreaming
                          ? PhosphorIconsLight.playCircle
                          : PhosphorIconsLight.pauseCircle,
                      color: widget.isStreaming ? Colors.green : Colors.grey,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Connection Status
            _buildStatusSection(),
            const SizedBox(height: 12),

            // Performance Metrics
            _buildPerformanceSection(),
            const SizedBox(height: 12),

            // Benchmark Results
            if (_benchmarkResults != null) _buildBenchmarkSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    final isConnected = _performanceStats['isConnected'] ?? false;
    final streamingMethod = _performanceStats['streamingMethod'] ?? 'Unknown';
    final optimizationLevel =
        _performanceStats['optimizationLevel'] ?? 'Unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Text(isConnected ? 'Connected' : 'Disconnected'),
          ],
        ),
        const SizedBox(height: 4),
        Text('Method: $streamingMethod'),
        Text('Optimization: $optimizationLevel'),
      ],
    );
  }

  Widget _buildPerformanceSection() {
    final streaming = _performanceStats['streaming'] as Map<String, dynamic>?;
    final prefetchController =
        _performanceStats['prefetchController'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Performance Metrics',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        if (streaming != null) ...[
          _buildMetricRow('Chunk Size', streaming['chunkSize'] ?? 'Unknown'),
          _buildMetricRow('Buffer Size', streaming['bufferSize'] ?? 'Unknown'),
          _buildMetricRow(
              'Prefetch Size', streaming['prefetchSize'] ?? 'Unknown'),
          _buildMetricRow(
              'Max Connections', '${streaming['maxConnections'] ?? 'Unknown'}'),
          _buildMetricRow(
              'Estimated Speed', streaming['estimatedSpeed'] ?? 'Unknown'),
        ],
        if (prefetchController != null) ...[
          const SizedBox(height: 8),
          _buildMetricRow('Cache Hit Rate',
              '${prefetchController['cacheHitRate'] ?? '0.0'}%'),
          _buildMetricRow(
              'Buffer Usage', '${prefetchController['bufferSize'] ?? 0} bytes'),
        ],
      ],
    );
  }

  Widget _buildBenchmarkSection() {
    final results = _benchmarkResults!;
    final error = results['error'];

    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Benchmark Results',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Text(
              'Error: $error',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      );
    }

    final speedMBps = results['speedMBps'] ?? '0.00';
    final speedKBps = results['speedKBps'] ?? '0';
    final totalBytes = results['totalBytes'] ?? 0;
    final chunkCount = results['chunkCount'] ?? 0;
    final testDuration = results['testDuration'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Benchmark Results',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Speed:'),
                  Text(
                    '$speedMBps MB/s ($speedKBps KB/s)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Data Transferred:'),
                  Text('${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB'),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Chunks:'),
                  Text('$chunkCount'),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Test Duration:'),
                  Text('${testDuration}ms'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
